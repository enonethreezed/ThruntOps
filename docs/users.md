---
title: Users
layout: default
nav_order: 6
---

# Users
{: .no_toc }

All credentials used in the ThruntOps lab.
{: .fs-6 .fw-300 }

{: .warning }
This reference is for a local lab environment. Never use these credentials in production systems.

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Domain — thruntops.domain

| User | Password | Type |
|---|---|---|
| `THRUNTOPS\domainadmin` | `password` | Domain Admin (Ludus default) |
| `THRUNTOPS\domainuser` | `password` | Domain User (Ludus default) |

### Scenario identities (seeded by `thruntops_ad_content`)

| User | Password | Scenario |
|---|---|---|
| `THRUNTOPS\asrep.user` | `ASRep2022!` | `CRED-ASREP-01` — AS-REP roastable account |
| `THRUNTOPS\svc.web` | `Spring2022!` | `CRED-KERBEROAST-01` — Kerberoastable service account |
| `THRUNTOPS\helpdesk.user` | `Welcome2022!` | `CRED-DESCRIPTION-01` — password leaked in `description` |

---

## Local (all VMs)

| User | Password | Scope |
|---|---|---|
| `localuser` | `password` | Local Admin (Windows) / SSH login (Linux) — template default, all VMs |

---

## Kali

| User | Password | Scope |
|---|---|---|
| `root` | `password` | Attacker VM console — see [Kali](kali.md) |

---

## Services

| User | Password | Service | URL |
|---|---|---|---|
| `elastic` | `thisisapassword` (in `ranges/elk-base-2022.yml`) | Kibana / Fleet API | `https://<range_ip>.20.1:5601` |
| `admin` (Splunk) | `thisisapassword` (in `ranges/splunk-base-2022.yml`) | Splunk Web | `http://<range_ip>.20.1:8000` |
| `admin` (Wazuh) | `Thisisapassword1-` (in `ranges/wazuh-base-2022.yml`) | Wazuh Dashboard | `https://<range_ip>.20.1` |

---

## Notes

- Scenario identity passwords are defined in `roles/thruntops_ad_content/defaults/main.yml`
- Domain Admin credentials for scenario provisioning come from the Ludus range defaults
