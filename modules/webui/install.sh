#!/bin/sh
# ==============================================================================
# Установщик и синхронизатор веб-панели Alpine Linux (gateway-webui)
# На OpenWrt не выполняется (там работает native LuCI luci-app-gateway).
# ==============================================================================

install_alpine_webui() {
    is_openwrt 2>/dev/null && return 0
    [ -f /etc/openwrt_release ] && return 0

    SRC_WEBUI="${GATEWAY_DIR}/modules/webui"
    [ -f "${SRC_WEBUI}/server.py" ] || return 0
    [ -f "${SRC_WEBUI}/api.sh" ] || return 0

    if ! command -v python3 >/dev/null 2>&1; then
        apk add --no-cache python3 >/dev/null 2>&1 || return 1
    fi

    load_gateway_env >/dev/null 2>&1 || true

    BIND_HOST="0.0.0.0"
    AUTH_MODE="basic"
    if is_module_enabled "caddy" && [ -x /usr/sbin/caddy ]; then
        BIND_HOST="127.0.0.1"
        AUTH_MODE="caddy"
    fi

    cat << INIT_EOF > /etc/init.d/gateway-webui
#!/sbin/openrc-run
name="gateway-webui"
description="Universal Gateway & Homelab Web Dashboard"
supervisor="supervise-daemon"
command="/usr/bin/python3"
command_args="${SRC_WEBUI}/server.py"
output_log="/var/log/gateway-webui.log"
error_log="/var/log/gateway-webui.log"

export GATEWAY_DIR="${GATEWAY_DIR}"
export GATEWAY_WEBUI_HOST="${BIND_HOST}"
export GATEWAY_WEBUI_PORT="${PORT_WEBUI:-8095}"
export GATEWAY_WEBUI_AUTH="${AUTH_MODE}"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -f -m 0640 /var/log/gateway-webui.log
}
INIT_EOF
    chmod 755 /etc/init.d/gateway-webui

    if command -v rc-update >/dev/null 2>&1; then
        rc-update add gateway-webui default >/dev/null 2>&1 || true
    fi
    if command -v rc-service >/dev/null 2>&1; then
        rc-service gateway-webui restart >/dev/null 2>&1 || rc-service gateway-webui start >/dev/null 2>&1 || true
    fi

    if [ "$AUTH_MODE" = "caddy" ]; then
        if [ -f "$AGH_CONF" ]; then
            _need_agh_sync="no"
            grep -q "${DOM_GATEWAY:-gateway.lan}" "$AGH_CONF" 2>/dev/null || _need_agh_sync="yes"
            if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
                grep -q "gateway.${SSL_DOMAIN}" "$AGH_CONF" 2>/dev/null || _need_agh_sync="yes"
            fi
            if [ "$_need_agh_sync" = "yes" ] && command -v sync_agh_homelab_rewrites >/dev/null 2>&1; then
                sync_agh_homelab_rewrites "$(get_current_lan_ip)" >/dev/null 2>&1 || true
            fi
        fi
        if command -v register_caddy_site >/dev/null 2>&1; then
            register_caddy_site "gateway" "${DOM_GATEWAY:-gateway.lan}" "${PORT_WEBUI:-8095}" "yes" >/dev/null 2>&1 || true
        fi
        if command -v build_pki_portal >/dev/null 2>&1; then
            build_pki_portal >/dev/null 2>&1 || true
        fi
    else
        rm -f "${CADDY_CONFD}/gateway.caddy" 2>/dev/null || true
    fi
    return 0
}
