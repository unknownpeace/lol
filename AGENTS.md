# 🤖 AI Assistant & Developer Invariants (`AGENTS.md`)

> **Updated:** November 22, 2026 (Phase-2 Baseline).

Critical repository invariants, platform rules, security contracts, and verification commands for AI agents and human engineers.

---

## 1. Dual-OS Platform Invariants (`apk`-only, Zero Docker)

1. **Supported Targets:**
   - **Alpine Linux `3.23–3.24+` (`OpenRC` + `apk-tools v3` + cgroups v2):** Full appliance profile — Routing Gateway (`Sing-Box Extended` ⇄ `Mihomo`), `AdGuard Home`, Alpine Web Dashboard (`:8095`) + `ttyd` LXC Console (`:8096`), Caddy HTTPS (`Local PKI` ⇄ `DuckDNS Let's Encrypt`), 7 Homelab modules, LUKS2 external storage, and LXC 7.0 Container Studio. *(Alpine `3.21` reaches EOL in late 2026.)*
   - **OpenWrt `>= 25.12.6` (`procd` + `fw4` + `apk-tools 3.x` + LuCI SPA):** Focused **Gateway + AdGuard Home + `luci-app-gateway`** profile only. Homelab services, Caddy/PKI, LUKS2, LXC, and the Alpine Python WebUI are excluded by design and **must** remain gated behind `require_alpine_feature` / `is_openwrt`.
   - **Explicitly Rejected:** OpenWrt `< 25.12.6`, legacy `opkg` builds, `systemd`, and Docker runtime dependencies.
2. **Unified OS Layer (`lib/core.sh`):**
   - Canonical OS helpers (`detect_os`, `is_openwrt`, `version_ge`) and service wrapper (`service_ctl` supporting OpenRC & `procd`) live solely in `lib/core.sh`. Never duplicate `service_ctl` in modules.
   - `lib/constants.sh` must stay **read-only on source** (no `set -e`, no `mkdir`, no `ln -sf`, no disk writes on import).
3. **POSIX `sh` / BusyBox `ash` & OpenWrt Quirks:**
   - All scripts under `lib/`, `modules/`, `ui/`, `gateway.sh`, `setup.sh`, and extensionless `modules/luci/rpcd/gateway` **must** start with `#!/bin/sh`, use **LF (`\n`) only** (UTF-8 without BOM), and pass `sh -n` and `shellcheck -s sh -S error`.
   - **No bashisms:** no `[[ ... ]]`, arrays, `local` outside guarded blocks, `source`, or `BASH_SOURCE` assumptions.
   - **OpenWrt tool gaps:** No `bash`, `ss`, `stat`, or `base64`; `free -m` outputs KiB (read `/proc/meminfo` instead); **`jq` is compiled without Oniguruma** — never use `test()`, `match()`, or `sub()` in `jq` filters! Use `apache-utils` for `htpasswd` (immediately followed by `disable_apache_daemon`). Cron daemon is `cron`.
   - Avoid GNU-only `sed`/`grep`/`find` extensions (`\s`, `-P`, etc.); pass `TZ=UTC` when parsing ISO timestamps with BusyBox `date`.
   - Never keep top-level `set -e` in sourced module scripts (`samba.sh`, `ssl.sh`, `services/*.sh`).

---

## 2. Security & Runtime Contracts (Phase-2)

1. **Private Runtime Directory (`/run/gateway`, `0700 root:root`):**
   - **Zero secrets, tokens, locks, temp scripts, or caches in `/tmp`!** Always call `ensure_gateway_runtime_dir` and place locks (`op.lock`, `job.lock`), console tokens (`console_tokens/`), async jobs (`gw_job_*`), caches (`ver.cache`, `update_check.cache`, `disks.cache`, `lan_scan.cache`), and `mktemp` staging directories inside `/run/gateway` (`0700`).
   - Only 3 OpenWrt system paths may reference `/tmp`: `/tmp/resolv.conf`, `/tmp/luci-indexcache*` flush in `modules/luci/install.sh`, and read-only `/tmp/sysinfo/model`.
2. **Caddy ↔ WebUI Proxy Auth Contract (`X-Gateway-Proxy-Token`):**
   - Shared secret lives at `/etc/sing-box/homelab/webui_proxy.token` (`0600 root:root`, 32-char lowercase hex).
   - When Caddy is enabled, `gateway-webui` binds `127.0.0.1:8095` with `GATEWAY_WEBUI_AUTH="caddy"` and validates `X-Gateway-Proxy-Token` using constant-time `hmac.compare_digest` (`modules/webui/server.py`).
   - Caddy (`modules/caddy/caddy.sh`) injects `header_up X-Gateway-Proxy-Token <token>` for the `gateway` site, **fails closed** if `basic_auth` bcrypt hashing fails, stages configs with `caddy validate` before swapping, and adds **`header_up -Authorization`** to every `basic_auth`-protected `reverse_proxy` (`gateway`, `/console*`, `code`, `torrent`, `ytdlp`).
   - When Caddy is disabled, `gateway-webui` binds `0.0.0.0:8095` with `GATEWAY_WEBUI_AUTH="basic"`, enforcing BasicAuth + per-IP exponential backoff (`429`).
   - `server.py` enforces strict `Host`/`Origin` allowlist, `X-Gateway-Action: 1` CSRF header on `POST /api/*`, `Cache-Control: no-cache` on static files, and query token redaction (`?arg=`/`?token=`) in logs.
3. **`ttyd` Web Console Contract (`127.0.0.1:8096`):**
   - `gateway-console` runs `ttyd -i 127.0.0.1 -p 8096 -b /console -a -W -O -t disableReconnect=true -t fontSize=14 -t cursorBlink=true /bin/sh .../lxc_console.sh`.
   - One-time 32-hex tokens are created in `/run/gateway/console_tokens/<tok>` (`0700`, 60s TTL) and consumed atomically via `mv` in `modules/webui/lxc_console.sh`.
   - Firewall drops external TCP `8096` on both Alpine and OpenWrt.
4. **Storage & Backup Isolation:**
   - `/srv/storage` root is `0755 root:root` (no default ACL on root).
   - Samba `[storage]` and LXC bind-mounts expose **`/srv/storage/Shared`** only (plus dedicated Samba `[Music]`, `[Videos]`, `[Downloads]` under `media:media` GID `990`, `2775` + POSIX ACL `rwX`). Never expose `/srv/storage` root, `Backups/`, or `/var/lib/lxc`.
   - `/srv/storage/Backups` is enforced **`0700 root:root`** with `0600` archives. `modules/tools/backup.sh` **must exclude `*storage.luks.key*`** from backup tarballs.
   - Storage-dependent OpenRC daemons (`samba`, `transmission-daemon`, `metube`, `forgejo`, `code-server`) use `/usr/lib/gateway/storage-mount-guard.sh` via `start_pre()` (`ensure_openrc_mount_guard`).
5. **Firewall & `lxcbr0` Isolation (`modules/network/firewall.sh`):**
   - **Alpine:** `/etc/nftables.nft` (`table inet gateway_fw`). Drops `100.64.0.0/10` from trusted LAN input; blocks DoT/DoQ `:853` and IPv6 forwarding; allows only `:53` DNS and `:67` DHCP from `lxcbr0` to host (dropping host management ports `22, 3000, 8095, 8096, 9090, 445`) and drops `lxcbr0 -> RFC1918` LAN lateral traffic; `DNS_RULE`, `:853` reject, and `KS_RULE` cover both `${LAN_IF}` and `lxcbr0`.
   - **OpenWrt:** `/etc/nftables.d/90-gateway.nft` (chains **without** `table inet fw4` wrapper, included directly inside `table inet fw4`), validated via `fw4 check` with rollback.
6. **Supply-Chain & Credentials:**
   - Binary downloads (`sing-box`, `mihomo`) validate exact release tag SHA-256 digests (`verify_github_asset_sha256` with `checksums.txt` fallback) and fail closed on unverified mirrors.
   - Hide secrets from `ps` via `curl -K -` (`clash_api_curl`), read interactive secrets with `stty -echo`, and parse `.env`/cache files via `parse_env_file_safely` (never dot-source untrusted caches).

---

## 3. Dual-Core Routing & DNS Invariants

- **Pinned Baselines (Nov 2026):**
  - `shtorm-7/sing-box-extended`: `v1.14.3-extended-2.7.3` (JSON + `.srs` + WARP AmneziaWG + MASQUE H2).
  - `MetaCubeX/mihomo`: `v1.19.34` (YAML + `.mrs` + AmneziaWG).
  - `AdguardTeam/AdGuardHome`: `v1.0.0` (`schema_version: 35`, `ratelimit: 0`, **`handle_ddr: false`**, 14 explicit managed `.lan` rewrites on Alpine / 6 on OpenWrt — no blanket `*.lan` wildcard).
  - Clash-API Dashboards (`:9090/ui`): `Zephyruso/zashboard` (`v3.30.0`) ⇄ `MetaCubeX/metacubexd` (`v1.275.2`).
- **Shared TUN Contract:** Both Sing-Box Extended and Mihomo configure `CORE_TUN_IF="gateway-tun"`, `MTU 1400`, `stack: system`, `auto_redirect: true`, **`inet4-address: 172.19.0.1/30`**, FakeIP pool `198.18.0.0/15` (`198.18.0.1/16` in Mihomo with stale FakeIP guard `IP-CIDR,198.18.0.0/15,REJECT,no-resolve`).
- **Single Source of Truth (`lib/routing_rules.sh`):** Edit AI, game CDN, bootstrap, DDR, Roblox, Spotify/Twitch, and Homelab `.lan` domain lists **only** in `lib/routing_rules.sh`.
- **Sing-Box 1.14 Rules:** No deprecated `dns.independent_cache` or `ENABLE_DEPRECATED_*` flags; keep `http_clients[0]` (`tag: "default"`, `detour: "DIRECT"`) + `route.default_http_client: "default"`; keep `dns_homelab` (`type: "hosts"`) scoped to `query_type: ["A"]` so `AAAA`/`HTTPS` queries do not hijack fallbacks.
- **Full-VPN & Policy Precedence:**
  - `force_proxy_devices.conf` DNS (`query_type: ["A"] -> dns_fakeip`, non-A `-> dns_proxy`), QUIC reject (`udp/443`), and routing rules must sit **above** BitTorrent and user lists to prevent leaks.
  - All provider-dependent `urltest` groups (`🤖 Авто-ИИ`, `🎮 Авто-Гейминг`, `🇺🇸 Авто-US`, `🇩🇪 Авто-DE`, `⚡ Авто (Самый быстрый)`) include the fail-closed `⛔ Нет рабочих нод` (`socks 127.0.0.1:1`) stub. Never use positional `.outbounds[0]` slicing in `jq`.
  - Keep all selectors documented and consistent: `⚡ Авто (Самый быстрый)`, `🤖 Нейросети (ИИ)` (strictly **before** `google_domain`), `🇩🇪 Германия`, `🇺🇸 США`, `🎮 Гейминг` (default `DIRECT`, real IPs via `dns_ru`, game CDNs always `DIRECT`), `🧱 Roblox` (default `🇩🇪 Германия`, ahead of broad lists), `💬 Мессенджеры`, `▶️ YouTube & Медиа` (incl. Spotify/Twitch), user/extended proxy group, `🌐 Google & Android` (`DIRECT`), `🧲 Торренты` (default `DIRECT`), `📺 Устройства (Full-VPN)` (dynamic), `🌐 Остальной трафик` (`DIRECT`).
  - Block DDR/DoH canaries (`DDR_BLOCK_DOMAINS`) with `NXDOMAIN` (in Mihomo, place `DDR_BLOCK_DOMAINS` as real-IP entries at top of `fake-ip-filter` so `nameserver-policy` returns `rcode://name_error`). Never blindly hijack STUN/WebRTC UDP ports.
- **Low-RAM `GOMEMLIMIT` Tiers (`calc_hardware_limits`):** Never set `"off"` on swapless OpenWrt (`<=300MB`: `60MiB/35MiB` `GOGC=35`; `<=600MB`: `110MiB/55MiB` `GOGC=35`; scaled tiers above).

---

## 4. Web Dashboard & OpenWrt LuCI Invariants

- **Zero-Build Frontend:** `modules/webui/static/{index.html,style.css,app.js,favicon.svg}` and `modules/luci/root/www/luci-static/resources/**` use pure vanilla HTML/CSS/JS — **zero Node/npm/webpack/CDN dependencies**.
- **Schema Parity:** `modules/webui/server.py` (`_collect_status_fast()`) must preserve 100% JSON key and type parity with `modules/webui/api.sh` (`_cmd_status()`). When adding fields to `/api/status`, update both!
- **OpenWrt LuCI `rpcd` 30s Timeout:** Any slow or blocking operation (`update`, `doctor`, `restart`, `core_switch`, `backup`, etc.) must run asynchronously via `job_start` + `job_poll` (never synchronously inside a blocking `ubus` call).
- **UI Safety Rules:** Escape hyphens inside HTML `pattern="[A-Za-z0-9_\-]+"` (Chrome `/v` regex flag); preserve every SVG `<symbol id="...">` referenced by `svgIcon()` in `index.html`; keep mobile `<=640px` horizontal overflow strictly `0px`; never leave spent `ttyd` console tokens in `<a href>`.

---

## 5. Local Verification Commands

Run these checks before submitting changes:

```sh
# 1. Pure LF & no UTF-8 BOM check
python3 -c '
import os, sys
bad = []
for r, ds, fs in os.walk("."):
    ds[:] = [d for d in ds if d != ".git"]
    for f in fs:
        p = os.path.join(r, f)
        b = open(p, "rb").read()
        if b.startswith(b"\xef\xbb\xbf") or (b"\x00" not in b and b"\r\n" in b):
            bad.append(p)
print("BAD_EOL_OR_BOM:", bad)
sys.exit(1 if bad else 0)
'

# 2. POSIX sh syntax check (all *.sh + OpenWrt rpcd handler)
for f in $(find . -type f -name "*.sh" -not -path "*/.git/*" | sort) ./modules/luci/rpcd/gateway; do
  sh -n "$f"
done

# 3. ShellCheck (strict POSIX sh, error severity)
for f in $(find . -type f -name "*.sh" -not -path "*/.git/*" | sort) ./modules/luci/rpcd/gateway; do
  shellcheck -s sh -S error "$f"
done

# 4. Python 3 syntax check
python3 -m py_compile modules/webui/server.py

# 5. JSON validation (LuCI menus & ACLs)
find . -type f -name "*.json" -not -path "*/.git/*" -exec jq empty {} +

# 6. JavaScript syntax check (WebUI & LuCI)
node --check modules/webui/static/app.js
for f in $(find modules/luci/root/www -type f -name "*.js" | sort); do
  node -e "const fs=require('fs'); new Function(fs.readFileSync(process.argv[1],'utf8'));" "$f"
done
```

For standalone Homelab service testing on Alpine Linux:

```sh
sh modules/homelab/services/torrent.sh [install|remove|restart|status]
sh modules/homelab/services/ytdlp.sh [install|remove|restart|status]
sh modules/samba/samba.sh [install|remove|status]
```
