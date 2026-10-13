<# ================================================================
#  Example-Glas.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Glas (Irish: lock)
#  Role: Template - how a script of yours generates, stores and uses secrets
#  Runs: Copy the pattern you need into your own scripts
#  Last Modified: 9/29/2026
# ================================================================#>

<#
.SYNOPSIS
    Template showing the three Glas patterns for your own scripts.
.DESCRIPTION
    PATTERN 1 - secret baked into the script (unattended, runs as you on this PC)
        Start with a placeholder line:        $NasPass = ''
        Then once, from your shell:           lockvar .\Example-Glas.ps1 NasPass -ThisPC -Generate -Copy
        The line becomes:                     $NasPass = Unprotect-GlasText 'GLAS1:U:...'
        and the new password is on your clipboard to set on the NAS.

    PATTERN 2 - secret kept in your secrets log (interactive, portable)
        newsecret nas-admin -Copy             generate + encrypt + log
        getsecret nas-admin -AsCredential     use it

    PATTERN 3 - generate, encrypt and write into a LOG line from inside a script
        see the -Rotate branch below.
.PARAMETER Rotate
    Demo: generate a new password inside the script, log it encrypted, and
    write it back into this file.
.NOTES
    -ThisPC (DPAPI) secrets decrypt only for the same Windows account on the
    same PC. Scheduled tasks registered with S4U logon ("run whether logged on
    or not, don't store password") CANNOT decrypt them: DPAPI needs your
    password-derived key, which S4U doesn't have. For those, register the task
    with your stored password (LogonType Password) or use password mode with a
    session-less approach you trust.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Value was just decrypted by Glas')]
[CmdletBinding()]
param([switch]$Rotate)

# Glas autoloads from the module path; this line just makes the dependency explicit
Import-Module Glas -ErrorAction Stop

# --- PATTERN 1: placeholder, becomes an encrypted line after lockvar -----------------
$NasPass = ''

if ($Rotate) {
    # --- PATTERN 3: rotate from inside a script -------------------------------------
    $blob = New-GlasSecret -Name 'example-nas' -ThisPC -ScriptPath $PSCommandPath -Variable NasPass -Copy
    Write-Host "New blob stored in log and in this script: $($blob.Substring(0, 20))..." -ForegroundColor Cyan
    return
}

if (-not $NasPass) {
    Write-Host "NasPass is empty. Run:  lockvar '$PSCommandPath' NasPass -ThisPC -Generate -Copy" -ForegroundColor Yellow
    return
}

# Use it: never print it, hand it to the thing that needs it
$cred = [pscredential]::new('backup', (ConvertTo-SecureString $NasPass -AsPlainText -Force))
Remove-Variable NasPass
Write-Host "Credential ready for $($cred.UserName) (password length $($cred.GetNetworkCredential().Password.Length))." -ForegroundColor Green
# e.g. New-PSDrive -Name NAS -PSProvider FileSystem -Root \\nas\backup -Credential $cred
