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
    if id metube >/dev/null 2>&1; then
        addgroup metube "$MEDIA_GROUP" 2>/dev/null || true
        touch /var/log/metube.log 2>/dev/null || true
        chown metube:"$MEDIA_GROUP" /var/log/metube.log 2>/dev/null || true
    fi
    if id transmission >/dev/null 2>&1 && [ -d /var/lib/transmission ]; then
        addgroup transmission "$MEDIA_GROUP" 2>/dev/null || true
        chown -R transmission:"$MEDIA_GROUP" /var/lib/transmission 2>/dev/null || true
        chmod 770 /var/lib/transmission 2>/dev/null || true
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
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        ui_box_top "🔗 КАРТОЧКА БЫСТРОГО ДОСТУПА К СЕРВЕРУ (${CUR_LIP} | *.${SSL_DOMAIN})"
        ui_box_row "▸ Режим сертификата:      ${C_GRN}● Валидный Let's Encrypt Wildcard (*.${SSL_DOMAIN})${C_RES}"
        ui_box_row "▸ Панель Sing-Box:        ${C_GRN}https://zashboard.${SSL_DOMAIN}${C_RES}  ${C_DIM}(или http://${CUR_LIP}:9090/ui)${C_RES}"
        ui_box_row "▸ Панель AdGuard Home:    ${C_GRN}https://adguard.${SSL_DOMAIN}${C_RES}    ${C_DIM}(или http://${CUR_LIP}:3000)${C_RES}"
        ui_box_row "▸ Единый логин сервисов:  ${C_BLD}${AGH_USER:-admin}${C_RES} ${C_DIM}(пароль синхронизирован во всех модулях)${C_RES}"
        ui_box_sep "АКТИВНЫЕ МОДУЛИ HOMELAB И СЕТЕВЫЕ ШАРЫ"
        is_module_enabled "samba"       && ui_box_row "▸ Сетевой диск Samba (SMB3):   ${C_CYN}\\\\${HN_VAL}\\storage${C_RES} │ ${C_CYN}\\\\${CUR_LIP}\\storage${C_RES}"
        is_module_enabled "vaultwarden" && ui_box_row "▸ Пароли (Vaultwarden):        ${C_GRN}https://vaultwarden.${SSL_DOMAIN}${C_RES} ${C_DIM}(админ: /admin)${C_RES}"
        is_module_enabled "ytdlp"       && ui_box_row "▸ Загрузчик MeTube:            ${C_GRN}https://downloads.${SSL_DOMAIN}${C_RES} ${C_DIM}(видео -> Videos, аудио -> Music)${C_RES}"
        is_module_enabled "torrent"     && ui_box_row "▸ Торренты (Transmission):     ${C_GRN}https://torrents.${SSL_DOMAIN}${C_RES}"
        is_module_enabled "forgejo"     && ui_box_row "▸ Git-сервер (Forgejo):        ${C_GRN}https://forgejo.${SSL_DOMAIN}${C_RES}"
        is_module_enabled "code"        && ui_box_row "▸ VS Code в браузере:          ${C_GRN}https://code.${SSL_DOMAIN}${C_RES}"
    else
        ui_box_top "🔗 КАРТОЧКА БЫСТРОГО ДОСТУПА К СЕРВЕРУ (${CUR_LIP} | *.lan)"
        ui_box_row "▸ Панель Sing-Box (Zashboard): ${C_GRN}https://${DOM_ZASHBOARD}${C_RES}  ${C_DIM}(или http://${CUR_LIP}:9090/ui)${C_RES}"
        ui_box_row "▸ Панель AdGuard Home (DNS):   ${C_GRN}https://${DOM_ADGUARD}${C_RES}    ${C_DIM}(или http://${CUR_LIP}:3000)${C_RES}"
        ui_box_row "▸ Установка сертификата PKI:   ${C_CYN}http://${DOM_CA}${C_RES}          ${C_DIM}(Windows / Linux / Android в 1 клик)${C_RES}"
        ui_box_row "▸ Единый логин сервисов:       ${C_BLD}${AGH_USER:-admin}${C_RES} ${C_DIM}(пароль синхронизирован во всех модулях)${C_RES}"
        ui_box_sep "АКТИВНЫЕ МОДУЛИ HOMELAB И СЕТЕВЫЕ ШАРЫ"
        is_module_enabled "samba"       && ui_box_row "▸ Сетевой диск Samba (SMB3):   ${C_CYN}\\\\${HN_VAL}\\storage${C_RES} │ ${C_CYN}\\\\${CUR_LIP}\\storage${C_RES} (логин: ${C_BLD}${SMB_USER:-admin}${C_RES})"
        is_module_enabled "vaultwarden" && ui_box_row "▸ Пароли (Vaultwarden):        ${C_GRN}https://${DOM_VAULTWARDEN}${C_RES} ${C_DIM}(админ-панель: /admin)${C_RES}"
        is_module_enabled "ytdlp"       && ui_box_row "▸ Загрузчик MeTube:            ${C_GRN}https://${DOM_METUBE}${C_RES}   ${C_DIM}(видео -> Videos, аудио -> Music)${C_RES}"
        is_module_enabled "torrent"     && ui_box_row "▸ Торренты (Transmission):     ${C_GRN}https://${DOM_TORRENT}${C_RES}    ${C_DIM}(RPC веб-интерфейс)${C_RES}"
        is_module_enabled "forgejo"     && ui_box_row "▸ Git-сервер (Forgejo):        ${C_GRN}https://${DOM_FORGEJO}${C_RES}"
        is_module_enabled "code"        && ui_box_row "▸ VS Code в браузере:          ${C_GRN}https://${DOM_CODE}${C_RES}"
    fi
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
                ytdlp|metube) install_module_ytdlp ;;
                torrent|transmission) install_module_torrent ;;
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
                ytdlp|metube) remove_module_ytdlp ;;
                torrent|transmission) remove_module_torrent ;;
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
                ytdlp|metube) apk upgrade yt-dlp python3 py3-aiohttp ffmpeg && install_module_ytdlp ;;
                torrent|transmission) apk upgrade transmission-daemon transmission-daemon-openrc ;;
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
