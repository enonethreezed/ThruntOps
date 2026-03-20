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

### Prerequisites

- x86_64 CPU with VMX/SVM (hardware virtualization enabled in BIOS)
- Debian 12/13 or Proxmox 8/9
- Minimum 32 GB RAM, 200 GB storage (NVMe recommended)
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
ludus templates build -n kali-x64-desktop-template
```

Monitor build progress:

```bash
ludus templates logs -f
```

Wait for all four templates to show `BUILT` before proceeding:

```bash
ludus templates list
```

---

## 4. Install Ansible Roles

Install the required roles from Ansible Galaxy and GitHub:

```bash
# Elastic Stack roles
ludus ansible roles add badsectorlabs.ludus_elastic_container
ludus ansible roles add badsectorlabs.ludus_elastic_agent

# ADCS role
ludus ansible roles add badsectorlabs.ludus_adcs

# MSSQL
ludus ansible roles add badsectorlabs.ludus_mssql

# Custom roles (local user management, AD content, IIS, GitLab)
ludus ansible roles add https://github.com/Cyblex-Consulting/ludus-local-users/archive/refs/heads/main.tar.gz
ludus ansible roles add https://github.com/Cyblex-Consulting/ludus-ad-content/archive/refs/heads/main.tar.gz

# IIS+ASP.NET (local role — included in this repo)
ludus ansible roles add -d roles/ludus_iis

# GitLab CE — requires role_name fix before installing
curl -sL https://github.com/Cyblex-Consulting/ludus-gitlab-ce/archive/refs/heads/main.tar.gz -o /tmp/ludus-gitlab-ce.tar.gz
mkdir -p /tmp/ludus_gitlab_ce
tar -xzf /tmp/ludus-gitlab-ce.tar.gz -C /tmp/ludus_gitlab_ce --strip-components=1
sed -i 's/role_name: ludus_ad_content/role_name: ludus_gitlab_ce/' /tmp/ludus_gitlab_ce/meta/main.yml
ludus ansible roles add -d /tmp/ludus_gitlab_ce

# Local roles (included in this repo)
ludus ansible roles add -d roles/ludus_ad_content
ludus ansible roles add -d roles/ludus_gitlab_ldap
ludus ansible roles add -d roles/ludus_laps
```

Verify all roles are installed:

```bash
ludus ansible roles list
```

---

## 5. Deploy the Range

Set the range configuration from this repository:

```bash
ludus range config set -f elastic.yml
```

Verify the config was accepted without errors, then deploy:

```bash
ludus range deploy
```

Monitor deployment (takes 60–90 minutes for a full deploy):

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

Run the Fleet status check to confirm all Elastic agents are enrolled:

```bash
bash tests/fleet_status.sh
```

All Windows VMs (`DC01-2022`, `DC01-SEC`, `ADCS`, `WEB`, `WIN11-22H2-1`, `WIN11-22H2-2`) and the GitLab VM should appear with status `online`.

---

## Notes

- The ADCS VM requires `sysprep: true` to generate a unique machine SID — already set in `elastic.yml`
- DCs do not support local SAM accounts — local user provisioning only applies to member machines
- Windows LAPS schema extension runs on DC01-2022 — requires the domain to be fully provisioned first
