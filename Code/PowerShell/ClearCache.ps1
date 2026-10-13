<# ================================================================
#  ClearCache.ps1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Role: Closes Edge and Chrome in the current session, then clears their caches
#  Runs: On demand
#  Created: 2026-09-23
#  Last Modified: 2026-09-23
# ================================================================#>

# Close browsers in the current user's session only
$session = (Get-Process -Id $PID).SessionId
Get-Process msedge, chrome -ErrorAction SilentlyContinue |
    Where-Object SessionId -eq $session |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Clear Edge cache
Remove-Item "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue

# Clear Chrome cache
Remove-Item "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue