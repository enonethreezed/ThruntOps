---
title: Coverage
layout: default
nav_order: 8
---

# Lab Coverage
{: .no_toc }

Infrastructure, vulnerable states, attack techniques, and detection outcomes available in ThruntOps.
{: .fs-6 .fw-300 }

---

## Infrastructure

| Layer | Component | Status |
|---|---|---|
| SIEM | Elastic Stack + Fleet / Wazuh all-in-one / Splunk Enterprise + UF | Deployable via `siem.sh` |
| Directory | Windows Server 2022 DC — `thruntops.domain` | Deployable via `siem.sh` |
| Endpoint | Windows 11 22H2 workstation (domain member) | Deployable via `siem.sh` |
| Attacker | Kali Linux desktop | Deployable via `siem.sh` |

Deploy validation of the current 2022 baseline is pending.

---

## Vulnerable states

Provisioned by the pinned external [`ludus_ad`](https://github.com/enonethreezed/ThruntOps-vulnerabilities) role. Scenario IDs are validated against the pinned revision by `tests/validate-external-role.sh`.

| Scenario ID | Provisioned state |
|---|---|
| `CRED-ASREP-01` | Account without Kerberos pre-authentication |
| `CRED-KERBEROAST-01` | Service account with harvestable SPN |
| `CRED-DESCRIPTION-01` | Credential text exposed in user `description` |

---

## Techniques

| Technique | Tooling (Kali) | Target | Outcome |
|---|---|---|---|
| AS-REP roasting | `impacket-GetNPUsers` | AS-REP roastable account | Offline crack of the account password |
| Kerberoasting | `impacket-GetUserSPNs` | Service account with SPN | Offline crack of the service password |
| Credential exposure in descriptions | `net user /domain`, BloodHound | Domain user with leaked `description` | Plaintext credential recovery |

---

## Detection outcomes

Each backend should surface the corresponding telemetry:

| Scenario | Elastic | Wazuh | Splunk |
|---|---|---|---|
| AS-REP roast | Kerberos `4768` (pre-auth disabled) | Rule for 4768 without pre-auth | `index=windows` 4768 |
| Kerberoast | Kerberos `4769` (RC4 encryption) | Rule for 4769 RC4 | `index=windows` 4769 |
| Description recon | LDAP read events | LDAP query alerts | LDAP telemetry |

---

## Notes

- Attack surface growth is tracked in the [`ludus_ad`](https://github.com/enonethreezed/ThruntOps-vulnerabilities) scenario catalog
