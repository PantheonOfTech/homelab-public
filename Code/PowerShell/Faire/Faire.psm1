<# ================================================================
#  Faire.psm1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Faire (scheduled watch scripts)
#  Role: Shared module: logging, alerts, collectors
#  Runs: Imported by every Faire script
#  Last Modified: 10/12/2026
# ================================================================#>

<#
    Faire.psm1 - shared plumbing for the Faire scheduled watch scripts.
    Irish "faire" = watch, vigil.

    Every script:  Import-Module "$PSScriptRoot\Faire.psm1"
                   $cfg = Initialize-Faire -Name '<ScriptName>'
    then uses Write-FaireLog / Send-FaireAlert.

    Layout (created by Install-Faire.ps1):
      %ProgramData%\Faire\scripts   code + config   SYSTEM/Admins write, Users read
      %ProgramData%\Faire\logs      monthly logs    Users may append
      %ProgramData%\Faire\state     baselines       SYSTEM/Admins only

    Keep this file pure ASCII (Windows PowerShell 5.1 + no BOM = mojibake).
#>

$script:Root     = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Faire'
$script:LogDir   = Join-Path $script:Root 'logs'
$script:StateDir = Join-Path $script:Root 'state'
$script:Source   = 'Faire'
$script:Config   = $null      # cached by Get-FaireConfig; each script run is a fresh process

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Get-FaireConfig {
    <#
    .SYNOPSIS
        Defaults merged with faire.config.json (next to this module).
    .DESCRIPTION
        Any key in the JSON overrides the default; missing keys keep defaults,
        so a partial config file is fine. Read once per process and cached;
        -Refresh re-reads the file.
    .PARAMETER Refresh
        Ignore the cache and re-read faire.config.json.
    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([switch]$Refresh)

    if ($script:Config -and -not $Refresh) { return $script:Config }

    $cfg = [ordered]@{
        FailedLogonWindowMinutes = 60
        FailedLogonThreshold     = 10
        DiskMinFreePercent       = 15
        TempOlderThanDays        = 7
        LogRetentionDays         = 90
        BackupPaths              = @()
        BackupDestination        = '%LOCALAPPDATA%\Faire\Backups'   # not Documents: CFA blocks PowerShell writes there
        BackupKeep               = 14
        WebhookUrl               = ''
    }

    $file = Join-Path $PSScriptRoot 'faire.config.json'
    if (Test-Path -LiteralPath $file) {
        try {
            $json = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            foreach ($p in $json.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
        }
        catch { Write-Warning "faire.config.json unreadable, using defaults: $($_.Exception.Message)" }
    }
    $script:Config = [pscustomobject]$cfg
    $script:Config
}

function Initialize-Faire {
    <#
    .SYNOPSIS
        Call first in every script: names the log, ensures folders, returns config.
    .PARAMETER Name
        Script name; becomes the log file prefix and the alert tag.
    .OUTPUTS
        PSCustomObject (config)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Name)

    $script:Source = $Name
    foreach ($d in $script:LogDir, $script:StateDir) {
        if (-not (Test-Path -LiteralPath $d)) {
            try   { New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null }
            catch { Write-Warning "Can't create $d : $($_.Exception.Message)" }
        }
    }
    Write-FaireLog "Start as $([Environment]::UserName), PowerShell $($PSVersionTable.PSVersion)"
    Get-FaireConfig
}

function Get-FaireStatePath {
    <#
    .SYNOPSIS
        Full path for a named state file in the SYSTEM-only state folder.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    Join-Path $script:StateDir $Name
}

function Write-FaireLog {
    <#
    .SYNOPSIS
        Appends a timestamped line to logs\<Script>_<yyyy-MM>.log and echoes it.
    .PARAMETER Message
        Text to log.
    .PARAMETER Level
        INFO, WARN or ERROR.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $now  = Get-Date
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f $now, $Level, $Message
    $file = Join-Path $script:LogDir ('{0}_{1:yyyy-MM}.log' -f $script:Source, $now)
    try   { Add-Content -LiteralPath $file -Value $line -Encoding UTF8 -ErrorAction Stop -WhatIf:$false -Confirm:$false }
    catch { Write-Warning "Log write failed ($file): $($_.Exception.Message)" }
    Write-Information $line -InformationAction Continue
}

function Send-FaireAlert {
    <#
    .SYNOPSIS
        Raises an alert: log line + Windows Application event + optional webhook.
    .DESCRIPTION
        The event (source "Faire") lands in the Application log, so anything that
        already ships Windows events (Wazuh, WEF, Splunk UF, Sentinel AMA) picks
        it up with no extra config. If WebhookUrl is set in faire.config.json the
        text is also POSTed there: Discord webhook URLs get {"content": ...},
        anything else (ntfy, Gotify-style, custom) gets a plain-text body.
    .PARAMETER Message
        Alert text.
    .PARAMETER EventId
        1-1000. Faire uses 110/111 logons, 120 disk, 130/131 persistence,
        140 backup, 199 script failure.
    .PARAMETER Type
        WARNING, ERROR or INFORMATION.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateRange(1, 1000)][int]$EventId = 100,
        [ValidateSet('WARNING', 'ERROR', 'INFORMATION')][string]$Type = 'WARNING'
    )

    $level = if ($Type -eq 'INFORMATION') { 'INFO' } elseif ($Type -eq 'ERROR') { 'ERROR' } else { 'WARN' }
    Write-FaireLog -Level $level "ALERT $EventId $Message"

    $desc = ("[{0}] {1}" -f $script:Source, $Message) -replace '"', "'"
    if ($desc.Length -gt 30000) { $desc = $desc.Substring(0, 30000) }

    if (Get-Command eventcreate.exe -ErrorAction SilentlyContinue) {
        $null = & eventcreate.exe /T $Type /ID $EventId /L APPLICATION /SO Faire /D $desc 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-FaireLog -Level ERROR "eventcreate exit $LASTEXITCODE (source 'Faire' is registered by Install-Faire.ps1)"
        }
    }

    $url = (Get-FaireConfig).WebhookUrl
    if ($url) {
        $text = "$([Environment]::MachineName) $desc"
        try {
            if ($url -match 'discord(app)?\.com/api/webhooks') {
                $body = @{ content = $text } | ConvertTo-Json
                Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10 | Out-Null
            }
            else {
                Invoke-RestMethod -Uri $url -Method Post -ContentType 'text/plain; charset=utf-8' -Body $text -TimeoutSec 10 | Out-Null
            }
        }
        catch { Write-FaireLog -Level ERROR "Webhook failed: $($_.Exception.Message)" }
    }
}

function Get-FaireEvent {
    <#
    .SYNOPSIS
        Get-WinEvent wrapper: returns [] instead of throwing on "no events", and
        flattens EventData into a Data hashtable.
    .PARAMETER LogName
        Event log name. Default Security.
    .PARAMETER Id
        Event IDs.
    .PARAMETER Since
        Start time.
    .OUTPUTS
        PSCustomObject: Time, Id, Data
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$LogName = 'Security',
        [Parameter(Mandatory)][int[]]$Id,
        [Parameter(Mandatory)][datetime]$Since
    )

    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = $LogName; Id = $Id; StartTime = $Since } -ErrorAction Stop
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return }
        throw
    }
    foreach ($e in $events) {
        $d = @{}
        foreach ($n in ([xml]$e.ToXml()).Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
        [pscustomobject]@{ Time = $e.TimeCreated; Id = $e.Id; Data = $d }
    }
}

function Get-FairePersistence {
    <#
    .SYNOPSIS
        Collects autostart entries: Run keys, Winlogon, Startup folders,
        non-Microsoft scheduled tasks, non-Windows auto services, WMI consumers.
    .OUTPUTS
        PSCustomObject: Type, Location, Name, Command
    .NOTES
        Triage coverage, not Autoruns coverage. Run as SYSTEM/admin for HKLM,
        services and root\subscription.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if ($env:OS -ne 'Windows_NT') { return }
    $new = { param($Type, $Location, $Name, $Command)
             [pscustomobject]@{ Type = $Type; Location = $Location; Name = $Name; Command = "$Command".Trim() } }

    # Run / RunOnce
    $runKeys = foreach ($hive in 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\SOFTWARE') {
        foreach ($leaf in 'Run', 'RunOnce') { "$hive\Microsoft\Windows\CurrentVersion\$leaf" }
    }
    foreach ($k in $runKeys) {
        $key = Get-Item -LiteralPath $k -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($n in $key.GetValueNames()) { & $new 'RunKey' $k $n $key.GetValue($n) }
    }

    # Winlogon: Shell should be explorer.exe and Userinit userinit.exe; anything added is a backdoor
    $wl = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    if ($wl) { foreach ($n in 'Shell', 'Userinit') { & $new 'Winlogon' $wl.Name $n $wl.GetValue($n) } }

    # Startup folders (resolve .lnk targets)
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { Write-Verbose 'WScript.Shell unavailable' }
    foreach ($f in [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup')) {
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { continue }
        foreach ($i in Get-ChildItem -LiteralPath $f -File -Force -ErrorAction SilentlyContinue) {
            if ($i.Name -eq 'desktop.ini') { continue }
            $cmd = $i.FullName
            if ($shell -and $i.Extension -eq '.lnk') {
                try { $l = $shell.CreateShortcut($i.FullName); $cmd = "$($l.TargetPath) $($l.Arguments)" } catch { Write-Verbose "lnk: $($i.Name)" }
            }
            & $new 'StartupFolder' $f $i.Name $cmd
        }
    }

    # Scheduled tasks outside \Microsoft\
    foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue) {
        if ($t.TaskPath -like '\Microsoft\*') { continue }
        foreach ($a in $t.Actions) {
            $exe = if ($a.PSObject.Properties['Execute']) { $a.Execute } else { $null }
            if ($exe) { & $new 'ScheduledTask' $t.TaskPath $t.TaskName "$exe $($a.Arguments)" }
            else      { & $new 'ScheduledTask' $t.TaskPath $t.TaskName "[COM handler $($a.ClassId)]" }
        }
    }

    # Auto-start services outside the Windows folder
    foreach ($s in Get-CimInstance Win32_Service -ErrorAction SilentlyContinue) {
        if ($s.StartMode -ne 'Auto' -or -not $s.PathName) { continue }
        if ($s.PathName -match '(?i)\\Windows\\(System32|SysWOW64)\\') { continue }
        & $new 'Service' 'Win32_Service' $s.Name $s.PathName
    }

    # WMI permanent event consumers
    foreach ($cls in 'CommandLineEventConsumer', 'ActiveScriptEventConsumer') {
        foreach ($c in Get-CimInstance -Namespace 'root\subscription' -ClassName $cls -ErrorAction SilentlyContinue) {
            $cmd = if ($cls -eq 'CommandLineEventConsumer') { $c.CommandLineTemplate }
                   else { "$($c.ScriptingEngine): $($c.ScriptFileName)$($c.ScriptText)" }
            & $new 'WMIConsumer' $cls $c.Name $cmd
        }
    }
}

function Compare-FaireBaseline {
    <#
    .SYNOPSIS
        Diffs current items against a saved JSON baseline, then saves current.
    .DESCRIPTION
        Items are keyed by Type|Location|Name; Command is the compared value.
        First run (no baseline file) just saves and reports nothing, so you
        don't get alerted on everything that already existed.
    .PARAMETER Current
        Items with Type, Location, Name, Command.
    .PARAMETER Path
        Baseline JSON path.
    .OUTPUTS
        PSCustomObject: Change (Added/Changed/Removed), Type, Name, Command, Previous
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Current,
        [Parameter(Mandatory)][string]$Path
    )

    $key = { param($i) '{0}|{1}|{2}' -f $i.Type, $i.Location, $i.Name }
    $first = -not (Test-Path -LiteralPath $Path)

    if (-not $first) {
        # Windows PowerShell 5.1 emits a JSON array as ONE object down the pipeline, so
        # @(... | ConvertFrom-Json) gave a 1-item array holding the whole list. foreach unrolls it.
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw)
        $old = @(foreach ($o in $parsed) { $o })
        $oldIdx = @{}; foreach ($o in $old) { $oldIdx[(& $key $o)] = $o }
        $newIdx = @{}; foreach ($c in $Current) { $newIdx[(& $key $c)] = $c }

        foreach ($k in $newIdx.Keys) {
            $c = $newIdx[$k]
            if (-not $oldIdx.ContainsKey($k)) {
                [pscustomobject]@{ Change = 'Added'; Type = $c.Type; Name = $c.Name; Command = $c.Command; Previous = $null }
            }
            elseif ("$($oldIdx[$k].Command)" -ne "$($c.Command)") {
                [pscustomobject]@{ Change = 'Changed'; Type = $c.Type; Name = $c.Name; Command = $c.Command; Previous = $oldIdx[$k].Command }
            }
        }
        foreach ($k in $oldIdx.Keys) {
            if (-not $newIdx.ContainsKey($k)) {
                $o = $oldIdx[$k]
                [pscustomobject]@{ Change = 'Removed'; Type = $o.Type; Name = $o.Name; Command = $o.Command; Previous = $null }
            }
        }
    }

    ConvertTo-Json -InputObject @($Current) -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8
    if ($first) { Write-FaireLog "Baseline created: $($Current.Count) item(s) -> $Path" }
}

function Remove-FaireOldItem {
    <#
    .SYNOPSIS
        Deletes files older than N days under a folder, never following links.
    .DESCRIPTION
        Manual directory walk that skips junctions/symlinks entirely, so a link
        planted in the target can't redirect deletion elsewhere. Empties old
        folders deepest-first. Shared by temp cleanup and log retention.
    .PARAMETER Path
        Root folder.
    .PARAMETER OlderThanDays
        Age threshold on LastWriteTime.
    .PARAMETER Filter
        File name wildcard. Default *.
    .PARAMETER KeepFolders
        Don't prune empty folders (use for the logs folder).
    .OUTPUTS
        PSCustomObject: Files, FreedMB, Locked
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateRange(0, 36500)][int]$OlderThanDays,
        [string]$Filter = '*',
        [switch]$KeepFolders
    )

    $cutoff  = (Get-Date).AddDays(-$OlderThanDays)
    $reparse = [System.IO.FileAttributes]::ReparsePoint
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $dirs  = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $stack.Push([System.IO.DirectoryInfo]::new($Path))

    while ($stack.Count) {
        $d = $stack.Pop()
        try { $entries = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if ($e.Attributes -band $reparse) { continue }
            if ($e -is [System.IO.DirectoryInfo]) {
                $stack.Push($e)
                if ($e.LastWriteTime -lt $cutoff) { $dirs.Add($e) }
            }
            elseif ($e.LastWriteTime -lt $cutoff -and $e.Name -like $Filter) { $files.Add($e) }
        }
    }

    $freed = 0; $locked = 0; $done = 0
    if ($files.Count -and $PSCmdlet.ShouldProcess($Path, "Remove $($files.Count) file(s) older than $OlderThanDays day(s)")) {
        foreach ($f in $files) {
            try { $len = $f.Length; $f.Delete(); $freed += $len; $done++ } catch { $locked++ }
        }
        if (-not $KeepFolders) {
            foreach ($d in ($dirs | Sort-Object { $_.FullName.Length } -Descending)) {
                try { if (-not $d.EnumerateFileSystemInfos().GetEnumerator().MoveNext()) { $d.Delete() } } catch { $locked++ }
            }
        }
    }
    [pscustomobject]@{ Files = $done; FreedMB = [math]::Round($freed / 1MB, 1); Locked = $locked }
}

Export-ModuleMember -Function Get-FaireConfig, Initialize-Faire, Get-FaireStatePath, Write-FaireLog,
    Send-FaireAlert, Get-FaireEvent, Get-FairePersistence, Compare-FaireBaseline, Remove-FaireOldItem
