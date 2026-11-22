## Summary

<!-- Briefly describe what this PR changes and why. -->

## Checklist

- [ ] Scripts use `#!/bin/sh` and remain compatible with BusyBox `ash` across **Alpine Linux 3.23–3.24+ (OpenRC)** and **OpenWrt >= 25.12.6 (`procd` + `fw4` + `apk`)** (zero Docker / `systemd` / `opkg`).
- [ ] OpenWrt-unsupported features (Homelab, Caddy/PKI, LUKS2, LXC, Alpine WebUI) remain guarded by `require_alpine_feature` / `is_openwrt`.
- [ ] Passed `sh -n` and `shellcheck -s sh -S error` across all `*.sh` files and `modules/luci/rpcd/gateway`.
- [ ] Passed `python3 -m py_compile modules/webui/server.py`, `jq empty` on all JSON files, and JS syntax checks on WebUI/LuCI `.js` files.
- [ ] Verified pure LF (`\n`) line endings (no CRLF) and UTF-8 without BOM.
- [ ] Verified no tokens, passwords, private keys, personal domains, or test secrets are included.
- [ ] Updated documentation (`README.md`, `README.ru.md`, `ARCHITECTURE.md`, `SECURITY.md`, `CHANGELOG.md`) where applicable.
