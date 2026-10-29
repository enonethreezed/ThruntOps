---
title: Project Status
layout: default
nav_order: 9
---

# Project Status

Status snapshot: 2026-10-29. This page distinguishes repository-local checks
from validation that requires a live Ludus deployment. Issue status is tracked
with Beads; the entries below reflect the open/in-progress work items at the
time of this snapshot.

## Current repository

- The checked-in backend profiles are the four-node 2022 AD lab: Elastic,
  Wazuh, and Splunk (`ranges/*-base-2022.yml`).
- The repository contains SIEM server/agent roles, Windows Sysmon collection,
  Kali setup, and the local `thruntops_ad_*` scenario roles.
- `scripts/thruntops-scenarios.py` lists and selectively applies AD and ADCS
  profiles to an already-deployed range. Scenario profiles are opt-in and are
  not enabled by base range deployment.
- Credential-access scenario work `ThruntOps-lrd` is closed. Its ten child
  tasks are closed; BadSuccessor was closed as superseded because the original
  escalation path was patched and the active baseline has no Windows Server
  2025 DC.
- The read-only Splunk/Sysmon collector is
  `scripts/diagnose-splunk-sysmon.ps1`; usage and current findings are in the
  [Splunk backend guide](splunk.md).

Recent repository checks recorded for this work include Python unit tests,
YAML parsing, Ansible Lint, `git diff --check`, and a Jekyll site build. These
checks do not establish live behavior for every backend or scenario.

## Open project work

| Beads issue | Status | Remaining work |
|---|---|---|
| `ThruntOps-on1` | In progress | Track completion of the scenario-application CLI work. The CLI is present in the repository; issue closure/acceptance remains outstanding. |
| `ThruntOps-a14` | Open | Manually verify the Splunk backend architecture and deployment. |
| `ThruntOps-8x2` | Open | Verify cross-repository role name, revision, scenario IDs, and variable alignment. |
| `ThruntOps-9w8` | Open | Complete the full repository static quality-gate task. |
| `ThruntOps-qnx` | Open | Complete final clean deployment review; its criteria prohibit starting a range deployment during that review. |
| `ThruntOps-10r` | Open | Validate the aligned lab and close its dependent validation tasks. |
| `ThruntOps-1ne` | Open | Align AD identity seeding with external scenario principals. |
| `ThruntOps-bzj` | In progress | Rewrite active project documentation. |
| `ThruntOps-cuc` | Open | Repair external role references and ownership descriptions. |
| `ThruntOps-oqc` | In progress | Revalidate the Windows Server 2025 functional-level fix with a live deployment. |
| `ThruntOps-m13` | In progress | Resolve and validate missing Splunk Sysmon events on Windows member hosts. |

## Splunk Sysmon finding

Read-only collections from `tla-ad-win11-22h2-enterprise-x64-1` and
`tla-ad-dc-win2022-server-x64` in range `tla` on 2026-10-29 show:

- Sysmon64 was running and the enabled Sysmon Operational channel contained
  events on both machines. A direct channel read succeeded as elevated
  `domainadmin` on both; this does **not** test Splunk's service token.
- Both had the same channel ACL, including full access for `SYSTEM` and
  `BUILTIN\Administrators`, plus read access for the Event Log Readers SID.
- On WIN11, Splunk UF 10.2.1 ran as `NT SERVICE\SplunkForwarder`; its effective
  Sysmon input was enabled and targeted `index=sysmon`. The log contained
  `errorCode=5` when subscribing. Event Log Readers existed but was empty.
- On the DC, Splunk UF 10.2.1 ran as `LocalSystem`; Event Log Readers was not
  found. No matching subscription errors appeared in the collected logs.
- The Splunk service SID type was `NONE` on both hosts.

The service identity was the key difference. On WIN11, adding
`NT SERVICE\SplunkForwarder` to the existing `Event Log Readers` group and
restarting the service cleared the live failure: `./siem.sh check splunk` then
reported recent Sysmon events from both WIN11 and the DC. No DC changes were
needed. This validates the targeted permission change on the current range.

The latest Ludus deployment log for WIN11 did not contain the corresponding
grant task, even though it exists in the repository role. This indicates the
range used a stale cached `ludus_splunk_uf` role. The live fix is applied, but
future deployments will need the repository role synchronized into Ludus and
validated to ensure the grant is provisioned automatically. The collector did
not modify either host. Its service summary emitted a non-fatal duplicate-
property warning; other commands still captured the service account and SID
type.

Next validation is to synchronize the current repository role for a future
deployment and confirm that it provisions membership automatically. The
current range already has the narrow membership fix; the DC is unchanged.

## Published website

The GitHub Pages site is generated from the Markdown in `docs/`. Publishing the
documentation commit to the repository's configured branch updates the website
through the Pages workflow; a successful local Jekyll build only verifies the
site can be generated locally, not that the remote deployment has completed.
