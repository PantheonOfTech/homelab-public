<# ================================================================
#  Invoke-TempCleanup.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Faire (scheduled watch scripts)
#  Role: Link-safe user temp cleanup
#  Runs: Sundays 03:00 as user, S4U (Task Scheduler \Faire\)
#  Last Modified: 9/29/2026
# ================================================================#>

<#
.SYNOPSIS
    Deletes files older than N days from the running user's temp folder.
.DESCRIPTION
    Link-safe (never follows junctions/symlinks), per-file age check, prunes
    emptied folders. Cleans the temp folder of whoever runs it, so register it
    as YOUR user, not SYSTEM (SYSTEM's temp is C:\Windows\Temp).
    Schedule: weekly, as your user.
.PARAMETER OlderThanDays
    Default from config (7).
.EXAMPLE
    .\Invoke-TempCleanup.ps1 -WhatIf
.NOTES
    Exit 0 = ran clean, 1 = script error (event 199 raised).
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateRange(0, 3650)][int]$OlderThanDays)

Import-Module (Join-Path $PSScriptRoot 'Faire.psm1') -Force -DisableNameChecking
$cfg = Initialize-Faire -Name 'Invoke-TempCleanup'
if (-not $PSBoundParameters.ContainsKey('OlderThanDays')) { $OlderThanDays = [int]$cfg.TempOlderThanDays }

try {
    $temp = [System.IO.Path]::GetTempPath()
    $r = Remove-FaireOldItem -Path $temp -OlderThanDays $OlderThanDays -WhatIf:$WhatIfPreference
    Write-FaireLog "$temp : removed $($r.Files) file(s), freed $($r.FreedMB) MB, $($r.Locked) locked"
    exit 0
}
catch {
    Send-FaireAlert -EventId 199 -Type ERROR "Script failed: $($_.Exception.Message)"
    exit 1
}
