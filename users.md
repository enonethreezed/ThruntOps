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

## Fase 1 — Core SIEM

ThruntOps Fase 1 uses Ludus default credentials. No custom user population is deployed.

### Domain — thruntops.domain

| User | Password | Type |
|---|---|---|
| `THRUNTOPS\domainadmin` | `password` | Domain Admin (Ludus default) |
| `THRUNTOPS\domainuser` | `password` | Domain User (Ludus default) |

### Domain — secondary.thruntops.domain

| User | Password | Type |
|---|---|---|
| `SECONDARY\domainadmin` | `password` | Domain Admin (Ludus default) |
| `SECONDARY\domainuser` | `password` | Domain User (Ludus default) |

### Local (all VMs)

| User | Password | Scope |
|---|---|---|
| `localuser` | `password` | Local Admin (Windows) / SSH login (Linux) — template default, all VMs |

### Services

| User | Password | Service | URL |
|---|---|---|---|
| `elastic` | set in `elk-dual.yml` | Kibana / Fleet API | `https://<range_ip>.20.1:5601` |
| `admin` (Splunk) | set in `splunk-dual.yml` | Splunk Web | `http://<range_ip>.20.1:8000` |
| `admin` (Wazuh) | set in `wazuh-dual.yml` | Wazuh Dashboard | `https://<range_ip>.20.1` |

---

## Fase 2 — Extended User Population

{: .note }
**Fase 2 — not yet deployed.** The following user population will be created by `ludus_ad_content` in Fase 2 when vulnerability scenarios are added. Preserved here as implementation reference.

### Domain — thruntops.domain

| User | Password | Notes |
|---|---|---|
| `basicdomainuser` | `Zz5)"8Gf` | Low privilege domain user |
| `enterpriseadmin` | `b0"zy/$s93#0pJlS` | Enterprise Admin — forest-wide privileges |
| `pkiadmin` | `L4U8v!P¿` | Domain Admin (PKI) |
| `webdev` | `n4&1Kj@K` | Domain User — unassigned (was Developers group / GitLab maintainer; GitLab removed from ThruntOps roadmap) |
| `primary_user01` | `iFgu¿83¿` | Domain User — shares domain admin password ⚠️ |
| `primary_user02` | `OS)O69H"` | Domain User — RDP on DC01-2022 ⚠️ |
| `primary_user03` | `o)@9t7iq` | Domain User — unassigned (was LAPS read; LAPS removed from ThruntOps) |
| `primary_user04` | `ggA15$y!` | Domain User — RDP access to ADCS ⚠️ |
| `primary_user05` | `X¿s\|m7C8` | Domain User — unassigned (was SSH + sudo on gitlab VM; GitLab removed from ThruntOps roadmap) |
| `primary_user06` | `U34SO/p@` | Domain User — SSH on ops VM (no sudo) ⚠️ |
| `primary_user07` | `n9ro$8=M` | Domain User — DBA group, sysadmin on MSSQL ⚠️ |
| `primary_user08` | `c7eX@/8N` | Domain User |
| `primary_user09` | `bpR8#8t"` | Domain User |
| `primary_user10` | `o6u8!PF=` | Domain User — SSH + sudo on ops VM |

### Domain — secondary.thruntops.domain

| User | Password | Notes |
|---|---|---|
| `basicdomainuser` | `FrN1u/1?` | Low privilege domain user |
| `secondary_user01` | `Ut2cf7%/` | Domain User — shares domain admin password ⚠️ |
| `secondary_user02` | `G4L4¿/Ff` | Domain User — RDP on DC01-SEC ⚠️ |
| `secondary_user03` | `cqA(&P91` | Domain User — unassigned (was LAPS read; LAPS removed from ThruntOps) |
| `secondary_user04` | `Xz"c7e7?` | Domain User — RDP access to ADCS ⚠️ |
| `secondary_user05` | `B@80G(Va` | Domain User — unassigned (was SSH + sudo on gitlab VM; GitLab removed from ThruntOps roadmap) |
| `secondary_user06` | `kN&(2V3T` | Domain User — unassigned (was SSH on gitlab VM; GitLab removed from ThruntOps roadmap) |
| `secondary_user07` | `aV%u9¿u5` | Domain User — DBA group |
| `secondary_user08` | `MV3(i)6F` | Domain User |
| `secondary_user09` | `Ug1$m%b4` | Domain User |
| `secondary_user10` | `snx0"¿C1` | Domain User — SSH + sudo on ops VM |

### Local (Windows VMs) — Fase 2

| User | Password | Scope |
|---|---|---|
| `basicuser` | `H)2?H8vC` | Local User — workstations |

---

## Notes

- ⚠️ marks accounts with intentional vulnerabilities — see the [vulnerability role matrix](https://github.com/enonethreezed/ThruntOps-vulnerabilities/blob/main/ansible/vulnerability-matrix.md)
- Fase 2 passwords use special characters from: `!"$%&/()=?¿@#|`
