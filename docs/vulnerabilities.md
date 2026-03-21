---
title: Vulnerabilities
layout: default
nav_order: 6
---

# Vulnerabilities
{: .no_toc }

Attack surface and intentional vulnerability classes present in the ThruntOps lab.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Active Directory

### Credential Reuse — Domain User to Domain Admin

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user01` (thruntops.domain), `secondary_user01` (secondary.thruntops.domain) |
| **Condition** | These accounts share the exact password of their respective `domainadmin` |
| **Primitive** | Low-privilege domain user credential → Domain Admin via password reuse |
| **MITRE ATT&CK** | [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/) |
| **Related techniques** | [T1110.001 — Brute Force: Password Guessing](https://attack.mitre.org/techniques/T1110/001/), [T1110.004 — Credential Stuffing](https://attack.mitre.org/techniques/T1110/004/) |

**Attack path:**

```
Compromise primary_user01 (low-priv)
  → Recover plaintext / NTLM hash
  → Reuse credential against domainadmin
  → Full domain compromise (T1078.002)
```

**Detection opportunities:**

- Logon event with `domainadmin` originating from a workstation (Event ID 4624, logon type 3/10)
- Same NTLM hash seen across accounts of different privilege levels (requires credential dumping detection — T1003)
- Lateral movement from workstation to DC using admin credentials (Event ID 4769 / Kerberos TGS request for privileged service)

---

### RDP Access to Domain Controllers — Low-Privilege User

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user02` (thruntops.domain → DC01-2022), `secondary_user02` (secondary.thruntops.domain → DC01-SEC) |
| **Condition** | Low-privilege domain users are members of the `Remote Desktop Users` group on their respective domain controller |
| **Primitive** | Interactive session on a DC as a non-admin — enables local enumeration, memory access attempts, and token abuse |
| **MITRE ATT&CK** | [T1021.001 — Remote Services: Remote Desktop Protocol](https://attack.mitre.org/techniques/T1021/001/) |
| **Related techniques** | [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/), [T1003.001 — OS Credential Dumping: LSASS Memory](https://attack.mitre.org/techniques/T1003/001/) |

**Attack path:**

```
Compromise primary_user02 (low-priv)
  → RDP to DC01-2022 (T1021.001)
  → Interactive session on DC — LSASS in scope (T1003.001)
  → Dump credentials / escalate to Domain Admin
```

**Detection opportunities:**

- RDP logon to DC from non-admin account (Event ID 4624, logon type 10, source non-admin)
- Interactive session on DC from workstation IP (Event ID 4778 / 4779 — session connect/disconnect)
- Process creation under non-admin account on DC (Sysmon Event ID 1)

---

### LAPS Password Read — Low-Privilege Domain User

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user03` (thruntops.domain), `secondary_user03` (secondary.thruntops.domain) |
| **Condition** | `Set-LapsADReadPasswordPermission` granted on the domain root — these users can read `msLAPS-Password` on any workstation in their domain |
| **Primitive** | Low-privilege domain user reads LAPS-managed local admin password → local admin on any workstation |
| **MITRE ATT&CK** | [T1555 — Credentials from Password Stores](https://attack.mitre.org/techniques/T1555/) |
| **Related techniques** | [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/), [T1021.001 — Remote Services: RDP](https://attack.mitre.org/techniques/T1021/001/) |

**Attack path:**

```
Compromise primary_user03 (low-priv)
  → Query LAPS: Get-LapsADPassword -Identity WIN11-22H2-1 (T1555)
  → Recover localuser password for target workstation
  → RDP / lateral movement as local admin (T1021.001)
```

**Detection opportunities:**

- Read access to `msLAPS-Password` attribute by non-admin account (AD audit — Event ID 4662, object access on computer object)
- `Get-LapsADPassword` or LDAP query for `msLAPS-Password` from non-privileged context

---

### RDP Access to ADCS — Low-Privilege Domain User

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user04` (thruntops.domain), `secondary_user04` (secondary.thruntops.domain) |
| **Condition** | Low-privilege domain users from both domains are members of `Remote Desktop Users` on the Certificate Authority (ADCS VM) |
| **Primitive** | Interactive session on the CA — enables certificate template enumeration, ESC abuse, and potential CA private key access |
| **MITRE ATT&CK** | [T1021.001 — Remote Services: Remote Desktop Protocol](https://attack.mitre.org/techniques/T1021/001/) |
| **Related techniques** | [T1649 — Steal or Forge Authentication Certificates](https://attack.mitre.org/techniques/T1649/), [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/) |

**Attack path:**

```
Compromise primary_user04 (low-priv)
  → RDP to ADCS (T1021.001)
  → Enumerate certificate templates — identify ESC misconfigurations
  → Request malicious certificate (T1649)
  → Authenticate as Domain Admin using certificate
```

**Detection opportunities:**

- RDP logon to ADCS from non-admin account (Event ID 4624, logon type 10)
- Certificate enrollment from unexpected account (Event ID 4886 / 4887 — certificate issued)
- Certify / Certipy tooling signatures in process creation logs (Sysmon Event ID 1)

---

## Linux Privilege Escalation

Entry points: `secondary_user06` → gitlab (10.2.50.15), `primary_user06` → ops (10.2.50.2).

### SUID R — Shell Escape to Root (gitlab)

| Field | Detail |
|---|---|
| **Host** | gitlab (10.2.50.15) |
| **Entry point** | `secondary_user06` (SSH, no sudo) |
| **Condition** | `/usr/bin/R` has SUID root bit set |
| **Primitive** | R spawns a shell inheriting the SUID effective UID → root shell |
| **GTFOBins** | [R — SUID](https://gtfobins.github.io/gtfobins/r/#suid) |
| **MITRE ATT&CK** | [T1548.001 — Abuse Elevation Control Mechanism: Setuid and Setgid](https://attack.mitre.org/techniques/T1548/001/) |

**Exploit:**

```bash
R --no-save -e 'system("/bin/sh")'
```

**Attack path:**

```
SSH as secondary_user06 (no sudo)
  → Discover SUID binaries: find / -perm -4000 -type f 2>/dev/null
  → Identify /usr/bin/R with SUID root
  → R --no-save -e 'system("/bin/sh")' → root shell (T1548.001)
```

**Detection opportunities:**

- `R` process spawned by a non-root user with effective UID 0 (Sysmon/auditd — process creation with euid=0)
- `/bin/sh` child of `R` process owned by non-root user
- SUID binary execution outside expected administrative context

---

## By Technology

| Technology | Vectors |
|---|---|
| Active Directory (dual domain) | Credential reuse, Kerberoasting, AS-REP roasting, ACL abuse, lateral movement, trust abuse |
| ADCS | ESC1–ESC16 certificate template misconfigurations, RDP access to CA |
| IIS + ASP.NET + MSSQL | Web application attacks, SQL injection, authentication bypass |
| GitLab CE | Source code exposure, CI/CD pipeline abuse, secret leakage, SUID privesc |
| Linux (gitlab, ops) | SUID binary abuse |
| Elastic SIEM | Detection engineering, alert tuning, log analysis |

## Notes

- Passwords are randomised but `primary_user01` / `secondary_user01` intentionally share their domain admin password
- No password policy enforced on the domain
- ADCS is configured with intentionally misconfigured templates to enable ESC attack paths
- GitLab CI/CD pipeline deploys directly to IIS on push — pipeline poisoning surface
- Domain trust between `thruntops.domain` and `secondary.thruntops.domain` enables cross-domain lateral movement
- Linux privesc scenarios are only present on profiles that include the relevant VM (gitlab: elastic + splunk; ops: all profiles)
