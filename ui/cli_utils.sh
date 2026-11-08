resolve_homelab_module_id() {
    RAW_M=$(printf "%s" "${1:-}" | tr 'A-Z' 'a-z' | tr -d ' \t\r\n')
    case "$RAW_M" in
        1|caddy)                          printf "caddy" ;;
        2|samba|smb)                      printf "samba" ;;
        3|vaultwarden|vw|bw)              printf "vaultwarden" ;;
        4|forgejo|git)                    printf "forgejo" ;;
        5|code|vscode|code-server)        printf "code" ;;
        6|ytdlp|yt|metube|downloads)     printf "ytdlp" ;;
        7|torrent|transmission|tr|qbittorrent) printf "torrent" ;;
        *)                                return 1 ;;
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
        ytdlp|metube|downloads)
            tail -n "$LINES_Q" /var/log/metube.log /var/log/ytdlp-webui.log 2>/dev/null || echo "  (лог MeTube пуст)"
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
        torrent|transmission|tr)
            tail -n "$LINES_Q" /var/log/transmission/transmission.log /var/log/qbittorrent-nox.log 2>/dev/null || echo "  (лог Transmission пуст)"
            ;;
        autoupdate|cron)
            tail -n "$LINES_Q" "$AUTOUPDATE_LOG" 2>/dev/null || echo "  (лог ${AUTOUPDATE_LOG} пуст)"
            ;;
        *)
            echo "  ${C_YEL}[▲] Неизвестная служба: ${SVC_Q}${C_RES}"
            echo "  Доступные: sing-box, adguard, caddy, vaultwarden, metube, code, samba, forgejo, transmission, autoupdate"
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
            save_gateway_env
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

# Генерация подробного шаблона файла автоматических ответов (Answers Template)
generate_answers_template() {
    OUT_F="${1:-}"
    SRC_EXAMPLE="${GATEWAY_DIR}/gateway.answers.example"

    emit_content() {
        if [ -f "$SRC_EXAMPLE" ]; then
            cat "$SRC_EXAMPLE"
        else
            cat << 'ANS_EOF'
# ==============================================================================
# 🚀 Universal Sidecar Gateway & Homelab: Файл автоматических ответов (Answers)
# ==============================================================================
# Запуск установки без единого вопроса:
#   gw install --answers gateway.answers
# ==============================================================================

# 1. Сеть и подключение к интернету
SUB_URL="warp"
WARP_LICENSE=""
TARGET_LAN_IP="auto"
GW_IP="auto"

# 2. Учетные данные администратора (Единый мастер-логин)
ADMIN_USER="admin"
ADMIN_PASS="ChangeMe123!"
ENABLE_AUTOUPDATE="no"

# 3. Модули домашнего сервера (Homelab & Media Stack)
# Доступно: 1/caddy, 2/samba, 3/vaultwarden, 4/forgejo, 5/code, 6/metube, 7/torrent, 'all', 'none'
HOMELAB_MODULES="1 2 3 6 7"

# 4. Внешний накопитель и шифрование (USB / SATA / NVMe) [Опционально]
STORAGE_DISK="none"
STORAGE_ACTION="mount"
STORAGE_FS="ext4"
STORAGE_LUKS="no"
STORAGE_LUKS_PASS=""

# 5. SSL / TLS Сертификат: Бесплатный Let's Encrypt Wildcard [Опционально]
SSL_TYPE="local"
DUCKDNS_SUBDOMAIN=""
DUCKDNS_TOKEN=""
ANS_EOF
        fi
    }

    if [ -n "$OUT_F" ]; then
        mkdir -p "$(dirname "$OUT_F")" 2>/dev/null || true
        emit_content > "$OUT_F"
        chmod 600 "$OUT_F" 2>/dev/null || true
        ui_ok_msg "Шаблон файла ответов сохранен в: ${OUT_F}"
        echo " Отредактируйте параметры и запустите установку:"
        echo "   ${C_CYN}gw install --answers ${OUT_F}${C_RES}"
    else
        emit_content
    fi
    return 0
}

# Валидация и проверка корректности заполнения файла ответов
verify_answers_file() {
    IN_F="${1:-}"
    if [ -z "$IN_F" ]; then
        for cand in "${GATEWAY_DIR}/gateway.answers" "./gateway.answers" "/opt/gateway/gateway.answers" "/etc/gateway/gateway.answers"; do
            [ -f "$cand" ] && { IN_F="$cand"; break; }
        done
    fi
    if [ -z "$IN_F" ] || [ ! -f "$IN_F" ]; then
        ui_warn_box "Файл ответов не найден: ${IN_F:-<не указан>}" \
                    "Сгенерируйте шаблон командой: gw answers template gateway.answers"
        return 1
    fi

    ui_banner "ANSWERS VERIFICATION // ПРОВЕРКА ФАЙЛА ОТВЕТОВ"
    echo "Проверяемый файл: ${C_CYN}${IN_F}${C_RES}"
    ui_box_sep

    # 1. Проверка синтаксиса sh
    if ! sh -n "$IN_F" 2>/dev/null; then
        ui_warn_box "Ошибка синтаксиса в файле ответов ${IN_F}!" \
                    "Исправьте кавычки или незакрытые скобки."
        return 1
    fi
    echo "${C_GRN}[✔] Синтаксис shell: КОРРЕКТЕН${C_RES}"

    # 2. Изолированная безопасная загрузка переменных
    (
        parse_env_file_safely "$IN_F"

        # Сеть
        printf "• Сеть:             LAN IP: %s │ GW IP: %s │ Подписка: %s\n" "${TARGET_LAN_IP:-auto}" "${GW_IP:-auto}" "${SUB_URL:-warp}"
        # Пользователь
        if [ -n "${ADMIN_PASS:-}" ]; then
            printf "• Администратор:    Логин: %s │ Мастер-пароль: [ЗАДАН (длина: %d)]\n" "${ADMIN_USER:-admin}" "${#ADMIN_PASS}"
        else
            printf "• Администратор:    Логин: %s │ ${C_YEL}Мастер-пароль: [ПУСТО -> сгенерируется случайно]${C_RES}\n" "${ADMIN_USER:-admin}"
        fi
        # Homelab
        printf "• Модули Homelab:   %s\n" "${HOMELAB_MODULES:-none}"
        # Storage
        printf "• Хранилище:        Диск: %s │ Действие: %s │ ФС: %s │ LUKS2: %s\n" "${STORAGE_DISK:-none}" "${STORAGE_ACTION:-mount}" "${STORAGE_FS:-ext4}" "${STORAGE_LUKS:-no}"
        # SSL
        if [ "${SSL_TYPE:-local}" = "duckdns" ]; then
            printf "• SSL / Домен:      DuckDNS (*.%s.duckdns.org) │ Токен: [ЗАДАН]\n" "${DUCKDNS_SUBDOMAIN:-не указан}"
        else
            printf "• SSL / Домен:      Локальный CA (*.lan)\n"
        fi
    )
    ui_box_sep
    ui_ok_msg "Файл ответов готов к запуску через: gw install --answers ${IN_F}"
    return 0
}

# Полная красиво оформленная в ASCII-рамках справка по всем CLI-командам `gateway help`
print_gateway_cli_help() {
    ui_banner "GATEWAY CLI // СПРАВОЧНИК КОМАНД АДМИНИСТРАТОРА (v2026.11)"
    ui_box_top "🚀 ОСНОВНЫЕ КОМАНДЫ УПРАВЛЕНИЯ ШЛЮЗОМ И ДАШБОРДОМ"
    ui_box_row "${C_CYN}gw${C_RES} (или ${C_CYN}gateway${C_RES})             — Главное интерактивное TUI-меню с телеметрией"
    ui_box_row "${C_CYN}gw motd${C_RES}                     — Быстрый системный баннер (ОЗУ, диск, сеть, службы)"
    ui_box_row "${C_CYN}gw status${C_RES} (или ${C_CYN}gw test${C_RES})        — Полный рентген и матрица здоровья (Self-Test 2.0 + Ping Matrix)"
    ui_box_row "${C_CYN}gw doctor${C_RES} (или ${C_CYN}gw fix${C_RES})         — Умная авто-починка одной командой (модули, DNS, nftables, БД, диск)"
    ui_box_row "${C_CYN}gw passwd [новый_пароль]${C_RES}   — Ротация единого пароля (Sing-Box, AdGuard, Samba, Vaultwarden)"
    ui_box_row "${C_CYN}gw restart${C_RES}                  — Быстрая пересборка конфига, сброс conntrack и перезапуск шлюза"
    ui_box_row "${C_CYN}gw update${C_RES} (или ${C_CYN}check${C_RES})        — Полное обновление: скрипты Git + ядра Sing-Box/AGH + Homelab"
    ui_box_row "${C_CYN}gw links${C_RES} (или ${C_CYN}gw urls${C_RES})         — Карточка всех веб-адресов https://*.lan, сертификата и шары Samba"
    ui_box_row "${C_CYN}gw logs [служба]${C_RES}            — Живые логи (sing-box|adguard|caddy|vaultwarden|metube|samba|...)"
    ui_box_sep "🤖 АВТОМАТИЧЕСКАЯ УСТАНОВКА И ФАЙЛЫ ОТВЕТОВ (ZERO-TOUCH)"
    ui_box_row "${C_CYN}gw install --answers <файл>${C_RES} — Полная тихая установка шлюза и сервисов без единого вопроса"
    ui_box_row "${C_CYN}gw answers template [файл]${C_RES}  — Сгенерировать подробный шаблон файла ответов (Answers File)"
    ui_box_row "${C_CYN}gw answers verify [файл]${C_RES}    — Проверить корректность заполнения файла ответов перед установкой"
    ui_box_sep "🔐 ЗАЩИТА ПИТАНИЯ, ДИСКИ LUKS2 И БЕЗОПАСНОЕ ВЫКЛЮЧЕНИЕ"
    ui_box_row "${C_GRN}gw unlock${C_RES}                   — Быстрая разблокировка LUKS2-накопителя после ребута + старт Homelab"
    ui_box_row "${C_YEL}gw lock${C_RES} (или ${C_YEL}gw eject${C_RES})         — Безопасная остановка медиа-сервисов, sync, umount и закрытие LUKS2"
    ui_box_row "${C_CYN}gw disk${C_RES}                     — Интерактивный менеджер внешних дисков (LUKS2 / ext4 / btrfs / f2fs)"
    ui_box_row "${C_CYN}gw safe-reboot${C_RES}              — Корректная перезагрузка с остановкой БД/торрентов, sync и закрытием LUKS"
    ui_box_row "${C_CYN}gw safe-poweroff${C_RES}            — Безопасное отключение питания сервера с полной парковкой хранилища"
    ui_box_sep "🌐 БЫСТРОЕ УПРАВЛЕНИЕ ПРОКСИ И ДОМЕНАМИ НА ЛЕТУ"
    ui_box_row "${C_CYN}gw proxy add <url|key|warp>${C_RES} — Добавить подписку (Слот 1), ключ URI (Слот 2) или включить WARP"
    ui_box_row "${C_CYN}gw domain direct <url|dom>${C_RES}  — Направить сайт/домен всегда НАПРЯМУЮ (в обход туннеля)"
    ui_box_row "${C_CYN}gw domain proxy <url|dom>${C_RES}   — Направить сайт/домен принудительно В ПРОКСИ (через туннель)"
    ui_box_sep "📦 УПРАВЛЕНИЕ КОНТЕЙНЕРАМИ LXC И СНАПШОТАМИ"
    ui_box_row "${C_CYN}gw lxc${C_RES} (или ${C_CYN}gw lxc list${C_RES})    — Таблица контейнеров (статус, IP, память, автозапуск, снапшоты)"
    ui_box_row "${C_CYN}gw lxc create${C_RES}               — Интерактивный мастер создания контейнера (Alpine, Debian, Ubuntu, Arch...)"
    ui_box_row "${C_CYN}gw lxc start|stop|restart <имя>${C_RES} — Управление состоянием контейнера"
    ui_box_row "${C_CYN}gw lxc attach <имя>${C_RES}         — Открыть сессию терминала root внутри контейнера (lxc-attach)"
    ui_box_row "${C_CYN}gw lxc snap <имя> [create|list|restore|delete]${C_RES} — Управление мгновенными снимками (снапшотами)"
    ui_box_row "${C_CYN}gw lxc autostart <имя> [on|off]${C_RES} — Настройка автозапуска контейнера при включении сервера"
    ui_box_row "${C_CYN}gw lxc fix-net <имя>${C_RES}         — Автоисправление сети контейнера (DHCP/resolv.conf)"
    ui_box_row "${C_CYN}gw lxc menu${C_RES}                 — Интерактивное TUI-меню LXC виртуализации"
    ui_box_sep "🏠 МОДУЛИ HOMELAB И ЕДИНЫЙ БЭКАП"
    ui_box_row "${C_CYN}gw homelab${C_RES}                  — Открыть интерактивное меню управления домашним сервером (Пункт 13)"
    ui_box_row "${C_CYN}gw homelab install <1-7>${C_RES}    — Установить модуль (caddy|samba|vaultwarden|forgejo|code|metube|torrent)"
    ui_box_row "${C_CYN}gw homelab restart <1-7>${C_RES}    — Перезапустить выбранный модуль Homelab"
    ui_box_row "${C_CYN}gw backup [create|full|restore|telegram]${C_RES} — Управление резервными копиями и отправка в Telegram"
    ui_box_bottom
    return 0
}

# ==============================================================================
# Интерактивное подменю Homelab & Media Stack (Пункт 13 главного меню)
# ==============================================================================
