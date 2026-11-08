#!/bin/sh
set -e

# ==============================================================================
# Модуль Transmission (BitTorrent Client Web UI)
# Интеграция с единым хранилищем /srv/storage/Downloads и Caddy HTTPS
# ==============================================================================

if [ -z "${GATEWAY_DIR:-}" ]; then
    GATEWAY_DIR="$(cd -P "$(dirname "$0")/../../.." && pwd)"
    . "${GATEWAY_DIR}/lib/constants.sh"
    . "${GATEWAY_DIR}/lib/ui.sh"
    . "${GATEWAY_DIR}/lib/core.sh"
    . "${GATEWAY_DIR}/lib/env.sh"
    . "${GATEWAY_DIR}/lib/env_store.sh"
    . "${GATEWAY_DIR}/modules/adguard/adguard.sh"
    . "${GATEWAY_DIR}/modules/caddy/ssl.sh"
    . "${GATEWAY_DIR}/modules/caddy/caddy.sh"
    . "${GATEWAY_DIR}/modules/network/firewall.sh"
    . "${GATEWAY_DIR}/modules/homelab/registry.sh"
fi

install_module_torrent() {
    echo "${C_CYN}[*] Установка модуля Transmission (BitTorrent Web UI)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add transmission-daemon transmission-daemon-openrc; then
        echo "${C_RED}[X] Не удалось установить пакет transmission-daemon!${C_RES}"
        return 1
    fi

    load_gateway_env
    init_homelab_storage
    ensure_media_group_and_users

    # Убеждаемся в наличии пользователя transmission и его участии в группе media
    if ! id transmission >/dev/null 2>&1; then
        addgroup -S transmission 2>/dev/null || true
        adduser -S -D -H -h /var/lib/transmission -s /sbin/nologin -G transmission transmission 2>/dev/null || true
    fi
    addgroup transmission "$MEDIA_GROUP" 2>/dev/null || true

    TR_HOME="/var/lib/transmission"
    TR_CONF_DIR="${TR_HOME}/config"
    mkdir -p "$TR_CONF_DIR" "${STORAGE_DOWNLOADS}" "${STORAGE_INCOMPLETE}"

    TR_USER="${SMB_USER:-${AGH_USER:-admin}}"
    TR_PASS="${ADMIN_PASS:-admin}"

    # Остановка сервиса перед перезаписью settings.json (Transmission перезаписывает файл при завершении)
    service_ctl transmission-daemon stop 2>/dev/null || true

    cat << TR_SETTINGS > "${TR_CONF_DIR}/settings.json"
{
    "alt-speed-down": 50,
    "alt-speed-enabled": false,
    "alt-speed-time-begin": 540,
    "alt-speed-time-day": 127,
    "alt-speed-time-enabled": false,
    "alt-speed-time-end": 1020,
    "alt-speed-up": 50,
    "bind-address-ipv4": "0.0.0.0",
    "bind-address-ipv6": "::",
    "blocklist-enabled": false,
    "dht-enabled": true,
    "download-dir": "${STORAGE_DOWNLOADS}",
    "download-queue-enabled": true,
    "download-queue-size": 5,
    "encryption": 1,
    "idle-seeding-limit": 30,
    "idle-seeding-limit-enabled": false,
    "incomplete-dir": "${STORAGE_INCOMPLETE}",
    "incomplete-dir-enabled": true,
    "lpd-enabled": false,
    "max-peers-global": 200,
    "message-level": 1,
    "peer-congestion-algorithm": "",
    "peer-id-ttl-hours": 6,
    "peer-limit-global": 200,
    "peer-limit-per-torrent": 50,
    "peer-port": ${PORT_TRANSMISSION_PEER:-51413},
    "peer-port-random-high": 65535,
    "peer-port-random-low": 49152,
    "peer-port-random-on-start": false,
    "peer-socket-tos": "default",
    "pex-enabled": true,
    "port-forwarding-enabled": false,
    "queue-stalled-enabled": true,
    "queue-stalled-minutes": 30,
    "ratio-limit": 2,
    "ratio-limit-enabled": false,
    "rename-partial-files": true,
    "rpc-authentication-required": true,
    "rpc-bind-address": "127.0.0.1",
    "rpc-enabled": true,
    "rpc-host-whitelist-enabled": false,
    "rpc-password": "${TR_PASS}",
    "rpc-port": ${PORT_TRANSMISSION_WEB:-9091},
    "rpc-url": "/transmission/",
    "rpc-username": "${TR_USER}",
    "rpc-whitelist-enabled": false,
    "scrape-paused-torrents-enabled": true,
    "script-torrent-done-enabled": false,
    "seed-queue-enabled": false,
    "speed-limit-down": 100,
    "speed-limit-down-enabled": false,
    "speed-limit-up": 100,
    "speed-limit-up-enabled": false,
    "start-added-torrents": true,
    "trash-original-torrent-files": false,
    "umask": 2,
    "upload-slots-per-torrent": 14,
    "utp-enabled": true
}
TR_SETTINGS

    chmod 600 "${TR_CONF_DIR}/settings.json"
    chown -R transmission:"$MEDIA_GROUP" "$TR_HOME" 2>/dev/null || true
    chmod 770 "$TR_HOME" "$TR_CONF_DIR" 2>/dev/null || true

    # Настройка параметров OpenRC запуска
    mkdir -p /etc/conf.d
    cat << TR_CONFD > /etc/conf.d/transmission-daemon
runas_user="transmission:${MEDIA_GROUP}"
config_dir="${TR_CONF_DIR}"
download_dir="${STORAGE_DOWNLOADS}"
logfile="/var/log/transmission/transmission.log"
TRANSMISSION_OPTIONS="--foreground"
TR_CONFD

    mkdir -p /var/log/transmission
    chown -R transmission:"$MEDIA_GROUP" /var/log/transmission 2>/dev/null || true
    chmod 750 /var/log/transmission 2>/dev/null || true

    repair_storage_permissions
    init_homelab_registry
    service_ctl transmission-daemon enable
    if ! service_ctl transmission-daemon restart; then
        echo "${C_RED}[X] Служба transmission-daemon не смогла запуститься!${C_RES}"
        return 1
    fi

    sync_dns_firewall "yes" "keep"
    register_caddy_site "torrent" "$DOM_TORRENT" "${PORT_TRANSMISSION_WEB:-9091}" "yes"
    set_module_state "torrent" "yes"

    echo "${C_GRN}[✓] Transmission успешно запущен: https://${DOM_TORRENT} (RPC порт: ${PORT_TRANSMISSION_WEB:-9091})${C_RES}"
    echo "    • Логин: ${C_BLD}${TR_USER}${C_RES} / Пароль: ${C_BLD}${TR_PASS}${C_RES}"
    echo "    • Загрузки сохраняются в: ${C_CYN}${STORAGE_DOWNLOADS}${C_RES}"
    return 0
}

remove_module_torrent() {
    echo "Остановка и отключение Transmission..."
    service_ctl transmission-daemon stop || true
    service_ctl transmission-daemon disable || true
    remove_caddy_site "torrent"
    set_module_state "torrent" "no"
    echo "${C_GRN}[✓] Модуль Transmission отключен (файлы в ${STORAGE_DOWNLOADS} сохранены).${C_RES}"
    return 0
}

if [ "${0##*/}" = "torrent.sh" ] || [ "${0##*/}" = "transmission.sh" ]; then
    case "${1:-status}" in
        install) install_module_torrent ;;
        remove)  remove_module_torrent ;;
        restart) service_ctl transmission-daemon restart ;;
        status)  service_ctl transmission-daemon status ;;
        *)       echo "Использование: $0 [install|remove|restart|status]" ;;
    esac
fi
