# Code

Scripts and modules from my Windows workstation and lab. Everything here is written for Windows PowerShell 5.1 and PowerShell 7 unless a README says otherwise. The Python tools use the standard library only.

| Tool | What it is | Language | Docs |
|------|-----------|----------|------|
| **profile.ps1** | One shared profile for console, ISE and VS Code: git-aware prompt, SOC triage helpers, cheat sheet | PowerShell | [PowerShell/](PowerShell/README.md) |
| **ClearCache.ps1** | Closes Edge and Chrome for the current user and clears their caches | PowerShell | [PowerShell/](PowerShell/README.md) |
| **Faire** | Scheduled watch scripts: failed logons, autostart changes, low disk, temp cleanup, profile backup. Alerts land in the Windows event log | PowerShell | [PowerShell/Faire/](PowerShell/Faire/README.md) |
| **Glas** | Encryption for text, files, a secrets log, and secrets embedded in scripts (AES-256 + HMAC, or DPAPI) | PowerShell | [PowerShell/Glas/](PowerShell/Glas/README.md) |
| **Seala** | Stamps and maintains a standard header block with a rolling changelog | PowerShell + Python | [PowerShell/Seala/](PowerShell/Seala/README.md) |
| **Cuairt** | Read-only lab sweep: ping, TCP ports, Wazuh agent state, subnet discovery | Python | [Python/](Python/README.md) |

The names are Irish: *faire* (watch), *glas* (lock), *séala* (seal), *cuairt* (round, patrol), *doras* (door).

## Layout

```
Code/
  JSON/          example configs (cuairt.example.json)
  PowerShell/    profile.ps1, ClearCache.ps1, and one folder per module
  Python/        cuairt.py, seala.py
```

## Conventions

- **ASCII only.** Windows PowerShell 5.1 misreads UTF-8 files that have no BOM, so the .ps1/.psm1 files stay plain ASCII.
- **Preview before change.** The installers and most commands that modify things support `-WhatIf` / `-Confirm` (PowerShell) or `--dry-run` (Python).
- **Help lives in the code.** Public PowerShell commands have comment-based help (`Get-Help <command> -Examples`), and Python tools have `--help`.
- **Linted and tested in CI.** PSScriptAnalyzer (Warning and Error) and ruff run on every push, along with the tests in [`tests/`](../tests). Tool versions are pinned in the [workflow](../.github/workflows/ci.yml).

## AI use

Some of this code was written with Claude's help. See [AI use](../README.md#ai-use) in the main README for how that works and how those commits are marked.

## Sanitization

These are clean copies of tools from a private repo. Real addresses, host names, user paths and anything tied to an employer or client have been removed. Example addresses use the RFC 5737 documentation ranges, and the example MAC uses the RFC 7042 documentation block.

## License

MIT, see [LICENSE](../LICENSE).
