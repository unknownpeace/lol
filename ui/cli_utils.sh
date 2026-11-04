resolve_homelab_module_id() {
    RAW_M=$(printf "%s" "${1:-}" | tr 'A-Z' 'a-z' | tr -d ' \t\r\n')
    case "$RAW_M" in
        1|caddy)                  printf "caddy" ;;
        2|samba|smb)              printf "samba" ;;
        3|vaultwarden|vw|bw)      printf "vaultwarden" ;;
        4|forgejo|git)            printf "forgejo" ;;
        5|code|vscode|code-server) printf "code" ;;
        6|navidrome|music)        printf "navidrome" ;;
        7|jellyfin|jf)            printf "jellyfin" ;;
        8|ytdlp|yt|downloads)     printf "ytdlp" ;;
        9|torrent|qbittorrent)    printf "torrent" ;;
        *)                        return 1 ;;
    esac
    return 0
}

# Быстрое просмотр логов любой службы из CLI: `gateway logs [service]`
show_service_logs_cli() {
    SVC_Q=$(printf "%s" "${1:-sing-box}" | tr 'A-Z' 'a-z' | tr -d ' \t\r\n')
    LINES_Q="${2:-45}"
    ui_box_top "📜 ЖУРНАЛ СОБЫТИЙ СЛУЖБЫ: ${SVC_Q} (последние ${LINES_Q} строк)"
    case "$SVC_Q" in
        sing-box|singbox|sb)
            show_singbox_logs "$LINES_Q"
            ;;
        adguard|adguardhome|agh)
            if [ -f /var/log/messages ]; then
                grep -i "AdGuardHome" /var/log/messages 2>/dev/null | tail -n "$LINES_Q" || echo "  (записей пока нет)"
            fi
            ;;
        caddy|https|pki)
            tail -n "$LINES_Q" /var/log/caddy.log 2>/dev/null || echo "  (лог /var/log/caddy.log пуст)"
            ;;
        vaultwarden|vw|bitwarden)
            tail -n "$LINES_Q" /var/log/vaultwarden.log 2>/dev/null || echo "  (лог /var/log/vaultwarden.log пуст)"
            ;;
        ytdlp|ytdlp-webui|downloads)
            tail -n "$LINES_Q" /var/log/ytdlp-webui.log 2>/dev/null || echo "  (лог /var/log/ytdlp-webui.log пуст)"
            ;;
        code|code-server|vscode)
            tail -n "$LINES_Q" /var/log/code-server.log 2>/dev/null || echo "  (лог /var/log/code-server.log пуст)"
            ;;
        samba|smb|smbd)
            tail -n "$LINES_Q" /var/log/samba/log.smbd 2>/dev/null || echo "  (лог /var/log/samba/log.smbd пуст)"
            ;;
        forgejo|git)
            tail -n "$LINES_Q" /var/log/forgejo/*.log 2>/dev/null || echo "  (лог /var/log/forgejo пуст)"
            ;;
        jellyfin|jf)
            tail -n "$LINES_Q" /var/log/jellyfin/*.log /var/log/jellyfin.log 2>/dev/null || echo "  (лог jellyfin пуст)"
            ;;
        navidrome|music)
            tail -n "$LINES_Q" /var/log/navidrome.log 2>/dev/null || echo "  (лог /var/log/navidrome.log пуст)"
            ;;
        torrent|qbittorrent|qbittorrent-nox)
            tail -n "$LINES_Q" /var/log/qbittorrent-nox.log 2>/dev/null || echo "  (лог /var/log/qbittorrent-nox.log пуст)"
            ;;
        autoupdate|cron)
            tail -n "$LINES_Q" "$AUTOUPDATE_LOG" 2>/dev/null || echo "  (лог ${AUTOUPDATE_LOG} пуст)"
            ;;
        *)
            echo "  ${C_YEL}[▲] Неизвестная служба: ${SVC_Q}${C_RES}"
            echo "  Доступные: sing-box, adguard, caddy, vaultwarden, ytdlp, code, samba, forgejo, jellyfin, navidrome, torrent, autoupdate"
            ;;
    esac
    ui_box_bottom
    return 0
}

# Быстрое добавление прокси/подписки из CLI: `gateway proxy add <url|key|warp>`
cli_proxy_add() {
    RAW_P_ARG=$(clean_clipboard_line "${1:-}")
    if [ -z "$RAW_P_ARG" ]; then
        ui_warn_box "Не указана ссылка на подписку или URI-ключ прокси." \
                    "Пример: gateway proxy add https://sub.example.com/api/v1/client/subscribe?token=..."
        return 1
    fi
    backup_gateway_state
    load_gateway_env
    init_user_lists
    case "$RAW_P_ARG" in
        http://*|https://*)
            CLEAN_P=$(sanitize_sub_url_list "$RAW_P_ARG")
            case " ${SUB_URL:-} " in
                *" ${CLEAN_P} "*) ;;
                *) SUB_URL="${SUB_URL:+${SUB_URL} }${CLEAN_P}" ;;
            esac
            apply_and_verify_singbox "CLI: Добавление подписки в Слот 1"
            ;;
        warp|WARP|amnezia|masque)
            generate_amnezia_warp "${2:-}" && apply_and_verify_singbox "CLI: Активация Amnezia WARP 2.0 + MASQUE H2"
            ;;
        *)
            sed -i '/^proxies:[[:space:]]*\[\]/d' "$CUSTOM_NODES_FILE" 2>/dev/null || true
            format_uri_keys "$RAW_P_ARG" >> "$CUSTOM_NODES_FILE"
            apply_and_verify_singbox "CLI: Добавление ключа в Слот 2 (my_nodes.yaml)"
            ;;
    esac
    return $?
}

# Быстрое добавление домена в список DIRECT или PROXY из CLI: `gateway domain direct|proxy <url|domain>`
cli_domain_rule_add() {
    RULE_MODE="${1:-proxy}"
    RAW_D_ARG=$(clean_clipboard_line "${2:-}")
    if [ -z "$RAW_D_ARG" ]; then
        ui_warn_box "Не указан домен или URL для маршрутизации." \
                    "Пример: gateway domain ${RULE_MODE} https://kinopoisk.ru"
        return 1
    fi
    CLEAN_D=$(sanitize_domain_entry "$RAW_D_ARG" || true)
    if [ -z "$CLEAN_D" ]; then
        ui_warn_box "Некорректный формат домена: ${RAW_D_ARG} (IP-адреса добавляются в меню устройств п. 8)." \
                    "Укажите доменное имя или ссылку, например: gateway domain ${RULE_MODE} site.com"
        return 1
    fi
    backup_gateway_state
    load_gateway_env
    init_user_lists
    if [ "$RULE_MODE" = "direct" ]; then
        awk -v d="$CLEAN_D" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.chatgpt.com"}' "$USER_PROXY_FILE" > "${USER_PROXY_FILE}.tmp.$$"
        atomic_commit_tmp "${USER_PROXY_FILE}.tmp.$$" "$USER_PROXY_FILE" 0644 "root:root" || true
        grep -qxF "$CLEAN_D" "$USER_DIRECT_FILE" 2>/dev/null || echo "$CLEAN_D" >> "$USER_DIRECT_FILE"
        apply_and_verify_singbox "CLI: Перевод домена ${CLEAN_D} напрямую (DIRECT)"
    else
        awk -v d="$CLEAN_D" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.localdomain"}' "$USER_DIRECT_FILE" > "${USER_DIRECT_FILE}.tmp.$$"
        atomic_commit_tmp "${USER_DIRECT_FILE}.tmp.$$" "$USER_DIRECT_FILE" 0644 "root:root" || true
        grep -qxF "$CLEAN_D" "$USER_PROXY_FILE" 2>/dev/null || echo "$CLEAN_D" >> "$USER_PROXY_FILE"
        apply_and_verify_singbox "CLI: Перевод домена ${CLEAN_D} в прокси (PROXY)"
    fi
    return $?
}

# Полная красиво оформленная в ASCII-рамках справка по всем CLI-командам `gateway help`
print_gateway_cli_help() {
    ui_banner "GATEWAY CLI // СПРАВОЧНИК КОМАНД АДМИНИСТРАТОРА (v2026.11)"
    ui_box_top "🚀 ОСНОВНЫЕ КОМАНДЫ УПРАВЛЕНИЯ ШЛЮЗОМ И ДАШБОРДОМ"
    ui_box_row "${C_CYN}gateway${C_RES}                          — Главное интерактивное TUI-меню с телеметрией"
    ui_box_row "${C_CYN}gateway status${C_RES} (или ${C_CYN}test${C_RES})        — Полный рентген и матрица здоровья (Self-Test 2.0 + Ping Matrix)"
    ui_box_row "${C_CYN}gateway doctor${C_RES} (или ${C_CYN}fix${C_RES})         — Умная авто-починка одной командой (модули, DNS, nftables, БД, диск)"
    ui_box_row "${C_CYN}gateway restart${C_RES}                  — Быстрая пересборка конфига, сброс conntrack и перезапуск шлюза"
    ui_box_row "${C_CYN}gateway update${C_RES}                   — Обновление ядер Sing-Box Extended, AdGuard Home, Zashboard и Homelab"
    ui_box_row "${C_CYN}gateway links${C_RES} (или ${C_CYN}urls${C_RES})         — Карточка всех веб-адресов https://*.lan, сертификата и шары Samba"
    ui_box_row "${C_CYN}gateway logs [служба]${C_RES}            — Живые логи (sing-box|adguard|caddy|vaultwarden|jellyfin|samba|...)"
    ui_box_sep "🔐 ЗАЩИТА ПИТАНИЯ, ДИСКИ LUKS2 И БЕЗОПАСНОЕ ВЫКЛЮЧЕНИЕ"
    ui_box_row "${C_GRN}gateway unlock${C_RES}                   — Быстрая разблокировка LUKS2-накопителя после ребута + старт Homelab"
    ui_box_row "${C_YEL}gateway lock${C_RES} (или ${C_YEL}eject${C_RES})         — Безопасная остановка медиа-сервисов, sync, umount и закрытие LUKS2"
    ui_box_row "${C_CYN}gateway disk${C_RES}                     — Интерактивный менеджер внешних дисков (LUKS2 / ext4 / btrfs / f2fs)"
    ui_box_row "${C_CYN}gateway safe-reboot${C_RES}              — Корректная перезагрузка с остановкой БД/торрентов, sync и закрытием LUKS"
    ui_box_row "${C_CYN}gateway safe-poweroff${C_RES}            — Безопасное отключение питания сервера с полной парковкой хранилища"
    ui_box_sep "🌐 БЫСТРОЕ УПРАВЛЕНИЕ ПРОКСИ И ДОМЕНАМИ НА ЛЕТУ"
    ui_box_row "${C_CYN}gateway proxy add <url|key|warp>${C_RES} — Добавить подписку (Слот 1), ключ URI (Слот 2) или включить WARP"
    ui_box_row "${C_CYN}gateway domain direct <url|dom>${C_RES}  — Направить сайт/домен всегда НАПРЯМУЮ (в обход туннеля)"
    ui_box_row "${C_CYN}gateway domain proxy <url|dom>${C_RES}   — Направить сайт/домен принудительно В ПРОКСИ (через туннель)"
    ui_box_sep "🏠 МОДУЛИ HOMELAB И ЕДИНЫЙ БЭКАП"
    ui_box_row "${C_CYN}gateway homelab${C_RES}                  — Открыть интерактивное меню управления домашним сервером (Пункт 13)"
    ui_box_row "${C_CYN}gateway homelab install <1-9>${C_RES}    — Установить модуль (caddy|samba|vaultwarden|forgejo|code|navidrome|jellyfin|ytdlp|torrent)"
    ui_box_row "${C_CYN}gateway homelab restart <1-9>${C_RES}    — Перезапустить выбранный модуль Homelab"
    ui_box_row "${C_CYN}gateway backup [create|full|restore|telegram]${C_RES} — Управление резервными копиями и отправка в Telegram"
    ui_box_bottom
    return 0
}

# ==============================================================================
# Интерактивное подменю Homelab & Media Stack (Пункт 13 главного меню)
# ==============================================================================
