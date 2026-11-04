install_module_navidrome() {
    echo "${C_CYN}[*] Установка модуля Navidrome (Music Streaming Server — Subsonic API)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add navidrome navidrome-openrc ffmpeg; then
        echo "${C_RED}[X] Не удалось установить пакет navidrome!${C_RES}"
        return 1
    fi

    if ! id navidrome >/dev/null 2>&1; then
        addgroup -S navidrome 2>/dev/null || true
        adduser -S -D -H -h /var/lib/navidrome -s /sbin/nologin -G navidrome navidrome 2>/dev/null || true
    fi

    init_homelab_storage
    addgroup navidrome "$MEDIA_GROUP" 2>/dev/null || true
    repair_storage_permissions

    mkdir -p /etc/navidrome /var/lib/navidrome
    cat << ND_EOF > /etc/navidrome/navidrome.toml
MusicFolder = "${STORAGE_MUSIC}"
DataFolder = "/var/lib/navidrome"
Address = "127.0.0.1"
Port = ${PORT_NAVIDROME}
DefaultLanguage = "ru"
ScanSchedule = "@every 15m"
EnableTranscodingConfig = true
ND_EOF
    cp -f /etc/navidrome/navidrome.toml /var/lib/navidrome/navidrome.toml 2>/dev/null || true
    chown -R navidrome:"$MEDIA_GROUP" /var/lib/navidrome /etc/navidrome 2>/dev/null || true
    chmod 750 /var/lib/navidrome /etc/navidrome 2>/dev/null || true
    chmod 640 /etc/navidrome/navidrome.toml /var/lib/navidrome/navidrome.toml 2>/dev/null || true

    if [ -f /etc/conf.d/navidrome ]; then
        grep -q 'command_user=' /etc/conf.d/navidrome 2>/dev/null && \
            sed -i "s|^command_user=.*|command_user=\"navidrome:${MEDIA_GROUP}\"|" /etc/conf.d/navidrome 2>/dev/null || \
            echo "command_user=\"navidrome:${MEDIA_GROUP}\"" >> /etc/conf.d/navidrome
    fi

    service_ctl navidrome enable
    if ! service_ctl navidrome restart; then
        echo "${C_RED}[X] Служба Navidrome не смогла запуститься!${C_RES}"
        return 1
    fi
    register_caddy_site "navidrome" "$DOM_NAVIDROME" "$PORT_NAVIDROME" "no"
    set_module_state "navidrome" "yes"

    echo "${C_GRN}[✓] Navidrome запущен: https://${DOM_NAVIDROME} (Библиотека: ${STORAGE_MUSIC}, совместим с Jellyfin)${C_RES}"
    return 0
}

remove_module_navidrome() {
    service_ctl navidrome stop
    service_ctl navidrome disable
    remove_caddy_site "navidrome"
    set_module_state "navidrome" "no"
    echo "${C_GRN}[✓] Модуль Navidrome отключен (музыка в ${STORAGE_MUSIC} сохранена).${C_RES}"
    return 0
}

# 5. Модуль Jellyfin (Единая медиаплатформа для Видео и Музыки: Movies, Series и Music + FFmpeg + VAAPI)
