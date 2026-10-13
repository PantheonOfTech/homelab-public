# homelab-public

> Part of **TechPanthéon** — purple-team homelab, detection engineering, and 3D-printed hardware.

Sanitized, shareable artifacts from my purple-team homelab — a self-hosted infrastructure and security lab built as a real-world environment for SOC development, detection engineering, and automation-first system design.

This repo is the **public face**: sanitized tooling from the lab. All sensitive infrastructure detail (real addressing, topology, secrets) lives in a separate private repo and never lands here. Everything below is authored clean, not filtered down.

## Links
- **Website:** https://www.pantheonoftech.com
- **Linktree:** https://linktr.ee/pantheonoftech

## What's here
| Path | Contents |
|------|----------|
| [`Code/`](Code/README.md) | PowerShell and Python tooling: a shared profile with SOC triage helpers, **Faire** (scheduled watch scripts that alert through the Windows event log), **Glas** (AES-256/HMAC and DPAPI secrets), **Seala** (script header stamper), **Cuairt** (read-only lab sweep with Wazuh agent state) |
| [`CHANGELOG.md`](CHANGELOG.md) | Sanitized mirror of the private engineering log |

Each tool folder has its own README covering install, usage and security notes.

## Architecture principles
- **Local-first, no telemetry** — self-hosted everything, llama.cpp over cloud inference, Tailscale overlay.
- **Configs-as-code** — git owns configuration; Obsidian owns knowledge.
- **Approval-gated execution** — read-only/diagnostics first, destructive steps confirmed.
- **Automation-first** — if it can be automated, it should be.

## Sanitization
Internal addressing is swapped for RFC5737 documentation ranges (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`); hostnames are genericized to role placeholders. User paths, real inventories and anything tied to an employer or client stay in the private repo. A pre-commit leak guard blocks private addressing, MACs, key fingerprints and secret file types.

## License
MIT — see [LICENSE](LICENSE).

## Changelog
See [CHANGELOG.md](CHANGELOG.md).
