<# ================================================================
#  Glas.psm1
#  Author:  Daniel J. Benoit (github.com/PantheonOfTech)
#  License: MIT - see LICENSE in the repo root
#  Suite: Glas (Irish: lock) - encryption for text, files and script secrets
#  Role: AES-256 + password (portable) and DPAPI (this PC + account) helpers
#  Runs: Autoloaded from the AllUsers module path in 5.1 and pwsh 7
#  Last Modified: 10/12/2026
# ================================================================#>

<#
    FORMAT (v1, all integers little-endian)
      [tag 6 ASCII: GLAS1P text | GLAS1F file][iterations int32][salt 16][iv 16][ciphertext][hmac 32]
      Key = PBKDF2-HMAC-SHA256(password, salt, iterations) -> 64 bytes
            bytes 0-31  AES-256-CBC key, bytes 32-63 HMAC-SHA256 key
      HMAC covers everything before it (encrypt-then-MAC), checked in constant
      time BEFORE decrypting. Wrong password and tampering look identical, on purpose.

    Text blobs:  GLAS1:P:<base64 of the binary above>   password mode, portable
                 GLAS1:U:<DPAPI hex>                     this Windows account on this PC only

    Keep this file pure ASCII (Windows PowerShell 5.1 + no BOM = mojibake).
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Converts values this module just generated or decrypted')]
param()

$script:Iterations = 600000      # OWASP 2023 guidance for PBKDF2-HMAC-SHA256; stored per blob
# LocalAppData, not Documents: Controlled Folder Access blocks PowerShell writes to Documents
$script:DefaultLog = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Glas\secrets.log'
$script:Cache      = $null

#region PRIVATE
function Get-GlasRandomByte {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Returns byte[] via unary comma')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([int]$Count)
    $b = [byte[]]::new($Count)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return , $b
}

function Test-GlasEqual {
    # constant-time compare so the MAC check doesn't leak timing
    [CmdletBinding()]
    [OutputType([bool])]
    param([byte[]]$A, [byte[]]$B)
    if ($A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $diff = $diff -bor ($A[$i] -bxor $B[$i]) }
    return ($diff -eq 0)
}

function ConvertFrom-GlasSecureString {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Returns byte[] via unary comma')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([securestring]$Secure)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try   { return , [Text.Encoding]::UTF8.GetBytes([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Resolve-GlasPassword {
    [CmdletBinding()]
    [OutputType([securestring])]
    param([securestring]$Password, [switch]$ForEncrypt)

    if ($Password) { return $Password }
    if ($script:Cache -and $script:Cache.Expires -gt (Get-Date)) { return $script:Cache.Password }
    if ($script:Cache) { $script:Cache = $null; Write-Warning 'Glas session expired.' }

    $p1 = Read-Host 'Glas password' -AsSecureString
    if ($p1.Length -eq 0) { throw 'Empty password.' }
    if ($ForEncrypt) {
        $p2 = Read-Host 'Confirm password' -AsSecureString
        $b1 = ConvertFrom-GlasSecureString $p1; $b2 = ConvertFrom-GlasSecureString $p2
        $same = Test-GlasEqual $b1 $b2
        [Array]::Clear($b1, 0, $b1.Length); [Array]::Clear($b2, 0, $b2.Length)
        if (-not $same) { throw 'Passwords did not match.' }
        if ($p1.Length -lt 12) { Write-Warning 'Under 12 characters. Anyone holding the ciphertext can guess offline, forever.' }
    }
    return $p1
}

function Get-GlasKey {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Returns byte[] via unary comma')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([byte[]]$PasswordBytes, [byte[]]$Salt, [int]$Iterations)
    $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $PasswordBytes, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try { return , $kdf.GetBytes(64) } finally { $kdf.Dispose() }
}

function ConvertTo-GlasCipher {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Returns byte[] via unary comma')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([byte[]]$Plain, [securestring]$Password, [ValidateSet('GLAS1P', 'GLAS1F')][string]$Tag)

    $pw   = ConvertFrom-GlasSecureString $Password
    $salt = Get-GlasRandomByte -Count 16
    $iv   = Get-GlasRandomByte -Count 16
    $keys = Get-GlasKey -PasswordBytes $pw -Salt $salt -Iterations $script:Iterations
    $aes  = [System.Security.Cryptography.Aes]::Create()
    $hmac = $null
    try {
        $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
        $aes.Key = [byte[]]$keys[0..31]; $aes.IV = $iv
        $ct = $aes.CreateEncryptor().TransformFinalBlock($Plain, 0, $Plain.Length)

        $ms = [System.IO.MemoryStream]::new()
        $ms.Write([Text.Encoding]::ASCII.GetBytes($Tag), 0, 6)
        $ms.Write([BitConverter]::GetBytes([int]$script:Iterations), 0, 4)
        $ms.Write($salt, 0, 16); $ms.Write($iv, 0, 16); $ms.Write($ct, 0, $ct.Length)
        $hmac = [System.Security.Cryptography.HMACSHA256]::new([byte[]]$keys[32..63])
        $mac  = $hmac.ComputeHash($ms.ToArray())
        $ms.Write($mac, 0, 32)
        return , $ms.ToArray()
    }
    finally {
        [Array]::Clear($pw, 0, $pw.Length); [Array]::Clear($keys, 0, $keys.Length)
        $aes.Dispose(); if ($hmac) { $hmac.Dispose() }
    }
}

function ConvertFrom-GlasCipher {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Returns byte[] via unary comma')]
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([byte[]]$Data, [securestring]$Password, [ValidateSet('GLAS1P', 'GLAS1F')][string]$Tag)

    if ($Data.Length -lt 90) { throw 'Not Glas data (too short).' }
    if ([Text.Encoding]::ASCII.GetString($Data, 0, 6) -ne $Tag) { throw "Not Glas data (expected $Tag header)." }
    $iter = [BitConverter]::ToInt32($Data, 6)
    if ($iter -lt 10000 -or $iter -gt 50000000) { throw 'Corrupt header (iteration count).' }

    $salt  = [byte[]]$Data[10..25]
    $iv    = [byte[]]$Data[26..41]
    $macAt = $Data.Length - 32
    $mac   = [byte[]]$Data[$macAt..($Data.Length - 1)]

    $pw   = ConvertFrom-GlasSecureString $Password
    $keys = Get-GlasKey -PasswordBytes $pw -Salt $salt -Iterations $iter
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([byte[]]$keys[32..63])
    $aes  = [System.Security.Cryptography.Aes]::Create()
    try {
        if (-not (Test-GlasEqual $mac $hmac.ComputeHash($Data, 0, $macAt))) {
            throw 'Wrong password, or the data was modified.'
        }
        $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
        $aes.Key = [byte[]]$keys[0..31]; $aes.IV = $iv
        return , $aes.CreateDecryptor().TransformFinalBlock($Data, 42, $macAt - 42)
    }
    finally {
        [Array]::Clear($pw, 0, $pw.Length); [Array]::Clear($keys, 0, $keys.Length)
        $aes.Dispose(); $hmac.Dispose()
    }
}

function Read-GlasTextFile {
    # returns @{ Text; Encoding } preserving BOM/encoding for write-back
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$Path)
    $sr = [System.IO.StreamReader]::new($Path, [Text.UTF8Encoding]::new($false), $true)
    try { $t = $sr.ReadToEnd(); @{ Text = $t; Encoding = $sr.CurrentEncoding } } finally { $sr.Dispose() }
}

function Find-GlasScriptVariable {
    [CmdletBinding()]
    param([string]$Text, [string]$Name)
    $n = [regex]::Escape($Name.TrimStart('$'))
    $pattern = '(?m)^(?<lead>[ \t]*\$' + $n + '[ \t]*=[ \t]*)(?:(?<call>Unprotect-GlasText|unlock)[ \t]+)?' +
               '(?<q>[''"])(?<val>[^''"\r\n]*)\k<q>[ \t]*(?=\r?$)'
    $m = [regex]::Matches($Text, $pattern)
    if ($m.Count -eq 0) { throw "No line like  `$$($Name.TrimStart('$')) = '...'  found. Add a placeholder line first." }
    if ($m.Count -gt 1) { throw "`$$($Name.TrimStart('$')) is assigned $($m.Count) times; make it one line so the edit is unambiguous." }
    $m[0]
}

function Set-GlasScriptLine {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path, [string]$Name, [string]$Blob)
    $full  = Convert-Path -LiteralPath $Path
    $file  = Read-GlasTextFile $full
    $m     = Find-GlasScriptVariable $file.Text $Name
    $line  = "$($m.Groups['lead'].Value)Unprotect-GlasText '$Blob'"
    if ($PSCmdlet.ShouldProcess("$full : `$$($Name.TrimStart('$'))", 'Replace with encrypted value')) {
        $new = $file.Text.Substring(0, $m.Index) + $line + $file.Text.Substring($m.Index + $m.Length)
        [System.IO.File]::WriteAllText($full, $new, $file.Encoding)
        Write-Host "Updated `$$($Name.TrimStart('$')) in $full" -ForegroundColor Green
        Write-Host "Old plaintext may still exist in git history, editor backups or recycle bin." -ForegroundColor DarkGray
    }
}

function Assert-GlasWindows {
    [CmdletBinding()]
    param()
    if ($env:OS -ne 'Windows_NT') { throw '-ThisPC (DPAPI) is Windows-only. Use password mode.' }
}
#endregion

#region PUBLIC
function New-GlasPassword {
    <#
    .SYNOPSIS
        Cryptographically random password; -Copy keeps it off the screen.
    .DESCRIPTION
        OS crypto RNG with rejection sampling (no modulo bias). Guarantees at least
        one lowercase, uppercase, digit and (unless -NoSymbols) symbol. Symbols skip
        quotes and backslashes so results paste safely into shells and configs.
    .PARAMETER Length
        8 to 256. Default 24.
    .PARAMETER NoSymbols
        Letters and digits only.
    .PARAMETER Copy
        Clipboard instead of output.
    .EXAMPLE
        genpass -Copy
    .EXAMPLE
        genpass 32 -NoSymbols
    .OUTPUTS
        System.String (nothing with -Copy)
    .NOTES
        Clipboard history (Win+V) keeps copies. Alias: genpass
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)][ValidateRange(8, 256)][int]$Length = 24,
        [switch]$NoSymbols,
        [switch]$Copy
    )

    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    $need  = @('[a-z]', '[A-Z]', '[0-9]')
    if (-not $NoSymbols) { $chars += '!@#$%^&*-_=+?'; $need += '[^a-zA-Z0-9]' }

    $n = $chars.Length; $limit = 256 - (256 % $n)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $one = [byte[]]::new(1)
    try {
        do {
            $sb = [System.Text.StringBuilder]::new($Length)
            while ($sb.Length -lt $Length) {
                $rng.GetBytes($one)
                if ($one[0] -lt $limit) { [void]$sb.Append($chars[$one[0] % $n]) }
            }
            $pw = $sb.ToString()
        } until (-not ($need | Where-Object { $pw -cnotmatch $_ }))
    }
    finally { $rng.Dispose() }

    if ($Copy) { Set-Clipboard -Value $pw; Write-Host "Copied ($Length chars)." -ForegroundColor Green; return }
    $pw
}

function Unlock-GlasSession {
    <#
    .SYNOPSIS
        Type your Glas password once; lock/unlock/newsecret/getsecret reuse it for N minutes.
    .DESCRIPTION
        Asks twice (so a typo can't silently encrypt things with the wrong
        password) and caches it as a SecureString inside the module for this
        PowerShell session only. Nothing is written to disk.
    .PARAMETER Minutes
        How long the cache lives. Default 30.
    .EXAMPLE
        glas
    .EXAMPLE
        glas 120
    .NOTES
        Alias: glas. End early with glasoff.
    #>
    [CmdletBinding()]
    param([Parameter(Position = 0)][ValidateRange(1, 1440)][int]$Minutes = 30)

    $script:Cache = $null
    $p = Resolve-GlasPassword -ForEncrypt
    $script:Cache = @{ Password = $p; Expires = (Get-Date).AddMinutes($Minutes) }
    Write-Host "Glas unlocked until $($script:Cache.Expires.ToString('HH:mm'))." -ForegroundColor Green
}

function Lock-GlasSession {
    <#
    .SYNOPSIS
        Forgets the cached Glas password now.
    .EXAMPLE
        glasoff
    .NOTES
        Alias: glasoff
    #>
    [CmdletBinding()]
    param()
    if ($script:Cache) { $script:Cache.Password.Dispose() }
    $script:Cache = $null
    Write-Host 'Glas locked.' -ForegroundColor Yellow
}

function Protect-GlasText {
    <#
    .SYNOPSIS
        Encrypts text into a single-line GLAS1 blob, safe to store in logs or scripts.
    .DESCRIPTION
        Password mode (default): AES-256 + PBKDF2, decrypts anywhere with the
        password. -ThisPC: Windows DPAPI, no password, but only YOUR account on
        THIS PC can decrypt (right for secrets used by your own scheduled scripts).
    .PARAMETER Text
        Plain text. Accepts pipeline input.
    .PARAMETER ThisPC
        Use DPAPI instead of a password.
    .PARAMETER Password
        SecureString; otherwise uses the glas session or prompts.
    .PARAMETER Copy
        Put the blob on the clipboard instead of output.
    .EXAMPLE
        lock 'hunter2'
    .EXAMPLE
        'api-key-123' | lock -ThisPC
    .OUTPUTS
        System.String  (GLAS1:P:... or GLAS1:U:...)
    .NOTES
        Alias: lock
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)][AllowEmptyString()][string]$Text,
        [switch]$ThisPC,
        [securestring]$Password,
        [switch]$Copy
    )
    begin {
        if ($ThisPC) { Assert-GlasWindows } else { $pw = Resolve-GlasPassword -Password $Password -ForEncrypt }
    }
    process {
        if ($ThisPC) {
            $blob = 'GLAS1:U:' + (ConvertTo-SecureString -String $Text -AsPlainText -Force | ConvertFrom-SecureString)
        }
        else {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
            $blob  = 'GLAS1:P:' + [Convert]::ToBase64String((ConvertTo-GlasCipher -Plain $bytes -Password $pw -Tag GLAS1P))
            [Array]::Clear($bytes, 0, $bytes.Length)
        }
        if ($Copy) { Set-Clipboard -Value $blob; Write-Host 'Encrypted blob copied.' -ForegroundColor Green }
        else { $blob }
    }
}

function Unprotect-GlasText {
    <#
    .SYNOPSIS
        Decrypts a GLAS1 blob; auto-detects password vs. this-PC mode.
    .PARAMETER Blob
        GLAS1:P:... or GLAS1:U:... Accepts pipeline input.
    .PARAMETER Password
        SecureString; otherwise uses the glas session or prompts (password mode only).
    .PARAMETER AsSecureString
        Return a SecureString instead of plain text.
    .PARAMETER Copy
        Clipboard instead of output.
    .EXAMPLE
        unlock 'GLAS1:P:R0xBUzFQ...'
    .EXAMPLE
        $cred = [pscredential]::new('svc-backup', (unlock 'GLAS1:U:01000000d08c...' -AsSecureString))
    .OUTPUTS
        System.String or System.Security.SecureString
    .NOTES
        Alias: unlock
    #>
    [CmdletBinding()]
    [OutputType([string], [securestring])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)][string]$Blob,
        [securestring]$Password,
        [switch]$AsSecureString,
        [switch]$Copy
    )
    process {
        $Blob = $Blob.Trim()
        if ($Blob -like 'GLAS1:U:*') {
            Assert-GlasWindows
            try   { $ss = ConvertTo-SecureString -String $Blob.Substring(8) -ErrorAction Stop }
            catch { throw 'This blob was locked with -ThisPC by a different Windows account or PC (DPAPI).' }
            if ($AsSecureString) { return $ss }
            $plain = [Net.NetworkCredential]::new('', $ss).Password
        }
        elseif ($Blob -like 'GLAS1:P:*') {
            $pw = Resolve-GlasPassword -Password $Password
            try   { $data = [Convert]::FromBase64String($Blob.Substring(8)) }
            catch { throw 'Blob is not valid base64 (truncated when copied?).' }
            $bytes = ConvertFrom-GlasCipher -Data $data -Password $pw -Tag GLAS1P
            $plain = [Text.Encoding]::UTF8.GetString($bytes)
            [Array]::Clear($bytes, 0, $bytes.Length)
            if ($AsSecureString) { return (ConvertTo-SecureString -String $plain -AsPlainText -Force) }
        }
        else { throw 'Not a Glas blob (should start with GLAS1:P: or GLAS1:U:).' }

        if ($Copy) { Set-Clipboard -Value $plain; Write-Host 'Decrypted value copied.' -ForegroundColor Green }
        else { $plain }
    }
}

function Protect-GlasFile {
    <#
    .SYNOPSIS
        Encrypts a file to <name>.glas with AES-256 + password.
    .DESCRIPTION
        Same format as text mode, binary. The .glas file opens anywhere with the
        password. The original is kept unless -RemoveOriginal.
    .PARAMETER Path
        File(s) to encrypt. Accepts pipeline input.
    .PARAMETER Password
        SecureString; otherwise uses the glas session or prompts.
    .PARAMETER RemoveOriginal
        Delete the plaintext file after a successful encrypt.
    .PARAMETER Force
        Overwrite an existing .glas file.
    .EXAMPLE
        lockf .\client-notes.txt
    .EXAMPLE
        Get-ChildItem .\keys\* | lockf -RemoveOriginal
    .OUTPUTS
        System.IO.FileInfo
    .NOTES
        Whole file is processed in memory; fine for documents and archives, not
        for multi-GB images. -RemoveOriginal is a normal delete: on SSDs and
        synced folders the plaintext may be recoverable.
        Alias: lockf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')][string]$Path,
        [securestring]$Password,
        [switch]$RemoveOriginal,
        [switch]$Force
    )
    begin { $pw = $null }
    process {
        $full = Convert-Path -LiteralPath $Path -ErrorAction Stop
        $out  = "$full.glas"
        if ((Test-Path -LiteralPath $out) -and -not $Force) { Write-Error "$out exists (use -Force)."; return }
        $len = (Get-Item -LiteralPath $full).Length
        if ($len -gt 1GB) { Write-Error "$full is over 1 GB; too big for in-memory encryption."; return }
        if (-not $PSCmdlet.ShouldProcess($full, 'Encrypt')) { return }

        if (-not $pw) { $pw = Resolve-GlasPassword -Password $Password -ForEncrypt }
        $bytes = [System.IO.File]::ReadAllBytes($full)
        [System.IO.File]::WriteAllBytes($out, (ConvertTo-GlasCipher -Plain $bytes -Password $pw -Tag GLAS1F))
        [Array]::Clear($bytes, 0, $bytes.Length)

        if ($RemoveOriginal) { Remove-Item -LiteralPath $full -Force }
        Get-Item -LiteralPath $out
    }
}

function Unprotect-GlasFile {
    <#
    .SYNOPSIS
        Decrypts a .glas file back to the original name.
    .PARAMETER Path
        Encrypted file(s) (*.glas). Accepts pipeline input.
    .PARAMETER Destination
        Output path. Default: same name without .glas.
    .PARAMETER Password
        SecureString; otherwise uses the glas session or prompts.
    .PARAMETER Force
        Overwrite an existing output file.
    .EXAMPLE
        unlockf .\client-notes.txt.glas
    .OUTPUTS
        System.IO.FileInfo
    .NOTES
        Alias: unlockf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')][string]$Path,
        [string]$Destination,
        [securestring]$Password,
        [switch]$Force
    )
    begin { $pw = $null }
    process {
        $full = Convert-Path -LiteralPath $Path -ErrorAction Stop
        $out  = if ($Destination) { $Destination } elseif ($full -like '*.glas') { $full.Substring(0, $full.Length - 5) } else { "$full.decrypted" }
        if ((Test-Path -LiteralPath $out) -and -not $Force) { Write-Error "$out exists (use -Force)."; return }
        if (-not $PSCmdlet.ShouldProcess($full, "Decrypt to $out")) { return }

        if (-not $pw) { $pw = Resolve-GlasPassword -Password $Password }
        $plain = ConvertFrom-GlasCipher -Data ([System.IO.File]::ReadAllBytes($full)) -Password $pw -Tag GLAS1F
        [System.IO.File]::WriteAllBytes($out, $plain)
        [Array]::Clear($plain, 0, $plain.Length)
        Get-Item -LiteralPath $out
    }
}

function New-GlasSecret {
    <#
    .SYNOPSIS
        Generate a password, encrypt it, save it to the secrets log and/or into a script.
    .DESCRIPTION
        The one-shot workflow: new random password -> GLAS1 blob -> appended to
        the secrets log under a name (newest wins, older versions kept as
        history) -> optionally written straight into a script variable.
        The plaintext is never printed; use -Copy to put it on the clipboard so
        you can set it on the target system.
    .PARAMETER Name
        Label, e.g. 'nas-admin' or 'svc-backup'.
    .PARAMETER Length
        Password length. Default 24.
    .PARAMETER NoSymbols
        Letters and digits only.
    .PARAMETER ThisPC
        DPAPI instead of password (for secrets your own scheduled scripts read).
    .PARAMETER Password
        Glas password as SecureString; otherwise uses the glas session or prompts.
    .PARAMETER LogPath
        Secrets log. Default %LOCALAPPDATA%\Glas\secrets.log.
    .PARAMETER NoLog
        Don't write to the log.
    .PARAMETER ScriptPath
        Script to update; needs a line like  $Variable = ''  (or an older Glas line).
    .PARAMETER Variable
        Variable name in that script. Default: Name with dashes removed.
    .PARAMETER Copy
        Plaintext to clipboard.
    .EXAMPLE
        newsecret nas-admin -Copy
    .EXAMPLE
        newsecret svc-backup -ThisPC -ScriptPath .\Backup-Nas.ps1 -Variable NasPass -Copy
        Rotates the password inside the script and gives you the new one to set on the NAS.
    .OUTPUTS
        System.String (the blob)
    .NOTES
        Alias: newsecret
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)][ValidatePattern('^[\w.-]+$')][string]$Name,
        [ValidateRange(8, 256)][int]$Length = 24,
        [switch]$NoSymbols,
        [switch]$ThisPC,
        [securestring]$Password,
        [string]$LogPath = $script:DefaultLog,
        [switch]$NoLog,
        [string]$ScriptPath,
        [string]$Variable,
        [switch]$Copy
    )

    $plain = New-GlasPassword -Length $Length -NoSymbols:$NoSymbols
    $blob  = Protect-GlasText -Text $plain -ThisPC:$ThisPC -Password $Password

    if (-not $NoLog) {
        $dir = Split-Path -Parent $LogPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $LogPath -Value ("{0:yyyy-MM-dd HH:mm:ss}`t{1}`t{2}" -f (Get-Date), $Name, $blob) -Encoding UTF8
        Write-Host "Saved '$Name' to $LogPath" -ForegroundColor Green
    }
    if ($ScriptPath) {
        if (-not $Variable) { $Variable = $Name -replace '[^\w]', '' }
        Set-GlasScriptLine -Path $ScriptPath -Name $Variable -Blob $blob
    }
    if ($Copy) { Set-Clipboard -Value $plain; Write-Host 'New password copied to clipboard.' -ForegroundColor Green }
    $plain = $null
    $blob
}

function Read-GlasSecret {
    <#
    .SYNOPSIS
        Gets a secret from the secrets log by name (newest version), decrypted.
    .PARAMETER Name
        Label used with newsecret.
    .PARAMETER List
        Show stored names, dates and version counts without decrypting anything.
    .PARAMETER LogPath
        Secrets log. Default %LOCALAPPDATA%\Glas\secrets.log.
    .PARAMETER Password
        SecureString; otherwise uses the glas session or prompts.
    .PARAMETER Copy
        Clipboard instead of output.
    .PARAMETER AsCredential
        Return a PSCredential using -UserName.
    .PARAMETER UserName
        User name for -AsCredential. Default: the secret's name.
    .EXAMPLE
        getsecret -List
    .EXAMPLE
        getsecret nas-admin -Copy
    .EXAMPLE
        $cred = getsecret svc-backup -AsCredential -UserName 'NAS\backup'
    .OUTPUTS
        System.String, PSCredential, or list objects
    .NOTES
        Alias: getsecret
    #>
    [CmdletBinding(DefaultParameterSetName = 'Get')]
    [OutputType([string], [pscredential], [pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Get')][string]$Name,
        [Parameter(Mandatory, ParameterSetName = 'List')][switch]$List,
        [string]$LogPath = $script:DefaultLog,
        [Parameter(ParameterSetName = 'Get')][securestring]$Password,
        [Parameter(ParameterSetName = 'Get')][switch]$Copy,
        [Parameter(ParameterSetName = 'Get')][switch]$AsCredential,
        [Parameter(ParameterSetName = 'Get')][string]$UserName
    )

    if (-not (Test-Path -LiteralPath $LogPath)) { throw "No secrets log at $LogPath. Create one with newsecret." }
    $rows = foreach ($l in Get-Content -LiteralPath $LogPath) {
        $p = $l -split "`t"
        if ($p.Count -eq 3) { [pscustomobject]@{ Time = [datetime]$p[0]; Name = $p[1]; Blob = $p[2] } }
    }

    if ($List) {
        return $rows | Group-Object Name | ForEach-Object {
            $last = $_.Group | Sort-Object Time | Select-Object -Last 1
            [pscustomobject]@{
                Name     = $_.Name
                Updated  = $last.Time
                Versions = $_.Count
                Mode     = if ($last.Blob -like 'GLAS1:U:*') { 'ThisPC' } else { 'Password' }
            }
        } | Sort-Object Name
    }

    $hit = $rows | Where-Object Name -eq $Name | Sort-Object Time | Select-Object -Last 1
    if (-not $hit) { throw "No secret named '$Name'. Try: getsecret -List" }

    if ($AsCredential) {
        $ss = Unprotect-GlasText -Blob $hit.Blob -Password $Password -AsSecureString
        if (-not $UserName) { $UserName = $Name }
        return [pscredential]::new($UserName, $ss)
    }
    Unprotect-GlasText -Blob $hit.Blob -Password $Password -Copy:$Copy
}

function Lock-GlasScriptVariable {
    <#
    .SYNOPSIS
        Replaces a plaintext secret in a script with an encrypted Glas line, in place.
    .DESCRIPTION
        Finds exactly one line like  $DbPass = 'plaintext'  and rewrites it as
        $DbPass = Unprotect-GlasText 'GLAS1:...'. The script keeps working as long
        as Glas is installed. -Generate ignores the old value and creates a new
        random password (rotation); pair with -Copy to get the new one.
        File encoding and BOM are preserved.
    .PARAMETER Path
        Script to edit.
    .PARAMETER Name
        Variable name, with or without $.
    .PARAMETER ThisPC
        DPAPI instead of password. Right for scripts that run unattended as you.
    .PARAMETER Password
        SecureString; otherwise uses the glas session or prompts.
    .PARAMETER Generate
        Replace with a new random password instead of encrypting the current one.
    .PARAMETER Length
        Length for -Generate. Default 24.
    .PARAMETER Copy
        With -Generate: new plaintext to the clipboard.
    .EXAMPLE
        lockvar .\Sync-Nas.ps1 NasPass -ThisPC
    .EXAMPLE
        lockvar .\Sync-Nas.ps1 NasPass -ThisPC -Generate -Copy
    .NOTES
        Only single- or double-quoted literals without $ or backticks are touched.
        The old plaintext still exists in git history and editor backups: rotate it.
        Alias: lockvar
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Path,
        [Parameter(Mandatory, Position = 1)][string]$Name,
        [switch]$ThisPC,
        [securestring]$Password,
        [switch]$Generate,
        [ValidateRange(8, 256)][int]$Length = 24,
        [switch]$Copy
    )

    $full = Convert-Path -LiteralPath $Path -ErrorAction Stop
    $m    = Find-GlasScriptVariable (Read-GlasTextFile $full).Text $Name

    if ($m.Groups['call'].Success -and -not $Generate) {
        Write-Host "`$$($Name.TrimStart('$')) is already encrypted. Use -Generate to rotate it." -ForegroundColor Yellow
        return
    }
    if ($Generate) { $value = New-GlasPassword -Length $Length }
    else {
        $value = $m.Groups['val'].Value
        if (-not $value) { throw 'Value is empty. Use -Generate to create one.' }
        if ($m.Groups['q'].Value -eq '"' -and $value -match '[$`]') { throw 'Double-quoted value contains $ or backtick; switch it to single quotes first.' }
    }

    $blob = Protect-GlasText -Text $value -ThisPC:$ThisPC -Password $Password
    Set-GlasScriptLine -Path $full -Name $Name -Blob $blob -WhatIf:$WhatIfPreference
    if ($Generate -and $Copy) { Set-Clipboard -Value $value; Write-Host 'New password copied to clipboard.' -ForegroundColor Green }
    $value = $null
}
#endregion

Set-Alias genpass   New-GlasPassword
Set-Alias glas      Unlock-GlasSession
Set-Alias glasoff   Lock-GlasSession
Set-Alias lock      Protect-GlasText
Set-Alias unlock    Unprotect-GlasText
Set-Alias lockf     Protect-GlasFile
Set-Alias unlockf   Unprotect-GlasFile
Set-Alias newsecret New-GlasSecret
Set-Alias getsecret Read-GlasSecret
Set-Alias lockvar   Lock-GlasScriptVariable

Export-ModuleMember -Function New-GlasPassword, Unlock-GlasSession, Lock-GlasSession, Protect-GlasText,
    Unprotect-GlasText, Protect-GlasFile, Unprotect-GlasFile, New-GlasSecret, Read-GlasSecret, Lock-GlasScriptVariable `
    -Alias genpass, glas, glasoff, lock, unlock, lockf, unlockf, newsecret, getsecret, lockvar
