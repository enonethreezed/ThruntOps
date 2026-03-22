---
title: Sigma & Infection Monkey
layout: default
nav_order: 8
---

# Sigma Rules & Infection Monkey
{: .no_toc }

Detection engineering pipeline using Infection Monkey to generate realistic attack telemetry and Sigma to write portable detection rules.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

{: .note }
**Sigma** — generic SIEM rule format: [sigmahq.github.io](https://sigmahq.github.io) · [github.com/SigmaHQ/sigma](https://github.com/SigmaHQ/sigma)<br>
**Infection Monkey** — automated breach and attack simulation (BAS): [github.com/guardicore/monkey](https://github.com/guardicore/monkey) · [Akamai/Guardicore documentation](https://techdocs.akamai.com/infection-monkey/docs/welcome-infection-monkey)

## Pipeline

```
Intentional vulnerability
  → Infection Monkey simulates the attack or exploitation path
    → SIEM captures telemetry (Elastic / Wazuh / Splunk)
      → Sigma rule written against that telemetry
        → Rule converted to target query language and loaded into SIEM
          → Alert fires on next simulation run ✓
```

---

## Infection Monkey

Infection Monkey is deployed on the **ops** VM (`10.2.50.2`) via Docker Compose and is available at:

```
https://10.2.50.2:5000
```

It runs as a self-hosted Island (C2 server) — agents are launched from the Island and spread through the network using configured exploits and credential attacks.

References:
- Project: [github.com/guardicore/monkey](https://github.com/guardicore/monkey)
- Documentation: [techdocs.akamai.com/infection-monkey/docs/welcome-infection-monkey](https://techdocs.akamai.com/infection-monkey/docs/welcome-infection-monkey)
- Configuration guide: [techdocs.akamai.com/infection-monkey/docs/configuration](https://techdocs.akamai.com/infection-monkey/docs/configuration)
- ATT&CK mapping: [techdocs.akamai.com/infection-monkey/docs/mitre-attack](https://techdocs.akamai.com/infection-monkey/docs/mitre-attack)

### Running a simulation

1. Open `https://10.2.50.2:5000` in a browser (accept the self-signed certificate)
2. Create or load a simulation configuration
3. Set target network scope: `10.2.50.0/24`
4. Seed credentials from the lab user list (`docs/users.md`) to simulate credential reuse and lateral movement
5. Launch the Monkey Island agent and monitor propagation

### Useful simulation scenarios for this lab

| Scenario | Techniques exercised |
|---|---|
| Credential reuse sweep | T1078.002, T1110.004 |
| SMB lateral movement | T1021.002 |
| SSH lateral movement | T1021.004 |
| Network scanning | T1046 |
| Credential collection | T1003, T1555 |

---

## Sigma

**Installation** (on Kali or ops VM):

```bash
pip install sigma-cli
sigma plugin install elasticsearch   # for Elastic
sigma plugin install splunk          # for Splunk
```

### Workflow

#### 1. Run a simulation with Infection Monkey

Configure and launch a simulation targeting `10.2.50.0/24`. Let it run until completion or until the target technique fires.

#### 2. Capture events in the SIEM

Identify events that correspond to the simulated technique:

- Event ID, process name, command line, parent process
- Network connections, registry changes, file writes
- Authentication events (4624, 4625, 4768, 4769)

#### 3. Write the Sigma rule

```yaml
title: Credential Reuse — Domain User Authenticating as Admin
id: <uuid>
status: experimental
description: Detects a domain user account authenticating with the same credentials as a domain admin
references:
  - https://attack.mitre.org/techniques/T1078/002/
author: ThruntOps
date: 2026/03/22
tags:
  - attack.credential_access
  - attack.t1078.002
logsource:
  product: windows
  service: security
detection:
  selection:
    EventID: 4624
    LogonType: 3
    TargetUserName: 'domainadmin'
  filter:
    IpAddress: '127.0.0.1'
  condition: selection and not filter
falsepositives:
  - Legitimate admin activity from workstations
level: high
```

#### 4. Convert to target query language

```bash
# Elastic EQL
sigma convert -t eql -p ecs_windows sigma/rules/credential_reuse.yml

# Splunk SPL
sigma convert -t splunk -p splunk_windows sigma/rules/credential_reuse.yml
```

#### 5. Load into the SIEM

**Elastic:** Import the converted query as a detection rule in Kibana:
**Security → Rules → Create new rule → EQL**

**Splunk:** Create a saved search or correlation search from the converted SPL in the Security Essentials or ES app.

**Wazuh:** Custom rules can be added to `/var/ossec/etc/rules/` on the Wazuh server.

---

## Coverage Matrix

Mapping lab vulnerabilities to MITRE techniques — use these to scope Infection Monkey simulations:

| Vulnerability | MITRE | Simulation target |
|---|---|---|
| Credential reuse (user01 = domainadmin) | T1078.002 | Seed domainadmin hash/password |
| RDP to DC (user02) | T1021.001 | RDP propagation enabled |
| LAPS password read (user03) | T1555 | AD enumeration plugin |
| RDP to ADCS (user04) | T1021.001 + T1649 | RDP propagation to ADCS |
| SSH to GitLab via AD (user05) | T1021.004 | SSH lateral movement |
| Web app SQLi (WEB) | T1190 | HTTP exploitation plugin |
| CI/CD pipeline poisoning (GitLab) | T1195.002 | Manual — push to main branch |

---

## Rule Storage Convention

Sigma rules for this lab live in `sigma/rules/` organised by MITRE tactic:

```
sigma/
  rules/
    credential_access/
      t1078.002_credential_reuse.yml
      t1555_laps_read.yml
    lateral_movement/
      t1021.001_rdp_to_dc.yml
      t1021.001_rdp_to_adcs.yml
      t1021.004_ssh_gitlab.yml
    privilege_escalation/
      t1649_adcs_esc.yml
    initial_access/
      t1190_web_sqli.yml
```

---

## Notes

- Run simulations from the Infection Monkey Island at `https://10.2.50.2:5000` — accessible after lab deploy
- Each simulation run should be preceded by a snapshot (`ludus range snapshot`) so the lab can be restored cleanly
- Sigma rules should be validated against both a positive (simulation run) and a negative (normal activity) to tune false positives before loading into the SIEM
- Infection Monkey generates a full ATT&CK report after each run — use this to cross-reference which techniques fired and which did not
