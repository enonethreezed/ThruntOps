---
title: ThruntOps
layout: home
nav_order: 1
---

<img src="logo.png" alt="ThruntOps" width="256">

# ThruntOps

A Ludus-based lab environment for TTP testing and security research.

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud). Dual Active Directory domains and a choice of SIEM.

All 9 atomized profiles (base/dual/adcs × Elastic/Splunk/Wazuh) have passed a from-scratch deploy validation on Ludus 2: destroy + deploy succeeds, domain users authenticate, SIEM services are reachable, and every endpoint enrolls.

## Profiles

| Profile | Config | SIEM | VMs | Validation |
|---|---|---|---|---|
| [Elastic](elastic.md) | `elk-{base,dual,adcs}.yml` | Elastic Stack + Fleet | 3 / 5 / 4 VMs | Passed on Ludus 2 — base, dual, adcs |
| [Splunk](splunk.md) | `splunk-{base,dual,adcs}.yml` | Splunk Enterprise | 3 / 5 / 4 VMs | Passed on Ludus 2 — base, dual, adcs |
| [Wazuh](wazuh.md) | `wazuh-{base,dual,adcs}.yml` | Wazuh all-in-one | 3 / 5 / 4 VMs | Passed on Ludus 2 — base, dual, adcs |

Each SIEM has three atomic profiles, deployed via its own script:

- `--base` — 1 AD + 1 workstation
- `--dual` — 2 AD + 2 workstations (the validated profile above)
- `--adcs` — 1 AD + dedicated ADCS VM + 1 workstation

```bash
bash elastic.sh --dual
bash wazuh.sh --dual
bash splunk.sh --dual
```

## Phases

| Phase | Scope | Status |
|---|---|---|
| **Fase 1 — Core SIEM** | SIEM + dual AD + workstations + agents | Passed validation on Ludus 2 |
| **Fase 2 — Vulnerabilities** | ADCS, WEB (IIS+MSSQL), GitLab, OPS, vuln scripts | Planned |

→ [Installation](install.md) · [Users](users.md) · [Coverage](coverage.md)

> Fase 2 reference docs are preserved and accessible: [ADCS](adcs.md) · [Vulnerabilities](vulnerabilities.md) · [Vulnerable-AD Matrix](vulnerable-ad-matrix.md) · [WEB + MSSQL](web.md) · [GitLab](gitlab.md) · [Sigma](sigma.md)
