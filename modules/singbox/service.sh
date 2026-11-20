#!/bin/sh
# Снимок заведомо рабочего состояния конфигов на ПЕРСИСТЕНТНЫЙ диск (/etc/sing-box/.last_good_state)
# Переживает отключение питания (в отличие от /tmp в tmpfs) и спасает при обрыве света во время реконфигурации
backup_gateway_state() {
    mkdir -p "$STATE_BAK_DIR" 2>/dev/null || true
    chmod 700 "$STATE_BAK_DIR" 2>/dev/null || true
    for f in "$SB_CONF" "$MIHOMO_CONF" "$SB_ENV" "$HOMELAB_ENV" "$CUSTOM_NODES_FILE" "$WARP_NODES_FILE" \
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
    [ -s "${STATE_BAK_DIR}/config.yaml" ] && cp -f "${STATE_BAK_DIR}/config.yaml" "$MIHOMO_CONF" || true
    [ -s "${STATE_BAK_DIR}/gateway.env" ] && cp -f "${STATE_BAK_DIR}/gateway.env" "$SB_ENV" || true
    [ -s "${STATE_BAK_DIR}/homelab.env" ] && cp -f "${STATE_BAK_DIR}/homelab.env" "$HOMELAB_ENV" || true
    [ -s "${STATE_BAK_DIR}/my_nodes.yaml" ] && cp -f "${STATE_BAK_DIR}/my_nodes.yaml" "$CUSTOM_NODES_FILE" || true
    [ -s "${STATE_BAK_DIR}/warp_nodes.json" ] && cp -f "${STATE_BAK_DIR}/warp_nodes.json" "$WARP_NODES_FILE" || true
    [ -s "${STATE_BAK_DIR}/user_direct_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_direct_domains.list" "$USER_DIRECT_FILE" || true
    [ -s "${STATE_BAK_DIR}/user_proxy_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_proxy_domains.list" "$USER_PROXY_FILE" || true
    [ -f "${STATE_BAK_DIR}/bypass_devices.conf" ] && cp -f "${STATE_BAK_DIR}/bypass_devices.conf" "$USER_BYPASS_IPS" || true
    [ -f "${STATE_BAK_DIR}/force_proxy_devices.conf" ] && cp -f "${STATE_BAK_DIR}/force_proxy_devices.conf" "$USER_FORCE_PROXY_IPS" || true
    chmod 600 "$SB_CONF" "$MIHOMO_CONF" "$SB_ENV" "$HOMELAB_ENV" 2>/dev/null || true
    sync
    sync_user_domain_rulesets
    load_gateway_env
    if [ "$(get_active_core)" = "mihomo" ]; then
        service_ctl sing-box stop
        service_ctl sing-box disable
        service_ctl mihomo enable
        service_ctl mihomo restart
    else
        service_ctl mihomo stop
        service_ctl mihomo disable
        service_ctl sing-box enable
        service_ctl sing-box restart
    fi
    return 0
}

# Наглядный отчет по 3 независимым слотам прокси
