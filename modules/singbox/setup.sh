#!/bin/sh
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
    ensure_gateway_runtime_dir || return 1
    _sb_stage=$(mktemp -d "${GATEWAY_RUNTIME_DIR:-/run/gateway}/sb.XXXXXX" 2>/dev/null) || return 1
    chmod 700 "$_sb_stage" 2>/dev/null || true
    SB_ASSET="sing-box-${SB_VER_NO_V}-linux-${SB_ARCH}.tar.gz"
    SB_URL="https://github.com/shtorm-7/sing-box-extended/releases/download/${SB_TAG}/${SB_ASSET}"
    if download_file "$SB_URL" "${_sb_stage}/sing-box.tar.gz" && verify_github_asset_sha256 "shtorm-7/sing-box-extended" "$SB_ASSET" "${_sb_stage}/sing-box.tar.gz" "$SB_TAG"; then
        mkdir -p "${_sb_stage}/extract"
        if tar -xzf "${_sb_stage}/sing-box.tar.gz" -C "${_sb_stage}/extract" 2>/dev/null; then
            SB_BIN=$(find "${_sb_stage}/extract" -type f -name "sing-box" | head -n 1)
            if [ -n "$SB_BIN" ] && [ -f "$SB_BIN" ]; then
                chmod +x "$SB_BIN"
                if "$SB_BIN" version >/dev/null 2>&1; then
                    service_ctl sing-box stop
                    mv -f "$SB_BIN" /usr/bin/sing-box
                    rm -rf "$_sb_stage"
                    echo "${C_GRN}[✓] Sing-Box Extended безопасно обновлен до ${SB_TAG}.${C_RES}"
                    return 0
                else
                    echo "${C_RED}[X] Ошибка: скачанный бинарник sing-box поврежден, оставлена текущая версия.${C_RES}"
                fi
            fi
        fi
    else
        echo "${C_RED}[X] Не удалось скачать или верифицировать Sing-Box Extended ${SB_TAG}.${C_RES}"
    fi
    rm -rf "$_sb_stage"
    [ -x /usr/bin/sing-box ] && return 0 || return 1
}

# Криптографическая проверка SHA-256 скачанного архива через GitHub Releases API (fail-closed для зеркал)
verify_github_asset_sha256() {
    REPO_NAME="$1"
    ASSET_NAME="$2"
    LOCAL_FILE="$3"
    TAG_NAME="${4:-}"
    _from_mirror="${LAST_DOWNLOAD_VIA_MIRROR:-no}"

    if ! command -v sha256sum >/dev/null 2>&1; then
        if [ "$_from_mirror" = "yes" ]; then
            echo "${C_RED}[X] КРИТИЧЕСКАЯ ОШИБКА: Отсутствует sha256sum — загрузка с зеркала без проверки отклонена!${C_RES}" >&2
            return 1
        fi
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        if [ "$_from_mirror" = "yes" ]; then
            echo "${C_RED}[X] КРИТИЧЕСКАЯ ОШИБКА: Отсутствует jq — загрузка с зеркала без проверки SHA-256 отклонена!${C_RES}" >&2
            return 1
        fi
        return 0
    fi

    if [ -n "$TAG_NAME" ]; then
        _api_url="https://api.github.com/repos/${REPO_NAME}/releases/tags/${TAG_NAME}"
    else
        _api_url="https://api.github.com/repos/${REPO_NAME}/releases/latest"
    fi

    REL_JSON=$(gw_curl -fsSL --connect-timeout 3 -m 6 "$_api_url" 2>/dev/null || true)
    EXP_DIGEST=""
    if [ -n "$REL_JSON" ]; then
        EXP_DIGEST=$(printf "%s" "$REL_JSON" | jq -r --arg name "$ASSET_NAME" '.assets[]? | select(.name == $name) | .digest // empty' 2>/dev/null | sed 's/^sha256://' | tr -d ' \t\r\n')
    fi

    if [ -z "$EXP_DIGEST" ] && [ -n "$TAG_NAME" ]; then
        for _cs_name in checksums.txt SHA256SUMS sha256sums.txt "${ASSET_NAME}.sha256"; do
            _cs_txt=$(gw_curl -fsSL --connect-timeout 3 -m 6 "https://github.com/${REPO_NAME}/releases/download/${TAG_NAME}/${_cs_name}" 2>/dev/null || true)
            if [ -n "$_cs_txt" ]; then
                EXP_DIGEST=$(printf "%s\n" "$_cs_txt" | awk -v a="$ASSET_NAME" '
                    $2 == a || $2 == ("*" a) || $2 ~ ("/" a "$") { print $1; exit }
                    NF == 1 && /^[0-9a-fA-F]{64}$/ { print $1; exit }
                ' | tr -d ' \t\r\n')
                [ -n "$EXP_DIGEST" ] && break
            fi
        done
    fi

    if [ -z "$EXP_DIGEST" ]; then
        if [ "$_from_mirror" = "yes" ]; then
            echo "${C_RED}[X] КРИТИЧЕСКАЯ ОШИБКА БЕЗОПАСНОСТИ: Не удалось получить эталонный SHA-256 для ${ASSET_NAME} при загрузке через стороннее зеркало!${C_RES}" >&2
            return 1
        fi
        if [ -n "$REL_JSON" ]; then
            echo "${C_RED}[X] Ошибка верификации: В релизе GitHub отсутствует SHA-256 дайджест для ${ASSET_NAME}!${C_RES}" >&2
            return 1
        fi
        return 0
    fi

    ACT_DIGEST=$(sha256sum "$LOCAL_FILE" 2>/dev/null | awk '{print $1}' | tr -d ' \t\r\n')
    if [ -z "$ACT_DIGEST" ] || [ "$ACT_DIGEST" != "$EXP_DIGEST" ]; then
        echo "${C_RED}[X] КРИТИЧЕСКАЯ ОШИБКА БЕЗОПАСНОСТИ: Несовпадение SHA-256 для ${ASSET_NAME}!${C_RES}" >&2
        echo "    Ожидался: ${EXP_DIGEST}" >&2
        echo "    Получен:  ${ACT_DIGEST:-<пусто>}" >&2
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
        ensure_gateway_runtime_dir || return 1
        _agh_stage=$(mktemp -d "${GATEWAY_RUNTIME_DIR:-/run/gateway}/agh.XXXXXX" 2>/dev/null) || return 1
        chmod 700 "$_agh_stage" 2>/dev/null || true
        AGH_ASSET="AdGuardHome_linux_${AGH_ARCH}.tar.gz"
        AGH_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_TAG}/${AGH_ASSET}"
        if download_file "$AGH_URL" "${_agh_stage}/agh.tar.gz" && verify_github_asset_sha256 "AdguardTeam/AdGuardHome" "$AGH_ASSET" "${_agh_stage}/agh.tar.gz" "$AGH_TAG"; then
            mkdir -p "${_agh_stage}/extract"
            if tar -xzf "${_agh_stage}/agh.tar.gz" -C "${_agh_stage}/extract" 2>/dev/null && [ -f "${_agh_stage}/extract/AdGuardHome/AdGuardHome" ]; then
                chmod +x "${_agh_stage}/extract/AdGuardHome/AdGuardHome"
                if "${_agh_stage}/extract/AdGuardHome/AdGuardHome" --version >/dev/null 2>&1; then
                    service_ctl adguardhome stop
                    mv -f "${_agh_stage}/extract/AdGuardHome/AdGuardHome" /usr/bin/AdGuardHome
                    echo "${C_GRN}[✓] AdGuard Home безопасно обновлен до ${AGH_TAG}.${C_RES}"
                else
                    echo "${C_RED}[X] Ошибка проверки бинарника AdGuard Home, оставлена текущая версия.${C_RES}"
                fi
            fi
            rm -rf "$_agh_stage"
        else
            rm -rf "$_agh_stage"
            echo "${C_RED}[X] Не удалось скачать или верифицировать AdGuard Home ${AGH_TAG}.${C_RES}"
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

    ensure_gateway_runtime_dir >/dev/null 2>&1 || true
    atomic_write_file "$VER_CACHE_FILE" 0600 "root:root" << VC_EOF 2>/dev/null || true
LATEST_SB_TAG='${LATEST_SB_TAG}'
LATEST_MIHOMO_TAG='${LATEST_MIHOMO_TAG}'
LATEST_AGH_TAG='${LATEST_AGH_TAG}'
LATEST_UI_TAG='${LATEST_UI_TAG}'
VC_EOF
    return 0
}

# Создание системных служб автозапуска (Alpine OpenRC / OpenWrt procd) и загрузочного Boot Guard
setup_init_scripts() {
    calc_hardware_limits
    load_gateway_env || true
    ACT_CORE_S=$(get_active_core)

    if is_openwrt 2>/dev/null; then
        if [ -z "${SB_GOMEMLIMIT:-}" ] || [ "$SB_GOMEMLIMIT" = "off" ]; then
            SB_ENV_LINE="procd_set_param env GOGC=100"
        else
            SB_ENV_LINE="procd_set_param env GOGC=${SB_GOGC:-50} GOMEMLIMIT=${SB_GOMEMLIMIT}"
        fi
        if [ -z "${AGH_GOMEMLIMIT:-}" ] || [ "$AGH_GOMEMLIMIT" = "off" ]; then
            AGH_ENV_LINE="procd_set_param env GOGC=100"
        else
            AGH_ENV_LINE="procd_set_param env GOGC=${AGH_GOGC:-50} GOMEMLIMIT=${AGH_GOMEMLIMIT}"
        fi

        cat << INIT_SB_OWRT > /etc/init.d/sing-box
#!/bin/sh /etc/rc.common
START=95
STOP=10
USE_PROCD=1

start_service() {
    mkdir -p /dev/net
    [ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null || true
    procd_open_instance
    procd_set_param command /bin/sh -c "exec /usr/bin/sing-box run -c /etc/sing-box/config.json -D /etc/sing-box >>'${SB_LOG_FILE}' 2>&1"
    ${SB_ENV_LINE}
    procd_set_param limits nofile="65535 65535"
    procd_set_param respawn 3600 3 10
    procd_close_instance
}
INIT_SB_OWRT
        chmod +x /etc/init.d/sing-box

        setup_mihomo_init_script

        cat << INIT_AGH_OWRT > /etc/init.d/adguardhome
#!/bin/sh /etc/rc.common
START=96
STOP=10
USE_PROCD=1

start_service() {
    mkdir -p /etc/AdGuardHome/data
    procd_open_instance
    procd_set_param command /usr/bin/AdGuardHome -c /etc/AdGuardHome/AdGuardHome.yaml -w /etc/AdGuardHome --no-check-update
    ${AGH_ENV_LINE}
    procd_set_param limits nofile="65535 65535"
    procd_set_param respawn 3600 3 10
    procd_close_instance
}
INIT_AGH_OWRT
        chmod +x /etc/init.d/adguardhome

        activate_core_service "$ACT_CORE_S"
        sleep 2
        service_ctl adguardhome enable
        service_ctl adguardhome restart

        mkdir -p /etc
        [ -f /etc/rc.local ] || printf "# Put your custom commands here\n\nexit 0\n" > /etc/rc.local
        if ! grep -q "gateway watchdog" /etc/rc.local 2>/dev/null; then
            awk 'BEGIN { added=0 }
                /^[[:space:]]*exit[[:space:]]+0/ && !added {
                    print "(sleep 10 && [ -x /usr/bin/gateway ] && /usr/bin/gateway watchdog >/dev/null 2>&1) &"
                    added=1
                }
                { print }
                END {
                    if (!added) print "(sleep 10 && [ -x /usr/bin/gateway ] && /usr/bin/gateway watchdog >/dev/null 2>&1) &"
                }' /etc/rc.local > "/etc/rc.local.tmp.$$" && mv -f "/etc/rc.local.tmp.$$" /etc/rc.local
        fi
        chmod +x /etc/rc.local 2>/dev/null || true
        return 0
    fi

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
export GOGC=${SB_GOGC:-50}
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
export GOGC=${AGH_GOGC:-50}
export GOMEMLIMIT=${AGH_GOMEMLIMIT}

depend() {
    need net
    after ${AFTER_CORE}
}
INIT_AGH_ALP
    chmod +x /etc/init.d/adguardhome

    activate_core_service "$ACT_CORE_S"
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
