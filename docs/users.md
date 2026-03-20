---
title: Users
layout: default
nav_order: 3
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
| `domainadmin` | `iFgu¿83¿` | Domain Admin (Ludus default) |
| `domainuser` | `NV#8SL9#` | Domain User (Ludus default) |
| `basicdomainuser` | `Zz5)"8Gf` | Domain User |
| `enterpriseadmin` | `b0"zy/$s93#0pJlS` | Enterprise Admin — forest-wide privileges |
| `pkiadmin` | `L4U8v!P¿` | Domain Admin (PKI) |
| `webdev` | `n4&1Kj@K` | Domain User — Developers group, GitLab maintainer |
| `primary_user01` | `iFgu¿83¿` | Domain User — shares domain admin password ⚠️ |
| `primary_user02` | `OS)O69H"` | Domain User — RDP on DC01-2022 ⚠️ |
| `primary_user03` | `o)@9t7iq` | Domain User — LAPS read on workstations ⚠️ |
| `primary_user04` | `ggA15$y!` | Domain User — RDP access to ADCS (intentional vulnerability) ⚠️ |
| `primary_user05` | `X¿s\|m7C8` | Domain User |
| `primary_user06` | `U34SO/p@` | Domain User |
| `primary_user07` | `n9ro$8=M` | Domain User |
| `primary_user08` | `c7eX@/8N` | Domain User |
| `primary_user09` | `bpR8#8t"` | Domain User |
| `primary_user10` | `o6u8!PF=` | Domain User |

---

## Domain — secondary.thruntops.domain

| User | Password | Type |
|---|---|---|
| `domainadmin` | `Ut2cf7%/` | Domain Admin (Ludus default) |
| `domainuser` | `p0aAQ¿9)` | Domain User (Ludus default) |
| `basicdomainuser` | `FrN1u/1?` | Domain User |
| `secondary_user01` | `Ut2cf7%/` | Domain User — shares domain admin password ⚠️ |
| `secondary_user02` | `G4L4¿/Ff` | Domain User — RDP on DC01-SEC ⚠️ |
| `secondary_user03` | `cqA(&P91` | Domain User — LAPS read on workstations ⚠️ |
| `secondary_user04` | `Xz"c7e7?` | Domain User — RDP access to ADCS (intentional vulnerability) ⚠️ |
| `secondary_user05` | `B@80G(Va` | Domain User |
| `secondary_user06` | `kN&(2V3T` | Domain User |
| `secondary_user07` | `aV%u9¿u5` | Domain User |
| `secondary_user08` | `MV3(i)6F` | Domain User |
| `secondary_user09` | `Ug1$m%b4` | Domain User |
| `secondary_user10` | `snx0"¿C1` | Domain User |

---

## Local (Windows VMs)

| User | Password | Type | Scope |
|---|---|---|---|
| `localuser` | LAPS-managed (workstations) / `ZT4q?%5x` (WEB, ADCS) | Local Admin | All Windows VMs |
| `basicuser` | `H)2?H8vC` | Local User | All Windows VMs |
| `webadmin` | `O5G=S(5q` | Local Admin | WEB only — IIS/wwwroot access |

---

## Services

| User | Password | Service | URL |
|---|---|---|---|
| `elastic` | `thisisapassword` | Kibana / Fleet API | https://10.2.50.1:5601 |
| `kibana_system` | `thisisapassword` | Internal Kibana | — |
| `logstash_system` | `thisisapassword` | Logstash monitoring | — |
| `beats_system` | `thisisapassword` | Beats monitoring | — |
| `apm_system` | `thisisapassword` | APM monitoring | — |
| `remote_monitoring_user` | `thisisapassword` | Metricbeat | — |
| `webdev` | `n4&1Kj@K` | GitLab maintainer (AD credentials via LDAP) | http://10.2.50.15 |

---

## Notes

- ⚠️ marks accounts with intentional vulnerabilities — see [Vulnerabilities](vulnerabilities.md)
- `localuser` on workstations is managed by Windows LAPS — read with `Get-LapsADPassword -Identity <hostname>`
- Elastic service accounts share the password set in `ludus_elastic_password`
- Special characters in passwords are drawn from: `!"$%&/()=?¿@#|`
