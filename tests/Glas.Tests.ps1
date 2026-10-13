# Pester 5 tests for the Glas password mode (AES-256-CBC + HMAC-SHA256, PBKDF2 keys).
# Cross-platform: no DPAPI (-ThisPC) here. Run: Invoke-Pester ./tests
# ASCII only, like the module itself.

BeforeAll {
    Import-Module "$PSScriptRoot/../Code/PowerShell/Glas/Glas.psd1" -Force

    # Variables set in BeforeAll are visible to every It block (Pester 5 scoping).
    # Build SecureStrings without ConvertTo-SecureString -AsPlainText (keeps PSScriptAnalyzer quiet).
    function New-TestSecret {
        param([string]$Text)
        $s = [securestring]::new()
        foreach ($c in $Text.ToCharArray()) { $s.AppendChar($c) }
        $s.MakeReadOnly()
        return $s
    }
    $Pw    = New-TestSecret 'correct horse battery staple'
    $Wrong = New-TestSecret 'incorrect horse battery staple'
}

Describe 'Glas password mode' {

    It 'round-trips text, including non-ASCII characters' {
        $text = "lab secret caf$([char]0xE9) $([char]0x2713)"
        $blob = Protect-GlasText -Text $text -Password $Pw
        $blob | Should -BeLike 'GLAS1:P:*'
        Unprotect-GlasText -Blob $blob -Password $Pw | Should -BeExactly $text
    }

    It 'uses a fresh salt and IV, so the same input never encrypts the same way twice' {
        $a = Protect-GlasText -Text 'same' -Password $Pw
        $b = Protect-GlasText -Text 'same' -Password $Pw
        $a | Should -Not -Be $b
    }

    It 'stores the PBKDF2 iteration count (600000) in the blob header' {
        $bytes = [Convert]::FromBase64String((Protect-GlasText -Text 'x' -Password $Pw).Substring(8))
        [Text.Encoding]::ASCII.GetString($bytes, 0, 6) | Should -Be 'GLAS1P'
        [BitConverter]::ToInt32($bytes, 6) | Should -Be 600000
    }

    It 'rejects the wrong password' {
        $blob = Protect-GlasText -Text 'x' -Password $Pw
        { Unprotect-GlasText -Blob $blob -Password $Wrong } | Should -Throw -ExpectedMessage 'Wrong password*'
    }

    It 'rejects a blob whose ciphertext was modified (MAC check before decrypt)' {
        $bytes = [Convert]::FromBase64String((Protect-GlasText -Text 'tamper me' -Password $Pw).Substring(8))
        $bytes[50] = $bytes[50] -bxor 0x01      # header is 42 bytes, so index 50 is ciphertext
        $tampered = 'GLAS1:P:' + [Convert]::ToBase64String($bytes)
        { Unprotect-GlasText -Blob $tampered -Password $Pw } | Should -Throw -ExpectedMessage '*modified*'
    }

    It 'rejects input that is not a Glas blob' {
        { Unprotect-GlasText -Blob 'hello' -Password $Pw } | Should -Throw -ExpectedMessage 'Not a Glas blob*'
    }
}

Describe 'Glas module surface' {
    It 'does not export its private crypto helpers' {
        $names = (Get-Command -Module Glas).Name
        $names | Should -Contain 'Protect-GlasText'
        $names | Should -Not -Contain 'ConvertTo-GlasCipher'
        $names | Should -Not -Contain 'Get-GlasKey'
    }
}
