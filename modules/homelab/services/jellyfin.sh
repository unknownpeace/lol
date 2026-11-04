install_module_jellyfin() {
    echo "${C_CYN}[*] Установка модуля Jellyfin (Unified Media Server: Movies + Series + Music + FFmpeg)...${C_RES}"
    umask 022
    if [ "${TOTAL_RAM_MB:-512}" -lt 1000 ]; then
        echo "${C_YEL}[!] Внимание: Для Jellyfin рекомендуется минимум 1.5–2 ГБ ОЗУ.${C_RES}"
    fi
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add jellyfin jellyfin-openrc jellyfin-web jellyfin-ffmpeg; then
        if ! apk add jellyfin jellyfin-openrc jellyfin-web ffmpeg; then
            echo "${C_RED}[X] Не удалось установить пакеты jellyfin!${C_RES}"
            return 1
        fi
    fi

    if ! id jellyfin >/dev/null 2>&1; then
        addgroup -S jellyfin 2>/dev/null || true
        adduser -S -D -H -h /var/lib/jellyfin -s /sbin/nologin -G jellyfin jellyfin 2>/dev/null || true
    fi

    init_homelab_storage
    for GRP_J in "$MEDIA_GROUP" video render; do
        addgroup jellyfin "$GRP_J" 2>/dev/null || true
    done
    repair_storage_permissions

    mkdir -p /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin
    chown -R jellyfin:"$MEDIA_GROUP" /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin 2>/dev/null || true
    chmod 750 /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin 2>/dev/null || true

    # Удаление флага --nowebclient в Alpine /etc/conf.d/jellyfin для активации пакета jellyfin-web
    if [ -f /etc/conf.d/jellyfin ]; then
        sed -i 's/--nowebclient//g' /etc/conf.d/jellyfin 2>/dev/null || true
        grep -q 'rc_oom_score_adj=' /etc/conf.d/jellyfin 2>/dev/null || echo 'rc_oom_score_adj="200"' >> /etc/conf.d/jellyfin
    fi

    service_ctl jellyfin enable
    if ! service_ctl jellyfin restart; then
        echo "${C_RED}[X] Служба Jellyfin не смогла запуститься!${C_RES}"
        return 1
    fi
    W_JF=0
    while [ "$W_JF" -lt 12 ]; do
        curl -sS -o /dev/null --connect-timeout 1 -m 2 "http://127.0.0.1:${PORT_JELLYFIN}" 2>/dev/null && break
        sleep 1
        W_JF=$((W_JF + 1))
    done
    register_caddy_site "jellyfin" "$DOM_JELLYFIN" "$PORT_JELLYFIN" "no"
    set_module_state "jellyfin" "yes"

    echo "${C_GRN}[✓] Jellyfin запущен: https://${DOM_JELLYFIN} (Единая медиаплатформа Видео + Музыка)${C_RES}"
    echo "    • Библиотека Фильмов (Movies):   ${C_CYN}${STORAGE_VIDEOS_MOVIES}${C_RES} (или ${STORAGE_VIDEOS})"
    echo "    • Библиотека Сериалов (Shows):   ${C_CYN}${STORAGE_VIDEOS_SERIES}${C_RES}"
    echo "    • Библиотека Музыки (Music):     ${C_CYN}${STORAGE_MUSIC}${C_RES} (полный доступ через группу ${MEDIA_GROUP} + ACL)"
    return 0
}

remove_module_jellyfin() {
    service_ctl jellyfin stop
    service_ctl jellyfin disable
    remove_caddy_site "jellyfin"
    set_module_state "jellyfin" "no"
    echo "${C_GRN}[✓] Модуль Jellyfin отключен (медиафайлы в ${STORAGE_VIDEOS} и ${STORAGE_MUSIC} сохранены).${C_RES}"
    return 0
}

# Сравнительный обзор и управление архитектурой медиатеки (Единый Jellyfin для видео+музыки vs связка с Navidrome)
