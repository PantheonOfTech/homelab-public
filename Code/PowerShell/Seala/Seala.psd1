<# ================================================================
#  Seala.psd1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Seala (Irish: seal)
#  Role: Module manifest
#  Runs: Loaded by PowerShell
#  Last Modified: 2026-10-12 17:30 CDT
#  Changelog (newest first):
#    2026-10-12 17:30 CDT - v1.2.0
#    2026-10-03 18:39 CDT - v1.1.1
#    2026-10-03 17:18 CDT - Initial manifest (v1.1.0)
# ================================================================#>

@{
    RootModule           = 'Seala.psm1'
    ModuleVersion        = '1.2.0'
    GUID                 = '40da0eab-7add-4bce-9818-e2680b6382b4'
    Author               = 'Daniel J. Benoit'
    Copyright            = '(c) 2026 PantheonOfTech. MIT License.'
    Description          = 'Seala: applies and maintains the standard header block (IP notice, Last Modified, rolling changelog) on PowerShell files.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Set-ScriptHeader')
    AliasesToExport      = @('seala')
    CmdletsToExport      = @()
    VariablesToExport    = @()
}
