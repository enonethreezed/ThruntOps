# ThruntOps

![ThruntOps](logo.png)

A Ludus-based lab environment for TTP testing and security research.

## Purpose

ThruntOps exists to provide a controlled environment for testing attack techniques and procedures (TTPs). The design philosophy is breadth over depth: rather than optimizing for a single attack scenario, the lab grows by adding technologies — each one introducing new attack surfaces, protocols, and vectors to test against.

## Status
All 9 atomized profiles are validated on Ludus 2: Elastic, Wazuh, and Splunk, each in `--base`, `--dual`, and `--adcs` form.

Validation completed via a from-scratch deploy (destroy + deploy) of every profile: range deploy succeeds, domain authentication works, SIEM services are reachable, and every endpoint enrolls.

## Profiles

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud). The validated profiles run on VLAN 20 (`10.<range>.20.0/24`). Each SIEM has three atomic profiles, deployed via its own script (`elastic.sh`, `wazuh.sh`, `splunk.sh`) with `--base`, `--dual`, or `--adcs`:

| Profile | Config | SIEM | VMs | Validation |
|---|---|---|---|---|
| [Elastic](https://enonethreezed.github.io/ThruntOps/elastic) | `elk-{base,dual,adcs}.yml` | Elastic Stack + Fleet | 3 / 5 / 4 VMs | Passed on Ludus 2 — base, dual, adcs |
| [Wazuh](https://enonethreezed.github.io/ThruntOps/wazuh) | `wazuh-{base,dual,adcs}.yml` | Wazuh all-in-one | 3 / 5 / 4 VMs | Passed on Ludus 2 — base, dual, adcs |
| [Splunk](https://enonethreezed.github.io/ThruntOps/splunk) | `splunk-{base,dual,adcs}.yml` | Splunk Enterprise | 3 / 5 / 4 VMs | Passed on Ludus 2 — base, dual, adcs |

`--base` is a single AD domain + 1 workstation, `--dual` adds a second AD domain + workstation (the validated profile above), and `--adcs` swaps the second domain for a dedicated ADCS VM on the single domain. All profiles share the same AD forest naming (`thruntops.domain` [+ `secondary.thruntops.domain` on dual]) and only provision Ludus's default accounts. Fase 2 will add MSSQL and OPS infrastructure.

## Users

See the [Users reference](https://enonethreezed.github.io/ThruntOps/users) for the full credentials reference.

## Attack Surface

See the [Vulnerabilities reference](https://enonethreezed.github.io/ThruntOps/vulnerabilities) for the full attack surface reference.

## Installation

See the [Installation guide](https://enonethreezed.github.io/ThruntOps/install) for full setup instructions.

## Roadmap

- MSSQL as a standalone vulnerability vector (xp_cmdshell, NTLM capture, DBA → sysadmin escalation) — see [MSSQL TTPs](https://enonethreezed.github.io/ThruntOps/mssql)
- Reduce resource requirements to support lower-spec hosts (target: 32 GB RAM)
