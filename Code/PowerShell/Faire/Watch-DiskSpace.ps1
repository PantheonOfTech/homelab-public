<# ================================================================
#  Watch-DiskSpace.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Faire (scheduled watch scripts)
#  Role: Low disk alerts + Faire log retention
#  Runs: Daily 07:00 as SYSTEM (Task Scheduler \Faire\)
#  Last Modified: 9/29/2026
# ================================================================#>

<#
.SYNOPSIS
    Alerts on low free space; also prunes old Faire logs (housekeeping).
.DESCRIPTION
    Raises event 120 for every fixed drive under -MinFreePercent free. Then
    deletes Faire log files older than LogRetentionDays from config (default 90).
    Log pruning lives here because this task runs as SYSTEM, the only account
    allowed to delete in the logs folder.
    Schedule: daily, as SYSTEM.
.PARAMETER MinFreePercent
    Threshold. Default from config (15).
.EXAMPLE
    .\Watch-DiskSpace.ps1 -MinFreePercent 50
    Force an alert to test the pipeline.
.NOTES
    Exit 0 = ran clean, 1 = script error (event 199 raised).
#>
[CmdletBinding()]
param([ValidateRange(1, 99)][int]$MinFreePercent)

Import-Module (Join-Path $PSScriptRoot 'Faire.psm1') -Force -DisableNameChecking
$cfg = Initialize-Faire -Name 'Watch-DiskSpace'
if (-not $PSBoundParameters.ContainsKey('MinFreePercent')) { $MinFreePercent = [int]$cfg.DiskMinFreePercent }

try {
    $checked = 0
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady -or $d.DriveType -ne 'Fixed' -or $d.TotalSize -le 0) { continue }
        $checked++
        $pct = [math]::Round($d.AvailableFreeSpace / $d.TotalSize * 100, 1)
        $gb  = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
        if ($pct -lt $MinFreePercent) {
            Send-FaireAlert -EventId 120 "Low disk: $($d.Name) $pct% free ($gb GB), threshold $MinFreePercent%"
        }
        else {
            Write-FaireLog "$($d.Name) $pct% free ($gb GB)"
        }
    }
    Write-FaireLog "Checked $checked fixed drive(s)"

    $logDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Faire\logs'
    if (Test-Path -LiteralPath $logDir) {
        $r = Remove-FaireOldItem -Path $logDir -OlderThanDays ([int]$cfg.LogRetentionDays) -Filter '*.log' -KeepFolders
        if ($r.Files) { Write-FaireLog "Log retention: removed $($r.Files) file(s) older than $($cfg.LogRetentionDays) days" }
    }
    exit 0
}
catch {
    Send-FaireAlert -EventId 199 -Type ERROR "Script failed: $($_.Exception.Message)"
    exit 1
}
