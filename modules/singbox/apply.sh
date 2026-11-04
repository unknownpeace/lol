apply_and_verify_singbox() {
    ACTION_TITLE="${1:-Обновление конфигурации}"
    ensure_alpine_modules
    generate_singbox_config

    if ! check_singbox_config; then
        echo "${C_RED}[X] Ошибка синтаксиса при действии: ${ACTION_TITLE}!${C_RES}"
        ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
            /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" || true
        echo "${C_YEL}[!] Выполняется авто-откат к предыдущей рабочей конфигурации...${C_RES}"
        restore_gateway_state
        return 1
    fi

    service_ctl sing-box restart

    WAIT_OK="no"
    W_IDX=0
    while [ "$W_IDX" -lt 8 ]; do
        if pgrep sing-box >/dev/null 2>&1 && ip link show singbox-tun >/dev/null 2>&1; then
            WAIT_OK="yes"
            break
        fi
        sleep 1
        W_IDX=$((W_IDX + 1))
    done

    if [ "$WAIT_OK" = "yes" ]; then
        sync_dns_firewall "yes" "keep" >/dev/null 2>&1 || true
        reload_singbox_api
        ui_box_top "✔ ${ACTION_TITLE}: УСПЕШНО (SING-BOX & TUN АКТИВНЫ)"
        print_proxy_slots_report
        ui_box_bottom
        return 0
    else
        ui_box_sep
        echo "${C_RED}[X] Служба Sing-Box не смогла запуститься (${ACTION_TITLE})!${C_RES}"
        echo "--- Причина из системного журнала ---"
        show_singbox_logs 8
        ui_box_sep
        echo "${C_YEL}[!] Выполняется авто-откат к предыдущей рабочей конфигурации...${C_RES}"
        restore_gateway_state
        return 1
    fi
}

# Отправка текстового уведомления в Telegram (через туннель Sing-Box или напрямую)
