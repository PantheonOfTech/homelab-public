<# ================================================================
#  Watch-Persistence.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Faire (scheduled watch scripts)
#  Role: Autostart baseline + change alerts
#  Runs: Every 4h as SYSTEM (Task Scheduler \Faire\)
#  Last Modified: 9/29/2026
# ================================================================#>

<#
.SYNOPSIS
    Baselines autostart locations and alerts when anything is added or changed.
.DESCRIPTION
    Collects Run keys, Winlogon, Startup folders, non-Microsoft scheduled tasks,
    non-Windows auto services and WMI consumers (Get-FairePersistence), diffs
    against the last run, and saves the new state.
      Added / Changed -> event 130 (WARNING), one per item
      Removed         -> event 131 (INFORMATION)
    First run only builds the baseline.
    Schedule: every 4 hours, as SYSTEM.
.PARAMETER Rebaseline
    Throw away the old baseline and start fresh (after installing software you trust).
.EXAMPLE
    .\Watch-Persistence.ps1 -Rebaseline
.NOTES
    The baseline lives in state\ which only SYSTEM/Admins can write, so a normal
    user (or malware running as one) can't quietly bless its own entry.
    Anything already running as admin can, which is why the alerts also go to
    the event log for off-box collection.
    Exit 0 = ran clean, 1 = script error (event 199 raised).
#>
[CmdletBinding()]
param([switch]$Rebaseline)

Import-Module (Join-Path $PSScriptRoot 'Faire.psm1') -Force -DisableNameChecking
$null = Initialize-Faire -Name 'Watch-Persistence'

try {
    $state = Get-FaireStatePath 'persistence.json'
    if ($Rebaseline -and (Test-Path -LiteralPath $state)) {
        Remove-Item -LiteralPath $state -Force
        Write-FaireLog 'Rebaseline requested; old baseline removed'
    }

    $current = @(Get-FairePersistence)
    $changes = @(Compare-FaireBaseline -Current $current -Path $state)

    $max = 25
    $i = 0
    foreach ($c in ($changes | Where-Object Change -ne 'Removed')) {
        if (++$i -gt $max) { break }
        $msg = "$($c.Change) $($c.Type) '$($c.Name)': $($c.Command)"
        if ($c.Change -eq 'Changed') { $msg += " (was: $($c.Previous))" }
        Send-FaireAlert -EventId 130 $msg
    }
    if ($i -gt $max) { Send-FaireAlert -EventId 130 "...and more: $($changes.Count) total changes, see state\persistence.json" }

    foreach ($c in ($changes | Where-Object Change -eq 'Removed')) {
        Send-FaireAlert -EventId 131 -Type INFORMATION "Removed $($c.Type) '$($c.Name)': $($c.Command)"
    }

    Write-FaireLog "$($current.Count) autostart item(s), $($changes.Count) change(s)"
    exit 0
}
catch {
    Send-FaireAlert -EventId 199 -Type ERROR "Script failed: $($_.Exception.Message)"
    exit 1
}
