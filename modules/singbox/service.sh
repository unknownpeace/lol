service_ctl() {
    SVC_NAME="$1"
    SVC_ACT="$2"
    [ "$SVC_NAME" = "cron" ] && SVC_NAME="crond"

    case "$SVC_ACT" in
        enable)
            rc-update add "$SVC_NAME" default >/dev/null 2>&1 || true
            return 0
            ;;
        disable)
            rc-update del "$SVC_NAME" default >/dev/null 2>&1 || true
            return 0
            ;;
        stop)
            rc-service "$SVC_NAME" stop >/dev/null 2>&1 || "/etc/init.d/${SVC_NAME}" stop >/dev/null 2>&1 || true
            return 0
            ;;
        reload)
            if rc-service "$SVC_NAME" reload >/dev/null 2>&1 || rc-service "$SVC_NAME" restart >/dev/null 2>&1; then
                return 0
            fi
            "/etc/init.d/${SVC_NAME}" restart >/dev/null 2>&1 || return 1
            return 0
            ;;
        status)
            rc-service "$SVC_NAME" status >/dev/null 2>&1 || "/etc/init.d/${SVC_NAME}" status >/dev/null 2>&1
            return $?
            ;;
        *)
            if rc-service "$SVC_NAME" "$SVC_ACT" >/dev/null 2>&1 || "/etc/init.d/${SVC_NAME}" "$SVC_ACT" >/dev/null 2>&1; then
                return 0
            fi
            return 1
            ;;
    esac
}

# Чтение логов Sing-Box в Alpine Linux
show_singbox_logs() {
    LINES_CNT="${1:-40}"
    if [ -s "$SB_LOG_FILE" ]; then
        tail -n "$LINES_CNT" "$SB_LOG_FILE" 2>/dev/null || true
    elif [ -f /var/log/messages ]; then
        grep -i "sing-box" /var/log/messages 2>/dev/null | tail -n "$LINES_CNT" || true
    else
        echo "  ${C_DIM}(лог-файл ${SB_LOG_FILE} пока пуст)${C_RES}"
    fi
    return 0
}

# Снимок заведомо рабочего состояния конфигов на ПЕРСИСТЕНТНЫЙ диск (/etc/sing-box/.last_good_state)
# Переживает отключение питания (в отличие от /tmp в tmpfs) и спасает при обрыве света во время реконфигурации
backup_gateway_state() {
    mkdir -p "$STATE_BAK_DIR" 2>/dev/null || true
    chmod 700 "$STATE_BAK_DIR" 2>/dev/null || true
    for f in "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" "$CUSTOM_NODES_FILE" "$WARP_NODES_FILE" \
             "$USER_DIRECT_FILE" "$USER_PROXY_FILE" "$USER_BYPASS_IPS" "$USER_FORCE_PROXY_IPS"; do
        if [ -s "$f" ]; then
            cp -f "$f" "$STATE_BAK_DIR/" 2>/dev/null || true
        fi
    done
    sync
    return 0
}

# Восстановление состояния при ошибке синтаксиса, старта или после обрыва питания
restore_gateway_state() {
    [ -d "$STATE_BAK_DIR" ] || return 0
    [ -s "${STATE_BAK_DIR}/config.json" ] && cp -f "${STATE_BAK_DIR}/config.json" "$SB_CONF" || true
    [ -s "${STATE_BAK_DIR}/gateway.env" ] && cp -f "${STATE_BAK_DIR}/gateway.env" "$SB_ENV" || true
    [ -s "${STATE_BAK_DIR}/homelab.env" ] && cp -f "${STATE_BAK_DIR}/homelab.env" "$HOMELAB_ENV" || true
    [ -s "${STATE_BAK_DIR}/my_nodes.yaml" ] && cp -f "${STATE_BAK_DIR}/my_nodes.yaml" "$CUSTOM_NODES_FILE" || true
    [ -s "${STATE_BAK_DIR}/warp_nodes.json" ] && cp -f "${STATE_BAK_DIR}/warp_nodes.json" "$WARP_NODES_FILE" || true
    [ -s "${STATE_BAK_DIR}/user_direct_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_direct_domains.list" "$USER_DIRECT_FILE" || true
    [ -s "${STATE_BAK_DIR}/user_proxy_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_proxy_domains.list" "$USER_PROXY_FILE" || true
    [ -f "${STATE_BAK_DIR}/bypass_devices.conf" ] && cp -f "${STATE_BAK_DIR}/bypass_devices.conf" "$USER_BYPASS_IPS" || true
    [ -f "${STATE_BAK_DIR}/force_proxy_devices.conf" ] && cp -f "${STATE_BAK_DIR}/force_proxy_devices.conf" "$USER_FORCE_PROXY_IPS" || true
    chmod 600 "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" 2>/dev/null || true
    sync
    sync_user_domain_rulesets
    load_gateway_env
    service_ctl sing-box restart
    return 0
}

# Наглядный отчет по 3 независимым слотам прокси
