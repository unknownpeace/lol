# Contributing to Universal Sidecar Gateway & Homelab

Thank you for helping improve **Universal Sidecar Gateway & Homelab**! Please review the platform rules, security contracts, and verification steps below before opening a Pull Request.

---

## Dual-OS Platform Constraints

This repository targets **two native `apk`-based platforms** with zero Docker, zero `systemd`, and zero legacy `opkg`:

1. **Alpine Linux `3.23–3.24+` (`OpenRC` + `apk-tools v3` + cgroups v2):**
   - Full stack: Dual-core routing (`Sing-Box Extended` ⇄ `Mihomo`), `AdGuard Home`, Alpine Web Dashboard (`:8095`) + `ttyd` LXC Console (`:8096`), Caddy HTTPS (`Local PKI` ⇄ `DuckDNS Let's Encrypt`), 7 Homelab modules, LUKS2 external storage, and LXC 7.0 Container Studio.
2. **OpenWrt `>= 25.12.6` (`procd` + `fw4` + `apk-tools 3.x` + LuCI SPA):**
   - Focused **Gateway + AdGuard Home + `luci-app-gateway`** profile only.
   - Any Alpine-only capability (Homelab, Caddy/PKI, LUKS2, LXC, Python WebUI) **must** be guarded via `require_alpine_feature` / `is_openwrt`.
   - Keep `fw4` rules inside `/etc/nftables.d/90-gateway.nft` (chains without `table inet fw4` wrapper) and preserve LuCI (`uhttpd :80`).

---

## Coding Standards & Contracts

1. **POSIX `sh` / BusyBox `ash` Compatibility:**
   - Every shell script (`gateway.sh`, `setup.sh`, `lib/*.sh`, `modules/**/*.sh`, `ui/*.sh`, and `modules/luci/rpcd/gateway`) must start with `#!/bin/sh`, use **LF (`\n`)** line endings (UTF-8 without BOM), and contain **zero bashisms**.
   - Avoid GNU-only `sed`/`grep`/`find` flags unsupported by BusyBox.
   - **OpenWrt `jq` constraint:** OpenWrt ships `jq` without Oniguruma — do **not** use `test()`, `match()`, or `sub()` inside `jq` expressions.
   - Use canonical helpers from `lib/core.sh` (`service_ctl`, `detect_os`, `is_openwrt`, `ensure_gateway_runtime_dir`) rather than duplicating them.
2. **Security & Runtime Contracts:**
   - **Never store secrets, tokens, locks, caches, or temp scripts in `/tmp`.** Use `/run/gateway` (`0700 root:root`) via `ensure_gateway_runtime_dir`.
   - **Caddy ↔ WebUI Auth:** Keep `X-Gateway-Proxy-Token` (`/etc/sing-box/homelab/webui_proxy.token`, `0600 root:root`) and `header_up -Authorization` intact across `modules/caddy/caddy.sh`, `modules/webui/install.sh`, and `modules/webui/server.py`.
   - **Storage & Backup Isolation:** Keep Samba `[storage]` and LXC bind-mounts scoped strictly to `/srv/storage/Shared`, keep `/srv/storage/Backups` at `0700 root:root` (`0600` files), and never include `*storage.luks.key*` in backups.
   - **Zero Hardcoded Secrets:** Never commit tokens, passwords, private keys, personal hostnames, or test subscription URLs.
3. **Zero-Build WebUI & LuCI Frontends:**
   - `modules/webui/static/*` and `modules/luci/root/www/**/*` use pure vanilla HTML/CSS/JS with zero Node/npm build steps and zero external CDN dependencies.
   - Changes to `/api/status` fields must stay 100% schema-aligned between `modules/webui/server.py` (`_collect_status_fast()`) and `modules/webui/api.sh` (`_cmd_status()`).
   - Long-running operations exposed to WebUI/LuCI must run via `job_start` / `job_poll` (respecting OpenWrt `rpcd`'s 30-second timeout).
4. **Single Source of Truth for Routing Rules:**
   - Update shared domain lists exclusively in [`lib/routing_rules.sh`](lib/routing_rules.sh) so **Sing-Box Extended** and **Mihomo** remain synchronized.

---

## Required Local Verification Before Opening a PR

Run the same checks enforced by [`.github/workflows/ci.yml`](.github/workflows/ci.yml):

```sh
# 1. POSIX sh syntax validation (all *.sh + OpenWrt rpcd handler)
for f in $(find . -type f -name "*.sh" -not -path "*/.git/*" | sort) ./modules/luci/rpcd/gateway; do
  sh -n "$f"
done

# 2. ShellCheck (POSIX sh mode, zero errors)
for f in $(find . -type f -name "*.sh" -not -path "*/.git/*" | sort) ./modules/luci/rpcd/gateway; do
  shellcheck -s sh -S error "$f"
done

# 3. Python 3 syntax check (Alpine Web Dashboard backend)
python3 -m py_compile modules/webui/server.py

# 4. JSON validation (OpenWrt LuCI menus & RPCD ACLs)
find . -type f -name "*.json" -not -path "*/.git/*" -exec jq empty {} +

# 5. JavaScript syntax validation (Alpine WebUI + LuCI SPA)
node --check modules/webui/static/app.js
for f in $(find modules/luci/root/www -type f -name "*.js" | sort); do
  node -e "const fs=require('fs'); new Function(fs.readFileSync(process.argv[1],'utf8'));" "$f"
done

# 6. LF line-ending & UTF-8 no-BOM check
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
assert not bad, f"CRLF or BOM found in: {bad}"
print("LF & no-BOM check passed.")
'
```

---

## Pull Request Guidelines

- Keep PRs focused and well-scoped.
- Update [`README.md`](README.md), [`README.ru.md`](README.ru.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`SECURITY.md`](SECURITY.md), and [`CHANGELOG.md`](CHANGELOG.md) when user-facing behavior, architecture, or security boundaries change.
- Complete every item in the Pull Request template checklist.
