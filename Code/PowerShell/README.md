# PowerShell

## profile.ps1

One profile file shared by the console (5.1 and 7), the ISE and the VS Code PowerShell host. Install it as `$PROFILE.CurrentUserAllHosts`, or dot-source it from each host's own profile.

Everything machine-specific is in the `CONFIG` region at the top. The values that need setting are:

| Setting | Default | Used by |
|---------|---------|---------|
| `PSP_Repos` | empty (disabled) | `pushscripts`: the repos it can push, each with `Path` and `Public`. With several, it asks which; public repos block `.nopush` files and need the repo name typed to confirm |
| `PSP_CmndLogr` / `PSP_CmndLogrSHA256` | Desktop path, no pin | Optional per-prompt command logger (not included here). With no SHA256 pin it never runs in an elevated shell |
| `PSP_Projects` | `Documents\Projects` | `Go-Projects` |
| `PSP_CheatModules` | `Glas`, `Seala` | Extra modules listed by `cheat` |

### Commands

Type `cheat` for the full list with synopses, or `cheat <name>` for one command's options and examples. The highlights:

| Alias | Command | What it does |
|-------|---------|--------------|
| `logons` | Get-LogonEvent | 4625 / 4624 / 4740 decoded: user, source IP, logon type, and why it failed. `-Summary` gives the brute-force view |
| `ports` | Get-ListeningPort | netstat with the PID already resolved to process name and path |
| `tp` | Test-Port | TCP connect with a real timeout; reports Open, Closed or Filtered |
| `persist` | Get-PersistenceItem | Autoruns-lite, using the Faire collector |
| `apps` | Get-InstalledSoftware | Installed programs from the registry (never Win32_Product) |
| `snap` | Invoke-FieldSnapshot | Before/after evidence capture for a site visit, zipped |
| `hashcheck` | Test-FileHash | Verify a download, with the algorithm detected from hash length |
| `myip` | Get-PublicIP | Public egress IP |
| `df` | Get-DiskSpace | Free space per drive, low drives flagged |
| `faire` | Get-FaireStatus | Faire task dashboard and recent log lines |
| `doras` / `dorasoff` | Open-Doras / Close-Doras | Time-boxed Controlled Folder Access exception for PowerShell that relocks itself through a SYSTEM task |
| `pushscripts` | Publish-ScriptRepo | Pick a repo (or `-Repo name`), stage, scan the added lines for secrets, commit, push. Public repos get a `.nopush` block and a typed confirmation |
| `cleantemp` | Clear-TempFile | Link-safe user temp cleanup |
| `reload` | Update-Profile | Reload the profile. Must be dot-sourced: `. reload` |

### Notes

- The prompt captures `$?` and `$LASTEXITCODE` before doing anything, then restores them, so the prompt never masks a native command's exit code.
- `Start-AsAdmin` relaunches with plain `-Command` rather than `-EncodedCommand`, because encoded PowerShell is a standard EDR detection and would add noise to your own alerts.
- `Get-LogonEvent` and `Open-Doras` need an elevated session.

## ClearCache.ps1

Force-closes Edge and Chrome **in the current user's session only**, waits three seconds, then deletes each browser's cache for the `Default` profile.

```powershell
.\ClearCache.ps1
```

Limits: only the `Default` browser profile is cleared (`Profile 1`, `Profile 2` and so on are left alone), and the browsers are killed with `-Force`, so unsaved form data is lost.
