---
title: TTP Testing Methodology
icon: fas fa-flask
order: 1
---

# TTP Testing Methodology

This document defines an evidence-driven methodology for testing tactics, techniques, and procedures (TTPs) in ThruntOps. It adapts principles from [Verified IDA](https://github.com/SentineLabs/verified-ida): link claims to current evidence, verify outcomes, retain failures and uncertainty, and make findings reviewable. Verified IDA is a reverse-engineering harness; this document is an adaptation, not an integration or a claim of compatibility.

Use these procedures only in an isolated lab you control. A successful verification establishes what the evidence supports; it does not guarantee that an interpretation is correct.

## Testing cycle

1. Define a specific claim and its acceptance criteria.
2. Verify the current prerequisites and scope.
3. Execute one selected, bounded test.
4. Independently verify the effect, telemetry, and detection.
5. Record results, supporting evidence, failures, and uncertainty.
6. Review the claims and clean up any changes.
7. Preserve the investigation record and repeat when relevant conditions change.

The unit of work is a single TTP check: a specific technique, exercised against a specified target, within a defined time window, with observable acceptance criteria.

## 1. Define the claim

Before execution, record:

- The MITRE ATT&CK technique and sub-technique, where applicable.
- A hypothesis describing the expected behavior.
- The range, scenario, source, target, identities, and components in scope.
- Required initial conditions and how each will be verified.
- The expected effect of the technique and its acceptance criteria.
- The expected telemetry and detection, including data source, query or rule, and time window.
- Cleanup requirements, limitations, and what the test cannot establish.

Example hypothesis: a request for an AS-REP from a lab account without Kerberos preauthentication produces an observable response and generates the telemetry specified for the domain controller. Treat the following as separate claims: the scenario is prepared, the technique produced the expected effect, and the SIEM observed or detected it.

## 2. Verify the initial state

Collect current evidence for each prerequisite before running the test. For the AS-REP example, confirm that the test account exists, its relevant property shows that preauthentication is disabled, the queried domain controller and account belong to the selected range, and the intended event source is active and reaches the SIEM.

Account existence alone does not establish the vulnerable configuration. A failed query or insufficient access makes a prerequisite inconclusive; it does not establish that the condition is absent. Record the source, target, time, and result of each check.

## 3. Execute a bounded test

Run only the selected TTP and record:

- A unique execution identifier and the start and end times with timezone.
- The operator, tool and version, source, destination, and identity used.
- The procedure and parameters needed for reproduction, excluding secrets.
- The tool result and references to generated artifacts.
- Changes to the environment and the cleanup required.

Tool output is evidence of what the tool reported. A success message alone does not prove that the expected effect occurred on the target. Use a snapshot or documented cleanup appropriate to the scenario.

## 4. Verify each layer

Evaluate each layer independently against its own acceptance criteria.

| Layer | Question | Example evidence |
| --- | --- | --- |
| Preparation | Were the prerequisites satisfied? | AD properties collected before execution. |
| Execution | Was the technique attempted? | Tool log, target, and timestamp. |
| Effect | Did the expected behavior occur? | Response or observed target state. |
| Telemetry | Was the behavior recorded? | Original event with host, event identifier, and timestamp. |
| Detection | Did the selected rule or query identify the behavior? | Alert or query result correlated with the run. |
| Cleanup | Was test-created state removed or restored? | Post-cleanup state check or documented snapshot restoration. |

Correlate evidence using timestamps, hosts, accounts, processes, and other available identifiers. Record clock offsets and ingestion delays when relevant. If correlation is insufficient, leave the conclusion inconclusive. A successful execution is not evidence of SIEM detection; a missing alert is not proof of failed detection if the event source, query, or time window could not be verified.

## 5. Assign a status to each layer

| Status | Meaning |
| --- | --- |
| `confirmed` | Available evidence satisfies the defined criterion. |
| `not_observed` | The check completed, but the expected result was not observed within the defined scope and time window. |
| `inconclusive` | Evidence is insufficient to decide, for example because access, telemetry, or correlation is incomplete. |
| `not_run` | The check was omitted or not attempted. |
| `error` | The check could not be completed because of an identified failure. |
| `not_applicable` | The layer does not apply to this test; record the reason. |

Use `not_observed` only when the check itself completed and its observation conditions were adequate. A technique may be confirmed while detection is not observed, or detection may remain inconclusive because ingestion could not be checked. Do not collapse these outcomes into one success or failure.

## 6. Keep an evidence record

Create a reviewable record for every run. The following is an illustrative template, not a real execution:

```yaml
id: "run-2026-001"
technique: "T1558.004"
scenario: "asrep"
hypothesis: "A configured account returns an AS-REP response."
scope:
  range: "lab1"
  source: "kali"
  target: "dc01"
  account: "user.asrep"
time:
  start: "2026-11-06T10:00:00Z"
  end: "2026-11-06T10:05:00Z"
checks:
  preparation:
    status: "confirmed"
    evidence: ["evidence/ad-account-properties.json"]
  execution:
    status: "confirmed"
    evidence: ["evidence/runner.log"]
  effect:
    status: "confirmed"
    evidence: ["evidence/result-metadata.json"]
  telemetry:
    status: "inconclusive"
    evidence: []
    reason: "The event source could not be queried."
  detection:
    status: "not_run"
    evidence: []
    reason: "Telemetry was not available for correlation."
  cleanup:
    status: "not_applicable"
    evidence: []
    reason: "This illustrative test introduced no persistent state."
limitations:
  - "SIEM detection was not verified."
```

For each evidence item, retain its source, collection time, relevant target or run identifier, and a stable reference. Preserve enough context for an independent reviewer to understand the observation and reproduce the check. Restrict access to evidence and avoid recording passwords, hashes, tickets, or private keys when metadata or references suffice. Do not publish sensitive lab artifacts in a public repository.

## 7. Review the conclusion

A reviewer checks that:

1. Every claim has relevant supporting evidence.
2. Evidence corresponds to the selected range, target, and time window.
3. Prerequisites were verified rather than assumed.
4. Execution, effect, telemetry, and detection are distinguished.
5. Failed queries are not treated as negative findings.
6. Uncertainty, limitations, and cleanup are recorded.
7. The conclusion does not exceed what the evidence supports.

Example conclusion:

> The technique's effect was confirmed. Detection remains inconclusive because the event source could not be queried. This test does not establish detection coverage.

Retain failed checks and review findings alongside successful results so that they can be revisited and corrected.

## 8. Maintain the investigation record

Keep a record for each TTP containing the latest execution and scenario version, confirmed claims and evidence, negative and inconclusive results, observed differences between Elastic, Wazuh, and Splunk, open questions, conditions for repetition, and the last review date.

Recheck prior conclusions when the scenario, tools, audit configuration, SIEM ingestion, or detection rules change. Historical records provide context; they do not replace current evidence.

