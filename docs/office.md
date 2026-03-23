---
title: Office Abuse
layout: default
nav_order: 10
---

# Office Abuse
{: .no_toc }

SMB-based document delivery and Office execution abuse, using existing lab infrastructure without introducing new VMs.

<details open markdown="block">
  <summary>Contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## Infrastructure

| Role | VM | IP |
|---|---|---|
| Office clients | `WIN11-22H2-1` (thruntops.domain) | 10.2.50.21 |
| Office clients | `WIN11-22H2-2` (secondary.thruntops.domain) | 10.2.50.22 |
| SMB file server | `WEB` | 10.2.50.14 |

Microsoft Office 2019 (64-bit) is pre-installed on both workstations.

---

## SMB Shares

Three shares on `WEB` (`\\10.2.50.14\<share>`):

| Share | Description | Anonymous read |
|---|---|---|
| `thruntops_docs` | Internal documents — thruntops.domain | Yes |
| `secondary_docs` | Internal documents — secondary.thruntops.domain | Yes |
| `xdomain_docs` | Cross-domain collaboration | Yes |

Folder structure in each share:

```
HR/
IT/
Finance/
Templates/
```

(`xdomain_docs` uses `Projects/`, `Reports/`, `Shared-Templates/`)

---

## Access Control

### AD Groups (both domains)

| Group | Rights | Members |
|---|---|---|
| `FileShare_Users` | Read on own domain share | domainuser, basicdomainuser, user01–05 |
| `FileShare_Writers` | Modify on all shares | `primary_user08` / `secondary_user08` |
| `XDomain_Docs_RO` | Read on `xdomain_docs` | domainuser, basicdomainuser, user02–05 |

### Cross-domain

`thruntops\FileShare_Users` has Read on `secondary_docs` — simulates inter-domain collaboration and enables cross-domain lure access.

`primary_user08` and `secondary_user08` have Modify on all three shares — the intended lure planters.

---

## Null Session (Anonymous Enumeration)

WEB is configured to allow unauthenticated access for enumeration and RID brute-forcing:

| Registry key | Value | Effect |
|---|---|---|
| `LanmanServer\Parameters\RestrictNullSessAccess` | `0` | Allows null session on IPC$ |
| `LanmanServer\Parameters\NullSessionShares` | (the three shares) | Shares accessible via null session |
| `Lsa\EveryoneIncludesAnonymous` | `1` | Anonymous Logon included in Everyone |

### Enumeration from Kali

```bash
# RID brute-force via null session
lookupsid.py "ANONYMOUS@10.2.50.14" -no-pass

# Share listing
smbclient -L //10.2.50.14 -U "" -N

# Share access
smbclient //10.2.50.14/xdomain_docs -U "" -N
```

{: .note }
DCs (10.2.50.11, 10.2.50.12) also allow null sessions and are the preferred target for RID brute-forcing since they serve the full domain user list via LSARPC.

---

## Credential Lure

`xdomain_docs\IT\new_accounts_Q1_2026.txt` — readable without authentication.

Contains plaintext credentials for:

| User | Domain | Password |
|---|---|---|
| `primary_user09` | thruntops.domain | `bpR8#8t"` |
| `secondary_user09` | secondary.thruntops.domain | `Ug1$m%b4` |

### Exploitation chain

```
null session → IPC$ → RID brute → user enumeration
null session → \\WEB\xdomain_docs\IT\new_accounts_Q1_2026.txt → credentials
  → authenticate as primary_user09 or secondary_user09
  → foothold in Domain Users
  → chain into AD, LAPS, WEB, MSSQL, GitLab
```

---

## Scenarios

### VBA macro from SMB share

```
prior access → copy .docm/.xlsm to share
  → victim browses share → opens document
  → macro executes powershell / mshta / wscript
  → user-context shell on WIN11
```

### Document with remote SMB reference (NTLM capture)

```
document on share with embedded UNC path (\\<attacker>\x)
  → victim opens document
  → Office resolves UNC → NLA / NTLM handshake to attacker listener
  → NTLMv2 hash captured → crack or relay
```

See also: [Guacamole → NTLMv2](wazuh.md#guacamole-pre-loaded-connections) for an alternative capture path without Office.

### Macro + LOLBin

```
macro → certutil / mshta / wscript / cscript
  → downloads or executes secondary payload
  → strong endpoint telemetry in SIEM
```

---

## Expected Telemetry

### Windows endpoints

- `WINWORD.EXE` / `EXCEL.EXE` spawning: `powershell.exe`, `cmd.exe`, `mshta.exe`, `wscript.exe`, `cscript.exe`, `certutil.exe`
- Writes to `%TEMP%`, `Downloads`, Office recovery paths
- Outbound SMB or HTTP connections after document open

### WEB (SMB server)

- Share access events: creation, read, rename in `thruntops_docs`, `secondary_docs`, `xdomain_docs`
- Audit trail: which user planted the lure vs. which user opened it
- Anonymous enumeration attempts on IPC$

---

## Ansible Role

Deployed by `ludus_smb_shares` on `admin-web` in all three range profiles.

Key variables:

| Variable | Description |
|---|---|
| `ludus_smb_primary_admin_password` | thruntops domainadmin password |
| `ludus_smb_secondary_admin_password` | secondary domainadmin password |
| `ludus_smb_user09_primary_password` | Lure credential — primary_user09 |
| `ludus_smb_user09_secondary_password` | Lure credential — secondary_user09 |
