# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :--- |
| `v2026.11.2` (`main` branch) | ✅ Actively supported |
| Older snapshots | ❌ Please update via `gw update` |

---

## Defense-in-Depth Security Model

**Universal Sidecar Gateway & Homelab** follows a layered, fail-closed hardening model across both **Alpine Linux 3.23–3.24+ (OpenRC)** and **OpenWrt >= 25.12.6 (`procd` + `fw4`)**:

### 1. Web Dashboard, Caddy Reverse Proxy & `ttyd` Console Authentication
- **Localhost Backend Binding:** Homelab web services (`Vaultwarden :8222`, `Forgejo :3001`, `VS Code Web :8443`, `MeTube :8081`, `Transmission :9091`) and `gateway-console` (`ttyd :8096`) bind strictly to `127.0.0.1` and are never directly exposed to the LAN.
- **Caddy ↔ WebUI Shared-Secret Proxy Token (`AUTH_MODE="caddy"`):**
  - When Caddy is enabled, `gateway-webui` binds to `127.0.0.1:8095` and requires the `X-Gateway-Proxy-Token` header on every request, verified in constant time (`hmac.compare_digest`) against `/etc/sing-box/homelab/webui_proxy.token` (`0600 root:root`, 32-char random hex).
  - Caddy enforces `basic_auth` (bcrypt; **fails closed** and aborts site publishing if hash generation fails), stages changes with `caddy validate` before reloading, and strips credentials upstream via **`header_up -Authorization`** on all BasicAuth-protected reverse proxies (`gateway`, `/console*`, `code`, `torrent`, `ytdlp`).
  - `/etc/caddy` and `/etc/caddy/conf.d/*.caddy` are restricted to `root:caddy` (`0750` / `0640`).
- **Direct Mode Fallback (`AUTH_MODE="basic"`):**
  - When Caddy is not installed on Alpine, `gateway-webui` binds to `0.0.0.0:8095` and enforces HTTP BasicAuth directly with per-IP failed-attempt exponential backoff (`HTTP 429` + `Retry-After`) and constant-time credential verification.
- **Browser, CSRF & Logging Hardening (`server.py`):**
  - Strict `Host` and `Origin` allowlist (`localhost`, `127.0.0.1`, `::1`, local LAN IPs, `*.lan`, configured `SSL_DOMAIN`).
  - All state-changing `POST /api/*` requests require `X-Gateway-Action: 1`.
  - Responses include `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: no-referrer`, and `Cache-Control: no-store` (API) / `no-cache` (static assets).
  - Query parameters (`?arg=`, `?token=`) are redacted before access logs are written.
- **Tokenized `ttyd` Web Console (`127.0.0.1:8096`):**
  - Launched with `-i 127.0.0.1 -p 8096 -b /console -a -W -O -t disableReconnect=true` (`-O` enforces origin checks to prevent Cross-Site WebSocket Hijacking).
  - Requires a single-use 32-hex token stored in `/run/gateway/console_tokens/` (`0700 root:root`, 60-second TTL) and consumed atomically via `mv` in `modules/webui/lxc_console.sh`.

### 2. Private Runtime Isolation (`/run/gateway`, `0700 root:root`)
- All runtime locks (`op.lock`, `job.lock`), one-time console tokens (`console_tokens/`), async job scripts/logs (`gw_job_*`), caches (`ver.cache`, `update_check.cache`, `disks.cache`, `lan_scan.cache`), and temporary staging directories live exclusively under `/run/gateway` (`0700 root:root`) with `umask 077`.
- No secrets, credentials, locks, or temporary executable scripts are created in world-writable `/tmp`.

### 3. Storage, LUKS2 Encryption & Backup Isolation
- **Scoped Shared Storage (`/srv/storage/Shared`):** Samba `[storage]` and LXC container bind-mounts are strictly scoped to `/srv/storage/Shared` (with dedicated Samba shares `[Music]`, `[Videos]`, `[Downloads]`). `/srv/storage` root stays `0755 root:root` without a root default ACL, so Samba clients and LXC containers can never read `/srv/storage/Backups` or `/var/lib/lxc`.
- **Backup Confidentiality & Key Exclusion:** `/srv/storage/Backups` is enforced **`0700 root:root`** with `0600` archives. `gw backup` explicitly excludes **`*storage.luks.key*`** from all backup tarballs (and Telegram uploads) so encrypted volume keyfiles never leave the host unintentionally.
- **LUKS2 Hardening:** External volumes use `LUKS2` (`AES-XTS 512-bit + Argon2id`) with RAM-aware `--pbkdf-memory` (`65536` KiB on `<=1 GB` hosts, `131072` KiB otherwise), `0400` root-only keyfiles, `stty -echo` passphrase prompts, and OpenRC Mount Guard (`/usr/lib/gateway/storage-mount-guard.sh`) to prevent storage daemons from filling rootfs when a disk is locked or detached.
- **Strict Config Permissions:** `config.json`, `config.yaml`, `gateway.env`, `homelab.env`, `AdGuardHome.yaml`, and backup archives are enforced at `0600 root:root`.

### 4. Dual-OS Firewall & `lxcbr0` Container Isolation
- **Alpine Linux (`nftables` — `/etc/nftables.nft`, `table inet gateway_fw`):**
  - Accepts management/service traffic strictly from RFC1918 private LAN ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `127.0.0.0/8` — CGNAT `100.64.0.0/10` is explicitly excluded).
  - Blocks external access to internal ports including TCP `8096` (`ttyd`), rejects DoT/DoQ `:853` leaks, and drops IPv6 forwarding.
  - **`lxcbr0` Isolation:** NAT containers on `lxcbr0` may only reach host DNS (`:53`) and DHCP (`:67`); all other host management ports (`22, 3000, 8095, 8096, 9090, 445`) and lateral forwarding from `lxcbr0` to RFC1918 LAN subnets are dropped.
  - **Hardware Kill-Switch (`gw killswitch on`):** Restricts forwarded client WAN traffic across both `${LAN_IF}` and `lxcbr0` strictly to `gateway-tun`.
- **OpenWrt >= 25.12.6 (`fw4` — `/etc/nftables.d/90-gateway.nft`):**
  - Injects validated chains directly into `table inet fw4` (`gateway_input_guard`, `gateway_forward_mss`, `gateway_forward_filter`, `gateway_prerouting_dns`, `gateway_postrouting_nat`).
  - Drops non-RFC1918 access to `:3000`, `:7890`, `:8095`, `:8096`, and `:9090`, blocks `:853` and IPv6 forwarding, enforces Kill-Switch on `${LAN_IF}`, and rolls back automatically if `fw4 check` fails.

### 5. Supply-Chain, DNS & Application Hardening
- **Fail-Closed Binary Verification:** Sing-Box Extended and Mihomo downloads verify SHA-256 digests against exact GitHub release tags (with `checksums.txt` fallback) and abort if a mirror download lacks a verified digest.
- **DNS Anti-Bypass:** AdGuard Home sets `handle_ddr: false` and explicit managed `.lan` rewrites (no wildcard hijacking); cores reject DoH/DDR canaries (`use-application-dns.net`, `_dns.resolver.arpa`, `mask.icloud.com`, `mask-h2.icloud.com`) with `NXDOMAIN` and block `udp/443` QUIC for proxied & Full-VPN policies.
- **Homelab Defaults:** Vaultwarden hashes `ADMIN_TOKEN` with Argon2id (`vaultwarden hash --preset owasp`) and sets `SIGNUPS_ALLOWED="false"`; Forgejo sets `DISABLE_REGISTRATION=true` and warns on older Alpine packages affected by upstream `CVE-2026-89094` (fixed in Forgejo `16.0.4`, check Alpine repo updates); MeTube sets `ALLOW_PRIVATE_ADDRESSES="false"` against SSRF; Samba enforces `SMB2_10`–`SMB3`, `ntlmv2-only`, `server signing = mandatory`, and RFC1918-only `hosts allow`.
- **Process Argument Hygiene:** API credentials are passed via `curl -K -` stdin rather than command-line arguments, and secrets are masked on interactive prompts (`stty -echo`) and in UI/CLI output.

---

## Reporting a Vulnerability

If you discover a security vulnerability, credential leak, firewall bypass, or privilege escalation issue:

1. **Do not** disclose exploit details or private infrastructure logs in a public issue.
2. Open a private **Security Advisory** on GitHub (**Security → Advisories → Report a vulnerability**), or contact the maintainer with reproduction steps, affected files, and platform/core version details.
3. Verified fixes are prioritized and released directly to `main`.
