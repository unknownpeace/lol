#!/bin/sh
# ==============================================================================
# Модуль Homelab: VS Code Web Server (Native Alpine musl)
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
    . "${GATEWAY_DIR}/modules/homelab/registry.sh"
    detect_os >/dev/null 2>&1 || true
    load_gateway_env >/dev/null 2>&1 || true
fi

install_module_code() {
    echo "${C_CYN}[*] Установка модуля Server-Code (VS Code Web Server — нативный Alpine musl)...${C_RES}"
    umask 022
    detect_os >/dev/null 2>&1 || true
    load_gateway_env >/dev/null 2>&1 || true
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

    mkdir -p /opt/code-server /var/lib/coder/.vscode-cli /var/lib/coder/.vscode-server
    if [ -L /var/lib/coder/workspace ]; then
        if [ ! -d /var/lib/coder/workspace ]; then
            echo "${C_YEL}[!] Внимание: /var/lib/coder/workspace указывает на непримонтированное хранилище.${C_RES}"
        fi
    else
        mkdir -p /var/lib/coder/workspace
    fi
    chmod 755 /opt /opt/code-server /var/lib/coder 2>/dev/null || true

    _arch_chk="${ARCH_RAW:-$(uname -m 2>/dev/null || echo x86_64)}"
    VSC_OS="cli-alpine-x64"
    if [ "$_arch_chk" = "aarch64" ] || [ "$_arch_chk" = "arm64" ]; then
        VSC_OS="cli-alpine-arm64"
    fi

    if [ ! -x /opt/code-server/code ]; then
        echo "Загрузка официального нативного musl-бинарника VS Code (${VSC_OS})..."
        ensure_gateway_runtime_dir || return 1
        VSC_TMP_DIR=$(umask 077 && mktemp -d "${GATEWAY_RUNTIME_DIR:-/run/gateway}/vsc.XXXXXX") || return 1
        _vsc_tgz="${VSC_TMP_DIR}/vscode_cli.tar.gz"
        if curl -fsSL "https://code.visualstudio.com/sha/download?build=stable&os=${VSC_OS}" -o "$_vsc_tgz" && \
           [ -s "$_vsc_tgz" ] && tar -tzf "$_vsc_tgz" >/dev/null 2>&1; then
            mkdir -p "${VSC_TMP_DIR}/extract"
            if tar -xzf "$_vsc_tgz" -C "${VSC_TMP_DIR}/extract" && [ -s "${VSC_TMP_DIR}/extract/code" ]; then
                install -m 0755 "${VSC_TMP_DIR}/extract/code" /opt/code-server/code
                rm -rf "$VSC_TMP_DIR"
            else
                rm -rf "$VSC_TMP_DIR"
                echo "${C_RED}[X] Ошибка распаковки архива VS Code (${VSC_OS})!${C_RES}"
                return 1
            fi
        else
            rm -rf "$VSC_TMP_DIR"
            echo "${C_RED}[X] Не удалось скачать нативный бинарник VS Code (${VSC_OS})!${C_RES}"
            return 1
        fi
    fi

    chown -R coder:"$MEDIA_GROUP" /var/lib/coder /opt/code-server 2>/dev/null || true
    write_storage_mount_guard_script >/dev/null 2>&1 || true

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
    /usr/lib/gateway/storage-mount-guard.sh || return 1 # GW_MOUNT_GUARD
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
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
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

# Standalone CLI execution
if [ "${0##*/}" = "code.sh" ]; then
    case "${1:-status}" in
        install)
            install_module_code
            ;;
        remove|uninstall)
            remove_module_code
            ;;
        restart)
            service_ctl code-server restart
            ;;
        status)
            rc-service code-server status 2>/dev/null || rc-status
            ;;
        *)
            echo "Использование: $0 [install|remove|restart|status]"
            exit 1
            ;;
    esac
fi
