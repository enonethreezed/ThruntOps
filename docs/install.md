---
title: Installation
layout: default
nav_order: 4
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
ludus templates build -n kali-x64-desktop-template
```

#### LAPS-ready Windows Server 2022 template

ThruntOps requires a custom win2022 template with Security and Critical updates pre-installed. This ensures Windows built-in LAPS (KB5025230+) is available without running Windows Update during every lab deploy — saving 30–60 minutes per deployment.

Build it once from the included Packer template:

```bash
ludus templates add -d templates/win2022-server-x64-laps
ludus templates build -n win2022-server-x64-laps-template
```

> This build takes 2–3 hours (downloads ISO + installs all updates). It only needs to be done once.

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

Install roles based on your chosen profile.

### Elastic profile

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
ludus ansible roles add -d roles/ludus_ops
ludus ansible roles add -d roles/ludus_atomic_red_team
```

### Wazuh profile

```bash
# Wazuh server (all-in-one)
ludus ansible roles add aleemladha.wazuh_server_install

# Wazuh Windows agent
ludus ansible roles add aleemladha.ludus_wazuh_agent

# ADCS role
ludus ansible roles add badsectorlabs.ludus_adcs

# Local roles (included in this repo)
ludus ansible roles add https://github.com/Cyblex-Consulting/ludus-local-users/archive/refs/heads/main.tar.gz
ludus ansible roles add -d roles/ludus_ad_content
ludus ansible roles add -d roles/ludus_laps
ludus ansible roles add -d roles/ludus_ops
ludus ansible roles add -d roles/ludus_atomic_red_team
```

{: .warning }
The `aleemladha.ludus_wazuh_agent` role uses non-standard internal variable names. After installing the role, patch it to match the `role_vars` keys used in `wazuh.yml`:

```bash
ROLE="/opt/ludus/users/ludus-admin/.ansible/roles/aleemladha.ludus_wazuh_agent/tasks/windows.yml"
sudo sed -i 's/wazuh_agent_install_package/ludus_wazuh_agent_install_package/g' "$ROLE"
sudo sed -i 's/wazuh_manager_host/ludus_wazuh_siem_server/g' "$ROLE"
```

Verify all roles are installed:

```bash
ludus ansible roles list
```

#### Patch badsectorlabs.ludus_mssql template

The `win_template` module in the Ludus Ansible environment does not evaluate Jinja2 block tags (`{% %}`). After installing the role, patch the SQL Server 2019 config template to remove unrendered blocks and hardcode the instance name:

```bash
TMPL="/opt/ludus/users/ludus-admin/.ansible/roles/badsectorlabs.ludus_mssql/templates/sqlsrv_2019_config.ini.j2"
sudo sed -i '/^{%/d' "$TMPL"
sudo sed -i 's/INSTANCENAME="{{ ludus_mssql_instance_name }}"/INSTANCENAME="MSSQLSERVER"/' "$TMPL"
sudo sed -i 's/INSTANCEID="{{ ludus_mssql_instance_name }}"/INSTANCEID="MSSQLSERVER"/' "$TMPL"
sudo sed -i 's/UpdateEnabled="True"/UpdateEnabled="False"/' "$TMPL"
sudo sed -i 's/USEMICROSOFTUPDATE="True"/USEMICROSOFTUPDATE="False"/' "$TMPL"
```

---

## 5. Deploy the Range

Set the range configuration for your chosen profile:

```bash
# Elastic profile
ludus range config set -f elastic.yml

# Wazuh profile
ludus range config set -f wazuh.yml
```

Verify the config was accepted without errors, then deploy:

```bash
ludus range deploy
```

Monitor deployment (takes 2–3 hours with the LAPS-ready template):

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

Run the Fleet status check to confirm all Elastic agents are enrolled:

```bash
bash tests/fleet_status.sh
```

All Windows VMs (`DC01-2022`, `DC01-SEC`, `ADCS`, `WEB`, `WIN11-22H2-1`, `WIN11-22H2-2`), the GitLab VM, and the `ops` VM should appear with status `online`.

### Wazuh profile

Run the Wazuh agent status check:

```bash
bash tests/wazuh_status.sh
```

All Windows VMs (`DC01-2022`, `DC01-SEC`, `ADCS`, `WIN11-22H2-1`, `WIN11-22H2-2`) should appear with status `active`.

### Common

Once deployed, the `ops` VM exposes:
- **Guacamole** (remote access): `http://10.2.50.2:8080/guacamole/` — default credentials `guacadmin:guacadmin`
- **Infection Monkey** (BAS): `https://10.2.50.2:5000`

To add a Kali attacker VM (optional):

```bash
bash scripts/add-kali.sh
```

---

## Notes

- The ADCS VM requires `sysprep: true` to generate a unique machine SID — already set in `elastic.yml` and `wazuh.yml`
- DCs do not support local SAM accounts — local user provisioning only applies to member machines
- Windows LAPS schema extension runs on DC01-2022 — requires the domain to be fully provisioned first
- The `win2022-server-x64-laps-template` is used for both DCs. It includes all Windows updates applied at build time, so LAPS cmdlets are immediately available without running `win_updates` during deploy
- `ludus ansible roles add` does **not** overwrite an existing role — use `sudo cp -rf` to update installed roles
- `badsectorlabs.ludus_mssql` requires a manual template patch after install (see step 4) — `win_template` in the Ludus Ansible env does not evaluate Jinja2 block tags, leaving literal `{%` in rendered configs which causes `setup.exe` to fail
- The cached MSSQL ISO at `/opt/ludus/resources/iso/` is SQL Server 2019; `ludus_mssql_version` in `elastic.yml` is set to `"2019"` accordingly
