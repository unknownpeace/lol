# 🚀 Universal Sidecar Gateway & Homelab (2026 Edition)

<p align="center">
  <a href="README.ru.md"><b>🇷🇺 Версия на русском языке (README.ru.md)</b></a>
</p>

[![GitHub Repo](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/unknownpeace/lol)
[![Sing-Box Extended](https://img.shields.io/badge/Sing--Box_Extended-v1.14.3-purple)](https://github.com/shtorm-7/sing-box-extended)
[![AdGuard Home](https://img.shields.io/badge/AdGuard_Home-v0.107.60-green)](https://github.com/AdguardTeam/AdGuardHome)
[![Zashboard](https://img.shields.io/badge/Zashboard-Dashboard-orange)](https://github.com/Zephyruso/zashboard)
[![Vaultwarden](https://img.shields.io/badge/Vaultwarden-Bitwarden-blue)](https://github.com/dani-garcia/vaultwarden)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A high-performance, automated, zero-downtime appliance for deploying and managing a **Sidecar Network Gateway, Modular Homelab Suite, and Pure LXC Virtualization Platform** on minimal hardware: Single-Board Computers (Raspberry Pi, Orange Pi, NanoPi), Mini-PCs (Intel N100/N95), Proxmox VE LXC/VMs, or routers running **Alpine Linux 3.21–3.24+** (and OpenWrt 25.12+).

---

## ⚡ Key Highlights

* **Pure Native Performance & Zero Docker Overhead:** All core and home services run via native OpenRC daemons and cgroups v2. Total idle memory consumption is **under 100 MB RAM**.
* **Smart Traffic Routing & Multi-Protocol Core:** Powered by `sing-box-extended`, featuring automated upstream routing, latency-based node selection (`urltest`), split-tunnel rulesets, and fallback chains.
* **DNS Privacy & Anti-Spoofing Architecture:** Dual-engine DNS with **AdGuard Home** (port `:53`) for ad-blocking, tracker suppression, and local `.lan` zone resolution, coupled with upstream encrypted **DoH** (DNS over HTTPS with strict TLS SNI verification) and **FakeIP (`198.18.0.0/15`)** in Sing-Box.
* **Self-Contained Homelab Ecosystem:**
  * **Caddy Reverse Proxy & Local PKI:** Automatic TLS certificate authority and single-click root CA installation portal (`http://ca.lan`).
  * **Samba SMB3 + WSDD:** Seamless network folder sharing with instant auto-discovery on Windows 11 (24H2) and Linux.
  * **Vaultwarden:** Bitwarden-compatible password manager with WebCrypto API and WebAssembly support.
  * **MeTube:** Media downloader for video and audio based on `yt-dlp`.
  * **Transmission:** Lightweight BitTorrent client with RPC Web UI.
  * **Forgejo & Server-Code:** Local Git repository server and in-browser VS Code Web IDE.
* **Encrypted Storage (LUKS2):** Full support for USB/SATA/NVMe storage formatting and mounting (`ext4`, `btrfs` with `zstd:3` compression, `f2fs`) protected by **LUKS2 (Argon2id PBKDF + AES-XTS 512-bit)** with safe unmount (`gw eject`) and automated boot unlocking.
* **Lightweight LXC Virtualization:** Container engine without Docker daemon bloat. Official image downloads (Alpine, Debian, Ubuntu), snapshots, rollback, and container NAT with integrated smart gateway routing.

---

## 🚀 Quick Start

Connect to your Alpine Linux device via SSH as `root`:

### Method 1: Git Installation (Recommended)
```sh
apk add --no-cache git
git clone https://github.com/unknownpeace/lol.git /opt/gateway
cd /opt/gateway
./setup.sh
```

### Method 2: Zero-Touch Unattended Installation
```sh
# Generate template: gw answers template /root/answers.env
gw install --answers /root/answers.env
```

After installation, access the management console at any time with:
```sh
gw        # or 'gateway'
```

---

## 🧩 Modular Architecture

```text
/opt/gateway/
├── gateway.answers.example     # Template for Zero-Touch unattended installs
├── gateway.sh                  # Main entrypoint and module loader
├── setup.sh                    # Command registration (gw/gateway), bash completions, MOTD
├── config/                     # Configuration templates
│   ├── gateway.env.example     # Network, routing, and provider variables
│   └── homelab.env.example     # Storage root, Samba credentials, disk settings
├── lib/                        # Core runtime libraries
│   ├── constants.sh            # Global paths and defaults
│   ├── ui.sh                   # Modern TUI rendering, colors, and progress widgets
│   ├── core.sh                 # Atomic file transactions, inter-process locks, OS detection
│   ├── env.sh                  # Environment validators
│   ├── env_store.sh            # Safe .env persistence
│   └── metrics.sh              # Telemetry, memory limits, and power-loss recovery
├── modules/                    # Isolated service controllers
│   ├── network/                # nftables rules, TProxy, Smart DHCP (AdGuard Home), LAN scanning
│   ├── singbox/                # Core generator, subscriptions, routing groups, diagnostics
│   ├── adguard/                # AdGuard Home rewrites (*.lan) and upstream DNS integration
│   ├── storage/                # LUKS2 crypto-volumes, filesystem optimization, safe mount/umount
│   ├── caddy/                  # HTTPS gateway, local PKI authority, portal ca.lan
│   ├── samba/                  # SMB3 daemon, WSDD (Win11), Avahi mDNS
│   ├── homelab/                # Application modules (Vaultwarden, Transmission, MeTube, etc.)
│   ├── lxc/                    # Native LXC manager, container bridges, snapshots
│   └── tools/                  # Backups, Telegram bot alerts, health watchdog, system doctor
└── ui/                         # User Interface
    ├── wizard.sh               # Initial setup wizard & unattended engine
    ├── menu.sh                 # 16-section interactive TUI dashboard
    ├── cli.sh                  # Non-interactive CLI dispatcher
    └── cli_utils.sh            # Fast CLI shortcuts and helper screens
```

---

## 🏠 Homelab Service Directory

All services bind locally to `127.0.0.1` and are published through Caddy HTTPS:

| Module | Service | Local Address | Internal Port |
| :--- | :--- | :--- | :--- |
| **`1` (`caddy`)** | **Caddy HTTPS & Local PKI** | `http://ca.lan` (`https://ca.lan`) | `:80` / `:443` |
| **`2` (`samba`)** | **Samba SMB3 + WSDD** | `\\HOMELAB\storage` | `:445` |
| **`3` (`vaultwarden`)** | **Vaultwarden (Bitwarden Server)** | `https://vaultwarden.lan` | `127.0.0.1:8222` |
| **`4` (`forgejo`)** | **Forgejo Git Service** | `https://forgejo.lan` | `127.0.0.1:3001` |
| **`5` (`code`)** | **Server-Code (VS Code Web IDE)** | `https://code.lan` | `127.0.0.1:8443` |
| **`6` (`metube`)** | **MeTube Downloader** | `https://downloads.lan` | `127.0.0.1:8081` |
| **`7` (`torrent`)** | **Transmission Web UI** | `https://torrents.lan` | `127.0.0.1:9091` |

---

## 🛠️ Essential CLI Commands

```sh
# General & Health
gw                           # Open main interactive dashboard
gw status                    # Run Self-Test health matrix & ping benchmarks
gw doctor                    # Automated one-click system & database healing
gw update                    # Complete 5-stage atomic update from Git
gw links                     # Print full list of *.lan domains and access credentials

# Routing & Proxy Controls
gw proxy add <url|key|warp>  # Register subscription or node URI
gw domain direct <domain>    # Force domain to route directly via WAN
gw domain proxy <domain>     # Force domain through smart proxy group

# Storage & Crypto
gw unlock                    # Unlock and mount LUKS2 encrypted disk
gw lock                      # Safely stop services, flush buffers, and close LUKS2
gw safe-reboot               # Graceful reboot with clean DB checkpointing
gw safe-poweroff             # Graceful poweroff with storage parking

# Pure LXC Virtualization
gw lxc list                  # List running containers, IPs, and RAM usage
gw lxc create                # Interactive container wizard (Alpine, Debian, Ubuntu)
gw lxc snap <name> create    # Create instant snapshot
gw lxc snap <name> restore   # Restore container from snapshot
```

---

## 📄 License
This project is open-source software licensed under the [MIT License](LICENSE).
