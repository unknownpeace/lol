#!/usr/bin/env python3
"""
Bundle Gateway modules into standalone Install.sh
"""
import os
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
GATEWAY_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_FILE = os.path.join(GATEWAY_DIR, "Install.sh")

MODULES = [
    "lib/constants.sh",
    "lib/ui.sh",
    "lib/core.sh",
    "lib/env.sh",
    "lib/env_store.sh",
    "lib/metrics.sh",
    "modules/network/firewall.sh",
    "modules/network/lan.sh",
    "modules/network/dhcp.sh",
    "modules/adguard/adguard.sh",
    "modules/singbox/rulesets.sh",
    "modules/singbox/config.sh",
    "modules/singbox/service.sh",
    "modules/singbox/providers.sh",
    "modules/singbox/apply.sh",
    "modules/singbox/route_inspect.sh",
    "modules/singbox/node_diag.sh",
    "modules/singbox/warp.sh",
    "modules/singbox/setup.sh",
    "modules/storage/storage_unlock.sh",
    "modules/storage/disks.sh",
    "modules/caddy/ssl.sh",
    "modules/caddy/caddy.sh",
    "modules/samba/samba.sh",
    "modules/homelab/registry.sh",
    "modules/homelab/advisor.sh",
    "modules/homelab/services/vaultwarden.sh",
    "modules/homelab/services/forgejo.sh",
    "modules/homelab/services/code.sh",
    "modules/homelab/services/navidrome.sh",
    "modules/homelab/services/jellyfin.sh",
    "modules/homelab/services/ytdlp.sh",
    "modules/homelab/services/torrent.sh",
    "modules/homelab/dispatch.sh",
    "modules/homelab/selftest.sh",
    "modules/lxc/lxc.sh",
    "modules/tools/telegram.sh",
    "modules/tools/maintenance.sh",
    "modules/tools/password.sh",
    "modules/tools/cron_toggles.sh",
    "modules/tools/doctor.sh",
    "modules/tools/backup.sh",
    "modules/tools/selftest.sh",
    "ui/wizard.sh",
    "ui/cli_utils.sh",
    "ui/menu.sh",
    "ui/cli.sh"
]

def main():
    print("=== Сборка автономного Install.sh из модулей Gateway ===")
    total_lines = 0
    with open(OUTPUT_FILE, "w", encoding="utf-8", newline="\n") as out:
        for mod in MODULES:
            path = os.path.join(GATEWAY_DIR, mod)
            if not os.path.isfile(path):
                print(f"[!] Ошибка: Не найден модуль: {path}")
                sys.exit(1)
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
                out.write(content)
                total_lines += content.count("\n")
    print(f"[+] Успешно объединено {len(MODULES)} модулей.")
    print(f"[+] Файл обновлен: {OUTPUT_FILE} ({total_lines} строк)")

if __name__ == "__main__":
    main()
