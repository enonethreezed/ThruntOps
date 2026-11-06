---
title: Project Status
icon: fas fa-chart-line
order: 8
---

Status snapshot: 2026-11-06. The three SIEM backends have been checked and the
four-node 2022 lab architecture is ready. Current work expands and improves
Windows telemetry, using the implemented MiniLab components as a reference.
Source-level event arrival is being validated separately from agent and service
health. Issue status is tracked with Beads.

## Current repository

- The checked-in backend profiles are the four-node 2022 AD lab: Elastic,
  Wazuh, and Splunk (`ranges/*-base-2022.yml`).
- The repository contains SIEM server/agent roles, Windows event collection,
  Kali setup, and the local `thruntops_ad_*` scenario roles.
- `scripts/thruntops-scenarios.py` lists and selectively applies AD and ADCS
  profiles to an already-deployed range. Scenario profiles are opt-in and are
  not enabled by base range deployment.
- Credential-access scenario work `ThruntOps-lrd` is closed. Its ten child
  tasks are closed; BadSuccessor was closed as superseded because the original
  escalation path was patched and the active baseline has no Windows Server
  2025 DC.

The checked-in backend profiles share the four-node topology and do not enable
opt-in scenarios. Repository-local quality gates cover Python tests, YAML
lint, Ansible Lint, shell syntax, Markdown links, and the Jekyll build. These
checks complement, but do not replace, live source-level telemetry validation.

## Current phase: telemetry expansion

Active work uses MiniLab as a reference to expand event sources and strengthen
end-to-end validation across Elastic, Wazuh, and Splunk. The immediate focus is
checking that recent events arrive by Windows host and source; additional work
covers audit policy, PowerShell, Defender, DNS, Firewall, and a coverage matrix.

## Published website

The website is published from the `gh-pages` branch. Build the site locally,
sync the contents of `docs/` to the root of `gh-pages` while preserving existing
assets, then push that branch. A successful local Jekyll build alone does not
confirm remote publication.
