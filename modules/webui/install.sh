#!/bin/sh
# ==============================================================================
# Установщик и синхронизатор веб-панели Alpine Linux (gateway-webui + ttyd)
# На OpenWrt не выполняется (там работает native LuCI luci-app-gateway).
# ==============================================================================

_ensure_webui_runtime_and_token() {
    ensure_gateway_runtime_dir || return 1
    _ctok_dir="${GATEWAY_RUNTIME_DIR:-/run/gateway}/console_tokens"
    (umask 077 && mkdir -p "$_ctok_dir") 2>/dev/null || true
    chown root:root "$_ctok_dir" 2>/dev/null || true
    chmod 700 "$_ctok_dir" 2>/dev/null || true
    ensure_webui_proxy_token >/dev/null || return 1
    return 0
}

install_alpine_webui() {
    is_openwrt 2>/dev/null && return 0
    [ -f /etc/openwrt_release ] && return 0

    SRC_WEBUI="${GATEWAY_DIR}/modules/webui"
    [ -f "${SRC_WEBUI}/server.py" ] || return 0
    [ -f "${SRC_WEBUI}/api.sh" ] || return 0

    if ! command -v python3 >/dev/null 2>&1; then
        apk add --no-cache python3 >/dev/null 2>&1 || return 1
    fi
    if ! command -v ttyd >/dev/null 2>&1; then
        apk add --no-cache ttyd >/dev/null 2>&1 || true
    fi

    load_gateway_env >/dev/null 2>&1 || true
    _ensure_webui_runtime_and_token

    BIND_HOST="0.0.0.0"
    AUTH_MODE="basic"
    if is_module_enabled "caddy" && [ -x /usr/sbin/caddy ]; then
        BIND_HOST="127.0.0.1"
        AUTH_MODE="caddy"
    fi

    if command -v ttyd >/dev/null 2>&1 && [ -f "${SRC_WEBUI}/lxc_console.sh" ]; then
        cat << CON_INIT > /etc/init.d/gateway-console
#!/sbin/openrc-run
name="gateway-console"
description="Gateway LXC Web Console (ttyd)"
supervisor="supervise-daemon"
command="/usr/bin/ttyd"
command_args="-i 127.0.0.1 -p ${PORT_WEBUI_CONSOLE:-8096} -b /console -a -W -O -t disableReconnect=true -t fontSize=14 -t cursorBlink=true /bin/sh ${SRC_WEBUI}/lxc_console.sh"
output_log="/var/log/gateway-console.log"
error_log="/var/log/gateway-console.log"

depend() {
    need net
}

start_pre() {
    checkpath -d -m 0700 -o root:root /run/gateway
    checkpath -d -m 0700 -o root:root /run/gateway/console_tokens
    checkpath -f -m 0640 /var/log/gateway-console.log
}
CON_INIT
        chmod 755 /etc/init.d/gateway-console
        if command -v rc-update >/dev/null 2>&1; then
            rc-update add gateway-console default >/dev/null 2>&1 || true
        fi
        if command -v rc-service >/dev/null 2>&1; then
            rc-service gateway-console restart >/dev/null 2>&1 || rc-service gateway-console start >/dev/null 2>&1 || true
        fi
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
export GATEWAY_WEBUI_CONSOLE_PORT="${PORT_WEBUI_CONSOLE:-8096}"
export GATEWAY_WEBUI_AUTH="${AUTH_MODE}"
export GATEWAY_ENV_FILE="${SB_ENV:-/etc/sing-box/gateway.env}"
export GATEWAY_HOMELAB_ENV_FILE="${HOMELAB_ENV:-/etc/sing-box/homelab.env}"
export GATEWAY_PROXY_TOKEN_FILE="/etc/sing-box/homelab/webui_proxy.token"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -d -m 0700 -o root:root /run/gateway
    checkpath -d -m 0700 -o root:root /run/gateway/console_tokens
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
