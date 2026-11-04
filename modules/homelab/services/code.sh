install_module_code() {
    echo "${C_CYN}[*] Установка модуля Server-Code (VS Code Web Server — нативный Alpine musl)...${C_RES}"
    umask 022
    if [ "${TOTAL_RAM_MB:-512}" -lt 1000 ]; then
        echo "${C_YEL}[!] Внимание: Для комфортной работы VS Code Web IDE рекомендуется от 1.5–2 ГБ RAM (сейчас ${TOTAL_RAM_MB} МБ).${C_RES}"
    fi
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    apk add libstdc++ bash git curl python3 >/dev/null 2>&1 || true

    ensure_media_group_and_users
    if ! id coder >/dev/null 2>&1; then
        adduser -D -h /var/lib/coder -s /bin/bash -G "$MEDIA_GROUP" coder 2>/dev/null || \
        adduser -D -h /var/lib/coder -s /bin/sh coder 2>/dev/null || true
    fi
    addgroup coder "$MEDIA_GROUP" 2>/dev/null || true

    mkdir -p /opt/code-server /var/lib/coder/.vscode-cli /var/lib/coder/.vscode-server /var/lib/coder/workspace
    chmod 755 /opt /opt/code-server /var/lib/coder 2>/dev/null || true

    VSC_OS="cli-alpine-x64"
    if [ "$ARCH_RAW" = "aarch64" ] || [ "$ARCH_RAW" = "arm64" ]; then
        VSC_OS="cli-alpine-arm64"
    fi

    if [ ! -x /opt/code-server/code ]; then
        echo "Загрузка официального нативного musl-бинарника VS Code (${VSC_OS})..."
        rm -f /tmp/vscode_cli_alpine.tar.gz
        if curl -fsSL "https://code.visualstudio.com/sha/download?build=stable&os=${VSC_OS}" -o /tmp/vscode_cli_alpine.tar.gz; then
            tar -xzf /tmp/vscode_cli_alpine.tar.gz -C /opt/code-server
            chmod 755 /opt/code-server/code
            rm -f /tmp/vscode_cli_alpine.tar.gz
        else
            rm -f /tmp/vscode_cli_alpine.tar.gz
            echo "${C_RED}[X] Не удалось скачать нативный бинарник VS Code (${VSC_OS})!${C_RES}"
            return 1
        fi
    fi

    chown -R coder:"$MEDIA_GROUP" /var/lib/coder /opt/code-server 2>/dev/null || true

    cat << CS_INIT > /etc/init.d/code-server
#!/sbin/openrc-run
name="code-server"
description="VS Code Web IDE (Native Alpine musl)"
supervisor="supervise-daemon"
command="/opt/code-server/code"
command_args="serve-web --host 127.0.0.1 --port ${PORT_CODE} --without-connection-token --accept-server-license-terms --cli-data-dir /var/lib/coder/.vscode-cli --server-data-dir /var/lib/coder/.vscode-server"
command_user="coder:${MEDIA_GROUP}"
output_log="/var/log/code-server.log"
error_log="/var/log/code-server.log"
rc_oom_score_adj="200"
export HOME="/var/lib/coder"

depend() {
    need net
}

start_pre() {
    checkpath -f -m 0644 -o coder:${MEDIA_GROUP} /var/log/code-server.log
    checkpath -d -m 0755 -o coder:${MEDIA_GROUP} /var/lib/coder/.vscode-cli /var/lib/coder/.vscode-server
}
CS_INIT
    chmod +x /etc/init.d/code-server

    service_ctl code-server enable
    if ! service_ctl code-server restart; then
        echo "${C_RED}[X] Служба code-server не смогла запуститься!${C_RES}"
        return 1
    fi
    register_caddy_site "code" "$DOM_CODE" "$PORT_CODE" "yes"
    set_module_state "code" "yes"

    echo "${C_GRN}[✓] Server-Code (VS Code) запущен: https://${DOM_CODE} (Логин: ${SMB_USER:-admin} / Пароль: единый пароль шлюза)${C_RES}"
    return 0
}

remove_module_code() {
    service_ctl code-server stop
    service_ctl code-server disable
    remove_caddy_site "code"
    set_module_state "code" "no"
    echo "${C_GRN}[✓] Модуль Server-Code отключен (проекты в /var/lib/coder/workspace сохранены).${C_RES}"
    return 0
}

# 4. Модуль Navidrome (Специализированный музыкальный сервер Subsonic/OpenSubsonic с чтением /srv/storage/Music)
