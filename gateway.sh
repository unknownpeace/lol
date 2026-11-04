#!/bin/sh
set -e

# ==============================================================================
# 🚀 Universal Sidecar Gateway & Homelab (Modular Edition)
# Точка входа и загрузчик модулей ядра, сети, Sing-Box и Homelab
# ==============================================================================

# Определение реального каталога расположения шлюза (с поддержкой symlink, readlink -f и PATH)
if [ -z "${GATEWAY_DIR:-}" ]; then
    TARGET="${BASH_SOURCE:-$0}"
    case "$TARGET" in
        */*) ;;
        *)
            CMD_LOC=$(command -v "$TARGET" 2>/dev/null || true)
            [ -n "$CMD_LOC" ] && TARGET="$CMD_LOC"
            ;;
    esac
    REAL_TARGET=$(readlink -f "$TARGET" 2>/dev/null || true)
    if [ -n "$REAL_TARGET" ] && [ -f "$REAL_TARGET" ]; then
        GATEWAY_DIR="$(cd -P "$(dirname "$REAL_TARGET")" && pwd)"
    else
        while [ -h "$TARGET" ]; do
            DIR="$(cd -P "$(dirname "$TARGET")" && pwd)"
            TARGET="$(readlink "$TARGET")"
            case "$TARGET" in
                /*) ;;
                *) TARGET="$DIR/$TARGET" ;;
            esac
        done
        if [ ! -f "$TARGET" ]; then
            for cand in "/opt/gateway/gateway.sh" "/etc/gateway/gateway.sh" "./gateway.sh"; do
                if [ -f "$cand" ]; then
                    TARGET="$cand"
                    break
                fi
            done
        fi
        GATEWAY_DIR="$(cd -P "$(dirname "$TARGET")" && pwd)"
    fi
fi
export GATEWAY_DIR

# Автоматическая привязка глобальных команд /usr/bin/gateway и /usr/bin/gw (при наличии прав)
if [ -d "/usr/bin" ] && [ -w "/usr/bin" ]; then
    if [ ! -L "/usr/bin/gateway" ] || [ "$(readlink -f /usr/bin/gateway 2>/dev/null)" != "${GATEWAY_DIR}/gateway.sh" ]; then
        ln -sf "${GATEWAY_DIR}/gateway.sh" /usr/bin/gateway 2>/dev/null || true
    fi
    if [ ! -L "/usr/bin/gw" ] || [ "$(readlink -f /usr/bin/gw 2>/dev/null)" != "${GATEWAY_DIR}/gateway.sh" ]; then
        ln -sf "${GATEWAY_DIR}/gateway.sh" /usr/bin/gw 2>/dev/null || true
    fi
fi

# Загрузка базовых библиотек (Core & Environment)
. "${GATEWAY_DIR}/lib/constants.sh"
. "${GATEWAY_DIR}/lib/ui.sh"
. "${GATEWAY_DIR}/lib/core.sh"
. "${GATEWAY_DIR}/lib/env.sh"
. "${GATEWAY_DIR}/lib/env_store.sh"
. "${GATEWAY_DIR}/lib/metrics.sh"

# Загрузка сетевых модулей
. "${GATEWAY_DIR}/modules/network/firewall.sh"
. "${GATEWAY_DIR}/modules/network/lan.sh"
. "${GATEWAY_DIR}/modules/network/dhcp.sh"

# Загрузка AdGuard Home
. "${GATEWAY_DIR}/modules/adguard/adguard.sh"

# Загрузка модулей ядра Sing-Box Extended
. "${GATEWAY_DIR}/modules/singbox/rulesets.sh"
. "${GATEWAY_DIR}/modules/singbox/config.sh"
. "${GATEWAY_DIR}/modules/singbox/service.sh"
. "${GATEWAY_DIR}/modules/singbox/providers.sh"
. "${GATEWAY_DIR}/modules/singbox/apply.sh"
. "${GATEWAY_DIR}/modules/singbox/route_inspect.sh"
. "${GATEWAY_DIR}/modules/singbox/node_diag.sh"
. "${GATEWAY_DIR}/modules/singbox/warp.sh"
. "${GATEWAY_DIR}/modules/singbox/setup.sh"

# Загрузка подсистемы дисков и хранилища
. "${GATEWAY_DIR}/modules/storage/storage_unlock.sh"
. "${GATEWAY_DIR}/modules/storage/disks.sh"

# Загрузка веб-сервера Caddy и файлового сервера Samba
. "${GATEWAY_DIR}/modules/caddy/ssl.sh"
. "${GATEWAY_DIR}/modules/caddy/caddy.sh"
. "${GATEWAY_DIR}/modules/samba/samba.sh"

# Загрузка экосистемы Homelab и медиа-сервисов
. "${GATEWAY_DIR}/modules/homelab/registry.sh"
. "${GATEWAY_DIR}/modules/homelab/advisor.sh"
. "${GATEWAY_DIR}/modules/homelab/services/vaultwarden.sh"
. "${GATEWAY_DIR}/modules/homelab/services/forgejo.sh"
. "${GATEWAY_DIR}/modules/homelab/services/code.sh"
. "${GATEWAY_DIR}/modules/homelab/services/navidrome.sh"
. "${GATEWAY_DIR}/modules/homelab/services/jellyfin.sh"
. "${GATEWAY_DIR}/modules/homelab/services/ytdlp.sh"
. "${GATEWAY_DIR}/modules/homelab/services/torrent.sh"
. "${GATEWAY_DIR}/modules/homelab/dispatch.sh"
. "${GATEWAY_DIR}/modules/homelab/selftest.sh"

# Загрузка подсистемы контейнеров LXC
. "${GATEWAY_DIR}/modules/lxc/lxc.sh"

# Загрузка системных утилит, мониторинга и бэкапа
. "${GATEWAY_DIR}/modules/tools/telegram.sh"
. "${GATEWAY_DIR}/modules/tools/maintenance.sh"
. "${GATEWAY_DIR}/modules/tools/password.sh"
. "${GATEWAY_DIR}/modules/tools/cron_toggles.sh"
. "${GATEWAY_DIR}/modules/tools/doctor.sh"
. "${GATEWAY_DIR}/modules/tools/backup.sh"
. "${GATEWAY_DIR}/modules/tools/selftest.sh"

# Загрузка TUI интерфейса и CLI диспетчера
. "${GATEWAY_DIR}/ui/wizard.sh"
. "${GATEWAY_DIR}/ui/cli_utils.sh"
. "${GATEWAY_DIR}/ui/menu.sh"
. "${GATEWAY_DIR}/ui/cli.sh"
