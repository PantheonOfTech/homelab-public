<# ================================================================
#  Install-Glas.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Glas (Irish: lock)
#  Role: Installs the Glas module for all users (5.1 + pwsh 7)
#  Runs: Manually, elevated
#  Last Modified: 10/12/2026
# ================================================================#>

<#
.SYNOPSIS
    Installs Glas to C:\Program Files\WindowsPowerShell\Modules\Glas.
.DESCRIPTION
    That folder is on the module path of BOTH Windows PowerShell 5.1 and
    pwsh 7, so lock/unlock/newsecret/etc. autoload everywhere, including in
    scripts run with -NoProfile and in scheduled tasks. It's also admin-only
    writable, so nothing running as a normal user can swap your crypto code
    for a version that quietly logs passwords.
    Unblocks the files first (downloaded files carry Mark-of-the-Web, which
    RemoteSigned refuses to run).
.EXAMPLE
    .\Install-Glas.ps1
.EXAMPLE
    .\Install-Glas.ps1 -Uninstall
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules\Glas'

if ($Uninstall) {
    if ((Test-Path -LiteralPath $dest) -and $PSCmdlet.ShouldProcess($dest, 'Remove')) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Write-Host 'Glas removed. Your secrets log (%LOCALAPPDATA%\Glas) was not touched.' -ForegroundColor Green
    return
}

foreach ($f in 'Glas.psm1', 'Glas.psd1') {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $f))) { throw "Missing $f next to the installer." }
}
if ($PSCmdlet.ShouldProcess($dest, 'Install Glas module')) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    foreach ($f in 'Glas.psm1', 'Glas.psd1') {
        $src = Join-Path $PSScriptRoot $f
        Unblock-File -LiteralPath $src
        Copy-Item -LiteralPath $src -Destination $dest -Force
    }
    Get-ChildItem -LiteralPath $dest | Unblock-File
}

$m = Get-Module -ListAvailable Glas | Select-Object -First 1
if ($m) {
    Write-Host "Glas $($m.Version) installed: $($m.ModuleBase)" -ForegroundColor Green
    Write-Host "Try: genpass   |   lock 'test'   |   Get-Help lock -Examples" -ForegroundColor DarkGray
}
else { Write-Warning 'Installed, but Get-Module -ListAvailable cannot see it. Check $env:PSModulePath.' }
