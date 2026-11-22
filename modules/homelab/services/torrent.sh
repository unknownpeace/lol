#!/bin/sh

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

ensure_transmission_openrc() {
    _tr_home="/var/lib/transmission"
    _tr_conf="${_tr_home}/config"
    _tr_grp="${MEDIA_GROUP:-media}"
    write_storage_mount_guard_script >/dev/null 2>&1 || true

    mkdir -p /etc/conf.d /var/log/transmission
    chown -R transmission:"$_tr_grp" /var/log/transmission 2>/dev/null || true
    chmod 750 /var/log/transmission 2>/dev/null || true

    cat << TR_CONFD > /etc/conf.d/transmission-daemon
command_user="transmission:${_tr_grp}"
cfgdir="${_tr_conf}"
command_args="-f -g ${_tr_conf} --logfile /var/log/transmission/transmission.log"
TR_CONFD

    cat << 'TR_INIT' > /etc/init.d/transmission-daemon
#!/sbin/openrc-run
name="transmission-daemon"
description="Transmission BitTorrent Daemon (Alpine Homelab Edition)"
supervisor="supervise-daemon"
command="/usr/bin/transmission-daemon"
command_user="${command_user:-transmission:media}"
command_args="${command_args:--f -g /var/lib/transmission/config --logfile /var/log/transmission/transmission.log}"
umask="0002"
output_log="/var/log/transmission/transmission.log"
error_log="/var/log/transmission/transmission.log"

depend() {
    need net
    after firewall
}

start_pre() {
    /usr/lib/gateway/storage-mount-guard.sh || return 1 # GW_MOUNT_GUARD
    checkpath -d -m 0750 -o "${command_user}" /var/log/transmission
    checkpath -f -m 0640 -o "${command_user}" /var/log/transmission/transmission.log
    checkpath -d -m 0770 -o "${command_user}" "${cfgdir:-/var/lib/transmission/config}"
}
TR_INIT
    chmod +x /etc/init.d/transmission-daemon
    return 0
}

install_module_torrent() {
    echo "${C_CYN}[*] Установка модуля Transmission (BitTorrent Web UI)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add transmission-daemon transmission-daemon-openrc; then
        echo "${C_RED}[X] Не удалось установить пакет transmission-daemon!${C_RES}"
        return 1
    fi
    command -v jq >/dev/null 2>&1 || apk add --no-cache jq >/dev/null 2>&1 || true
    if ! command -v jq >/dev/null 2>&1; then
        echo "${C_RED}[X] Требуется утилита jq для безопасной генерации settings.json!${C_RES}"
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

    if ! jq -n \
        --arg dl "${STORAGE_DOWNLOADS}" \
        --arg inc "${STORAGE_INCOMPLETE}" \
        --arg rpc_u "$TR_USER" \
        --arg rpc_p "$TR_PASS" \
        --argjson pport "${PORT_TRANSMISSION_PEER:-51413}" \
        --argjson rport "${PORT_TRANSMISSION_WEB:-9091}" \
        '{
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
            "download-dir": $dl,
            "download-queue-enabled": true,
            "download-queue-size": 5,
            "encryption": 1,
            "idle-seeding-limit": 30,
            "idle-seeding-limit-enabled": false,
            "incomplete-dir": $inc,
            "incomplete-dir-enabled": true,
            "lpd-enabled": false,
            "max-peers-global": 200,
            "message-level": 1,
            "peer-congestion-algorithm": "",
            "peer-id-ttl-hours": 6,
            "peer-limit-global": 200,
            "peer-limit-per-torrent": 50,
            "peer-port": $pport,
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
            "rpc-password": $rpc_p,
            "rpc-port": $rport,
            "rpc-url": "/transmission/",
            "rpc-username": $rpc_u,
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
        }' > "${TR_CONF_DIR}/settings.json.tmp.$$"; then
        rm -f "${TR_CONF_DIR}/settings.json.tmp.$$" 2>/dev/null || true
        echo "${C_RED}[X] Ошибка формирования settings.json через jq!${C_RES}"
        return 1
    fi
    mv -f "${TR_CONF_DIR}/settings.json.tmp.$$" "${TR_CONF_DIR}/settings.json"

    chmod 600 "${TR_CONF_DIR}/settings.json"
    chown -R transmission:"$MEDIA_GROUP" "$TR_HOME" 2>/dev/null || true
    chmod 770 "$TR_HOME" "$TR_CONF_DIR" 2>/dev/null || true

    # Настройка параметров OpenRC запуска (command_user / command_args + Mount Guard)
    ensure_transmission_openrc

    repair_storage_permissions
    init_homelab_registry
    service_ctl transmission-daemon enable
    if ! service_ctl transmission-daemon restart; then
        echo "${C_RED}[X] Служба transmission-daemon не смогла запуститься!${C_RES}"
        return 1
    fi

    sync_dns_firewall "yes" "keep"
    register_caddy_site "torrent" "$DOM_TORRENT" "${PORT_TRANSMISSION_WEB:-9091}" "yes"
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
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
