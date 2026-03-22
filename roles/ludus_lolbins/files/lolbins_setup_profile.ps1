# Bootstraps the lolbins module into the current user's PowerShell profile.
# Runs as a logon-triggered scheduled task; $env:USERPROFILE resolves per user.

$profileDir  = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell"
$profileFile = Join-Path $profileDir "Microsoft.PowerShell_profile.ps1"

New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

$existing = Get-Content -Path $profileFile -Raw -ErrorAction SilentlyContinue
if (-not $existing -or $existing -notmatch 'lolbins') {
    Add-Content -Path $profileFile -Value "`nImport-Module lolbins`nUpdate-LOLBinData"
}
