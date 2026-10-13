<# ================================================================
#  Backup-Profile.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Faire (scheduled watch scripts)
#  Role: Profile + config backup with rotation
#  Runs: Daily 21:00 as user, S4U (Task Scheduler \Faire\)
#  Last Modified: 9/29/2026
# ================================================================#>

<#
.SYNOPSIS
    Zips your PowerShell profiles (+ any extra paths) with rotation.
.DESCRIPTION
    Backs up both profile folders' *.ps1 files (Documents\PowerShell and
    Documents\WindowsPowerShell) plus every path in BackupPaths from
    faire.config.json. Environment variables in paths are expanded
    (%USERPROFILE%). Keeps the newest BackupKeep zips, deletes older ones.
    Raises event 140 if the backup fails.
    Schedule: daily, as your user.
.EXAMPLE
    .\Backup-Profile.ps1
.NOTES
    Registered with S4U logon (runs whether you're logged on or not, stores no
    password) which means NO network credentials: point BackupDestination at a
    local disk, or change the task to store your password for a NAS path.
    Exit 0 = ok, 1 = failed.
#>
[CmdletBinding()]
param()

Import-Module (Join-Path $PSScriptRoot 'Faire.psm1') -Force -DisableNameChecking
$cfg = Initialize-Faire -Name 'Backup-Profile'

$stage = $null
try {
    $docs  = [Environment]::GetFolderPath('MyDocuments')
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($d in 'PowerShell', 'WindowsPowerShell') {
        $pd = Join-Path $docs $d
        if (Test-Path -LiteralPath $pd) {
            Get-ChildItem -LiteralPath $pd -Filter *.ps1 -File | ForEach-Object { $paths.Add($_.FullName) }
        }
    }
    foreach ($p in @($cfg.BackupPaths)) {
        if ($p) { $paths.Add([Environment]::ExpandEnvironmentVariables($p)) }
    }

    $dest = [Environment]::ExpandEnvironmentVariables([string]$cfg.BackupDestination)
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    # Stage first: Compress-Archive chokes on files another process has open
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) "faire-backup-$stamp"
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    $copied = 0
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { Write-FaireLog -Level WARN "Missing, skipped: $p"; continue }
        $item   = Get-Item -LiteralPath $p
        $parent = Split-Path -Leaf (Split-Path -Parent $item.FullName)
        $target = Join-Path $stage $parent
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force -ErrorAction Stop
        $copied++
    }
    if (-not $copied) { throw "Nothing to back up." }

    $zip = Join-Path $dest ("Faire-backup_{0}_{1}.zip" -f [Environment]::MachineName, $stamp)
    $ProgressPreference = 'SilentlyContinue'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
    Write-FaireLog ("Backed up {0} item(s) -> {1} ({2:N1} KB)" -f $copied, $zip, ((Get-Item -LiteralPath $zip).Length / 1KB))

    $old = Get-ChildItem -LiteralPath $dest -Filter 'Faire-backup_*.zip' -File |
           Sort-Object LastWriteTime -Descending | Select-Object -Skip ([int]$cfg.BackupKeep)
    foreach ($o in $old) { Remove-Item -LiteralPath $o.FullName -Force; Write-FaireLog "Rotated out $($o.Name)" }
    exit 0
}
catch {
    Send-FaireAlert -EventId 140 -Type ERROR "Backup failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}
