install_singbox_binary() {
    detect_os
    check_github_mirror

    SB_TAG=$(fetch_latest_github_tag "shtorm-7/sing-box-extended")
    case "$SB_TAG" in v*) ;; *) SB_TAG="v1.14.3-extended-2.7.3" ;; esac
    LATEST_SB_TAG="$SB_TAG"
    SB_VER_NO_V="${SB_TAG#v}"

    INSTALLED_SB_VER=""
    if [ -x /usr/bin/sing-box ]; then
        RAW_V=$(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        [ -n "$RAW_V" ] && INSTALLED_SB_VER="v${RAW_V#v}" || true
    fi

    if [ "$INSTALLED_SB_VER" = "$SB_TAG" ]; then
        echo "${C_GRN}[✓] Ядро Sing-Box Extended ${INSTALLED_SB_VER} (${SB_ARCH}) актуально.${C_RES}"
        return 0
    fi

    echo "Загрузка Sing-Box Extended ${SB_TAG} (${SB_ARCH})..."
    rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
    SB_ASSET="sing-box-${SB_VER_NO_V}-linux-${SB_ARCH}.tar.gz"
    SB_URL="https://github.com/shtorm-7/sing-box-extended/releases/download/${SB_TAG}/${SB_ASSET}"
    if download_file "$SB_URL" "/tmp/sing-box.tar.gz" && verify_github_asset_sha256 "shtorm-7/sing-box-extended" "$SB_ASSET" "/tmp/sing-box.tar.gz"; then
        mkdir -p /tmp/sb_extract
        if tar -xzf /tmp/sing-box.tar.gz -C /tmp/sb_extract 2>/dev/null; then
            SB_BIN=$(find /tmp/sb_extract -type f -name "sing-box" | head -n 1)
            if [ -n "$SB_BIN" ] && [ -f "$SB_BIN" ]; then
                chmod +x "$SB_BIN"
                if "$SB_BIN" version >/dev/null 2>&1; then
                    service_ctl sing-box stop
                    mv -f "$SB_BIN" /usr/bin/sing-box
                    rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
                    echo "${C_GRN}[✓] Sing-Box Extended безопасно обновлен до ${SB_TAG}.${C_RES}"
                    return 0
                else
                    echo "${C_RED}[X] Ошибка: скачанный бинарник sing-box поврежден, оставлена текущая версия.${C_RES}"
                fi
            fi
        fi
    else
        echo "${C_RED}[X] Не удалось скачать Sing-Box Extended ${SB_TAG}.${C_RES}"
    fi
    rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
    [ -x /usr/bin/sing-box ] && return 0 || return 1
}

# Криптографическая проверка SHA-256 скачанного архива через GitHub Releases API
verify_github_asset_sha256() {
    REPO_NAME="$1"
    ASSET_NAME="$2"
    LOCAL_FILE="$3"
    command -v sha256sum >/dev/null 2>&1 || return 0
    command -v jq >/dev/null 2>&1 || return 0

    REL_JSON=$(curl -fsSL --curves X25519:P-256 --connect-timeout 3 -m 5 "https://api.github.com/repos/${REPO_NAME}/releases/latest" 2>/dev/null || true)
    [ -z "$REL_JSON" ] && return 0

    EXP_DIGEST=$(printf "%s" "$REL_JSON" | jq -r --arg name "$ASSET_NAME" '.assets[]? | select(.name == $name) | .digest // empty' 2>/dev/null | sed 's/^sha256://' | tr -d ' \t\r\n')
    [ -z "$EXP_DIGEST" ] && return 0

    ACT_DIGEST=$(sha256sum "$LOCAL_FILE" 2>/dev/null | awk '{print $1}' | tr -d ' \t\r\n')
    if [ -n "$ACT_DIGEST" ] && [ "$ACT_DIGEST" != "$EXP_DIGEST" ]; then
        echo "${C_RED}[X] КРИТИЧЕСКАЯ ОШИБКА БЕЗОПАСНОСТИ: Несовпадение SHA-256 для ${ASSET_NAME}!${C_RES}" >&2
        echo "    Ожидался: ${EXP_DIGEST}" >&2
        echo "    Получен:  ${ACT_DIGEST}" >&2
        return 1
    fi
    return 0
}

# Атомарное обновление активного ядра (Sing-Box Extended / Mihomo), AdGuard Home и выбранной веб-панели (SHA-256)
update_cores_only() {
    CHECK_UI_UPDATE="${1:-no}"
    detect_os
    check_github_mirror
    load_gateway_env

    if [ "$(get_active_core)" = "mihomo" ]; then
        install_mihomo_binary || true
    else
        install_singbox_binary || true
    fi

    AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
    case "$AGH_TAG" in v*) ;; *) AGH_TAG="v1.0.0" ;; esac
    LATEST_AGH_TAG="$AGH_TAG"
    INSTALLED_AGH_VER=""
    if [ -x /usr/bin/AdGuardHome ]; then
        INSTALLED_AGH_VER=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)
    fi

    if [ "$INSTALLED_AGH_VER" = "$AGH_TAG" ]; then
        echo "${C_GRN}[✓] Ядро AdGuard Home ${INSTALLED_AGH_VER} актуально.${C_RES}"
    else
        echo "Загрузка AdGuard Home ${AGH_TAG}..."
        rm -rf /tmp/agh.tar.gz /tmp/agh_extract
        AGH_ASSET="AdGuardHome_linux_${AGH_ARCH}.tar.gz"
        AGH_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_TAG}/${AGH_ASSET}"
        if download_file "$AGH_URL" "/tmp/agh.tar.gz" && verify_github_asset_sha256 "AdguardTeam/AdGuardHome" "$AGH_ASSET" "/tmp/agh.tar.gz"; then
            mkdir -p /tmp/agh_extract
            if tar -xzf /tmp/agh.tar.gz -C /tmp/agh_extract 2>/dev/null && [ -f /tmp/agh_extract/AdGuardHome/AdGuardHome ]; then
                chmod +x /tmp/agh_extract/AdGuardHome/AdGuardHome
                if /tmp/agh_extract/AdGuardHome/AdGuardHome --version >/dev/null 2>&1; then
                    service_ctl adguardhome stop
                    mv -f /tmp/agh_extract/AdGuardHome/AdGuardHome /usr/bin/AdGuardHome
                    echo "${C_GRN}[✓] AdGuard Home безопасно обновлен до ${AGH_TAG}.${C_RES}"
                else
                    echo "${C_RED}[X] Ошибка проверки бинарника AdGuard Home, оставлена текущая версия.${C_RES}"
                fi
            fi
            rm -rf /tmp/agh.tar.gz /tmp/agh_extract
        else
            rm -rf /tmp/agh.tar.gz /tmp/agh_extract
            echo "${C_RED}[X] Не удалось скачать AdGuard Home ${AGH_TAG}.${C_RES}"
        fi
    fi

    if [ "$CHECK_UI_UPDATE" = "yes" ]; then
        CUR_UI_T=$(get_active_ui)
        CUR_UI_N=$(get_active_ui_name)
        if [ "$CUR_UI_T" = "metacubexd" ]; then
            UI_TAG=$(fetch_latest_github_tag "$METACUBEXD_REPO")
            case "$UI_TAG" in v*) ;; *) UI_TAG="v1.275.2" ;; esac
        else
            UI_TAG=$(fetch_latest_github_tag "$ZASHBOARD_REPO")
            case "$UI_TAG" in v*) ;; *) UI_TAG="v3.30.0" ;; esac
        fi
        LATEST_UI_TAG="$UI_TAG"
        INSTALLED_UI_VER=""
        INSTALLED_UI_TYPE=""
        [ -f "$UI_VER_FILE" ] && INSTALLED_UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n') || true
        [ -f "$UI_TYPE_FILE" ] && INSTALLED_UI_TYPE=$(cat "$UI_TYPE_FILE" 2>/dev/null | tr -d ' \t\r\n') || true

        if [ -f "${UI_DIR}/index.html" ] && [ "$INSTALLED_UI_TYPE" = "$CUR_UI_T" ] && [ -n "$UI_TAG" ] && [ "$INSTALLED_UI_VER" = "$UI_TAG" ]; then
            echo "${C_GRN}[✓] Веб-панель ${CUR_UI_N} ${INSTALLED_UI_VER} актуальна.${C_RES}"
        else
            install_web_ui "$CUR_UI_T" "$UI_TAG" || true
        fi
    fi

    cat << VC_EOF > "$VER_CACHE_FILE" 2>/dev/null || true
LATEST_SB_TAG='${LATEST_SB_TAG}'
LATEST_MIHOMO_TAG='${LATEST_MIHOMO_TAG}'
LATEST_AGH_TAG='${LATEST_AGH_TAG}'
LATEST_UI_TAG='${LATEST_UI_TAG}'
VC_EOF
    return 0
}

# Создание системных служб автозапуска Alpine OpenRC (с защитой сетевого шлюза от OOM-killer)
setup_init_scripts() {
    calc_hardware_limits
    load_gateway_env || true
    ACT_CORE_S=$(get_active_core)

    cat << INIT_SB_ALP > /etc/init.d/sing-box
#!/sbin/openrc-run
name="sing-box"
description="Sing-Box Extended Gateway"
supervisor="supervise-daemon"
command="/usr/bin/sing-box"
command_args="run -c /etc/sing-box/config.json -D /etc/sing-box"
output_log="${SB_LOG_FILE}"
error_log="${SB_LOG_FILE}"
rc_ulimit="-n 65535"
rc_oom_score_adj="-500"
respawn_delay=3
respawn_max=10
retry="TERM/10/KILL/5"
export GOGC=50
export GOMEMLIMIT=${SB_GOMEMLIMIT}

depend() {
    need net
    after nftables
}

start_pre() {
    mkdir -p /dev/net
    [ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null || true
    : > "${SB_LOG_FILE}" 2>/dev/null || true
}
INIT_SB_ALP
    chmod +x /etc/init.d/sing-box

    setup_mihomo_init_script

    if [ "$ACT_CORE_S" = "mihomo" ]; then
        AFTER_CORE="mihomo"
    else
        AFTER_CORE="sing-box"
    fi

    cat << INIT_AGH_ALP > /etc/init.d/adguardhome
#!/sbin/openrc-run
name="adguardhome"
description="AdGuard Home DNS Filter"
supervisor="supervise-daemon"
command="/usr/bin/AdGuardHome"
command_args="-c /etc/AdGuardHome/AdGuardHome.yaml -w /etc/AdGuardHome --no-check-update"
rc_ulimit="-n 65535"
rc_oom_score_adj="-500"
respawn_delay=3
respawn_max=10
retry="TERM/10/KILL/5"
export GOGC=50
export GOMEMLIMIT=${AGH_GOMEMLIMIT}

depend() {
    need net
    after ${AFTER_CORE}
}
INIT_AGH_ALP
    chmod +x /etc/init.d/adguardhome

    if [ "$ACT_CORE_S" = "mihomo" ]; then
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
    sleep 2
    service_ctl adguardhome enable
    service_ctl adguardhome restart

    mkdir -p /etc/local.d
    cat << 'BOOT_GUARD_EOF' > /etc/local.d/50-gateway-boot-guard.start
#!/bin/sh
# Немедленный запуск протокола восстановления после загрузки (питание, LUKS2, сеть)
[ -x /usr/bin/gateway ] && /usr/bin/gateway watchdog >/dev/null 2>&1 &
BOOT_GUARD_EOF
    chmod +x /etc/local.d/50-gateway-boot-guard.start 2>/dev/null || true
    rc-update add local default >/dev/null 2>&1 || true
    return 0
}

# ==============================================================================
# Ядро подсистемы Homelab: Реестр модулей, Единое хранилище /srv/storage,
# Центральный HTTPS/PKI прокси Caddy (*.lan) и Файловый сервер Samba (WSDD+Avahi)
# ==============================================================================

# Активация официального репозитория community в Alpine Linux
