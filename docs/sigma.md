---
title: Sigma & Atomic Tests
layout: default
nav_order: 8
---

# Sigma Rules & Atomic Red Team
{: .no_toc }

Detection engineering pipeline using Atomic Red Team to generate telemetry and Sigma to write portable detection rules.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

{: .note }
**Sigma** — generic SIEM rule format: [sigmahq.github.io](https://sigmahq.github.io) · [github.com/SigmaHQ/sigma](https://github.com/SigmaHQ/sigma)<br>
**Atomic Red Team** — ATT&CK-mapped attack simulations: [atomicredteam.io](https://atomicredteam.io) · [github.com/redcanaryco/atomic-red-team](https://github.com/redcanaryco/atomic-red-team)<br>
**Invoke-AtomicRedTeam** — PowerShell execution framework: [github.com/redcanaryco/invoke-atomicredteam](https://github.com/redcanaryco/invoke-atomicredteam)

## Pipeline

```
Intentional vulnerability
  → Atomic test simulates the attack
    → Elastic captures telemetry
      → Sigma rule written against that telemetry
        → Rule converted to EQL/KQL and loaded into Elastic
          → Alert fires on next test run ✓
```

---

## Atomic Red Team

Invoke-AtomicRedTeam and the full Atomics library are **automatically installed** on both workstations (`WIN11-22H2-1`, `WIN11-22H2-2`) during lab deployment via the `ludus_atomic_red_team` role.

Installation path: `C:\AtomicRedTeam\`
Module auto-loaded via PowerShell profile for all users.

### Running a test

Open PowerShell on a workstation (e.g. via Guacamole at `http://10.2.50.2:8080/guacamole/`) and run:

```powershell
# List all tests for a technique
Invoke-AtomicTest T1078.002 -ShowDetailsBrief

# Run a specific test
Invoke-AtomicTest T1078.002 -TestNumbers 1

# Run and capture output
Invoke-AtomicTest T1078.002 -TestNumbers 1 -LoggingModule Attire-ExecutionLogger

# Clean up after test
Invoke-AtomicTest T1078.002 -TestNumbers 1 -Cleanup
```

---

## Sigma

**Installation** (on Kali or ops VM):

```bash
pip install sigma-cli
sigma plugin install elasticsearch
```

### Workflow

#### 1. Run the atomic test on a workstation

```powershell
Invoke-AtomicTest T1078.002 -TestNumbers 1
```

#### 2. Capture events in Elastic

The Fleet agent ships Windows Event Logs and Sysmon events to Elastic. Identify relevant events:

- Event ID, process name, command line, parent process
- Network connections, registry changes, file writes

#### 3. Write the Sigma rule

```yaml
title: Credential Reuse — Domain User Authenticating as Admin
id: <uuid>
status: experimental
description: Detects a domain user account authenticating with the same credentials as a domain admin
references:
  - https://attack.mitre.org/techniques/T1078/002/
author: ThruntOps
date: 2026/03/20
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

#### 4. Convert to Elastic EQL

```bash
sigma convert -t eql -p ecs_windows sigma/rules/credential_reuse.yml
```

#### 5. Load into Elastic

Import the converted query as a detection rule in Kibana:
**Security → Rules → Create new rule → EQL**

---

## Coverage Matrix

Mapping existing lab vulnerabilities to Atomic test IDs:

| Vulnerability | MITRE | Atomic Test |
|---|---|---|
| Credential reuse (user01 = domainadmin) | T1078.002 | T1078.002-1 |
| RDP to DC (user02) | T1021.001 | T1021.001-1 |
| LAPS password read (user03) | T1555 | T1555.004-1 |
| RDP to ADCS (user04) | T1021.001 + T1649 | T1021.001-1, T1649-1 |
| SSH to GitLab via AD (user05) | T1021.004 | T1021.004-1 |

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
```

---

## Notes

- Run atomic tests from a **workstation** (WIN11-22H2-1 or WIN11-22H2-2) to produce realistic telemetry — accessible via Guacamole
- Each test run should be preceded by a snapshot (`ludus range snapshot`) so the lab can be restored cleanly
- Sigma rules should be validated against both a positive (attack run) and a negative (normal activity) to tune false positives before loading into Elastic
