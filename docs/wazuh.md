---
title: Wazuh Profile
layout: default
nav_order: 4
---

# Wazuh Profile
{: .no_toc }

Wazuh all-in-one SIEM with dual AD domains and workstations. Fase 1 — core infrastructure and agent enrollment.
{: .fs-6 .fw-300 }

Validated on Ludus 2 across all three profiles (`--base`, `--dual`, `--adcs`): a from-scratch deploy (destroy + deploy) succeeds, domain authentication works, Wazuh API/dashboard are reachable, and every agent is active — including Sysmon telemetry.
{: .label .label-green }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Infrastructure

All VMs run on VLAN 20.

| IP | Hostname | OS | Role |
|---|---|---|---|
| .20.1 | wazuh | Ubuntu 24.04 | SIEM — Wazuh all-in-one (manager + indexer + dashboard) |
| .20.11 | DC01-2022 | Windows Server 2022 | Primary DC — `thruntops.domain` |
| .20.12 | DC01-SEC | Windows Server 2022 | Primary DC — `secondary.thruntops.domain` |
| .20.21 | WIN11-22H2-1 | Windows 11 22H2 | Workstation — `thruntops.domain` |
| .20.22 | WIN11-22H2-2 | Windows 11 22H2 | Workstation — `secondary.thruntops.domain` |

> IP prefix depends on the Ludus range network (e.g. `10.1.0.0/16` → `10.1.20.x`).

Table shows `--dual` (5 VMs). `--base` drops the secondary domain (3 VMs: `wazuh`, `DC01-2022`, `WIN11-22H2-1`). `--adcs` swaps the secondary domain for a dedicated ADCS VM at `.20.13` (4 VMs: `wazuh`, `DC01-2022`, `ADCS`, `WIN11-22H2-1`) — single domain only.

---

## Network Diagram

```mermaid
graph TB
    subgraph VLAN20["VLAN 20"]

        subgraph primary["thruntops.domain"]
            DC1["🖥 DC01-2022\n.20.11\nPrimary DC"]
            W1["🖥 WIN11-22H2-1\n.20.21\nWorkstation"]
        end

        subgraph secondary["secondary.thruntops.domain"]
            DC2["🖥 DC01-SEC\n.20.12\nPrimary DC"]
            W2["🖥 WIN11-22H2-2\n.20.22\nWorkstation"]
        end

        WAZUH["🐧 wazuh\n.20.1\nWazuh SIEM"]
    end

    DC1 <-->|"domain trust"| DC2
    W1 -->|"member"| DC1
    W2 -->|"member"| DC2

    WAZUH -.->|"Wazuh agent"| DC1
    WAZUH -.->|"Wazuh agent"| DC2
    WAZUH -.->|"Wazuh agent"| W1
    WAZUH -.->|"Wazuh agent"| W2
```

---

## Credentials

| Service | URL | User | Password |
|---|---|---|---|
| Wazuh Dashboard | `https://<range_ip>.20.1` | `admin` | set in `wazuh-dual.yml` → `wazuh_admin_password` |
| Wazuh REST API | `https://<range_ip>.20.1:55000` | `wazuh` | set in `wazuh-dual.yml` → `wazuh_api_password` |

### Local & Domain — Ludus defaults

| User | Password | Scope |
|---|---|---|
| `localuser` | `password` (template default) | Local Admin (Windows) / SSH login (Linux) — all VMs |
| `THRUNTOPS\domainadmin` | `password` | Domain Admin — thruntops.domain |
| `THRUNTOPS\domainuser` | `password` | Domain User — thruntops.domain |
| `SECONDARY\domainadmin` | `password` | Domain Admin — secondary.thruntops.domain |
| `SECONDARY\domainuser` | `password` | Domain User — secondary.thruntops.domain |

{: .warning }
The Wazuh REST API user (`wazuh`) and dashboard user (`wazuh-wui`) are stored in a SQLite database at `/var/ossec/api/configuration/security/rbac.db` using werkzeug scrypt hashes. These are **not** updated by `wazuh-passwords-tool.sh` (which only changes the OpenSearch `admin` user). The `ludus_wazuh_server` role handles both via a Python script executed with `/var/ossec/framework/python/bin/python3`.

---

## Deployment

```bash
./siem.sh wazuh deploy --dual   # 2 AD + 2 workstations
./siem.sh wazuh deploy --base   # 1 AD + 1 workstation
./siem.sh wazuh deploy --adcs   # 1 AD + ADCS + 1 workstation
```

Or step by step:

```bash
ludus range destroy
ludus range config set -f ranges/wazuh-dual.yml
ludus range deploy
ludus range logs -f
```

---

## Verify

All three profiles have passed the post-deploy validation checklist on Ludus 2, run with the matching flag:

```bash
RANGE_PREFIX=10.<range> ./siem.sh wazuh check --base   # or --dual / --adcs
```

Or manually, confirm agents are enrolled, active, and reporting Sysmon:

```bash
./siem.sh wazuh status
```

Expected output: every agent in the deployed profile with status `active` (2 for `--base`, 4 for `--dual`, 3 for `--adcs`).

Check range status:

```bash
ludus range status
```

---

## Notes

- `wazuh-dual.yml` deploys Wazuh all-in-one via `wazuh-install.sh -a` (also available as `wazuh-base.yml` and `wazuh-adcs.yml` — see `siem.sh`)
- Unlike Splunk ([ThruntOps-m13](splunk.md#notes)), the Wazuh agent reads the Sysmon event channel correctly on every endpoint, including domain-member workstations and the ADCS VM — confirmed during validation.
- Fase 2 will add ADCS, MSSQL, and OPS VM.
