#!/bin/sh
set -e

# ==============================================================================
# Скрипт сборки автономного монолитного установщика Install.sh из модулей
# ==============================================================================

SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"
GATEWAY_DIR="$(cd -P "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_FILE="${GATEWAY_DIR}/Install.sh"
TEMP_FILE="${OUTPUT_FILE}.tmp"

echo "=== Сборка автономного Install.sh из модулей Gateway ==="

rm -f "$TEMP_FILE"

MODULES="
lib/constants.sh
lib/ui.sh
lib/core.sh
lib/env.sh
lib/env_store.sh
lib/metrics.sh
modules/network/firewall.sh
modules/network/lan.sh
modules/network/dhcp.sh
modules/adguard/adguard.sh
modules/singbox/rulesets.sh
modules/singbox/config.sh
modules/singbox/service.sh
modules/singbox/providers.sh
modules/singbox/apply.sh
modules/singbox/route_inspect.sh
modules/singbox/node_diag.sh
modules/singbox/warp.sh
modules/singbox/setup.sh
modules/storage/storage_unlock.sh
modules/storage/disks.sh
modules/caddy/ssl.sh
modules/caddy/caddy.sh
modules/samba/samba.sh
modules/homelab/registry.sh
modules/homelab/advisor.sh
modules/homelab/services/vaultwarden.sh
modules/homelab/services/forgejo.sh
modules/homelab/services/code.sh
modules/homelab/services/navidrome.sh
modules/homelab/services/jellyfin.sh
modules/homelab/services/ytdlp.sh
modules/homelab/services/torrent.sh
modules/homelab/dispatch.sh
modules/homelab/selftest.sh
modules/lxc/lxc.sh
modules/tools/telegram.sh
modules/tools/maintenance.sh
modules/tools/password.sh
modules/tools/cron_toggles.sh
modules/tools/doctor.sh
modules/tools/backup.sh
modules/tools/selftest.sh
ui/wizard.sh
ui/cli_utils.sh
ui/menu.sh
ui/cli.sh
"

TOTAL_MODS=0
for mod in $MODULES; do
    MOD_PATH="${GATEWAY_DIR}/${mod}"
    if [ ! -f "$MOD_PATH" ]; then
        echo "[!] Ошибка: Не найден модуль: $MOD_PATH"
        rm -f "$TEMP_FILE"
        exit 1
    fi
    cat "$MOD_PATH" >> "$TEMP_FILE"
    TOTAL_MODS=$((TOTAL_MODS + 1))
done

mv -f "$TEMP_FILE" "$OUTPUT_FILE"
chmod +x "$OUTPUT_FILE"

LINE_COUNT=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || true)
echo "[✓] Сборка успешно завершена!"
echo "    Объединено модулей: ${TOTAL_MODS}"
echo "    Итоговый файл: ${OUTPUT_FILE} (${LINE_COUNT} строк)"
