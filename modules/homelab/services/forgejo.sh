#!/bin/sh

# ==============================================================================
# Модуль Forgejo (Легковесный Git-сервер)
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

# Проверка минимально безопасной версии Forgejo (>= 15.0.8, CVE-2026-89094)
check_forgejo_min_version() {
    command -v forgejo >/dev/null 2>&1 || return 1
    _fg_ver=$(forgejo --version 2>/dev/null | sed -n 's/.*version[[:space:]]\{1,\}\([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)
    [ -z "$_fg_ver" ] && return 0
    if command -v version_ge >/dev/null 2>&1; then
        if ! version_ge "$_fg_ver" "15.0.8"; then
            echo "${C_YEL}[!] ВНИМАНИЕ: Установлена версия Forgejo ${_fg_ver} (< 15.0.8, уязвимость CVE-2026-89094). Выполните apk upgrade forgejo с актуального репозитория Alpine!${C_RES}"
            return 1
        fi
    fi
    return 0
}

# Синхронизация DOMAIN, ROOT_URL и файлового логирования в /etc/forgejo/app.ini
sync_forgejo_domain_config() {
    load_gateway_env >/dev/null 2>&1 || true
    [ -f /etc/forgejo/app.ini ] || return 0
    FG_EXT_DOM="${DOM_FORGEJO}"
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        FG_EXT_DOM="forgejo.${SSL_DOMAIN}"
    fi
    FG_GRP=$(id -gn forgejo 2>/dev/null || echo "www-data")
    awk -v dom="$FG_EXT_DOM" '
        /^DOMAIN[[:space:]]*=/ { print "DOMAIN = " dom; next }
        /^ROOT_URL[[:space:]]*=/ { print "ROOT_URL = https://" dom "/"; next }
        /^MODE[[:space:]]*=[[:space:]]*console[[:space:]]*$/ { print "MODE = file"; next }
        { print }
    ' /etc/forgejo/app.ini > /etc/forgejo/app.ini.tmp.$$ && \
        mv -f /etc/forgejo/app.ini.tmp.$$ /etc/forgejo/app.ini
    mkdir -p /var/log/forgejo 2>/dev/null || true
    touch /var/log/forgejo/forgejo.log 2>/dev/null || true
    chown "forgejo:${FG_GRP}" /etc/forgejo/app.ini /var/log/forgejo/forgejo.log 2>/dev/null || true
    chmod 640 /etc/forgejo/app.ini /var/log/forgejo/forgejo.log 2>/dev/null || true
    return 0
}

install_module_forgejo() {
    echo "${C_CYN}[*] Установка модуля Forgejo (Git Server)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add --upgrade forgejo forgejo-openrc git git-lfs gnupg sqlite; then
        echo "${C_RED}[X] Не удалось установить пакет forgejo!${C_RES}"
        return 1
    fi
    check_forgejo_min_version || true

    if ! id forgejo >/dev/null 2>&1; then
        addgroup -S forgejo 2>/dev/null || true
        adduser -S -D -H -h /var/lib/forgejo -s /bin/sh -G forgejo forgejo 2>/dev/null || true
    fi

    ensure_media_group_and_users
    FG_GRP=$(id -gn forgejo 2>/dev/null || echo "www-data")
    mkdir -p /var/log/forgejo /var/lib/forgejo/data /var/lib/forgejo/custom /etc/forgejo
    [ -L /var/lib/forgejo/repos ] || mkdir -p /var/lib/forgejo/repos
    chown -R "forgejo:${FG_GRP}" /var/lib/forgejo /var/log/forgejo /etc/forgejo 2>/dev/null || true
    chmod 750 /var/lib/forgejo /var/log/forgejo /etc/forgejo 2>/dev/null || true

    if [ ! -s /etc/forgejo/app.ini ] || ! grep -q "^HTTP_PORT = ${PORT_FORGEJO}" /etc/forgejo/app.ini 2>/dev/null || grep -q "INSTALL_LOCK = false" /etc/forgejo/app.ini 2>/dev/null; then
        FG_SEC=$(su -s /bin/sh forgejo -c "forgejo generate secret SECRET_KEY" 2>/dev/null || od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
        FG_TOK=$(su -s /bin/sh forgejo -c "forgejo generate secret INTERNAL_TOKEN" 2>/dev/null || od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
        cat << FG_EOF > /etc/forgejo/app.ini
APP_NAME = Alpine Homelab Git (Forgejo)
RUN_USER = forgejo
RUN_MODE = prod
WORK_PATH = /var/lib/forgejo

[repository]
ROOT = /var/lib/forgejo/repos

[database]
DB_TYPE = sqlite3
PATH = /var/lib/forgejo/data/forgejo.db

[server]
PROTOCOL = http
DOMAIN = ${DOM_FORGEJO}
ROOT_URL = https://${DOM_FORGEJO}/
HTTP_ADDR = 127.0.0.1
HTTP_PORT = ${PORT_FORGEJO}
DISABLE_SSH = false
SSH_PORT = 22
LFS_START_SERVER = true

[security]
INSTALL_LOCK = true
SECRET_KEY = ${FG_SEC}
INTERNAL_TOKEN = ${FG_TOK}

[log]
ROOT_PATH = /var/log/forgejo
MODE = file
LEVEL = info

[service]
DISABLE_REGISTRATION = true
REQUIRE_SIGNIN_VIEW = false
FG_EOF
        chown "forgejo:${FG_GRP}" /etc/forgejo/app.ini 2>/dev/null || true
        chmod 640 /etc/forgejo/app.ini 2>/dev/null || true
    fi

    sync_forgejo_domain_config
    ensure_openrc_mount_guard "forgejo" >/dev/null 2>&1 || true

    su -s /bin/sh forgejo -c "/usr/bin/forgejo migrate --config /etc/forgejo/app.ini" >/dev/null 2>&1 || true
    service_ctl forgejo enable
    if ! service_ctl forgejo restart; then
        echo "${C_RED}[X] Служба Forgejo не смогла запуститься!${C_RES}"
        return 1
    fi
    W_FG=0
    while [ "$W_FG" -lt 10 ]; do
        curl -sS -o /dev/null --connect-timeout 1 -m 2 "http://127.0.0.1:${PORT_FORGEJO}" 2>/dev/null && break
        sleep 1
        W_FG=$((W_FG + 1))
    done
    register_caddy_site "forgejo" "$DOM_FORGEJO" "$PORT_FORGEJO" "no"
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
    set_module_state "forgejo" "yes"

    FG_SHOW_DOM="${DOM_FORGEJO}"
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        FG_SHOW_DOM="forgejo.${SSL_DOMAIN}"
    fi
    echo "${C_GRN}[✓] Forgejo запущен: https://${FG_SHOW_DOM} (локальный порт 127.0.0.1:${PORT_FORGEJO})${C_RES}"
    return 0
}

remove_module_forgejo() {
    service_ctl forgejo stop || true
    service_ctl forgejo disable || true
    remove_caddy_site "forgejo"
    set_module_state "forgejo" "no"
    echo "${C_GRN}[✓] Модуль Forgejo отключен (репозитории в /var/lib/forgejo сохранены).${C_RES}"
    return 0
}

if [ "${0##*/}" = "forgejo.sh" ]; then
    case "${1:-status}" in
        install) install_module_forgejo ;;
        update)  apk upgrade forgejo forgejo-openrc && sync_forgejo_domain_config && check_forgejo_min_version ;;
        remove)  remove_module_forgejo ;;
        restart) service_ctl forgejo restart ;;
        status)  service_ctl forgejo status ;;
        *)       echo "Использование: $0 [install|update|remove|restart|status]" ;;
    esac
fi
