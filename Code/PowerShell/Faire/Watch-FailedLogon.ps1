<# ================================================================
#  Watch-FailedLogon.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Faire (scheduled watch scripts)
#  Role: Brute-force / lockout alerts (4625, 4740)
#  Runs: Hourly as SYSTEM (Task Scheduler \Faire\)
#  Last Modified: 9/29/2026
# ================================================================#>

<#
.SYNOPSIS
    Alerts on brute force (failed logons per user+source over a threshold) and on any lockout.
.DESCRIPTION
    Reads 4625 (failed logon) and 4740 (lockout) from the Security log for the
    last -WindowMinutes. Groups failures by user + source IP; any group at or
    above -Threshold raises event 110. Every lockout raises event 111.
    Schedule: hourly, as SYSTEM (Security log needs it).
.PARAMETER WindowMinutes
    Look-back window. Default from config (60). Keep it equal to the run interval.
.PARAMETER Threshold
    Failures per user+source that trigger an alert. Default from config (10).
.EXAMPLE
    .\Watch-FailedLogon.ps1 -WindowMinutes 1440 -Threshold 5
    Manual run over the last day with a lower bar.
.NOTES
    Exit 0 = ran clean (alerts or not), 1 = script error (event 199 raised).
    A slow spray under the threshold per window won't trip this; that's what
    the SIEM correlation is for.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 10080)][int]$WindowMinutes,
    [ValidateRange(1, 100000)][int]$Threshold
)

Import-Module (Join-Path $PSScriptRoot 'Faire.psm1') -Force -DisableNameChecking
$cfg = Initialize-Faire -Name 'Watch-FailedLogon'
if (-not $PSBoundParameters.ContainsKey('WindowMinutes')) { $WindowMinutes = [int]$cfg.FailedLogonWindowMinutes }
if (-not $PSBoundParameters.ContainsKey('Threshold'))     { $Threshold     = [int]$cfg.FailedLogonThreshold }

try {
    $events = @(Get-FaireEvent -Id 4625, 4740 -Since (Get-Date).AddMinutes(-$WindowMinutes))
    $fails  = @($events | Where-Object Id -eq 4625)
    $locks  = @($events | Where-Object Id -eq 4740)

    $groups = @($fails | Group-Object { '{0}\{1}|{2}' -f $_.Data.TargetDomainName, $_.Data.TargetUserName, $_.Data.IpAddress } |
                Where-Object Count -ge $Threshold)

    foreach ($g in $groups) {
        $user, $ip = $g.Name -split '\|', 2
        Send-FaireAlert -EventId 110 "Brute force? $($g.Count) failed logons for $user from $ip in $WindowMinutes min"
    }
    foreach ($l in $locks) {
        Send-FaireAlert -EventId 111 "Account locked out: $($l.Data.TargetUserName) (caller: $($l.Data.TargetDomainName)) at $($l.Time)"
    }

    Write-FaireLog "Window $WindowMinutes min: $($fails.Count) failure(s), $($locks.Count) lockout(s), $($groups.Count) group(s) over threshold $Threshold"
    exit 0
}
catch {
    Send-FaireAlert -EventId 199 -Type ERROR "Script failed: $($_.Exception.Message)"
    exit 1
}
