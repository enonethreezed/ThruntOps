#requires -Version 5.1
<#
.SYNOPSIS
    Collect read-only diagnostics for Splunk Universal Forwarder Sysmon channel access.
.DESCRIPTION
    Run from an elevated PowerShell prompt on each affected Windows host. The
    script does not change service state, configuration, or event-channel ACLs.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PWD ("splunk-sysmon-diagnostics-{0}-{1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

$ErrorActionPreference = 'Continue'
$channel = 'Microsoft-Windows-Sysmon/Operational'
$serviceName = 'SplunkForwarder'
$splunkHome = Join-Path $env:ProgramFiles 'SplunkUniversalForwarder'
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
$transcriptPath = Join-Path $OutputDirectory 'diagnostics.txt'

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    "`r`n===== $Title =====" | Tee-Object -FilePath $transcriptPath -Append
}

function Save-Command {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][scriptblock]$Command
    )
    Write-Section $Title
    try {
        $result = & $Command 2>&1 | Out-String -Width 240
        if ([string]::IsNullOrWhiteSpace($result)) { $result = '(no output)' }
        $result | Tee-Object -FilePath $transcriptPath -Append
    } catch {
        ("ERROR: {0}" -f $_.Exception.Message) | Tee-Object -FilePath $transcriptPath -Append
    }
}

try { Start-Transcript -Path (Join-Path $OutputDirectory 'powershell-transcript.txt') -Force | Out-Null } catch {}

Save-Command 'Collection metadata' {
    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        CollectedAt = (Get-Date).ToString('o')
        User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        IsAdministrator = ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        PowerShell = $PSVersionTable.PSVersion.ToString()
    } | Format-List
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture, LastBootUpTime | Format-List
    Get-CimInstance Win32_ComputerSystem | Select-Object Domain, PartOfDomain, DomainRole | Format-List
}

Save-Command 'SplunkForwarder service, executable and process identity' {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction Stop
    $svc | Select-Object Name, State, StartMode, StartName, ProcessId, PathName, ExitCode, StartName | Format-List
    if ($svc.ProcessId) {
        Get-CimInstance Win32_Process -Filter "ProcessId=$($svc.ProcessId)" |
            Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine | Format-List
    }
    Get-Item (Join-Path $splunkHome 'bin\splunkd.exe') -ErrorAction SilentlyContinue |
        Select-Object FullName, @{Name='Version';Expression={$_.VersionInfo.ProductVersion}}, LastWriteTime | Format-List
    sc.exe qsidtype $serviceName
    sc.exe showsid $serviceName
    sc.exe qprivs $serviceName
}

Save-Command 'Event Log Readers membership and current token groups' {
    Get-LocalGroupMember -Group 'Event Log Readers' -ErrorAction Stop |
        Select-Object Name, ObjectClass, PrincipalSource, SID | Format-Table -AutoSize
    whoami.exe /all
}

Save-Command 'Sysmon channel metadata and channel access descriptor' {
    wevtutil.exe gl $channel
    wevtutil.exe gli $channel
    $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
    $log | Select-Object LogName, IsEnabled, RecordCount, LogMode, LogType, MaximumSizeInBytes, LogFilePath, OwningProviderName, ProviderNames, SecurityDescriptor | Format-List
}

Save-Command 'Direct event-channel read test as the current elevated user' {
    try {
        Get-WinEvent -LogName $channel -MaxEvents 3 -ErrorAction Stop |
            Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message | Format-List
        'Read test: SUCCESS'
    } catch {
        'Read test: FAILED'
        "Exception: $($_.Exception.GetType().FullName)"
        "Message: $($_.Exception.Message)"
        if ($_.Exception.HResult) { 'HRESULT: 0x{0:X8}' -f $_.Exception.HResult }
    }
}

Save-Command 'Splunk effective input and output configuration' {
    $splunk = Join-Path $splunkHome 'bin\splunk.exe'
    if (Test-Path $splunk) {
        & $splunk btool inputs list --debug
        & $splunk btool outputs list --debug
        & $splunk version
    } else {
        "Splunk executable not found at $splunk"
    }
    $localConfig = Join-Path $splunkHome 'etc\system\local\inputs.conf'
    if (Test-Path $localConfig) {
        '--- system/local/inputs.conf ---'
        Get-Content $localConfig
    }
}

Save-Command 'Splunk UF logs mentioning Sysmon, access denied, or WinEventLog (last 7 days)' {
    $logPath = Join-Path $splunkHome 'var\log\splunk'
    if (Test-Path $logPath) {
        $since = (Get-Date).AddDays(-7)
        Get-ChildItem $logPath -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('splunkd.log', 'splunk-winevtlog.log') -and $_.LastWriteTime -ge $since } |
            ForEach-Object {
                Select-String -Path $_.FullName -Pattern 'Sysmon/Operational|WinEventLogChannel|ACCESS_DENIED|errorCode=5|subscribeToEvtChannel' -ErrorAction SilentlyContinue |
                    Select-Object Path, LineNumber, Line
            } | Format-List
    } else {
        "Splunk log directory not found at $logPath"
    }
}

Save-Command 'Sysmon service, provider and latest channel events' {
    Get-CimInstance Win32_Service -Filter "Name='Sysmon64' OR Name='Sysmon'" -ErrorAction SilentlyContinue |
        Select-Object Name, State, StartMode, StartName, PathName, ExitCode | Format-List
    Get-WinEvent -ListProvider 'Microsoft-Windows-Sysmon' -ErrorAction SilentlyContinue |
        Select-Object Name, LogLinks | Format-List
    Get-WinEvent -LogName $channel -MaxEvents 5 -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, ProviderName, LevelDisplayName | Format-Table -AutoSize
}

Save-Command 'Relevant Windows event log errors (last 7 days)' {
    Get-WinEvent -FilterHashtable @{ LogName='Application'; Level=2; StartTime=(Get-Date).AddDays(-7) } -MaxEvents 100 -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'Splunk|Service Control Manager|Sysmon' -or $_.Message -match 'SplunkForwarder|splunk-winevtlog|Sysmon/Operational' } |
        Select-Object TimeCreated, Id, ProviderName, Message | Format-List
}

try { Stop-Transcript | Out-Null } catch {}
$zipPath = "$OutputDirectory.zip"
Compress-Archive -Path (Join-Path $OutputDirectory '*') -DestinationPath $zipPath -Force
Write-Output "Diagnostics saved to: $OutputDirectory"
Write-Output "Archive: $zipPath"
