---
title: Vulnerable-AD Matrix
layout: default
nav_order: 14
---

{: .note }
**Implemented in a separate repository.** AD vulnerability scenarios are provisioned by standalone Ansible roles in [`ThruntOps-vulnerabilities`](https://github.com/enonethreezed/ThruntOps-vulnerabilities) — that repo's own [`ansible/vulnerability-matrix.md`](https://github.com/enonethreezed/ThruntOps-vulnerabilities/blob/main/ansible/vulnerability-matrix.md) is the authoritative, up-to-date scenario list (ID, role, provisioned condition, source). This page is a ThruntOps-side integration summary — do not duplicate scenario design here.

# Vulnerable-AD Scenario Matrix
{: .no_toc }

How ThruntOps wires the AD-vulnerable-scenario roles from `ThruntOps-vulnerabilities` into a range.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Design Rules (confirmed in the external repo)

- One role provisions one intentional condition — no shared `ludus_ad_vulnerable` monolith. This was the original ThruntOps design decision for this matrix, and `ThruntOps-vulnerabilities` implements it: each scenario is its own role under `ansible/roles/`.
- Roles are disabled by omission: nothing changes on a host unless its role is added to that VM's `roles:` list.
- Roles accept explicit users, groups, DNs, passwords, and host names as variables — no random target selection.
- Roles validate every configured principal and target object before changing Active Directory, and fail on an unmet prerequisite rather than silently no-op.
- Windows roles declare a `target_profile` (`windows-legacy-2016` / `windows-standard-2022` / `windows-modern-2025`) so a role never silently applies a legacy condition to a host where the OS or its patches would block it.

## Current AD Role Catalog

25 roles under `ansible/roles/ad_*` in `ThruntOps-vulnerabilities` (as of this writing — check the [external matrix](https://github.com/enonethreezed/ThruntOps-vulnerabilities/blob/main/ansible/vulnerability-matrix.md) for the current, authoritative list):

| Role | Provisioned condition |
|---|---|
| `ad_acl_delegation` | Delegates named `ActiveDirectoryRights` to one principal on one explicit object DN. |
| `ad_adminsdholder_delegation` | Delegates a directory write right on AdminSDHolder. |
| `ad_asrep_roast_user` | Disables Kerberos pre-authentication for explicitly listed users. |
| `ad_credential_reuse` | Sets a declared password on a selected AD user (shares a privileged account's password). |
| `ad_cross_forest_trust` | Adds a declared foreign member to a selected group across an existing trust. |
| `ad_dcsync_delegation` | Delegates the three directory-replication extended rights at the domain root. |
| `ad_default_password` | Resets explicitly listed users to one lab-only password. |
| `ad_dnsadmins_membership` | Adds declared principals to `DnsAdmins`. |
| `ad_gmsa_account` | Creates a GMSA (after verifying the KDS root key) with explicit SPNs/authorized hosts. |
| `ad_gmsa_password_read` | Adds declared principals to a GMSA's managed-password retrieval list. |
| `ad_gpo_write_delegation` | Delegates GPO edit/security-modification rights to a declared principal. |
| `ad_kerberoast_account` | Sets a lab password + requestable SPNs on an existing service account. |
| `ad_laps_read_delegation` | Delegates read access to LAPS password attributes on a computer/OU DN. |
| `ad_password_in_description` | Writes a lab-only value to a user's readable `description` attribute. |
| `ad_password_in_sysvol` | Writes declared lab-only content to a SYSVOL path. |
| `ad_password_spraying` | Resets ≥2 explicitly listed users to one shared lab password. |
| `ad_pre2k_legacy_access` | Adds declared principals to `Pre-Windows 2000 Compatible Access`. |
| `ad_pre2k_machine_account` | Creates a computer account with an explicit legacy lab password. |
| `ad_rdp_adcs` | Adds domain principals to the local RDP group on the ADCS host. |
| `ad_rdp_domain_controller` | Adds domain principals to Remote Desktop Users on a DC. |
| `ad_reset_password_delegation` | Delegates the Reset Password extended right on one target object. |
| `ad_shadow_credentials` | Delegates a directory write right enabling shadow-credentials abuse. |
| `ad_unconstrained_delegation` | Marks a declared computer account for unconstrained delegation. |
| `ad_weak_password_policy` | Sets the default domain password policy to declared weak values. |
| `ad_weak_user_credentials` | Creates absent AD users from a `name`/`password` list. |

ADCS-specific scenarios (`adcs_esc1_...` through `adcs_esc16_...`, plus `adcs_rdp_low_privilege`) live in the same repo and are documented separately in [ADCS Attack Paths](adcs.md).

## Role Interface

Each role defaults to inert and is opted into a range purely by being present in that VM's `roles:` list in `ranges/*.yml` — the same pattern already used for `ludus_wazuh_agent`, `ludus_sysmon_windows`, etc. Variables are role-prefixed scalars/lists (e.g. `ad_kerberoast_account_user`, `ad_kerberoast_account_password`, `ad_kerberoast_account_spns`), not a shared nested dict — see each role's own `README.md` for its exact variables.

Example — only `ad_kerberoast_account` and `ad_dnsadmins_membership` enabled for a given DC:

```yaml
roles:
  - ludus_ad_content
  - ad_kerberoast_account
  - ad_dnsadmins_membership
role_vars:
  ad_kerberoast_account_target_profile: windows-standard-2022
  ad_kerberoast_account_user: svc_backup
  ad_kerberoast_account_password: "L4bK3rb!"
  ad_kerberoast_account_spns:
    - "MSSQLSvc/db01.thruntops.domain:1433"
  ad_dnsadmins_membership_members:
    - thruntops\primary_user06
```

The primary DC should run `ludus_ad_content` (base users/groups) before any scenario role. Host-scoped roles (e.g. `ad_rdp_adcs`) are only added to the specific Windows VMs they target.

## Non-Goals

- Do not design or maintain a parallel scenario list here — `ThruntOps-vulnerabilities` owns that.
- Do not consolidate scenario roles back into a single role for convenience — the granularity lets ranges select an exact subset.
- Do not place lab passwords in role defaults; define them in the selected range's `role_vars`.
