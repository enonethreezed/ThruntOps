---
title: Project Status
layout: default
nav_order: 12
---

# Project Status

Status snapshot: 2026-11-05. This page distinguishes repository-local checks
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

Repository-local quality gates pass: Python tests, YAML lint, Ansible Lint,
shell syntax checks, Markdown link checks, `git diff --check`, and a Jekyll site
build. Structural checks confirm that the three checked-in backend profiles
share the four-node topology and do not enable opt-in scenarios. The scenario
catalog, exploit runner, and vulnerability ledger align across the ThruntOps
and ThruntOpsExploits repositories. Static checks do not establish live
behavior for every backend or scenario.

## Open project work

| Beads issue | Status | Remaining work |
|---|---|---|
| `ThruntOps-m13` | In progress | Validate the Splunk Universal Forwarder Sysmon channel-access fix on Windows member hosts. A live deployment/validation is currently underway; results are not yet confirmed. |

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
grant task, even though it exists in the repository role. This indicated that
the observed range used a stale cached `ludus_splunk_uf` role. At that time, the
live fix was applied manually and confirmed. A new deployment and validation is
now underway to check that the repository role provisions the membership
automatically; its result is pending. The read-only collector did not modify
either host. Its service summary emitted a non-fatal duplicate-property
warning; other commands still captured the service account and SID type.

## Published website

The website is published from the `gh-pages` branch. Build the site locally,
sync the contents of `docs/` to the root of `gh-pages` while preserving existing
assets, then push that branch. A successful local Jekyll build alone does not
confirm remote publication.
