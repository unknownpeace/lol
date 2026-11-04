print_homelab_services_table() {
    init_homelab_registry
    load_gateway_env
    DISK_BADGE=$(get_storage_disk_badge)
    DISK_PCT=$(get_disk_usage_pct "$STORAGE_ROOT")
    DISK_BAR=$(ui_progress_bar "$DISK_PCT" 10)

    ui_box_top "🏠 МОДУЛИ ДОМАШНЕГО СЕРВЕРА (ALPINE HOMELAB & MEDIA STACK)"
    ui_box_row "Хранилище ${STORAGE_ROOT}: ${DISK_BAR} ▸ ${C_CYN}${DISK_BADGE}${C_RES}"
    ui_box_sep "СПИСОК МОДУЛЕЙ [1-9]"
    IDX_M=0
    while IFS='|' read -r M_ID M_EN M_SVC M_PORT M_DOM _M_USR M_TITLE; do
        case "$M_ID" in ''|\#*) continue ;; esac
        IDX_M=$((IDX_M + 1))
        if [ "$M_EN" = "yes" ]; then
            if rc-service "$M_SVC" status >/dev/null 2>&1; then
                ST_BADGE="${C_GRN}[ ● РАБОТАЕТ ]  ${C_RES}"
            elif ! is_storage_mount_ready && [ "$M_ID" != "caddy" ] && [ "$M_ID" != "vaultwarden" ]; then
                ST_BADGE="${C_YEL}[ ▲ ЖДЕТ ДИСК ] ${C_RES}"
            else
                ST_BADGE="${C_RED}[ ✖ ОСТАНОВЛЕН ]${C_RES}"
            fi
        else
            ST_BADGE="${C_DIM}[ ○ ВЫКЛЮЧЕН ]  ${C_RES}"
        fi
        if [ "$M_ID" = "caddy" ]; then
            M_URL="http://ca.lan (PKI)"
        elif [ "$M_DOM" != "_" ]; then
            M_URL="https://${M_DOM}"
        else
            M_URL="\\\\$(hostname -s 2>/dev/null || echo HOMELAB)\\storage"
        fi
        printf "%s│%s  %s[%d]%s %-11s %s │ %-6s │ %-24s │ %s\n" "$C_CYN" "$C_RES" "$C_CYN" "$IDX_M" "$C_RES" "$M_ID" "$ST_BADGE" ":$M_PORT" "$M_URL" "$M_TITLE"
    done < "$HOMELAB_STATE"
    ui_box_bottom
    return 0
}

# Глубокая проверка состояния подсистемы Homelab (Homelab Self-Test)
run_homelab_self_test() {
    init_homelab_registry
    load_gateway_env
    CUR_LIP=$(get_current_lan_ip)

    ui_box_top "🔬 ДИАГНОСТИКА ПОДСИСТЕМЫ HOMELAB (HOMELAB SELF-TEST)"
    if [ -d "$STORAGE_ROOT" ]; then
        ST_PERM=$(stat -c "%a %U:%G" "$STORAGE_ROOT" 2>/dev/null || echo "н/д")
        ui_box_row "${C_GRN}[✔]${C_RES} Единое хранилище (${STORAGE_ROOT}): ${C_GRN}ДОСТУПНО${C_RES} (права: ${ST_PERM} | $(get_storage_disk_badge))"
    else
        ui_box_row "${C_YEL}[▲]${C_RES} Единое хранилище (${STORAGE_ROOT}): еще не инициализировано"
    fi

    if find_caddy_root_cert; then
        ui_box_row "${C_GRN}[✔]${C_RES} Локальный Root CA Caddy: ${C_GRN}СГЕНЕРИРОВАН${C_RES} (портал: http://${DOM_CA} / http://${CUR_LIP})"
        ui_box_row "${C_GRN}[✔]${C_RES} Панели шлюза по HTTPS: ${C_CYN}https://${DOM_ZASHBOARD}${C_RES} │ ${C_CYN}https://${DOM_ADGUARD}${C_RES}"
    else
        ui_box_row "${C_DIM}[○]${C_RES} Локальный Root CA Caddy: не активен (установите модуль caddy)"
    fi

    while IFS='|' read -r M_ID M_EN M_SVC M_PORT M_DOM _M_USR M_TITLE; do
        case "$M_ID" in ''|\#*) continue ;; esac
        [ "$M_EN" = "yes" ] || continue

        if rc-service "$M_SVC" status >/dev/null 2>&1; then
            SVC_TXT="${C_GRN}● ЗАПУЩЕН${C_RES}"
        else
            SVC_TXT="${C_RED}✖ ОСТАНОВЛЕН${C_RES}"
        fi

        if [ "$M_ID" = "samba" ]; then
            WSDD_ST=$(rc-service wsdd status >/dev/null 2>&1 && echo "WSDD:OK" || echo "WSDD:OFF")
            AVAHI_ST=$(rc-service avahi-daemon status >/dev/null 2>&1 && echo "Avahi:OK" || echo "Avahi:OFF")
            PDB_ST="PDB:OK"
            if command -v pdbedit >/dev/null 2>&1; then
                pdbedit -L -w "${SMB_USER:-homelab}" 2>/dev/null | grep -q "^${SMB_USER:-homelab}:" || PDB_ST="PDB:FAIL"
            fi
            ui_box_row "▸ [${M_ID}] ${M_TITLE}: ${SVC_TXT} │ Юзер: ${SMB_USER:-homelab} (${PDB_ST}) │ LAN: ${C_CYN}${WSDD_ST}, ${AVAHI_ST}${C_RES}"
        elif [ "$M_ID" = "caddy" ]; then
            ui_box_row "▸ [${M_ID}] ${M_TITLE}: ${SVC_TXT} │ HTTPS :443 / PKI :80"
        elif [ "$M_ID" = "vaultwarden" ]; then
            HTTP_CODE=$(curl -k -o /dev/null -sS --connect-timeout 2 -m 3 -w '%{http_code}' "http://127.0.0.1:${M_PORT}/api/config" 2>/dev/null || echo "000")
            WV_ST="WebVault:OK"
            detect_vaultwarden_web_dir >/dev/null 2>&1 || WV_ST="WebVault:FAIL"
            ui_box_row "▸ [${M_ID}] ${M_TITLE}: ${SVC_TXT} │ 127.0.0.1:${M_PORT} (HTTP ${HTTP_CODE}, ${WV_ST}) ▸ ${C_CYN}https://${M_DOM}${C_RES}"
        else
            HTTP_CODE=$(curl -k -o /dev/null -sS --connect-timeout 2 -m 3 -w '%{http_code}' "http://127.0.0.1:${M_PORT}" 2>/dev/null || echo "000")
            ui_box_row "▸ [${M_ID}] ${M_TITLE}: ${SVC_TXT} │ 127.0.0.1:${M_PORT} (HTTP ${HTTP_CODE}) ▸ ${C_CYN}https://${M_DOM}${C_RES}"
        fi
    done < "$HOMELAB_STATE"
    ui_box_bottom
    return 0
}

# Мастер выбора модулей Homelab при первоначальной установке или доустановке
