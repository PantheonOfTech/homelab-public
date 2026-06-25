# homelab-public

> Part of **TechPanthéon** — purple-team homelab, detection engineering, and 3D-printed hardware.

Sanitized, shareable artifacts from my purple-team homelab — a self-hosted infrastructure and security lab built as a real-world environment for SOC development, detection engineering, and automation-first system design.

This repo is the **public face**: cleaned detection rules, fabrication files, and write-ups. All sensitive infrastructure detail (real addressing, topology, secrets) lives in a separate private repo and never lands here. Everything below is authored clean, not filtered down.

## Links
- **Website:** http://www.pantheonoftech.com
- **Linktree:** https://linktr.ee/pantheonoftech
- **TikTok:** [@techpanthon](https://www.tiktok.com/@techpanthon)

## What's here
| Path | Contents |
|------|----------|
| `security/` | Sanitized Wazuh rules, Suricata configs |
| `fabrication/` | 3D-printable rack mounts, hardware mods |
| `docs/` | PRDs, runbooks, architecture write-ups |
| `projects/` | Self-contained project artifacts |

## Architecture principles
- **Local-first, no telemetry** — self-hosted everything, llama.cpp over cloud inference, Tailscale overlay.
- **Configs-as-code** — git owns configuration; Obsidian owns knowledge.
- **Approval-gated execution** — read-only/diagnostics first, destructive steps confirmed.
- **Automation-first** — if it can be automated, it should be.

## Sanitization
Internal addressing is swapped for RFC5737 documentation ranges (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`); hostnames are genericized to role placeholders.

## License
MIT — see [LICENSE](LICENSE).

## Changelog
- 2026-06-25 — Top-level README authored; brand + links added.
