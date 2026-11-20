# Changelog

All notable changes to **Universal Sidecar Gateway & Homelab** are documented in this file.

## [v2026.11] — 2026-11-20

### Highlights
- **Dual-Core Routing Architecture:** Full runtime support and atomic hot-switching (`gw core singbox|mihomo`) between **Sing-Box Extended v1.14.3** and **Mihomo v1.19.34** with pre-flight config validation and automatic rollback.
- **Dual Clash-API Web UI:** Instant hot-switching (`gw ui zashboard|metacubexd`) between **Zashboard v3.30.0** and **MetaCubeXD v1.275.2** with **0 core restarts**.
- **Shared Single Source of Truth for Policy Routing (`lib/routing_rules.sh`):**
  - Dedicated `🧱 Roblox` selector (defaulting to `🇩🇪 Германия`, ordered ahead of regional bundles).
  - Dedicated `🤖 Нейросети (ИИ)` selector (defaulting to `🤖 Авто-ИИ` with isolated `dns_ai` DoH).
  - Enhanced `▶️ YouTube & Медиа` coverage including explicit **Twitch** and **Spotify** routing suffixes.
  - Dedicated `🧲 Торренты` selector defaulting to `DIRECT`, switchable in one click to `🇩🇪 Германия`, `🇺🇸 США`, `⚡ Авто`, or any node.
  - Direct game storefront DNS (`dns_ru`) and CDN traffic (`DIRECT`) with `masquerade persistent` Open NAT.
- **LUKS2 Storage & Fault-Tolerant Power/Network Recovery:**
  - Native OpenRC `dmcrypt` LUKS2 (`AES-XTS 512-bit` + `Argon2id`) provisioning (`gw disk`), OS-disk guard, `gw lock` / `gw unlock` lifecycle, and `wsdd`/`avahi-daemon` orchestration.
  - Boot Guard (`/etc/local.d/50-gateway-boot-guard.start`) and Mount Guard: recovers damaged/empty configs from `.last_good_state`, clears stale locks, keeps core gateway + Vaultwarden alive when external drives are detached, and auto-heals missing default routes + `conntrack` on Ethernet link flaps.
- **SSL & Certificate Lifecycle:** Instant reuse of valid cached Let's Encrypt DuckDNS wildcard certificates when switching back from Local PKI (`gw ssl`).
- **CLI & CI Reliability:**
  - Added `gw killswitch [on|off|status]` CLI subcommand + Bash completion.
  - Synchronous readiness waiting in `gw passwd`, 2-stage parallel URLTest warmup in `core_reload_api`, safe GNU `tar` handling for live sockets/WAL in `gw backup create/restore`, and non-TTY guard in `gw`.
  - Added POSIX `#!/bin/sh` headers across all scripts (zero `ShellCheck` `severity: error` findings) and MIT `LICENSE`.
