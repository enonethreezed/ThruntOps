---
title: Kali
layout: default
nav_order: 5
---

# Kali

Every supported ThruntOps range includes one Kali attacker workstation.

| Setting | Value |
|---|---|
| Template | `kali-x64-desktop-template` |
| Hostname | `<range_id>-kali` |
| Address | `10.<range>.20.250` |
| RAM | 4 GB |
| CPUs | 4 |

Kali shares VLAN 20 with the SIEM, domain controller, and Windows workstation.
It is an operator workstation only: range provisioning does not launch attacks,
capture credentials, or execute exploitation workflows.

The Active Directory vulnerability role configures vulnerable directory state
on the domain controller. Tools on Kali are used manually to inspect and test
that state after provisioning.
