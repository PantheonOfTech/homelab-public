<# ================================================================
#  Install-Seala.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Seala (Irish: seal)
#  Role: Installs the Seala module for all users (5.1 + pwsh 7)
#  Runs: Manually, elevated
#  Last Modified: 2026-10-03 17:18 CDT
#  Changelog (newest first):
#    2026-10-03 17:18 CDT - Initial version
# ================================================================#>

<#
.SYNOPSIS
    Installs Seala to C:\Program Files\WindowsPowerShell\Modules\Seala.
.DESCRIPTION
    Same pattern as Glas: that folder is on the module path of both Windows
    PowerShell 5.1 and pwsh 7, so `seala` / Set-ScriptHeader autoload in every
    host, including -NoProfile sessions. It is admin-only writable.
    Strips Mark-of-the-Web (Zone.Identifier) from source and installed files,
    since Unblock-File alone has failed on this machine before.
.EXAMPLE
    .\Install-Seala.ps1
.EXAMPLE
    .\Install-Seala.ps1 -Uninstall
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$files = 'Seala.psm1', 'Seala.psd1'
$dest  = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules\Seala'

function Clear-Motw ([string]$File) {
    Unblock-File -LiteralPath $File -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $File -Stream Zone.Identifier -ErrorAction SilentlyContinue
}

if ($Uninstall) {
    if ((Test-Path -LiteralPath $dest) -and $PSCmdlet.ShouldProcess($dest, 'Remove')) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Write-Host 'Seala removed.' -ForegroundColor Green
    return
}

foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $f))) { throw "Missing $f next to the installer." }
}

if ($PSCmdlet.ShouldProcess($dest, 'Install Seala module')) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    foreach ($f in $files) {
        $src = Join-Path $PSScriptRoot $f
        Clear-Motw $src
        Copy-Item -LiteralPath $src -Destination $dest -Force
        Clear-Motw (Join-Path $dest $f)
    }

    Remove-Module Seala -ErrorAction SilentlyContinue
    $m = Get-Module -ListAvailable Seala | Select-Object -First 1
    if ($m) {
        Write-Host "Seala $($m.Version) installed: $($m.ModuleBase)" -ForegroundColor Green
        Write-Host "Try: seala .\Some-Script.ps1 -WhatIf   |   Get-Help seala -Examples" -ForegroundColor DarkGray
    }
    else { Write-Warning 'Installed, but Get-Module -ListAvailable cannot see it. Check $env:PSModulePath.' }
}
