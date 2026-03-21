# ThruntOps

![ThruntOps](logo.png)

A Ludus-based lab environment for TTP testing and security research.

## Purpose

ThruntOps exists to provide a controlled environment for testing attack techniques and procedures (TTPs). The design philosophy is breadth over depth: rather than optimizing for a single attack scenario, the lab grows by adding technologies — each one introducing new attack surfaces, protocols, and vectors to test against.

## Profiles

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud). All VMs run on VLAN 50 (`10.2.50.0/24`). Deploy with the config file matching your chosen SIEM:

| Profile | Config | SIEM | VMs |
|---|---|---|---|
| [Elastic](https://enonethreezed.github.io/ThruntOps/elastic) | `elastic.yml` | Elastic Stack + Fleet | 9 — full lab with IIS, MSSQL, GitLab CE |
| [Wazuh](https://enonethreezed.github.io/ThruntOps/wazuh) | `wazuh.yml` | Wazuh all-in-one | 7 — lightweight, Windows-only agents |

All profiles share the same dual AD forest (`thruntops.domain` + `secondary.thruntops.domain`), ADCS, dual Windows 11 workstations, and an ops VM with Guacamole and Infection Monkey.

## Users

See the [Users reference](https://enonethreezed.github.io/ThruntOps/users) for the full credentials reference.

## Attack Surface

See the [Vulnerabilities reference](https://enonethreezed.github.io/ThruntOps/vulnerabilities) for the full attack surface reference.

## Installation

See the [Installation guide](https://enonethreezed.github.io/ThruntOps/install) for full setup instructions.

## Roadmap

- Vulnerable web application covering OWASP Top 10
- GitLab CI/CD pipeline to WEB (automated deploy on push)
- Sigma rules + Atomic Red Team detection pipeline — see [docs](https://enonethreezed.github.io/ThruntOps/sigma)
- Reduce resource requirements to support lower-spec hosts (target: 32 GB RAM)
