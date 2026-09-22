# ThruntOps

![ThruntOps](logo.png)

A Ludus-based lab for TTP detection testing: one SIEM, one Active Directory domain, one workstation, one attacker box.

## Scope

ThruntOps targets a single 2022 baseline: Windows Server 2022 DC (`thruntops.domain`), a Windows 11 22H2 workstation, and a Kali attacker VM, plus a choice of SIEM backend (Elastic, Wazuh, or Splunk). Vulnerable AD states are provisioned in-repo, applied manually after the base lab is deployed.

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud) on VLAN 20 (`10.<range>.20.0/24`).

## Backends

| Backend | Config | SIEM | VMs |
|---|---|---|---|
| [Elastic](https://enonethreezed.github.io/ThruntOps/elastic) | `ranges/elk-base-2022.yml` | Elastic Stack + Fleet | 4 |
| [Wazuh](https://enonethreezed.github.io/ThruntOps/wazuh) | `ranges/wazuh-base-2022.yml` | Wazuh all-in-one | 4 |
| [Splunk](https://enonethreezed.github.io/ThruntOps/splunk) | `ranges/splunk-base-2022.yml` | Splunk Enterprise | 4 |

All backends share the same four-node topology and are managed with:

```bash
./siem.sh <deploy|start|stop|check|status> <elastic|wazuh|splunk>
```

## Users

See the [Users reference](https://enonethreezed.github.io/ThruntOps/users) for the full credentials reference.

## Installation

See the [Installation guide](https://enonethreezed.github.io/ThruntOps/install) for full setup instructions.

## Status

Static build: ranges, roles, installer, and cross-repo contract validation pass. Deploy validation pending.
