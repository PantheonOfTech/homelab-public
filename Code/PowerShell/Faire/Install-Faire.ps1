<# ================================================================
#  Install-Faire.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Faire (scheduled watch scripts)
#  Role: Installer: files, ACLs, event source, tasks
#  Runs: Manually, elevated
#  Last Modified: 9/30/2026
# ================================================================#>

<#
.SYNOPSIS
    Installs Faire: copies scripts to %ProgramData%\Faire, locks down ACLs,
    registers the event source, and creates the scheduled tasks under \Faire\.
.DESCRIPTION
    Safe to re-run: code is refreshed, tasks are overwritten, your existing
    faire.config.json is never replaced.

    Tasks created:
      Faire-FailedLogon    hourly           SYSTEM
      Faire-Persistence    every 4 hours    SYSTEM
      Faire-DiskSpace      daily 07:00      SYSTEM   (+ log retention)
      Faire-TempCleanup    Sundays 03:00    -User    (S4U, no stored password)
      Faire-Backup         daily 21:00      -User    (S4U, no stored password)

    Why the ACL step matters: these scripts run as SYSTEM. If a normal user
    could edit them, that user could get SYSTEM by editing a file and waiting.
    scripts\ and state\ are therefore writable by SYSTEM + Administrators only.
.PARAMETER User
    Account for the user-context tasks. Default: you.
.PARAMETER Uninstall
    Remove the \Faire\ tasks. Files are left in place for you to review.
.EXAMPLE
    .\Install-Faire.ps1
.EXAMPLE
    .\Install-Faire.ps1 -WhatIf
.EXAMPLE
    .\Install-Faire.ps1 -Uninstall
.NOTES
    Uses pwsh 7 if installed, else Windows PowerShell 5.1. Built-in principals
    are referenced by SID in icacls so it works on non-English Windows.
#>
#Requires -RunAsAdministrator
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$User = "$env:USERDOMAIN\$env:USERNAME",
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$root     = Join-Path $env:ProgramData 'Faire'
$scripts  = Join-Path $root 'scripts'
$logs     = Join-Path $root 'logs'
$state    = Join-Path $root 'state'
$taskPath = '\Faire\'

if ($Uninstall) {
    $tasks = @(Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue)
    foreach ($t in $tasks) {
        if ($PSCmdlet.ShouldProcess($t.TaskName, 'Unregister task')) {
            Unregister-ScheduledTask -TaskPath $taskPath -TaskName $t.TaskName -Confirm:$false
        }
    }
    Write-Host "Removed $($tasks.Count) task(s). Files remain in $root." -ForegroundColor Green
    return
}

# 1. Folders + code
foreach ($d in $scripts, $logs, $state) {
    if (-not (Test-Path -LiteralPath $d) -and $PSCmdlet.ShouldProcess($d, 'Create folder')) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}
$code = 'Faire.psm1', 'Watch-FailedLogon.ps1', 'Watch-DiskSpace.ps1', 'Watch-Persistence.ps1',
        'Invoke-TempCleanup.ps1', 'Backup-Profile.ps1'
foreach ($f in $code) {
    $src = Join-Path $PSScriptRoot $f
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing $f next to the installer." }
    if ($PSCmdlet.ShouldProcess($f, "Copy to $scripts")) { Copy-Item -LiteralPath $src -Destination $scripts -Force }
}
$cfgDest = Join-Path $scripts 'faire.config.json'
if (-not (Test-Path -LiteralPath $cfgDest) -and $PSCmdlet.ShouldProcess('faire.config.json', 'Copy default config')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'faire.config.json') -Destination $cfgDest
}

# 2. ACLs (SIDs: S-1-5-18 SYSTEM, S-1-5-32-544 Administrators, S-1-5-32-545 Users)
$acl = @{
    $scripts = @('*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX')
    $state   = @('*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
    $logs    = @('*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)(RX,W)')
}
foreach ($d in $acl.Keys) {
    if ($PSCmdlet.ShouldProcess($d, 'Replace ACL')) {
        $grants = foreach ($g in $acl[$d]) { '/grant:r'; $g }
        & icacls.exe $d @grants /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls grant failed on $d (exit $LASTEXITCODE)" }
        & icacls.exe $d /inheritance:r /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls inheritance failed on $d (exit $LASTEXITCODE)" }
        if (Get-ChildItem -LiteralPath $d -Force) { & icacls.exe (Join-Path $d '*') /reset /T /C /Q | Out-Null }
        if ($LASTEXITCODE -ne 0) { throw "icacls failed on $d (exit $LASTEXITCODE)" }
    }
}

# 3. Event source (must be created by an admin once)
if ($PSCmdlet.ShouldProcess('Application log', "Register event source 'Faire'")) {
    & eventcreate.exe /T INFORMATION /ID 1 /L APPLICATION /SO Faire /D "Faire installed/updated" | Out-Null
}

# 4. Scheduled tasks
$exe = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'   # MSI pwsh only; Store pwsh (WindowsApps alias) breaks SYSTEM tasks
if (-not (Test-Path -LiteralPath $exe)) { $exe = $null }
if (-not $exe) { $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
                -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$system   = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$me       = New-ScheduledTaskPrincipal -UserId $User -LogonType S4U -RunLevel Limited
$nextHour = (Get-Date).Date.AddHours((Get-Date).Hour + 1)

$tasks = @(
    @{ Name = 'Faire-FailedLogon'; Script = 'Watch-FailedLogon.ps1';  Principal = $system
       Trigger = New-ScheduledTaskTrigger -Once -At $nextHour -RepetitionInterval (New-TimeSpan -Hours 1) }
    @{ Name = 'Faire-Persistence'; Script = 'Watch-Persistence.ps1';  Principal = $system
       Trigger = New-ScheduledTaskTrigger -Once -At $nextHour -RepetitionInterval (New-TimeSpan -Hours 4) }
    @{ Name = 'Faire-DiskSpace';   Script = 'Watch-DiskSpace.ps1';    Principal = $system
       Trigger = New-ScheduledTaskTrigger -Daily -At '07:00' }
    @{ Name = 'Faire-TempCleanup'; Script = 'Invoke-TempCleanup.ps1'; Principal = $me
       Trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:00' }
    @{ Name = 'Faire-Backup';      Script = 'Backup-Profile.ps1';     Principal = $me
       Trigger = New-ScheduledTaskTrigger -Daily -At '21:00' }
)

foreach ($t in $tasks) {
    $file   = Join-Path $scripts $t.Script
    $action = New-ScheduledTaskAction -Execute $exe -WorkingDirectory $scripts `
                -Argument "-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File `"$file`""
    if ($PSCmdlet.ShouldProcess("$taskPath$($t.Name)", 'Register task')) {
        Register-ScheduledTask -TaskPath $taskPath -TaskName $t.Name -Action $action -Trigger $t.Trigger `
            -Principal $t.Principal -Settings $settings -Description "Faire: $($t.Script)" -Force | Out-Null
        Write-Host "  registered $($t.Name)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Faire installed to $root using $exe" -ForegroundColor Cyan
Write-Host "Test one now:  Start-ScheduledTask -TaskPath '$taskPath' -TaskName Faire-DiskSpace" -ForegroundColor DarkGray
Write-Host "Then check:    faire   (from your profile)" -ForegroundColor DarkGray
