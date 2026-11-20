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
    rm -f /tmp/mihomo.gz /tmp/mihomo.bin
    MH_ASSET="mihomo-linux-${MIHOMO_ARCH}-${MH_TAG}.gz"
    MH_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MH_TAG}/${MH_ASSET}"

    if download_file "$MH_URL" "/tmp/mihomo.gz" && verify_github_asset_sha256 "MetaCubeX/mihomo" "$MH_ASSET" "/tmp/mihomo.gz"; then
        if gzip -dc /tmp/mihomo.gz > /tmp/mihomo.bin 2>/dev/null && [ -s /tmp/mihomo.bin ]; then
            chmod +x /tmp/mihomo.bin
            if /tmp/mihomo.bin -v >/dev/null 2>&1; then
                service_ctl mihomo stop >/dev/null 2>&1 || true
                mv -f /tmp/mihomo.bin /usr/bin/mihomo
                chmod +x /usr/bin/mihomo
                rm -f /tmp/mihomo.gz
                echo "${C_GRN}[✓] Mihomo безопасно обновлен до ${MH_TAG} (${MIHOMO_ARCH}).${C_RES}"
                return 0
            else
                echo "${C_RED}[X] Ошибка: бинарник mihomo не прошел проверку запуска, оставлена текущая версия.${C_RES}"
            fi
        fi
    else
        echo "${C_RED}[X] Не удалось скачать Mihomo ${MH_TAG} (${MH_ASSET}).${C_RES}"
    fi
    rm -f /tmp/mihomo.gz /tmp/mihomo.bin
    [ -x /usr/bin/mihomo ] && return 0 || return 1
}

setup_mihomo_init_script() {
    calc_hardware_limits
    mkdir -p "$MIHOMO_DIR" "${MIHOMO_DIR}/providers" "${MIHOMO_DIR}/rules"
    chmod 700 "$MIHOMO_DIR" 2>/dev/null || true

    if is_openwrt 2>/dev/null; then
        cat << INIT_MH_OWRT > /etc/init.d/mihomo
#!/bin/sh /etc/rc.common
START=95
STOP=10
USE_PROCD=1

start_service() {
    mkdir -p /dev/net "${MIHOMO_DIR}"
    [ -e /dev/net/tun ] || mknod /dev/net/tun c 10 200 2>/dev/null || true
    procd_open_instance
    procd_set_param command /bin/sh -c ": > '${MIHOMO_LOG_FILE}'; exec /usr/bin/mihomo -d '${MIHOMO_DIR}' -f '${MIHOMO_CONF}' >>'${MIHOMO_LOG_FILE}' 2>&1"
    procd_set_param env GOGC=50 GOMEMLIMIT=${SB_GOMEMLIMIT} SAFE_PATHS=${SB_DIR}:${MIHOMO_DIR}
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
export GOGC=50
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
