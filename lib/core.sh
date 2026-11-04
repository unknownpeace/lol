atomic_write_file() {
    AW_TARGET="$1"
    AW_MODE="${2:-0600}"
    AW_OWNER="${3:-root:root}"
    AW_DIR=$(dirname "$AW_TARGET")
    mkdir -p "$AW_DIR" 2>/dev/null || true
    AW_TMP="${AW_TARGET}.tmp.$$"

    if ! cat > "$AW_TMP"; then
        rm -f "$AW_TMP" 2>/dev/null || true
        return 1
    fi
    chown "$AW_OWNER" "$AW_TMP" 2>/dev/null || true
    chmod "$AW_MODE" "$AW_TMP" 2>/dev/null || true
    if command -v fsync >/dev/null 2>&1; then
        fsync "$AW_TMP" 2>/dev/null || sync
    else
        sync
    fi
    if ! mv -f "$AW_TMP" "$AW_TARGET" 2>/dev/null; then
        cp -f "$AW_TMP" "$AW_TARGET" 2>/dev/null || { rm -f "$AW_TMP" 2>/dev/null || true; return 1; }
        rm -f "$AW_TMP" 2>/dev/null || true
    fi
    chmod "$AW_MODE" "$AW_TARGET" 2>/dev/null || true
    if command -v fsync >/dev/null 2>&1; then
        fsync "$AW_DIR" 2>/dev/null || true
    fi
    return 0
}

# Атомарное перемещение подготовленного временного файла на место целевого с fsync
atomic_commit_tmp() {
    AC_TMP="$1"
    AC_TARGET="$2"
    AC_MODE="${3:-0600}"
    AC_OWNER="${4:-root:root}"
    if [ ! -s "$AC_TMP" ]; then
        rm -f "$AC_TMP" 2>/dev/null || true
        return 1
    fi
    chown "$AC_OWNER" "$AC_TMP" 2>/dev/null || true
    chmod "$AC_MODE" "$AC_TMP" 2>/dev/null || true
    if command -v fsync >/dev/null 2>&1; then
        fsync "$AC_TMP" 2>/dev/null || sync
    else
        sync
    fi
    mv -f "$AC_TMP" "$AC_TARGET" 2>/dev/null || cp -f "$AC_TMP" "$AC_TARGET" 2>/dev/null || return 1
    rm -f "$AC_TMP" 2>/dev/null || true
    chmod "$AC_MODE" "$AC_TARGET" 2>/dev/null || true
    return 0
}

# Безопасная атомарная запись /etc/resolv.conf в Alpine Linux (с защитой от перезаписи udhcpc)
write_resolv_conf() {
    mkdir -p /etc/udhcpc 2>/dev/null || true
    if [ ! -f /etc/udhcpc/udhcpc.conf ] || ! grep -q '^RESOLV_CONF=' /etc/udhcpc/udhcpc.conf 2>/dev/null; then
        echo 'RESOLV_CONF="no"' >> /etc/udhcpc/udhcpc.conf 2>/dev/null || true
    fi
    printf "%s\n" "$1" > "/tmp/resolv.conf.$$"
    rm -f /etc/resolv.conf 2>/dev/null || true
    mv -f "/tmp/resolv.conf.$$" /etc/resolv.conf 2>/dev/null || cp -f "/tmp/resolv.conf.$$" /etc/resolv.conf 2>/dev/null || true
    rm -f "/tmp/resolv.conf.$$" 2>/dev/null || true
    return 0
}

# Механизм межпроцессной блокировки (защита от гонки cron autoupdate, watchdog и установки модулей)
acquire_gateway_lock() {
    LOCK_OWNER="${1:-op}"
    if mkdir "$GATEWAY_LOCK_DIR" 2>/dev/null; then
        printf "%s %s\n" "$$" "$LOCK_OWNER" > "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true
        return 0
    fi
    if [ -f "${GATEWAY_LOCK_DIR}/pid" ]; then
        OLD_PID=$(awk '{print $1}' "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true)
        if [ -n "$OLD_PID" ] && ! kill -0 "$OLD_PID" 2>/dev/null; then
            rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
            if mkdir "$GATEWAY_LOCK_DIR" 2>/dev/null; then
                printf "%s %s\n" "$$" "$LOCK_OWNER" > "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true
                return 0
            fi
        fi
    fi
    return 1
}

release_gateway_lock() {
    rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
    return 0
}

# Получение актуального регулярного выражения фильтрации подписки
get_sub_filter_regex() {
    if [ "${ALLOW_RU_NODES:-no}" = "yes" ]; then
        printf "%s" "$SUB_FILTER_WHITELIST"
    else
        printf "%s" "$SUB_FILTER_STRICT"
    fi
    return 0
}

# Автоматический расчет лимитов RAM и сетевого стека под железо (с учетом нагрузки Homelab)
calc_hardware_limits() {
    MEM_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo "524288")
    [ -z "$MEM_KB" ] && MEM_KB="524288"
    TOTAL_RAM_MB=$((MEM_KB / 1024))

    if [ "$TOTAL_RAM_MB" -le 300 ]; then
        SB_GOMEMLIMIT="95MiB"
        AGH_GOMEMLIMIT="55MiB"
        SYS_CONNTRACK_MAX="32768"
        SYS_BUF_MAX="8388608"
    elif [ "$TOTAL_RAM_MB" -le 600 ]; then
        SB_GOMEMLIMIT="180MiB"
        AGH_GOMEMLIMIT="90MiB"
        SYS_CONNTRACK_MAX="65536"
        SYS_BUF_MAX="16777216"
    elif [ "$TOTAL_RAM_MB" -le 1200 ]; then
        SB_GOMEMLIMIT="300MiB"
        AGH_GOMEMLIMIT="130MiB"
        SYS_CONNTRACK_MAX="131072"
        SYS_BUF_MAX="33554432"
    elif [ "$TOTAL_RAM_MB" -le 2500 ]; then
        SB_GOMEMLIMIT="450MiB"
        AGH_GOMEMLIMIT="180MiB"
        SYS_CONNTRACK_MAX="196608"
        SYS_BUF_MAX="33554432"
    else
        SB_GOMEMLIMIT="600MiB"
        AGH_GOMEMLIMIT="250MiB"
        SYS_CONNTRACK_MAX="262144"
        SYS_BUF_MAX="67108864"
    fi
    return 0
}

# Проверка целевой платформы (Эксклюзивно Alpine Linux x86_64 / arm64)
detect_os() {
    if [ ! -f /etc/alpine-release ] || ! command -v apk >/dev/null 2>&1; then
        echo "${C_RED}[X] Ошибка: Эта ветка (Alpine Linux Homelab Edition) предназначена исключительно для Alpine Linux!${C_RES}"
        exit 1
    fi

    calc_hardware_limits
    OS_TYPE="alpine"
    OS_NAME="Alpine Linux v$(cat /etc/alpine-release 2>/dev/null | tr -d ' \t\r\n')"

    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64)
            SB_ARCH="amd64"
            AGH_ARCH="amd64"
            ;;
        aarch64|arm64)
            SB_ARCH="arm64"
            AGH_ARCH="arm64"
            ;;
        *)
            echo "${C_RED}[X] Ошибка: Неподдерживаемая архитектура ${ARCH_RAW} (требуется x86_64 или aarch64).${C_RES}"
            exit 1
            ;;
    esac
    return 0
}

# Подгрузка и фиксация ядерных модулей для Alpine Linux (tun, tcp_bbr, nf_conntrack, nftables)
ensure_alpine_modules() {
    touch /etc/modules 2>/dev/null || true
    for kmod in tun tcp_bbr nf_conntrack nft_chain_nat nft_masq nft_redir nft_reject_inet; do
        modprobe "$kmod" 2>/dev/null || true
        grep -qxF "$kmod" /etc/modules 2>/dev/null || echo "$kmod" >> /etc/modules
    done
    if [ ! -e /dev/net/tun ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 666 /dev/net/tun 2>/dev/null || true
    fi
    rc-update add modules boot >/dev/null 2>&1 || true
    rc-update add sysctl boot >/dev/null 2>&1 || true
    ensure_core_tools
    return 0
}

# Гарантированная проверка и автоустановка критических утилит (jq, curl, nftables, ca-certificates)
ensure_core_tools() {
    MISSING_PKGS=""
    command -v jq >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS jq"
    command -v curl >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS curl"
    command -v nft >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS nftables"
    [ -d /etc/ssl/certs ] || MISSING_PKGS="$MISSING_PKGS ca-certificates"
    if [ -n "$MISSING_PKGS" ]; then
        if command -v apk >/dev/null 2>&1; then
            apk add --no-cache $MISSING_PKGS >/dev/null 2>&1 || true
        fi
    fi
    return 0
}

# Проверка корректности IPv4-адреса (X.X.X.X, без восьмеричных ведущих нулей, октеты 0..255, хост 1..254)
is_valid_ipv4() {
    IP_CAND="$1"
    printf "%s" "$IP_CAND" | awk -F'.' '
        NF != 4 { exit 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^(0|[1-9][0-9]*)$/) exit 1
                if ($i + 0 < 0 || $i + 0 > 255) exit 1
            }
            if ($1 + 0 < 1 || $1 + 0 > 223 || $1 + 0 == 127) exit 1
            if ($4 + 0 < 1 || $4 + 0 > 254) exit 1
        }
    ' >/dev/null 2>&1
}

# Динамическое определение имени физического LAN-интерфейса в Alpine Linux (eth0, ens18, enp0s3, br0 и т.д.)
get_lan_ifname() {
    DEF_DEV=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev" && $(i+1)!="singbox-tun" && $(i+1)!="lo") {print $(i+1); exit}}')
    if [ -n "$DEF_DEV" ] && ip link show "$DEF_DEV" >/dev/null 2>&1; then
        printf "%s" "$DEF_DEV"
        return 0
    fi
    if ip link show eth0 >/dev/null 2>&1; then
        printf "eth0"
        return 0
    fi
    ANY_DEV=$(ip -o -4 addr show scope global 2>/dev/null | awk '$2 != "singbox-tun" && $2 != "lo" {print $2; exit}')
    if [ -n "$ANY_DEV" ] && ip link show "$ANY_DEV" >/dev/null 2>&1; then
        printf "%s" "$ANY_DEV"
        return 0
    fi
    printf "eth0"
    return 0
}

# Получение текущего LAN IP-адреса самого сервера Alpine Linux
get_current_lan_ip() {
    L_IF=$(get_lan_ifname)
    CUR_LAN=$(ip -4 addr show "$L_IF" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    [ -z "$CUR_LAN" ] && CUR_LAN=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    if [ -z "$CUR_LAN" ] && [ -f /etc/network/interfaces ]; then
        CUR_LAN=$(awk '/^[[:space:]]*address[[:space:]]+/ {split($2,a,"/"); print a[1]; exit}' /etc/network/interfaces 2>/dev/null || true)
    fi
    CUR_LAN="${CUR_LAN%%/*}"
    [ -z "$CUR_LAN" ] && CUR_LAN="192.168.1.2"
    printf "%s" "$CUR_LAN"
    return 0
}

# Отключение фонового демона apache2 (оставляем только утилиту htpasswd для генерации bcrypt)
disable_apache_daemon() {
    for srv in apache apache2 httpd; do
        if [ -f "/etc/init.d/${srv}" ]; then
            rc-service "$srv" stop >/dev/null 2>&1 || "/etc/init.d/${srv}" stop >/dev/null 2>&1 || true
            rc-update del "$srv" default >/dev/null 2>&1 || true
            rm -f "/etc/init.d/${srv}" 2>/dev/null || true
        fi
    done
    return 0
}


# Проверка валидности конфигурации sing-box-extended
