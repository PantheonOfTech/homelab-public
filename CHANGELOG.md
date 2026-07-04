# Changelog
Sanitized mirror of the private engineering log. Newest first. Addressing uses RFC5737 doc ranges; hosts are role placeholders.

## 2026-07-04
- Session opened; standing conventions reaffirmed.

## 2026-07-03
- Public CHANGELOG sanitized mirror synced; private + public matched at full history.
- Changelog rebuilt as continuous log; full project history backfilled; append-only policy locked.

## 2026-06-28
- ITSM pivot: SaaS dev-instance path dead (capacity), two commercial platforms rejected → self-hosted GLPI on the ITSM VM; planned second ITSM VM dropped.
- ITSM VM RAM doubled; Docker Compose stack: MariaDB 11.4 + GLPI 11.0.8 + Caddy reverse proxy; TLS SNI issue fixed via explicit SAN + default_sni.
- GLPI configured entirely via SQL/CLI: entity + location trees, native inventory enabled; inventory agents deployed to ITSM VM, hypervisor, workstation (MSI property injection failed silently — manual config workaround).
- SIEM agent enrolled for ITSM VM; linux-servers agent group created + assigned. Fleet verified: 7 agents, 2 disconnected flagged for follow-up.
- Domain controller patched (June 2026 CU, .NET sec, Defender defs); pre-patch snapshot taken, clean baseline preserved.
- Post-patch ~2600 SIEM alerts from update staging paths — false positives; telemetry pipeline validated, tuning deferred to baseline.
- Transient AD SRV-record DNS failure fixed (re-register + Netlogon restart); dcdiag clean.
- RSAT on workstation — remote AD/GPO/DNS management; direct DC GUI deprecated.

## 2026-06-27
- ITSM VM built on hypervisor: OVMF/q35, Ubuntu 24.04.4; hardened (full-upgrade, LAN-only firewall, key-only SSH); SIEM agent enrolled.
- Windows Server 2025 domain controller promoted + configured (AD DS + DNS, lab domain).

## 2026-06-25
- Node/VM/network docs committed as configs-as-code (7 nodes, 2 VMs, network gear); doc format standardized.
- Top-level READMEs both repos; public brand + links added.
- Mobile endpoint backup complete (checksummed tarballs, verified); OS rebuild locked: Fedora 44, Btrfs+LUKS, surface kernel, containerized Kali, SIEM agent. 12-phase runbook in progress.

## 2026-06-24
- Public repo created (MIT); automated leak-guard pre-commit hook (blocks private addressing, MACs, key fingerprints, secret file types).
- Remote-auth key rotated + re-enrolled.
- Encrypted legacy drive recovery workflow staged: read-only recon (health, encryption fingerprinting, header inspection), noexec mount + AV scan before any exfil. Paused pending cable.

## 2026-06-21
- Private repo created; GPG-backed transparent secret encryption (git-crypt) initialized + verified pre-push; key-based remote auth established.

## 2026-06-17
- M6 cage nuts locked as unified fastener standard across all 3 racks (19" 6U + two printed 10" racks); hardware kit sourced ×2.
- Rack depth ground-truthed; 4U full-ATX chassis selected for hypervisor's next home; current SFF box to be repurposed as router/backup-DNS node.
- Physical topology confirmed: edge router → edge switch (storage/SOC/services nodes + printers) + core switch (hypervisor/workstations).

## 2026-06-16
- Obsidian knowledge base locked: 4 pillars + capture inbox, controlled tag vocabulary, full template set. Split: Obsidian owns knowledge, git owns configs-as-code.

## 2026-06-14
- Meshtastic selected over MeshCore for SOC-logged home mesh (MQTT maturity). Portable LoRa terminal locked: nRF52840 platform, I2C keyboard, e-ink, LiFePO4, RF-switched antennas (no hot-switching).
- CAD: NURBS modeler trial started; Fusion 360 deferred to CNC CAM (free license prohibits commercial use — conflicts with sales pipeline).

## 2026-06-13
- Desktop CNC purchase gate set (spindle RPM + work area verification required); toolchain KiCad → FlatCAM → Gcode.

## 2026-06-12
- STL library catalogued; compatibility flags raised (wrong switch-model mount, missing AP mount, uncommitted rack-frame standard).
- First from-scratch printable part generated programmatically (watertight cradle tray for edge switch); 1U winged version gated on caliper measurements.

## 2026-06-11
- FDM printer commissioning P0–P2: serial recon + full EEPROM dump (modified Marlin, ABL present but disabled, leadscrew swap identified from steps/mm, extruder calibrated); mechanical pass; ABL re-enabled, Z-offset calibrated + saved. First-print failure root-caused (Z height + bed contamination) and corrected.
- NAS physically relocated — drive seating verification flagged for next power-up.

## 2026-06-10
- Used FDM printer acquired (CoreXY, ABL); cheap-FDM-first revenue strategy, premium printer deferred.

## 2026-06-09
- Structured network audit opened: inventory recon, per-host health, posture (service scans, SIEM compliance API, agent connectivity, DNS path). SIEM VM blockers documented.
- Ticketing evaluation started; heavier stacks RAM-blocked.

## 2026-05-28
- Post-migration SIEM agent recovery: 3 agents repointed to new manager address (per-platform methods incl. container dual-fix); 2 fresh enrolls (hypervisor + work endpoint).

## 2026-05-27
- Subnet migration completed; ISP mesh gateway removed, temp edge router in place.

## 2026-05-25
- SIEM manager deployed manager-only (indexer/dashboard deferred pending RAM); API credentials rotated safely; 3 agents enrolled; container agent ownership bug root-caused + fixed; clean-base snapshot.
- ISP 802.1X EAP-TLS discovered on fiber gateway — direct replacement dead; IP-passthrough architecture adopted; hypervisor port map locked.

## 2026-05-23
- Dual-NIC + storage expansion on hypervisor; edge router VM deployed. Bridge loop incident root-caused → loopback detection enabled on core switch. Netmask default lesson logged.

## Init — repo scaffolded, encrypted configs enabled
