---
title: Vulnerable-AD Matrix
layout: default
nav_order: 14
---

{: .warning }
**Fase 2 — planning only, not implemented.** All scenarios below are exclusively for isolated lab ranges. They must be disabled by default and enabled explicitly in range `role_vars`.

# Vulnerable-AD Scenario Matrix
{: .no_toc }

Implementation matrix for porting [`safebuffer/vulnerable-AD`](https://github.com/safebuffer/vulnerable-AD)'s `vulnad.ps1` into declarative ThruntOps scenarios.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Design Rules

- Keep base users and groups in `ludus_ad_content`; do not generate random identities in any vulnerability role.
- Implement each scenario as its own standalone role. There is no shared `ludus_ad_vulnerable` role — each scenario (or tightly-coupled pair, e.g. the two credential-exposure scenarios) gets its own `roles/ludus_ad_vuln_<scenario>` role with its own `defaults/main.yml`, added independently to a range's `roles:` list.
- Accept explicit users, groups, DNs, passwords, and host names as variables. Do not select targets randomly.
- Validate every configured principal and target object before changing Active Directory.
- Fail on an unmet prerequisite. Do not suppress errors with empty PowerShell `catch` blocks.
- Keep global domain changes opt-in and separate from per-object scenarios.

## Scenario Matrix

| ID | Intentional condition | Source function | Proposed role | Required role variables | Verification |
|---|---|---|---|---|---|
| AD-BASE-01 | Create the named users and groups consumed by later scenarios. This is prerequisite content, not a vulnerability. | `VulnAD-AddADUser`, `VulnAD-AddADGroup` (lines 36-68) | Existing `ludus_ad_content` | `ludus_ad.users`, `ludus_ad.groups` | Query every declared user and group with AD cmdlets. |
| AD-PP-01 | Weak domain password policy: minimum length, complexity, and lockout settings. | `Invoke-VulnAD` (line 227) | `roles/ludus_ad_vuln_password_policy` | `min_password_length`, `complexity_enabled`, `lockout_duration`, `lockout_observation_window` | `Get-ADDefaultDomainPasswordPolicy` matches the configured values. |
| AD-ACL-01 | A low-privilege group receives object-control rights over a higher-privilege group or user. Rights include `GenericAll`, `GenericWrite`, `WriteOwner`, `WriteDACL`, `Self`, and `WriteProperty`. | `VulnAD-BadAcls`, `VulnAD-AddACL` (lines 69-124) | `roles/ludus_ad_vuln_acls` | `acl_rules`: `source_principal`, `target_dn`, `rights`, optional `inheritance` | The target object's DACL contains the requested allow ACE for the source SID. |
| AD-KRB-01 | Service principal with a known lab password and a requestable SPN, enabling Kerberoasting. The source creates managed service accounts; the role must explicitly select a managed service account or a normal user account. | `VulnAD-Kerberoasting` (lines 126-142) | `roles/ludus_ad_vuln_kerberoast` | `kerberoast_accounts`: `name`, `account_type`, `password`, `spns`, optional `enabled` | The selected account type exists, exposes every declared SPN, and authenticates according to the selected account model. |
| AD-ASREP-01 | User has Kerberos pre-authentication disabled and a known lab password. | `VulnAD-ASREPRoasting` (lines 144-151) | `roles/ludus_ad_vuln_asrep_roast` | `asrep_roast_users`: `name`, optional `password` | `DoesNotRequirePreAuth` is true for each declared user. |
| AD-DNS-01 | Explicit user or group membership in `DnsAdmins`. | `VulnAD-DnsAdmins` (lines 153-161) | `roles/ludus_ad_vuln_dnsadmins` | `dnsadmins_members` | `Get-ADGroupMember DnsAdmins` contains each declared principal. |
| AD-CRED-01 | A user password is deliberately stored in the readable `description` attribute. | `VulnAD-PwdInObjectDescription` (lines 163-170) | `roles/ludus_ad_vuln_credentials` | `password_descriptions`: `name`, `password`, optional `description_template` | The account password is set and `Get-ADUser -Properties Description` returns the expected lab value. |
| AD-CRED-02 | Multiple accounts share the same known password for password-spraying and reuse scenarios. | `VulnAD-DefaultPassword`, `VulnAD-PasswordSpraying` (lines 172-189) | `roles/ludus_ad_vuln_credentials` | `shared_passwords`: `users`, `password`, optional `change_password_at_logon` | Each configured account authenticates with the configured shared password. |
| AD-DCSYNC-01 | A declared principal receives the three directory replication extended rights on the domain root. | `VulnAD-DCSync` (lines 191-212) | `roles/ludus_ad_vuln_dcsync` | `dcsync_principals` | The domain-root DACL contains `DS-Replication-Get-Changes`, `DS-Replication-Get-Changes-All`, and `DS-Replication-Get-Changes-In-Filtered-Set` ACEs for the principal SID. |
| AD-SMB-01 | SMB client signing is disabled on a declared Windows host. | `VulnAD-DisableSMBSigning` (lines 214-216) | `roles/ludus_ad_vuln_smb_signing` | `smb_signing_enabled`, optional `target_hosts` | `Get-SmbClientConfiguration` reports both signing settings as disabled. |

`AD-CRED-01` and `AD-CRED-02` share `roles/ludus_ad_vuln_credentials` because both source functions operate on the same object (a user's password/description) — everything else gets its own role.

## Role Interface

There is no single `ludus_ad_vulnerable` role or top-level enable dictionary. Each scenario role defaults to inert (empty list / `enabled: false`) and is opted into a range purely by being present in that VM's `roles:` list in `ranges/*.yml` — the same pattern already used for `ludus_wazuh_agent`, `ludus_sysmon_windows`, etc.

Example — only `ludus_ad_vuln_kerberoast` and `ludus_ad_vuln_dnsadmins` enabled for a given DC:

```yaml
roles:
  - ludus_ad_content
  - ludus_ad_vuln_kerberoast
  - ludus_ad_vuln_dnsadmins
role_vars:
  kerberoast_accounts:
    - name: svc_backup
      account_type: user
      password: "L4bK3rb!"
      spns:
        - "MSSQLSvc/db01.thruntops.domain:1433"
  dnsadmins_members:
    - thruntops\primary_user06
```

Each role's own `defaults/main.yml` ships an empty/disabled default (e.g. `kerberoast_accounts: []`) so adding the role with no `role_vars` override is a no-op. The primary DC should run `ludus_ad_content` before any `ludus_ad_vuln_*` role; host-scoped roles such as `ludus_ad_vuln_smb_signing` are only added to the `roles:` list of the specific Windows VMs they should target.

## Implementation Order

1. `AD-BASE-01`: declare deterministic identities in the range and confirm `ludus_ad_content` creates them.
2. `ludus_ad_vuln_kerberoast`, `ludus_ad_vuln_asrep_roast`, and `ludus_ad_vuln_credentials` (AD-CRED-02): per-account scenarios with no domain-wide ACL changes.
3. `ludus_ad_vuln_acls` and `ludus_ad_vuln_dnsadmins`: explicit privilege-path scenarios.
4. `ludus_ad_vuln_dcsync`, `ludus_ad_vuln_password_policy`, and `ludus_ad_vuln_smb_signing`: high-impact scenarios, added to ranges separately and tested last.

## Non-Goals

- Do not copy the script's random counts, global state, or silent failure handling.
- Do not make domain-wide policy changes merely because another scenario role is present.
- Do not place lab passwords in role defaults; define them in the selected range's `role_vars`.
- Do not consolidate scenario roles back into a single `ludus_ad_vulnerable` role for convenience — the granularity is intentional so ranges can select an exact subset.
