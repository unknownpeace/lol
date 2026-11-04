show_homelab_menu() {
    init_homelab_registry
    load_gateway_env
    while true; do
        clear
        ui_banner "HOMELAB & MEDIA STACK // МОДУЛЬНЫЙ ДОМАШНИЙ СЕРВЕР ALPINE"
        print_homelab_services_table
        ui_box_top "🎛️ ПАНЕЛЬ УПРАВЛЕНИЯ ДОМАШНИМ СЕРВЕРОМ [0-12]"
        ui_box_row "${C_CYN}1)${C_RES}  🔗 Карточка всех веб-ссылок (*.lan), сетевых папок и диагностика (Self-Test)"
        ui_box_row "${C_CYN}2)${C_RES}  ➕ Установить дополнительные модули Homelab (по номерам 1–9)"
        ui_box_row "${C_CYN}3)${C_RES}  ➖ Отключить / остановить модуль по номеру [1–9] (с сохранением данных)"
        ui_box_row "${C_CYN}4)${C_RES}  🔄 Обновить модули Homelab (по номеру [1–9] или 'all' для всех)"
        ui_box_row "${C_CYN}5)${C_RES}  ⚙️ Управление службами: Старт / Стоп / Перезапуск (по номеру [1–9])"
        ui_box_row "${C_CYN}6)${C_RES}  📜 Просмотр живых логов сервисов Homelab"
        ui_box_row "${C_CYN}7)${C_RES}  ${C_GRN}💽 Внешние накопители (USB/SATA/NVMe), LUKS2, ФС (ext4/btrfs/f2fs) и перенос данных${C_RES}"
        ui_box_row "${C_CYN}8)${C_RES}  📁 Настройка сетевого диска Samba и обнаружения (Windows 11 24H2+ / Linux)"
        ui_box_row "${C_CYN}9)${C_RES}  🔒 Управление SSL/TLS: Валидный Let's Encrypt (DuckDNS) vs Локальный PKI (*.lan)"
        ui_box_row "${C_CYN}10)${C_RES} 📦 Резервное копирование и восстановление (Шлюз + БД SQLite + Telegram)"
        ui_box_row "${C_CYN}11)${C_RES} 🎬🎵 Архитектура медиатеки: режим работы Jellyfin и Navidrome"
        ui_box_row "${C_CYN}12)${C_RES} ${C_YEL}🔓 Быстро разблокировать внешний диск LUKS2 (gateway unlock)${C_RES}"
        ui_box_row "${C_CYN}0)${C_RES}  Назад в главное меню шлюза"
        ui_box_bottom
        printf "Выберите действие [0-12]: "
        read -r HL_ACT < /dev/tty || true

        case "$HL_ACT" in
            ""|0)
                break
                ;;
            1)
                echo ""
                print_quick_access_card
                run_homelab_self_test
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            2)
                prompt_homelab_modules_wizard
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            3)
                printf "Введите номер [1-9] или имя модуля для отключения: "
                read -r RM_IN < /dev/tty || true
                RM_MOD=$(resolve_homelab_module_id "$RM_IN" || true)
                if [ -n "$RM_MOD" ]; then
                    homelab_module_dispatch "$RM_MOD" "remove" || true
                else
                    ui_warn_box "Модуль '${RM_IN}' не распознан." "Введите число от 1 до 9 или имя модуля (например: jellyfin)."
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            4)
                printf "Введите номер модуля [1-9] для обновления (или Enter / 'all' — обновить все активные): "
                read -r UP_IN < /dev/tty || true
                UP_IN=$(printf "%s" "$UP_IN" | tr -d ' \t\r\n')
                if [ -z "$UP_IN" ] || [ "$UP_IN" = "all" ] || [ "$UP_IN" = "ALL" ]; then
                    while IFS='|' read -r M_ID M_EN _REST; do
                        case "$M_ID" in ''|\#*) continue ;; esac
                        [ "$M_EN" = "yes" ] && homelab_module_dispatch "$M_ID" "update"
                    done < "$HOMELAB_STATE"
                else
                    UP_MOD=$(resolve_homelab_module_id "$UP_IN" || true)
                    if [ -n "$UP_MOD" ]; then
                        homelab_module_dispatch "$UP_MOD" "update" || true
                    else
                        ui_warn_box "Модуль '${UP_IN}' не распознан." "Введите число от 1 до 9 или 'all'."
                    fi
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            5)
                printf "Введите номер [1-9] или имя модуля: "
                read -r CTL_IN < /dev/tty || true
                CTL_MOD=$(resolve_homelab_module_id "$CTL_IN" || true)
                if [ -n "$CTL_MOD" ]; then
                    echo "Выберите действие: 1) Перезапустить (restart)  2) Запустить (start)  3) Остановить (stop)"
                    printf "Выбор [1-3, Enter = 1]: "
                    read -r CTL_NUM < /dev/tty || true
                    case "${CTL_NUM:-1}" in
                        1|restart) CTL_OP="restart" ;;
                        2|start)   CTL_OP="start" ;;
                        3|stop)    CTL_OP="stop" ;;
                        *)         CTL_OP="restart" ;;
                    esac
                    homelab_module_dispatch "$CTL_MOD" "$CTL_OP" || true
                else
                    ui_warn_box "Модуль '${CTL_IN}' не распознан." "Введите число от 1 до 9."
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            6)
                echo "Доступные журналы: 1) caddy  2) vaultwarden  3) ytdlp  4) code-server  5) samba  6) forgejo  7) jellyfin  8) navidrome  9) qbittorrent"
                printf "Выберите журнал [1-9]: "
                read -r LOG_SEL < /dev/tty || true
                case "$LOG_SEL" in
                    1) show_service_logs_cli "caddy" ;;
                    2) show_service_logs_cli "vaultwarden" ;;
                    3) show_service_logs_cli "ytdlp" ;;
                    4) show_service_logs_cli "code" ;;
                    5) show_service_logs_cli "samba" ;;
                    6) show_service_logs_cli "forgejo" ;;
                    7) show_service_logs_cli "jellyfin" ;;
                    8) show_service_logs_cli "navidrome" ;;
                    9) show_service_logs_cli "torrent" ;;
                esac
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            7)
                manage_external_disks_menu || true
                ;;
            8)
                echo ""
                ui_box_top "📁 НАСТРОЙКА SAMBA (SMB3) И СЕТЕВОГО ОБНАРУЖЕНИЯ (WSDD + AVAHI)"
                ui_box_row "Текущий пользователь Samba: ${C_BLD}${SMB_USER:-homelab}${C_RES}"
                ui_box_row "1) Установить / Перенастроить Samba и сменить логин/пароль шары"
                ui_box_row "2) Проверить и принудительно синхронизировать текущий пароль Samba в passdb.tdb"
                ui_box_row "3) Перезапустить службы обнаружения Windows 11 (wsdd) и Linux (avahi)"
                ui_box_row "0) Назад"
                ui_box_bottom
                printf "Выбор [0-3]: "
                read -r SMB_OP < /dev/tty || true
                case "$SMB_OP" in
                    1) install_module_samba "interactive" || true ;;
                    2)
                        load_gateway_env
                        if apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS"; then
                            ui_ok_msg "Пароль Samba для пользователя '${SMB_USER}' успешно проверен и синхронизирован в passdb.tdb!"
                        fi
                        ;;
                    3) setup_wsdd_and_avahi; ui_ok_msg "Службы wsdd и avahi-daemon перезапущены." ;;
                esac
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            9)
                prompt_ssl_management_menu
                ;;
            10)
                echo ""
                ui_box_top "📦 ЕДИНАЯ СИСТЕМА РЕЗЕРВНОГО КОПИРОВАНИЯ (ШЛЮЗ + HOMELAB + SQLITE)"
                ui_box_row "1) Создать бэкап конфигураций, БД SQLite и сертификатов CA (без медиафайлов)"
                ui_box_row "2) Создать ПОЛНЫЙ бэкап (включая медиафайлы в ${STORAGE_ROOT})"
                ui_box_row "3) Восстановить систему из архива (${BACKUP_ARCHIVE})"
                ui_box_row "4) Отправить архив бэкапа в Telegram"
                ui_box_row "0) Назад"
                ui_box_bottom
                printf "Выбор [0-4]: "
                read -r BK_OP < /dev/tty || true
                case "$BK_OP" in
                    1)
                        create_unified_backup "no"
                        is_telegram_configured && send_telegram_backup "$BACKUP_ARCHIVE" || true
                        ;;
                    2)
                        create_unified_backup "yes"
                        ;;
                    3)
                        restore_unified_backup || true
                        ;;
                    4)
                        [ -f "$BACKUP_ARCHIVE" ] || create_unified_backup "no"
                        send_telegram_backup "$BACKUP_ARCHIVE" || true
                        ;;
                esac
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            11)
                show_media_architecture_advisor || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            12)
                unlock_external_storage_cli || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
        esac
    done
    return 0
}

# ==============================================================================
# Главное интерактивное меню управления (Шлюз + Пункт 13 Homelab + Доктор/LUKS2)
# ==============================================================================
show_menu() {
    set +e
    detect_os
    check_and_recover_power_loss_state
    init_user_lists
    init_homelab_registry
    refresh_remote_versions "no"
    while true; do
        clear
        ui_banner "UNIVERSAL SIDECAR GATEWAY & HOMELAB // ALPINE LINUX EDITION"
        print_gateway_header
        ui_box_top "🎛️ ГЛАВНОЕ МЕНЮ УПРАВЛЕНИЯ СЕРВЕРОМ [0-15 / u / d]"
        ui_box_row "${C_CYN}1)${C_RES}  📊 Статус служб, матрица пинга и рентген сайтов (Self-Test 2.0)"
        ui_box_row "${C_CYN}2)${C_RES}  🌐 Управление прокси: Подписки / Ключи / WARP + ${C_GRN}⚡ SSH-пульт нод${C_RES}"
        ui_box_row "${C_CYN}3)${C_RES}  🔄 Обновить ядра Sing-Box Extended, AdGuard Home и Zashboard"
        ui_box_row "${C_CYN}4)${C_RES}  ♻️  Перезапустить службы + пересобрать конфиг и сбросить conntrack"
        ui_box_row "${C_CYN}5)${C_RES}  📜 Посмотреть живые логи Sing-Box и служб сервера"
        ui_box_row "${C_CYN}6)${C_RES}  🛠️  Полная перенастройка сервера (Мастер установки)"
        ui_box_row "${C_CYN}7)${C_RES}  🧭 Свои домены (В прокси / Напрямую) + ${C_GRN}🕵️ Детектор сайта${C_RES}"
        ui_box_row "${C_CYN}8)${C_RES}  📱 Маршрутизация устройств по IP + ${C_GRN}🔍 Авто-поиск в LAN${C_RES}"
        ui_box_row "${C_CYN}9)${C_RES}  🔐 Сервисный режим, смена пароля и ${C_GRN}☁️ Единый бэкап в Telegram${C_RES}"
        ui_box_row "${C_CYN}10)${C_RES} ⏰ Автообновление (04:00), Авто-Доктор (Watchdog) и Telegram"
        ui_box_row "${C_CYN}11)${C_RES} 🛡️  Аппаратный Kill-Switch (защита от утечек при падении Sing-Box)"
        ui_box_row "${C_CYN}12)${C_RES} 🖧  Сетевые настройки: IP сервера / роутера + Умный DHCP Sidecar"
        ui_box_row "${C_CYN}13)${C_RES} ${C_GRN}🏠 Управление домашним сервером (Homelab & Media Stack + Диски LUKS2)${C_RES}"
        ui_box_row "${C_CYN}14)${C_RES} ${C_YEL}🩺 Авто-Доктор одной кнопкой (gateway doctor — починка сети, БД и диска)${C_RES}"
        ui_box_row "${C_CYN}15)${C_RES} ${C_CYN}⚡ Безопасное выключение / перезагрузка сервера или разблокировка LUKS2${C_RES}"
        ui_box_row "${C_CYN}u)${C_RES}  🔗 Показать все веб-ссылки (https://*.lan), сетевые папки и доступы"
        ui_box_row "${C_CYN}0)${C_RES}  Выход"
        ui_box_bottom
        printf "Выберите действие [0-15 / u]: "
        read -r CHOICE < /dev/tty || true

        case "$CHOICE" in
            u|U)
                echo ""
                print_quick_access_card
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty || true
                ;;
            14|d|D)
                echo ""
                run_gateway_doctor
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty || true
                ;;
            15)
                echo ""
                ui_box_top "⚡ УПРАВЛЕНИЕ ПИТАНИЕМ И КРИПТОКОНТЕЙНЕРОМ LUKS2"
                ui_box_row "1) 🔓 Разблокировать и смонтировать внешний диск LUKS2 (gateway unlock)"
                ui_box_row "2) ⏏️ Безопасно извлечь и заблокировать внешний диск LUKS2 (gateway eject)"
                ui_box_row "3) 🔄 Безопасная перезагрузка сервера с парковкой БД и LUKS2 (gateway safe-reboot)"
                ui_box_row "4) 🛑 Безопасное выключение сервера с парковкой БД и LUKS2 (gateway safe-poweroff)"
                ui_box_row "0) Отмена"
                ui_box_bottom
                printf "Выбор [0-4]: "
                read -r PWR_CH < /dev/tty || true
                case "$PWR_CH" in
                    1) unlock_external_storage_cli || true; printf "\nНажмите Enter..." ; read -r _ < /dev/tty || true ;;
                    2) unmount_external_storage_safe || true; printf "\nНажмите Enter..." ; read -r _ < /dev/tty || true ;;
                    3) safe_power_action "reboot" ;;
                    4) safe_power_action "poweroff" ;;
                esac
                ;;
            1)
                echo ""
                run_self_test
                ui_box_top "🔌 АКТИВНЫЕ СЕТЕВЫЕ ПОРТЫ СЕРВЕРА"
                ss -tulpn 2>/dev/null | grep -E ':(53|80|443|445|1053|3000|3001|4533|7890|8080|8081|8096|8222|8443|9090)\b' || true
                ui_box_bottom
                printf "Нажмите Enter для возврата в меню (или введите 'd' для рентгена любого сайта): "
                read -r ST_ACT < /dev/tty || true
                if [ "$ST_ACT" = "d" ] || [ "$ST_ACT" = "D" ]; then
                    inspect_domain_route || true
                    printf "\nНажмите Enter для возврата в меню..."
                    read -r _ < /dev/tty || true
                fi
                ;;
            2)
                while true; do
                    clear
                    ui_banner "PROXY MANAGER // 3 НЕЗАВИСИМЫХ СЛОТА И ПУЛЬТ НОД"
                    ui_box_top "🌐 УПРАВЛЕНИЕ ИСТОЧНИКАМИ ПРОКСИ (3 НЕЗАВИСИМЫХ СЛОТА)"
                    print_proxy_slots_report
                    ui_box_sep "ДЕЙСТВИЯ [0-12]"
                    ui_box_row "1)  Указать / заменить основную подписку (http://...) [Слот 1]"
                    ui_box_row "2)  Добавить дополнительную подписку в пул (Мульти-Саб) [Слот 1]"
                    ui_box_row "3)  Отключить и очистить все подписки по ссылке [Слот 1]"
                    ui_box_row "4)  Посмотреть пронумерованный список личных ключей [Слот 2]"
                    ui_box_row "5)  Добавить личный ключ (vless/hy2/tuic/ss/wg/anytls...) [Слот 2]"
                    ui_box_row "6)  Удалить один конкретный личный ключ по номеру [Слот 2]"
                    ui_box_row "7)  Очистить все личные ключи в my_nodes.yaml [Слот 2]"
                    ui_box_row "8)  Включить / перевыпустить гибридный WARP 2.0 + MASQUE H2 [Слот 3]"
                    ui_box_row "9)  Отключить и полностью очистить ноды Amnezia WARP 2.0 [Слот 3]"
                    ui_box_row "10) Режим «Белые списки» (показать/скрыть РФ-каскады в подписке) [Слот 1]"
                    ui_box_row "11) ${C_GRN}⚡ Мини-пульт управления нодами и группами прямо из SSH${C_RES}"
                    ui_box_row "12) ${C_GRN}🩺 Поштучно проверить и оживить ноды с молнией (⚡)${C_RES}"
                    ui_box_row "0)  Назад в главное меню"
                    ui_box_bottom
                    printf "Выбор [0-12]: "
                    read -r SUB_ACT < /dev/tty || true
                    case "$SUB_ACT" in
                        ""|0) break ;;
                        1)
                            printf "Введите ссылку на подписку (или несколько через пробел): "
                            read -r NEW_SUB < /dev/tty || true
                            NEW_SUB=$(clean_clipboard_line "$NEW_SUB")
                            if [ -n "$NEW_SUB" ] && [ -f "$SB_CONF" ]; then
                                backup_gateway_state
                                load_gateway_env
                                apply_subscription_input "$NEW_SUB"
                                [ "${USE_INITIAL_WARP:-no}" = "yes" ] && generate_amnezia_warp || true
                                apply_and_verify_singbox "Обновление подписки (Слот 1)" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        2)
                            printf "Введите дополнительную ссылку на подписку (http://...): "
                            read -r EXTRA_SUB < /dev/tty || true
                            EXTRA_SUB=$(clean_clipboard_line "$EXTRA_SUB")
                            case "$EXTRA_SUB" in
                                http://*|https://*)
                                    backup_gateway_state
                                    load_gateway_env
                                    CLEAN_EXTRA=$(sanitize_sub_url_list "$EXTRA_SUB")
                                    SUB_URL="${SUB_URL:+${SUB_URL} }${CLEAN_EXTRA}"
                                    apply_and_verify_singbox "Добавление дополнительной подписки в Слот 1" || true
                                    ;;
                                *) ui_warn_box "Ссылка подписки должна начинаться с http:// или https://" "Для добавления отдельного URI-ключа (vless://) выберите пункт 5." ;;
                            esac
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        3)
                            backup_gateway_state
                            load_gateway_env
                            SUB_URL=""
                            apply_and_verify_singbox "Очистка подписок по ссылке (Слот 1)" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        4)
                            echo ""
                            list_my_nodes
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        5)
                            printf "Вставьте один или несколько ключей (vless://, hy2://, ss://, tuic://, wg://, anytls://): "
                            read -r EXTRA_KEY < /dev/tty || true
                            EXTRA_KEY=$(clean_clipboard_line "$EXTRA_KEY")
                            if [ -n "$EXTRA_KEY" ]; then
                                backup_gateway_state
                                load_gateway_env
                                sed -i '/^proxies:[[:space:]]*\[\]/d' "$CUSTOM_NODES_FILE" 2>/dev/null || true
                                format_uri_keys "$EXTRA_KEY" >> "$CUSTOM_NODES_FILE"
                                apply_and_verify_singbox "Добавление личного ключа в Слот 2 (my_nodes)" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        6)
                            echo ""
                            list_my_nodes
                            if has_my_nodes; then
                                printf "\nВведите номер ключа для удаления [Enter = отмена]: "
                                read -r DEL_NUM < /dev/tty || true
                                DEL_NUM=$(printf "%s" "$DEL_NUM" | tr -d ' \t\r\n')
                                if [ -n "$DEL_NUM" ]; then
                                    backup_gateway_state
                                    load_gateway_env
                                    delete_my_node_by_index "$DEL_NUM" && apply_and_verify_singbox "Удаление ключа #${DEL_NUM}" || true
                                fi
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        7)
                            backup_gateway_state
                            load_gateway_env
                            echo "proxies: []" > "$CUSTOM_NODES_FILE"
                            apply_and_verify_singbox "Очистка всех личных ключей (Слот 2)" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        8)
                            backup_gateway_state
                            load_gateway_env
                            printf "Вставьте ключ лицензии WARP+ (если есть) [Enter = бесплатный WARP]: "
                            read -r W_LIC_IN < /dev/tty || true
                            W_LIC_IN=$(printf "%s" "$W_LIC_IN" | tr -d ' \t\r\n')
                            generate_amnezia_warp "$W_LIC_IN" && apply_and_verify_singbox "Обновление гибридного WARP 2.0 + MASQUE H2" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        9)
                            backup_gateway_state
                            load_gateway_env
                            echo '{"outbounds": []}' > "$WARP_NODES_FILE"
                            WARP_LICENSE=""
                            apply_and_verify_singbox "Отключение Amnezia WARP 2.0 (Слот 3)" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        10)
                            backup_gateway_state
                            load_gateway_env
                            if [ "${ALLOW_RU_NODES:-no}" = "yes" ]; then
                                ALLOW_RU_NODES="no"
                                ACT_MSG="Скрытие нод РФ/Белые списки в подписке"
                            else
                                ALLOW_RU_NODES="yes"
                                ACT_MSG="Показ каскадных нод РФ/Белые списки в подписке"
                            fi
                            save_gateway_env
                            apply_and_verify_singbox "$ACT_MSG" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        11) manage_nodes_cli_menu || true ;;
                        12)
                            diagnose_failed_nodes || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                    esac
                done
                ;;
            3)
                ui_box_top "🔄 АТОМАРНОЕ ОБНОВЛЕНИЕ ЯДЕР И ПАНЕЛИ ZASHBOARD"
                update_cores_only "yes"
                service_ctl sing-box restart
                service_ctl adguardhome restart
                ui_box_bottom
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty || true
                ;;
            4)
                ui_box_top "♻️ ПЕРЕСБОРКА КОНФИГУРАЦИИ И СБРОС СЕССИЙ CONNTRACK"
                backup_gateway_state
                load_gateway_env
                if apply_and_verify_singbox "Актуализация групп и перезапуск служб"; then
                    conntrack -F >/dev/null 2>&1 || true
                    service_ctl adguardhome restart
                    ui_ok_msg "Таблица conntrack очищена, службы успешно перезапущены."
                fi
                ui_box_bottom
                sleep 2
                ;;
            5)
                show_service_logs_cli "sing-box" 45
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty || true
                ;;
            6)
                run_installer
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty || true
                ;;
            7)
                while true; do
                    clear
                    ui_banner "DOMAIN ROUTER // ПОЛЬЗОВАТЕЛЬСКИЕ ДОМЕНЫ И РЕНТГЕН САЙТОВ"
                    ui_box_top "🧭 ПОЛЬЗОВАТЕЛЬСКИЕ ПРАВИЛА ДОМЕНОВ (JSON RULE-SET v3)"
                    ui_box_row "${C_BLD}Домены В ПРОКСИ (${USER_PROXY_FILE} -> группа 🌐 Остальной трафик):${C_RES}"
                    list_entries_numbered "$USER_PROXY_FILE"
                    ui_box_sep "Домены НАПРЯМУЮ (${USER_DIRECT_FILE} -> DIRECT, высший приоритет)"
                    list_entries_numbered "$USER_DIRECT_FILE"
                    ui_box_sep "ДЕЙСТВИЯ С ДОМЕНАМИ [0-6]"
                    ui_box_row "1) Добавить домен(ы) В ПРОКСИ (можно вставлять ссылки https://..., IDN, *.site.com)"
                    ui_box_row "2) Добавить домен(ы) НАПРЯМУЮ (можно вставлять ссылки https://..., IDN, *.site.com)"
                    ui_box_row "3) Удалить один домен из списка В ПРОКСИ по номеру"
                    ui_box_row "4) Удалить один домен из списка НАПРЯМУЮ по номеру"
                    ui_box_row "5) Сбросить оба списка доменов по умолчанию"
                    ui_box_row "6) ${C_GRN}🕵️ Проверить любой сайт / домен (Рентген маршрута + TLS замер)${C_RES}"
                    ui_box_row "0) Назад в главное меню"
                    ui_box_bottom
                    printf "Выбор [0-6]: "
                    read -r DOM_ACT < /dev/tty || true
                    case "$DOM_ACT" in
                        ""|0) break ;;
                        1)
                            printf "Введите домен или ссылку (можно несколько через пробел): "
                            read -r D_IN < /dev/tty || true
                            D_IN=$(clean_clipboard_line "$D_IN")
                            if [ -n "$D_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                ADDED_LIST=""
                                for D_ITEM in $(printf "%s\n" "$D_IN" | tr ' ,' '\n\n'); do
                                    [ -z "$D_ITEM" ] && continue
                                    CLEAN_D=$(sanitize_domain_entry "$D_ITEM" || true)
                                    if [ -n "$CLEAN_D" ]; then
                                        awk -v d="$CLEAN_D" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.localdomain"}' "$USER_DIRECT_FILE" > "${USER_DIRECT_FILE}.tmp.$$" && mv -f "${USER_DIRECT_FILE}.tmp.$$" "$USER_DIRECT_FILE"
                                        grep -qxF "$CLEAN_D" "$USER_PROXY_FILE" 2>/dev/null || echo "$CLEAN_D" >> "$USER_PROXY_FILE"
                                        ADDED_LIST="${ADDED_LIST} ${CLEAN_D}"
                                    else
                                        ui_warn_box "Запись '${D_ITEM}' не является доменом (для IP используйте меню п. 8)." \
                                                    "Пример корректного домена: youtube.com или https://site.org"
                                    fi
                                done
                                [ -n "$ADDED_LIST" ] && apply_and_verify_singbox "Добавление в прокси:${ADDED_LIST}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        2)
                            printf "Введите домен или ссылку (можно несколько через пробел): "
                            read -r D_IN < /dev/tty || true
                            D_IN=$(clean_clipboard_line "$D_IN")
                            if [ -n "$D_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                ADDED_LIST=""
                                for D_ITEM in $(printf "%s\n" "$D_IN" | tr ' ,' '\n\n'); do
                                    [ -z "$D_ITEM" ] && continue
                                    CLEAN_D=$(sanitize_domain_entry "$D_ITEM" || true)
                                    if [ -n "$CLEAN_D" ]; then
                                        awk -v d="$CLEAN_D" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.chatgpt.com"}' "$USER_PROXY_FILE" > "${USER_PROXY_FILE}.tmp.$$" && mv -f "${USER_PROXY_FILE}.tmp.$$" "$USER_PROXY_FILE"
                                        grep -qxF "$CLEAN_D" "$USER_DIRECT_FILE" 2>/dev/null || echo "$CLEAN_D" >> "$USER_DIRECT_FILE"
                                        ADDED_LIST="${ADDED_LIST} ${CLEAN_D}"
                                    else
                                        ui_warn_box "Запись '${D_ITEM}' не является доменом (для IP используйте меню п. 8)." \
                                                    "Пример корректного домена: gosuslugi.ru или https://bank.ru"
                                    fi
                                done
                                [ -n "$ADDED_LIST" ] && apply_and_verify_singbox "Добавление напрямую (DIRECT):${ADDED_LIST}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        3)
                            printf "Введите номер домена из списка В ПРОКСИ для удаления: "
                            read -r DEL_D_IDX < /dev/tty || true
                            DEL_D_IDX=$(printf "%s" "$DEL_D_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_D_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_VAL=$(get_entry_by_index "$USER_PROXY_FILE" "$DEL_D_IDX")
                                delete_entry_by_index "$USER_PROXY_FILE" "$DEL_D_IDX" "+.chatgpt.com" && apply_and_verify_singbox "Удаление ${DEL_VAL}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        4)
                            printf "Введите номер домена из списка НАПРЯМУЮ для удаления: "
                            read -r DEL_D_IDX < /dev/tty || true
                            DEL_D_IDX=$(printf "%s" "$DEL_D_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_D_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_VAL=$(get_entry_by_index "$USER_DIRECT_FILE" "$DEL_D_IDX")
                                delete_entry_by_index "$USER_DIRECT_FILE" "$DEL_D_IDX" "+.localdomain" && apply_and_verify_singbox "Удаление ${DEL_VAL}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        5)
                            backup_gateway_state
                            load_gateway_env
                            printf "+.localdomain\n+.lan\n" > "$USER_DIRECT_FILE"
                            echo "+.chatgpt.com" > "$USER_PROXY_FILE"
                            apply_and_verify_singbox "Сброс пользовательских списков доменов" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        6)
                            inspect_domain_route || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                    esac
                done
                ;;
            8)
                while true; do
                    clear
                    ui_banner "LAN DEVICE ROUTER // МАРШРУТИЗАЦИЯ УСТРОЙСТВ ПО IP"
                    ui_box_top "📱 МАРШРУТИЗАЦИЯ УСТРОЙСТВ ПО IP (АВТО-СКАНЕР LAN)"
                    discover_lan_devices
                    ui_box_sep "Устройства в обходе (всегда DIRECT)"
                    list_entries_numbered "$USER_BYPASS_IPS"
                    ui_box_sep "Устройства в Full-VPN (группа '📺 Устройства (Full-VPN)')"
                    list_entries_numbered "$USER_FORCE_PROXY_IPS"
                    ui_box_sep "ДЕЙСТВИЯ [0-5 / s]"
                    ui_box_row "1) Добавить устройство в ОБХОД (DIRECT) — по номеру из LAN или по IP"
                    ui_box_row "2) Добавить устройство в FULL-VPN — по номеру из LAN или по IP"
                    ui_box_row "3) Удалить один IP из списка ОБХОД (DIRECT) по номеру"
                    ui_box_row "4) Удалить один IP из списка FULL-VPN по номеру"
                    ui_box_row "5) Очистить оба списка IP"
                    ui_box_row "s) ${C_GRN}🔄 Активно просканировать всю подсеть LAN${C_RES}"
                    ui_box_row "0) Назад в главное меню"
                    ui_box_bottom
                    printf "Выбор [0-5 / s]: "
                    read -r BYP_ACT < /dev/tty || true
                    case "$BYP_ACT" in
                        ""|0) break ;;
                        s|S) scan_lan_subnet ;;
                        1)
                            printf "Введите номер устройства из таблицы LAN ИЛИ его IP-адрес (для DIRECT): "
                            read -r RAW_DEV_IN < /dev/tty || true
                            IP_IN=$(resolve_device_ip_input "$RAW_DEV_IN" || true)
                            if [ -n "$IP_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                sed -i "\|^${IP_IN}$|d" "$USER_FORCE_PROXY_IPS" 2>/dev/null || true
                                grep -qxF "$IP_IN" "$USER_BYPASS_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_BYPASS_IPS"
                                apply_and_verify_singbox "Добавление IP ${IP_IN} в DIRECT" && conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            else
                                ui_warn_box "Некорректный IP или номер устройства (${RAW_DEV_IN})." "Нажмите 's' для сканирования сети или введите IP вида 192.168.1.50."
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        2)
                            printf "Введите номер устройства из таблицы LAN ИЛИ его IP-адрес (для Full-VPN): "
                            read -r RAW_DEV_IN < /dev/tty || true
                            IP_IN=$(resolve_device_ip_input "$RAW_DEV_IN" || true)
                            if [ -n "$IP_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                sed -i "\|^${IP_IN}$|d" "$USER_BYPASS_IPS" 2>/dev/null || true
                                grep -qxF "$IP_IN" "$USER_FORCE_PROXY_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_FORCE_PROXY_IPS"
                                apply_and_verify_singbox "Добавление IP ${IP_IN} в Full-VPN" && conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            else
                                ui_warn_box "Некорректный IP или номер устройства (${RAW_DEV_IN})." "Нажмите 's' для сканирования сети или введите IP вида 192.168.1.50."
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        3)
                            printf "Введите номер IP из списка ОБХОД (DIRECT) для удаления: "
                            read -r DEL_I_IDX < /dev/tty || true
                            DEL_I_IDX=$(printf "%s" "$DEL_I_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_I_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_IP=$(get_entry_by_index "$USER_BYPASS_IPS" "$DEL_I_IDX")
                                delete_entry_by_index "$USER_BYPASS_IPS" "$DEL_I_IDX" "" && apply_and_verify_singbox "Удаление IP ${DEL_IP}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        4)
                            printf "Введите номер IP из списка FULL-VPN для удаления: "
                            read -r DEL_I_IDX < /dev/tty || true
                            DEL_I_IDX=$(printf "%s" "$DEL_I_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_I_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_IP=$(get_entry_by_index "$USER_FORCE_PROXY_IPS" "$DEL_I_IDX")
                                delete_entry_by_index "$USER_FORCE_PROXY_IPS" "$DEL_I_IDX" "" && apply_and_verify_singbox "Удаление IP ${DEL_IP}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        5)
                            backup_gateway_state
                            load_gateway_env
                            : > "$USER_BYPASS_IPS"
                            : > "$USER_FORCE_PROXY_IPS"
                            apply_and_verify_singbox "Очистка списков маршрутизации по IP" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                    esac
                done
                ;;
            9)
                while true; do
                    load_gateway_env
                    clear
                    ui_banner "SECURITY & BACKUP // ПАРОЛЬ, СЕРВИСНЫЙ РЕЖИМ И БЭКАП"
                    ui_box_top "🔐 СЕРВИСНЫЙ РЕЖИМ, ЕДИНЫЙ ПАРОЛЬ И ОБЛАЧНЫЙ БЭКАП"
                    ui_box_row "Облако Telegram: $(is_telegram_configured && echo "${C_GRN}● ПОДКЛЮЧЕНО (Chat ID: ${TG_CHAT_ID})${C_RES}" || echo "${C_DIM}○ НЕ НАСТРОЕНО${C_RES}")"
                    ui_box_sep "ДЕЙСТВИЯ [0-7]"
                    ui_box_row "1) Пауза: переключить весь трафик в DIRECT (без остановки DNS)"
                    ui_box_row "2) Возобновить работу по правилам (mode: rule)"
                    ui_box_row "3) Создать единый бэкап (Шлюз + Homelab БД + CA) + отправка в TG"
                    ui_box_row "4) Восстановить систему из бэкапа (${BACKUP_ARCHIVE})"
                    ui_box_row "5) Сменить единый пароль (Sing-Box + AdGuard Home + Samba + Homelab)"
                    ui_box_row "6) ${C_GRN}☁️ Отправить текущий файл бэкапа себе в Telegram${C_RES}"
                    ui_box_row "7) ⚙️ Настроить Telegram-бота (Токен и Chat ID)"
                    ui_box_row "0) Назад в главное меню"
                    ui_box_bottom
                    printf "Выбор [0-7]: "
                    read -r SRV_ACT < /dev/tty || true
                    case "$SRV_ACT" in
                        ""|0) break ;;
                        1)
                            curl -fsS -X PATCH -H "Authorization: Bearer ${ADMIN_PASS}" -H "Content-Type: application/json" \
                                -d '{"mode":"direct"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                            ui_ok_msg "Шлюз переведен в режим паузы (DIRECT)."
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        2)
                            curl -fsS -X PATCH -H "Authorization: Bearer ${ADMIN_PASS}" -H "Content-Type: application/json" \
                                -d '{"mode":"rule"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                            ui_ok_msg "Режим маршрутизации по правилам (rule) восстановлен."
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        3)
                            create_unified_backup "no"
                            is_telegram_configured && send_telegram_backup "$BACKUP_ARCHIVE" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        4)
                            restore_unified_backup || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        5)
                            printf "Введите новый единый пароль: "
                            read -r NEW_P_IN < /dev/tty || true
                            NEW_P_IN=$(printf "%s" "$NEW_P_IN" | tr -d '\r\n')
                            [ -n "$NEW_P_IN" ] && change_unified_password "$NEW_P_IN" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        6)
                            [ -f "$BACKUP_ARCHIVE" ] || create_unified_backup "no"
                            send_telegram_backup "$BACKUP_ARCHIVE" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        7)
                            configure_telegram_menu || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                    esac
                done
                ;;
            10)
                while true; do
                    load_gateway_env
                    clear
                    ui_banner "AUTONOMOUS GUARD // АВТООБНОВЛЕНИЕ, WATCHDOG И TELEGRAM"
                    ui_box_top "⏰ АВТООБНОВЛЕНИЕ (04:00), АВТО-ДОКТОР (WATCHDOG) И TELEGRAM"
                    ui_box_row "• Автообновление ядер (04:00): $(is_autoupdate_enabled && echo "${C_GRN}● ВКЛЮЧЕНО${C_RES}" || echo "${C_DIM}○ ВЫКЛЮЧЕНО${C_RES}")"
                    ui_box_row "• Авто-Доктор (Шлюз+Homelab):  $(is_watchdog_enabled && echo "${C_GRN}● ВКЛЮЧЕН (каждые 5 мин)${C_RES}" || echo "${C_DIM}○ ВЫКЛЮЧЕН${C_RES}")"
                    ui_box_row "• Уведомления в Telegram:      $(is_telegram_configured && echo "${C_GRN}● ВКЛЮЧЕНЫ (Chat ID: ${TG_CHAT_ID})${C_RES}" || echo "${C_DIM}○ НЕ НАСТРОЕНЫ${C_RES}")"
                    ui_box_sep "ДЕЙСТВИЯ [0-5]"
                    ui_box_row "1) Включить Автообновление (04:00) + Watchdog"
                    ui_box_row "2) Выключить Автообновление (оставить только Watchdog)"
                    ui_box_row "3) Включить / Выключить Авто-Доктор (Watchdog)"
                    ui_box_row "4) Посмотреть лог последнего автообновления (${AUTOUPDATE_LOG})"
                    ui_box_row "5) ⚙️ Настроить уведомления и облачный бэкап в Telegram"
                    ui_box_row "0) Назад в главное меню"
                    ui_box_bottom
                    printf "Выбор [0-5]: "
                    read -r AU_ACT < /dev/tty || true
                    case "$AU_ACT" in
                        ""|0) break ;;
                        1) enable_autoupdate; enable_watchdog; ui_ok_msg "Автообновление и Watchdog включены."; sleep 1 ;;
                        2) disable_autoupdate; enable_watchdog; ui_ok_msg "Автообновление отключено."; sleep 1 ;;
                        3)
                            if is_watchdog_enabled; then
                                disable_watchdog; ui_info_msg "Watchdog отключен."
                            else
                                enable_watchdog; ui_ok_msg "Watchdog включен."
                            fi
                            sleep 1
                            ;;
                        4)
                            show_service_logs_cli "autoupdate" 50
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        5) configure_telegram_menu || true ;;
                    esac
                done
                ;;
            11)
                while true; do
                    clear
                    ui_banner "HARDWARE KILL-SWITCH // ЗАЩИТА ОТ УТЕЧЕК ТРАФИКА"
                    ui_box_top "🛡️ АППАРАТНЫЙ KILL-SWITCH (NFTABLES НА ИНТЕРФЕЙСЕ $(get_lan_ifname))"
                    ui_box_row "Текущий статус: $(is_killswitch_enabled && echo "${C_GRN}◆ ВКЛЮЧЕН (строгая блокировка трафика мимо singbox-tun)${C_RES}" || echo "${C_CYN}● ВЫКЛЮЧЕН (стандартная защита DNS + DoT + IPv6)${C_RES}")"
                    ui_box_row "Локальная сеть LAN (SSH, Samba, *.lan) всегда доступна и защищена от блокировки."
                    ui_box_sep "ДЕЙСТВИЯ [0-2]"
                    ui_box_row "1) ВКЛЮЧИТЬ строгий Kill-Switch"
                    ui_box_row "2) ВЫКЛЮЧИТЬ строгий Kill-Switch"
                    ui_box_row "0) Назад"
                    ui_box_bottom
                    printf "Выбор [0-2]: "
                    read -r KS_ACT < /dev/tty || true
                    case "$KS_ACT" in
                        ""|0) break ;;
                        1) sync_dns_firewall "yes" "yes"; ui_ok_msg "Kill-Switch ВКЛЮЧЕН."; sleep 1 ;;
                        2) sync_dns_firewall "yes" "no"; ui_ok_msg "Kill-Switch ВЫКЛЮЧЕН."; sleep 1 ;;
                    esac
                done
                ;;
            12)
                while true; do
                    CUR_LAN_NOW=$(get_current_lan_ip)
                    load_gateway_env
                    clear
                    ui_banner "NETWORK & SMART DHCP // СЕТЕВЫЕ НАСТРОЙКИ SIDECAR"
                    ui_box_top "🖧 СЕТЕВЫЕ НАСТРОЙКИ СЕРВЕРА И УМНЫЙ DHCP SIDECAR"
                    ui_box_row "• Текущий IP сервера (${OS_NAME}): ${C_BLD}${CUR_LAN_NOW}${C_RES} ($(get_lan_ifname), /24)"
                    ui_box_row "• Текущий IP основного роутера:   ${C_CYN}${GW_IP}${C_RES}"
                    ui_box_row "• Умный DHCP-сервер на шлюзе:     $(is_dhcp_server_enabled && echo "${C_GRN}● ВКЛЮЧЕН${C_RES}" || echo "${C_DIM}○ ВЫКЛЮЧЕН${C_RES}")"
                    ui_box_sep "ДЕЙСТВИЯ [0-5]"
                    ui_box_row "1) Сменить IP-адрес самого сервера (${OS_NAME})"
                    ui_box_row "2) Сменить IP-адрес основного роутера"
                    ui_box_row "3) Сменить оба адреса сразу"
                    ui_box_row "4) ВКЛЮЧИТЬ Умный DHCP-сервер на шлюзе"
                    ui_box_row "5) ВЫКЛЮЧИТЬ DHCP-сервер на шлюзе"
                    ui_box_row "0) Назад"
                    ui_box_bottom
                    printf "Выбор [0-5]: "
                    read -r NET_ACT < /dev/tty || true
                    case "$NET_ACT" in
                        ""|0) break ;;
                        1)
                            printf "Введите новый IP для сервера [текущий %s]: " "$CUR_LAN_NOW"
                            read -r NEW_L < /dev/tty || true
                            NEW_L=$(printf "%s" "$NEW_L" | tr -d ' \t\r\n')
                            if [ -n "$NEW_L" ] && apply_network_ips "$NEW_L" "$GW_IP"; then
                                [ "$NEW_L" != "$CUR_LAN_NOW" ] && exit 0
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        2)
                            printf "Введите новый IP основного роутера [текущий %s]: " "$GW_IP"
                            read -r NEW_G < /dev/tty || true
                            NEW_G=$(printf "%s" "$NEW_G" | tr -d ' \t\r\n')
                            [ -n "$NEW_G" ] && apply_network_ips "$CUR_LAN_NOW" "$NEW_G" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        3)
                            printf "Введите новый IP для сервера [текущий %s]: " "$CUR_LAN_NOW"
                            read -r NEW_L < /dev/tty || true
                            NEW_L=$(printf "%s" "$NEW_L" | tr -d ' \t\r\n')
                            printf "Введите новый IP основного роутера [текущий %s]: " "$GW_IP"
                            read -r NEW_G < /dev/tty || true
                            NEW_G=$(printf "%s" "$NEW_G" | tr -d ' \t\r\n')
                            if [ -n "$NEW_L" ] && [ -n "$NEW_G" ] && apply_network_ips "$NEW_L" "$NEW_G"; then
                                [ "$NEW_L" != "$CUR_LAN_NOW" ] && exit 0
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty || true
                            ;;
                        4) configure_smart_dhcp "on"; sleep 1 ;;
                        5) configure_smart_dhcp "off"; sleep 1 ;;
                    esac
                done
                ;;
            13)
                show_homelab_menu
                ;;
            0)
                exit 0
                ;;
        esac
    done
}

