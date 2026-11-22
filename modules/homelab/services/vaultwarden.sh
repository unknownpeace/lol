#!/bin/sh

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
    . "${GATEWAY_DIR}/modules/adguard/adguard.sh"
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

# Неинтерактивное хэширование ADMIN_TOKEN через `vaultwarden hash --preset owasp` (Argon2id PHC)
_hash_vaultwarden_admin_token() {
    _raw_pw="$1"
    [ -z "$_raw_pw" ] && return 1
    _phc=""

    if [ -x /usr/bin/vaultwarden ] && command -v python3 >/dev/null 2>&1; then
        _phc=$(_VW_PASS="$_raw_pw" python3 - << 'PY_VW_HASH' 2>/dev/null || true
import os, pty, re, select, subprocess, time

pw = os.environ.get("_VW_PASS", "")
master, slave = pty.openpty()
proc = subprocess.Popen(
    ["/usr/bin/vaultwarden", "hash", "--preset", "owasp"],
    stdin=slave, stdout=slave, stderr=slave, close_fds=True
)
os.close(slave)
buf = b""
sent = 0
deadline = time.time() + 10.0
try:
    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 0.25)
        if r:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            low = buf.lower()
            if sent == 0 and b"password" in low:
                os.write(master, (pw + "\n").encode("utf-8"))
                sent = 1
            elif sent == 1 and (b"confirm" in low or low.count(b"password") >= 2):
                os.write(master, (pw + "\n").encode("utf-8"))
                sent = 2
        elif proc.poll() is not None:
            break
finally:
    try:
        os.close(master)
    except OSError:
        pass
    if proc.poll() is None:
        proc.kill()
    proc.wait()

txt = buf.decode("utf-8", "ignore")
m = re.search(r'(\$argon2(?:id|i|d)\$[^\s\'"\r\n]+)', txt)
if m:
    print(m.group(1), end="")
PY_VW_HASH
        )
    fi

    if [ -z "$_phc" ] && [ -x /usr/bin/vaultwarden ]; then
        _out=$(printf "%s\n%s\n" "$_raw_pw" "$_raw_pw" | timeout 5 /usr/bin/vaultwarden hash --preset owasp 2>/dev/null || true)
        _phc=$(printf "%s" "$_out" | grep -Eo '\$argon2(id|i|d)\$[^[:space:]'\''"]+' | head -n 1 || true)
    fi

    if [ -z "$_phc" ] && command -v argon2 >/dev/null 2>&1; then
        _salt=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -dc '0-9a-f' | head -c 24 || true)
        if [ -n "$_salt" ]; then
            _phc=$(printf "%s" "$_raw_pw" | argon2 "$_salt" -e -id -k 19456 -t 2 -p 1 2>/dev/null | tr -d ' \t\r\n' || true)
        fi
    fi

    case "$_phc" in
        \$argon2*)
            printf "%s" "$_phc"
            return 0
            ;;
    esac
    return 1
}

# Синхронизация эталонной конфигурации Vaultwarden (/etc/conf.d/vaultwarden + /var/lib/vaultwarden/.env)
sync_vaultwarden_config() {
    load_gateway_env
    ensure_media_group_and_users

    mkdir -p /var/lib/vaultwarden/attachments /var/lib/vaultwarden/sends /var/lib/vaultwarden/icon_cache /var/lib/vaultwarden/tmp
    WEB_VAULT_DIR=$(detect_vaultwarden_web_dir || true)

    VW_EXT_DOM="${DOM_VAULTWARDEN}"
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        VW_EXT_DOM="vaultwarden.${SSL_DOMAIN}"
    fi

    RAW_VW_PASS="${ADMIN_PASS:-admin}"
    VW_ADMIN_VAL=$(_hash_vaultwarden_admin_token "$RAW_VW_PASS" || true)
    if [ -z "$VW_ADMIN_VAL" ]; then
        echo "${C_YEL}[!] Предупреждение: Argon2-хэширование ADMIN_TOKEN недоступно, используется исходное значение.${C_RES}" >&2
        VW_ADMIN_VAL="$RAW_VW_PASS"
    fi

    ESC_VW_SH=$(escape_single_quotes "$VW_ADMIN_VAL")
    case "$VW_ADMIN_VAL" in
        *\'*)
            # Экранирование для dotenv (double-quoted) без shell-конструкции '\\''
            _dot_esc=$(printf "%s" "$VW_ADMIN_VAL" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g')
            DOTENV_ADMIN_LINE="ADMIN_TOKEN=\"${_dot_esc}\""
            ;;
        *)
            DOTENV_ADMIN_LINE="ADMIN_TOKEN='${VW_ADMIN_VAL}'"
            ;;
    esac

    umask 077
    cat << VW_EOF > /etc/conf.d/vaultwarden
# Конфигурация Vaultwarden (Alpine Homelab Edition)
export DATA_FOLDER="/var/lib/vaultwarden"
export DATABASE_URL="sqlite:///var/lib/vaultwarden/db.sqlite3"
export ENABLE_DB_WAL="true"
export ROCKET_ADDRESS="127.0.0.1"
export ROCKET_PORT="${PORT_VAULTWARDEN}"
export DOMAIN="https://${VW_EXT_DOM}"
export WEB_VAULT_ENABLED="true"
export WEB_VAULT_FOLDER="${WEB_VAULT_DIR}"
export SIGNUPS_ALLOWED="false"
export WEBSOCKET_ENABLED="true"
export IP_HEADER="X-Real-IP"
export EXTENDED_LOGGING="true"
export LOG_LEVEL="info"
export LOG_FILE="/var/log/vaultwarden.log"
export ADMIN_TOKEN='${ESC_VW_SH}'
VW_EOF
    chown root:vaultwarden /etc/conf.d/vaultwarden 2>/dev/null || true
    chmod 640 /etc/conf.d/vaultwarden 2>/dev/null || true

    cat << VW_DOTENV > /var/lib/vaultwarden/.env
DATA_FOLDER="/var/lib/vaultwarden"
DATABASE_URL="sqlite:///var/lib/vaultwarden/db.sqlite3"
ENABLE_DB_WAL="true"
ROCKET_ADDRESS="127.0.0.1"
ROCKET_PORT="${PORT_VAULTWARDEN}"
DOMAIN="https://${VW_EXT_DOM}"
WEB_VAULT_ENABLED="true"
WEB_VAULT_FOLDER="${WEB_VAULT_DIR}"
SIGNUPS_ALLOWED="false"
WEBSOCKET_ENABLED="true"
IP_HEADER="X-Real-IP"
EXTENDED_LOGGING="true"
LOG_LEVEL="info"
LOG_FILE="/var/log/vaultwarden.log"
${DOTENV_ADMIN_LINE}
VW_DOTENV
    chown vaultwarden:vaultwarden /var/lib/vaultwarden/.env 2>/dev/null || true
    chmod 600 /var/lib/vaultwarden/.env 2>/dev/null || true
    umask 022

    if [ -f /var/lib/vaultwarden/config.json ] && command -v jq >/dev/null 2>&1; then
        jq --arg dom "https://${VW_EXT_DOM}" --arg adm "$VW_ADMIN_VAL" \
           '.domain = $dom | .web_vault_enabled = true | .signups_allowed = false | .admin_token = $adm' \
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
    if [ -n "$CUR_LIP_VW" ]; then
        _vw_hosts="${DOM_VAULTWARDEN}"
        [ "$VW_EXT_DOM" != "$DOM_VAULTWARDEN" ] && _vw_hosts="${_vw_hosts} ${VW_EXT_DOM}"
        [ -n "${DOM_CA:-}" ] && _vw_hosts="${_vw_hosts} ${DOM_CA}"
        _hosts_tmp=$(mktemp "/etc/hosts.gw.XXXXXX" 2>/dev/null) || _hosts_tmp="/etc/hosts.tmp.$$"
        awk -v dw="$DOM_VAULTWARDEN" -v de="$VW_EXT_DOM" -v dc="${DOM_CA:-ca.lan}" '
            /^#/ || NF < 2 { print; next }
            {
                keep = 1
                for (i = 2; i <= NF; i++) {
                    if ($i == dw || $i == de || $i == dc) { keep = 0; break }
                }
                if (keep) print
            }
        ' /etc/hosts > "$_hosts_tmp" 2>/dev/null || : > "$_hosts_tmp"
        printf "%s\t%s\n" "$CUR_LIP_VW" "$_vw_hosts" >> "$_hosts_tmp"
        chmod 644 "$_hosts_tmp" 2>/dev/null || true
        mv -f "$_hosts_tmp" /etc/hosts 2>/dev/null || rm -f "$_hosts_tmp" 2>/dev/null || true
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
    apk add --no-cache argon2 >/dev/null 2>&1 || true

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

    VW_SHOW_DOM="${DOM_VAULTWARDEN}"
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        VW_SHOW_DOM="vaultwarden.${SSL_DOMAIN}"
    fi
    echo "${C_GRN}[✓] Vaultwarden запущен: https://${VW_SHOW_DOM} (Админ-панель: https://${VW_SHOW_DOM}/admin)${C_RES}"
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
