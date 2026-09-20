---
title: ThruntOps
layout: home
nav_order: 1
---

<img src="logo.png" alt="ThruntOps" width="256">

# ThruntOps

A Ludus-based lab for TTP detection testing: one SIEM, one Active Directory domain, one workstation, one attacker box.

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud). Single 2022 baseline with a choice of SIEM backend.

## Backends

| Backend | Config | SIEM | VMs |
|---|---|---|---|
| [Elastic](elastic.md) | `ranges/elk-base-2022.yml` | Elastic Stack + Fleet | 4 |
| [Wazuh](wazuh.md) | `ranges/wazuh-base-2022.yml` | Wazuh all-in-one | 4 |
| [Splunk](splunk.md) | `ranges/splunk-base-2022.yml` | Splunk Enterprise | 4 |

All backends share the same four-node topology (SIEM, DC01-2022, WIN11-22H2-1, Kali) and are managed with the unified `siem.sh` script:

```bash
./siem.sh deploy elastic
./siem.sh deploy wazuh
./siem.sh deploy splunk
```

## Vulnerable AD Scenarios

AD attack states are provisioned by the pinned external role [`ludus_ad`](https://github.com/enonethreezed/ThruntOps-vulnerabilities):

- `CRED-ASREP-01` — accounts without Kerberos pre-authentication
- `CRED-KERBEROAST-01` — service accounts with harvestable SPNs
- `CRED-DESCRIPTION-01` — credentials exposed in user descriptions

→ [Installation](install.md) · [Users](users.md) · [Kali](kali.md)
