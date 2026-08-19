---
title: Coverage
layout: default
nav_order: 10
---

{: .note }
**Fase 1 active:** SIEM agent enrollment on DC01-2022, DC01-SEC, WIN11-22H2-1, WIN11-22H2-2. All other categories below require Fase 2 (ADCS, MSSQL, OPS VMs).

# Lab Coverage
{: .no_toc }

All attack techniques, vulnerability classes, and test scenarios available in ThruntOps.
{: .fs-6 .fw-300 }

---

```mermaid
mindmap
  root((ThruntOps))
    Active Directory
      Credential Reuse
      RDP to DC
      RDP to ADCS
    ADCS / PKI
      ESC1 Enrollee SAN
      ESC2 Any Purpose EKU
      ESC3 Cert Request Agent
      ESC4 Template Write
      ESC5 PKI Object Control
      ESC6 EDITF SubjectAltName
      ESC7 CA Officer
      ESC8 NTLM Relay HTTP
      ESC9 GenericWrite no SAN
      ESC11 NTLM Relay RPC
      ESC13 OID Group Link
      ESC14 Weak Mapping
      ESC15 Schema v1
      ESC16 SecurityExtension Off
    MSSQL
      xp_cmdshell RCE
      NTLM Hash Capture
      DBA to Sysadmin
    Linux PrivEsc ops
      sudo ansible-playbook
      sudo ansible-test
      sudo certbot
      sudo watch
      cap_gdb
    Reverse Shells
      Linux PHP Ruby Python
      Linux Node tclsh Perl
      Windows PowerShell mshta
      Windows certutil cscript wscript
    LOLBins Windows
      Module installed
      Checklist TBD
```

---

## Summary

| Category | Techniques | VM | Docs |
|---|---|---|---|
| **Active Directory** | Credential reuse, RDP to DC, RDP to ADCS | DC01-2022, DC01-SEC, WIN11 | [Vulnerabilities](vulnerabilities.md) |
| **ADCS / PKI** | ESC1–ESC16 | ADCS | [ADCS Attack Paths](adcs.md) |
| **MSSQL** | xp_cmdshell, NTLM capture, DBA→sysadmin | TBD | [MSSQL TTPs](mssql.md) |
| **Linux PrivEsc — ops** | sudo (ansible-playbook, ansible-test, certbot, watch), cap_gdb | ops | [Vulnerabilities](vulnerabilities.md) |
| **Reverse Shells — Linux** | PHP, Ruby, Python, Node.js, tclsh, Perl | ops | [Vulnerabilities](vulnerabilities.md) |
| **Reverse Shells — Windows** | PowerShell, mshta, certutil, cscript, wscript | WIN11 | [Vulnerabilities](vulnerabilities.md) |
| **LOLBins — Windows** | Module installed for user08 on WIN11-22H2-1/2 | WIN11-22H2-1/2 | — |

---

## ADCS Quick Reference

| ESC | Condition | Entry Point |
|---|---|---|
| ESC1 | Enrollee supplies SAN + Client Auth EKU | `domainuser` |
| ESC2 | Any Purpose EKU | `domainuser` |
| ESC3 | Certificate Request Agent EKU | `domainuser` |
| ESC4 | Write permission on template | `domainuser` |
| ESC5 | Control of PKI AD object | `esc5user` |
| ESC6 | EDITF_ATTRIBUTESUBJECTALTNAME2 on CA | `domainuser` |
| ESC7 | ManageCA / ManageCertificates | `esc7_camgr_user`, `esc7_certmgr_user` |
| ESC8 | NTLM relay → ADCS HTTP enrollment | PetitPotam coercion |
| ESC9 | GenericWrite on victim + no SAN security | `domainuser` → `esc9user` |
| ESC11 | NTLM relay → ADCS RPC (ICertPassage) | PetitPotam coercion |
| ESC13 | OID group link escalation | `esc13user` |
| ESC14 | Weak explicit mapping | `domainuser` |
| ESC15 | Schema version 1 SAN bypass | `domainuser` |
| ESC16 | GenericWrite → SecurityExtension disabled | `domainuser` → `esc16user` |

---

## Linux PrivEsc Quick Reference

| Technique | VM | Entry | Target |
|---|---|---|---|
| sudo ansible-playbook | ops | `primary_user06` (no sudo on most) | root shell |
| sudo ansible-test | ops | `primary_user06` | root shell |
| sudo certbot | ops | `primary_user06` | root shell |
| sudo watch | ops | `primary_user06` | root shell |
| cap_gdb | ops | `primary_user06` | root shell (CAP_SETUID) |
