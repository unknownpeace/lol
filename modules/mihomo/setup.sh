#!/bin/sh
# ==============================================================================
# Установка, обновление и OpenRC-служба ядра Mihomo (MetaCubeX / Clash Meta)
# ==============================================================================

install_mihomo_binary() {
    detect_os
    check_github_mirror

    MH_TAG=$(fetch_latest_github_tag "MetaCubeX/mihomo")
    case "$MH_TAG" in v*) ;; *) MH_TAG="v1.19.34" ;; esac
    LATEST_MIHOMO_TAG="$MH_TAG"

    INSTALLED_MH_VER=""
    if [ -x /usr/bin/mihomo ]; then
        INSTALLED_MH_VER=$(/usr/bin/mihomo -v 2>/dev/null | sed -n 's/.*\(v[0-9][0-9.a-zA-Z_-]*\).*/\1/p' | head -n 1 || true)
    fi

    if [ "$INSTALLED_MH_VER" = "$MH_TAG" ]; then
        echo "${C_GRN}[✓] Ядро Mihomo ${INSTALLED_MH_VER} (${MIHOMO_ARCH}) актуально.${C_RES}"
        return 0
    fi

    echo "Загрузка Mihomo ${MH_TAG} (${MIHOMO_ARCH})..."
    ensure_gateway_runtime_dir || return 1
    _mh_stage=$(mktemp -d "${GATEWAY_RUNTIME_DIR:-/run/gateway}/mh.XXXXXX" 2>/dev/null) || return 1
    chmod 700 "$_mh_stage" 2>/dev/null || true
    MH_ASSET="mihomo-linux-${MIHOMO_ARCH}-${MH_TAG}.gz"
    MH_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MH_TAG}/${MH_ASSET}"

    if download_file "$MH_URL" "${_mh_stage}/mihomo.gz" && verify_github_asset_sha256 "MetaCubeX/mihomo" "$MH_ASSET" "${_mh_stage}/mihomo.gz" "$MH_TAG"; then
        if gzip -dc "${_mh_stage}/mihomo.gz" > "${_mh_stage}/mihomo.bin" 2>/dev/null && [ -s "${_mh_stage}/mihomo.bin" ]; then
            chmod +x "${_mh_stage}/mihomo.bin"
            if "${_mh_stage}/mihomo.bin" -v >/dev/null 2>&1; then
                service_ctl mihomo stop >/dev/null 2>&1 || true
                mv -f "${_mh_stage}/mihomo.bin" /usr/bin/mihomo
                chmod +x /usr/bin/mihomo
                rm -rf "$_mh_stage"
                echo "${C_GRN}[✓] Mihomo безопасно обновлен до ${MH_TAG} (${MIHOMO_ARCH}).${C_RES}"
                return 0
            else
                echo "${C_RED}[X] Ошибка: бинарник mihomo не прошел проверку запуска, оставлена текущая версия.${C_RES}"
            fi
        fi
    else
        echo "${C_RED}[X] Не удалось скачать или верифицировать Mihomo ${MH_TAG} (${MH_ASSET}).${C_RES}"
    fi
    rm -rf "$_mh_stage"
    [ -x /usr/bin/mihomo ] && return 0 || return 1
}

setup_mihomo_init_script() {
    calc_hardware_limits
    mkdir -p "$MIHOMO_DIR" "${MIHOMO_DIR}/providers" "${MIHOMO_DIR}/rules"
    chmod 700 "$MIHOMO_DIR" 2>/dev/null || true

    if is_openwrt 2>/dev/null; then
        if [ -z "${SB_GOMEMLIMIT:-}" ] || [ "$SB_GOMEMLIMIT" = "off" ]; then
            MH_ENV_LINE="procd_set_param env GOGC=100 SAFE_PATHS=${SB_DIR}:${MIHOMO_DIR}"
        else
            MH_ENV_LINE="procd_set_param env GOGC=${SB_GOGC:-50} GOMEMLIMIT=${SB_GOMEMLIMIT} SAFE_PATHS=${SB_DIR}:${MIHOMO_DIR}"
        fi
        cat << INIT_MH_OWRT > /etc/init.d/mihomo
#!/bin/sh /etc/rc.common
START=95
STOP=10
USE_PROCD=1

start_service() {
    mkdir -p /dev/net "${MIHOMO_DIR}"
    [ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null || true
    procd_open_instance
    procd_set_param command /bin/sh -c "exec /usr/bin/mihomo -d '${MIHOMO_DIR}' -f '${MIHOMO_CONF}' >>'${MIHOMO_LOG_FILE}' 2>&1"
    ${MH_ENV_LINE}
    procd_set_param limits nofile="65535 65535"
    procd_set_param respawn 3600 3 10
    procd_close_instance
}
INIT_MH_OWRT
        chmod +x /etc/init.d/mihomo
        return 0
    fi

    cat << INIT_MH_ALP > /etc/init.d/mihomo
#!/sbin/openrc-run
name="mihomo"
description="Mihomo (Clash Meta) Gateway"
supervisor="supervise-daemon"
command="/usr/bin/mihomo"
command_args="-d ${MIHOMO_DIR} -f ${MIHOMO_CONF}"
output_log="${MIHOMO_LOG_FILE}"
error_log="${MIHOMO_LOG_FILE}"
rc_ulimit="-n 65535"
rc_oom_score_adj="-500"
respawn_delay=3
respawn_max=10
retry="TERM/10/KILL/5"
export GOGC=${SB_GOGC:-50}
export GOMEMLIMIT=${SB_GOMEMLIMIT}
export SAFE_PATHS="${SB_DIR}:${MIHOMO_DIR}"

depend() {
    need net
    after nftables
}

start_pre() {
    mkdir -p /dev/net "${MIHOMO_DIR}"
    [ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null || true
    : > "${MIHOMO_LOG_FILE}" 2>/dev/null || true
}
INIT_MH_ALP
    chmod +x /etc/init.d/mihomo
    return 0
}
