# Python

Standard library only. `cuairt.py` needs Python 3.8+; `seala.py` needs Python 3.

## cuairt.py

A read-only sweep of the lab. For every host in an inventory it sends one ping and tries a TCP connect to each listed port, then (optionally) asks the Wazuh manager API for agent state. Nothing is changed anywhere. *Cuairt* is Irish for a round or patrol.

```bash
cp ../JSON/cuairt.example.json cuairt.json   # then fill in real hosts
python3 cuairt.py                    # table
python3 cuairt.py --json             # for n8n and other automation
python3 cuairt.py --csv sweep.csv    # also write the host rows to CSV
python3 cuairt.py --discover         # also ping the subnet and flag devices missing from the inventory
python3 cuairt.py --only dc --no-wazuh
```

Exit codes: `0` all as expected, `1` something is DOWN / WARN / CHANGED or the Wazuh call failed, `2` bad config. That makes it usable as a scheduled health check.

### Inventory

`cuairt.json` holds real addresses, so keep it out of git (it's in `.gitignore`). Per host:

| Field | Required | Notes |
|-------|----------|-------|
| `name` | yes | Also matched against Wazuh agent names |
| `ip` | no | Without it the host is reported as `NO IP` (the Wazuh agent IP is shown if known) |
| `ports` | no | TCP ports that should be open |
| `expect` | no | `up` (default) or `down`. A `down` host that answers is reported as `CHANGED` |
| `mac` | no | Used by `--discover` to match devices whose IP changed |
| `agent` | no | Wazuh agent name, if different from `name` |

### Wazuh

Credentials never go in the inventory. Set `CUAIRT_WAZUH_USER` and `CUAIRT_WAZUH_PASS`, or run interactively and you'll be prompted.

For TLS, prefer **pinning**: set `wazuh.cert_sha256` and cuairt refuses to send credentials if the presented certificate doesn't match. `ca_file` works too. With `verify_tls: false` and no pin, cuairt warns on every run and prints the pin to add.

### Discovery

`--discover` pings every address in `subnet` and reads the OS neighbour (ARP) cache. It only runs on private address space, /22 or smaller.

## seala.py

The Python and shell twin of the [Seala](../PowerShell/Seala/README.md) PowerShell module: same header fields, same rolling changelog, written as `#` comments. It handles `.py`, `.pyw`, `.sh`, `.bash` and `.zsh`, plus extensionless files with a python/sh shebang.

```bash
python3 seala.py sweep.py --role 'Lab sweep' --note 'Initial version'
python3 seala.py ~/scripts -r --dry-run
git diff --name-only | python3 seala.py -n 'What changed'
```

The shebang and any Python encoding line stay on top. Created is set once and then preserved, taken from the first git commit, then the file's birth time. Older-style headers are absorbed. The owner comes from `SEALA_OWNER`, then `git config user.name`, then the login name.
