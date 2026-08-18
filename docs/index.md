---
title: ThruntOps
layout: home
nav_order: 1
---

<img src="logo.png" alt="ThruntOps" width="256">

# ThruntOps

A Ludus-based lab environment for TTP testing and security research.

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud). Dual Active Directory domains and a choice of SIEM.

All three core SIEM profiles have passed Ludus 2 validation: range deploy succeeds, domain users authenticate, SIEM services are reachable, and all four Windows endpoints report telemetry.

## Profiles

| Profile | Config | SIEM | VMs | Validation |
|---|---|---|---|---|
| [Elastic](elastic.md) | `elastic-core.yml` | Elastic Stack + Fleet | 5 — dual AD, dual workstations | Passed on Ludus 2 |
| Elastic + ADCS | `elastic-adcs.yml` | Elastic Stack + Fleet | 6 — core + ADCS | Passed ADCS smoke test on Ludus 2 |
| [Splunk](splunk.md) | `splunk-core.yml` | Splunk Enterprise | 5 — dual AD, dual workstations | Passed on Ludus 2 |
| [Wazuh](wazuh.md) | `wazuh-core.yml` | Wazuh all-in-one | 5 — dual AD, dual workstations | Passed on Ludus 2 |

## Phases

| Phase | Scope | Status |
|---|---|---|
| **Fase 1 — Core SIEM** | SIEM + dual AD + workstations + agents | Passed validation on Ludus 2 |
| **Fase 2 — Vulnerabilities** | ADCS, WEB (IIS+MSSQL), GitLab, OPS, vuln scripts | Planned |

→ [Installation](install.md) · [Users](users.md) · [Coverage](coverage.md)

> Fase 2 reference docs are preserved and accessible: [ADCS](adcs.md) · [Vulnerabilities](vulnerabilities.md) · [Vulnerable-AD Matrix](vulnerable-ad-matrix.md) · [WEB + MSSQL](web.md) · [GitLab](gitlab.md) · [Sigma](sigma.md)
