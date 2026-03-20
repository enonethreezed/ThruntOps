# ThruntOps

A Ludus-based lab environment for TTP testing and security research.

## Purpose

ThruntOps exists to provide a controlled environment for testing attack techniques and procedures (TTPs). The design philosophy is breadth over depth: rather than optimizing for a single attack scenario, the lab grows by adding technologies — each one introducing new attack surfaces, protocols, and vectors to test against.

## Current Architecture

Deployed on Proxmox via [Ludus](https://docs.ludus.cloud). All VMs run on VLAN 50 (`10.2.50.0/24`).

| IP | Hostname | Role |
|---|---|---|
| 10.2.50.1 | elastic | SIEM — Elastic Stack + Fleet |
| 10.2.50.11 | DC01-2022 | Primary DC — `thruntops.domain` |
| 10.2.50.12 | DC01-SEC | Primary DC — `secondary.thruntops.domain` |
| 10.2.50.13 | ADCS | Certificate Authority — `thruntops.domain` |
| 10.2.50.21 | WIN11-22H2-1 | Workstation — `thruntops.domain` |
| 10.2.50.22 | WIN11-22H2-2 | Workstation — `secondary.thruntops.domain` |
| 10.2.50.250 | kali | Attacker |
| 10.2.50.254 | router | Router / DNS |

## Users

| User | Password | Type | Scope |
|---|---|---|---|
| `domainadmin` | `password` | Domain Admin | thruntops.domain |
| `domainadmin` | `password` | Domain Admin | secondary.thruntops.domain |
| `domainuser` | `password` | Domain User | thruntops.domain |
| `domainuser` | `password` | Domain User | secondary.thruntops.domain |
| `basicdomainuser` | `password` | Domain User | thruntops.domain |
| `basicdomainuser` | `password` | Domain User | secondary.thruntops.domain |
| `pkiadmin` | `password` | Domain Admin | thruntops.domain (PKI) |
| `localuser` | `password` | Local Admin | all Windows VMs |
| `basicuser` | `password` | Local User | all Windows VMs |
| `elastic` | `thisisapassword` | Service Account | Kibana / Fleet API |

All users have RDP access on the machines they belong to.

## Attack Surface

| Technology | Vectors |
|---|---|
| Active Directory (dual domain) | Kerberoasting, AS-REP roasting, ACL abuse, lateral movement, trust abuse |
| ADCS | ESC1–ESC16 certificate template misconfigurations |
| Elastic SIEM | Detection engineering, alert tuning, log analysis |

## Roadmap

- Vulnerable web application covering OWASP Top 10
