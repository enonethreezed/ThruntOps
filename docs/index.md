---
title: ThruntOps
layout: home
nav_order: 1
---

<img src="logo.png" alt="ThruntOps" width="256">

# ThruntOps

A Ludus-based lab environment for TTP testing and security research.

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud). Dual Active Directory domain, ADCS, and a choice of SIEM.

## Profiles

| Profile | Config | SIEM | VMs |
|---|---|---|---|
| [Elastic](elastic.md) | `elastic.yml` | Elastic Stack + Fleet | 9 — full lab with IIS, MSSQL, GitLab CE |
| [Wazuh](wazuh.md) | `wazuh.yml` | Wazuh all-in-one | 9 — full lab with IIS, MSSQL, GitLab CE |
| [Splunk](splunk.md) | `splunk.yml` | Splunk Enterprise | 9 — full lab with IIS, MSSQL, GitLab CE |

→ [Vulnerabilities](vulnerabilities.md) · [ADCS Attack Paths](adcs.md)
