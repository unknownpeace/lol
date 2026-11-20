# Contributing to Universal Sidecar Gateway & Homelab

Thank you for helping improve **Universal Sidecar Gateway & Homelab**!

## Core Platform Constraints

1. **Strictly Alpine Linux + OpenRC + `apk`:** Never introduce Docker, `systemd`, `opkg`, or OpenWrt assumptions.
2. **POSIX / BusyBox `ash` Compatibility:** All scripts under `lib/`, `modules/`, and `ui/` must:
   - Start with `#!/bin/sh`.
   - Use **LF (`\n`)** line endings only (never CRLF).
   - Avoid GNU-only sed/grep/find flags unsupported by BusyBox (or guard them cleanly).
3. **Zero Hardcoded Secrets:** Never commit tokens, passwords, private keys, personal hostnames, or test subscription URLs.
4. **Shared Routing Rules:** Update domain lists in [`lib/routing_rules.sh`](lib/routing_rules.sh) so **Sing-Box Extended** and **Mihomo** stay synchronized.

## Required Checks Before Opening a Pull Request

Run these checks locally or inside an Alpine Linux environment:

```sh
# 1. POSIX shell syntax check
find . -type f -name "*.sh" -not -path "*/.git/*" -exec sh -n {} +

# 2. ShellCheck (errors must be 0)
find . -type f -name "*.sh" -not -path "*/.git/*" -exec shellcheck -S error {} +
```

Please keep PRs focused, update both `README.md` / `README.ru.md` (and `ARCHITECTURE.md` if architecture changes), and fill out the Pull Request template checklist.
