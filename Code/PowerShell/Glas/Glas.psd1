<# ================================================================
#  Glas.psd1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Glas (Irish: lock)
#  Role: Module manifest - lets the aliases autoload in any session
#  Runs: Read by PowerShell on first use of any Glas command or alias
#  Last Modified: 10/12/2026
# ================================================================#>
@{
    RootModule           = 'Glas.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = '34d50f28-c8bc-4aa7-aead-57951136d384'
    Author               = 'Daniel J. Benoit'
    Copyright            = '(c) 2026 PantheonOfTech. MIT License.'
    Description          = 'Glas: AES-256/PBKDF2 and DPAPI encryption for text, files, secrets logs and script variables.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('New-GlasPassword', 'Unlock-GlasSession', 'Lock-GlasSession', 'Protect-GlasText',
                             'Unprotect-GlasText', 'Protect-GlasFile', 'Unprotect-GlasFile', 'New-GlasSecret',
                             'Read-GlasSecret', 'Lock-GlasScriptVariable')
    AliasesToExport      = @('genpass', 'glas', 'glasoff', 'lock', 'unlock', 'lockf', 'unlockf', 'newsecret', 'getsecret', 'lockvar')
    CmdletsToExport      = @()
    VariablesToExport    = @()
}
