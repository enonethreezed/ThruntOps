# GitLab — TTP Planning Notes

Attack surface and planned scenarios for the GitLab CE instance at `10.2.50.15`.

---

## Current State

| Item | Detail |
|---|---|
| Host | gitlab (10.2.50.15) — Ubuntu 24.04 |
| Software | GitLab CE, LDAP auth against `thruntops.domain` |
| Domain user with access | `webdev` (thruntops.domain) — Developers group, maintainer on all repos |
| CI/CD target | `C:\inetpub\wwwroot` on WEB (10.2.50.14) via pipeline |
| **Gap** | No GitLab Runner configured — pipelines do not execute |
| **Gap** | No repository with actual application code exists yet |

---

## Infrastructure Requirement: GitLab Runner

All CI/CD-based TTPs require a runner. Options:

- **Shell runner on gitlab itself** — simplest, runs as `gitlab-runner` user (or root if misconfigured). Jobs execute directly on the Linux host.
- **Shell runner on WEB** — runner registered on WEB, jobs run in the Windows context with access to `wwwroot`. Closer to a real dev pipeline.
- **Docker runner** — adds container isolation, less interesting for lateral movement scenarios.

**Recommendation:** Shell runner on WEB running as `webadmin` (local admin). This gives the pipeline legitimate write access to `wwwroot` and makes the poisoning primitive more realistic.

---

## Planned TTPs

### 1. CI/CD Pipeline Poisoning (T1195.002 / T1059)

**Setup needed:**
- GitLab Runner registered on WEB, running as `webadmin`
- A repository with a real (vulnerable) web application and a working `.gitlab-ci.yml`
- Pipeline triggered on push to `main`

**Attack path:**
```
Compromise webdev credentials
  → Push modified .gitlab-ci.yml to main branch
  → Pipeline executes on WEB runner
  → Deploy web shell (shell.aspx) to C:\inetpub\wwwroot
  → RCE via IIS worker process (w3wp.exe)
```

**Trigger options:**
- Direct push as `webdev` (maintainer — no review required)
- Merge request from a forked branch if branch protection is enabled

**Detection opportunities:**
- Unexpected `.gitlab-ci.yml` modification (GitLab audit log)
- Unusual file deployed to `wwwroot` (Sysmon file creation on WEB)
- `cmd.exe` / `powershell.exe` spawned by `w3wp.exe` (Sysmon process creation)

---

### 2. Secret Leakage from Repositories (T1552.001)

**Setup needed:**
- Repository with intentional hardcoded secrets: MSSQL connection string with SA credentials, API keys, deploy tokens

**Attack path:**
```
Log in to GitLab with any LDAP domain user
  → Browse repos (all domain users can authenticate via LDAP)
  → Find hardcoded connection string: Server=10.2.50.14;User=sa;Password=...
  → Connect to MSSQL directly from Kali with recovered SA credentials
```

**Variants:**
- Secrets in `.gitlab-ci.yml` (env vars in plain text)
- Secrets in CI/CD project variables (requires maintainer/owner to expose)
- Commit history with a "accidentally committed" password that was later removed

**Detection opportunities:**
- LDAP authentication by unexpected domain users (GitLab auth log)
- Direct MSSQL connection from non-WEB host (SQL Server audit, network)

---

### 3. Webhook / Outbound SSRF (T1071)

**Setup needed:** None — available immediately once a repo exists.

**Attack path:**
```
Authenticate to GitLab (any domain user)
  → Create or modify a project webhook pointing to http://10.2.50.250:<port>
  → Trigger webhook via push / pipeline event
  → Capture HTTP request on Kali — confirms outbound connectivity and internal token leakage
```

Webhooks include a secret token and internal GitLab metadata in the request body. This is low-effort and works as a building block for exfiltration scenarios.

---

## Dependencies Between Scenarios

```
GitLab Runner on WEB
    └─► CI/CD Pipeline Poisoning
            └─► Web Shell on WEB (see WEB.md)
                    └─► Token Impersonation → SYSTEM

Repo with secrets
    └─► SA credentials recovered
            └─► Direct MSSQL access (xp_cmdshell, NTLM capture)

Webhook
    └─► Outbound exfiltration demo
    └─► SSRF if GitLab is on a more restricted network segment
```

---

## Implementation Checklist

- [x] Create a repository with the vulnerable web application source (`thruntops-web` via `ludus_gitlab_runner` role)
- [x] Register a GitLab Runner (shell executor on GitLab VM, not WEB — deploys via smbclient)
- [x] Write a working `.gitlab-ci.yml` that deploys the app to `wwwroot` via SMB
- [x] Add intentional hardcoded secrets to `.gitlab-ci.yml` (webadmin credentials in smbclient command)
- [x] Document pipeline poisoning + secret leakage attack paths in `docs/vulnerabilities.md`
- [ ] Verify end-to-end pipeline: push → deploy → app reachable at `http://10.2.50.14`
