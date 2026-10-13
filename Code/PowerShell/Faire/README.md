# Faire

Scheduled watch scripts for a single Windows host. Each script does one job, logs to a monthly file, and raises alerts as **Windows Application log events** (source `Faire`). That means anything already collecting the Application log (a Wazuh agent with its default Windows config, WEF, Splunk UF or Sentinel AMA set up for it) picks them up without changes to Faire. An optional webhook (Discord, ntfy or anything that accepts a POST) can mirror alerts.

*Faire* is Irish for watch or vigil.

## Install

From an elevated shell, in this folder:

```powershell
.\Install-Faire.ps1 -WhatIf   # preview
.\Install-Faire.ps1
```

The installer:

1. Copies the scripts to `%ProgramData%\Faire\scripts`. An existing `faire.config.json` is never overwritten.
2. Locks down the ACLs, using SIDs so it works on non-English Windows:
   - `scripts\` and `state\`: SYSTEM and Administrators only, because these scripts run as SYSTEM. If a normal user could edit them, they could get SYSTEM by editing a file and waiting.
   - `logs\`: users may append, so the user-context tasks can log. Log files are therefore not tamper-evident; treat the event log as the trustworthy record.
3. Registers the `Faire` event source.
4. Creates the scheduled tasks under `\Faire\`. It uses PowerShell 7 if installed from the MSI and falls back to 5.1. The Store build of pwsh is avoided because its alias breaks SYSTEM tasks.

Remove the tasks with `.\Install-Faire.ps1 -Uninstall`. Files are left in place for review.

## Tasks

| Task | Script | Schedule | Runs as | Events |
|------|--------|----------|---------|--------|
| Faire-FailedLogon | Watch-FailedLogon.ps1 | Hourly | SYSTEM | 110 brute force (user + source over threshold), 111 lockout |
| Faire-Persistence | Watch-Persistence.ps1 | Every 4 h | SYSTEM | 130 autostart added/changed, 131 removed |
| Faire-DiskSpace | Watch-DiskSpace.ps1 | Daily 07:00 | SYSTEM | 120 low disk. Also prunes old Faire logs |
| Faire-TempCleanup | Invoke-TempCleanup.ps1 | Sundays 03:00 | You (S4U) | none |
| Faire-Backup | Backup-Profile.ps1 | Daily 21:00 | You (S4U) | 140 backup failed |

Any script error raises event **199**. Check status with `faire` (from the profile), or run a task now:

```powershell
Start-ScheduledTask -TaskPath '\Faire\' -TaskName Faire-DiskSpace
```

## Config

`faire.config.json` sits next to the scripts. Every key is optional; missing keys keep the defaults in `Faire.psm1`.

| Key | Default | Notes |
|-----|---------|-------|
| `FailedLogonWindowMinutes` | 60 | Keep equal to the task interval |
| `FailedLogonThreshold` | 10 | Failures per user + source IP per window |
| `DiskMinFreePercent` | 15 | |
| `TempOlderThanDays` | 7 | |
| `LogRetentionDays` | 90 | |
| `BackupPaths` | `[]` | Extra paths to back up. Environment variables expand |
| `BackupDestination` | `%LOCALAPPDATA%\Faire\Backups` | Must be a local disk (see below) |
| `BackupKeep` | 14 | Zips kept |
| `WebhookUrl` | empty | Discord webhook URLs get JSON; anything else gets plain text |

## Things to know

- **S4U tasks have no network credentials.** "Run whether logged on or not, don't store password" means the backup can't reach a NAS share. Point `BackupDestination` at a local disk, or change the task to store a password.
- **Controlled Folder Access** blocks PowerShell writes under Documents, which is why the default backup destination is `%LOCALAPPDATA%`.
- **Watch-FailedLogon misses low-and-slow sprays** that stay under the threshold in every window. That's left to SIEM correlation.
- **Watch-Persistence baselines on its first run** and only alerts on changes after that. Run `.\Watch-Persistence.ps1 -Rebaseline` after installing software you trust. Anything already running as admin can rebaseline too, which is why the alerts also go to the event log for off-box collection.
- `Get-FairePersistence` is triage coverage, not Autoruns coverage: it skips System32 service binaries, IFEO and COM hijacks.
