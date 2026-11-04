install_module_forgejo() {
    echo "${C_CYN}[*] Установка модуля Forgejo (Git Server)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add forgejo forgejo-openrc git git-lfs gnupg sqlite; then
        echo "${C_RED}[X] Не удалось установить пакет forgejo!${C_RES}"
        return 1
    fi

    if ! id forgejo >/dev/null 2>&1; then
        addgroup -S forgejo 2>/dev/null || true
        adduser -S -D -H -h /var/lib/forgejo -s /bin/sh -G forgejo forgejo 2>/dev/null || true
    fi

    ensure_media_group_and_users
    FG_GRP=$(id -gn forgejo 2>/dev/null || echo "www-data")
    mkdir -p /var/log/forgejo /var/lib/forgejo/data /var/lib/forgejo/repos /var/lib/forgejo/custom /etc/forgejo
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
MODE = console

[service]
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW = false
FG_EOF
        chown "forgejo:${FG_GRP}" /etc/forgejo/app.ini 2>/dev/null || true
        chmod 640 /etc/forgejo/app.ini 2>/dev/null || true
    fi

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
    set_module_state "forgejo" "yes"

    echo "${C_GRN}[✓] Forgejo запущен: https://${DOM_FORGEJO} (локальный порт 127.0.0.1:${PORT_FORGEJO})${C_RES}"
    return 0
}

remove_module_forgejo() {
    service_ctl forgejo stop
    service_ctl forgejo disable
    remove_caddy_site "forgejo"
    set_module_state "forgejo" "no"
    echo "${C_GRN}[✓] Модуль Forgejo отключен (репозитории в /var/lib/forgejo сохранены).${C_RES}"
    return 0
}

# 3. Модуль Server-Code (Официальный нативный Alpine musl VS Code Web Server)
