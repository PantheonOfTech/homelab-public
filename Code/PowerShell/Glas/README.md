# Glas

Encryption helpers for PowerShell 5.1 and 7: text, files, a secrets log, and secrets embedded directly in scripts. *Glas* is Irish for lock.

## Install

From an elevated shell, in this folder:

```powershell
.\Install-Glas.ps1
```

This installs to `C:\Program Files\WindowsPowerShell\Modules\Glas`, which is on the module path of both 5.1 and 7. The commands then autoload everywhere, including `-NoProfile` sessions and scheduled tasks. The folder is admin-only writable, so nothing running as a normal user can swap the crypto code for a version that logs passwords.

## Two modes

| Mode | How | Decrypts where | Use for |
|------|-----|----------------|---------|
| **Password** (default) | AES-256-CBC + HMAC-SHA256, encrypt-then-MAC. Keys from PBKDF2-SHA256 at 600,000 iterations with a random salt | Anywhere, with the password | Portable secrets, files you move between machines |
| **This PC** (`-ThisPC`) | Windows DPAPI | Same Windows account on the same PC only | Secrets your own scheduled scripts read, with no password prompt |

The MAC is checked in constant time before anything is decrypted, and a wrong password looks identical to tampered data, on purpose. Blobs are single-line text (`GLAS1:P:...` or `GLAS1:U:...`), safe to store in logs or scripts.

## Commands

| Alias | Command | What it does |
|-------|---------|--------------|
| `genpass` | New-GlasPassword | Random password from the OS crypto RNG, with no modulo bias. `-Copy` keeps it off the screen |
| `glas` / `glasoff` | Unlock-GlasSession / Lock-GlasSession | Type the password once and reuse it for N minutes (in memory only) |
| `lock` / `unlock` | Protect-GlasText / Unprotect-GlasText | Encrypt or decrypt text |
| `lockf` / `unlockf` | Protect-GlasFile / Unprotect-GlasFile | Encrypt a file to `<name>.glas`, or back |
| `newsecret` | New-GlasSecret | Generate, encrypt and save to the secrets log, and optionally write it into a script |
| `getsecret` | Read-GlasSecret | Newest version of a named secret. `-List` shows names without decrypting |
| `lockvar` | Lock-GlasScriptVariable | Replace `$Pass = 'plaintext'` in a script with an encrypted line, in place |

```powershell
genpass -Copy
newsecret nas-admin -Copy
$cred = getsecret nas-admin -AsCredential -UserName 'NAS\backup'
lockvar .\Sync-Nas.ps1 NasPass -ThisPC -Generate -Copy   # rotate a password baked into a script
```

`Example-Glas.ps1` shows the three patterns side by side.

## Things to know

- The secrets log defaults to `%LOCALAPPDATA%\Glas\secrets.log`. Earlier versions used `Documents\Glas`; move the file, or pass `-LogPath`.
- **DPAPI and S4U don't mix.** A task registered as "run whether logged on or not, don't store password" can't decrypt `-ThisPC` secrets, because DPAPI needs the password-derived key. Register those tasks with a stored password.
- `lockvar` leaves the old plaintext in git history, editor backups and the recycle bin. Rotate the secret after encrypting it.
- Files are processed in memory, and anything over 1 GB is refused. `-RemoveOriginal` is a normal delete, so on SSDs and synced folders the plaintext may still be recoverable.
- The clipboard history (Win+V) keeps copies of anything sent there with `-Copy`.
