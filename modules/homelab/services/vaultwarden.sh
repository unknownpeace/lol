#!/bin/sh
set -e

# ==============================================================================
# Модуль Vaultwarden (Bitwarden Server)
# ==============================================================================

if [ -z "${GATEWAY_DIR:-}" ]; then
    GATEWAY_DIR="$(cd -P "$(dirname "$0")/../../.." && pwd)"
    . "${GATEWAY_DIR}/lib/constants.sh"
    . "${GATEWAY_DIR}/lib/ui.sh"
    . "${GATEWAY_DIR}/lib/core.sh"
    . "${GATEWAY_DIR}/lib/env.sh"
    . "${GATEWAY_DIR}/lib/env_store.sh"
    . "${GATEWAY_DIR}/modules/caddy/ssl.sh"
    . "${GATEWAY_DIR}/modules/caddy/caddy.sh"
    . "${GATEWAY_DIR}/modules/network/firewall.sh"
    . "${GATEWAY_DIR}/modules/homelab/registry.sh"
fi

detect_vaultwarden_web_dir() {
    for WV_CAND in \
        "/usr/share/webapps/vaultwarden-web" \
        "/usr/share/vaultwarden/web-vault" \
        "/var/lib/vaultwarden/web-vault"; do
        if [ -f "${WV_CAND}/index.html" ]; then
            printf "%s" "${WV_CAND%/}/"
            return 0
        fi
    done
    printf "/usr/share/webapps/vaultwarden-web/"
    return 1
}

# Синхронизация эталонной конфигурации Vaultwarden (/etc/conf.d/vaultwarden + /var/lib/vaultwarden/.env)
sync_vaultwarden_config() {
    load_gateway_env
    ensure_media_group_and_users

    mkdir -p /var/lib/vaultwarden/attachments /var/lib/vaultwarden/sends /var/lib/vaultwarden/icon_cache /var/lib/vaultwarden/tmp
    WEB_VAULT_DIR=$(detect_vaultwarden_web_dir || true)

    ESC_VW_ADM=$(escape_single_quotes "${ADMIN_PASS:-admin}")
    umask 077
    cat << VW_EOF > /etc/conf.d/vaultwarden
# Конфигурация Vaultwarden (Alpine Homelab Edition)
export DATA_FOLDER="/var/lib/vaultwarden"
export DATABASE_URL="sqlite:///var/lib/vaultwarden/db.sqlite3"
export ENABLE_DB_WAL="true"
export ROCKET_ADDRESS="127.0.0.1"
export ROCKET_PORT="${PORT_VAULTWARDEN}"
export DOMAIN="https://${DOM_VAULTWARDEN}"
export WEB_VAULT_ENABLED="true"
export WEB_VAULT_FOLDER="${WEB_VAULT_DIR}"
export SIGNUPS_ALLOWED="true"
export WEBSOCKET_ENABLED="true"
export IP_HEADER="X-Real-IP"
export EXTENDED_LOGGING="true"
export LOG_LEVEL="info"
export LOG_FILE="/var/log/vaultwarden.log"
export ADMIN_TOKEN='${ESC_VW_ADM}'
VW_EOF
    chown root:vaultwarden /etc/conf.d/vaultwarden 2>/dev/null || true
    chmod 640 /etc/conf.d/vaultwarden 2>/dev/null || true

    sed 's/^export //' /etc/conf.d/vaultwarden > /var/lib/vaultwarden/.env 2>/dev/null || true
    chown vaultwarden:vaultwarden /var/lib/vaultwarden/.env 2>/dev/null || true
    chmod 600 /var/lib/vaultwarden/.env 2>/dev/null || true
    umask 022

    if [ -f /var/lib/vaultwarden/config.json ] && command -v jq >/dev/null 2>&1; then
        jq --arg dom "https://${DOM_VAULTWARDEN}" --arg adm "${ADMIN_PASS:-admin}" \
           '.domain = $dom | .web_vault_enabled = true | .admin_token = $adm' \
           /var/lib/vaultwarden/config.json > /var/lib/vaultwarden/config.json.tmp 2>/dev/null && \
           mv -f /var/lib/vaultwarden/config.json.tmp /var/lib/vaultwarden/config.json 2>/dev/null || true
        chown vaultwarden:vaultwarden /var/lib/vaultwarden/config.json 2>/dev/null || true
        chmod 600 /var/lib/vaultwarden/config.json 2>/dev/null || true
    fi

    touch /var/log/vaultwarden.log 2>/dev/null || true
    chown vaultwarden:vaultwarden /var/log/vaultwarden.log 2>/dev/null || true
    chmod 640 /var/log/vaultwarden.log 2>/dev/null || true
    chown -R vaultwarden:vaultwarden /var/lib/vaultwarden 2>/dev/null || true
    chmod 750 /var/lib/vaultwarden 2>/dev/null || true
    [ -d "${WEB_VAULT_DIR%/}" ] && chmod -R a+rX "${WEB_VAULT_DIR%/}" 2>/dev/null || true

    CUR_LIP_VW=$(get_current_lan_ip)
    if [ -n "$CUR_LIP_VW" ] && ! grep -qE "^${CUR_LIP_VW}[[:space:]].*${DOM_VAULTWARDEN}" /etc/hosts 2>/dev/null; then
        sed -i "/${DOM_VAULTWARDEN}/d" /etc/hosts 2>/dev/null || true
        printf "%s\t%s %s\n" "$CUR_LIP_VW" "$DOM_VAULTWARDEN" "$DOM_CA" >> /etc/hosts 2>/dev/null || true
    fi
    return 0
}

install_module_vaultwarden() {
    echo "${C_CYN}[*] Установка модуля Vaultwarden (Bitwarden Server + Web Vault)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add vaultwarden vaultwarden-openrc vaultwarden-web-vault sqlite; then
        echo "${C_RED}[X] Не удалось установить пакеты vaultwarden и vaultwarden-web-vault!${C_RES}"
        return 1
    fi

    if ! id vaultwarden >/dev/null 2>&1; then
        addgroup -S vaultwarden 2>/dev/null || true
        adduser -S -D -H -h /var/lib/vaultwarden -s /sbin/nologin -G vaultwarden vaultwarden 2>/dev/null || true
    fi

    sync_vaultwarden_config

    cat << 'VW_INIT_EOF' > /etc/init.d/vaultwarden
#!/sbin/openrc-run
name="vaultwarden"
description="Vaultwarden Bitwarden Server (Alpine Homelab Edition)"
supervisor="supervise-daemon"
command="/usr/bin/vaultwarden"
command_user="vaultwarden:vaultwarden"
directory="/var/lib/vaultwarden"
output_log="/var/log/vaultwarden.log"
error_log="/var/log/vaultwarden.log"
rc_ulimit="-n 65535"
respawn_delay=3
respawn_max=10

if [ -f /etc/conf.d/vaultwarden ]; then
    . /etc/conf.d/vaultwarden
fi

depend() {
    need net
}

start_pre() {
    checkpath -d -m 0750 -o vaultwarden:vaultwarden /var/lib/vaultwarden
    checkpath -f -m 0640 -o vaultwarden:vaultwarden /var/log/vaultwarden.log
}
VW_INIT_EOF
    chmod +x /etc/init.d/vaultwarden

    service_ctl vaultwarden enable
    if ! service_ctl vaultwarden restart; then
        echo "${C_RED}[X] Служба Vaultwarden не смогла запуститься! Проверьте /var/log/vaultwarden.log.${C_RES}"
        return 1
    fi

    W_VW=0
    while [ "$W_VW" -lt 8 ]; do
        if curl -fsS --connect-timeout 1 -m 2 "http://127.0.0.1:${PORT_VAULTWARDEN}/alive" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        W_VW=$((W_VW + 1))
    done

    register_caddy_site "vaultwarden" "$DOM_VAULTWARDEN" "$PORT_VAULTWARDEN" "no"
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
    set_module_state "vaultwarden" "yes"

    echo "${C_GRN}[✓] Vaultwarden запущен: https://${DOM_VAULTWARDEN} (Админ-панель: https://${DOM_VAULTWARDEN}/admin)${C_RES}"
    return 0
}

remove_module_vaultwarden() {
    service_ctl vaultwarden stop || true
    service_ctl vaultwarden disable || true
    remove_caddy_site "vaultwarden"
    set_module_state "vaultwarden" "no"
    echo "${C_GRN}[✓] Модуль Vaultwarden отключен (база паролей в /var/lib/vaultwarden сохранена).${C_RES}"
    return 0
}

if [ "${0##*/}" = "vaultwarden.sh" ]; then
    case "${1:-status}" in
        install) install_module_vaultwarden ;;
        remove)  remove_module_vaultwarden ;;
        restart) service_ctl vaultwarden restart ;;
        status)  service_ctl vaultwarden status ;;
        *)       echo "Использование: $0 [install|remove|restart|status]" ;;
    esac
fi
