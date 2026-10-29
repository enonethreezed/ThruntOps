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

The latest read-only collection came from `tla-ad-win11-22h2-enterprise-x64-1`
in range `tla` on 2026-10-29. It confirms:

- Windows 11 22H2 is domain joined; Sysmon64 is running and the Sysmon
  Operational channel is enabled and contains events.
- Splunk Universal Forwarder 10.2.1 is running as
  `NT SERVICE\SplunkForwarder`; the configured Sysmon input is enabled and
  targets `index=sysmon`.
- Splunk's log still reports `errorCode=5` while subscribing to
  `Microsoft-Windows-Sysmon/Operational`.
- The channel ACL grants read access to the `Event Log Readers` group, but that
  group had no members on this workstation. The Splunk service SID type is
  `NONE`.
- A direct event read succeeded in the elevated `domainadmin` session. That
  confirms the channel and its events are readable by that administrator; it
  does **not** test the Splunk service's access token.

This narrows the investigation to how the Splunk service is granted and receives
event-log read access on member machines. It is not yet a verified root-cause
fix. The collector did not modify the host. Its service summary also emitted a
non-fatal duplicate-property warning; the service account and SID type were
available from the other collected commands.

Next validation depends on comparing a domain controller's collector output
and then testing any service-account/group/ACL correction on a disposable or
snapshotted range. Do not treat the administrator read test as proof that the
service can subscribe.

## Published website

The GitHub Pages site is generated from the Markdown in `docs/`. Publishing the
documentation commit to the repository's configured branch updates the website
through the Pages workflow; a successful local Jekyll build only verifies the
site can be generated locally, not that the remote deployment has completed.
