<# ================================================================
#  Seala.psm1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Seala (Irish: seal)
#  Role: Module: Set-ScriptHeader (alias seala)
#  Runs: On demand; autoloads from Program Files module path
#  Last Modified: 2026-10-12 17:30 CDT
#  Changelog (newest first):
#    2026-10-12 17:30 CDT - v1.2.0: owner comes from SEALA_OWNER, git user.name, or the login name (no longer hard-coded)
#    2026-10-03 18:39 CDT - v1.1.1: verify write on disk, report FAILED instead of false success; clearer -WhatIf wording
#    2026-10-03 17:19 CDT - Canonical field order (Company, Suite, Role, Runs)
#    2026-10-03 17:18 CDT - Converted from Seala.ps1 to module (v1.1.0)
#    2026-10-03 16:40 CDT - Initial version (v1.0)
# ================================================================#>

Set-StrictMode -Version 2

# Name stamped on the IP line. Pin it with $env:SEALA_OWNER; otherwise git's user.name,
# then the login name. Resolved once, when the module loads.
$Owner = "$env:SEALA_OWNER".Trim()
if (-not $Owner -and (Get-Command git -ErrorAction SilentlyContinue)) { $Owner = "$(git config --get user.name 2>$null)".Trim() }
if (-not $Owner) { $Owner = [Environment]::UserName }
$Rule      = '=' * 64
$Exts      = '.ps1', '.psm1', '.psd1'

# Matches an existing header block (anchored at start of text).
$RxHeader = '(?s)\A\s*<#\s*=+[ \t]*\r?\n####\s+Intellectual Property of[^\r\n]*\r?\n(?<body>.*?)\r?\n#?\s*=+\s*#>[ \t]*(?:\r?\n)*'

function Get-Stamp {
    $now  = Get-Date
    $tz   = [TimeZoneInfo]::Local
    $name = if ($tz.IsDaylightSavingTime($now)) { $tz.DaylightName } else { $tz.StandardName }
    $abbr = if ($tz.Id -in 'UTC', 'Etc/UTC') { 'UTC' }
            elseif ($name -match '\s') { -join ($name -split '\s+' | ForEach-Object { $_[0] }) }
            else { $name }
    '{0:yyyy-MM-dd HH:mm} {1}' -f $now, $abbr.ToUpper()
}

function Read-Text ([string]$File) {
    $bytes = [IO.File]::ReadAllBytes($File)
    $skip  = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = New-Object Text.UTF8Encoding($true, $true); $skip = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $enc = New-Object Text.UnicodeEncoding($false, $true); $skip = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $enc = New-Object Text.UnicodeEncoding($true, $true); $skip = 2
    }
    else {
        $enc = New-Object Text.UTF8Encoding($false, $true)   # throws on invalid bytes (ANSI)
    }
    [pscustomobject]@{
        Text     = $enc.GetString($bytes, $skip, $bytes.Length - $skip)
        Encoding = $enc
    }
}

function ConvertFrom-Header ([string]$Body) {
    # Returns ordered field map + changelog entries from an existing header body.
    $fields = [ordered]@{}
    $log    = New-Object System.Collections.Generic.List[string]
    $inLog  = $false
    foreach ($line in ($Body -split '\r?\n')) {
        if ($line -match '^#+\s+Do Not Copy' -or $line -match '^#\s+\S+ for ') { continue }
        if ($line -match '^#\s+Changelog\b') { $inLog = $true; continue }
        if ($inLog -and $line -match '^#\s{3,}(\S.*?)\s*$') { $log.Add($Matches[1]); continue }
        if ($line -match '^#\s+([^:]+?):\s*(.*?)\s*$') {
            $inLog = $false
            $fields[$Matches[1]] = $Matches[2]
        }
    }
    [pscustomobject]@{ Fields = $fields; Log = $log }
}

function Build-Header ([string]$Name, $Fields, [string[]]$Log, [string]$Stamp, [string]$NL) {
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("<# $Rule")
    $out.Add("####   Intellectual Property of $Owner ####")
    $out.Add('#####           Do Not Copy without Consent      #####')
    $out.Add("#  $Name for $Owner")
    foreach ($k in $Fields.Keys) {
        if ($k -eq 'Last Modified') { continue }
        $out.Add(("#  {0}: {1}" -f $k, $Fields[$k]).TrimEnd())
    }
    $out.Add("#  Last Modified: $Stamp")
    $out.Add('#  Changelog (newest first):')
    foreach ($e in $Log) { $out.Add("#    $e") }
    $out.Add("# $Rule#>")
    ($out -join $NL) + $NL + $NL
}

function Resolve-Target ([string]$Item, [bool]$Recurse) {
    if (-not (Test-Path -LiteralPath $Item)) { Write-Warning "Not found: $Item"; return }
    $obj = Get-Item -LiteralPath $Item
    if ($obj.PSIsContainer) {
        Get-ChildItem -LiteralPath $obj.FullName -File -Recurse:$Recurse |
            Where-Object { $Exts -contains $_.Extension.ToLower() }
    }
    elseif ($Exts -contains $obj.Extension.ToLower()) { $obj }
    else { Write-Verbose "Skipped (not PowerShell): $($obj.FullName)" }
}

function Set-ScriptHeader {
    <#
    .SYNOPSIS
        Applies or updates the standard header block on PowerShell files (alias: seala).

    .DESCRIPTION
        New file     : inserts the header at the top (below a shebang if present).
        Has a header : refreshes the IP lines and file name, bumps Last Modified,
                       prepends a changelog entry, trims the changelog to -MaxChangelog.
        The owner on the IP line comes from $env:SEALA_OWNER, else git user.name, else
        the login name. Existing field values (Company, Suite, Role, Runs, any custom field) are kept
        unless overridden by a parameter. Encoding, BOM and line endings are preserved.

        Skips: non-PowerShell files, invalid UTF-8 (ANSI) files, signed scripts
        (unless -Force, since editing voids the signature).

    .PARAMETER Path
        Files or folders. Folders are scanned for .ps1 / .psm1 / .psd1.

    .PARAMETER Note
        Changelog entry text. Defaults to 'Header added' or 'Modified'.

    .PARAMETER MaxChangelog
        Number of changelog entries to keep (rolling). Default 10.

    .PARAMETER Backup
        Write <file>.bak before changing a file.

    .EXAMPLE
        seala .\Get-Thing.ps1 -Role 'Inventory pull' -Note 'Initial version'

    .EXAMPLE
        seala .\scripts -Recurse -WhatIf

    .EXAMPLE
        git diff --name-only | seala -Note 'Fix null handling'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string[]]$Path,

        [string]$Note,
        [string]$Company,
        [string]$Suite,
        [string]$Role,
        [string]$Runs,

        [ValidateRange(1, 100)]
        [int]$MaxChangelog = 10,

        [switch]$Recurse,
        [switch]$Backup,
        [switch]$Force
    )

    begin {
        $Overrides = @{}
        foreach ($k in 'Company', 'Suite', 'Role', 'Runs') {
            if ($PSBoundParameters.ContainsKey($k)) { $Overrides[$k] = $PSBoundParameters[$k] }
        }
    }

    process {
        foreach ($item in $Path) {
            foreach ($file in (Resolve-Target $item $Recurse.IsPresent)) {
                $result = [pscustomobject]@{ Action = 'Skipped'; Stamp = $null; Path = $file.FullName }

                try { $src = Read-Text $file.FullName }
                catch {
                    Write-Warning "Skipped (not valid UTF-8/UTF-16, re-save as UTF-8): $($file.FullName)"
                    $result; continue
                }
                $text = $src.Text

                if ($text -match '(?m)^# SIG # Begin signature block' -and -not $Force) {
                    Write-Warning "Skipped (signed; -Force to edit and void signature): $($file.FullName)"
                    $result; continue
                }

                $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }

                $shebang = ''
                if ($text -match '\A#![^\n]*\n') { $shebang = $Matches[0]; $text = $text.Substring($shebang.Length) }

                $stamp = Get-Stamp
                $m     = [regex]::Match($text, $RxHeader)

                if ($m.Success) {
                    $parsed = ConvertFrom-Header $m.Groups['body'].Value
                    $fields = $parsed.Fields
                    $log    = $parsed.Log
                    $rest   = $text.Substring($m.Length)
                    $entry  = if ($Note) { $Note } else { 'Modified' }
                    $action = 'Updated'
                }
                else {
                    $fields = [ordered]@{ Company = '' }
                    $log    = New-Object System.Collections.Generic.List[string]
                    $rest   = $text.TrimStart("`r", "`n")
                    $entry  = if ($Note) { $Note } else { 'Header added' }
                    $action = 'Added'

                    if ($rest -match '(?s)\A(?:[ \t]*#Requires[^\n]*\n\s*)+<#') {
                        Write-Warning "#Requires sits above the help block; move it to just above param() or Get-Help breaks: $($file.FullName)"
                    }
                }

                if (-not $fields.Contains('Company')) { $fields.Insert(0, 'Company', '') }
                foreach ($k in 'Company', 'Suite', 'Role', 'Runs') {
                    if ($Overrides.ContainsKey($k)) { $fields[$k] = $Overrides[$k] }
                }

                # Canonical field order first, then any custom fields in their original order.
                $sorted = [ordered]@{}
                foreach ($k in 'Company', 'Suite', 'Role', 'Runs') { if ($fields.Contains($k)) { $sorted[$k] = $fields[$k] } }
                foreach ($k in @($fields.Keys)) { if (-not $sorted.Contains($k)) { $sorted[$k] = $fields[$k] } }
                $fields = $sorted

                $log.Insert(0, "$stamp - $entry")
                $keep   = @($log | Select-Object -First $MaxChangelog)
                $header = Build-Header -Name $file.Name -Fields $fields -Log $keep -Stamp $stamp -NL $nl
                $new    = $shebang + $header + $rest

                $verb = if ($action -eq 'Added') { 'add a header to' } else { 'update the header in' }
                if ($PSCmdlet.ShouldProcess(
                        "PREVIEW ONLY, nothing written: would $verb $($file.FullName)",
                        "$action header: $($file.FullName)?", 'Seala')) {
                    try {
                        if ($Backup) { Copy-Item -LiteralPath $file.FullName -Destination "$($file.FullName).bak" -Force -ErrorAction Stop }
                        [IO.File]::WriteAllText($file.FullName, $new, $src.Encoding)
                        # Verify on disk: never report success on a write that did not land.
                        $check = (Read-Text $file.FullName).Text
                        if ($check -ne $new) { throw 'File on disk does not match what was written.' }
                        $result.Action = $action
                        $result.Stamp  = $stamp
                    }
                    catch {
                        $result.Action = 'FAILED'
                        Write-Warning ("NOT written: {0}`n         {1}`n         If this file is under Desktop/Documents, Controlled Folder Access is the likely block: open a Doras pass or work from a folder outside Documents." -f $file.FullName, $_.Exception.Message)
                    }
                }
                else {
                    $result.Action = 'Preview only'
                }
                $result
            }
        }
    }
}

Set-Alias -Name seala -Value Set-ScriptHeader
Export-ModuleMember -Function Set-ScriptHeader -Alias seala
