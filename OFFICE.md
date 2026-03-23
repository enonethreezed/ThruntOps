# Office - Architecture and TTP Matrix Proposal

Proposal to add an Office abuse track to ThruntOps, with and without spearphishing, reusing the current infrastructure and minimizing resource impact.

---

## Objective

Cover a category that is currently incomplete in `docs/coverage.md`: Office document execution, payload delivery, credential capture, and user-driven initial access.

The proposal is split into two blocks:

- **Without spearphishing**: the malicious document is distributed through internal shares.
- **With spearphishing**: the document or link is delivered through internal email.

---

## Functional Scope

The expansion should support the following scenarios:

1. Manual opening of malicious documents from SMB shares.
2. VBA macro execution in Word and Excel.
3. Payload delivery through LOLBins already present in the matrix (`powershell`, `mshta`, `wscript`, `cscript`, `certutil`).
4. NTLM capture through documents with remote references.
5. Internal spearphishing campaigns with attachments or links.
6. Follow-on chaining into techniques already present in the lab: AD, LAPS, RDP, WEB, MSSQL, and GitLab.

---

## Proposed Architecture

### 1. Office Clients

Reuse the two existing Windows workstations:

- `WIN11-22H2-1` - primary user endpoint for `thruntops.domain`
- `WIN11-22H2-2` - primary user endpoint for `secondary.thruntops.domain`

Requirement already covered:

- Microsoft Office installed on both systems.

### 2. SMB / NAS Shares on `WEB`

Reuse `WEB` as the SMB file server to avoid introducing a new VM.

Proposed shares:

- `\\WEB\thruntops_docs`
- `\\WEB\secondary_docs`
- `\\WEB\xdomain_docs`

Purpose of each share:

- `thruntops_docs`: internal document exchange for `thruntops.domain`
- `secondary_docs`: internal document exchange for `secondary.thruntops.domain`
- `xdomain_docs`: shared collaboration space between both domains

Suggested structure:

```text
thruntops_docs/
  HR/
  IT/
  Finance/
  Templates/

secondary_docs/
  HR/
  IT/
  Finance/
  Templates/

xdomain_docs/
  Projects/
  Reports/
  Shared-Templates/
```

### 3. Email Service on `gitlab`

Exchange is excluded due to resource cost.

Deploy a lightweight stack on `gitlab`:

- Postfix
- Dovecot
- Roundcube

Recommended model:

- one shared mail service
- two virtual mail domains:
  - `thruntops.domain`
  - `secondary.thruntops.domain`

Minimum required capabilities:

- internal SMTP delivery
- IMAP mailboxes
- Roundcube webmail access
- attachment support
- clickable links in HTML or plain-text emails
- sufficient logging for defensive analysis

### 4. Payload and Linked Document Hosting

No additional web host is strictly required.

Valid options:

- serve content from `gitlab`
- serve content from `ops`
- use SMB paths directly on `WEB`

For a first phase, SMB plus internal email is sufficient.

---

## Identity and Permissions Requirements

### Suggested AD Groups

To control share access more precisely, create dedicated groups.

In `thruntops.domain`:

- `FileShare_Users`
- `XDomain_Docs_RW`
- `XDomain_Docs_RO`

In `secondary.thruntops.domain`:

- `FileShare_Users`
- `XDomain_Docs_RW`
- `XDomain_Docs_RO`

### Recommended ACLs

- `thruntops_docs`: access for the `thruntops` domain
- `secondary_docs`: access for the `secondary` domain
- `xdomain_docs`: explicit access for both domains

Recommended model:

- some users with write access to plant lures
- other users with read-only access to open and consume documents
- avoid giving broad undifferentiated access to `Domain Users` on every share

This supports more realistic representations of:

- legitimate collaboration
- lure staging
- attacker abuse after prior access
- victims who only open documents

---

## Use Cases Without Spearphishing

These scenarios do not require email. The document is placed on a shared resource and the user opens it manually.

### 1. VBA Macro from SMB Share

**Chain:**

```text
Prior access to internal or cross-domain share
  -> copy .docm or .xlsm document
  -> user browses the share
  -> opens the document
  -> macro executes powershell/mshta/wscript
  -> user-context shell
```

**Value:**

- simulates internal abuse without needing mail infrastructure
- chains well into AD, LAPS, WEB, and MSSQL

### 2. Document with Remote Template / SMB Reference

**Chain:**

```text
Office document on share
  -> user opens it
  -> Office attempts to load remote SMB/HTTP resource
  -> NTLM authentication or remote content retrieval
```

**Value:**

- does not depend on macros
- useful for credential capture and outbound traffic detection

### 3. Document with Indirect Payload via LOLBin

**Chain:**

```text
Document with macro
  -> macro invokes certutil/mshta/wscript/cscript
  -> downloads or executes additional payload
  -> user-context shell
```

**Value:**

- reuses Windows techniques already documented
- produces strong endpoint telemetry

---

## Use Cases With Spearphishing

These scenarios add email delivery and user narrative.

### 1. Malicious Attachment with Macro

**Suggested pretexts:**

- HR: payroll update
- IT: new password policy
- Security: access review
- Finance: expense template
- Cross-domain project: quarterly report

**Chain:**

```text
Internal email with .docm/.xlsm attachment
  -> user opens attachment on WIN11
  -> macro executes payload
  -> user-context shell
```

### 2. Email with Link to SMB-hosted Document

**Chain:**

```text
Internal email with link to \\WEB\xdomain_docs\...
  -> user accesses the share
  -> opens SMB-hosted document
  -> macro execution or remote reference trigger
```

**Value:**

- combines mail and NAS in a single technique
- avoids depending only on direct attachments

### 3. Email with Link to Remotely Hosted Document

**Chain:**

```text
Internal email with internal HTTP link
  -> user downloads document
  -> opens it in Office
  -> execution or NTLM capture
```

---

## Proposed Office Technique Matrix

| Category | Technique | Requires Mail | Requires NAS | Primary Goal |
|---|---|---:|---:|---|
| Office | VBA macro in Word | No | Yes | User-context execution |
| Office | VBA macro in Excel | No | Yes | User-context execution |
| Office | Remote template / SMB reference | No | Yes | NTLM capture / remote retrieval |
| Office | Spearphishing with attachment | Yes | No | Initial access |
| Office | Spearphishing with SMB link | Yes | Yes | Initial access / user execution |
| Office | Spearphishing with internal HTTP link | Yes | No | Initial access / retrieval |
| Office | Macro + LOLBin | Optional | Yes | Payload download and execution |

---

## Expected Telemetry and Detections

### On Windows Endpoints

- `WINWORD.EXE` or `EXCEL.EXE` launching:
  - `powershell.exe`
  - `cmd.exe`
  - `mshta.exe`
  - `wscript.exe`
  - `cscript.exe`
  - `certutil.exe`
- writes into `%TEMP%`, `Downloads`, or Office recovery paths
- outbound SMB/HTTP connections after document open

### On `WEB` as SMB Server

- document creation, rename, and read events in shares
- access to `thruntops_docs`, `secondary_docs`, and `xdomain_docs`
- identification of the user who plants the lure and the user who opens it

### On `gitlab` as Mail Platform

- Roundcube logins
- SMTP delivery
- IMAP access
- sender, recipient, subject, attachments, and included links

---

## Fit with the Current Matrix

The Office track should serve as an initial access or user-execution layer, not as an isolated block.

Recommended chains:

### Chain A - Office -> AD / LAPS

```text
Malicious document on share or as email attachment
  -> shell on WIN11
  -> credential theft or user-context foothold
  -> LAPS abuse / lateral movement / RDP
```

### Chain B - Office -> WEB

```text
Malicious document
  -> shell on workstation user
  -> access to WEB via RDP/SMB/recovered credentials
  -> pivot into IIS or MSSQL
```

### Chain C - Office -> GitLab / Secrets / CI

```text
Compromise of workstation used by a GitLab-capable user
  -> credential or session theft
  -> access to repositories / CI
  -> chaining into pipeline poisoning
```

---

## Implementation Phases

### Phase 1 - Without Mail

1. Create the three SMB shares on `WEB`.
2. Define AD groups and ACLs.
3. Create a realistic folder structure.
4. Validate document access from `WIN11-22H2-1` and `WIN11-22H2-2`.
5. Add at least two scenarios:
   - VBA macro
   - remote SMB reference

### Phase 2 - With Mail

1. Deploy `postfix + dovecot + roundcube` on `gitlab`.
2. Create realistic mailboxes and aliases.
3. Validate attachment and internal link delivery.
4. Add spearphishing campaigns.

### Phase 3 - Documentation and Coverage

1. Update `docs/coverage.md`.
2. Add an Office section to `docs/vulnerabilities.md`.
3. Document target users and pretexts.
4. Add Sigma ideas for Office child-process abuse and Office -> SMB/HTTP activity.

---

## Final Recommendation

The Office expansion should rest on two pillars:

- `WEB` as SMB server with three shares (`thruntops_docs`, `secondary_docs`, `xdomain_docs`)
- `gitlab` as lightweight internal mail platform (`postfix + dovecot + roundcube`)

This provides realistic and low-cost coverage for two TTP families currently missing from the matrix:

- Office document abuse without spearphishing
- initial access through internal spearphishing

The first phase can be deployed without mail and already adds immediate value to the matrix.
