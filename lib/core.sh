#!/bin/sh
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

# Гарантированное создание приватного runtime-каталога /run/gateway (0700 root:root)
ensure_gateway_runtime_dir() {
    _rt_dir="${GATEWAY_RUNTIME_DIR:-/run/gateway}"
    if [ -L "$_rt_dir" ] || { [ -e "$_rt_dir" ] && [ ! -d "$_rt_dir" ]; }; then
        rm -rf "$_rt_dir" 2>/dev/null || return 1
    fi
    if [ ! -d "$_rt_dir" ]; then
        (umask 077 && mkdir -p "$_rt_dir") 2>/dev/null || return 1
    fi
    chown root:root "$_rt_dir" 2>/dev/null || true
    chmod 0700 "$_rt_dir" 2>/dev/null || return 1
    return 0
}

# Общий секрет между Caddy и gateway-webui (32 hex, 0600 root:root; печатает токен в stdout)
# Caddy передаёт его в X-Gateway-Proxy-Token после проверки basic_auth и снятия Authorization.
ensure_webui_proxy_token() {
    _tok_sb="${SB_DIR:-/etc/sing-box}"
    _tok_dir="${HOMELAB_DIR:-/etc/sing-box/homelab}"
    _tok_file="${_tok_dir}/webui_proxy.token"
    mkdir -p "$_tok_sb" "$_tok_dir" 2>/dev/null || true
    chown root:root "$_tok_sb" "$_tok_dir" 2>/dev/null || true
    chmod 700 "$_tok_sb" 2>/dev/null || true
    chmod 750 "$_tok_dir" 2>/dev/null || true

    _cur_tok=""
    [ -s "$_tok_file" ] && _cur_tok=$(tr -d ' \t\r\n' < "$_tok_file" 2>/dev/null || true)
    case "$_cur_tok" in
        *[!0-9a-f]*|"") _cur_tok="" ;;
        *) [ "${#_cur_tok}" -eq 32 ] || _cur_tok="" ;;
    esac

    if [ -z "$_cur_tok" ]; then
        _cur_tok=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -dc '0-9a-f' | head -c 32 || true)
        if [ "${#_cur_tok}" -ne 32 ] && command -v openssl >/dev/null 2>&1; then
            _cur_tok=$(openssl rand -hex 16 2>/dev/null | tr -dc '0-9a-f' | head -c 32 || true)
        fi
        [ "${#_cur_tok}" -eq 32 ] || return 1
        (
            umask 077
            printf "%s\n" "$_cur_tok" > "${_tok_file}.tmp.$$" &&
            chown root:root "${_tok_file}.tmp.$$" 2>/dev/null || true
            chmod 600 "${_tok_file}.tmp.$$" 2>/dev/null || true
            mv -f "${_tok_file}.tmp.$$" "$_tok_file"
        ) || { rm -f "${_tok_file}.tmp.$$" 2>/dev/null || true; return 1; }
    fi
    chown root:root "$_tok_file" 2>/dev/null || true
    chmod 600 "$_tok_file" 2>/dev/null || true
    printf "%s" "$_cur_tok"
    return 0
}

# Проверка корректности IPv4 CIDR (X.X.X.X/1..32)
is_valid_ipv4_cidr() {
    _cidr_cand="$1"
    case "$_cidr_cand" in
        */*)
            _cidr_ip="${_cidr_cand%%/*}"
            _cidr_len="${_cidr_cand#*/}"
            case "$_cidr_len" in
                ''|*[!0-9]*) return 1 ;;
            esac
            [ "$_cidr_len" -ge 1 ] && [ "$_cidr_len" -le 32 ] || return 1
            printf "%s" "$_cidr_ip" | awk -F'.' '
                NF != 4 { exit 1 }
                {
                    for (i = 1; i <= 4; i++) {
                        if ($i !~ /^(0|[1-9][0-9]*)$/) exit 1
                        if ($i + 0 < 0 || $i + 0 > 255) exit 1
                    }
                    if ($1 + 0 < 1 || $1 + 0 > 223 || $1 + 0 == 127) exit 1
                }
            ' >/dev/null 2>&1
            ;;
        *) return 1 ;;
    esac
}

# Обёртка curl с безопасным фоллбэком --curves для OpenWrt mbedTLS/wolfSSL
gw_curl() {
    _gc_out=""
    _gc_rc=0
    if [ -z "${_GW_NO_CURVES:-}" ]; then
        _gc_out=$(curl --curves X25519:P-256 "$@" 2>/dev/null) || _gc_rc=$?
        if [ "$_gc_rc" -eq 0 ]; then
            printf "%s" "$_gc_out"
            return 0
        fi
        case "$_gc_rc" in
            2|4|35|45|59)
                _GW_NO_CURVES=1
                ;;
            *)
                printf "%s" "$_gc_out"
                return "$_gc_rc"
                ;;
        esac
    fi
    curl "$@"
}

# Вызов Clash API с передачей Bearer-токена через stdin (-K -), чтобы не светить ADMIN_PASS в ps
clash_api_curl() {
    _ca_pass="${ADMIN_PASS:-}"
    _ca_esc=$(printf "%s" "$_ca_pass" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf 'header = "Authorization: Bearer %s"\n' "$_ca_esc" | curl -K - "$@"
}

# Безопасная атомарная запись resolv.conf в той же ФС (OpenWrt держит /etc/resolv.conf симлинком на /tmp/resolv.conf)
write_resolv_conf() {
    if is_openwrt 2>/dev/null; then
        _rc_dst="/tmp/resolv.conf"
    else
        mkdir -p /etc/udhcpc 2>/dev/null || true
        if [ ! -f /etc/udhcpc/udhcpc.conf ] || ! grep -q '^RESOLV_CONF=' /etc/udhcpc/udhcpc.conf 2>/dev/null; then
            echo 'RESOLV_CONF="no"' >> /etc/udhcpc/udhcpc.conf 2>/dev/null || true
        fi
        _rc_dst="/etc/resolv.conf"
    fi
    _rc_tmp="${_rc_dst}.tmp.$$"
    if printf "%s\n" "$1" > "$_rc_tmp" 2>/dev/null; then
        chmod 0644 "$_rc_tmp" 2>/dev/null || true
        if ! mv -f "$_rc_tmp" "$_rc_dst" 2>/dev/null; then
            cp -f "$_rc_tmp" "$_rc_dst" 2>/dev/null || true
            rm -f "$_rc_tmp" 2>/dev/null || true
        fi
    fi
    return 0
}

# Механизм межпроцессной блокировки в /run/gateway (защита от гонки cron autoupdate, watchdog и установки)
acquire_gateway_lock() {
    LOCK_OWNER="${1:-op}"
    ensure_gateway_runtime_dir || return 1
    if (umask 077 && mkdir "$GATEWAY_LOCK_DIR" 2>/dev/null); then
        printf "%s %s\n" "$$" "$LOCK_OWNER" > "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true
        chmod 0600 "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true
        return 0
    fi

    _stale_lock=0
    if [ -f "${GATEWAY_LOCK_DIR}/pid" ]; then
        OLD_PID=$(awk '{print $1}' "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true)
        case "$OLD_PID" in
            ''|*[!0-9]*) OLD_PID="" ;;
        esac
        if [ -n "$OLD_PID" ] && ! kill -0 "$OLD_PID" 2>/dev/null; then
            _stale_lock=1
        fi
    fi

    if [ "$_stale_lock" -eq 0 ]; then
        if [ ! -f "${GATEWAY_LOCK_DIR}/pid" ] || [ -z "${OLD_PID:-}" ]; then
            _lck_ts=$(date -r "$GATEWAY_LOCK_DIR" +%s 2>/dev/null || stat -c %Y "$GATEWAY_LOCK_DIR" 2>/dev/null || true)
            _now_ts=$(date +%s 2>/dev/null || echo 0)
            case "$_lck_ts" in ''|*[!0-9]*) _lck_ts="" ;; esac
            if [ -n "$_lck_ts" ] && [ "${_now_ts:-0}" -gt 0 ]; then
                [ $((_now_ts - _lck_ts)) -ge 30 ] && _stale_lock=1
            elif [ -n "$(find "$GATEWAY_LOCK_DIR" -maxdepth 0 -mmin +1 2>/dev/null || true)" ]; then
                _stale_lock=1
            fi
        fi
    fi

    if [ "$_stale_lock" -eq 1 ]; then
        rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
        if (umask 077 && mkdir "$GATEWAY_LOCK_DIR" 2>/dev/null); then
            printf "%s %s\n" "$$" "$LOCK_OWNER" > "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true
            chmod 0600 "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true
            return 0
        fi
    fi
    return 1
}

release_gateway_lock() {
    if [ "${1:-}" = "force" ]; then
        rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
        return 0
    fi
    if [ -f "${GATEWAY_LOCK_DIR}/pid" ]; then
        _own_pid=$(awk '{print $1}' "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true)
        if [ -z "$_own_pid" ] || [ "$_own_pid" = "$$" ]; then
            rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
        fi
    else
        rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
    fi
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

# Автоматический расчет лимитов RAM и сетевого стека под железо (с учетом нагрузки Homelab и swapless OpenWrt)
calc_hardware_limits() {
    MEM_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo "524288")
    [ -z "$MEM_KB" ] && MEM_KB="524288"
    TOTAL_RAM_MB=$((MEM_KB / 1024))
    _is_owrt_hw=0
    if is_openwrt 2>/dev/null || [ -f /etc/openwrt_release ]; then
        _is_owrt_hw=1
    fi

    if [ "$TOTAL_RAM_MB" -le 300 ]; then
        SB_GOMEMLIMIT="60MiB"
        AGH_GOMEMLIMIT="35MiB"
        SB_GOGC="35"
        AGH_GOGC="35"
        SYS_CONNTRACK_MAX="16384"
        SYS_BUF_MAX="2097152"
        SYS_UDP_TIMEOUT="30"
        SYS_UDP_STREAM_TIMEOUT="90"
    elif [ "$TOTAL_RAM_MB" -le 600 ]; then
        SB_GOMEMLIMIT="110MiB"
        AGH_GOMEMLIMIT="55MiB"
        SB_GOGC="35"
        AGH_GOGC="35"
        SYS_CONNTRACK_MAX="16384"
        SYS_BUF_MAX="2097152"
        SYS_UDP_TIMEOUT="30"
        SYS_UDP_STREAM_TIMEOUT="90"
    elif [ "$TOTAL_RAM_MB" -le 1200 ]; then
        SB_GOMEMLIMIT="200MiB"
        AGH_GOMEMLIMIT="90MiB"
        SB_GOGC="50"
        AGH_GOGC="50"
        SYS_CONNTRACK_MAX="32768"
        SYS_BUF_MAX="4194304"
        SYS_UDP_TIMEOUT="45"
        SYS_UDP_STREAM_TIMEOUT="120"
    elif [ "$TOTAL_RAM_MB" -le 2500 ]; then
        if [ "$_is_owrt_hw" -eq 1 ]; then
            SB_GOMEMLIMIT="320MiB"
            AGH_GOMEMLIMIT="130MiB"
        else
            SB_GOMEMLIMIT="400MiB"
            AGH_GOMEMLIMIT="160MiB"
        fi
        SB_GOGC="50"
        AGH_GOGC="50"
        SYS_CONNTRACK_MAX="65536"
        SYS_BUF_MAX="8388608"
        SYS_UDP_TIMEOUT="60"
        SYS_UDP_STREAM_TIMEOUT="180"
    else
        if [ "$_is_owrt_hw" -eq 1 ]; then
            SB_GOMEMLIMIT="450MiB"
            AGH_GOMEMLIMIT="180MiB"
        else
            SB_GOMEMLIMIT="600MiB"
            AGH_GOMEMLIMIT="250MiB"
        fi
        SB_GOGC="50"
        AGH_GOGC="50"
        SYS_CONNTRACK_MAX="131072"
        SYS_BUF_MAX="16777216"
        SYS_UDP_TIMEOUT="60"
        SYS_UDP_STREAM_TIMEOUT="180"
    fi
    return 0
}

is_openwrt() {
    [ "${OS_TYPE:-alpine}" = "openwrt" ]
}

version_ge() {
    awk -v cur="$1" -v min="$2" '
        BEGIN {
            nc = split(cur, c, ".")
            nm = split(min, m, ".")
            n = (nc > nm) ? nc : nm
            for (i = 1; i <= n; i++) {
                if (c[i] != "" && c[i] !~ /^[0-9]+$/) exit 1
                if (m[i] != "" && m[i] !~ /^[0-9]+$/) exit 1
                ci = (i <= nc && c[i] != "") ? c[i] + 0 : 0
                mi = (i <= nm && m[i] != "") ? m[i] + 0 : 0
                if (ci > mi) exit 0
                if (ci < mi) exit 1
            }
            exit 0
        }
    ' 2>/dev/null
}

# Проверка целевой платформы (Alpine Linux 3.21+ и OpenWrt >= 25.12.6 с apk)
detect_os() {
    if [ -f /etc/openwrt_release ] || grep -qi '^ID="openwrt"' /etc/os-release 2>/dev/null; then
        if ! command -v apk >/dev/null 2>&1; then
            echo "${C_RED}[X] Ошибка: Поддерживается только OpenWrt ${OPENWRT_MIN_VERSION:-25.12.6}+ с пакетным менеджером apk!${C_RES}"
            exit 1
        fi
        OWRT_VER=""
        if [ -f /etc/openwrt_release ]; then
            OWRT_VER=$(sed -n "s/^DISTRIB_RELEASE=['\"]\([^'\"]*\)['\"].*/\1/p" /etc/openwrt_release 2>/dev/null | head -n 1 | tr -d ' \t\r\n')
        fi
        if [ -z "$OWRT_VER" ] && [ -f /etc/os-release ]; then
            OWRT_VER=$(sed -n 's/^VERSION_ID="\([^"]*\)".*/\1/p' /etc/os-release 2>/dev/null | head -n 1 | tr -d ' \t\r\n')
        fi
        if ! version_ge "$OWRT_VER" "${OPENWRT_MIN_VERSION:-25.12.6}"; then
            echo "${C_RED}[X] Ошибка: Требуется OpenWrt ${OPENWRT_MIN_VERSION:-25.12.6} или новее! Обнаружена версия: ${OWRT_VER:-неизвестна}${C_RES}"
            exit 1
        fi
        calc_hardware_limits
        OS_TYPE="openwrt"
        OS_NAME="OpenWrt ${OWRT_VER}"
    elif [ -f /etc/alpine-release ] && command -v apk >/dev/null 2>&1; then
        calc_hardware_limits
        OS_TYPE="alpine"
        OS_NAME="Alpine Linux v$(tr -d ' \t\r\n' < /etc/alpine-release 2>/dev/null)"
    else
        echo "${C_RED}[X] Ошибка: Поддерживаются только Alpine Linux и OpenWrt >= ${OPENWRT_MIN_VERSION:-25.12.6} (с apk)!${C_RES}"
        exit 1
    fi

    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64)
            SB_ARCH="amd64"
            AGH_ARCH="amd64"
            if grep -qw avx2 /proc/cpuinfo 2>/dev/null && grep -qw bmi2 /proc/cpuinfo 2>/dev/null && grep -qw fma /proc/cpuinfo 2>/dev/null; then
                MIHOMO_ARCH="amd64-v3"
            else
                MIHOMO_ARCH="amd64-v1"
            fi
            ;;
        aarch64|arm64)
            SB_ARCH="arm64"
            AGH_ARCH="arm64"
            MIHOMO_ARCH="arm64"
            ;;
        *)
            echo "${C_RED}[X] Ошибка: Неподдерживаемая архитектура ${ARCH_RAW} (требуется x86_64 или aarch64).${C_RES}"
            exit 1
            ;;
    esac
    if [ -w /run ] 2>/dev/null && [ ! -d "${GATEWAY_RUNTIME_DIR:-/run/gateway}" ]; then
        ensure_gateway_runtime_dir >/dev/null 2>&1 || true
    fi
    return 0
}

# Подгрузка и фиксация ядерных модулей (tun, tcp_bbr, nf_conntrack, nftables)
ensure_alpine_modules() {
    if is_openwrt; then
        for kmod in tun tcp_bbr nf_conntrack; do
            modprobe "$kmod" 2>/dev/null || true
        done
    else
        touch /etc/modules 2>/dev/null || true
        for kmod in tun tcp_bbr nf_conntrack nft_chain_nat nft_masq nft_redir nft_reject_inet; do
            modprobe "$kmod" 2>/dev/null || true
            grep -qxF "$kmod" /etc/modules 2>/dev/null || echo "$kmod" >> /etc/modules
        done
        rc-update add modules boot >/dev/null 2>&1 || true
        rc-update add sysctl boot >/dev/null 2>&1 || true
    fi
    if [ ! -e /dev/net/tun ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 666 /dev/net/tun 2>/dev/null || true
    fi
    ensure_core_tools
    return 0
}

# Гарантированная проверка и автоустановка критических утилит (jq, curl, nftables, ca-certificates, git)
ensure_core_tools() {
    MISSING_PKGS=""
    command -v jq >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS jq"
    command -v curl >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS curl"
    command -v git >/dev/null 2>&1 || {
        MISSING_PKGS="$MISSING_PKGS git"
        is_openwrt && MISSING_PKGS="$MISSING_PKGS git-http"
    }
    if is_openwrt; then
        [ -d /etc/ssl/certs ] || MISSING_PKGS="$MISSING_PKGS ca-bundle ca-certificates"
        [ -e /dev/net/tun ] || modprobe tun >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS kmod-tun"
        if [ -n "$MISSING_PKGS" ] && command -v apk >/dev/null 2>&1; then
            apk update >/dev/null 2>&1 || true
            # shellcheck disable=SC2086
            apk add $MISSING_PKGS >/dev/null 2>&1 || true
        fi
    else
        command -v nft >/dev/null 2>&1 || MISSING_PKGS="$MISSING_PKGS nftables"
        [ -d /etc/ssl/certs ] || MISSING_PKGS="$MISSING_PKGS ca-certificates"
        if [ -n "$MISSING_PKGS" ] && command -v apk >/dev/null 2>&1; then
            # shellcheck disable=SC2086
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

# Динамическое определение имени физического LAN-интерфейса (br-lan, eth0, ens18, enp0s3 и т.д.)
get_lan_ifname() {
    if is_openwrt 2>/dev/null || [ -f /etc/openwrt_release ]; then
        if command -v uci >/dev/null 2>&1; then
            _ow_lan=$(uci -q get network.lan.device 2>/dev/null || uci -q get network.lan.ifname 2>/dev/null || true)
            _ow_lan="${_ow_lan%% *}"
            if [ -n "$_ow_lan" ] && ip link show "$_ow_lan" >/dev/null 2>&1; then
                printf "%s" "$_ow_lan"
                return 0
            fi
        fi
        if ip link show br-lan >/dev/null 2>&1; then
            printf "br-lan"
            return 0
        fi
    fi

    DEF_DEV=$(ip -4 route show default 2>/dev/null | awk -v ct="${CORE_TUN_IF:-gateway-tun}" '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev") {
                    d = $(i + 1)
                    sub(/@.*/, "", d)
                    if (d != "" && d != ct && d != "gateway-tun" && d != "singbox-tun" && d != "mihomo0" && d != "lo" && \
                        d !~ /^(lxcbr|veth|wg|tun|tap|docker|virbr)/) {
                        print d; exit
                    }
                }
            }
        }
    ')
    if [ -n "$DEF_DEV" ] && ip link show "$DEF_DEV" >/dev/null 2>&1; then
        printf "%s" "$DEF_DEV"
        return 0
    fi
    if ip link show eth0 >/dev/null 2>&1; then
        printf "eth0"
        return 0
    fi
    ANY_DEV=$(ip -o -4 addr show scope global 2>/dev/null | awk -v ct="${CORE_TUN_IF:-gateway-tun}" '
        {
            d = $2
            sub(/@.*/, "", d)
            if (d != "" && d != ct && d != "gateway-tun" && d != "singbox-tun" && d != "mihomo0" && d != "lo" && \
                d !~ /^(lxcbr|veth|wg|tun|tap|docker|virbr)/) {
                print d; exit
            }
        }
    ')
    if [ -n "$ANY_DEV" ] && ip link show "$ANY_DEV" >/dev/null 2>&1; then
        printf "%s" "$ANY_DEV"
        return 0
    fi
    printf "eth0"
    return 0
}

# Получение текущего LAN IP-адреса самого сервера
get_current_lan_ip() {
    if [ -n "${GW_TARGET_LAN_IP_OVERRIDE:-}" ] && is_valid_ipv4 "$GW_TARGET_LAN_IP_OVERRIDE"; then
        printf "%s" "$GW_TARGET_LAN_IP_OVERRIDE"
        return 0
    fi
    L_IF=$(get_lan_ifname)
    CUR_LAN=$(ip -4 addr show "$L_IF" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    [ -z "$CUR_LAN" ] && CUR_LAN=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    if [ -z "$CUR_LAN" ] && is_openwrt 2>/dev/null && command -v uci >/dev/null 2>&1; then
        CUR_LAN=$(uci -q get network.lan.ipaddr 2>/dev/null || true)
    fi
    if [ -z "$CUR_LAN" ] && [ -f /etc/network/interfaces ]; then
        CUR_LAN=$(awk '/^[[:space:]]*address[[:space:]]+/ {split($2,a,"/"); print a[1]; exit}' /etc/network/interfaces 2>/dev/null || true)
    fi
    CUR_LAN="${CUR_LAN%%/*}"
    [ -z "$CUR_LAN" ] && CUR_LAN="192.168.1.2"
    printf "%s" "$CUR_LAN"
    return 0
}

# Получение IP-адреса основного роутера из таблицы маршрутизации (в обход gateway-tun)
get_default_router_ip() {
    DEF_GW=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {gw=$(i+1); if(gw!="" && gw!="172.19.0.1") {print gw; exit}}}')
    if [ -n "$DEF_GW" ] && is_valid_ipv4 "$DEF_GW"; then
        printf "%s" "$DEF_GW"
        return 0
    fi
    printf "%s" "${DEFAULT_ROUTER_IP:-192.168.1.5}"
    return 0
}

# Отключение фонового демона apache2 (оставляем только утилиту htpasswd для генерации bcrypt; uhttpd на OpenWrt не трогаем)
disable_apache_daemon() {
    for srv in apache apache2 httpd; do
        if [ -f "/etc/init.d/${srv}" ]; then
            service_ctl "$srv" stop
            service_ctl "$srv" disable
            rm -f "/etc/init.d/${srv}" 2>/dev/null || true
        fi
    done
    return 0
}

# Универсальное управление системными службами (Alpine OpenRC / OpenWrt procd)
service_ctl() {
    SVC_NAME="$1"
    SVC_ACT="$2"
    if is_openwrt 2>/dev/null; then
        [ "$SVC_NAME" = "crond" ] && SVC_NAME="cron"
        SVC_SCRIPT="/etc/init.d/${SVC_NAME}"
        case "$SVC_ACT" in
            enable)
                [ -x "$SVC_SCRIPT" ] && "$SVC_SCRIPT" enable >/dev/null 2>&1 || true
                return 0
                ;;
            disable)
                [ -x "$SVC_SCRIPT" ] && "$SVC_SCRIPT" disable >/dev/null 2>&1 || true
                return 0
                ;;
            stop)
                [ -x "$SVC_SCRIPT" ] && "$SVC_SCRIPT" stop >/dev/null 2>&1 || true
                return 0
                ;;
            reload)
                if [ -x "$SVC_SCRIPT" ]; then
                    "$SVC_SCRIPT" reload >/dev/null 2>&1 || "$SVC_SCRIPT" restart >/dev/null 2>&1 || return 1
                    return 0
                fi
                return 1
                ;;
            status)
                if [ -x "$SVC_SCRIPT" ] && "$SVC_SCRIPT" running >/dev/null 2>&1; then
                    return 0
                fi
                case "$SVC_NAME" in
                    sing-box)    pgrep -x sing-box >/dev/null 2>&1 ;;
                    mihomo)      pgrep -x mihomo >/dev/null 2>&1 ;;
                    adguardhome) pgrep AdGuardHome >/dev/null 2>&1 ;;
                    cron)        pgrep crond >/dev/null 2>&1 ;;
                    *)           return 1 ;;
                esac
                return $?
                ;;
            *)
                [ -x "$SVC_SCRIPT" ] && "$SVC_SCRIPT" "$SVC_ACT" >/dev/null 2>&1 && return 0
                return 1
                ;;
        esac
    fi

    [ "$SVC_NAME" = "cron" ] && SVC_NAME="crond"
    case "$SVC_ACT" in
        enable)
            rc-update add "$SVC_NAME" default >/dev/null 2>&1 || true
            return 0
            ;;
        disable)
            rc-update del "$SVC_NAME" default >/dev/null 2>&1 || true
            return 0
            ;;
        stop)
            rc-service "$SVC_NAME" stop >/dev/null 2>&1 || "/etc/init.d/${SVC_NAME}" stop >/dev/null 2>&1 || true
            return 0
            ;;
        reload)
            if rc-service "$SVC_NAME" reload >/dev/null 2>&1 || rc-service "$SVC_NAME" restart >/dev/null 2>&1; then
                return 0
            fi
            "/etc/init.d/${SVC_NAME}" restart >/dev/null 2>&1 || return 1
            return 0
            ;;
        status)
            rc-service "$SVC_NAME" status >/dev/null 2>&1 || "/etc/init.d/${SVC_NAME}" status >/dev/null 2>&1
            return $?
            ;;
        *)
            if rc-service "$SVC_NAME" "$SVC_ACT" >/dev/null 2>&1 || "/etc/init.d/${SVC_NAME}" "$SVC_ACT" >/dev/null 2>&1; then
                return 0
            fi
            return 1
            ;;
    esac
}
