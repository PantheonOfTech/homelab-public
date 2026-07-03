# Build Log

Milestone log for the TechPanthéon homelab. Dates + capabilities only — no infrastructure detail.

## 2026-06

- **2026-06-25** — Documented all compute nodes, VMs, and network gear as configs-as-code in the private repo.
- **2026-06-24** — Split public/private repo boundary; added automated leak-guard (pre-commit secret/address scanning) to the public repo.
- **2026-06-21** — Established encrypted configs-as-code: GPG-backed transparent secret encryption, key-based remote auth to origin.

## 2026-05

- **2026-05-27** — Flat network re-architected onto a dedicated subnet; stale references retired.
- Stood up SIEM manager with agent fleet across Linux/Windows endpoints, hypervisor, and a domain controller.
- Deployed network-services host (DNS sinkhole, uptime + metrics monitoring, overlay VPN).
