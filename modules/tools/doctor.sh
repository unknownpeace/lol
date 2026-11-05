run_gateway_doctor() {
    set +e
    detect_os
    load_gateway_env
    ui_banner "GATEWAY DOCTOR // АВТОМАТИЧЕСКАЯ ДИАГНОСТИКА И ПОЧИНКА"
    ui_box_top "🩺 ПРОТОКОЛ САМОИСЦЕЛЕНИЯ СИСТЕМЫ (DOCTOR 2.0)"

    ui_step_progress 1 6 "Проверка целостности конфигов, PID-блокировок и баз SQLite после сбоя питания..."
    rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
    check_and_recover_power_loss_state
    rm -f "$POWER_LOSS_FLAG" 2>/dev/null || true

    ui_step_progress 2 6 "Подгрузка ядерных модулей (tun, tcp_bbr, nftables, dm_crypt) и настройка sysctl..."
    ensure_alpine_modules
    [ -f /etc/sysctl.d/99-gateway-forward.conf ] && sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf >/dev/null 2>&1 || true

    ui_step_progress 3 6 "Проверка DNS-резолвера (/etc/resolv.conf) и таблиц файрвола nftables..."
    write_resolv_conf "nameserver 127.0.0.1
nameserver ${GW_IP:-192.168.1.1}
nameserver 77.88.8.8"
    sync_user_domain_rulesets
    sync_dns_firewall "yes" "keep" >/dev/null 2>&1 || true

    ui_step_progress 4 6 "Проверка внешнего накопителя (${STORAGE_ROOT}), LUKS2 и прав доступа (${MEDIA_GROUP})..."
    if [ "${EXT_STORAGE_EXPECTED:-no}" = "yes" ] && ! is_external_storage_mounted; then
        if try_auto_unlock_and_mount_storage; then
            ui_ok_msg "Внешний накопитель автоматически разблокирован, проверен fsck и смонтирован!"
        else
            ui_warn_box "Внешний накопитель (${STORAGE_ROOT}) ожидает ручного ввода пароля LUKS2 или подключения кабеля." \
                        "Подключите диск и выполните команду: gateway unlock"
        fi
    fi
    if is_storage_mount_ready; then
        sync_all_homelab_permissions >/dev/null 2>&1 || true
    fi

    ui_step_progress 5 6 "Валидация и перезапуск служб Sing-Box Extended, AdGuard Home и Conntrack..."
    if [ ! -s "$SB_CONF" ] || ! check_singbox_config; then
        generate_singbox_config
    fi
    service_ctl sing-box restart
    sleep 2
    service_ctl adguardhome restart
    conntrack -F >/dev/null 2>&1 || true
    reload_singbox_api

    ui_step_progress 6 6 "Проверка и запуск активных модулей Homelab..."
    if is_module_enabled "caddy"; then
        reload_caddy_safe >/dev/null 2>&1 || true
    fi
    if is_storage_mount_ready; then
        start_storage_dependent_services
    else
        stop_storage_dependent_services
    fi
    check_and_heal_lxc_doctor
    backup_gateway_state
    ui_ok_msg "Авто-починка (gateway doctor) успешно завершена!"
    ui_box_bottom
    run_self_test
    return 0
}

# Фоновая проверка здоровья служб шлюза и активных модулей Homelab (Watchdog Auto-Healer + Mount Guard)
run_watchdog() {
    set +e
    acquire_gateway_lock "watchdog" || return 0
    trap 'release_gateway_lock' EXIT INT TERM HUP
    detect_os
    rotate_gateway_logs
    check_and_recover_power_loss_state
    load_gateway_env

    if [ ! -f "$SB_CONF" ]; then
        release_gateway_lock
        trap - EXIT INT TERM HUP
        return 0
    fi
    ensure_alpine_modules
    RECOVERED_MSG=""

    if ! pgrep sing-box >/dev/null 2>&1 || ! ip link show singbox-tun >/dev/null 2>&1; then
        logger -t gateway-watchdog "Sing-Box or singbox-tun down, restarting service..." 2>/dev/null || true
        if ! check_singbox_config && [ -s "${STATE_BAK_DIR}/config.json" ]; then
            cp -f "${STATE_BAK_DIR}/config.json" "$SB_CONF" 2>/dev/null || true
        fi
        service_ctl sing-box restart
        sleep 2
        RECOVERED_MSG="⚡ [Авто-Доктор] На сервере ($(get_current_lan_ip)) перезапущен туннель Sing-Box."
    fi

    if ! pgrep AdGuardHome >/dev/null 2>&1; then
        logger -t gateway-watchdog "AdGuardHome down, restarting service..." 2>/dev/null || true
        service_ctl adguardhome restart
        RECOVERED_MSG="${RECOVERED_MSG}
⚡ [Авто-Доктор] Перезапущена служба AdGuard Home."
    fi

    # Caddy и Vaultwarden не зависят от внешнего USB-диска и всегда поддерживаются в работе
    for CORE_HL in caddy vaultwarden; do
        if is_module_enabled "$CORE_HL"; then
            C_SVC=$(get_module_field "$CORE_HL" 3)
            if [ -n "$C_SVC" ] && [ -x "/etc/init.d/${C_SVC}" ] && ! rc-service "$C_SVC" status >/dev/null 2>&1; then
                rc-service "$C_SVC" restart >/dev/null 2>&1 || true
            fi
        fi
    done

    # Mount Guard для внешнего накопителя /srv/storage после сбоя питания
    if [ "${EXT_STORAGE_EXPECTED:-no}" = "yes" ] && ! is_external_storage_mounted; then
        if try_auto_unlock_and_mount_storage; then
            RECOVERED_MSG="${RECOVERED_MSG}
🔒 [Авто-Доктор] Внешний накопитель (${STORAGE_ROOT}) автоматически разблокирован и смонтирован после перезагрузки."
        else
            # Удерживаем зависимые от диска сервисы в безопасной паузе, чтобы не забить корневую флешку
            stop_storage_dependent_services
            NOW_TS=$(date +%s 2>/dev/null || echo "0")
            LAST_ALERT_TS=0
            [ -f "$STORAGE_ALERT_CACHE" ] && LAST_ALERT_TS=$(cat "$STORAGE_ALERT_CACHE" 2>/dev/null | tr -d ' \t\r\n' || echo "0")
            case "$LAST_ALERT_TS" in ''|*[!0-9]*) LAST_ALERT_TS=0 ;; esac
            if [ $((NOW_TS - LAST_ALERT_TS)) -ge 3600 ]; then
                echo "$NOW_TS" > "$STORAGE_ALERT_CACHE" 2>/dev/null || true
                send_telegram_msg "⚡ Сервер ($(get_current_lan_ip)) перезагрузился после сбоя питания. Сетевой шлюз (Sing-Box + AdGuard) работает, но внешний диск (${STORAGE_ROOT}) ожидает подключения или разблокировки (выполните: gateway unlock)" >/dev/null 2>&1 || true
            fi
            if [ -n "$RECOVERED_MSG" ]; then
                send_telegram_msg "$RECOVERED_MSG" >/dev/null 2>&1 || true
            fi
            release_gateway_lock
            trap - EXIT INT TERM HUP
            return 0
        fi
    fi

    # Проверка активных служб Homelab из реестра modules.state (только когда диск смонтирован и готов)
    if [ -f "$HOMELAB_STATE" ] && is_storage_mount_ready; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            [ "$M_EN" = "yes" ] || continue
            [ -z "$M_SVC" ] && continue
            if [ -x "/etc/init.d/${M_SVC}" ] && ! rc-service "$M_SVC" status >/dev/null 2>&1; then
                logger -t gateway-watchdog "Homelab module ${M_ID} (${M_SVC}) down, restarting..." 2>/dev/null || true
                rc-service "$M_SVC" restart >/dev/null 2>&1 || true
                RECOVERED_MSG="${RECOVERED_MSG}
⚡ [Авто-Доктор Homelab] Перезапущен модуль ${M_ID} (${M_SVC})."
            fi
        done < "$HOMELAB_STATE"
    fi

    if [ -n "$RECOVERED_MSG" ]; then
        send_telegram_msg "$RECOVERED_MSG" >/dev/null 2>&1 || true
    fi
    release_gateway_lock
    trap - EXIT INT TERM HUP
    return 0
}

# Фоновая задача автообновления для cron (с эксклюзивной блокировкой против гонки с Watchdog в 04:00)
run_autoupdate() {
    set +e
    WAIT_LCK=0
    while ! acquire_gateway_lock "autoupdate"; do
        sleep 1
        WAIT_LCK=$((WAIT_LCK + 1))
        [ "$WAIT_LCK" -ge 15 ] && break
    done
    trap 'release_gateway_lock' EXIT INT TERM HUP
    detect_os
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Запуск автообновления шлюза и Homelab (${OS_NAME}) ==="
    update_cores_only "yes"
    if ! pgrep sing-box >/dev/null 2>&1; then
        service_ctl sing-box start
    fi
    if ! pgrep AdGuardHome >/dev/null 2>&1; then
        service_ctl adguardhome start
    fi
    reload_singbox_api
    rotate_gateway_logs
    send_telegram_msg "🔄 [Автообновление 04:00] Сервер (${OS_NAME} | $(get_current_lan_ip)) проверил обновления. Текущие версии: Sing-Box ${LATEST_SB_TAG}, AdGuard ${LATEST_AGH_TAG}." >/dev/null 2>&1 || true
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Автообновление завершено ==="
    release_gateway_lock
    trap - EXIT INT TERM HUP
    return 0
}

# Получение последнего тега релиза с GitHub
fetch_latest_github_tag() {
    REPO="$1"
    TAG=""
    RAW_JSON=$(curl -fsSL --curves X25519:P-256 --connect-timeout 3 -m 5 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || \
               curl -fsSL --connect-timeout 3 -m 5 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)
    if [ -n "$RAW_JSON" ]; then
        if command -v jq >/dev/null 2>&1; then
            TAG=$(printf "%s" "$RAW_JSON" | jq -r '.tag_name // empty' 2>/dev/null || true)
        fi
        if [ -z "$TAG" ]; then
            TAG=$(printf "%s" "$RAW_JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 | tr -d ' \t\r\n' || true)
        fi
    fi
    case "$TAG" in *[\/:]*|"") TAG="" ;; esac
    if [ -z "$TAG" ]; then
        TAG=$(curl -fsSLI --curves X25519:P-256 --connect-timeout 3 -m 5 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null | awk -F'/' '{print $NF}' | tr -d '\r\n' || true)
        [ "$TAG" = "latest" ] && TAG="" || true
        case "$TAG" in *[\/:]*|"") TAG="" ;; esac
    fi
    printf "%s" "$TAG"
    return 0
}

# Мгновенное чтение кэша версий из /tmp (чтобы меню открывалось за 0.01 сек без паузы!)
refresh_remote_versions() {
    FORCE_FETCH="${1:-no}"
    if [ "$FORCE_FETCH" != "yes" ] && [ -f "$VER_CACHE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$VER_CACHE_FILE" 2>/dev/null || true
        return 0
    fi

    LATEST_SB_TAG=$(fetch_latest_github_tag "shtorm-7/sing-box-extended")
    LATEST_AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
    if [ -f "${SB_DIR}/ui/index.html" ]; then
        LATEST_UI_TAG=$(fetch_latest_github_tag "$UI_REPO")
        if [ ! -f "$UI_VER_FILE" ] && [ -n "$LATEST_UI_TAG" ]; then
            echo "$LATEST_UI_TAG" > "$UI_VER_FILE"
        fi
    fi

    cat << VC_EOF > "$VER_CACHE_FILE" 2>/dev/null || true
LATEST_SB_TAG='${LATEST_SB_TAG}'
LATEST_AGH_TAG='${LATEST_AGH_TAG}'
LATEST_UI_TAG='${LATEST_UI_TAG}'
VC_EOF
    return 0
}

# Отрисовка телеметрии и статуса шлюза / стека Homelab в шапке главного меню (Spacecraft Dashboard)
print_gateway_header() {
    load_gateway_env
    calc_hardware_limits
    LAN_IP_NOW=$(get_current_lan_ip)
    LAN_IF_NOW=$(get_lan_ifname)

    if pgrep sing-box >/dev/null 2>&1; then
        S_BADGE=$(ui_badge "on" "SING-BOX: АКТИВЕН")
    else
        S_BADGE=$(ui_badge "err" "SING-BOX: СТОП")
    fi

    if [ -x /usr/bin/sing-box ]; then
        S_VER_RAW=$(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        [ -n "$S_VER_RAW" ] && S_VER="v${S_VER_RAW#v}" || S_VER="неизвестно"
    else
        S_VER="не установлен"
    fi

    if [ -n "$LATEST_SB_TAG" ] && [ "$S_VER" != "не установлен" ]; then
        if [ "$S_VER" = "$LATEST_SB_TAG" ]; then
            S_VER_INFO="${S_VER} ${C_DIM}(актуальна)${C_RES}"
        else
            S_VER_INFO="${S_VER} -> ${C_YEL}ДОСТУПНА ${LATEST_SB_TAG}!${C_RES}"
        fi
    else
        S_VER_INFO="${S_VER}"
    fi

    if pgrep AdGuardHome >/dev/null 2>&1; then
        A_BADGE=$(ui_badge "on" "ADGUARD: АКТИВЕН")
    else
        A_BADGE=$(ui_badge "err" "ADGUARD: СТОП")
    fi

    if [ -x /usr/bin/AdGuardHome ]; then
        A_VER=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)
        [ -z "$A_VER" ] && A_VER="установлен"
    else
        A_VER="не установлен"
    fi

    if [ -n "$LATEST_AGH_TAG" ] && [ "$A_VER" != "не установлен" ]; then
        if [ "$A_VER" = "$LATEST_AGH_TAG" ]; then
            A_VER_INFO="${A_VER} ${C_DIM}(актуальна)${C_RES}"
        else
            A_VER_INFO="${A_VER} -> ${C_YEL}ДОСТУПНА ${LATEST_AGH_TAG}!${C_RES}"
        fi
    else
        A_VER_INFO="${A_VER}"
    fi

    SUB_CNT=$(count_sub_urls)
    MY_CNT=$(count_my_nodes)
    if [ "$SUB_CNT" -gt 1 ]; then
        P_BADGE=$(ui_badge "info" "МУЛЬТИ-САБ: ${SUB_CNT}")
        P_INFO="подписок: ${SUB_CNT} шт. | ключей URI: ${MY_CNT}"
    elif [ "$SUB_CNT" -eq 1 ]; then
        P_BADGE=$(ui_badge "info" "ПОДПИСКА HTTP")
        P_INFO="${SUB_URL}"
    elif [ "$MY_CNT" -gt 0 ]; then
        P_BADGE=$(ui_badge "info" "КЛЮЧИ URI: ${MY_CNT}")
        P_INFO="активно в my_nodes.yaml: ${MY_CNT} шт."
    elif is_warp_enabled; then
        P_BADGE=$(ui_badge "on" "ТОЛЬКО WARP 2.0")
        P_INFO="гибридный Amnezia WARP 2.0 + MASQUE H2"
    else
        P_BADGE=$(ui_badge "warn" "РЕЖИМ DIRECT")
        P_INFO="прокси не заданы (весь трафик напрямую)"
    fi

    if is_warp_enabled; then
        W_BADGE=$(ui_badge "on" "WARP 2.0: ON")
        if [ -n "${WARP_LICENSE:-}" ]; then
            W_INFO="4 ноды AWG WARP+ + MASQUE TCP/H2"
        else
            W_INFO="4 ноды AWG 2.0 + MASQUE TCP/H2"
        fi
    else
        W_BADGE=$(ui_badge "off" "WARP 2.0: OFF")
        W_INFO="можно включить бесплатно в п. 2"
    fi

    if [ -f "${SB_DIR}/ui/index.html" ]; then
        UI_VER=""
        [ -f "$UI_VER_FILE" ] && UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n') || true
        [ -z "$UI_VER" ] && UI_VER="установлена"
        UI_BADGE=$(ui_badge "on" "ZASHBOARD")
        if [ -n "$LATEST_UI_TAG" ] && [ "$UI_VER" != "установлена" ] && [ "$UI_VER" != "$LATEST_UI_TAG" ]; then
            UI_VER_INFO="${UI_VER} -> ${C_YEL}ДОСТУПНА ${LATEST_UI_TAG}!${C_RES}"
        else
            UI_VER_INFO="${UI_VER}"
        fi
    else
        UI_BADGE=$(ui_badge "err" "UI: НЕТ")
        UI_VER_INFO="не установлена"
    fi

    if is_killswitch_enabled; then
        KS_BADGE=$(ui_badge "info" "KILL-SWITCH: ON")
        KS_INFO="строгая блокировка мимо singbox-tun (${LAN_IF_NOW})"
    else
        KS_BADGE=$(ui_badge "on" "FIREWALL: GUARD")
        KS_INFO="блок IPv6 + DoT/853 + перехват DNS :53 (${LAN_IF_NOW})"
    fi

    is_watchdog_enabled && WD_TXT="${C_GRN}● ВКЛ${C_RES}" || WD_TXT="${C_DIM}○ ВЫКЛ${C_RES}"
    is_telegram_configured && TG_TXT="${C_GRN}● ВКЛ${C_RES}" || TG_TXT="${C_DIM}○ ВЫКЛ${C_RES}"
    is_dhcp_server_enabled && DHCP_TXT="${C_GRN}● ВКЛ${C_RES}" || DHCP_TXT="${C_DIM}○ ВЫКЛ${C_RES}"
    is_autoupdate_enabled && AU_BADGE=$(ui_badge "on" "AUTO-UPD: 04:00") || AU_BADGE=$(ui_badge "off" "AUTO-UPD: РУЧНОЙ")

    RAM_PCT=$(get_ram_usage_pct)
    RAM_USED=$(get_ram_used_mb)
    RAM_BAR=$(ui_progress_bar "$RAM_PCT" 10)

    DISK_PCT=$(get_disk_usage_pct "$STORAGE_ROOT")
    DISK_BAR=$(ui_progress_bar "$DISK_PCT" 10)
    DISK_FREE_TXT=$(df -h "${STORAGE_ROOT:-/}" 2>/dev/null | awk 'NR==2 {print $4 " своб. из " $2}' || echo "н/д")
    DISK_BADGE=$(get_storage_disk_badge)

    HL_ACT_CNT=$(count_enabled_homelab_modules)
    if [ "$HL_ACT_CNT" -gt 0 ]; then
        HL_BADGE=$(ui_badge "on" "HOMELAB: ${HL_ACT_CNT}/9")
    else
        HL_BADGE=$(ui_badge "off" "HOMELAB: 0/9")
    fi

    ui_box_top "⚡ ПРИБОРНАЯ ПАНЕЛЬ ТЕЛЕМЕТРИИ ШЛЮЗА И HOMELAB (${OS_NAME})"
    ui_box_row "Сеть LAN:     ${C_BLD}${LAN_IF_NOW}: ${LAN_IP_NOW}${C_RES} ▸ Роутер: ${C_CYN}${GW_IP}${C_RES} │ Умный DHCP: ${DHCP_TXT}"
    ui_box_row "Загрузка ОЗУ: ${RAM_BAR} (${RAM_USED}/${TOTAL_RAM_MB} МБ, лимит SB: ${SB_GOMEMLIMIT}, AGH: ${AGH_GOMEMLIMIT})"
    ui_box_row "Накопитель:   ${DISK_BAR} (${DISK_FREE_TXT}) ▸ ${C_CYN}${DISK_BADGE}${C_RES}"
    ui_box_sep "СТАТУС ЯДЕР И СЛУЖБ"
    ui_box_row "Sing-Box Ext: ${S_BADGE} ${S_VER_INFO} │ Веб-панель: ${UI_BADGE} ${UI_VER_INFO}"
    ui_box_row "AdGuard Home: ${A_BADGE} ${A_VER_INFO} (DNS :53 + *.lan Rewrites)"
    ui_box_row "Основной пул: ${P_BADGE} ${P_INFO}"
    ui_box_row "Amnezia WARP: ${W_BADGE} ${W_INFO}"
    ui_box_row "Защита сети:  ${KS_BADGE} ${KS_INFO}"
    ui_box_row "Автономность: ${AU_BADGE} │ Watchdog: ${WD_TXT} │ Telegram: ${TG_TXT} │ Стек: ${HL_BADGE}"

    if [ -f "$POWER_LOSS_FLAG" ]; then
        PL_TIME=$(cat "$POWER_LOSS_FLAG" 2>/dev/null || echo "недавно")
        ui_box_sep "ПРЕДУПРЕЖДЕНИЕ ПИТАНИЯ"
        ui_box_row "${C_YEL}▲ Зафиксировано авто-восстановление после сбоя питания (${PL_TIME}). Рекомендуется: gateway doctor${C_RES}"
    fi
    if [ "${EXT_STORAGE_EXPECTED:-no}" = "yes" ] && ! is_external_storage_mounted; then
        ui_box_sep "СТАТУС ВНЕШНЕГО ДИСКА LUKS2"
        ui_box_row "${C_YEL}▲ Внешний накопитель ожидает разблокировки! Выполните в терминале: ${C_BLD}gateway unlock${C_RES}"
    fi
    ui_box_bottom
    return 0
}

# Проверка прямого доступа к GitHub (с защитой от фрагментации TLS 1.3 Kyber)
