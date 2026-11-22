# Changelog

All notable changes to **Universal Sidecar Gateway & Homelab** are documented in this file.

## [v2026.11.2] — 2026-11-22

### Phase-2: Defense-in-Depth Hardening, Web Dashboard Redesign, LXC 7.0 Studio & OpenWrt LuCI

#### Security & Runtime Isolation
- **Caddy ↔ WebUI Proxy Token (`X-Gateway-Proxy-Token`):** Added `/etc/sing-box/homelab/webui_proxy.token` (`0600 root:root`, 32-char hex) verified in constant time (`hmac.compare_digest`) by `modules/webui/server.py` when `AUTH_MODE="caddy"`; added `header_up -Authorization` to all `basic_auth`-protected Caddy reverse proxies (`gateway`, `/console*`, `code`, `torrent`, `ytdlp`); enforced fail-closed Caddy bcrypt hashing, staged `caddy validate` checks, and `root:caddy` (`0750`/`0640`) permissions on `/etc/caddy`.
- **Direct WebUI Auth & Transport Hardening (`modules/webui/server.py`):** Added per-IP exponential brute-force backoff (`HTTP 429`) in `AUTH_MODE="basic"`, strict `Host`/`Origin` allowlist, `X-Gateway-Action: 1` CSRF header, `Cache-Control: no-cache` on static files, query token redaction (`?arg=`/`?token=`) in access logs, and hardened non-blocking WebSocket relay with 64 KB backpressure buffers and write-stall/idle timeouts.
- **`/run/gateway` (`0700 root:root`) Isolation:** Migrated all locks (`op.lock`, `job.lock`), `ttyd` one-time console tokens (`console_tokens/`), async jobs, update/version/disk/LAN caches, and temporary staging directories out of `/tmp` into `/run/gateway` (`0700 root:root`).
- **Storage & Backup Isolation:** Scoped Samba `[storage]` and LXC container bind-mounts strictly to `/srv/storage/Shared` (with automatic doctor migration of legacy `/srv/storage` LXC mounts); restricted `/srv/storage` root to `0755 root:root` and `/srv/storage/Backups` to `0700 root:root` (`0600` files); explicitly excluded `*storage.luks.key*` from `gw backup` tarballs; added OpenRC Mount Guard (`/usr/lib/gateway/storage-mount-guard.sh`) via `start_pre()` across all storage-dependent services.
- **Firewall & `lxcbr0` Hardening (`modules/network/firewall.sh`):** Removed CGNAT `100.64.0.0/10` from trusted LAN input; blocked external TCP `8096`; isolated `lxcbr0` NAT containers from host management ports (`22, 3000, 8095, 8096, 9090, 445`, allowing only `:53`/`:67`) and RFC1918 LAN subnets; extended DNS redirect, `:853` reject, and Kill-Switch rules to cover `lxcbr0`; validated `USER_BYPASS_IPS`.
- **Supply-Chain & Credential Hygiene:** Enforced fail-closed SHA-256 verification for Sing-Box Extended and Mihomo releases (exact tag + `checksums.txt` fallback; rejects unverified mirrors); switched API calls to `curl -K -` and interactive secret prompts to `stty -echo`; replaced dot-sourcing of version caches with `parse_env_file_safely`.

#### Alpine Web Dashboard (`:8095`) & `ttyd` Web Console (`:8096`)
- **Zero-Build Next-Gen UI/UX Redesign (`modules/webui/static/*`):**
  - Dual **Obsidian Glass** (dark) and **Porcelain Slate** (light) themes with inline SVG icon sprite (zero Node/npm/CDN dependencies).
  - Single-row sticky desktop header + `Ctrl+K` / `/` fuzzy Command Palette + mobile thumb-zone bottom navigation (`<=640px`, 0px horizontal overflow) + full ARIA keyboard navigation.
  - 4-node interactive SVG Traffic Pipeline, 240° radial gauges & sparklines, First-Run Onboarding, `?` contextual help popovers, Domain X-Ray with client-side IP literal validation, sequential Slot 1→2→3 Proxy editor, and XSS-safe severity-tinted Log Viewer.
- **Native Fast `/api/status` Engine (`modules/webui/server.py`):** Replaced slow shell-fork status polling on Alpine with a native Python 3 stdlib collector (`< 250ms` warm response) reading `/proc/*`, `/run/openrc/started/*`, `os.statvfs`, Clash API, cached AdGuard Home session cookies, concurrent `lxc-info`, and TTL-cached background `du`, maintaining 100% JSON schema parity with `modules/webui/api.sh`.
- **Hardened `ttyd` Console (`modules/webui/install.sh`, `lxc_console.sh`):** Bound strictly to `127.0.0.1:8096` with `-O` (`--check-origin`) and `-t disableReconnect=true`, using atomic `mv` consumption of one-time tokens in `/run/gateway/console_tokens` and clean iframe reset/reconnect in the dashboard.

#### OpenWrt Native LuCI SPA (`luci-app-gateway`)
- **Integrated `Sidecar Gateway` Section (`modules/luci/*`):** Added native OpenWrt >= 25.12.6 LuCI SPA (`admin/gateway`) with 5 tabs (`Overview`, `Core & Network`, `Proxies & Routes`, `Telegram & Backup`, `Update & Logs`), backed by `/usr/libexec/rpcd/gateway` delegating to the shared POSIX `modules/webui/api.sh` engine with async `job_start`/`job_poll` (respecting `rpcd`'s 30s timeout), 15s visibility-aware polling, multi-line subscription textarea, and safe stream teardown on view navigation.

#### Core Routing, DNS, Low-RAM Tuning & CLI
- **Sing-Box Extended `v1.14.3-extended-2.7.3` & Mihomo `v1.19.34`:** Fixed Full-VPN (`force_proxy_devices.conf`) DNS/QUIC/routing precedence (placed above BitTorrent and user lists); added `http_clients[0]` (`detour: DIRECT`) + `route.default_http_client`; scoped `dns_homelab` to `query_type: ["A"]`; expanded `udp/443` QUIC reject to Spotify, Twitch, Roblox, Cloudflare, refilter, Facebook, and Full-VPN; aligned Mihomo TUN to `172.19.0.1/30` with `fake-ip-range: 198.18.0.1/16`.
- **AdGuard Home `v1.0.0`:** Set `handle_ddr: false` and replaced wildcard `*.lan` rewrites with 14 explicit managed `.lan` hostnames (6 on OpenWrt), handling flow-style YAML safely.
- **Low-RAM Hardware Profiles (`calc_hardware_limits`):** Added right-sized `GOMEMLIMIT`/`GOGC`/`sysctl`/AGH tiers for `<=300 MB` and `<=600 MB` routers/SBCs (never `"off"` on swapless OpenWrt).
- **CLI & Env Improvements:** Added `gw logs webui|console`, `gw lxc doctor|fix-net|menu`, `fix-net` Bash completion, non-zero CLI error exits, in-memory CRLF stripping in `load_gateway_env`, and read-only `lib/constants.sh`.

#### Homelab, LXC 7.0 & LUKS2 Storage
- **LXC 7.0 Container Studio:** Full cgroups v2 support, upstream `nesting.conf`, fixed `lxc-snapshot` (removed invalid `--allowrunning`), strict validation for container names/CPU/RAM/static IPv4/CIDR, clone with fresh `10:66:6a:xx:xx:xx` MAC, Quick Exec, and non-destructive network preservation in `lxc_autoseed_container_network`.
- **LUKS2 & Disk Safety:** Added RAM-aware Argon2id `--pbkdf-memory` (`65536` / `131072` KiB), `--key-file=-`, stopped running LXC containers before unmount, removed unsafe lazy `umount -l`, verified `cryptsetup close` exit codes, fixed `e2fsck -p` exit code `0|1` handling and Btrfs SSD/HDD rotational detection.
- **Homelab Module Hardening:** Vaultwarden Argon2id `ADMIN_TOKEN` + `SIGNUPS_ALLOWED="false"`; Forgejo `DISABLE_REGISTRATION=true`, file logging, and CVE-2026-89094 version check; Transmission native OpenRC `command_user`/`command_args` + `jq`-built `settings.json`; MeTube `ALLOW_PRIVATE_ADDRESSES="false"` + optional `deno`/`nodejs` JS runtime; Caddy DuckDNS ECC (`ec-256`, apex SAN, `--ecc` install/renew) + refreshed Obsidian Glass `ca.lan` PKI portal; unified backup now resolves Forgejo repo symlinks and includes VS Code Web, crontabs, network interfaces, and sysctl configs.

#### Documentation & CI/CD
- Synchronized `README.md`, `README.ru.md`, `ARCHITECTURE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md` with the Phase-2 dual-OS codebase (Alpine 3.23–3.24+ & OpenWrt >= 25.12.6), added Mermaid architecture & auth diagrams, "How to extend in 5 minutes" recipes, and Beginner Troubleshooting FAQ.
- Hardened `.gitattributes` (enforcing LF for `modules/luci/rpcd/gateway`, `*.js`, `*.css`, `*.html`, `*.sh`, `*.py`, `*.json`, `*.md`, `*.yml`) and expanded `.github/workflows/ci.yml` with LF/no-BOM enforcement, POSIX `sh -n`, `shellcheck -s sh -S error`, `python3 -m py_compile`, `jq empty`, Node JS syntax validation (WebUI + LuCI), and secret-pattern hygiene scanning.

---

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
