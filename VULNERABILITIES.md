# Vulnerabilities

Attack surface and known vulnerability classes present in the ThruntOps lab.

---

## Intentional Vulnerabilities

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

## By Technology

| Technology | Vectors |
|---|---|
| Active Directory (dual domain) | Kerberoasting, AS-REP roasting, ACL abuse, lateral movement, trust abuse |
| ADCS | ESC1–ESC16 certificate template misconfigurations |
| IIS + ASP.NET + MSSQL | Web application attacks, SQL injection, authentication bypass |
| GitLab CE | Source code exposure, CI/CD pipeline abuse, secret leakage |
| Elastic SIEM | Detection engineering, alert tuning, log analysis |

## Notes

- Passwords are randomised but `primary_user01` / `secondary_user01` intentionally share their domain admin password
- No password policy enforced on the domain
- ADCS is configured with intentionally misconfigured templates to enable ESC attack paths
- GitLab CI/CD pipeline deploys directly to IIS on push — pipeline poisoning surface
- Domain trust between `thruntops.domain` and `secondary.thruntops.domain` enables cross-domain lateral movement
