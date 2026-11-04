sync_all_homelab_permissions() {
    load_gateway_env
    init_homelab_storage
    repair_storage_permissions
    chmod 600 "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" "$AGH_CONF" 2>/dev/null || true
    if id vaultwarden >/dev/null 2>&1 || [ -d /var/lib/vaultwarden ]; then
        sync_vaultwarden_config >/dev/null 2>&1 || true
    fi
    if id forgejo >/dev/null 2>&1 && [ -d /var/lib/forgejo ]; then
        FG_GRP=$(id -gn forgejo 2>/dev/null || echo "www-data")
        chown -R "forgejo:${FG_GRP}" /var/lib/forgejo /var/log/forgejo /etc/forgejo 2>/dev/null || true
        chmod 750 /var/lib/forgejo /var/log/forgejo /etc/forgejo 2>/dev/null || true
        [ -f /etc/forgejo/app.ini ] && chmod 640 /etc/forgejo/app.ini 2>/dev/null || true
    fi
    if id navidrome >/dev/null 2>&1 && [ -d /var/lib/navidrome ]; then
        addgroup navidrome "$MEDIA_GROUP" 2>/dev/null || true
        chown -R navidrome:"$MEDIA_GROUP" /var/lib/navidrome /etc/navidrome 2>/dev/null || true
        chmod 750 /var/lib/navidrome /etc/navidrome 2>/dev/null || true
    fi
    if id jellyfin >/dev/null 2>&1; then
        for GRP_J in "$MEDIA_GROUP" video render; do
            addgroup jellyfin "$GRP_J" 2>/dev/null || true
        done
        for JF_D in /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin; do
            [ -d "$JF_D" ] && { chown -R jellyfin:"$MEDIA_GROUP" "$JF_D" 2>/dev/null || true; chmod 750 "$JF_D" 2>/dev/null || true; }
        done
    fi
    if id ytdlp >/dev/null 2>&1; then
        addgroup ytdlp "$MEDIA_GROUP" 2>/dev/null || true
        touch /var/log/ytdlp-webui.log 2>/dev/null || true
        chown ytdlp:"$MEDIA_GROUP" /var/log/ytdlp-webui.log 2>/dev/null || true
    fi
    if id qbittorrent >/dev/null 2>&1 && [ -d /var/lib/qbittorrent ]; then
        addgroup qbittorrent "$MEDIA_GROUP" 2>/dev/null || true
        chown -R qbittorrent:"$MEDIA_GROUP" /var/lib/qbittorrent 2>/dev/null || true
        chmod 750 /var/lib/qbittorrent 2>/dev/null || true
    fi
    if id caddy >/dev/null 2>&1; then
        chown -R caddy:caddy /var/lib/caddy "$PKI_PORTAL_DIR" /etc/caddy 2>/dev/null || true
    fi
    if id coder >/dev/null 2>&1 && [ -d /var/lib/coder ]; then
        addgroup coder "$MEDIA_GROUP" 2>/dev/null || true
        chown -R coder:"$MEDIA_GROUP" /var/lib/coder /opt/code-server 2>/dev/null || true
    fi
    return 0
}

# Вывод структурированной приборной доски всех веб-ссылок и сетевых папок вашего сервера
print_quick_access_card() {
    load_gateway_env
    CUR_LIP=$(get_current_lan_ip)
    HN_VAL=$(hostname -s 2>/dev/null || echo "HOMELAB")
    ui_box_top "🔗 КАРТОЧКА БЫСТРОГО ДОСТУПА К СЕРВЕРУ (${CUR_LIP} | *.lan)"
    ui_box_row "▸ Панель Sing-Box (Zashboard): ${C_GRN}https://${DOM_ZASHBOARD}${C_RES}  ${C_DIM}(или http://${CUR_LIP}:9090/ui)${C_RES}"
    ui_box_row "▸ Панель AdGuard Home (DNS):   ${C_GRN}https://${DOM_ADGUARD}${C_RES}    ${C_DIM}(или http://${CUR_LIP}:3000)${C_RES}"
    ui_box_row "▸ Установка сертификата PKI:   ${C_CYN}http://${DOM_CA}${C_RES}          ${C_DIM}(Windows / Linux / Android в 1 клик)${C_RES}"
    ui_box_row "▸ Единый логин сервисов:       ${C_BLD}${AGH_USER:-admin}${C_RES} ${C_DIM}(пароль синхронизирован во всех модулях)${C_RES}"
    ui_box_sep "АКТИВНЫЕ МОДУЛИ HOMELAB И СЕТЕВЫЕ ШАРЫ"
    is_module_enabled "samba"       && ui_box_row "▸ Сетевой диск Samba (SMB3):   ${C_CYN}\\\\${HN_VAL}\\storage${C_RES} │ ${C_CYN}\\\\${CUR_LIP}\\storage${C_RES} (логин: ${C_BLD}${SMB_USER:-admin}${C_RES})"
    is_module_enabled "vaultwarden" && ui_box_row "▸ Пароли (Vaultwarden):        ${C_GRN}https://${DOM_VAULTWARDEN}${C_RES} ${C_DIM}(админ-панель: /admin)${C_RES}"
    is_module_enabled "jellyfin"    && ui_box_row "▸ Кинотеатр (Jellyfin):        ${C_GRN}https://${DOM_JELLYFIN}${C_RES}    ${C_DIM}(Фильмы / Сериалы / Музыка)${C_RES}"
    is_module_enabled "navidrome"   && ui_box_row "▸ Музыка (Navidrome Subsonic): ${C_GRN}https://${DOM_NAVIDROME}${C_RES}   ${C_DIM}(каталог: ${STORAGE_MUSIC})${C_RES}"
    is_module_enabled "ytdlp"       && ui_box_row "▸ Загрузчик видео/аудио:       ${C_GRN}https://${DOM_YTDLP}${C_RES}   ${C_DIM}(авто-обложки и теги)${C_RES}"
    is_module_enabled "torrent"     && ui_box_row "▸ Торренты (qBittorrent):      ${C_GRN}https://${DOM_TORRENT}${C_RES}    ${C_DIM}(Hardlink-импорт в медиатеку)${C_RES}"
    is_module_enabled "forgejo"     && ui_box_row "▸ Git-сервер (Forgejo):        ${C_GRN}https://${DOM_FORGEJO}${C_RES}"
    is_module_enabled "code"        && ui_box_row "▸ VS Code в браузере:          ${C_GRN}https://${DOM_CODE}${C_RES}"
    ui_box_bottom
    return 0
}

# ==============================================================================
# Универсальный диспетчер модулей Homelab (install / remove / start / stop / restart)
# ==============================================================================
homelab_module_dispatch() {
    MOD_ID="$1"
    MOD_ACT="$2"
    init_homelab_registry

    MOD_SVC=$(get_module_field "$MOD_ID" 3)
    MOD_TITLE=$(get_module_field "$MOD_ID" 7)
    if [ -z "$MOD_TITLE" ]; then
        echo "${C_RED}[X] Неизвестный модуль: ${MOD_ID}${C_RES}"
        return 1
    fi

    case "$MOD_ACT" in
        install)
            case "$MOD_ID" in
                caddy)       install_module_caddy ;;
                samba)       install_module_samba "interactive" ;;
                vaultwarden) install_module_vaultwarden ;;
                forgejo)     install_module_forgejo ;;
                code)        install_module_code ;;
                navidrome)   install_module_navidrome ;;
                jellyfin)    install_module_jellyfin ;;
                ytdlp)       install_module_ytdlp ;;
                torrent)     install_module_torrent ;;
                *)           echo "${C_RED}[X] Неизвестный модуль: ${MOD_ID}${C_RES}"; return 1 ;;
            esac
            ;;
        remove)
            case "$MOD_ID" in
                caddy)       remove_module_caddy ;;
                samba)       remove_module_samba ;;
                vaultwarden) remove_module_vaultwarden ;;
                forgejo)     remove_module_forgejo ;;
                code)        remove_module_code ;;
                navidrome)   remove_module_navidrome ;;
                jellyfin)    remove_module_jellyfin ;;
                ytdlp)       remove_module_ytdlp ;;
                torrent)     remove_module_torrent ;;
                *)           echo "${C_RED}[X] Неизвестный модуль: ${MOD_ID}${C_RES}"; return 1 ;;
            esac
            ;;
        start|stop|restart)
            if [ -n "$MOD_SVC" ]; then
                if service_ctl "$MOD_SVC" "$MOD_ACT"; then
                    [ "$MOD_ID" = "samba" ] && { service_ctl wsdd "$MOD_ACT" || true; service_ctl avahi-daemon "$MOD_ACT" || true; }
                    echo "${C_GRN}[✓] Модуль ${MOD_TITLE} (${MOD_SVC}): действие '${MOD_ACT}' выполнено успешно.${C_RES}"
                else
                    echo "${C_RED}[X] Модуль ${MOD_TITLE} (${MOD_SVC}): ошибка при выполнении '${MOD_ACT}'!${C_RES}"
                    return 1
                fi
            fi
            ;;
        update)
            echo "${C_CYN}[*] Обновление модуля ${MOD_TITLE}...${C_RES}"
            ensure_alpine_community_repo
            apk update >/dev/null 2>&1 || true
            case "$MOD_ID" in
                caddy)       apk upgrade caddy caddy-openrc ;;
                samba)       apk upgrade samba-server samba-common-tools wsdd avahi ;;
                vaultwarden) apk upgrade vaultwarden vaultwarden-openrc vaultwarden-web-vault && sync_vaultwarden_config ;;
                forgejo)     apk upgrade forgejo forgejo-openrc ;;
                code)        rm -f /opt/code-server/code; install_module_code ;;
                navidrome)   apk upgrade navidrome navidrome-openrc ffmpeg ;;
                jellyfin)    apk upgrade jellyfin jellyfin-openrc jellyfin-web jellyfin-ffmpeg ;;
                ytdlp)       apk upgrade yt-dlp py3-yt-dlp py3-mutagen ffmpeg && install_module_ytdlp ;;
                torrent)     apk upgrade qbittorrent-nox qbittorrent-nox-openrc ;;
            esac
            if [ -n "$MOD_SVC" ]; then
                if service_ctl "$MOD_SVC" restart; then
                    echo "${C_GRN}[✓] Модуль ${MOD_TITLE} успешно обновлен и перезапущен.${C_RES}"
                else
                    echo "${C_RED}[X] Модуль ${MOD_TITLE} обновлен, но не смог перезапуститься!${C_RES}"
                    return 1
                fi
            fi
            ;;
    esac
    return 0
}

# ==============================================================================
# Единый модуль резервного копирования (Шлюз + БД SQLite + Caddy PKI + Конфиги)
# ==============================================================================
