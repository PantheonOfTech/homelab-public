# Seala

Applies and maintains a standard header block on scripts: owner line, file name, Company / Suite / Role / Runs fields, Last Modified, and a rolling changelog. *Séala* is Irish for seal.

There are two versions:

- **Seala** (this folder): a PowerShell module for `.ps1`, `.psm1` and `.psd1`.
- **seala.py** (in [`../../Python`](../../Python/README.md)): the same header for `.py`, `.sh`, `.bash` and `.zsh`.

## Install

From an elevated shell, in this folder:

```powershell
.\Install-Seala.ps1
```

This installs to `C:\Program Files\WindowsPowerShell\Modules\Seala` and strips Mark-of-the-Web from the files.

## Usage

```powershell
seala .\Get-Thing.ps1 -Role 'Inventory pull' -Note 'Initial version'
seala .\scripts -Recurse -WhatIf
git diff --name-only | seala -Note 'Fix null handling'
```

- **New file:** inserts the header at the top (below a shebang if there is one).
- **File with a header:** keeps the existing fields, bumps Last Modified, adds a changelog entry, and trims the changelog to `-MaxChangelog` (default 10).
- Encoding, BOM and line endings are preserved, and every write is read back from disk to confirm it landed.
- Skips signed scripts unless `-Force` (editing voids the signature), and skips files that aren't valid UTF-8 or UTF-16.

## Owner

The name on the header's owner line comes from, in order:

1. `$env:SEALA_OWNER`
2. `git config user.name`
3. The login name

```powershell
$env:SEALA_OWNER = 'Your Name'   # pin it for this session
```

## Note

Seala recognizes only its own header format. The files in this repo carry a shorter MIT header instead, so running Seala on them adds a new block on top rather than updating them.
