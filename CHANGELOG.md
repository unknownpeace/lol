# Changelog

All notable changes to **Universal Sidecar Gateway & Homelab** are documented in this file.

## [v2026.11.1] — 2026-11-21

### OpenWrt >= 25.12.6 Support (Dedicated Gateway + AdGuard Home Mode)
- **Dual-OS Platform Detection (`lib/core.sh`):** Added `detect_os()`, `is_openwrt()`, and `version_ge()` enforcing **OpenWrt `>= 25.12.6`** with `apk-tools 3.x`, rejecting older `< 25.12.6` or legacy `opkg` builds cleanly.
- **Native `procd`, `fw4`, `uci` & `cron` Integration:**
  - Unified `service_ctl` for both Alpine `OpenRC` and OpenWrt `procd` (`/etc/init.d/sing-box`, `/etc/init.d/mihomo`, `/etc/init.d/adguardhome`, `/etc/init.d/cron`), plus Boot Guard in `/etc/rc.local`.
  - Native `fw4` nftables ruleset written to `/etc/nftables.d/90-gateway.nft` (chains inside `table inet fw4`) with `fw4 check` validation and automatic rollback/fallback.
  - Non-disruptive `dnsmasq` handoff (`dhcp.@dnsmasq[0].port='0'`, `dhcp.lan.ignore='1'`) so **AdGuard Home** owns `:53` while **LuCI** (`uhttpd :80`) stays online.
  - Added LAN IP conflict guard (`check_ip_conflict_on_lan`) and `br-lan` UCI static network persistence.
- **Focused OpenWrt Scope (Zero Bloat):** Strictly installs only the routing cores (**Sing-Box Extended ⇄ Mihomo**), **Zashboard ⇄ MetaCubeXD**, **WARP 2.0 + MASQUE H2**, Kill-Switch, and **AdGuard Home** — Homelab services, Caddy/PKI, LUKS2 storage, and LXC are excluded and guarded via `require_alpine_feature` in CLI/TUI, `backup.sh`, `password.sh`, `doctor.sh`, and `selftest.sh` (fixed `/proc/meminfo` RAM reporting for BusyBox and `.last_good_state` sync in `gw passwd`).

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
