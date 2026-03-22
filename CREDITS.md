# Credits & Acknowledgements

ThruntOps is built on the work of many individuals, teams, and companies. This document lists the projects, tools, and research that make this lab possible.

---

## Lab Framework

### Ludus
[ludus.cloud](https://ludus.cloud) · [docs.ludus.cloud](https://docs.ludus.cloud)

The entire lab is built on Ludus — a Proxmox-based cyber range automation platform developed by [Bad Sector Labs](https://badsectorlabs.com). Ludus handles VM provisioning, templating, networking, and Ansible role orchestration.

---

## Ansible Roles (External)

### Bad Sector Labs
[github.com/badsectorlabs](https://github.com/badsectorlabs)

- [`ludus_elastic_container`](https://github.com/badsectorlabs/ludus_elastic_container) — Elastic Stack deployment
- [`ludus_elastic_agent`](https://github.com/badsectorlabs/ludus_elastic_agent) — Elastic Fleet agent
- [`ludus_adcs`](https://github.com/badsectorlabs/ludus_adcs) — Active Directory Certificate Services with ESC misconfigurations
- [`ludus_mssql`](https://github.com/badsectorlabs/ludus_mssql) — SQL Server installation

### Cyblex Consulting
[github.com/Cyblex-Consulting](https://github.com/Cyblex-Consulting)

- [`ludus-local-users`](https://github.com/Cyblex-Consulting/ludus-local-users) — Local user management on Windows VMs
- [`ludus-ad-content`](https://github.com/Cyblex-Consulting/ludus-ad-content) — Active Directory users, groups, and OUs
- [`ludus-gitlab-ce`](https://github.com/Cyblex-Consulting/ludus-gitlab-ce) — GitLab CE deployment

---

## SIEM Platforms

### Elastic
[elastic.co](https://www.elastic.co)

Elasticsearch, Kibana, and the Elastic Fleet/Agent framework used in the `elastic.yml` profile.

### Wazuh
[wazuh.com](https://wazuh.com)

Open-source XDR and SIEM platform used in the `wazuh.yml` profile. Agents deployed on all lab VMs for centralized log collection and alerting.

### Splunk
[splunk.com](https://www.splunk.com)

Splunk Enterprise and Universal Forwarder used in the `splunk.yml` profile.

---

## Applications & Services

### GitLab CE
[gitlab.com](https://gitlab.com)

Self-hosted Git repository and CI/CD platform. Used as an attack surface for pipeline poisoning, secret leakage, and SUID privilege escalation scenarios.

### Microsoft SQL Server
[microsoft.com](https://www.microsoft.com/en-us/sql-server)

SQL Server 2019 used as the backend for the vulnerable web application and as an independent attack surface (xp_cmdshell, NTLM capture, DBA privilege escalation).

### Microsoft Active Directory & ADCS
[microsoft.com](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/)

Windows Server 2022 domain infrastructure (dual domain, ADCS, LAPS) providing the core AD attack surface.

---

## Security Tools & Frameworks

### Certipy
[github.com/ly4k/Certipy](https://github.com/ly4k/Certipy) — Oliver Lyak

The primary tool used for ADCS enumeration and exploitation (ESC1–ESC16). All ADCS attack paths in this lab were validated using Certipy.

### Impacket
[github.com/fortra/impacket](https://github.com/fortra/impacket) — SecureAuth / Fortra

Python library for network protocol interaction. Used for NTLM relay (ntlmrelayx), lateral movement (psexec, secretsdump), and credential operations.

### PetitPotam
[github.com/topotam/PetitPotam](https://github.com/topotam/PetitPotam) — topotam

Unauthenticated NTLM coercion tool used for ESC8 and ESC11 attack paths.

### Infection Monkey
[github.com/guardicore/monkey](https://github.com/guardicore/monkey) — Guardicore / Akamai

Automated breach and attack simulation (BAS) platform deployed on the ops VM. Used to generate realistic attack telemetry for detection engineering.

### Sigma
[github.com/SigmaHQ/sigma](https://github.com/SigmaHQ/sigma) — SigmaHQ community

Generic SIEM detection rule format. Used for writing and converting portable detection rules against lab telemetry.

### GTFOBins
[gtfobins.github.io](https://gtfobins.github.io)

Reference for Unix binary exploitation (SUID, capabilities, sudo). The privilege escalation scenarios on the `ops` and `gitlab` VMs are based on GTFOBins techniques.

### Sysmon (Linux)
[github.com/Sysinternals/SysmonForLinux](https://github.com/Sysinternals/SysmonForLinux) — Microsoft Sysinternals

Linux port of Sysinternals Sysmon, deployed on Linux VMs for process and network telemetry.

---

## Research & Documentation

### SpecterOps — "Certified Pre-Owned"
[specterops.io](https://specterops.io) — Will Schroeder, Lee Christensen

The foundational research paper on Active Directory Certificate Services attack paths (ESC1–ESC8 and beyond). All ADCS scenarios in this lab are derived from this work.
[Download whitepaper](https://specterops.io/assets/resources/Certified_Pre-Owned.pdf)

### MITRE ATT&CK
[attack.mitre.org](https://attack.mitre.org)

Adversarial tactics and techniques framework. All attack paths in this lab are mapped to ATT&CK technique IDs.

### BloodHound / SpecterOps ADCS research
[medium.com/specter-ops-posts](https://medium.com/specter-ops-posts)

ADCS attack path documentation in BloodHound (Parts 1–3), referenced throughout the ADCS attack path documentation.

---

## Windows LAPS

[learn.microsoft.com — Windows LAPS](https://learn.microsoft.com/en-us/windows-server/identity/laps/laps-overview) — Microsoft

Windows Local Administrator Password Solution deployed on all domain-joined VMs. The `win2022-server-x64-laps-template` custom Packer template ensures KB5025230 is pre-installed so LAPS cmdlets are available without running Windows Update during every deploy.
