# Security Policy

## Supported Versions

| Version | Supported |
| :--- | :--- |
| `v2026.11` (`main` branch) | ✅ Actively supported |
| Older snapshots | ❌ Please update via `gw update` |

## Built-In Hardening Model

- **Localhost Isolation:** Homelab backend web apps (`Vaultwarden`, `Forgejo`, `MeTube`, `Transmission`, `VS Code Server`) bind exclusively to `127.0.0.1` and are exposed only through **Caddy HTTPS** with TLS + optional BasicAuth.
- **Strict File Permissions:** Environment secrets, core configs (`config.json`, `config.yaml`, `gateway.env`), and backups use `0600` (`0400` for LUKS2 keyfiles).
- **Firewall & Kill-Switch:** `nftables` (`inet gateway_fw`) restricts LAN-only ports, blocks DoT/DoQ `:853` leaks, drops IPv6 forwarding, and provides `gw killswitch on|off`.

## Reporting a Vulnerability

If you discover a security vulnerability, credential leak, firewall bypass, or privilege escalation issue:

1. **Do not** disclose sensitive exploit details or private infrastructure logs in a public issue.
2. Open a private **Security Advisory** on GitHub (**Security → Advisories → Report a vulnerability**), or contact the maintainer with reproduction steps, affected files, and Alpine/core version details.
3. We aim to acknowledge reports promptly and release verified fixes directly to `main`.
