<# ================================================================
#  PowerShell Profile - one file shared by console, ISE and VS Code
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Slot: CurrentUserAllHosts  (console + ISE + VS Code)
#  Last Modified: 10/12/2026
#  v6 - Doras (time-boxed CFA pass), Glas log outside Documents, cheat warns on module load failure
#  Keep this file pure ASCII: Windows PowerShell 5.1 misreads UTF-8 without BOM.
# ================================================================#>

# Globals + Write-Host are deliberate in a profile (shared config, colored UI output)
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
param()

#region CONFIG - everything machine-specific lives here
# GetFolderPath follows OneDrive/GPO folder redirection; $env:USERPROFILE\Desktop does not.
$global:PSP_Desktop   = [Environment]::GetFolderPath('Desktop')
$global:PSP_Documents = [Environment]::GetFolderPath('MyDocuments')
if (-not $global:PSP_Desktop)   { $global:PSP_Desktop   = Join-Path $HOME 'Desktop' }     # empty if folder missing
if (-not $global:PSP_Documents) { $global:PSP_Documents = Join-Path $HOME 'Documents' }

$global:PSP_User       = [Environment]::UserName   # shown in banner + greeting
$global:PSP_Company    = ''                      # blank = hidden in banner
$global:PSP_Tag        = "[$([Environment]::UserName)]"   # prompt tag
$global:PSP_Projects   = Join-Path $global:PSP_Documents 'Projects'
$global:PSP_PSReadLine = $true                   # predictive history + history search on arrows

# PSCmndLogr runs on EVERY prompt, including elevated ones. Pin its hash so a tampered
# copy can't ride along into an admin shell. Without a pin it runs in normal sessions
# only. Generate a pin with:  (Get-FileHash $global:PSP_CmndLogr).Hash
$global:PSP_CmndLogr       = Join-Path $global:PSP_Desktop 'CmndLogr\PSCmndLogr\PSCmndLogr.ps1'
$global:PSP_CmndLogrSHA256 = $null

# Faire: scheduled watch scripts (see Faire\README.md). Irish "faire" = watch, vigil.
$global:PSP_Faire = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Faire'

# Modules whose commands also show in 'cheat' (Glas = encryption: lock, unlock, newsecret...; Seala = script headers)
$global:PSP_CheatModules = @('Glas', 'Seala')

# Glas secrets log lives outside Documents (Controlled Folder Access blocks PowerShell writes there)
$PSDefaultParameterValues['New-GlasSecret:LogPath']  = Join-Path $env:LOCALAPPDATA 'Glas\secrets.log'
$PSDefaultParameterValues['Read-GlasSecret:LogPath'] = Join-Path $env:LOCALAPPDATA 'Glas\secrets.log'

# Where snapshots from Invoke-FieldSnapshot land
$global:PSP_Snapshots = Join-Path $global:PSP_Desktop 'Snapshots'

# Repos pushscripts can target: name = @{ Path = '...'; Public = $true|$false }.
# One repo: pushscripts uses it. Several: pushscripts asks which (or use -Repo <name>).
# Public repos also block staged *.nopush files and need the repo name typed to confirm.
$global:PSP_Repos = [ordered]@{
    # priv = @{ Path = 'C:\Path\To\PrivateRepo'; Public = $false }
    # pub  = @{ Path = 'C:\Path\To\PublicRepo';  Public = $true }
}
#endregion

#region HOST / SESSION DETECTION - computed once, reused everywhere
$global:PSP_IsISE     = $Host.Name -eq 'Windows PowerShell ISE Host'
$global:PSP_IsVSCode  = $Host.Name -eq 'Visual Studio Code Host'
$global:PSP_IsWindows = $env:OS -eq 'Windows_NT'

# The file actually running right now. If the ISE/VS Code profiles are stubs that
# dot-source this one, this still points at the real shared file.
$global:PSP_Path = if ($PSCommandPath) { $PSCommandPath } else { $PROFILE.CurrentUserAllHosts }

# Windows PowerShell 5.1 can default to TLS 1.0; modern HTTPS endpoints refuse it
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Skip banner/Clear-Host when a script or scheduled task launches a shell that loads
# the profile (-Command / -File / -NonInteractive), unless -NoExit keeps it open.
# VS Code's extension launches with -NonInteractive itself, so it's special-cased.
$_psp_args = [Environment]::GetCommandLineArgs() | Select-Object -Skip 1
$global:PSP_Interactive = $global:PSP_IsVSCode -or $global:PSP_IsISE -or (
    [Environment]::UserInteractive -and (
        ($_psp_args -match '^-noe') -or -not ($_psp_args -match '^-(noni\w*|c|command|f|file|e|ec|enc\w*)$')
    )
)
Remove-Variable _psp_args

$global:PSP_IsAdmin = $false
if ($global:PSP_IsWindows) {
    $global:PSP_IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
$global:PSP_LogrWarned = $null
#endregion

#region THEME - dark scheme, applied automatically in ISE
# ISE colors are ARGB hex: #AARRGGBB. Background 42,42,42 = #2A2A2A
# Run Export-ISETheme to dump your CURRENT settings as code to paste
# in here - that beats hand-tuning these values.
$global:PSP_Theme = @{
    Background = '#FF2A2A2A'   # 42 / 42 / 42
    Foreground = '#FFDCDCDC'
    FontName   = 'Lucida Console'
    FontSize   = 9
    Tokens     = @{
        Command           = '#FFDCDCDC'
        CommandArgument   = '#FF57A64A'
        CommandParameter  = '#FFB4B4B4'
        Comment           = '#FF57A64A'
        Keyword           = '#FF569CD6'
        Member            = '#FFDCDCDC'
        Number            = '#FFB5CEA8'
        Operator          = '#FFB4B4B4'
        String            = '#FFCE9178'
        Type              = '#FF4EC9B0'
        Variable          = '#FFE06C75'
        GroupStart        = '#FFB4B4B4'
        GroupEnd          = '#FFB4B4B4'
        Unknown           = '#FFDCDCDC'
    }
}

function Set-ISETheme {
    <#
    .SYNOPSIS
        Applies $global:PSP_Theme to the Windows PowerShell ISE.
    .DESCRIPTION
        Sets script pane, console pane, font and token colors from the PSP_Theme
        hashtable. Unknown token names are skipped instead of throwing. Does
        nothing outside the ISE. Runs automatically at profile load.
    .EXAMPLE
        Set-ISETheme
        Re-applies the theme after changing $global:PSP_Theme by hand.
    .NOTES
        Colors are ARGB hex strings (#AARRGGBB). Use Export-ISETheme to capture
        colors set through Tools > Options instead of hand-editing hex.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not $global:PSP_IsISE) { return }
    if (-not $PSCmdlet.ShouldProcess('ISE options', 'Apply PSP_Theme')) { return }

    try {
        $t = $global:PSP_Theme
        $o = $psISE.Options
        $o.ScriptPaneBackgroundColor      = $t.Background
        $o.ScriptPaneForegroundColor      = $t.Foreground
        $o.ConsolePaneBackgroundColor     = $t.Background
        $o.ConsolePaneTextBackgroundColor = $t.Background
        $o.ConsolePaneForegroundColor     = $t.Foreground
        $o.FontName                       = $t.FontName
        $o.FontSize                       = $t.FontSize

        foreach ($k in $t.Tokens.Keys) {
            if ($o.TokenColors.ContainsKey($k))        { $o.TokenColors[$k]        = $t.Tokens[$k] }
            if ($o.ConsoleTokenColors.ContainsKey($k)) { $o.ConsoleTokenColors[$k] = $t.Tokens[$k] }
        }
    }
    catch {
        Write-Host "Theme not applied: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Set-ISETheme
#endregion

#region PSREADLINE - console / VS Code only (ISE doesn't use it)
if ($global:PSP_PSReadLine -and -not $global:PSP_IsISE) {
    $prl = Get-Module PSReadLine
    if ($prl) {
        try {
            Set-PSReadLineOption -HistoryNoDuplicates -BellStyle None
            Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
            Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
            Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
            if ($prl.Version -ge [version]'2.1.0') { Set-PSReadLineOption -PredictionSource History }
        }
        catch {
            Write-Host "PSReadLine tweaks skipped: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Remove-Variable prl -ErrorAction SilentlyContinue
}
#endregion

#region BANNER
if ($global:PSP_Interactive) {
    Clear-Host
    Write-Host "===================================" -ForegroundColor DarkGray
    Write-Host "   PowerShell Console Environment   " -ForegroundColor Cyan
    Write-Host "   User: $global:PSP_User" -ForegroundColor Yellow
    if ($global:PSP_Company) {
        Write-Host "   Company: $global:PSP_Company" -ForegroundColor Green
    }
    Write-Host "   Host: $($Host.Name)" -ForegroundColor DarkCyan
    if ($global:PSP_IsAdmin) {
        Write-Host "   ELEVATED SESSION" -ForegroundColor Red
        if (-not $global:PSP_CmndLogrSHA256 -and (Test-Path -LiteralPath $global:PSP_CmndLogr)) {
            Write-Host "   CmndLogr OFF here (no hash pin set)" -ForegroundColor Red
        }
    }
    Write-Host "   Loaded: $(Get-Date -Format 'F')  " -ForegroundColor DarkCyan
    Write-Host "===================================" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Hello there, $global:PSP_User" -ForegroundColor Green
    Write-Host "Type 'cheat' for your commands, 'Get-Help <command> -Examples' for usage." -ForegroundColor DarkGray
    Write-Host ""
}
#endregion

#region PROMPT
function Get-GitBranch {
    <#
    .SYNOPSIS
        Returns the current git branch without launching git.exe.
    .DESCRIPTION
        Walks up from the current FileSystem location looking for .git, then reads
        HEAD directly. Handles worktrees and submodules (.git as a "gitdir:" file)
        and detached HEAD (returns a 7-char SHA). Returns nothing outside a repo or
        on non-FileSystem drives. Cheap enough to call on every prompt.
    .EXAMPLE
        Get-GitBranch
        main
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $loc = $ExecutionContext.SessionState.Path.CurrentLocation
    if ($loc.Provider.Name -ne 'FileSystem') { return }

    try {
        $dir = [System.IO.DirectoryInfo]::new($loc.ProviderPath)
        while ($dir) {
            $git  = [System.IO.Path]::Combine($dir.FullName, '.git')
            $head = $null

            if ([System.IO.Directory]::Exists($git)) {
                $head = [System.IO.Path]::Combine($git, 'HEAD')
            }
            elseif ([System.IO.File]::Exists($git)) {
                $gd = ([System.IO.File]::ReadAllText($git).Trim()) -replace '^gitdir:\s*', ''
                if (-not [System.IO.Path]::IsPathRooted($gd)) { $gd = [System.IO.Path]::Combine($dir.FullName, $gd) }
                $head = [System.IO.Path]::Combine($gd, 'HEAD')
            }

            if ($head) {
                if (-not [System.IO.File]::Exists($head)) { return }
                $ref = [System.IO.File]::ReadAllText($head).Trim()
                if ($ref -match '^ref: refs/heads/(.+)$') { return $Matches[1] }
                if ($ref.Length -ge 7) { return $ref.Substring(0, 7) }
                return
            }
            $dir = $dir.Parent
        }
    }
    catch {
        Write-Verbose "Get-GitBranch: $($_.Exception.Message)"   # locked/unreadable HEAD: show no branch
    }
}

function Test-CmndLogrTrusted {
    <#
    .SYNOPSIS
        Decides whether the prompt may run PSCmndLogr right now.
    .DESCRIPTION
        Returns $true when the logger exists and either:
          - a SHA256 pin is set and the file matches it, or
          - no pin is set and the session is NOT elevated.
        A mismatch is reported once per distinct hash, not on every prompt.
    .OUTPUTS
        System.Boolean
    .NOTES
        The logger is hashed and then executed as a file, so a small
        time-of-check/time-of-use window remains. The pin blocks persistent
        tampering, not a race.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $path = $global:PSP_CmndLogr
    if (-not $path -or -not [System.IO.File]::Exists($path)) { return $false }

    $pin = $global:PSP_CmndLogrSHA256
    if (-not $pin) { return -not $global:PSP_IsAdmin }

    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -eq $pin) { return $true }

    if ($global:PSP_LogrWarned -ne $hash) {
        Write-Host "[CmndLogr] hash mismatch, not running: $path" -ForegroundColor Red
        $global:PSP_LogrWarned = $hash
    }
    return $false
}

function prompt {
    <#
    .SYNOPSIS
        Custom prompt: [ADMIN][tag]<path> [git:branch] !>
    .DESCRIPTION
        Runs PSCmndLogr (when trusted), then draws the prompt. [ADMIN] appears in
        elevated sessions; a red ! means the previous command failed. $? and
        $LASTEXITCODE are captured first and restored last, so neither the logger
        nor the prompt can mask a native command's exit code. Strict-mode safe.
    #>
    $lastOK   = $?
    $lastExit = Get-Variable -Name LASTEXITCODE -Scope Global -ValueOnly -ErrorAction Ignore

    if (Test-CmndLogrTrusted) {
        try   { & $global:PSP_CmndLogr }
        catch { Write-Host "[CmndLogr] $($_.Exception.Message)" -ForegroundColor Red }
    }

    if ($global:PSP_IsAdmin) { Write-Host '[ADMIN]' -NoNewline -ForegroundColor Red }
    Write-Host $global:PSP_Tag -NoNewline -ForegroundColor Green
    Write-Host $ExecutionContext.SessionState.Path.CurrentLocation -NoNewline -ForegroundColor Cyan

    $branch = Get-GitBranch
    if ($branch) { Write-Host " [git:$branch]" -NoNewline -ForegroundColor Magenta }

    if (-not $lastOK) { Write-Host ' !' -NoNewline -ForegroundColor Red }

    if ($null -ne $lastExit) { $global:LASTEXITCODE = $lastExit }
    return "> "
}
#endregion

#region ALIASES
Set-Alias ll          Get-ChildItem
Set-Alias editprofile Edit-Profile
Set-Alias sysinfo     Get-SystemInfo
Set-Alias np          notepad
Set-Alias admin       Start-AsAdmin
Set-Alias ifconfig    Get-NetIPConfiguration      # Linux-like

# Old/short names -> approved-verb functions (muscle memory + old scripts keep working)
Set-Alias Email-Trace     Get-EmailTrace
Set-Alias Reload-Profile  Update-Profile
Set-Alias Go-Projects     Set-ProjectLocation
Set-Alias cleantemp       Clear-TempFile
Set-Alias Get-Zip         Get-ZipContent
Set-Alias seek            Find-File
Set-Alias Timestamp       Get-Timestamp
Set-Alias pushscripts     Publish-ScriptRepo

# Toolkit
Set-Alias cheat     Show-ProfileCommand
Set-Alias logons    Get-LogonEvent
Set-Alias ports     Get-ListeningPort
Set-Alias tp        Test-Port
Set-Alias myip      Get-PublicIP
Set-Alias hashcheck Test-FileHash
Set-Alias df        Get-DiskSpace
Set-Alias apps      Get-InstalledSoftware
Set-Alias persist   Get-PersistenceItem
Set-Alias snap      Invoke-FieldSnapshot
Set-Alias faire     Get-FaireStatus
Set-Alias doras     Open-Doras
Set-Alias dorasoff  Close-Doras
Set-Alias unblock   Unblock-Download
Set-Alias reload    Update-Profile
#endregion

#region FUNCTIONS
function la {
    <#
    .SYNOPSIS
        Get-ChildItem -Force: lists hidden and system items too.
    .DESCRIPTION
        Thin wrapper because Set-Alias can't carry parameters. Any extra
        arguments pass straight through to Get-ChildItem.
    .EXAMPLE
        la
    .EXAMPLE
        la C:\Windows -Directory
    #>
    Get-ChildItem -Force @args
}

function Get-EmailTrace {
    <#
    .SYNOPSIS
        Exchange Online message trace, preferring Get-MessageTraceV2.
    .DESCRIPTION
        Microsoft deprecated Get-MessageTrace on 9/1/2025. This calls
        Get-MessageTraceV2 when it's loaded and falls back to the legacy cmdlet.
        All arguments pass through unchanged.
    .EXAMPLE
        Get-EmailTrace -RecipientAddress user@contoso.com -StartDate (Get-Date).AddDays(-2) -EndDate (Get-Date)
    .NOTES
        Requires ExchangeOnlineManagement 3.7+ and an active Connect-ExchangeOnline.
        V2 returns up to 5,000 rows per call and searches 10 days per query.
        Alias: Email-Trace
    #>
    foreach ($name in 'Get-MessageTraceV2', 'Get-MessageTrace') {
        if (Get-Command $name -ErrorAction SilentlyContinue) { return & $name @args }
    }
    Write-Warning "No message trace cmdlet loaded. Import ExchangeOnlineManagement (3.7+) and run Connect-ExchangeOnline."
}

function Find-File {
    <#
    .SYNOPSIS
        Finds files by name or wildcard under a folder.
    .DESCRIPTION
        Searches files only (including hidden) and returns full paths. Access-denied
        folders are skipped silently during a recursive search; a path that does
        not exist is an error, not a "not found".
    .PARAMETER Path
        Folder to search. Taken literally (brackets are not wildcards).
    .PARAMETER FileName
        Name or wildcard pattern, e.g. 'hosts' or '*.evtx'.
    .PARAMETER Recurse
        Search subfolders.
    .EXAMPLE
        Find-File C:\Windows\System32\drivers\etc hosts
    .EXAMPLE
        seek C:\Logs *.evtx -Recurse
    .OUTPUTS
        System.String
    .NOTES
        Alias: seek
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [string]$FileName,

        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Error "Folder not found: $Path"
        return
    }

    $searchScope = if ($Recurse) { "recursively" } else { "non-recursively" }
    Write-Host "Searching $searchScope in $Path for '$FileName'..." -ForegroundColor Cyan

    $searchParams = @{
        LiteralPath = $Path
        Filter      = $FileName
        File        = $true
        Force       = $true
        Recurse     = [bool]$Recurse
        ErrorAction = 'SilentlyContinue'
    }

    $result = @(Get-ChildItem @searchParams)
    if ($result.Count) {
        Write-Host "Found $($result.Count) match(es):" -ForegroundColor Green
        return $result.FullName
    }
    Write-Host "File not found." -ForegroundColor Yellow
}

function Start-AsAdmin {
    <#
    .SYNOPSIS
        Opens an elevated copy of the current shell in the current folder.
    .DESCRIPTION
        pwsh relaunches pwsh, Windows PowerShell relaunches Windows PowerShell,
        and the ISE or VS Code open a console. Triggers a UAC prompt.
    .EXAMPLE
        Start-AsAdmin
    .NOTES
        Uses plain -Command, not -EncodedCommand, on purpose: encoded PowerShell
        is a standard EDR/SIEM detection and would add noise to your own alerts.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $exe = if ($global:PSP_IsISE) { Join-Path $PSHOME 'powershell.exe' } else { (Get-Process -Id $PID).Path }
    $dir = $PWD.Path -replace "'", "''"
    if (-not $PSCmdlet.ShouldProcess($exe, 'Launch elevated')) { return }
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList '-NoExit', '-Command', "Set-Location -LiteralPath '$dir'"
}

function Set-HVResolution {
    <#
    .SYNOPSIS
        Sets a Hyper-V VM's display resolution to a preset.
    .PARAMETER VMName
        One or more VM names. Accepts Get-VM output from the pipeline.
    .PARAMETER Preset
        HD = 1920x1080, Small = 750x550.
    .EXAMPLE
        Set-HVResolution -VMName lab-vm01 -Preset HD
    .EXAMPLE
        Get-VM lab-* | Set-HVResolution -Preset Small -WhatIf
    .NOTES
        Requires the Hyper-V module and an elevated session.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'HvName')]
        [string[]]$VMName,

        [ValidateSet('HD', 'Small')]
        [string]$Preset = 'HD'
    )

    begin {
        if (-not (Get-Command Set-VMVideo -ErrorAction SilentlyContinue)) {
            throw "Set-VMVideo not available. Enable the Hyper-V PowerShell module."
        }
        $res = @{ HD = @(1920, 1080); Small = @(750, 550) }[$Preset]
    }
    process {
        foreach ($vm in $VMName) {
            if ($PSCmdlet.ShouldProcess($vm, "Set video to $Preset ($($res[0])x$($res[1]))")) {
                Set-VMVideo -VMName $vm -HorizontalResolution $res[0] -VerticalResolution $res[1] -ResolutionType Single
            }
        }
    }
}

function hdhv {
    <#
    .SYNOPSIS
        Shortcut: set Hyper-V VM(s) to 1920x1080.
    .EXAMPLE
        hdhv lab-vm01
    #>
    param([Parameter(Mandatory)][string[]]$HvName)
    Set-HVResolution -VMName $HvName -Preset HD
}

function ldhv {
    <#
    .SYNOPSIS
        Shortcut: set Hyper-V VM(s) to 750x550.
    .EXAMPLE
        ldhv lab-vm01
    #>
    param([Parameter(Mandatory)][string[]]$HvName)
    Set-HVResolution -VMName $HvName -Preset Small
}

function Edit-Profile {
    <#
    .SYNOPSIS
        Opens the shared profile file in the best available editor.
    .DESCRIPTION
        ISE opens it in a new tab; otherwise VS Code if 'code' is on PATH, then
        Notepad. Creates the file (and folder) first if it doesn't exist.
    .EXAMPLE
        editprofile
    .NOTES
        Alias: editprofile. After saving, run: . Update-Profile
    #>
    [CmdletBinding()]
    param()

    $target = $global:PSP_Path
    if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType File -Path $target -Force | Out-Null }
    if     ($global:PSP_IsISE)                              { psEdit $target }
    elseif (Get-Command code -ErrorAction SilentlyContinue) { code $target }
    else                                                    { notepad $target }
}

function Update-Profile {
    <#
    .SYNOPSIS
        Reloads the shared profile into the current session.
    .DESCRIPTION
        MUST be dot-sourced. Called normally, everything the profile defines lands
        in this function's scope and disappears when it returns. Dot-sourcing the
        call runs the body in your scope, so the reload reaches global. Warns and
        does nothing if called without the dot.
    .EXAMPLE
        . Update-Profile
    .EXAMPLE
        . Reload-Profile
    .EXAMPLE
        . reload
    .NOTES
        Kept as a simple (non-advanced) function so dot-sourced behavior stays
        predictable. Removed functions/aliases are not unloaded; open a new
        session for a truly clean state.
        Aliases: Reload-Profile, reload
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param()

    if ($MyInvocation.InvocationName -ne '.') {
        Write-Host "Dot-source it so changes stick:  . reload  (or . Update-Profile)" -ForegroundColor Yellow
        return
    }
    . $global:PSP_Path
    Write-Host "Profile reloaded." -ForegroundColor Green
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Quick host summary: name, user, OS build, uptime, PowerShell, elevation.
    .DESCRIPTION
        Returns an object, so it can be piped, filtered or exported. OS caption
        and uptime come from CIM on Windows; elsewhere they fall back to .NET.
    .EXAMPLE
        sysinfo
    .EXAMPLE
        Get-SystemInfo | ConvertTo-Json
    .OUTPUTS
        PSCustomObject
    .NOTES
        Alias: sysinfo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $os = $null
    if ($global:PSP_IsWindows) { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue }

    [pscustomobject]@{
        ComputerName = [Environment]::MachineName
        UserName     = '{0}\{1}' -f [Environment]::UserDomainName, [Environment]::UserName
        OS           = if ($os) { "$($os.Caption) (build $($os.BuildNumber))" } else { [Environment]::OSVersion.VersionString }
        Uptime       = if ($os) { '{0:%d}d {0:hh}h {0:mm}m' -f ((Get-Date) - $os.LastBootUpTime) } else { $null }
        '64-bit OS'  = [Environment]::Is64BitOperatingSystem
        PowerShell   = $PSVersionTable.PSVersion.ToString()
        Host         = $Host.Name
        Elevated     = $global:PSP_IsAdmin
    }
}

function Get-Timestamp {
    <#
    .SYNOPSIS
        Filename-safe timestamp: yyyy-MM-dd_HH-mm-ss.
    .EXAMPLE
        Export-Csv ".\scan_$(Get-Timestamp).csv"
    .OUTPUTS
        System.String
    .NOTES
        Alias: Timestamp
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
}

function Set-ProjectLocation {
    <#
    .SYNOPSIS
        cd to $global:PSP_Projects.
    .EXAMPLE
        Go-Projects
    .NOTES
        Alias: Go-Projects. Path is set in the CONFIG region.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $global:PSP_Projects) { Set-Location -LiteralPath $global:PSP_Projects }
    else { Write-Host "Projects folder not found -> $global:PSP_Projects" -ForegroundColor Yellow }
}

function Clear-TempFile {
    <#
    .SYNOPSIS
        Deletes old files from the user temp folder and prunes empty folders.
    .DESCRIPTION
        Removes files whose LastWriteTime is older than -OlderThanHours, then
        removes folders left empty. Works per FILE, so a fresh file inside an old
        folder is kept. Junctions and symlinks are skipped and never traversed,
        so a link planted in %TEMP% can't redirect deletion outside it.
        Locked files are counted and skipped. Asks once for the whole batch
        with -Confirm; -WhatIf shows the count and size without deleting.
    .PARAMETER OlderThanHours
        Age threshold. Default 24. Use 0 to target everything not in use.
    .EXAMPLE
        Clear-TempFile -WhatIf
    .EXAMPLE
        cleantemp -OlderThanHours 0
    .NOTES
        Alias: cleantemp. Only the per-user temp path; C:\Windows\Temp is
        out of scope.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [ValidateRange(0, [int]::MaxValue)]
        [int]$OlderThanHours = 24
    )

    $temp   = [System.IO.Path]::GetTempPath()
    $cutoff = (Get-Date).AddHours(-$OlderThanHours)
    $reparse = [System.IO.FileAttributes]::ReparsePoint

    # Manual walk: GCI -Recurse follows junctions in 5.1, which could reach outside %TEMP%
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $dirs  = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
    $stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $stack.Push([System.IO.DirectoryInfo]::new($temp))

    while ($stack.Count) {
        $d = $stack.Pop()
        try { $entries = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entries) {
            if ($e.Attributes -band $reparse) { continue }
            if ($e -is [System.IO.DirectoryInfo]) {
                $stack.Push($e)
                if ($e.LastWriteTime -lt $cutoff) { $dirs.Add($e) }   # captured BEFORE deletes touch mtimes
            }
            elseif ($e.LastWriteTime -lt $cutoff) { $files.Add($e) }
        }
    }

    if (-not $files.Count -and -not $dirs.Count) {
        Write-Host "Nothing in $temp older than $OlderThanHours h." -ForegroundColor DarkGray
        return
    }

    $bytes = ($files | Measure-Object -Property Length -Sum).Sum
    $what  = "Remove {0} file(s), {1:N1} MB, older than {2} h" -f $files.Count, ($bytes / 1MB), $OlderThanHours
    if (-not $PSCmdlet.ShouldProcess($temp, $what)) { return }

    $freed = 0; $locked = 0
    foreach ($f in $files) {
        try { $f.Delete(); $freed += $f.Length } catch { $locked++ }
    }

    # Deepest first so parents empty out before they're checked
    foreach ($d in ($dirs | Sort-Object { $_.FullName.Length } -Descending)) {
        try { if (-not $d.EnumerateFileSystemInfos().GetEnumerator().MoveNext()) { $d.Delete() } } catch { $locked++ }
    }

    Write-Host ("Done. Freed {0:N1} MB, {1} item(s) locked/in use." -f ($freed / 1MB), $locked) -ForegroundColor Green
}

function Export-ISETheme {
    <#
    .SYNOPSIS
        Dumps the ISE's current colors as a paste-ready PSP_Theme block.
    .DESCRIPTION
        Set colors by hand in Tools > Options, run this, then paste the output
        over the $global:PSP_Theme block in the THEME region. Also copies to the
        clipboard when available.
    .EXAMPLE
        Export-ISETheme
    .OUTPUTS
        None. Writes to the host and clipboard.
    #>
    [CmdletBinding()]
    param()

    if (-not $global:PSP_IsISE) {
        Write-Host "Export-ISETheme only runs inside the ISE." -ForegroundColor Yellow
        return
    }

    $o = $psISE.Options
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('$global:PSP_Theme = @{')
    $lines.Add("    Background = '$($o.ConsolePaneBackgroundColor)'")
    $lines.Add("    Foreground = '$($o.ConsolePaneForegroundColor)'")
    $lines.Add("    FontName   = '$($o.FontName)'")
    $lines.Add("    FontSize   = $($o.FontSize)")
    $lines.Add('    Tokens     = @{')
    foreach ($k in ($o.TokenColors.Keys | Sort-Object)) {
        $lines.Add(("        {0,-18}= '{1}'" -f $k, $o.TokenColors[$k]))
    }
    $lines.Add('    }')
    $lines.Add('}')

    $out = $lines -join "`r`n"
    Write-Host $out -ForegroundColor Cyan
    try {
        Set-Clipboard -Value $out
        Write-Host "`nCopied to clipboard." -ForegroundColor Green
    }
    catch {
        Write-Verbose "Clipboard unavailable: $($_.Exception.Message)"
    }
}

function Get-ZipContent {
    <#
    .SYNOPSIS
        Lists entries in a ZIP without extracting it.
    .PARAMETER Path
        ZIP file path. Accepts pipeline input, including FileInfo objects.
    .EXAMPLE
        Get-ZipContent .\evidence.zip
    .EXAMPLE
        Get-ChildItem *.zip | Get-ZipContent | Where-Object FullName -like '*.ps1'
        Triage: find scripts hiding in a pile of archives.
    .OUTPUTS
        PSCustomObject: FullName, Length, CompressedSize, LastWriteTime
    .NOTES
        Alias: Get-Zip
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path
    )

    begin { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue }
    process {
        $zip = $null
        try {
            $full = Convert-Path -LiteralPath $Path -ErrorAction Stop
            $zip  = [System.IO.Compression.ZipFile]::OpenRead($full)
            foreach ($e in $zip.Entries) {
                [pscustomobject]@{
                    FullName       = $e.FullName
                    Length         = $e.Length
                    CompressedSize = $e.CompressedLength
                    LastWriteTime  = $e.LastWriteTime.DateTime
                }
            }
        }
        catch { Write-Error "Failed to read ZIP '$Path': $($_.Exception.Message)" }
        finally { if ($zip) { $zip.Dispose() } }
    }
}

function Publish-ScriptRepo {
    <#
    .SYNOPSIS
        Stages, secret-scans, commits and pushes one of your repos (asks which when there are several).
    .DESCRIPTION
        Repos are listed in $global:PSP_Repos in the CONFIG region. -Repo goes straight
        to one by name. Without it, a single configured repo is used as-is, and several
        give a numbered menu showing each repo's path, visibility, branch and remote.
        Nothing is staged until a repo is chosen.

        Then: git add -A, a scan of the ADDED lines for common secrets (AWS keys, GitHub
        tokens, private key blocks, password/secret/token/apikey assignments), commit
        and push. The first push of a new branch sets its upstream automatically.

        Repos marked Public = $true get two extra gates:
          - any staged file whose path contains '.nopush' aborts the run and unstages
          - you type the repo's name to confirm before the commit is made
    .PARAMETER Message
        Commit message. Prompted for if omitted; empty aborts.
    .PARAMETER Repo
        Name of a repo in $global:PSP_Repos. Tab-completes.
    .EXAMPLE
        pushscripts "Add log analyzer v1.8"
        Asks which repo, then commits and pushes.
    .EXAMPLE
        pushscripts -Repo pub "Add Faire README"
        Public repo: .nopush check, then asks you to type 'pub' before committing.
    .NOTES
        The scan is a tripwire, not a replacement for gitleaks or GitHub push
        protection. Alias: pushscripts
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Message,
        [ArgumentCompleter({
            $word = $args[2]   # completer args: command, parameter, word being completed
            @($global:PSP_Repos.Keys) | Where-Object { $_ -like "$word*" }
        })]
        [string]$Repo
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "pushscripts: git not found in PATH." -ForegroundColor Red
        return
    }
    $repos = $global:PSP_Repos
    if (-not $repos -or -not $repos.Count) {
        Write-Host "pushscripts: no repos set - add them to PSP_Repos in the CONFIG region." -ForegroundColor Yellow
        return
    }

    # Pick the target before touching anything
    $names = @($repos.Keys)
    if ($Repo) {
        if (-not $repos.Contains($Repo)) {
            Write-Host "pushscripts: unknown repo '$Repo'. Known: $($names -join ', ')" -ForegroundColor Red
            return
        }
        $name = $Repo
    }
    elseif ($names.Count -eq 1) {
        $name = $names[0]
    }
    else {
        Write-Host "Push which repo?" -ForegroundColor Cyan
        for ($i = 0; $i -lt $names.Count; $i++) {
            $r = $repos[$names[$i]]
            $p = if ($r -is [string]) { $r } else { $r.Path }
            $pub = ($r -isnot [string]) -and [bool]$r.Public
            $branch = $remote = ''
            if ($p -and (Test-Path -LiteralPath $p)) {
                $branch = git -C $p rev-parse --abbrev-ref HEAD 2>$null
                $remote = git -C $p remote get-url origin 2>$null
            }
            $vis = if ($pub) { 'PUBLIC ' } else { 'private' }
            $color = if ($pub) { 'Yellow' } else { 'Gray' }
            Write-Host ("  {0}) {1,-6} {2}  {3}  [{4}]  {5}" -f ($i + 1), $names[$i], $vis, $p, $branch, $remote) -ForegroundColor $color
        }
        $pick = (Read-Host "Number or name (Enter cancels)").Trim()
        if (-not $pick) { Write-Host "Cancelled." -ForegroundColor DarkGray; return }
        if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $names.Count) { $name = $names[[int]$pick - 1] }
        elseif ($repos.Contains($pick)) { $name = $pick }
        else { Write-Host "pushscripts: '$pick' is not on the list." -ForegroundColor Red; return }
    }

    $name     = $names | Where-Object { $_ -eq $name } | Select-Object -First 1   # canonical spelling
    $target   = $repos[$name]
    $path     = if ($target -is [string]) { $target } else { $target.Path }
    $isPublic = ($target -isnot [string]) -and [bool]$target.Public

    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        Write-Host "pushscripts: repo '$name' not found -> $path" -ForegroundColor Red
        return
    }

    Push-Location -LiteralPath $path
    try {
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "pushscripts: $path is not a git repo." -ForegroundColor Red
            return
        }

        if (-not (git status --porcelain)) {
            Write-Host "Nothing to commit in '$name'." -ForegroundColor DarkGray
            return
        }

        $vis = if ($isPublic) { 'PUBLIC' } else { 'private' }
        Write-Host "Repo: $name ($vis) $path" -ForegroundColor $(if ($isPublic) { 'Yellow' } else { 'Cyan' })
        git status --short
        git add -A

        # Public repos: files tagged .nopush never leave the machine
        if ($isPublic) {
            $blocked = @(git diff --cached --name-only --diff-filter=ACMR | Where-Object { $_ -match '\.nopush' })
            if ($blocked.Count) {
                Write-Host "Files tagged .nopush are staged for a PUBLIC repo:" -ForegroundColor Red
                $blocked | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
                git reset -q
                Write-Host "Aborted and unstaged." -ForegroundColor Yellow
                return
            }
        }

        # Secret tripwire on added lines only
        $patterns = @(
            'AKIA[0-9A-Z]{16}'
            'gh[pousr]_[A-Za-z0-9]{36,}'
            '-----BEGIN [A-Z ]*PRIVATE KEY-----'
            '(?i)(password|passwd|pwd|secret|api[_-]?key|token)\s*[:=]\s*[''"][^''"]{6,}[''"]'
        )
        $hits = [System.Collections.Generic.List[string]]::new()
        $file = $null; $line = 0
        foreach ($d in (git diff --cached -U0 --no-color)) {
            if     ($d -match '^\+\+\+ b/(.+)$')        { $file = $Matches[1]; continue }
            elseif ($d -match '^@@ .*\+(\d+)')         { $line = [int]$Matches[1]; continue }
            elseif ($d.StartsWith('+'))  {
                foreach ($p in $patterns) { if ($d -match $p) { $hits.Add("${file}:$line"); break } }
                $line++
            }
        }
        if ($hits.Count) {
            Write-Host "Possible secrets staged:" -ForegroundColor Red
            $hits | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            if ((Read-Host "Commit anyway? (y/N)") -ne 'y') {
                git reset -q
                Write-Host "Aborted and unstaged." -ForegroundColor Yellow
                return
            }
        }

        if (-not $Message) { $Message = Read-Host "Commit message" }
        if (-not "$Message".Trim()) {
            git reset -q
            Write-Host "Aborted - empty commit message (unstaged)." -ForegroundColor Red
            return
        }

        # Public repos: deliberate, typed confirmation (muscle-memory 'y' doesn't count)
        if ($isPublic) {
            $remoteUrl = git remote get-url origin 2>$null
            Write-Host "About to commit and push to PUBLIC repo '$name' -> $remoteUrl" -ForegroundColor Yellow
            if ((Read-Host "Type '$name' to continue") -cne $name) {
                git reset -q
                Write-Host "Aborted and unstaged." -ForegroundColor Yellow
                return
            }
        }

        git commit -m "$Message"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Commit failed - not pushing." -ForegroundColor Red
            return
        }

        git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { git push } else { git push -u origin HEAD }

        if ($LASTEXITCODE -eq 0) { Write-Host "Pushed to ${name}: $Message" -ForegroundColor Green }
        else                     { Write-Host "Push failed (exit $LASTEXITCODE)." -ForegroundColor Red }
    }
    finally { Pop-Location }
}
#endregion

#region TOOLKIT
function Add-DisplaySet {
    <#
    .SYNOPSIS
        Internal: sets which properties show by default, keeping the rest available.
    .DESCRIPTION
        PowerShell shows objects with more than 4 properties as a list. Giving an
        object a default display set of 4 or fewer makes it render as a table,
        while Select-Object * still reveals every property.
    .PARAMETER InputObject
        The object to tag. Accepts pipeline input; passes the object through.
    .PARAMETER Property
        Property names to show by default.
    .EXAMPLE
        [pscustomobject]@{a=1;b=2;c=3;d=4;e=5} | Add-DisplaySet a,b
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]$InputObject,
        [Parameter(Mandatory, Position = 0)][string[]]$Property
    )
    begin {
        $set = [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', $Property)
        $ms  = [System.Management.Automation.PSMemberInfo[]]@($set)
    }
    process {
        $InputObject | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $ms -Force -PassThru
    }
}

function Get-LogonEvent {
    <#
    .SYNOPSIS
        Failed, successful or lockout logons from the Security log, decoded.
    .DESCRIPTION
        Pulls 4625 (failed), 4624 (success) and/or 4740 (lockout) events and turns
        the raw XML into readable fields: user, source IP, logon type name, and
        for failures, WHY it failed (bad password vs. no such user, etc.).
        -Summary groups by user + source IP, which is the brute-force view.
    .PARAMETER Type
        Failed (default), Success, Lockout or All.
    .PARAMETER Hours
        How far back to look. Default 24.
    .PARAMETER MaxEvents
        Cap on events read. Default 1000.
    .PARAMETER Summary
        Group by User + SourceIP with counts and first/last seen.
    .EXAMPLE
        logons
        Failed logons, last 24 hours.
    .EXAMPLE
        logons -Summary -Hours 72
        Who is hammering which account from where.
    .EXAMPLE
        logons Success | Where-Object LogonType -eq 'RemoteInteractive'
        RDP logons.
    .OUTPUTS
        PSCustomObject (default view: Time, Result, User, SourceIP)
    .NOTES
        Needs an elevated session. "No such user" failures from one IP across many
        names = spraying/enumeration; "Bad password" on one name = guessing.
        Alias: logons
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Failed', 'Success', 'Lockout', 'All')]
        [string]$Type = 'Failed',
        [ValidateRange(1, 8760)][int]$Hours = 24,
        [ValidateRange(1, 100000)][int]$MaxEvents = 1000,
        [switch]$Summary
    )

    if (-not $global:PSP_IsWindows) { Write-Warning 'Windows only.'; return }
    if (-not $global:PSP_IsAdmin)   { Write-Warning 'The Security log needs an elevated session. Run Start-AsAdmin.'; return }

    $ids = switch ($Type) {
        'Failed'  { 4625 }
        'Success' { 4624 }
        'Lockout' { 4740 }
        'All'     { 4624, 4625, 4740 }
    }
    $logonTypes = @{ '2' = 'Interactive'; '3' = 'Network'; '4' = 'Batch'; '5' = 'Service'; '7' = 'Unlock'
                     '8' = 'NetworkCleartext'; '9' = 'NewCredentials'; '10' = 'RemoteInteractive'; '11' = 'CachedInteractive' }
    $reasons = @{ '0xc000006a' = 'Bad password'; '0xc0000064' = 'No such user'; '0xc0000234' = 'Locked out'
                  '0xc0000072' = 'Account disabled'; '0xc000006f' = 'Outside allowed hours'; '0xc0000070' = 'Workstation restriction'
                  '0xc0000071' = 'Password expired'; '0xc0000193' = 'Account expired'; '0xc0000224' = 'Must change password'
                  '0xc0000133' = 'Clock skew' }

    $filter = @{ LogName = 'Security'; Id = $ids; StartTime = (Get-Date).AddHours(-$Hours) }
    try {
        $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            Write-Host "No matching events in the last $Hours h." -ForegroundColor DarkGray
            return
        }
        throw
    }

    $rows = foreach ($e in $events) {
        $d = @{}
        foreach ($n in ([xml]$e.ToXml()).Event.EventData.Data) { $d[$n.Name] = $n.'#text' }

        $code = if ($d.SubStatus -and $d.SubStatus -ne '0x0') { $d.SubStatus } else { $d.Status }
        [pscustomobject]@{
            Time        = $e.TimeCreated
            Result      = switch ($e.Id) { 4624 { 'Success' } 4625 { 'Failed' } 4740 { 'Lockout' } }
            User        = if ($e.Id -ne 4740 -and $d.TargetDomainName) { "$($d.TargetDomainName)\$($d.TargetUserName)" } else { $d.TargetUserName }
            SourceIP    = $d.IpAddress
            LogonType   = $logonTypes["$($d.LogonType)"]
            Workstation = if ($e.Id -eq 4740) { $d.TargetDomainName } else { $d.WorkstationName }
            Reason      = if ($e.Id -eq 4625) { if ($reasons["$code"]) { $reasons["$code"] } else { $code } } else { $null }
            Process     = $d.ProcessName
            EventId     = $e.Id
        }
    }

    if ($Summary) {
        return $rows | Group-Object User, SourceIP | Sort-Object Count -Descending | ForEach-Object {
            $times = $_.Group.Time | Measure-Object -Minimum -Maximum
            [pscustomobject]@{
                Count    = $_.Count
                User     = $_.Group[0].User
                SourceIP = $_.Group[0].SourceIP
                Reasons  = ($_.Group.Reason | Where-Object { $_ } | Select-Object -Unique) -join ', '
                First    = $times.Minimum
                Last     = $times.Maximum
            } | Add-DisplaySet Count, User, SourceIP, Reasons
        }
    }
    $rows | Add-DisplaySet Time, Result, User, SourceIP
}

function Get-ListeningPort {
    <#
    .SYNOPSIS
        What is listening on this box (or talking out), with process name and path.
    .DESCRIPTION
        netstat -ano, but with the PID already resolved to a process and its exe
        path. Shows TCP listeners and UDP endpoints by default; -Established shows
        live outbound/inbound TCP sessions instead.
    .PARAMETER Established
        Show established TCP connections (with remote address) instead of listeners.
    .PARAMETER Port
        Only show this local or remote port.
    .EXAMPLE
        ports
    .EXAMPLE
        ports -Established | Where-Object RemotePort -eq 443
    .EXAMPLE
        ports -Port 3389
        Is RDP open, and who owns it?
    .OUTPUTS
        PSCustomObject (default view: Proto, LocalPort, PID, Process)
    .NOTES
        Exe paths of other users' and protected processes need elevation.
        Something listening on 0.0.0.0 that you don't recognize is worth a look.
        Alias: ports
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [switch]$Established,
        [ValidateRange(1, 65535)][int]$Port
    )

    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        Write-Warning 'Needs the NetTCPIP module (Windows).'
        return
    }

    $procs = @{}
    foreach ($p in Get-Process) { $procs[$p.Id] = $p }

    $out = [System.Collections.Generic.List[object]]::new()
    $state = if ($Established) { 'Established' } else { 'Listen' }
    foreach ($c in (Get-NetTCPConnection -State $state -ErrorAction SilentlyContinue)) {
        $p = $procs[[int]$c.OwningProcess]
        $out.Add([pscustomobject]@{
            Proto         = 'TCP'
            LocalAddress  = $c.LocalAddress
            LocalPort     = $c.LocalPort
            RemoteAddress = if ($Established) { $c.RemoteAddress } else { $null }
            RemotePort    = if ($Established) { $c.RemotePort } else { $null }
            PID           = $c.OwningProcess
            Process       = if ($p) { $p.ProcessName } else { $null }
            Path          = if ($p) { $p.Path } else { $null }
        })
    }
    if (-not $Established) {
        foreach ($u in (Get-NetUDPEndpoint -ErrorAction SilentlyContinue)) {
            $p = $procs[[int]$u.OwningProcess]
            $out.Add([pscustomobject]@{
                Proto = 'UDP'; LocalAddress = $u.LocalAddress; LocalPort = $u.LocalPort
                RemoteAddress = $null; RemotePort = $null; PID = $u.OwningProcess
                Process = if ($p) { $p.ProcessName } else { $null }
                Path    = if ($p) { $p.Path } else { $null }
            })
        }
    }

    $rows = $out | Sort-Object Proto, LocalPort -Unique
    if ($Port) { $rows = $rows | Where-Object { $_.LocalPort -eq $Port -or $_.RemotePort -eq $Port } }
    $view = if ($Established) { 'LocalPort', 'RemoteAddress', 'RemotePort', 'Process' } else { 'Proto', 'LocalPort', 'PID', 'Process' }
    $rows | Add-DisplaySet $view
}

function Test-Port {
    <#
    .SYNOPSIS
        Fast TCP port check with a real timeout: Open, Closed or Filtered.
    .DESCRIPTION
        Test-NetConnection takes seconds and pings first. This does a single TCP
        connect with a timeout you control, against any number of hosts x ports.
          Open     = handshake completed
          Closed   = host answered with a reset (reachable, nothing listening)
          Filtered = no answer before the timeout (firewall drop, host down, wrong IP)
    .PARAMETER ComputerName
        Host names or IPs. Accepts pipeline input.
    .PARAMETER Port
        One or more ports.
    .PARAMETER TimeoutMs
        Milliseconds to wait per connection. Default 1000.
    .EXAMPLE
        tp 192.0.2.10 22,80,443,3389
    .EXAMPLE
        'dc01','dc02' | Test-Port -Port 53,88,389,445 -TimeoutMs 500
        Quick domain controller health check.
    .OUTPUTS
        PSCustomObject: ComputerName, Port, Status, Ms
    .NOTES
        Alias: tp
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string[]]$ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [ValidateRange(1, 65535)]
        [int[]]$Port,

        [ValidateRange(50, 60000)]
        [int]$TimeoutMs = 1000
    )

    process {
        foreach ($c in $ComputerName) {
            foreach ($p in $Port) {
                $client = [System.Net.Sockets.TcpClient]::new()
                $sw     = [System.Diagnostics.Stopwatch]::StartNew()
                $status = 'Filtered'
                try {
                    $task = $client.ConnectAsync($c, $p)
                    if ($task.Wait($TimeoutMs) -and $client.Connected) { $status = 'Open' }
                }
                catch {
                    $inner = $_.Exception
                    while ($inner.InnerException) { $inner = $inner.InnerException }
                    $status = if ($inner -is [System.Net.Sockets.SocketException] -and
                                  $inner.SocketErrorCode -eq 'ConnectionRefused') { 'Closed' }
                              else { "Error: $($inner.Message)" }
                }
                finally {
                    $sw.Stop()
                    $client.Dispose()
                }
                [pscustomobject]@{
                    ComputerName = $c
                    Port         = $p
                    Status       = $status
                    Ms           = if ($status -eq 'Open') { $sw.ElapsedMilliseconds } else { $null }
                }
            }
        }
    }
}

function Get-PublicIP {
    <#
    .SYNOPSIS
        Your public (internet-facing) IP address.
    .DESCRIPTION
        Asks a few well-known echo services in order and returns the first answer.
        Handy on client sites to confirm which WAN/VPN you are actually egressing.
    .EXAMPLE
        myip
    .OUTPUTS
        System.String
    .NOTES
        This tells a third party your IP; that is the point, but know it.
        Alias: myip
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $ProgressPreference = 'SilentlyContinue'    # local scope only; stops the download bar flicker
    foreach ($u in 'https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com') {
        try   { return "$(Invoke-RestMethod -Uri $u -TimeoutSec 5 -ErrorAction Stop)".Trim() }
        catch { Write-Verbose "$u failed: $($_.Exception.Message)" }
    }
    Write-Warning 'Could not reach any public IP service.'
}

function Test-FileHash {
    <#
    .SYNOPSIS
        Verifies a download against the publisher's hash. Algorithm auto-detected.
    .DESCRIPTION
        Paste the hash from the download page; its length picks the algorithm
        (32 = MD5, 40 = SHA1, 64 = SHA256, 128 = SHA512). Spaces and case are
        ignored. Prints MATCH/MISMATCH and returns the details.
    .PARAMETER Path
        File to check.
    .PARAMETER Expected
        Hash published by the vendor.
    .PARAMETER Algorithm
        Override auto-detection.
    .EXAMPLE
        hashcheck .\ventoy.zip 3A1B...F09C
    .OUTPUTS
        PSCustomObject: Match, Algorithm, Expected, Actual
    .NOTES
        A match only proves the file equals what the page says. If the page itself
        is compromised, so is the hash; prefer signed releases when offered.
        Alias: hashcheck
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [Parameter(Mandatory, Position = 1)][string]$Expected,
        [ValidateSet('MD5', 'SHA1', 'SHA256', 'SHA512')][string]$Algorithm
    )

    $exp = ($Expected -replace '\s', '').ToUpperInvariant()
    if (-not $Algorithm) {
        $Algorithm = switch ($exp.Length) {
            32 { 'MD5' } 40 { 'SHA1' } 64 { 'SHA256' } 128 { 'SHA512' }
            default { throw "Can't tell the algorithm from a $($exp.Length)-char hash. Use -Algorithm." }
        }
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm -ErrorAction Stop).Hash
    $match  = $actual -eq $exp
    if ($match) { Write-Host "MATCH ($Algorithm)" -ForegroundColor Green }
    else        { Write-Host "MISMATCH ($Algorithm) - do not run this file" -ForegroundColor Red }

    [pscustomobject]@{ Match = $match; Algorithm = $Algorithm; Expected = $exp; Actual = $actual }
}

function Get-DiskSpace {
    <#
    .SYNOPSIS
        Free space per drive, with low drives flagged in red.
    .PARAMETER WarnBelowPercent
        Flag drives with less free space than this. Default 15.
    .EXAMPLE
        df
    .EXAMPLE
        df | Where-Object Low
    .OUTPUTS
        PSCustomObject (default view: Drive, SizeGB, FreeGB, FreePct)
    .NOTES
        Alias: df
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([ValidateRange(0, 100)][int]$WarnBelowPercent = 15)

    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady -or $d.TotalSize -le 0 -or $d.DriveType -notin 'Fixed', 'Removable') { continue }
        $pct = [math]::Round($d.AvailableFreeSpace / $d.TotalSize * 100, 1)
        if ($pct -lt $WarnBelowPercent) { Write-Host "LOW: $($d.Name) at $pct% free" -ForegroundColor Red }
        [pscustomobject]@{
            Drive   = $d.Name
            Label   = $d.VolumeLabel
            SizeGB  = [math]::Round($d.TotalSize / 1GB, 1)
            FreeGB  = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
            FreePct = $pct
            Low     = $pct -lt $WarnBelowPercent
        } | Add-DisplaySet Drive, SizeGB, FreeGB, FreePct
    }
}

function Get-InstalledSoftware {
    <#
    .SYNOPSIS
        Installed programs from the registry (both 32- and 64-bit, machine + user).
    .DESCRIPTION
        Reads the Uninstall keys directly. Much faster than Win32_Product, which
        you should never use: querying it triggers an MSI consistency check that
        can silently repair or reconfigure installed software.
    .PARAMETER Name
        Wildcard filter on the display name.
    .EXAMPLE
        apps
    .EXAMPLE
        apps *anydesk*
        Find remote access tools left installed on a machine.
    .OUTPUTS
        PSCustomObject (default view: Name, Version, Publisher, Scope)
    .NOTES
        Alias: apps
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Position = 0)][string]$Name = '*')

    if (-not $global:PSP_IsWindows) { Write-Warning 'Windows only.'; return }

    $keys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';             Scope = 'Machine' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Machine32' }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*';             Scope = 'User' }
    )
    $rows = foreach ($k in $keys) {
        Get-ItemProperty -Path $k.Path -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -and $_.DisplayName -like $Name -and
                           -not ($_.PSObject.Properties['SystemComponent'] -and $_.SystemComponent -eq 1) } |
            ForEach-Object {
                $p = $_.PSObject.Properties
                [pscustomobject]@{
                    Name        = $_.DisplayName
                    Version     = if ($p['DisplayVersion'])  { $_.DisplayVersion }  else { $null }
                    Publisher   = if ($p['Publisher'])       { $_.Publisher }       else { $null }
                    Scope       = $k.Scope
                    InstallDate = if ($p['InstallDate'])     { $_.InstallDate }     else { $null }
                    Uninstall   = if ($p['UninstallString']) { $_.UninstallString } else { $null }
                } | Add-DisplaySet Name, Version, Publisher, Scope
            }
    }
    $rows | Sort-Object Name
}

function Get-PersistenceItem {
    <#
    .SYNOPSIS
        Autoruns-lite: everything set to start automatically, in one list.
    .DESCRIPTION
        Checks the common persistence spots: Run/RunOnce keys (HKLM, HKCU, 32-bit),
        Winlogon Shell/Userinit, Startup folders, non-Microsoft scheduled tasks,
        auto-start services living outside the Windows folder, and WMI event
        consumers (a favorite fileless trick). Uses the same collector as the
        Faire Watch-Persistence task, so what you see here is what it baselines.
    .EXAMPLE
        persist
    .EXAMPLE
        persist | Where-Object Command -match 'powershell|mshta|rundll32|\\AppData\\|\\Temp\\'
        The usual suspects.
    .OUTPUTS
        PSCustomObject (default view: Type, Name, Command)
    .NOTES
        Fast triage, not a replacement for Sysinternals Autoruns: it skips
        System32 service binaries (where svchost DLL tricks live), IFEO, COM
        hijacks, and more. Run elevated for complete results.
        Needs Faire installed or the Faire folder next to this profile.
        Alias: persist
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $module = @(
        (Join-Path $global:PSP_Faire 'scripts\Faire.psm1')
        (Join-Path (Split-Path -Parent $global:PSP_Path) 'Faire\Faire.psm1')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $module) {
        Write-Warning "Faire.psm1 not found. Install Faire, or put the Faire folder next to your profile."
        return
    }
    Import-Module $module -Force -DisableNameChecking
    Get-FairePersistence | Add-DisplaySet Type, Name, Command
}

function Invoke-FieldSnapshot {
    <#
    .SYNOPSIS
        One-command before/after evidence capture for a site visit, zipped.
    .DESCRIPTION
        Grabs system info, disks, full IP config, routes, listening ports,
        running services, installed software, printers and hotfixes into a
        timestamped folder named for the machine and a label you choose, then
        zips it. Each section fails independently, so one broken command never
        kills the capture.
    .PARAMETER Label
        Short tag for the capture, e.g. 'before' or 'after'.
    .PARAMETER Destination
        Where to save. Default: Desktop\Snapshots.
    .PARAMETER NoZip
        Keep the folder instead of zipping it.
    .EXAMPLE
        snap before
        ... do the work ...
        snap after
    .EXAMPLE
        Compare-Object (Get-Content .\before\software.csv) (Get-Content .\after\software.csv)
        What changed.
    .OUTPUTS
        System.String (path to the zip or folder)
    .NOTES
        Captures config data from the client's machine; handle per their policy.
        Alias: snap
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)][string]$Label = 'snapshot',
        [string]$Destination = $global:PSP_Snapshots,
        [switch]$NoZip
    )

    $name = '{0}_{1}_{2}' -f [Environment]::MachineName, ($Label -replace '[^\w-]', '_'), (Get-Timestamp)
    $dir  = Join-Path $Destination $name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $sections = [ordered]@{
        'system.txt'    = { Get-SystemInfo | Format-List | Out-String -Width 250 }
        'disks.txt'     = { Get-DiskSpace | Select-Object * | Format-Table -AutoSize | Out-String -Width 250 }
        'ipconfig.txt'  = { ipconfig /all | Out-String }
        'routes.txt'    = { route print | Out-String }
        'listening.txt' = { Get-ListeningPort | Select-Object * | Format-Table -AutoSize | Out-String -Width 400 }
        'services.txt'  = { Get-Service | Where-Object Status -eq 'Running' | Sort-Object Name | Format-Table -AutoSize | Out-String -Width 250 }
        'printers.txt'  = { Get-Printer | Format-Table Name, DriverName, PortName, Shared -AutoSize | Out-String -Width 250 }
        'hotfixes.txt'  = { Get-HotFix | Sort-Object InstalledOn -Descending | Format-Table -AutoSize | Out-String -Width 250 }
    }

    foreach ($file in $sections.Keys) {
        Write-Host "  $file" -ForegroundColor DarkGray
        try   { & $sections[$file] | Set-Content -LiteralPath (Join-Path $dir $file) -Encoding UTF8 }
        catch { "FAILED: $($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $dir $file) -Encoding UTF8 }
    }
    try   { Get-InstalledSoftware | Select-Object * | Export-Csv -LiteralPath (Join-Path $dir 'software.csv') -NoTypeInformation -Encoding UTF8 }
    catch { "FAILED: $($_.Exception.Message)" | Set-Content -LiteralPath (Join-Path $dir 'software.csv') }

    if ($NoZip) {
        Write-Host "Snapshot: $dir" -ForegroundColor Green
        return $dir
    }
    $zip = "$dir.zip"
    $ProgressPreference = 'SilentlyContinue'
    Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zip -Force
    Remove-Item -LiteralPath $dir -Recurse -Force
    Write-Host "Snapshot: $zip" -ForegroundColor Green
    $zip
}

function Get-FaireStatus {
    <#
    .SYNOPSIS
        Dashboard for the Faire scheduled tasks: last run, result, next run, recent log lines.
    .PARAMETER Tail
        Log lines to show per script. Default 5.
    .EXAMPLE
        faire
    .NOTES
        Result: OK = exit 0, Running, Never run, else the hex exit code
        (0x1 = the script caught an error; check its log).
        Alias: faire
    #>
    [CmdletBinding()]
    param([ValidateRange(0, 500)][int]$Tail = 5)

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { Write-Warning 'Windows only.'; return }

    $tasks = @(Get-ScheduledTask -TaskPath '\Faire\' -ErrorAction SilentlyContinue)
    if (-not $tasks.Count) {
        Write-Host "No Faire tasks registered. Run Faire\Install-Faire.ps1 as admin." -ForegroundColor Yellow
    }
    else {
        $tasks | ForEach-Object {
            $i = Get-ScheduledTaskInfo -InputObject $_
            [pscustomobject]@{
                Task    = $_.TaskName
                State   = $_.State
                LastRun = $i.LastRunTime
                Result  = switch ($i.LastTaskResult) { 0 { 'OK' } 267009 { 'Running' } 267011 { 'Never run' } default { '0x{0:X}' -f $_ } }
                NextRun = $i.NextRunTime
            }
        } | Format-Table -AutoSize | Out-Host
    }

    $logDir = Join-Path $global:PSP_Faire 'logs'
    if ($Tail -and (Test-Path -LiteralPath $logDir)) {
        Get-ChildItem -LiteralPath $logDir -Filter *.log -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Group-Object { $_.BaseName -replace '_\d{4}-\d{2}$', '' } |
            ForEach-Object {
                $f = $_.Group[0]
                Write-Host "--- $($_.Name)" -ForegroundColor Cyan
                Get-Content -LiteralPath $f.FullName -Tail $Tail | ForEach-Object {
                    $color = if ($_ -match '\[ERROR\]') { 'Red' } elseif ($_ -match '\[WARN\]') { 'Yellow' } else { 'Gray' }
                    Write-Host "  $_" -ForegroundColor $color
                }
            }
    }
}

function Open-Doras {
    <#
    .SYNOPSIS
        Time-boxed CFA pass: lets PowerShell write to protected folders, then relocks itself.
    .DESCRIPTION
        Adds powershell.exe (and pwsh.exe if installed) to Controlled Folder Access's
        allowed apps, and registers a one-shot SYSTEM task that removes them after
        -Minutes, even if you close the window or forget. Needs elevation, so the
        UAC prompt is the password gate. Opening and closing are written to the
        Application log (source Faire, events 150/151) for your own audit trail.
    .PARAMETER Minutes
        How long the door stays open. Default 15, max 240.
    .EXAMPLE
        doras
    .EXAMPLE
        doras 5
    .NOTES
        While open, ANY PowerShell process can write to protected folders, not just
        yours. Keep it short. Alias: doras (Irish: door). Close early with dorasoff.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Doras is Irish for door (singular)')]
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Position = 0)][ValidateRange(1, 240)][int]$Minutes = 15)

    if (-not $global:PSP_IsAdmin) { Write-Warning 'Needs elevation: run Start-AsAdmin first. That UAC prompt is the gate.'; return }

    $apps = @(
        (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $until = (Get-Date).AddMinutes($Minutes)
    if (-not $PSCmdlet.ShouldProcess(($apps -join ', '), "Allow through Controlled Folder Access until $($until.ToString('HH:mm'))")) { return }

    Add-MpPreference -ControlledFolderAccessAllowedApplications $apps

    # Defender needs a moment to enforce the entry; probe until a real write succeeds (max ~15s)
    $probe = Join-Path ([Environment]::GetFolderPath('MyDocuments')) '.doras-probe'
    $open = $false
    foreach ($i in 1..15) {
        Start-Sleep -Seconds 1
        try { Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop; Remove-Item -LiteralPath $probe -Force; $open = $true; break }
        catch { Write-Verbose "Doras probe $i : not yet" }
    }
    if (-not $open) { Write-Warning 'Allow entry added, but Documents still refuses writes after 15s. Check Defender event 1123.' }

    $list   = "'" + ($apps -join "','") + "'"
    $relock = "Remove-MpPreference -ControlledFolderAccessAllowedApplications $list -ErrorAction SilentlyContinue; " +
              "eventcreate.exe /T INFORMATION /ID 151 /L APPLICATION /SO Faire /D 'Doras auto-relocked'; " +
              "Unregister-ScheduledTask -TaskPath '\Doras\' -TaskName Relock -Confirm:`$false"
    $action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
                -Argument "-NoProfile -NonInteractive -Command `"$relock`""
    $trigger   = New-ScheduledTaskTrigger -Once -At $until
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskPath '\Doras\' -TaskName Relock -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null

    $null = & eventcreate.exe /T WARNING /ID 150 /L APPLICATION /SO Faire /D "Doras opened by $env:USERNAME for $Minutes min" 2>&1
    Write-Host "Doras OPEN until $($until.ToString('HH:mm')) - PowerShell can write to protected folders." -ForegroundColor Yellow
}

function Close-Doras {
    <#
    .SYNOPSIS
        Relocks Controlled Folder Access for PowerShell now and cancels the timer.
    .EXAMPLE
        dorasoff
    .NOTES
        Alias: dorasoff. Check state any time with:
        (Get-MpPreference).ControlledFolderAccessAllowedApplications
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Doras is Irish for door (singular)')]
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not $global:PSP_IsAdmin) { Write-Warning 'Needs elevation: run Start-AsAdmin first.'; return }
    $apps = @(
        (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
    )
    if (-not $PSCmdlet.ShouldProcess('PowerShell', 'Remove Controlled Folder Access allowance')) { return }

    Remove-MpPreference -ControlledFolderAccessAllowedApplications $apps -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskPath '\Doras\' -TaskName Relock -Confirm:$false -ErrorAction SilentlyContinue
    $null = & eventcreate.exe /T INFORMATION /ID 151 /L APPLICATION /SO Faire /D "Doras closed by $env:USERNAME" 2>&1
    Write-Host 'Doras CLOSED - Controlled Folder Access fully enforced.' -ForegroundColor Green
}

function Show-ProfileCommand {
    <#
    .SYNOPSIS
        Cheat sheet: every function in this profile, its aliases and what it does.
    .DESCRIPTION
        Two views, both read straight out of each function's own help, so they
        never go stale:
          List   - one line per command (Source, Name, Alias, Synopsis).
          Detail - a full card per command: what it does, every option and
                   what it takes, and worked examples.
        Naming one command or alias exactly (cheat seala) opens its card.
        A wildcard (cheat *port*) lists matches; add -Detail for their cards.
        Also covers modules named in $global:PSP_CheatModules.
    .PARAMETER Filter
        Command name, alias, or wildcard matched against name, alias and synopsis.
    .PARAMETER Detail
        Show the full card for every match instead of the one-line list.
    .EXAMPLE
        cheat
    .EXAMPLE
        cheat seala
    .EXAMPLE
        cheat *glas* -Detail
    .OUTPUTS
        List view: PSCustomObject (Source, Name, Alias, Synopsis). Detail view: host text.
    .NOTES
        Alias: cheat
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)][string]$Filter = '*',
        [switch]$Detail
    )

    foreach ($m in @($global:PSP_CheatModules)) {
        if ($m -and -not (Get-Module $m)) {
            try   { Import-Module $m -ErrorAction Stop }
            catch { Write-Warning "cheat: module '$m' failed to load: $($_.Exception.Message)" }
        }
    }

    $aliasMap = @{}
    foreach ($a in Get-Alias) {
        if ($a.ResolvedCommandName) { $aliasMap[$a.ResolvedCommandName] += @($a.Name) }
    }

    $items = Get-Command -CommandType Function |
        Where-Object {
            ($_.ScriptBlock.File -and $_.ScriptBlock.File -eq $global:PSP_Path -and $_.Name -ne 'Add-DisplaySet') -or
            ($_.ModuleName -and $_.ModuleName -in @($global:PSP_CheatModules))
        } |
        ForEach-Object {
            $h = $null
            try { $h = $_.ScriptBlock.Ast.GetHelpContent() }
            catch { Write-Verbose "No help for $($_.Name)" }
            [pscustomobject]@{
                Source   = if ($_.ModuleName) { $_.ModuleName } else { 'profile' }
                Name     = $_.Name
                Aliases  = @($aliasMap[$_.Name] | Where-Object { $_ } | Sort-Object)
                Synopsis = if ($h) { "$($h.Synopsis)".Trim() } else { '' }
                Help     = $h
                Command  = $_
            }
        } |
        Sort-Object Source, Name

    # Exact name or alias (no wildcard) opens the card for that command.
    $exact = @()
    if ($Filter -notmatch '[\*\?\[]') {
        $exact = @($items | Where-Object { $_.Name -eq $Filter -or $_.Aliases -contains $Filter })
    }
    $hits = if ($exact.Count) { $exact } else {
        @($items | Where-Object {
            $_.Name -like $Filter -or ($_.Aliases -like $Filter) -or $_.Synopsis -like $Filter
        })
    }

    if (-not ($Detail -or $exact.Count)) {
        $hits | ForEach-Object {
            [pscustomobject]@{
                Source   = $_.Source
                Name     = $_.Name
                Alias    = $_.Aliases -join ', '
                Synopsis = $_.Synopsis
            }
        }
        return
    }

    $common = [System.Management.Automation.PSCmdlet]::CommonParameters +
              [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    $indent = {
        param([string]$Text, [int]$Pad)
        foreach ($l in ("$Text".Trim() -split '\r?\n')) { (' ' * $Pad) + $l.Trim() }
    }

    foreach ($i in $hits) {
        $h = $i.Help
        Write-Host ''
        Write-Host $i.Name -ForegroundColor DarkMagenta -NoNewline
        if ($i.Aliases.Count) { Write-Host "  ($($i.Aliases -join ', '))" -ForegroundColor Green -NoNewline }
        Write-Host "  [$($i.Source)]" -ForegroundColor DarkGray
        if ($i.Synopsis) { Write-Host "  $($i.Synopsis)" }

        if ($h -and "$($h.Description)".Trim()) {
            Write-Host ''
            Write-Host '  WHAT IT DOES' -ForegroundColor DarkMagenta
            & $indent $h.Description 4 | ForEach-Object { Write-Host $_ }
        }

        $params = @($i.Command.Parameters.Values | Where-Object { $common -notcontains $_.Name })
        if ($params.Count) {
            Write-Host ''
            Write-Host '  OPTIONS' -ForegroundColor DarkMagenta
            foreach ($p in $params) {
                $type = if ($p.SwitchParameter) { 'switch' } else { $p.ParameterType.Name }
                Write-Host ("    -{0}" -f $p.Name) -ForegroundColor Green -NoNewline
                Write-Host "  <$type>" -ForegroundColor DarkGray
                $text = $null
                if ($h -and $h.Parameters) { $text = $h.Parameters[$p.Name.ToUpperInvariant()] }
                if ("$text".Trim()) { & $indent $text 8 | ForEach-Object { Write-Host $_ } }
            }
        }

        if ($h -and $h.Examples -and $h.Examples.Count) {
            Write-Host ''
            Write-Host '  HOW TO USE' -ForegroundColor DarkMagenta
            foreach ($e in $h.Examples) {
                $lines = @("$e".Trim() -split '\r?\n')
                Write-Host "    $($lines[0].Trim())" -ForegroundColor Green
                foreach ($l in ($lines | Select-Object -Skip 1)) { Write-Host "      $($l.Trim())" -ForegroundColor DarkGray }
            }
        }

        if ($h -and "$($h.Notes)".Trim()) {
            Write-Host ''
            Write-Host '  NOTES' -ForegroundColor DarkMagenta
            & $indent $h.Notes 4 | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
        }
    }
    Write-Host ''
}

function Unblock-Download {
    <#
    .SYNOPSIS
        Removes the "downloaded from the internet" mark from files (alias: unblock).
    .DESCRIPTION
        Deletes the Zone.Identifier stream directly, since Unblock-File alone
        has failed on this machine. Clears the "not digitally signed" error.
    .PARAMETER Path
        File or folder. Defaults to the current folder.
    .PARAMETER Recurse
        Include subfolders.
    .EXAMPLE
        unblock
    .EXAMPLE
        unblock C:\Tools\SomeModule -Recurse
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Path = '.',
        [switch]$Recurse
    )
    Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse | ForEach-Object {
        if (Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
            $left = Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue
            [pscustomobject]@{ Result = if ($left) { 'BLOCKED' } else { 'Unblocked' }; File = $_.FullName }
        }
    }
}

#endregion