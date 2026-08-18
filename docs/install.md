---
title: Installation
layout: default
nav_order: 2
---

# Installation Guide
{: .no_toc }

Full setup from a bare Debian/Proxmox host to a running ThruntOps lab.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## 1. Install Ludus

{: .note }
Full Ludus documentation at [docs.ludus.cloud](https://docs.ludus.cloud). Project home at [ludus.cloud](https://ludus.cloud).

### Prerequisites

- x86_64 CPU with VMX/SVM (hardware virtualization enabled in BIOS)
- Debian 12/13 or Proxmox 8/9
- Minimum 48 GB RAM, 200 GB storage (NVMe recommended)
- Wired ethernet (WiFi not supported)
- Root access + internet connectivity
- Docker must NOT be installed on the host

### Install

```bash
curl --proto '=https' --tlsv1.2 -sSf https://ludus.cloud/install | bash
```

The installer will prompt for configuration values (defaults are fine) and reboot the machine. After reboot, monitor progress:

```bash
ludus-install-status
```

---

## 2. Configure API Access

Once Ludus is running, get your API key and configure the client:

```bash
ludus users apikey
```

Set the API URL and key in `~/.config/ludus/config.yml` or via environment variables if accessing remotely.

---

## 3. Build Templates

List available templates and build the ones required by this lab:

```bash
ludus templates list
```

Build required templates (each can take 20–60 minutes):

```bash
ludus templates build -n debian-12-x64-server-template
ludus templates build -n win2022-server-x64-template
ludus templates build -n win11-22h2-x64-enterprise-template
```

Monitor build progress:

```bash
ludus templates logs -f
```

Wait for all templates to show `BUILT` before proceeding:

```bash
ludus templates list
```

---

## 4. Install Ansible Roles

Install the Galaxy roles and register all local roles with the included script:

```bash
# Elastic Stack
ludus ansible roles add badsectorlabs.ludus_elastic_container
ludus ansible roles add badsectorlabs.ludus_elastic_agent

# Splunk (if using Splunk profile)
# ludus ansible roles add -d roles/ludus_splunk
# ludus ansible roles add -d roles/ludus_splunk_uf

# All local roles (AD content, local users, etc.)
bash roles/install-roles.sh
```

{: .warning }
After any change to a local role, re-sync with `--force` to overwrite the cached version:
```bash
ludus ansible roles add -d roles/<name> --force
```

Verify all roles are installed:

```bash
ludus ansible roles list
```

---

## 5. Deploy the Range

Each SIEM has its own script (`elastic.sh`, `wazuh.sh`, `splunk.sh`) that destroys any existing range, applies the config, and deploys in one step. Each accepts one of three profile flags:

- `--base` — 1 AD + 1 workstation
- `--dual` — 2 AD + 2 workstations
- `--adcs` — 1 AD + ADCS + 1 workstation

```bash
bash elastic.sh --dual   # ranges/elk-dual.yml
bash elastic.sh --adcs   # ranges/elk-adcs.yml
bash wazuh.sh --dual     # ranges/wazuh-dual.yml
bash splunk.sh --dual    # ranges/splunk-dual.yml
```

Or step by step:

```bash
ludus range config set -f ranges/elk-dual.yml
ludus range deploy
ludus range logs -f
```

Monitor deployment:

```bash
ludus range logs -f
```

Check final status:

```bash
ludus range status
```

All VMs should show `BUILT` and the deployment status should be `SUCCESS`.

---

## 6. Verify

### Elastic profile

Open Kibana at `https://<range_ip>.20.1:5601` and navigate to:

**Management → Fleet → Agents**

All four VMs (`DC01-2022`, `DC01-SEC`, `WIN11-22H2-1`, `WIN11-22H2-2`) should show status `Healthy`.

### Splunk profile

Check that all Universal Forwarders are connected via Splunk Web at `http://<range_ip>.20.1:8000`:

- **Settings → Forwarding and receiving → Forwarder management** — all forwarders should appear
- **Search:** `index=windows earliest=-15m` — Windows Event Logs from all domain-joined VMs

### Wazuh profile

Run the Wazuh agent status check:

```bash
bash tests/wazuh_status.sh
```

All agents should appear with status `active`.

---

## Notes

- DCs do not support local SAM accounts — local user provisioning only applies to member machines
- `ludus ansible roles add` does **not** overwrite an existing role — use `--force` flag to update installed roles
