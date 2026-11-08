#!/bin/sh
set -e

# ==============================================================================
# Модуль MeTube (yt-dlp Web UI без Docker)
# Раздельное сохранение: Видео -> /srv/storage/Videos, Аудио -> /srv/storage/Music
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

install_module_ytdlp() {
    echo "${C_CYN}[*] Установка модуля MeTube (yt-dlp Web UI)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true

    # Системные пакеты (Python 3, aiohttp, yt-dlp, ffmpeg, crane)
    if ! apk add python3 py3-pip py3-aiohttp yt-dlp ffmpeg crane ca-certificates; then
        echo "${C_RED}[X] Ошибка установки системных пакетов для MeTube!${C_RES}"
        return 1
    fi

    load_gateway_env
    init_homelab_storage
    ensure_media_group_and_users

    # Пользователь metube в группе media
    if ! id metube >/dev/null 2>&1; then
        addgroup -S metube 2>/dev/null || true
        adduser -S -D -H -h "${METUBE_DIR:-/opt/metube}" -s /sbin/nologin -G "$MEDIA_GROUP" metube 2>/dev/null || true
    fi
    addgroup metube "$MEDIA_GROUP" 2>/dev/null || true

    # Развертывание директории приложения MeTube
    mkdir -p "${METUBE_DIR:-/opt/metube}" "${STORAGE_VIDEOS}" "${STORAGE_MUSIC}" "${STORAGE_INCOMPLETE}/metube"

    # Загрузка и распаковка готового бэкенда и скомпилированного Web UI MeTube
    if [ ! -f "${METUBE_DIR}/app/app/main.py" ] || [ ! -d "${METUBE_DIR}/app/ui/dist" ]; then
        echo "${C_CYN}[*] Загрузка актуального релиза MeTube...${C_RES}"
        crane export ghcr.io/alexta69/metube:latest - 2>/dev/null | tar -x -C "${METUBE_DIR}" app || {
            echo "${C_RED}[X] Не удалось извлечь MeTube!${C_RES}"
            return 1
        }
    fi

    # Установка Python-зависимостей (python-socketio и watchfiles)
    if ! python3 -c "import socketio, watchfiles" >/dev/null 2>&1; then
        echo "${C_CYN}[*] Настройка Python-модулей MeTube...${C_RES}"
        pip install --break-system-packages "python-socketio>=5.0,<6.0" watchfiles >/dev/null 2>&1 || \
        pip install "python-socketio>=5.0,<6.0" watchfiles >/dev/null 2>&1 || true
    fi

    # Выставляем права
    chown -R metube:"$MEDIA_GROUP" "${METUBE_DIR}" "${STORAGE_INCOMPLETE}/metube" 2>/dev/null || true
    chmod -R 775 "${METUBE_DIR}" 2>/dev/null || true

    # Остановка старого самописного демона ytdlp-webui (если работал)
    service_ctl ytdlp-webui stop 2>/dev/null || true
    service_ctl ytdlp-webui disable 2>/dev/null || true
    rm -f /etc/init.d/ytdlp-webui 2>/dev/null || true

    # Создание службы OpenRC для MeTube
    cat << METUBE_INIT > /etc/init.d/metube
#!/sbin/openrc-run
name="metube"
description="MeTube Web UI for yt-dlp"
supervisor="supervise-daemon"
command="/usr/bin/python3"
command_args="-m app.main"
command_user="metube:${MEDIA_GROUP}"
directory="${METUBE_DIR}/app"
umask="0002"
output_log="/var/log/metube.log"
error_log="/var/log/metube.log"
rc_nice="10"
rc_oom_score_adj="400"

export PYTHONPATH="${METUBE_DIR}/app/app"
export DOWNLOAD_DIR="${STORAGE_VIDEOS}"
export AUDIO_DOWNLOAD_DIR="${STORAGE_MUSIC}"
export TEMP_DIR="${STORAGE_INCOMPLETE}/metube"
export PORT="${PORT_METUBE:-8081}"
export CUSTOM_DIRS="true"
export CREATE_CUSTOM_DIRS="true"
export OUTPUT_TEMPLATE="%(title)s.%(ext)s"
export OUTPUT_TEMPLATE_PLAYLIST="%(playlist_title)s/%(title)s.%(ext)s"
export ALLOW_PRIVATE_ADDRESSES="true"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -f -m 0644 -o metube:${MEDIA_GROUP} /var/log/metube.log
    checkpath -d -m 2775 -o metube:${MEDIA_GROUP} "${STORAGE_INCOMPLETE}/metube"
}
METUBE_INIT
    chmod +x /etc/init.d/metube

    repair_storage_permissions
    init_homelab_registry
    service_ctl metube enable
    if ! service_ctl metube restart; then
        echo "${C_RED}[X] Служба metube не смогла запуститься! Проверьте /var/log/metube.log.${C_RES}"
        return 1
    fi

    sync_dns_firewall "yes" "keep"
    register_caddy_site "ytdlp" "$DOM_METUBE" "${PORT_METUBE:-8081}" "yes"
    set_module_state "ytdlp" "yes"

    echo "${C_GRN}[✓] MeTube успешно запущен: https://${DOM_METUBE} (порт: ${PORT_METUBE:-8081})${C_RES}"
    echo "    • Видео скачивается в: ${C_CYN}${STORAGE_VIDEOS}${C_RES}"
    echo "    • Музыка/аудио скачивается в: ${C_CYN}${STORAGE_MUSIC}${C_RES}"
    return 0
}

remove_module_ytdlp() {
    echo "Остановка и отключение MeTube..."
    service_ctl metube stop || true
    service_ctl metube disable || true
    service_ctl ytdlp-webui stop 2>/dev/null || true
    service_ctl ytdlp-webui disable 2>/dev/null || true
    remove_caddy_site "ytdlp"
    set_module_state "ytdlp" "no"
    echo "${C_GRN}[✓] Модуль MeTube отключен (скачанные файлы сохранены).${C_RES}"
    return 0
}

if [ "${0##*/}" = "ytdlp.sh" ] || [ "${0##*/}" = "metube.sh" ]; then
    case "${1:-status}" in
        install) install_module_ytdlp ;;
        remove)  remove_module_ytdlp ;;
        restart) service_ctl metube restart ;;
        status)  service_ctl metube status ;;
        *)       echo "Использование: $0 [install|remove|restart|status]" ;;
    esac
fi
