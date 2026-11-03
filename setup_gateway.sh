#!/bin/sh
set -e

# ==================== [ НАЧАЛО ЧАСТИ 1 ИЗ 6 ] ====================
# ==============================================================================
# Глобальные пути и переменные (Alpine Linux Homelab Edition)
# Сетевой шлюз (Sing-Box Extended + AdGuard Home) + Модульный Homelab стек
# ==============================================================================
SB_DIR="/etc/sing-box"
SB_CONF="${SB_DIR}/config.json"
SB_ENV="${SB_DIR}/gateway.env"
SB_RULES_DIR="${SB_DIR}/rule_sets"
SB_PROVIDERS_DIR="${SB_DIR}/providers"
CUSTOM_NODES_FILE="${SB_PROVIDERS_DIR}/my_nodes.yaml"
WARP_NODES_FILE="${SB_PROVIDERS_DIR}/warp_nodes.json"
USER_DIRECT_FILE="${SB_RULES_DIR}/user_direct_domains.list"
USER_PROXY_FILE="${SB_RULES_DIR}/user_proxy_domains.list"
USER_DIRECT_JSON="${SB_RULES_DIR}/user_direct_domains.json"
USER_PROXY_JSON="${SB_RULES_DIR}/user_proxy_domains.json"
USER_BYPASS_IPS="${SB_DIR}/bypass_devices.conf"
USER_FORCE_PROXY_IPS="${SB_DIR}/force_proxy_devices.conf"
BACKUP_ARCHIVE="/root/gateway_backup.tar.gz"
STATE_BAK_DIR="/tmp/gateway_state_bak"
CRON_FILE="/etc/crontabs/root"
AUTOUPDATE_LOG="/var/log/gateway_autoupdate.log"
SB_LOG_FILE="/var/log/sing-box.log"
VER_CACHE_FILE="/tmp/gateway_ver.cache"
LAN_SCAN_CACHE="/tmp/gateway_lan_scan.cache"
GATEWAY_LOCK_DIR="/tmp/gateway_op.lock"
UI_VER_FILE="${SB_DIR}/ui/.ui_version"
UI_REPO="Zephyruso/zashboard"
UI_ZIP_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
AGH_CONF="/etc/AdGuardHome/AdGuardHome.yaml"
ALPINE_NFT_CONF="/etc/nftables.nft"
ALPINE_DHCP_CONF="/etc/dnsmasq.d/gateway-dhcp.conf"

# Глобальные пути и переменные подсистемы Homelab
HOMELAB_DIR="${SB_DIR}/homelab"
HOMELAB_ENV="${SB_DIR}/homelab.env"
HOMELAB_STATE="${HOMELAB_DIR}/modules.state"
HOMELAB_LIB_DIR="/usr/lib/gateway"
TORRENT_HOOK="${HOMELAB_LIB_DIR}/torrent-import-hook.sh"
YTDLP_WEB_SCRIPT="${HOMELAB_LIB_DIR}/ytdlp-webui.py"
STORAGE_ROOT="/srv/storage"
STORAGE_MUSIC="${STORAGE_ROOT}/Music"
STORAGE_VIDEOS="${STORAGE_ROOT}/Videos"
STORAGE_VIDEOS_MOVIES="${STORAGE_VIDEOS}/Movies"
STORAGE_VIDEOS_SERIES="${STORAGE_VIDEOS}/Series"
STORAGE_DOWNLOADS="${STORAGE_ROOT}/Downloads"
STORAGE_DL_MUSIC="${STORAGE_DOWNLOADS}/Music"
STORAGE_DL_VIDEOS="${STORAGE_DOWNLOADS}/Videos"
STORAGE_DL_OTHER="${STORAGE_DOWNLOADS}/Other"
STORAGE_INCOMPLETE="${STORAGE_DOWNLOADS}/Incomplete"
STORAGE_INC_TORRENTS="${STORAGE_INCOMPLETE}/torrents"
STORAGE_INC_YTDLP="${STORAGE_INCOMPLETE}/ytdlp"
PKI_PORTAL_DIR="/srv/homelab/pki-portal"
CADDY_CONF="/etc/caddy/Caddyfile"
CADDY_CONFD="/etc/caddy/conf.d"
CADDY_ROOT_CERT="/var/lib/caddy/caddy/pki/authorities/local/root.crt"
MEDIA_GROUP="media"
MEDIA_GID="990"
SMB_USER="homelab"
SMB_PASS=""
JELLYFIN_UNIFIED_MEDIA="yes"
HOMELAB_DOMAIN_SUFFIX="lan"

# Порты локальных бэкендов Homelab (слушают строго 127.0.0.1)
PORT_VAULTWARDEN="8222"
PORT_FORGEJO="3001"
PORT_CODE="8443"
PORT_NAVIDROME="4533"
PORT_JELLYFIN="8096"
PORT_YTDLP="8081"
PORT_TORRENT_WEB="8080"
PORT_TORRENT_PEER="51413"

# Домены Homelab и панелей шлюза (Caddy HTTPS + AdGuard Home DNS Rewrites)
DOM_VAULTWARDEN="vaultwarden.lan"
DOM_FORGEJO="forgejo.lan"
DOM_CODE="code.lan"
DOM_NAVIDROME="music.lan"
DOM_JELLYFIN="jellyfin.lan"
DOM_YTDLP="downloads.lan"
DOM_TORRENT="torrents.lan"
DOM_CA="ca.lan"
DOM_ADGUARD="adguard.lan"
DOM_ZASHBOARD="zashboard.lan"
DOM_SINGBOX="singbox.lan"

SUB_FILTER_STRICT="(?i)(剩余|过期|到期|官网|流量|套餐|重置|expire|traffic|website|official|срок|осталось|трафик|истекает|подписк|тариф|торрент|запрещ|лимит|инфо|новост|поддержк|канал|бот|t[.]me/|ℹ️|⛔|🚫|⚠️|📅|🇷🇺|Россия|Russia|Москва|Moscow|СПб|Белые списки|WhiteList)"
SUB_FILTER_WHITELIST="(?i)(剩余|过期|到期|官网|流量|套餐|重置|expire|traffic|website|official|срок|осталось|трафик|истекает|подписк|тариф|торрент|запрещ|лимит|инфо|новост|поддержк|канал|бот|t[.]me/|ℹ️|⛔|🚫|⚠️|📅)"
ALLOW_RU_NODES="no"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
GH_PROXY=""
LATEST_SB_TAG=""
LATEST_AGH_TAG=""
LATEST_UI_TAG=""
OS_TYPE="alpine"
OS_NAME="Alpine Linux"
SB_ARCH="amd64"
AGH_ARCH="amd64"
ARCH_RAW="x86_64"
SB_GOMEMLIMIT="200MiB"
AGH_GOMEMLIMIT="100MiB"
SYS_CONNTRACK_MAX="65536"
SYS_BUF_MAX="16777216"
TOTAL_RAM_MB="512"

# Инициализация цветовой палитры терминала (автоматически выключается в cron-логах)
init_colors() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        C_RES=$(printf '\033[0m')
        C_BLD=$(printf '\033[1m')
        C_DIM=$(printf '\033[2m')
        C_GRN=$(printf '\033[1;32m')
        C_RED=$(printf '\033[1;31m')
        C_YEL=$(printf '\033[1;33m')
        C_CYN=$(printf '\033[1;36m')
    else
        C_RES=""
        C_BLD=""
        C_DIM=""
        C_GRN=""
        C_RED=""
        C_YEL=""
        C_CYN=""
    fi
    return 0
}
init_colors

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

# Отключение старого сервиса Mihomo при миграции на sing-box-extended
disable_legacy_mihomo() {
    if [ -x /etc/init.d/mihomo ]; then
        rc-service mihomo stop >/dev/null 2>&1 || /etc/init.d/mihomo stop >/dev/null 2>&1 || true
        rc-update del mihomo default >/dev/null 2>&1 || true
    fi
    return 0
}

# Проверка валидности конфигурации sing-box-extended
check_singbox_config() {
    ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
        /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" >/dev/null 2>&1
}

# Проверка 3 независимых слотов прокси: Слот 1 (Подписки HTTP), Слот 2 (my_nodes), Слот 3 (WARP + MASQUE)
is_sub_enabled() {
    case "${SUB_URL:-}" in
        *http://* | *https://*) return 0 ;;
        *) return 1 ;;
    esac
}

count_sub_urls() {
    if ! is_sub_enabled; then
        echo "0"
        return 0
    fi
    printf "%s\n" "$SUB_URL" | tr ' |,' '\n\n\n' | grep -E '^https?://' | wc -l | tr -d ' \t\r\n'
    return 0
}

has_my_nodes() {
    [ -s "$CUSTOM_NODES_FILE" ] && ! grep -q '^proxies:[[:space:]]*\[\][[:space:]]*$' "$CUSTOM_NODES_FILE" 2>/dev/null && \
        awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {found=1} END {exit !found}' "$CUSTOM_NODES_FILE" 2>/dev/null
}

count_my_nodes() {
    if [ -s "$CUSTOM_NODES_FILE" ] && ! grep -q '^proxies:[[:space:]]*\[\][[:space:]]*$' "$CUSTOM_NODES_FILE" 2>/dev/null; then
        awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {c++} END {print c+0}' "$CUSTOM_NODES_FILE" 2>/dev/null
    else
        echo "0"
    fi
    return 0
}

is_warp_enabled() {
    [ -f "$WARP_NODES_FILE" ] && grep -Eq '"type":[[:space:]]*"(wireguard|masque)"' "$WARP_NODES_FILE" 2>/dev/null
}

is_telegram_configured() {
    [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]
}

# Проверка состояния аппаратного Kill-Switch в /etc/nftables.nft
is_killswitch_enabled() {
    [ -f "$ALPINE_NFT_CONF" ] && grep -q "#KILLSWITCH_ACTIVE" "$ALPINE_NFT_CONF" 2>/dev/null
}

# Проверка состояния Умного DHCP-сервера на самом шлюзе Alpine Linux
is_dhcp_server_enabled() {
    [ -f "$ALPINE_DHCP_CONF" ] && pgrep dnsmasq >/dev/null 2>&1
}

# Формирование списка IP-исключений (bypass_devices.conf) для корректной работы DIRECT при включенном Kill-Switch
get_nft_bypass_saddr_clause() {
    if [ ! -s "$USER_BYPASS_IPS" ]; then
        printf ""
        return 0
    fi
    BYP_CSV=$(awk '{
        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", $0);
        if ($0 != "" && $0 !~ /^#/) {
            if (c++) printf ", %s", $0;
            else printf "%s", $0;
        }
    }' "$USER_BYPASS_IPS" 2>/dev/null || true)
    if [ -n "$BYP_CSV" ]; then
        printf "ip saddr != { %s } " "$BYP_CSV"
    fi
    return 0
}

# Динамическое формирование списков разрешенных LAN-портов (Шлюз + активные сервисы Homelab) для nftables
get_homelab_nft_tcp_ports() {
    TCP_LIST="22, 53, 80, 443, 445, 3000, 5357, 7890, 9090, ${PORT_TORRENT_PEER}"
    printf "%s" "$TCP_LIST"
    return 0
}

get_homelab_nft_udp_ports() {
    UDP_LIST="53, 67, 443, 3702, 5353, 7890, ${PORT_TORRENT_PEER}"
    printf "%s" "$UDP_LIST"
    return 0
}

# Настройка нативного nftables на Alpine Linux (защита input_protect для Шлюза и Homelab + Kill-Switch 2.0)
sync_dns_firewall() {
    USE_DNS_REDIRECT="${1:-yes}"
    KS_STATE="${2:-keep}"
    LAN_IF=$(get_lan_ifname)

    if [ "$KS_STATE" = "keep" ]; then
        if is_killswitch_enabled; then
            KS_STATE="yes"
        else
            KS_STATE="no"
        fi
    fi

    BYP_SADDR_CLAUSE=$(get_nft_bypass_saddr_clause)
    LAN_TCP_PORTS=$(get_homelab_nft_tcp_ports)
    LAN_UDP_PORTS=$(get_homelab_nft_udp_ports)

    KS_COMMENT=""
    KS_RULE=""
    if [ "$KS_STATE" = "yes" ]; then
        KS_COMMENT="#KILLSWITCH_ACTIVE"
        KS_RULE="iifname \"${LAN_IF}\" oifname != { \"singbox-tun\", \"lo\" } ${BYP_SADDR_CLAUSE}ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } reject"
    fi

    DNS_RULE=""
    if [ "$USE_DNS_REDIRECT" = "yes" ]; then
        DNS_RULE="iifname \"${LAN_IF}\" meta l4proto { tcp, udp } th dport 53 redirect to :53"
    fi

    cat << NFT_ALPINE > "${ALPINE_NFT_CONF}.tmp.$$"
#!/usr/sbin/nft -f
${KS_COMMENT}

table inet gateway_fw
delete table inet gateway_fw

table inet gateway_fw {
    chain input_protect {
        type filter hook input priority filter - 5; policy accept;
        iifname "lo" accept
        ct state established,related accept
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16 } tcp dport { ${LAN_TCP_PORTS} } accept
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16 } udp dport { ${LAN_UDP_PORTS} } accept
        ip daddr { 224.0.0.251, 239.255.255.250 } udp dport { 3702, 5353 } accept
        tcp dport { 80, 443, 445, 3000, 3001, 4533, 5357, 7890, 8080, 8081, 8096, 8222, 8443, 9090 } drop
        udp dport { 443, 3702, 5353, 7890 } drop
    }

    chain forward_mss {
        type filter hook forward priority mangle; policy accept;
        oifname "singbox-tun" tcp flags syn tcp option maxseg size set rt mtu
        iifname "singbox-tun" tcp flags syn tcp option maxseg size set rt mtu
    }

    chain forward_filter {
        type filter hook forward priority filter - 5; policy accept;
        meta nfproto ipv6 drop
        iifname "${LAN_IF}" meta l4proto { tcp, udp } th dport 853 reject
        ${KS_RULE}
    }

    chain prerouting_dns {
        type nat hook prerouting priority dstnat - 5; policy accept;
        ${DNS_RULE}
    }

    chain postrouting_nat {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${LAN_IF}" masquerade
    }
}
NFT_ALPINE
    chmod +x "${ALPINE_NFT_CONF}.tmp.$$" 2>/dev/null || true
    if nft --check -f "${ALPINE_NFT_CONF}.tmp.$$" >/dev/null 2>&1; then
        mv -f "${ALPINE_NFT_CONF}.tmp.$$" "$ALPINE_NFT_CONF"
        nft -f "$ALPINE_NFT_CONF" 2>/dev/null || true
    else
        rm -f "${ALPINE_NFT_CONF}.tmp.$$"
        echo "${C_RED}[X] Ошибка проверки синтаксиса nftables! Сохранена предыдущая конфигурация.${C_RES}" >&2
        return 1
    fi
    rc-update add nftables default >/dev/null 2>&1 || true
    rc-service nftables start >/dev/null 2>&1 || true
    return 0
}

# Автоматическая синхронизация DNS Rewrites (*.lan -> LAN_IP с enabled: true) в AdGuardHome.yaml
sync_agh_homelab_rewrites() {
    TARGET_LAN_IP="${1:-$(get_current_lan_ip)}"
    [ -f "$AGH_CONF" ] || return 0
    AGH_WAS_RUNNING="no"
    if pgrep AdGuardHome >/dev/null 2>&1; then
        AGH_WAS_RUNNING="yes"
        rc-service adguardhome stop >/dev/null 2>&1 || /etc/init.d/adguardhome stop >/dev/null 2>&1 || true
    fi

    awk -v lip="$TARGET_LAN_IP" '
        /^filtering:/ {
            print "filtering:"
            print "  protection_enabled: true"
            print "  filtering_enabled: true"
            print "  rewrites:"
            print "    - domain: '\''*.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''ca.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''adguard.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''zashboard.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''singbox.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''vaultwarden.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''forgejo.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''music.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''jellyfin.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''downloads.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''torrents.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            print "    - domain: '\''code.lan'\''"
            print "      answer: " lip
            print "      enabled: true"
            in_flt=1
            next
        }
        in_flt && /^[^[:space:]]/ { in_flt=0 }
        in_flt { next }
        { print }
    ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv -f "${AGH_CONF}.tmp" "$AGH_CONF"
    chmod 600 "$AGH_CONF" 2>/dev/null || true

    if [ "$AGH_WAS_RUNNING" = "yes" ]; then
        rc-service adguardhome start >/dev/null 2>&1 || /etc/init.d/adguardhome start >/dev/null 2>&1 || true
    fi
    return 0
}

# Обновление IP основного роутера и LAN IP для *.lan внутри AdGuardHome.yaml
update_agh_gateway_ip() {
    NEW_GW="$1"
    NEW_LAN="${2:-$(get_current_lan_ip)}"
    [ -f "$AGH_CONF" ] || return 0
    AGH_WAS_RUNNING="no"
    if pgrep AdGuardHome >/dev/null 2>&1; then
        AGH_WAS_RUNNING="yes"
        rc-service adguardhome stop >/dev/null 2>&1 || /etc/init.d/adguardhome stop >/dev/null 2>&1 || true
    fi
    awk -v gw="$NEW_GW" '
        /^[[:space:]]*bootstrap_dns:/ {
            print "  bootstrap_dns: [" gw ", 77.88.8.8, 77.88.8.1]"
            in_list=1; next
        }
        /^[[:space:]]*local_ptr_upstreams:/ {
            print "  local_ptr_upstreams: [" gw ":53]"
            in_list=1; next
        }
        in_list && /^[[:space:]]*-/ { next }
        in_list { in_list=0 }
        { print }
    ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv -f "${AGH_CONF}.tmp" "$AGH_CONF"
    chmod 600 "$AGH_CONF" 2>/dev/null || true
    sync_agh_homelab_rewrites "$NEW_LAN"
    if [ "$AGH_WAS_RUNNING" = "yes" ]; then
        rc-service adguardhome start >/dev/null 2>&1 || /etc/init.d/adguardhome start >/dev/null 2>&1 || true
    fi
    return 0
}

# Безопасное экранирование одинарных кавычек для записи в .env файлы
escape_single_quotes() {
    printf "%s" "$1" | tr -d '\r' | sed "s/'/'\\\\''/g"
    return 0
}

# Чтение и сохранение параметров сетевого шлюза (gateway.env) и Homelab (homelab.env)
load_gateway_env() {
    if [ -f "$SB_ENV" ]; then
        sed -i 's/\r$//' "$SB_ENV" 2>/dev/null || true
        # shellcheck disable=SC1090
        . "$SB_ENV" 2>/dev/null || true
    fi
    if [ -f "$HOMELAB_ENV" ]; then
        sed -i 's/\r$//' "$HOMELAB_ENV" 2>/dev/null || true
        # shellcheck disable=SC1090
        . "$HOMELAB_ENV" 2>/dev/null || true
    fi

    if [ -z "${GW_IP:-}" ] && [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        GW_IP=$(jq -r '.dns.servers[]? | select(.tag=="dns_local") | .server // empty' "$SB_CONF" 2>/dev/null | head -n 1)
    fi
    if [ -z "${ADMIN_PASS:-}" ] && [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        ADMIN_PASS=$(jq -r '.experimental.clash_api.secret // empty' "$SB_CONF" 2>/dev/null | head -n 1)
    fi
    if [ -z "${SUB_URL:-}" ] && [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        SUB_URL=$(jq -r '[.providers[]? | select(.type=="remote") | .url] | join(" ")' "$SB_CONF" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    case "${SUB_URL:-}" in
        *http://* | *https://*) ;;
        *) SUB_URL="" ;;
    esac

    [ -f "${HOMELAB_DIR}/homelab.env" ] && . "${HOMELAB_DIR}/homelab.env" 2>/dev/null || true
    [ -z "${ALLOW_RU_NODES:-}" ] && ALLOW_RU_NODES="no" || true
    [ -z "${GW_IP:-}" ] && GW_IP=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}') || true
    [ -z "${GW_IP:-}" ] && GW_IP="192.168.1.1" || true
    [ -z "${AGH_USER:-}" ] && [ -f "${AGH_CONF:-/etc/AdGuardHome/AdGuardHome.yaml}" ] && \
        AGH_USER=$(sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "${AGH_CONF:-/etc/AdGuardHome/AdGuardHome.yaml}" 2>/dev/null | head -n 1 | tr -d ' \t\r\n"') || true
    [ -z "${SMB_USER:-}" ] && SMB_USER="${AGH_USER:-homelab}" || true
    [ -z "${SMB_PASS:-}" ] && SMB_PASS="${ADMIN_PASS:-}" || true
    [ -z "${STORAGE_ROOT:-}" ] && STORAGE_ROOT="/srv/storage" || true
    [ -z "${JELLYFIN_UNIFIED_MEDIA:-}" ] && JELLYFIN_UNIFIED_MEDIA="yes" || true
    STORAGE_MUSIC="${STORAGE_ROOT}/Music"
    STORAGE_VIDEOS="${STORAGE_ROOT}/Videos"
    STORAGE_VIDEOS_MOVIES="${STORAGE_VIDEOS}/Movies"
    STORAGE_VIDEOS_SERIES="${STORAGE_VIDEOS}/Series"
    STORAGE_DOWNLOADS="${STORAGE_ROOT}/Downloads"
    STORAGE_DL_MUSIC="${STORAGE_DOWNLOADS}/Music"
    STORAGE_DL_VIDEOS="${STORAGE_DOWNLOADS}/Videos"
    STORAGE_DL_OTHER="${STORAGE_DOWNLOADS}/Other"
    STORAGE_INCOMPLETE="${STORAGE_DOWNLOADS}/Incomplete"
    STORAGE_INC_TORRENTS="${STORAGE_INCOMPLETE}/torrents"
    STORAGE_INC_YTDLP="${STORAGE_INCOMPLETE}/ytdlp"
    return 0
}

save_gateway_env() {
    mkdir -p "$SB_DIR"
    chown root:root "$SB_DIR" 2>/dev/null || true
    chmod 700 "$SB_DIR" 2>/dev/null || true
    umask 077
    ESC_GW=$(escape_single_quotes "${GW_IP:-}")
    ESC_AGHU=$(escape_single_quotes "${AGH_USER:-admin}")
    ESC_PASS=$(escape_single_quotes "${ADMIN_PASS:-}")
    ESC_SUB=$(escape_single_quotes "${SUB_URL:-}")
    ESC_WLIC=$(escape_single_quotes "${WARP_LICENSE:-}")
    ESC_ARU=$(escape_single_quotes "${ALLOW_RU_NODES:-no}")
    ESC_TGB=$(escape_single_quotes "${TG_BOT_TOKEN:-}")
    ESC_TGC=$(escape_single_quotes "${TG_CHAT_ID:-}")
    cat << ENV_EOF > "${SB_ENV}.tmp.$$"
GW_IP='${ESC_GW}'
AGH_USER='${ESC_AGHU}'
ADMIN_PASS='${ESC_PASS}'
SUB_URL='${ESC_SUB}'
WARP_LICENSE='${ESC_WLIC}'
ALLOW_RU_NODES='${ESC_ARU}'
TG_BOT_TOKEN='${ESC_TGB}'
TG_CHAT_ID='${ESC_TGC}'
ENV_EOF
    chown root:root "${SB_ENV}.tmp.$$" 2>/dev/null || true
    chmod 600 "${SB_ENV}.tmp.$$" 2>/dev/null || true
    mv -f "${SB_ENV}.tmp.$$" "$SB_ENV"
    chmod 600 "$SB_ENV" 2>/dev/null || true
    umask 022
    return 0
}

save_homelab_env() {
    mkdir -p "$SB_DIR" "$HOMELAB_DIR"
    chown root:root "$SB_DIR" "$HOMELAB_DIR" 2>/dev/null || true
    chmod 700 "$SB_DIR" 2>/dev/null || true
    chmod 750 "$HOMELAB_DIR" 2>/dev/null || true
    umask 077
    ESC_SMBU=$(escape_single_quotes "${SMB_USER:-${AGH_USER:-homelab}}")
    ESC_SMBP=$(escape_single_quotes "${SMB_PASS:-${ADMIN_PASS:-}}")
    ESC_SROOT=$(escape_single_quotes "${STORAGE_ROOT:-/srv/storage}")
    ESC_JFUNI=$(escape_single_quotes "${JELLYFIN_UNIFIED_MEDIA:-yes}")
    cat << HL_ENV_EOF > "${HOMELAB_ENV}.tmp.$$"
SMB_USER='${ESC_SMBU}'
SMB_PASS='${ESC_SMBP}'
STORAGE_ROOT='${ESC_SROOT}'
JELLYFIN_UNIFIED_MEDIA='${ESC_JFUNI}'
HL_ENV_EOF
    chown root:root "${HOMELAB_ENV}.tmp.$$" 2>/dev/null || true
    chmod 600 "${HOMELAB_ENV}.tmp.$$" 2>/dev/null || true
    mv -f "${HOMELAB_ENV}.tmp.$$" "$HOMELAB_ENV"
    cp -f "$HOMELAB_ENV" "${HOMELAB_DIR}/homelab.env" 2>/dev/null || true
    chmod 600 "$HOMELAB_ENV" "${HOMELAB_DIR}/homelab.env" 2>/dev/null || true
    umask 022
    return 0
}

# Очистка и нормализация домена при вставке ссылки из браузера (https://www.site.com/path -> +.site.com)
sanitize_domain_entry() {
    RAW_DOM=$(printf "%s" "$1" | tr 'A-Z' 'a-z' | sed -E 's|^https?://||; s|/.*$||; s|:.*$||; s|^\*\.\.?||; s|^\+\.||; s|^\.||; s|^www\.||')
    case "$RAW_DOM" in
        ""|*[![:alnum:]._-]*|*..*|.*)
            return 1
            ;;
        *.*)
            printf "+.%s" "$RAW_DOM"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Вывод пронумерованного списка строк из файла (для доменов и IP устройств)
list_entries_numbered() {
    TARGET_FILE="$1"
    if [ ! -s "$TARGET_FILE" ] || ! awk 'NF {found=1} END {exit !found}' "$TARGET_FILE" 2>/dev/null; then
        echo "  ${C_DIM}(список пуст)${C_RES}"
        return 0
    fi
    awk -v c="${C_CYN}" -v r="${C_RES}" 'NF {idx++; printf "  %s[%d]%s %s\n", c, idx, r, $0}' "$TARGET_FILE" 2>/dev/null || true
    return 0
}

count_file_entries() {
    TARGET_FILE="$1"
    if [ -s "$TARGET_FILE" ]; then
        awk 'NF {c++} END {print c+0}' "$TARGET_FILE" 2>/dev/null
    else
        echo "0"
    fi
    return 0
}

get_entry_by_index() {
    TARGET_FILE="$1"
    TARGET_IDX="$2"
    awk -v target="$TARGET_IDX" 'NF {idx++; if (idx == target) {print $0; exit}}' "$TARGET_FILE" 2>/dev/null
    return 0
}

# Точечное удаление строки (домена или IP) по порядковому номеру
delete_entry_by_index() {
    TARGET_FILE="$1"
    DEL_IDX="$2"
    FALLBACK_VAL="${3:-}"
    case "$DEL_IDX" in
        ''|*[!0-9]*)
            echo "${C_RED}[X] Некорректный номер.${C_RES}"
            return 1
            ;;
    esac
    TOTAL_E=$(count_file_entries "$TARGET_FILE")
    if [ "$DEL_IDX" -lt 1 ] || [ "$DEL_IDX" -gt "$TOTAL_E" ]; then
        echo "${C_RED}[X] Запись с номером ${DEL_IDX} не существует (доступно: 1..${TOTAL_E}).${C_RES}"
        return 1
    fi
    awk -v target="$DEL_IDX" -v fb="$FALLBACK_VAL" '
        NF {
            idx++
            if (idx == target) next
            print $0
            kept++
        }
        END {
            if (kept == 0 && fb != "") print fb
        }
    ' "$TARGET_FILE" > "${TARGET_FILE}.tmp" && mv -f "${TARGET_FILE}.tmp" "$TARGET_FILE"
    return 0
}

# Компиляция текстовых пользовательских списков доменов (.list) в JSON rule-set (version 3)
# Включает автоматическую защиту локальной зоны +.lan от попадания в FakeIP
sync_user_domain_rulesets() {
    mkdir -p "$SB_RULES_DIR"
    [ -f "$USER_DIRECT_FILE" ] || printf "+.localdomain\n+.lan\n" > "$USER_DIRECT_FILE"
    grep -qxF "+.lan" "$USER_DIRECT_FILE" 2>/dev/null || echo "+.lan" >> "$USER_DIRECT_FILE"
    [ -f "$USER_PROXY_FILE" ] || echo "+.chatgpt.com" > "$USER_PROXY_FILE"
    sed -i 's/\r$//' "$USER_DIRECT_FILE" "$USER_PROXY_FILE" "$CUSTOM_NODES_FILE" 2>/dev/null || true

    if command -v jq >/dev/null 2>&1; then
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^+\.//;s/^\.//' "$USER_DIRECT_FILE" 2>/dev/null | grep -v '^$' | \
            jq -R . | jq -s '{version: 3, rules: [{domain_suffix: (if length > 0 then . else ["localdomain", "lan"] end)}]}' > "${USER_DIRECT_JSON}.tmp" && \
            mv "${USER_DIRECT_JSON}.tmp" "$USER_DIRECT_JSON"

        sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^+\.//;s/^\.//' "$USER_PROXY_FILE" 2>/dev/null | grep -v '^$' | \
            jq -R . | jq -s '{version: 3, rules: [{domain_suffix: (if length > 0 then . else ["chatgpt.com"] end)}]}' > "${USER_PROXY_JSON}.tmp" && \
            mv "${USER_PROXY_JSON}.tmp" "$USER_PROXY_JSON"
    else
        cat << 'J_DIR' > "$USER_DIRECT_JSON"
{"version":3,"rules":[{"domain_suffix":["localdomain","lan"]}]}
J_DIR
        cat << 'J_PRX' > "$USER_PROXY_JSON"
{"version":3,"rules":[{"domain_suffix":["chatgpt.com"]}]}
J_PRX
    fi
    return 0
}

# Сборка JSON-массивов IP-адресов устройств (DIRECT и Full-VPN)
get_ip_cidr_json_array() {
    SRC_FILE="$1"
    if [ ! -s "$SRC_FILE" ] || ! command -v jq >/dev/null 2>&1; then
        printf "[]"
        return 0
    fi
    sed -i 's/\r$//' "$SRC_FILE" 2>/dev/null || true
    awk '{
        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", $0);
        if ($0 != "") {
            if (index($0, "/") == 0) print $0 "/32";
            else print $0;
        }
    }' "$SRC_FILE" | jq -R . | jq -s .
    return 0
}
# ==================== [ КОНЕЦ ЧАСТИ 1 ИЗ 6 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 2 ИЗ 6 ] ====================
# Генерация эталонного /etc/sing-box/config.json (оптимизировано под 200+ нод, AI-сервера и зону .lan)
generate_singbox_config() {
    check_github_mirror
    sync_user_domain_rulesets
    [ -z "${ADMIN_PASS:-}" ] && load_gateway_env || true
    [ -z "${ADMIN_PASS:-}" ] && ADMIN_PASS="admin" || true
    CUR_LIP_SB=$(get_current_lan_ip)

    PROVIDERS_JSON_ARR="[]"
    PROVIDER_TAGS_JSON="[]"
    ACTIVE_SUB_REGEX=$(get_sub_filter_regex)

    if command -v jq >/dev/null 2>&1; then
        # Слот 1: Поддержка одной или нескольких HTTP(S) подписок
        if is_sub_enabled; then
            IDX=0
            for U_ITEM in $(printf "%s\n" "$SUB_URL" | tr ' |,' '\n\n\n' | grep -E '^https?://'); do
                IDX=$((IDX + 1))
                if [ "$IDX" -eq 1 ]; then
                    P_TAG="custom_sub"
                else
                    P_TAG="custom_sub_${IDX}"
                fi
                PROVIDERS_JSON_ARR=$(printf "%s" "$PROVIDERS_JSON_ARR" | jq \
                    --arg tag "$P_TAG" \
                    --arg url "$U_ITEM" \
                    --arg excl "$ACTIVE_SUB_REGEX" \
                    '. + [{
                        "tag": $tag,
                        "type": "remote",
                        "url": $url,
                        "update_interval": "24h",
                        "download_detour": "DIRECT",
                        "exclude": $excl,
                        "health_check": {
                            "enabled": true,
                            "url": "https://www.gstatic.com/generate_204",
                            "interval": "3m",
                            "timeout": "8s"
                        }
                    }]')
                PROVIDER_TAGS_JSON=$(printf "%s" "$PROVIDER_TAGS_JSON" | jq --arg tag "$P_TAG" '. + [$tag]')
            done
        fi

        # Слот 2: Локальные ключи URI в my_nodes.yaml
        if has_my_nodes; then
            PROVIDERS_JSON_ARR=$(printf "%s" "$PROVIDERS_JSON_ARR" | jq \
                --arg path "$CUSTOM_NODES_FILE" \
                '. + [{
                    "tag": "my_nodes",
                    "type": "local",
                    "path": $path,
                    "health_check": {
                        "enabled": true,
                        "url": "https://www.gstatic.com/generate_204",
                        "interval": "3m",
                        "timeout": "8s"
                    }
                }]')
            PROVIDER_TAGS_JSON=$(printf "%s" "$PROVIDER_TAGS_JSON" | jq '. + ["my_nodes"]')
        fi
    fi

    BYPASS_IPS_ARR=$(get_ip_cidr_json_array "$USER_BYPASS_IPS")
    FORCE_IPS_ARR=$(get_ip_cidr_json_array "$USER_FORCE_PROXY_IPS")

    BYPASS_ROUTE_RULE=""
    if [ "$BYPASS_IPS_ARR" != "[]" ]; then
        BYPASS_ROUTE_RULE="{\"source_ip_cidr\": ${BYPASS_IPS_ARR}, \"outbound\": \"DIRECT\"},"
    fi

    FORCE_OUTBOUND_GROUP=""
    FORCE_ROUTE_RULE=""
    if [ "$FORCE_IPS_ARR" != "[]" ]; then
        FORCE_OUTBOUND_GROUP=$(cat << FORCE_GRP
    {
      "type": "selector",
      "tag": "📺 Устройства (Full-VPN)",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🌐 Остальной трафик",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
FORCE_GRP
)
        FORCE_ROUTE_RULE="{\"source_ip_cidr\": ${FORCE_IPS_ARR}, \"outbound\": \"📺 Устройства (Full-VPN)\"},"
    fi

    DNS_FINAL_TAG="dns_proxy"
    if ! is_sub_enabled && ! has_my_nodes && ! is_warp_enabled; then
        DNS_FINAL_TAG="dns_ru"
    fi

    [ -f "$SB_CONF" ] && cp -f "$SB_CONF" "${SB_CONF}.bak" || true

    cat << CONFIG_EOF > "${SB_CONF}.tmp"
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/etc/sing-box/cache.db",
      "store_fakeip": true
    },
    "clash_api": {
      "external_controller": "0.0.0.0:9090",
      "external_ui": "/etc/sing-box/ui",
      "external_ui_download_url": "${GH_PROXY}${UI_ZIP_URL}",
      "secret": "PLACEHOLDER_SECRET",
      "default_mode": "rule"
    },
    "unified_delay": {
      "enabled": true
    }
  },
  "http_clients": [
    {
      "tag": "default"
    }
  ],
  "dns": {
    "servers": [
      {
        "tag": "dns_proxy",
        "type": "https",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "⚡ Авто (Самый быстрый)"
      },
      {
        "tag": "dns_ru",
        "type": "https",
        "server": "77.88.8.8",
        "server_port": 443,
        "path": "/dns-query",
        "tls": {
          "enabled": true,
          "server_name": "common.dot.dns.yandex.net"
        }
      },
      {
        "tag": "dns_ru_udp",
        "type": "udp",
        "server": "77.88.8.8",
        "server_port": 53
      },
      {
        "tag": "dns_local",
        "type": "udp",
        "server": "PLACEHOLDER_GW_IP",
        "server_port": 53
      },
      {
        "tag": "dns_fakeip",
        "type": "fakeip",
        "inet4_range": "198.18.0.0/15"
      }
    ],
    "rules": [
      {
        "clash_mode": "direct",
        "server": "dns_ru"
      },
      {
        "domain": [
          "ca.lan",
          "adguard.lan",
          "zashboard.lan",
          "singbox.lan",
          "vaultwarden.lan",
          "forgejo.lan",
          "music.lan",
          "jellyfin.lan",
          "downloads.lan",
          "torrents.lan",
          "code.lan"
        ],
        "domain_suffix": [
          ".lan"
        ],
        "action": "predefined",
        "rcode": "NOERROR",
        "answer": [
          "ca.lan. 60 IN A ${CUR_LIP_SB}",
          "adguard.lan. 60 IN A ${CUR_LIP_SB}",
          "zashboard.lan. 60 IN A ${CUR_LIP_SB}",
          "singbox.lan. 60 IN A ${CUR_LIP_SB}",
          "vaultwarden.lan. 60 IN A ${CUR_LIP_SB}",
          "forgejo.lan. 60 IN A ${CUR_LIP_SB}",
          "music.lan. 60 IN A ${CUR_LIP_SB}",
          "jellyfin.lan. 60 IN A ${CUR_LIP_SB}",
          "downloads.lan. 60 IN A ${CUR_LIP_SB}",
          "torrents.lan. 60 IN A ${CUR_LIP_SB}",
          "code.lan. 60 IN A ${CUR_LIP_SB}"
        ]
      },
      {
        "domain_suffix": [
          ".home.arpa",
          ".local"
        ],
        "server": "dns_local"
      },
      {
        "domain": [
          "use-application-dns.net"
        ],
        "action": "predefined",
        "rcode": "NXDOMAIN"
      },
      {
        "query_type": [
          "HTTPS",
          "SVCB",
          "AAAA"
        ],
        "action": "predefined",
        "rcode": "NOERROR"
      },
      {
        "rule_set": [
          "private_domain"
        ],
        "server": "dns_local"
      },
      {
        "rule_set": [
          "ntp_domain",
          "torrent_domain",
          "user_direct_domains"
        ],
        "server": "dns_ru"
      },
      {
        "rule_set": [
          "user_proxy_domains"
        ],
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      },
      {
        "rule_set": [
          "ru_domain"
        ],
        "server": "dns_ru"
      },
      {
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      }
    ],
    "final": "${DNS_FINAL_TAG}",
    "strategy": "ipv4_only",
    "reverse_mapping": true
  },
  "inbounds": [
    {
      "type": "direct",
      "tag": "dns-in",
      "listen": "127.0.0.1",
      "listen_port": 1053
    },
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": 7890
    },
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "singbox-tun",
      "address": [
        "172.19.0.1/30"
      ],
      "mtu": 1492,
      "auto_route": true,
      "auto_redirect": true,
      "strict_route": true,
      "stack": "mixed",
      "udp_timeout": "5m"
    }
  ],
  "providers": ${PROVIDERS_JSON_ARR},
  "outbounds": [
    {
      "type": "urltest",
      "tag": "⚡ Авто (Самый быстрый)",
      "providers": ${PROVIDER_TAGS_JSON},
      "url": "https://www.gstatic.com/generate_204",
      "interval": "3m",
      "tolerance": 35,
      "idle_timeout": "30m"
    },
    {
      "type": "selector",
      "tag": "🤖 AI & Google",
      "outbounds": [
        "⚡ Авто (Самый быстрый)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🎮 Roblox",
      "outbounds": [
        "⚡ Авто (Самый быстрый)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "▶️ YouTube & Spotify",
      "outbounds": [
        "⚡ Авто (Самый быстрый)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "💬 Мессенджеры & Discord",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    ${FORCE_OUTBOUND_GROUP}
    {
      "type": "selector",
      "tag": "🌐 Остальной трафик",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "direct",
      "tag": "DIRECT"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "default_http_client": "default",
    "default_domain_resolver": {
      "server": "dns_ru",
      "strategy": "ipv4_only"
    },
    "final": "🌐 Остальной трафик",
    "rules": [
      {
        "inbound": [
          "dns-in"
        ],
        "action": "hijack-dns"
      },
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "clash_mode": "direct",
        "outbound": "DIRECT"
      },
      {
        "clash_mode": "global",
        "outbound": "⚡ Авто (Самый быстрый)"
      },
      {
        "ip_is_private": true,
        "outbound": "DIRECT"
      },
      {
        "domain_suffix": [
          ".lan",
          ".home.arpa",
          ".local"
        ],
        "outbound": "DIRECT"
      },
      ${BYPASS_ROUTE_RULE}
      {
        "rule_set": [
          "private_domain",
          "private_ip",
          "user_direct_domains",
          "ntp_domain",
          "torrent_domain"
        ],
        "outbound": "DIRECT"
      },
      {
        "protocol": [
          "bittorrent"
        ],
        "outbound": "DIRECT"
      },
      {
        "port": [
          123
        ],
        "outbound": "DIRECT"
      },
      {
        "port": [
          853
        ],
        "action": "reject"
      },
      {
        "rule_set": [
          "youtube_domain",
          "ai_domain",
          "google_domain",
          "ru_bundle"
        ],
        "network": [
          "udp"
        ],
        "port": [
          443
        ],
        "action": "reject"
      },
      ${FORCE_ROUTE_RULE}
      {
        "rule_set": [
          "youtube_domain",
          "spotify_domain",
          "twitch_domain"
        ],
        "outbound": "▶️ YouTube & Spotify"
      },
      {
        "rule_set": [
          "ai_domain",
          "google_domain"
        ],
        "outbound": "🤖 AI & Google"
      },
      {
        "rule_set": [
          "roblox_domain"
        ],
        "outbound": "🎮 Roblox"
      },
      {
        "network": [
          "udp"
        ],
        "port_range": [
          "50000:50100"
        ],
        "outbound": "💬 Мессенджеры & Discord"
      },
      {
        "network": [
          "udp"
        ],
        "port": [
          3478,
          5349,
          19302
        ],
        "outbound": "💬 Мессенджеры & Discord"
      },
      {
        "rule_set": [
          "telegram_domain",
          "telegram_ip",
          "whatsapp_domain",
          "meta_domain",
          "facebook_ip",
          "discord_domain",
          "discord_voice_ip",
          "stun_domain"
        ],
        "outbound": "💬 Мессенджеры & Discord"
      },
      {
        "rule_set": [
          "user_proxy_domains",
          "ru_bundle",
          "refilter_ip",
          "cloudflare_domain",
          "cloudflare_ip"
        ],
        "outbound": "🌐 Остальной трафик"
      },
      {
        "rule_set": [
          "ru_domain",
          "ru_ip"
        ],
        "outbound": "DIRECT"
      }
    ],
    "rule_set": [
      {
        "tag": "user_direct_domains",
        "type": "local",
        "format": "source",
        "path": "${USER_DIRECT_JSON}"
      },
      {
        "tag": "user_proxy_domains",
        "type": "local",
        "format": "source",
        "path": "${USER_PROXY_JSON}"
      },
      {
        "tag": "private_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/private.srs"
      },
      {
        "tag": "private_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/private.srs"
      },
      {
        "tag": "ntp_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ntp.srs"
      },
      {
        "tag": "stun_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-stun.srs"
      },
      {
        "tag": "torrent_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/tracker.srs"
      },
      {
        "tag": "youtube_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/youtube.srs"
      },
      {
        "tag": "spotify_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/spotify.srs"
      },
      {
        "tag": "twitch_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/twitch.srs"
      },
      {
        "tag": "meta_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/meta.srs"
      },
      {
        "tag": "ai_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ai-!cn.srs"
      },
      {
        "tag": "google_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/google.srs"
      },
      {
        "tag": "roblox_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/roblox.srs"
      },
      {
        "tag": "telegram_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/telegram.srs"
      },
      {
        "tag": "telegram_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/telegram.srs"
      },
      {
        "tag": "whatsapp_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/whatsapp.srs"
      },
      {
        "tag": "facebook_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/facebook.srs"
      },
      {
        "tag": "discord_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/discord.srs"
      },
      {
        "tag": "discord_voice_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/sb-rule-sets/main/discord-voice-ip-list.srs"
      },
      {
        "tag": "cloudflare_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/cloudflare.srs"
      },
      {
        "tag": "cloudflare_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/cloudflare.srs"
      },
      {
        "tag": "ru_bundle",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/sb-rule-sets/main/ru-bundle.srs"
      },
      {
        "tag": "refilter_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/sb-rule-sets/main/rknasnblock.srs"
      },
      {
        "tag": "ru_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ru.srs"
      },
      {
        "tag": "ru_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/ru.srs"
      }
    ]
  }
}
CONFIG_EOF

    # Атомарная подстановка секретов и сборка гибридного пула "☁️ Amnezia WARP" (4 UDP AWG + 1 TCP MASQUE H2)
    if command -v jq >/dev/null 2>&1; then
        if is_warp_enabled; then
            if [ "$PROVIDER_TAGS_JSON" != "[]" ]; then
                jq --arg secret "$ADMIN_PASS" --arg gw "$GW_IP" --arg wlic "${WARP_LICENSE:-}" --slurpfile w "$WARP_NODES_FILE" '
                    ($w[0].masque // {
                        "type": "masque",
                        "tag": "☁️ WARP MASQUE (TCP/H2)",
                        "use_http2": true,
                        "use_l4_proxy": false,
                        "use_ipv6": false,
                        "profile": {
                            "detour": "DIRECT",
                            "id": "",
                            "auth_token": "",
                            "license_key": $wlic
                        },
                        "address": "162.159.198.2",
                        "port": 443,
                        "udp_timeout": "5m0s",
                        "udp_keepalive_period": "30s",
                        "reconnect_delay": "5s",
                        "handshake_timeout": "10s",
                        "congestion_controller": "bbr",
                        "tls": {
                            "server_name": "",
                            "insecure": false,
                            "fragment": true,
                            "fragment_fallback_delay": "500ms",
                            "record_fragment": true
                        }
                    }) as $msq
                    | (($w[0].outbounds | map(.tag)) + [$msq.tag]) as $warp_tags
                    | .experimental.clash_api.secret = $secret
                    | (.dns.servers[] | select(.tag=="dns_local") | .server) = $gw
                    | .endpoints = ($w[0].outbounds // [])
                    | (.outbounds[] | select(.type == "selector" and .providers != null) | .outbounds) += ["☁️ Amnezia WARP", $msq.tag]
                    | .outbounds = (
                        [.outbounds[0]] + [{
                            "type": "urltest",
                            "tag": "☁️ Amnezia WARP",
                            "outbounds": $warp_tags,
                            "url": "https://cp.cloudflare.com/generate_204",
                            "interval": "3m",
                            "tolerance": 50,
                            "idle_timeout": "30m"
                        }] + .outbounds[1:-1] + [$msq, .outbounds[-1]]
                    )
                ' "${SB_CONF}.tmp" > "${SB_CONF}.final.$$"
            else
                jq --arg secret "$ADMIN_PASS" --arg gw "$GW_IP" --arg wlic "${WARP_LICENSE:-}" --slurpfile w "$WARP_NODES_FILE" '
                    ($w[0].masque // {
                        "type": "masque",
                        "tag": "☁️ WARP MASQUE (TCP/H2)",
                        "use_http2": true,
                        "use_l4_proxy": false,
                        "use_ipv6": false,
                        "profile": {
                            "detour": "DIRECT",
                            "id": "",
                            "auth_token": "",
                            "license_key": $wlic
                        },
                        "address": "162.159.198.2",
                        "port": 443,
                        "udp_timeout": "5m0s",
                        "udp_keepalive_period": "30s",
                        "reconnect_delay": "5s",
                        "handshake_timeout": "10s",
                        "congestion_controller": "bbr",
                        "tls": {
                            "server_name": "",
                            "insecure": false,
                            "fragment": true,
                            "fragment_fallback_delay": "500ms",
                            "record_fragment": true
                        }
                    }) as $msq
                    | (($w[0].outbounds | map(.tag)) + [$msq.tag]) as $warp_tags
                    | .experimental.clash_api.secret = $secret
                    | (.dns.servers[] | select(.tag=="dns_local") | .server) = $gw
                    | del(.providers)
                    | .endpoints = ($w[0].outbounds // [])
                    | (.outbounds[] | select(.type == "urltest" and .providers != null)) |= (
                        del(.providers)
                        | .outbounds = $warp_tags
                    )
                    | (.outbounds[] | select(.type == "selector" and .providers != null)) |= (
                        del(.providers)
                        | .outbounds = ((.outbounds // []) + ["☁️ Amnezia WARP"] + $warp_tags)
                    )
                    | .outbounds = (
                        [.outbounds[0]] + [{
                            "type": "urltest",
                            "tag": "☁️ Amnezia WARP",
                            "outbounds": $warp_tags,
                            "url": "https://cp.cloudflare.com/generate_204",
                            "interval": "3m",
                            "tolerance": 50,
                            "idle_timeout": "30m"
                        }] + .outbounds[1:-1] + [$msq, .outbounds[-1]]
                    )
                ' "${SB_CONF}.tmp" > "${SB_CONF}.final.$$"
            fi
        elif [ "$PROVIDER_TAGS_JSON" = "[]" ]; then
            jq --arg secret "$ADMIN_PASS" --arg gw "$GW_IP" '
                .experimental.clash_api.secret = $secret
                | (.dns.servers[] | select(.tag=="dns_local") | .server) = $gw
                | del(.providers)
                | (.outbounds[] | select(.providers != null)) |= (
                    del(.providers)
                    | .outbounds = (if (.outbounds == null or (.outbounds | length) == 0) then ["DIRECT"] else .outbounds end)
                )
            ' "${SB_CONF}.tmp" > "${SB_CONF}.final.$$"
        else
            jq --arg secret "$ADMIN_PASS" --arg gw "$GW_IP" '
                .experimental.clash_api.secret = $secret
                | (.dns.servers[] | select(.tag=="dns_local") | .server) = $gw
            ' "${SB_CONF}.tmp" > "${SB_CONF}.final.$$"
        fi
        rm -f "${SB_CONF}.tmp"
        if [ -s "${SB_CONF}.final.$$" ]; then
            chmod 600 "${SB_CONF}.final.$$" 2>/dev/null || true
            mv -f "${SB_CONF}.final.$$" "$SB_CONF"
        else
            rm -f "${SB_CONF}.final.$$"
            [ -f "${SB_CONF}.bak" ] && cp -f "${SB_CONF}.bak" "$SB_CONF" || true
        fi
    else
        chmod 600 "${SB_CONF}.tmp" 2>/dev/null || true
        mv -f "${SB_CONF}.tmp" "$SB_CONF"
    fi
    chmod 600 "$SB_CONF" 2>/dev/null || true
    save_gateway_env
    return 0
}

# Нативное управление службами в Alpine Linux через OpenRC (rc-service / rc-update)
service_ctl() {
    SVC_NAME="$1"
    SVC_ACT="$2"
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

# Чтение логов Sing-Box в Alpine Linux
show_singbox_logs() {
    LINES_CNT="${1:-40}"
    if [ -s "$SB_LOG_FILE" ]; then
        tail -n "$LINES_CNT" "$SB_LOG_FILE" 2>/dev/null || true
    elif [ -f /var/log/messages ]; then
        grep -i "sing-box" /var/log/messages 2>/dev/null | tail -n "$LINES_CNT" || true
    else
        echo "  ${C_DIM}(лог-файл ${SB_LOG_FILE} пока пуст)${C_RES}"
    fi
    return 0
}

# Снимок состояния перед изменениями в меню (для мгновенного авто-отката при сбое)
backup_gateway_state() {
    rm -rf "$STATE_BAK_DIR"
    mkdir -p "$STATE_BAK_DIR"
    for f in "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" "$CUSTOM_NODES_FILE" "$WARP_NODES_FILE" \
             "$USER_DIRECT_FILE" "$USER_PROXY_FILE" "$USER_BYPASS_IPS" "$USER_FORCE_PROXY_IPS"; do
        [ -f "$f" ] && cp -f "$f" "$STATE_BAK_DIR/" 2>/dev/null || true
    done
    return 0
}

# Восстановление состояния при ошибке синтаксиса или старта
restore_gateway_state() {
    [ -d "$STATE_BAK_DIR" ] || return 0
    [ -f "${STATE_BAK_DIR}/config.json" ] && cp -f "${STATE_BAK_DIR}/config.json" "$SB_CONF" || true
    [ -f "${STATE_BAK_DIR}/gateway.env" ] && cp -f "${STATE_BAK_DIR}/gateway.env" "$SB_ENV" || true
    [ -f "${STATE_BAK_DIR}/homelab.env" ] && cp -f "${STATE_BAK_DIR}/homelab.env" "$HOMELAB_ENV" || true
    [ -f "${STATE_BAK_DIR}/my_nodes.yaml" ] && cp -f "${STATE_BAK_DIR}/my_nodes.yaml" "$CUSTOM_NODES_FILE" || true
    [ -f "${STATE_BAK_DIR}/warp_nodes.json" ] && cp -f "${STATE_BAK_DIR}/warp_nodes.json" "$WARP_NODES_FILE" || true
    [ -f "${STATE_BAK_DIR}/user_direct_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_direct_domains.list" "$USER_DIRECT_FILE" || true
    [ -f "${STATE_BAK_DIR}/user_proxy_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_proxy_domains.list" "$USER_PROXY_FILE" || true
    [ -f "${STATE_BAK_DIR}/bypass_devices.conf" ] && cp -f "${STATE_BAK_DIR}/bypass_devices.conf" "$USER_BYPASS_IPS" || true
    [ -f "${STATE_BAK_DIR}/force_proxy_devices.conf" ] && cp -f "${STATE_BAK_DIR}/force_proxy_devices.conf" "$USER_FORCE_PROXY_IPS" || true
    chmod 600 "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" 2>/dev/null || true
    sync_user_domain_rulesets
    load_gateway_env
    service_ctl sing-box restart
    return 0
}

# Наглядный отчет по 3 независимым слотам прокси
print_proxy_slots_report() {
    load_gateway_env
    if [ "${ALLOW_RU_NODES:-no}" = "yes" ]; then
        RU_FLT_TAG="${C_YEL}Каскады РФ/БС: ПОКАЗАНЫ${C_RES}"
    else
        RU_FLT_TAG="Каскады РФ/БС: СКРЫТЫ"
    fi

    SUB_CNT=$(count_sub_urls)
    if [ "$SUB_CNT" -gt 1 ]; then
        SLOT1_INFO="${C_GRN}АКТИВНЫ${C_RES} (${SUB_CNT} подписки | ${RU_FLT_TAG})"
    elif [ "$SUB_CNT" -eq 1 ]; then
        SLOT1_INFO="${C_GRN}АКТИВНА${C_RES} (${SUB_URL} | ${RU_FLT_TAG})"
    else
        SLOT1_INFO="${C_DIM}ОТКЛЮЧЕНА${C_RES} (${RU_FLT_TAG})"
    fi

    MY_CNT=$(count_my_nodes)
    if [ "$MY_CNT" -gt 0 ]; then
        SLOT2_INFO="${C_GRN}АКТИВЕН${C_RES} (${MY_CNT} шт. в my_nodes.yaml)"
    else
        SLOT2_INFO="${C_DIM}ПУСТО (0 ключей)${C_RES}"
    fi

    if is_warp_enabled; then
        if [ -n "${WARP_LICENSE:-}" ]; then
            SLOT3_INFO="${C_GRN}АКТИВЕН${C_RES} (4 ноды UDP AWG WARP+ + 1 нода TCP MASQUE H2 -> '☁️ Amnezia WARP')"
        else
            SLOT3_INFO="${C_GRN}АКТИВЕН${C_RES} (4 ноды UDP AWG 2.0 + 1 нода TCP MASQUE H2 -> '☁️ Amnezia WARP')"
        fi
    else
        SLOT3_INFO="${C_DIM}ОТКЛЮЧЕН${C_RES}"
    fi

    echo " • Слот 1 [Подписки по ссылке]: ${SLOT1_INFO}"
    echo " • Слот 2 [Личные ключи URI]:   ${SLOT2_INFO}"
    echo " • Слот 3 [Amnezia WARP + H2]:  ${SLOT3_INFO}"
    return 0
}

# Вывод пронумерованного списка личных ключей в my_nodes.yaml
list_my_nodes() {
    if ! has_my_nodes; then
        echo " ${C_DIM}[i] Список личных ключей (my_nodes.yaml) пуст.${C_RES}"
        return 0
    fi
    echo " ${C_CYN}--- Список ваших ключей в ${CUSTOM_NODES_FILE} ---${C_RES}"
    awk -v c="${C_CYN}" -v r="${C_RES}" '
        NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {
            idx++
            line = $0
            proto = line
            sub(/:\/\/.*/, "", proto)
            tag = "(без названия)"
            if (index(line, "#") > 0) {
                tag = substr(line, index(line, "#") + 1)
                gsub(/%20/, " ", tag)
            }
            host = line
            sub(/^[a-zA-Z0-9+-]+:\/\/([^@]*@)?/, "", host)
            sub(/[\/?#].*/, "", host)
            if (length(host) > 34) host = substr(host, 1, 31) "..."
            printf "  %s[%d]%s %-10s | %-34s | #%s\n", c, idx, r, proto "://", host, tag
        }
    ' "$CUSTOM_NODES_FILE" 2>/dev/null || true
    return 0
}

# Точечное удаление личного ключа по его порядковому номеру
delete_my_node_by_index() {
    DEL_IDX="$1"
    case "$DEL_IDX" in
        ''|*[!0-9]*)
            echo "${C_RED}[X] Некорректный номер ключа.${C_RES}"
            return 1
            ;;
    esac
    TOTAL_K=$(count_my_nodes)
    if [ "$DEL_IDX" -lt 1 ] || [ "$DEL_IDX" -gt "$TOTAL_K" ]; then
        echo "${C_RED}[X] Ключ с номером ${DEL_IDX} не существует (доступно: 1..${TOTAL_K}).${C_RES}"
        return 1
    fi
    awk -v target="$DEL_IDX" '
        NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {
            idx++
            if (idx == target) next
            print $0
            kept++
        }
        END {
            if (kept == 0) print "proxies: []"
        }
    ' "$CUSTOM_NODES_FILE" > "${CUSTOM_NODES_FILE}.tmp" && mv "${CUSTOM_NODES_FILE}.tmp" "$CUSTOM_NODES_FILE"
    return 0
}

# Безопасное применение изменений с проверкой старта процесса и интерфейса singbox-tun
apply_and_verify_singbox() {
    ACTION_TITLE="${1:-Обновление конфигурации}"
    ensure_alpine_modules
    generate_singbox_config

    if ! check_singbox_config; then
        echo "${C_RED}[X] Ошибка синтаксиса при действии: ${ACTION_TITLE}!${C_RES}"
        ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
            /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" || true
        echo "${C_YEL}[!] Выполняется авто-откат к предыдущей рабочей конфигурации...${C_RES}"
        restore_gateway_state
        return 1
    fi

    service_ctl sing-box restart

    WAIT_OK="no"
    W_IDX=0
    while [ "$W_IDX" -lt 8 ]; do
        if pgrep sing-box >/dev/null 2>&1 && ip link show singbox-tun >/dev/null 2>&1; then
            WAIT_OK="yes"
            break
        fi
        sleep 1
        W_IDX=$((W_IDX + 1))
    done

    if [ "$WAIT_OK" = "yes" ]; then
        sync_dns_firewall "yes" "keep" >/dev/null 2>&1 || true
        reload_singbox_api
        echo "---------------------------------------------------------------"
        echo "${C_GRN}[✓] ${ACTION_TITLE}: УСПЕШНО (Sing-Box ЗАПУЩЕН | singbox-tun АКТИВЕН)${C_RES}"
        print_proxy_slots_report
        echo "---------------------------------------------------------------"
        return 0
    else
        echo "---------------------------------------------------------------"
        echo "${C_RED}[X] Служба Sing-Box не смогла запуститься (${ACTION_TITLE})!${C_RES}"
        echo "--- Причина из системного журнала ---"
        show_singbox_logs 8
        echo "---------------------------------------------------------------"
        echo "${C_YEL}[!] Выполняется авто-откат к предыдущей рабочей конфигурации...${C_RES}"
        restore_gateway_state
        return 1
    fi
}

# Отправка текстового уведомления в Telegram (через туннель Sing-Box или напрямую)
send_telegram_msg() {
    MSG_TEXT="$1"
    load_gateway_env
    is_telegram_configured || return 0

    TG_API_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
    for CURL_P in "-x http://127.0.0.1:7890" ""; do
        # shellcheck disable=SC2086
        if curl -fsSL --curves X25519:P-256 --connect-timeout 4 -m 8 $CURL_P \
            -X POST "$TG_API_URL" \
            --data-urlencode "chat_id=${TG_CHAT_ID}" \
            --data-urlencode "text=${MSG_TEXT}" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Отправка архива резервной копии шлюза и Homelab файлом в Telegram
send_telegram_backup() {
    BAK_FILE="${1:-$BACKUP_ARCHIVE}"
    load_gateway_env
    if ! is_telegram_configured; then
        echo "${C_YEL}[!] Telegram-бот не настроен (укажите Токен и Chat ID в меню).${C_RES}"
        return 1
    fi
    if [ ! -f "$BAK_FILE" ]; then
        echo "${C_RED}[X] Файл бэкапа ${BAK_FILE} не найден!${C_RES}"
        return 1
    fi

    CAPTION_TXT="📦 Бэкап шлюза и Homelab (${OS_NAME})
🌐 LAN IP: $(get_current_lan_ip)
🕒 Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    TG_DOC_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument"

    echo "Отправка архива ${BAK_FILE} в ваш Telegram..."
    for CURL_P in "-x http://127.0.0.1:7890" ""; do
        # shellcheck disable=SC2086
        if curl -fsSL --curves X25519:P-256 --connect-timeout 5 -m 30 $CURL_P \
            -F "chat_id=${TG_CHAT_ID}" \
            -F "caption=${CAPTION_TXT}" \
            -F "document=@${BAK_FILE}" \
            "$TG_DOC_URL" >/dev/null 2>&1; then
            echo "${C_GRN}[✓] Архив бэкапа успешно доставлен в ваш Telegram!${C_RES}"
            return 0
        fi
    done
    echo "${C_RED}[X] Не удалось отправить бэкап в Telegram (проверьте Токен, Chat ID и соединение).${C_RES}"
    return 1
}

# Интерактивная настройка Telegram-бота для облачных бэкапов и уведомлений
configure_telegram_menu() {
    load_gateway_env
    echo ""
    echo "${C_CYN}=== Настройка Telegram (Облачный бэкап + Уведомления) ===${C_RES}"
    if is_telegram_configured; then
        echo " • Статус: ${C_GRN}ПОДКЛЮЧЕН${C_RES} (Chat ID: ${TG_CHAT_ID})"
    else
        echo " • Статус: ${C_DIM}НЕ НАСТРОЕН${C_RES}"
    fi
    echo "--------------------------------------------------------"
    echo " 1) Указать / изменить Токен бота (@BotFather) и ваш Chat ID"
    echo " 2) Отправить тестовое сообщение в Telegram"
    echo " 3) Отключить Telegram-уведомления и очистить токен"
    echo " 0) Назад"
    printf "Выбор [0-3]: "
    read -r TG_ACT < /dev/tty || true
    case "$TG_ACT" in
        1)
            printf "Введите API Token бота (от @BotFather): "
            read -r IN_TOK < /dev/tty || true
            IN_TOK=$(printf "%s" "$IN_TOK" | tr -d ' \t\r\n')
            printf "Введите ваш Chat ID (узнать можно в @userinfobot): "
            read -r IN_CID < /dev/tty || true
            IN_CID=$(printf "%s" "$IN_CID" | tr -d ' \t\r\n')
            if [ -n "$IN_TOK" ] && [ -n "$IN_CID" ]; then
                TG_BOT_TOKEN="$IN_TOK"
                TG_CHAT_ID="$IN_CID"
                save_gateway_env
                if send_telegram_msg "✅ Сервер (${OS_NAME} | $(get_current_lan_ip)) успешно подключен к Telegram!"; then
                    echo "${C_GRN}[✓] Настройки сохранены, тестовое сообщение доставлено!${C_RES}"
                else
                    echo "${C_YEL}[!] Настройки сохранены, но тестовое сообщение не прошло (проверьте нажали ли вы /start у бота).${C_RES}"
                fi
            else
                echo "${C_RED}[X] Отмена: Токен и Chat ID не могут быть пустыми.${C_RES}"
            fi
            ;;
        2)
            if send_telegram_msg "🔔 Проверка связи с сервером (${OS_NAME} | $(get_current_lan_ip)). Все системы работают нормально."; then
                echo "${C_GRN}[✓] Тестовое уведомление успешно отправлено!${C_RES}"
            else
                echo "${C_RED}[X] Ошибка отправки сообщения.${C_RES}"
            fi
            ;;
        3)
            TG_BOT_TOKEN=""
            TG_CHAT_ID=""
            save_gateway_env
            echo "${C_GRN}[✓] Telegram-уведомления отключены.${C_RES}"
            ;;
    esac
    return 0
}

# Авто-ротация логов шлюза и сервисов Homelab (защита от переполнения диска)
rotate_gateway_logs() {
    for LOG_F in "$SB_LOG_FILE" "$AUTOUPDATE_LOG" /var/log/caddy.log /var/log/vaultwarden.log /var/log/ytdlp-webui.log /var/log/code-server.log /var/log/navidrome.log /var/log/jellyfin.log /var/log/qbittorrent-nox.log; do
        if [ -f "$LOG_F" ]; then
            F_SIZE=$(wc -c < "$LOG_F" 2>/dev/null | tr -d ' \t\r\n' || echo "0")
            if [ "${F_SIZE:-0}" -gt 1048576 ]; then
                tail -n 500 "$LOG_F" > "${LOG_F}.tmp" 2>/dev/null && mv -f "${LOG_F}.tmp" "$LOG_F" 2>/dev/null || true
            fi
        fi
    done
    return 0
}

# Активное сканирование всей /24 подсети LAN (прогрев ARP-таблицы за ~1.5 сек)
scan_lan_subnet() {
    CUR_LAN=$(get_current_lan_ip)
    LAN_SUB="${CUR_LAN%.*}"
    echo "Сканирование подсети ${LAN_SUB}.0/24 (опрос живых устройств ~1.5 сек)..."
    I_HOST=1
    while [ "$I_HOST" -le 254 ]; do
        ping -c 1 -W 1 "${LAN_SUB}.${I_HOST}" >/dev/null 2>&1 &
        if [ $((I_HOST % 64)) -eq 0 ]; then
            wait 2>/dev/null || true
        fi
        I_HOST=$((I_HOST + 1))
    done
    wait 2>/dev/null || true
    return 0
}

# Авто-сканер живых устройств в локальной сети (ARP + DHCP Leases Alpine Linux) для Пункта 8
discover_lan_devices() {
    load_gateway_env
    CUR_LAN=$(get_current_lan_ip)
    rm -f "$LAN_SCAN_CACHE"
    touch "$LAN_SCAN_CACHE"

    LEASE_F=""
    [ -f /var/lib/misc/dnsmasq.leases ] && LEASE_F="/var/lib/misc/dnsmasq.leases"

    echo " ${C_CYN}--- Обнаруженные устройства в локальной сети (ARP + DHCP) ---${C_RES}"
    # shellcheck disable=SC2086
    awk -v gw="$GW_IP" -v self="$CUR_LAN" -v out_cache="$LAN_SCAN_CACHE" \
        -v byp_f="$USER_BYPASS_IPS" -v vpn_f="$USER_FORCE_PROXY_IPS" \
        -v c_cyn="$C_CYN" -v c_grn="$C_GRN" -v c_yel="$C_YEL" -v c_dim="$C_DIM" -v c_res="$C_RES" '
        BEGIN {
            while ((getline line < byp_f) > 0) {
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
                if (line != "") byp[line] = 1
            }
            close(byp_f)
            while ((getline line < vpn_f) > 0) {
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
                if (line != "") vpn[line] = 1
            }
            close(vpn_f)
        }
        FILENAME ~ /leases$/ {
            ip = $3; mac = tolower($2); host = $4
            if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && ip != self) {
                ips[ip] = 1
                if (mac != "") macs[ip] = mac
                if (host != "" && host != "*") names[ip] = host
            }
            next
        }
        FILENAME == "/proc/net/arp" && FNR > 1 {
            ip = $1; flags = $3; mac = tolower($4)
            if (ip != self && flags != "0x0" && mac != "00:00:00:00:00:00") {
                ips[ip] = 1
                if (macs[ip] == "") macs[ip] = mac
            }
            next
        }
        END {
            idx = 0
            for (ip in ips) {
                idx++
                m = (macs[ip] != "") ? macs[ip] : "неизвестен"
                n = (names[ip] != "") ? names[ip] : "Устройство LAN"
                if (ip == gw) n = "Основной роутер (" n ")"
                st = c_dim "[По правилам]" c_res
                if (byp[ip]) st = c_yel "[В ОБХОДЕ: DIRECT]" c_res
                if (vpn[ip]) st = c_grn "[В FULL-VPN]" c_res
                printf "  %s[%d]%s %-15s | %-17s | %-22s %s\n", c_cyn, idx, c_res, ip, m, n, st
                print ip > out_cache
            }
            if (idx == 0) {
                printf "  %s(активные соседи в ARP/DHCP пока не обнаружены — нажмите [s] для опроса сети)%s\n", c_dim, c_res
            }
        }
    ' $LEASE_F /proc/net/arp 2>/dev/null || true
    return 0
}

# Преобразование ввода пользователя (IP или номер из авто-сканера LAN) в IPv4
resolve_device_ip_input() {
    RAW_IN=$(printf "%s" "$1" | tr -d ' \t\r\n')
    [ -z "$RAW_IN" ] && return 1
    case "$RAW_IN" in
        *[!0-9]*)
            if is_valid_ipv4 "$RAW_IN"; then
                printf "%s" "$RAW_IN"
                return 0
            fi
            return 1
            ;;
        *)
            if [ -s "$LAN_SCAN_CACHE" ]; then
                PICKED_IP=$(awk -v target="$RAW_IN" 'NR == target {print $1; exit}' "$LAN_SCAN_CACHE" 2>/dev/null)
                if [ -n "$PICKED_IP" ] && is_valid_ipv4 "$PICKED_IP"; then
                    printf "%s" "$PICKED_IP"
                    return 0
                fi
            fi
            return 1
            ;;
    esac
}

# Интерактивный «Детектор сайта» (Рентген маршрута домена: AdGuard + FakeIP + Homelab .lan + TLS-пинг)
inspect_domain_route() {
    printf "\nВведите домен или ссылку для проверки (например, https://instagram.com или vaultwarden.lan): "
    read -r TEST_IN < /dev/tty || true
    TEST_IN=$(printf "%s" "$TEST_IN" | tr -d ' \t\r\n')
    [ -z "$TEST_IN" ] && return 0

    CLEAN_SUFFIX=$(sanitize_domain_entry "$TEST_IN" || true)
    if [ -z "$CLEAN_SUFFIX" ]; then
        echo "${C_RED}[X] Некорректное имя домена: ${TEST_IN}${C_RES}"
        return 1
    fi
    CLEAN_HOST="${CLEAN_SUFFIX#+.}"

    echo ""
    echo "${C_CYN}=== 🕵️ Рентген маршрута для домена: ${C_BLD}${CLEAN_HOST}${C_RES}${C_CYN} ===${C_RES}"

    # 1. Проверка принадлежности к локальной зоне Homelab (.lan)
    case "$CLEAN_HOST" in
        *.lan)
            echo " • Тип домена:          ${C_GRN}Локальный сервис Homelab (*.lan -> Caddy HTTPS Reverse Proxy)${C_RES}"
            ;;
    esac

    # 2. Проверка в пользовательских списках
    if grep -qxF "$CLEAN_SUFFIX" "$USER_DIRECT_FILE" 2>/dev/null; then
        echo " • Списки пользователя: ${C_YEL}Принудительно НАПРЯМУЮ (${USER_DIRECT_FILE})${C_RES}"
    elif grep -qxF "$CLEAN_SUFFIX" "$USER_PROXY_FILE" 2>/dev/null; then
        echo " • Списки пользователя: ${C_GRN}Принудительно В ПРОКСИ (${USER_PROXY_FILE})${C_RES}"
    else
        echo " • Списки пользователя: ${C_DIM}Не числится (маршрутизируется по базам .srs)${C_RES}"
    fi

    # 3. DNS-резолв через AdGuard Home -> Sing-Box
    RESOLVED_IP=$(nslookup "$CLEAN_HOST" 127.0.0.1 2>/dev/null | awk '
        /^Server:/ { next }
        /^Address.*127\.0\.0\.1/ { next }
        /^Name:|^Non-authoritative answer:/ { f=1; next }
        f && /Address/ {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit }
            }
        }
    ')
    case "$RESOLVED_IP" in
        0.0.0.0|127.0.0.1)
            echo " • Вердикт DNS (:53):   ${C_RED}ЗАБЛОКИРОВАН фильтром рекламы AdGuard Home (${RESOLVED_IP})!${C_RES}"
            ;;
        198.18.*|198.19.*)
            echo " • Вердикт DNS (:53):   ${C_GRN}Выдан FakeIP (${RESOLVED_IP}) -> Маршрут: В ПРОКСИ (Туннель)${C_RES}"
            ;;
        "$(get_current_lan_ip)")
            echo " • Вердикт DNS (:53):   ${C_GRN}Локальный IP сервера (${RESOLVED_IP}) -> Маршрут: Локальный Caddy HTTPS${C_RES}"
            ;;
        "")
            echo " • Вердикт DNS (:53):   ${C_RED}Не удалось разрешить имя (NXDOMAIN или таймаут DNS)${C_RES}"
            ;;
        *)
            echo " • Вердикт DNS (:53):   ${C_YEL}Выдан реальный IP (${RESOLVED_IP}) -> Маршрут: НАПРЯМУЮ (DIRECT / dns_ru)${C_RES}"
            ;;
    esac

    # 4. Замер живого соединения через туннель и напрямую
    echo " • Проверка доступности по HTTPS (TLS Handshake)..."
    PRX_RES=$(curl -k -o /dev/null -sS --curves X25519:P-256 --connect-timeout 3 -m 5 -x http://127.0.0.1:7890 -w '%{http_code} %{time_appconnect}' "https://${CLEAN_HOST}" 2>/dev/null || echo "000 0")
    PRX_CODE=$(printf "%s" "$PRX_RES" | awk '{print $1}')
    PRX_MS=$(printf "%s" "$PRX_RES" | awk '$2+0 > 0 {printf "%.0f ms", $2*1000; ok=1} END {if (!ok) print "недоступен"}')

    LAN_IF_T=$(get_lan_ifname)
    DIR_RES=$(curl -k -o /dev/null -sS --curves X25519:P-256 --interface "$LAN_IF_T" --connect-timeout 2 -m 4 -w '%{http_code} %{time_appconnect}' "https://${CLEAN_HOST}" 2>/dev/null || echo "000 0")
    DIR_CODE=$(printf "%s" "$DIR_RES" | awk '{print $1}')
    DIR_MS=$(printf "%s" "$DIR_RES" | awk '$2+0 > 0 {printf "%.0f ms", $2*1000; ok=1} END {if (!ok) print "заблокирован/таймаут"}')

    echo "   -> Через Sing-Box: HTTP ${PRX_CODE} | TLS: ${C_GRN}${PRX_MS}${C_RES}"
    echo "   -> Напрямую (LAN): HTTP ${DIR_CODE} | TLS: ${C_YEL}${DIR_MS}${C_RES}"
    echo "--------------------------------------------------------"
    echo "Быстрое действие для ${CLEAN_SUFFIX}:"
    echo " 1) Направить этот домен В ПРОКСИ (добавить в ${USER_PROXY_FILE})"
    echo " 2) Направить этот домен НАПРЯМУЮ (добавить в ${USER_DIRECT_FILE})"
    echo " 0) Ничего не менять (назад)"
    printf "Выбор [0-2]: "
    read -r Q_ACT < /dev/tty || true
    case "$Q_ACT" in
        1)
            backup_gateway_state
            load_gateway_env
            awk -v d="$CLEAN_SUFFIX" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.localdomain"}' "$USER_DIRECT_FILE" > "${USER_DIRECT_FILE}.tmp" && mv "${USER_DIRECT_FILE}.tmp" "$USER_DIRECT_FILE"
            grep -qxF "$CLEAN_SUFFIX" "$USER_PROXY_FILE" 2>/dev/null || echo "$CLEAN_SUFFIX" >> "$USER_PROXY_FILE"
            apply_and_verify_singbox "Перевод домена ${CLEAN_SUFFIX} в прокси" || true
            ;;
        2)
            backup_gateway_state
            load_gateway_env
            awk -v d="$CLEAN_SUFFIX" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.chatgpt.com"}' "$USER_PROXY_FILE" > "${USER_PROXY_FILE}.tmp" && mv "${USER_PROXY_FILE}.tmp" "$USER_PROXY_FILE"
            grep -qxF "$CLEAN_SUFFIX" "$USER_DIRECT_FILE" 2>/dev/null || echo "$CLEAN_SUFFIX" >> "$USER_DIRECT_FILE"
            apply_and_verify_singbox "Перевод домена ${CLEAN_SUFFIX} напрямую (DIRECT)" || true
            ;;
    esac
    return 0
}
# ==================== [ КОНЕЦ ЧАСТИ 2 ИЗ 6 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 3 ИЗ 6 ] ====================
# Поштучная диагностика и оживление нод с «молнией» (⚡) без залповой перегрузки
diagnose_failed_nodes() {
    if ! pgrep sing-box >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo "${C_RED}[X] Служба Sing-Box не запущена или не найден jq.${C_RES}"
        return 1
    fi
    load_gateway_env
    API_JSON=$(curl -fsS --connect-timeout 2 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null || true)
    if [ -z "$API_JSON" ]; then
        echo "${C_RED}[X] Не удалось подключиться к Clash API (127.0.0.1:9090).${C_RES}"
        return 1
    fi

    echo ""
    echo "${C_CYN}=== 🩺 Поштучная диагностика и оживление нод без пинга (⚡) ===${C_RES}"
    FAILED_LIST=$(printf "%s" "$API_JSON" | jq -r '
        .proxies | to_entries[]
        | select(.value.type != "Selector" and .value.type != "URLTest" and .value.type != "Direct" and .value.type != "Reject" and .value.type != "Pass")
        | select(((.value.history // []) | if length > 0 then .[-1].delay else 0 end) == 0)
        | .key
    ' 2>/dev/null || true)

    if [ -z "$FAILED_LIST" ]; then
        echo "${C_GRN}[✓] Идеально! У всех 100% активных нод уже есть результат пинга!${C_RES}"
        return 0
    fi

    printf "%s\n" "$FAILED_LIST" | while IFS= read -r NODE_KEY; do
        [ -z "$NODE_KEY" ] && continue
        ENC_N=$(jq -rn --arg s "$NODE_KEY" '$s|@uri')
        RES1=$(curl -fsS --connect-timeout 6 -m 7 -H "Authorization: Bearer ${ADMIN_PASS}" \
            "http://127.0.0.1:9090/proxies/${ENC_N}/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000" 2>/dev/null || true)
        D1=$(printf "%s" "$RES1" | jq -r '.delay // 0' 2>/dev/null || echo "0")

        if [ "${D1:-0}" -gt 0 ]; then
            printf "  %s[✓ ОЖИВЛЕНА: %4s ms]%s %s\n" "$C_GRN" "$D1" "$C_RES" "$NODE_KEY"
        else
            RES2=$(curl -fsS --connect-timeout 6 -m 7 -H "Authorization: Bearer ${ADMIN_PASS}" \
                "http://127.0.0.1:9090/proxies/${ENC_N}/delay?url=http%3A%2F%2Fcp.cloudflare.com%2Fgenerate_204&timeout=5000" 2>/dev/null || true)
            D2=$(printf "%s" "$RES2" | jq -r '.delay // 0' 2>/dev/null || echo "0")
            if [ "${D2:-0}" -gt 0 ]; then
                printf "  %s[✓ ОЖИВЛЕНА: %4s ms]%s %s (через CF)\n" "$C_GRN" "$D2" "$C_RES" "$NODE_KEY"
            else
                printf "  %s[X МЕРТВА У ПРОВАЙДЕРА]%s %s\n" "$C_RED" "$C_RES" "$NODE_KEY"
            fi
        fi
    done
    echo "---------------------------------------------------------------"
    echo "${C_DIM}[i] Все оживленные ноды уже обновили свой пинг в панели Zashboard!${C_RES}"
    return 0
}

# Мини-пульт управления группами и нодами прямо из SSH-терминала (через Clash API)
manage_nodes_cli_menu() {
    if ! pgrep sing-box >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo "${C_RED}[X] Служба Sing-Box не запущена или не найден jq.${C_RES}"
        return 1
    fi
    load_gateway_env

    while true; do
        API_JSON=$(curl -fsS --connect-timeout 2 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null || true)
        if [ -z "$API_JSON" ]; then
            echo "${C_RED}[X] Не удалось получить список нод от Clash API (127.0.0.1:9090).${C_RES}"
            return 1
        fi

        clear
        echo "${C_CYN}=== ⚡ Мини-пульт управления группами и нодами (SSH) ===${C_RES}"
        AUTO_NOW=$(printf "%s" "$API_JSON" | jq -r '.proxies["⚡ Авто (Самый быстрый)"].now // "не выбрана"')
        echo " • Авто-выбор сейчас: ${C_GRN}${AUTO_NOW}${C_RES}"
        echo "--------------------------------------------------------"
        echo "${C_BLD}Топ-8 самых быстрых нод по замеру пинга:${C_RES}"
        printf "%s" "$API_JSON" | jq -r '
            [.proxies | to_entries[]
             | select(.value.type != "Selector" and .value.type != "URLTest" and .value.type != "Direct" and .value.type != "Reject" and .value.type != "Pass")
             | {name: .key, type: .value.type, delay: ((.value.history // []) | if length > 0 then .[-1].delay else 0 end)}
             | select(.delay > 0)]
            | sort_by(.delay) | .[:8] | to_entries[]
            | "  • [\(.value.delay) ms] \(.value.name) (\(.value.type))"
        ' 2>/dev/null || true
        echo "--------------------------------------------------------"
        echo "${C_BLD}Активные селекторы маршрутизации (выберите для смены ноды):${C_RES}"

        GRP_LIST_FILE="/tmp/gateway_selectors.list"
        printf "%s" "$API_JSON" | jq -r '
            [.proxies | to_entries[] | select(.value.type == "Selector" and .key != "GLOBAL")]
            | map(.key) | .[]
        ' > "$GRP_LIST_FILE" 2>/dev/null || true

        G_IDX=0
        while IFS= read -r G_NAME; do
            [ -z "$G_NAME" ] && continue
            G_IDX=$((G_IDX + 1))
            G_CUR=$(printf "%s" "$API_JSON" | jq -r --arg g "$G_NAME" '.proxies[$g].now // "Авто"')
            printf "  %s[%d]%s %-28s -> Сейчас: %s%s%s\n" "$C_CYN" "$G_IDX" "$C_RES" "$G_NAME" "$C_GRN" "$G_CUR" "$C_RES"
        done < "$GRP_LIST_FILE"

        echo "--------------------------------------------------------"
        echo "  ${C_CYN}[d]${C_RES} ${C_GRN}🩺 Поштучно проверить и оживить ноды с молнией (⚡)${C_RES}"
        echo "  ${C_CYN}[r]${C_RES} Запустить общий замер пинга всех нод"
        echo "  ${C_CYN}[0]${C_RES} Назад"
        printf "Выберите номер группы [1-%d / d / r / 0]: " "$G_IDX"
        read -r G_SEL < /dev/tty || true
        G_SEL=$(printf "%s" "$G_SEL" | tr -d ' \t\r\n')

        case "$G_SEL" in
            ""|0)
                rm -f "$GRP_LIST_FILE"
                break
                ;;
            d|D)
                diagnose_failed_nodes || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            r|R)
                echo "Запуск тестирования задержки всех нод..."
                reload_singbox_api
                sleep 1
                ;;
            *[!0-9]*)
                ;;
            *)
                TARGET_GRP=$(awk -v t="$G_SEL" 'NR == t {print $0; exit}' "$GRP_LIST_FILE" 2>/dev/null)
                if [ -n "$TARGET_GRP" ]; then
                    NODES_LIST_FILE="/tmp/gateway_group_nodes.list"
                    printf "%s" "$API_JSON" | jq -r --arg g "$TARGET_GRP" '.proxies[$g].all[]?' > "$NODES_LIST_FILE" 2>/dev/null || true
                    echo ""
                    echo "${C_CYN}--- Доступные ноды для группы «${TARGET_GRP}» ---${C_RES}"
                    N_IDX=0
                    while IFS= read -r N_NAME; do
                        [ -z "$N_NAME" ] && continue
                        N_IDX=$((N_IDX + 1))
                        N_DELAY=$(printf "%s" "$API_JSON" | jq -r --arg n "$N_NAME" '(.proxies[$n].history // []) | if length > 0 then .[-1].delay else 0 end' 2>/dev/null || echo "0")
                        if [ "${N_DELAY:-0}" -gt 0 ]; then
                            printf "  %s[%d]%s %s %s(%s ms)%s\n" "$C_CYN" "$N_IDX" "$C_RES" "$N_NAME" "$C_GRN" "$N_DELAY" "$C_RES"
                        else
                            printf "  %s[%d]%s %s %s(⚡)%s\n" "$C_CYN" "$N_IDX" "$C_RES" "$N_NAME" "$C_DIM" "$C_RES"
                        fi
                    done < "$NODES_LIST_FILE"
                    printf "\nВыберите номер ноды для «%s» [Enter = отмена]: " "$TARGET_GRP"
                    read -r N_SEL < /dev/tty || true
                    N_SEL=$(printf "%s" "$N_SEL" | tr -d ' \t\r\n')
                    case "$N_SEL" in
                        ''|*[!0-9]*) ;;
                        *)
                            PICKED_NODE=$(awk -v t="$N_SEL" 'NR == t {print $0; exit}' "$NODES_LIST_FILE" 2>/dev/null)
                            if [ -n "$PICKED_NODE" ]; then
                                ENC_GRP=$(jq -rn --arg s "$TARGET_GRP" '$s|@uri')
                                PAYLOAD_JSON=$(jq -n --arg name "$PICKED_NODE" '{"name": $name}')
                                if curl -fsS -X PUT -H "Authorization: Bearer ${ADMIN_PASS}" -H "Content-Type: application/json" \
                                    -d "$PAYLOAD_JSON" "http://127.0.0.1:9090/proxies/${ENC_GRP}" >/dev/null 2>&1; then
                                    echo "${C_GRN}[✓] Группа «${TARGET_GRP}» переключена на: ${PICKED_NODE}${C_RES}"
                                    sleep 1
                                fi
                            fi
                            ;;
                    esac
                    rm -f "$NODES_LIST_FILE"
                fi
                ;;
        esac
    done
    return 0
}

# Быстрая смена единого пароля (Sing-Box Zashboard + AdGuard Home + Samba + Vaultwarden + Caddy BasicAuth)
change_unified_password() {
    NEW_PASS=$(printf "%s" "$1" | tr -d '\r\n')
    SYNC_SMB_ANS="${2:-ask}"
    if [ -z "$NEW_PASS" ]; then
        echo "${C_RED}[X] Ошибка: Пароль не может быть пустым!${C_RES}"
        return 1
    fi
    load_gateway_env
    OLD_ADMIN_PASS="${ADMIN_PASS:-}"
    OLD_SMB_PASS="${SMB_PASS:-}"

    ADMIN_PASS="$NEW_PASS"
    if [ "$SYNC_SMB_ANS" = "yes" ] || [ -z "$OLD_SMB_PASS" ] || [ "$OLD_SMB_PASS" = "$OLD_ADMIN_PASS" ]; then
        SMB_PASS="$NEW_PASS"
    elif [ "$SYNC_SMB_ANS" = "ask" ] && [ -t 0 ]; then
        printf "Обновить также пароль сетевой папки Samba для пользователя '%s'? (y/n) [Enter = y]: " "${SMB_USER:-homelab}"
        read -r IN_SYNC_SMB < /dev/tty || true
        IN_SYNC_SMB=$(printf "%s" "$IN_SYNC_SMB" | tr -d ' \t\r\n')
        [ -z "$IN_SYNC_SMB" ] && IN_SYNC_SMB="y"
        case "$IN_SYNC_SMB" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) SMB_PASS="$NEW_PASS" ;;
        esac
    fi

    save_gateway_env
    save_homelab_env
    generate_singbox_config

    service_ctl adguardhome stop
    if [ -f "$AGH_CONF" ] && command -v htpasswd >/dev/null 2>&1; then
        CUR_AGH_USER=$(sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "$AGH_CONF" | head -n 1 | tr -d ' \t\r\n"')
        [ -z "$CUR_AGH_USER" ] && CUR_AGH_USER="admin" || true
        NEW_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$CUR_AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$NEW_HASH" ] && NEW_HASH=$(htpasswd -nbBC 10 "$CUR_AGH_USER" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true) || true
        if [ -n "$NEW_HASH" ]; then
            awk -v u="$CUR_AGH_USER" -v h="$NEW_HASH" '
                /^users:/ {
                    print "users:"
                    print "  - name: " u
                    print "    password: " h
                    in_users=1; next
                }
                in_users && /^[^[:space:]]/ { in_users=0 }
                in_users { next }
                { print }
            ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv "${AGH_CONF}.tmp" "$AGH_CONF"
            chmod 600 "$AGH_CONF" 2>/dev/null || true
        fi
    fi

    # Синхронизация и верификация пароля Samba
    if command -v smbpasswd >/dev/null 2>&1; then
        if ! apply_and_verify_samba_password "${SMB_USER:-homelab}" "${SMB_PASS:-$ADMIN_PASS}"; then
            echo "${C_YEL}[!] Предупреждение: Не удалось подтвердить обновление записи Samba passdb для ${SMB_USER:-homelab}.${C_RES}"
        fi
    fi

    # Синхронизация ADMIN_TOKEN в Vaultwarden (если модуль установлен)
    if [ -f /etc/conf.d/vaultwarden ] || is_module_enabled "vaultwarden"; then
        sync_vaultwarden_config >/dev/null 2>&1 || true
        is_module_enabled "vaultwarden" && service_ctl vaultwarden restart || true
    fi

    # Синхронизация BasicAuth в Caddy для защищенных модулей
    if [ -x /usr/sbin/caddy ] && [ -d "$CADDY_CONFD" ]; then
        is_module_enabled "ytdlp" && register_caddy_site "ytdlp" "$DOM_YTDLP" "$PORT_YTDLP" "yes" >/dev/null 2>&1 || true
        is_module_enabled "torrent" && register_caddy_site "torrent" "$DOM_TORRENT" "$PORT_TORRENT_WEB" "yes" >/dev/null 2>&1 || true
        is_module_enabled "code" && register_caddy_site "code" "$DOM_CODE" "$PORT_CODE" "yes" >/dev/null 2>&1 || true
    fi

    service_ctl sing-box restart || true
    service_ctl adguardhome start || true
    echo "${C_GRN}[✓] Единый пароль успешно синхронизирован (Sing-Box, AdGuard Home, Samba, Vaultwarden, Caddy)!${C_RES}"
    return 0
}

# Управление Умным DHCP-сервером на Alpine Linux (dnsmasq на порту 5353)
configure_smart_dhcp() {
    DHCP_MODE="${1:-off}"
    CUR_LAN_IP=$(get_current_lan_ip)
    LAN_IF=$(get_lan_ifname)
    LAN_SUB="${CUR_LAN_IP%.*}"

    if [ "$DHCP_MODE" = "on" ]; then
        if ! command -v dnsmasq >/dev/null 2>&1; then
            echo "Установка пакета dnsmasq для DHCP-сервера..."
            apk update >/dev/null 2>&1 || true
            apk add dnsmasq >/dev/null 2>&1 || true
        fi
        mkdir -p /etc/dnsmasq.d /var/lib/misc
        cat << ALP_DHCP > "$ALPINE_DHCP_CONF"
port=5353
interface=${LAN_IF}
bind-interfaces
dhcp-authoritative
dhcp-range=${LAN_SUB}.100,${LAN_SUB}.239,255.255.255.0,12h
dhcp-option=3,${CUR_LAN_IP}
dhcp-option=6,${CUR_LAN_IP}
ALP_DHCP
        service_ctl dnsmasq enable
        service_ctl dnsmasq restart
        echo "${C_GRN}[✓] Умный DHCP-сервер на Alpine ВКЛЮЧЕН (Шлюз и DNS: ${CUR_LAN_IP}, пул .100-.239).${C_RES}"
        echo "    Не забудьте отключить DHCP-сервер на основном роутере провайдера!"
    else
        rm -f "$ALPINE_DHCP_CONF" 2>/dev/null || true
        service_ctl dnsmasq stop
        service_ctl dnsmasq disable
        echo "${C_GRN}[✓] DHCP-сервер на Alpine ВЫКЛЮЧЕН (классический режим Sidecar).${C_RES}"
    fi
    return 0
}

# Запись статической конфигурации сети в /etc/network/interfaces для Alpine Linux
write_alpine_static_interfaces() {
    A_IF="$1"
    A_IP="$2"
    A_GW="$3"
    cat << NET_ALP > /etc/network/interfaces
auto lo
iface lo inet loopback

auto ${A_IF}
iface ${A_IF} inet static
    address ${A_IP}
    netmask 255.255.255.0
    gateway ${A_GW}
NET_ALP
    return 0
}

# Безопасная смена LAN IP шлюза и/или IP основного роутера на Alpine Linux (с обновлением *.lan в AdGuard Home)
apply_network_ips() {
    TARGET_LAN_IP="$1"
    TARGET_GW_IP="$2"

    CUR_LAN_IP=$(get_current_lan_ip)
    LAN_IF=$(get_lan_ifname)
    load_gateway_env

    [ -z "$TARGET_LAN_IP" ] && TARGET_LAN_IP="$CUR_LAN_IP"
    [ -z "$TARGET_GW_IP" ] && TARGET_GW_IP="$GW_IP"

    if ! is_valid_ipv4 "$TARGET_LAN_IP"; then
        echo "${C_RED}[X] Ошибка: Некорректный IPv4-адрес шлюза (${TARGET_LAN_IP})!${C_RES}"
        return 1
    fi

    if ! is_valid_ipv4 "$TARGET_GW_IP"; then
        echo "${C_RED}[X] Ошибка: Некорректный IPv4-адрес основного роутера (${TARGET_GW_IP})!${C_RES}"
        return 1
    fi

    if [ "$TARGET_LAN_IP" = "$TARGET_GW_IP" ]; then
        echo "${C_RED}[X] Ошибка: IP шлюза (${TARGET_LAN_IP}) не может совпадать с IP основного роутера (${TARGET_GW_IP})!${C_RES}"
        return 1
    fi

    LAN_SUBNET="${TARGET_LAN_IP%.*}"
    GW_SUBNET="${TARGET_GW_IP%.*}"
    if [ "$LAN_SUBNET" != "$GW_SUBNET" ]; then
        echo "${C_YEL}[!] Внимание: Подсеть шлюза (${LAN_SUBNET}.x) отличается от подсети роутера (${GW_SUBNET}.x)!${C_RES}"
        printf "Введите IP основного роутера в новой подсети [Enter = %s.1 / отмена = n]: " "$LAN_SUBNET"
        read -r FIX_GW < /dev/tty || true
        FIX_GW=$(printf "%s" "$FIX_GW" | tr -d ' \t\r\n')
        if [ "$FIX_GW" = "n" ] || [ "$FIX_GW" = "N" ]; then
            echo "[i] Смена IP отменена."
            return 1
        fi
        [ -z "$FIX_GW" ] && FIX_GW="${LAN_SUBNET}.1"
        if ! is_valid_ipv4 "$FIX_GW" || [ "$FIX_GW" = "$TARGET_LAN_IP" ]; then
            echo "${C_RED}[X] Некорректный или конфликтующий IP основного роутера (${FIX_GW}).${C_RES}"
            return 1
        fi
        TARGET_GW_IP="$FIX_GW"
    fi

    GW_IP="$TARGET_GW_IP"
    save_gateway_env
    update_agh_gateway_ip "$GW_IP" "$TARGET_LAN_IP"
    [ -f "$SB_CONF" ] && generate_singbox_config || true

    write_alpine_static_interfaces "$LAN_IF" "$TARGET_LAN_IP" "$GW_IP"
    if [ -f "$ALPINE_DHCP_CONF" ]; then
        configure_smart_dhcp "on" >/dev/null 2>&1 || true
    fi

    cat << SW_ALP > /tmp/switch_lan_ip.sh
#!/bin/sh
sleep 1
rc-service sing-box stop >/dev/null 2>&1 || true
killall -9 udhcpc >/dev/null 2>&1 || true
if [ "${TARGET_LAN_IP}" != "${CUR_LAN_IP}" ]; then
    ip -4 addr flush dev ${LAN_IF} >/dev/null 2>&1 || true
fi
ip -4 addr replace ${TARGET_LAN_IP}/24 dev ${LAN_IF} >/dev/null 2>&1 || true
ip link set ${LAN_IF} up >/dev/null 2>&1 || true
ip -4 route replace default via ${GW_IP} dev ${LAN_IF} >/dev/null 2>&1 || true
sleep 2
nft -f ${ALPINE_NFT_CONF} >/dev/null 2>&1 || true
rc-service sing-box start >/dev/null 2>&1 || true
rc-service adguardhome restart >/dev/null 2>&1 || true
rc-service caddy reload >/dev/null 2>&1 || rc-service caddy restart >/dev/null 2>&1 || true
rc-service samba restart >/dev/null 2>&1 || true
rc-service wsdd restart >/dev/null 2>&1 || true
rc-service avahi-daemon restart >/dev/null 2>&1 || true
rm -f /tmp/switch_lan_ip.sh
SW_ALP
    chmod +x /tmp/switch_lan_ip.sh

    write_resolv_conf "nameserver 127.0.0.1
nameserver ${GW_IP}
nameserver 77.88.8.8"

    echo "==============================================================="
    echo "${C_GRN}[✓] Сетевые настройки успешно сохранены (${OS_NAME}):${C_RES}"
    echo " • Новый IP сервера (${LAN_IF}):   ${TARGET_LAN_IP} (маска 255.255.255.0)"
    echo " • IP основного роутера:     ${GW_IP}"
    echo " • Панель Sing-Box Extended: http://${TARGET_LAN_IP}:9090/ui (https://${DOM_ZASHBOARD})"
    echo " • Панель AdGuard Home:      http://${TARGET_LAN_IP}:3000 (https://${DOM_ADGUARD})"
    echo " • Локальные домены *.lan:   перенаправлены на ${TARGET_LAN_IP}"

    if [ "$TARGET_LAN_IP" != "$CUR_LAN_IP" ]; then
        echo "---------------------------------------------------------------"
        echo "${C_YEL}[!] ВНИМАНИЕ: IP сервера изменился (${CUR_LAN_IP} -> ${TARGET_LAN_IP})!${C_RES}"
        echo " 1. Переподключитесь по SSH: ssh root@${TARGET_LAN_IP}"
        echo " 2. Обновите адрес шлюза/DNS на устройствах или в роутере на ${TARGET_LAN_IP}!"
        echo "==============================================================="
        nohup /tmp/switch_lan_ip.sh >/dev/null 2>&1 &
    else
        echo "==============================================================="
        /tmp/switch_lan_ip.sh
    fi
    return 0
}

# Проверка, включено ли автообновление и Watchdog в cron
is_autoupdate_enabled() {
    grep -q "/usr/bin/gateway autoupdate" "$CRON_FILE" 2>/dev/null
}

is_watchdog_enabled() {
    grep -q "/usr/bin/gateway watchdog" "$CRON_FILE" 2>/dev/null
}

# Включение автообновления (ежедневно в 04:00 через crond)
enable_autoupdate() {
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    echo "0 4 * * * /usr/bin/gateway autoupdate >${AUTOUPDATE_LOG} 2>&1" >> "$CRON_FILE"
    service_ctl cron enable
    service_ctl cron restart
    return 0
}

# Отключение автообновления
disable_autoupdate() {
    if [ -f "$CRON_FILE" ]; then
        sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    fi
    service_ctl cron reload
    return 0
}

# Управление встроенным Watchdog (самоисцеление служб каждые 5 минут)
enable_watchdog() {
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    sed -i '\|/usr/bin/gateway watchdog|d' "$CRON_FILE" 2>/dev/null || true
    echo "*/5 * * * * /usr/bin/gateway watchdog >/dev/null 2>&1" >> "$CRON_FILE"
    service_ctl cron enable
    service_ctl cron restart
    return 0
}

disable_watchdog() {
    if [ -f "$CRON_FILE" ]; then
        sed -i '\|/usr/bin/gateway watchdog|d' "$CRON_FILE" 2>/dev/null || true
    fi
    service_ctl cron reload
    return 0
}

# Фоновая проверка здоровья служб шлюза и активных модулей Homelab (Watchdog Auto-Healer)
run_watchdog() {
    set +e
    acquire_gateway_lock "watchdog" || return 0
    trap 'release_gateway_lock' EXIT INT TERM HUP
    detect_os
    rotate_gateway_logs
    if [ ! -f "$SB_CONF" ]; then
        release_gateway_lock
        trap - EXIT INT TERM HUP
        return 0
    fi
    ensure_alpine_modules
    RECOVERED_MSG=""

    if ! pgrep sing-box >/dev/null 2>&1 || ! ip link show singbox-tun >/dev/null 2>&1; then
        logger -t gateway-watchdog "Sing-Box or singbox-tun down, restarting service..." 2>/dev/null || true
        service_ctl sing-box restart
        sleep 2
        RECOVERED_MSG="⚠️ [Авто-Доктор] На сервере ($(get_current_lan_ip)) был перезапущен туннель Sing-Box."
    fi

    if ! pgrep AdGuardHome >/dev/null 2>&1; then
        logger -t gateway-watchdog "AdGuardHome down, restarting service..." 2>/dev/null || true
        service_ctl adguardhome restart
        RECOVERED_MSG="${RECOVERED_MSG}
⚠️ [Авто-Доктор] Перезапущена служба AdGuard Home."
    fi

    # Проверка активных служб Homelab из реестра modules.state
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            [ "$M_EN" = "yes" ] || continue
            [ -z "$M_SVC" ] && continue
            if [ -x "/etc/init.d/${M_SVC}" ] && ! rc-service "$M_SVC" status >/dev/null 2>&1; then
                logger -t gateway-watchdog "Homelab module ${M_ID} (${M_SVC}) down, restarting..." 2>/dev/null || true
                rc-service "$M_SVC" restart >/dev/null 2>&1 || true
                RECOVERED_MSG="${RECOVERED_MSG}
⚠️ [Авто-Доктор Homelab] Перезапущен модуль ${M_ID} (${M_SVC})."
            fi
        done < "$HOMELAB_STATE"
    fi

    if [ -n "$RECOVERED_MSG" ]; then
        send_telegram_msg "$RECOVERED_MSG" >/dev/null 2>&1 || true
    fi
    release_gateway_lock
    trap - EXIT INT TERM HUP
    return 0
}

# Фоновая задача автообновления для cron (с эксклюзивной блокировкой против гонки с Watchdog в 04:00)
run_autoupdate() {
    set +e
    WAIT_LCK=0
    while ! acquire_gateway_lock "autoupdate"; do
        sleep 1
        WAIT_LCK=$((WAIT_LCK + 1))
        [ "$WAIT_LCK" -ge 15 ] && break
    done
    trap 'release_gateway_lock' EXIT INT TERM HUP
    detect_os
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Запуск автообновления шлюза и Homelab (${OS_NAME}) ==="
    update_cores_only "yes"
    if ! pgrep sing-box >/dev/null 2>&1; then
        service_ctl sing-box start
    fi
    if ! pgrep AdGuardHome >/dev/null 2>&1; then
        service_ctl adguardhome start
    fi
    reload_singbox_api
    rotate_gateway_logs
    send_telegram_msg "🔄 [Автообновление 04:00] Сервер (${OS_NAME} | $(get_current_lan_ip)) проверил обновления. Текущие версии: Sing-Box ${LATEST_SB_TAG}, AdGuard ${LATEST_AGH_TAG}." >/dev/null 2>&1 || true
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Автообновление завершено ==="
    release_gateway_lock
    trap - EXIT INT TERM HUP
    return 0
}

# Получение последнего тега релиза с GitHub
fetch_latest_github_tag() {
    REPO="$1"
    TAG=$(curl -fsSL --curves X25519:P-256 --connect-timeout 2 -m 3 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | cut -d'"' -f4 || true)
    if [ -z "$TAG" ]; then
        TAG=$(curl -fsSLI --curves X25519:P-256 --connect-timeout 2 -m 3 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null | awk -F'/' '{print $NF}' | tr -d '\r\n' || true)
        [ "$TAG" = "latest" ] && TAG="" || true
    fi
    printf "%s" "$TAG"
    return 0
}

# Мгновенное чтение кэша версий из /tmp (чтобы меню открывалось за 0.01 сек без паузы!)
refresh_remote_versions() {
    FORCE_FETCH="${1:-no}"
    if [ "$FORCE_FETCH" != "yes" ] && [ -f "$VER_CACHE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$VER_CACHE_FILE" 2>/dev/null || true
        return 0
    fi

    LATEST_SB_TAG=$(fetch_latest_github_tag "shtorm-7/sing-box-extended")
    LATEST_AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
    if [ -f "${SB_DIR}/ui/index.html" ]; then
        LATEST_UI_TAG=$(fetch_latest_github_tag "$UI_REPO")
        if [ ! -f "$UI_VER_FILE" ] && [ -n "$LATEST_UI_TAG" ]; then
            echo "$LATEST_UI_TAG" > "$UI_VER_FILE"
        fi
    fi

    cat << VC_EOF > "$VER_CACHE_FILE" 2>/dev/null || true
LATEST_SB_TAG='${LATEST_SB_TAG}'
LATEST_AGH_TAG='${LATEST_AGH_TAG}'
LATEST_UI_TAG='${LATEST_UI_TAG}'
VC_EOF
    return 0
}

# Отрисовка статуса шлюза и стека Homelab в шапке главного меню
print_gateway_header() {
    load_gateway_env
    calc_hardware_limits
    LAN_IP_NOW=$(get_current_lan_ip)
    LAN_IF_NOW=$(get_lan_ifname)

    if pgrep sing-box >/dev/null 2>&1; then
        S_STAT="${C_GRN}[ЗАПУЩЕН]${C_RES}     "
    else
        S_STAT="${C_RED}[ОСТАНОВЛЕН]${C_RES}  "
    fi

    if [ -x /usr/bin/sing-box ]; then
        S_VER_RAW=$(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        if [ -n "$S_VER_RAW" ]; then
            S_VER="v${S_VER_RAW#v}"
        else
            S_VER="неизвестно"
        fi
    else
        S_VER="не установлен"
    fi

    if [ -n "$LATEST_SB_TAG" ] && [ "$S_VER" != "не установлен" ]; then
        if [ "$S_VER" = "$LATEST_SB_TAG" ]; then
            S_VER_INFO="${S_VER} ${C_DIM}(актуальна)${C_RES}"
        else
            S_VER_INFO="${S_VER} -> ${C_YEL}ДОСТУПНА ${LATEST_SB_TAG}!${C_RES}"
        fi
    else
        S_VER_INFO="${S_VER}"
    fi

    if pgrep AdGuardHome >/dev/null 2>&1; then
        A_STAT="${C_GRN}[ЗАПУЩЕН]${C_RES}     "
    else
        A_STAT="${C_RED}[ОСТАНОВЛЕН]${C_RES}  "
    fi

    if [ -x /usr/bin/AdGuardHome ]; then
        A_VER=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)
        [ -z "$A_VER" ] && A_VER="установлен" || true
    else
        A_VER="не установлен"
    fi

    if [ -n "$LATEST_AGH_TAG" ] && [ "$A_VER" != "не установлен" ]; then
        if [ "$A_VER" = "$LATEST_AGH_TAG" ]; then
            A_VER_INFO="${A_VER} ${C_DIM}(актуальна)${C_RES}"
        else
            A_VER_INFO="${A_VER} -> ${C_YEL}ДОСТУПНА ${LATEST_AGH_TAG}!${C_RES}"
        fi
    else
        A_VER_INFO="${A_VER}"
    fi

    SUB_CNT=$(count_sub_urls)
    MY_CNT=$(count_my_nodes)
    if [ "$SUB_CNT" -gt 1 ]; then
        P_STAT="${C_CYN}[МУЛЬТИ-САБ]${C_RES}  "
        P_INFO="активно подписок: ${SUB_CNT} шт. (+ ключей: ${MY_CNT})"
    elif [ "$SUB_CNT" -eq 1 ]; then
        P_STAT="${C_CYN}[ПОДПИСКА]${C_RES}    "
        P_INFO="${SUB_URL}"
    elif [ "$MY_CNT" -gt 0 ]; then
        P_STAT="${C_CYN}[КЛЮЧИ URI]${C_RES}   "
        P_INFO="активно ключей в my_nodes.yaml: ${MY_CNT} шт."
    elif is_warp_enabled; then
        P_STAT="${C_CYN}[ТОЛЬКО WARP]${C_RES} "
        P_INFO="работает гибридный Amnezia WARP 2.0 + MASQUE H2"
    else
        P_STAT="${C_YEL}[РЕЖИМ DIRECT]${C_RES}"
        P_INFO="прокси не заданы (весь трафик напрямую)"
    fi

    if is_warp_enabled; then
        W_STAT="${C_GRN}[АКТИВЕН]${C_RES}     "
        if [ -n "${WARP_LICENSE:-}" ]; then
            W_INFO="4 ноды AWG WARP+ + MASQUE TCP/H2 ('☁️ Amnezia WARP')"
        else
            W_INFO="4 ноды AWG 2.0 + MASQUE TCP/H2 ('☁️ Amnezia WARP')"
        fi
    else
        W_STAT="${C_DIM}[ВЫКЛЮЧЕН]${C_RES}    "
        W_INFO="можно включить бесплатно в пункте 2"
    fi

    if [ -f "${SB_DIR}/ui/index.html" ]; then
        UI_STAT="${C_GRN}[Zashboard]${C_RES}   "
        UI_VER=""
        [ -f "$UI_VER_FILE" ] && UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n') || true
        [ -z "$UI_VER" ] && UI_VER="установлена" || true

        if [ -n "$LATEST_UI_TAG" ] && [ "$UI_VER" != "установлена" ]; then
            if [ "$UI_VER" = "$LATEST_UI_TAG" ]; then
                UI_VER_INFO="${UI_VER} ${C_DIM}(актуальна)${C_RES}"
            else
                UI_VER_INFO="${UI_VER} -> ${C_YEL}ДОСТУПНА ${LATEST_UI_TAG}!${C_RES}"
            fi
        else
            UI_VER_INFO="${UI_VER}"
        fi
    else
        UI_STAT="${C_RED}[НЕ НАЙДЕНА]${C_RES}  "
        UI_VER_INFO="не установлена"
    fi

    if is_killswitch_enabled; then
        KS_STAT="${C_GRN}[АКТИВЕН]${C_RES}     "
        KS_INFO="строгая блокировка трафика мимо singbox-tun (${LAN_IF_NOW})"
    else
        KS_STAT="${C_CYN}[СТАНДАРТ]${C_RES}    "
        KS_INFO="защита IPv6 + DoT/DoQ + перехват DNS 53 (${LAN_IF_NOW})"
    fi

    if is_watchdog_enabled; then
        WD_TXT="${C_GRN}ВКЛ${C_RES}"
    else
        WD_TXT="${C_DIM}ВЫКЛ${C_RES}"
    fi

    if is_telegram_configured; then
        TG_TXT="${C_GRN}ВКЛ${C_RES}"
    else
        TG_TXT="${C_DIM}ВЫКЛ${C_RES}"
    fi

    if is_dhcp_server_enabled; then
        DHCP_TXT="${C_GRN}ВКЛ${C_RES}"
    else
        DHCP_TXT="${C_DIM}ВЫКЛ${C_RES}"
    fi

    if is_autoupdate_enabled; then
        AU_STAT="${C_GRN}[ВКЛЮЧЕНО]${C_RES}    "
        AU_INFO="04:00 | Watchdog: ${WD_TXT} | TG-облако: ${TG_TXT}"
    else
        AU_STAT="${C_DIM}[ВЫКЛЮЧЕНО]${C_RES}   "
        AU_INFO="вручную | Watchdog: ${WD_TXT} | TG-облако: ${TG_TXT}"
    fi

    HL_ACT_CNT=0
    if [ -f "$HOMELAB_STATE" ]; then
        HL_ACT_CNT=$(awk -F'|' '$1 !~ /^#/ && $2 == "yes" {c++} END {print c+0}' "$HOMELAB_STATE" 2>/dev/null || echo "0")
    fi
    DISK_FREE_TXT=$(df -h "${STORAGE_ROOT:-/}" 2>/dev/null | awk 'NR==2 {print $4 " свободно из " $2}' || echo "н/д")
    if [ "$HL_ACT_CNT" -gt 0 ]; then
        HL_STAT="${C_GRN}[АКТИВЕН: ${HL_ACT_CNT}/9]${C_RES}"
    else
        HL_STAT="${C_DIM}[НЕ УСТАНОВЛЕН]${C_RES}"
    fi

    echo " Платформа:     ${C_CYN}[${OS_NAME}]${C_RES} | [${TOTAL_RAM_MB} МБ RAM -> SB ${SB_GOMEMLIMIT}]"
    echo " Сеть сервера:  ${C_BLD}[${LAN_IF_NOW}: ${LAN_IP_NOW}]${C_RES} -> [Роутер: ${GW_IP}] | DHCP: ${DHCP_TXT}"
    echo " Sing-Box Ext:  ${S_STAT}${S_VER_INFO}"
    echo " AdGuard Home:  ${A_STAT}${A_VER_INFO} (DNS :53 + *.lan Rewrites)"
    echo " Основной пул:  ${P_STAT}${P_INFO}"
    echo " Amnezia WARP:  ${W_STAT}${W_INFO}"
    echo " Kill-Switch:   ${KS_STAT}${KS_INFO}"
    echo " Веб-панель:    ${UI_STAT}${UI_VER_INFO}"
    echo " Автоапдейт:    ${AU_STAT}${AU_INFO}"
    echo " Стек Homelab:  ${HL_STAT} | Хранилище: ${C_CYN}${DISK_FREE_TXT}${C_RES}"
    return 0
}

# Проверка прямого доступа к GitHub (с защитой от фрагментации TLS 1.3 Kyber)
check_github_mirror() {
    TEST_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/private.srs"
    if curl -fsSL --curves X25519:P-256 --connect-timeout 3 -m 5 -o /dev/null "$TEST_URL" 2>/dev/null || \
       curl -fsSL --connect-timeout 3 -m 5 -o /dev/null "$TEST_URL" 2>/dev/null; then
        GH_PROXY=""
        return 0
    fi
    for MIRROR in "https://gh-proxy.com/" "https://ghproxy.net/"; do
        if curl -fsSL --curves X25519:P-256 --connect-timeout 3 -m 5 -o /dev/null "${MIRROR}${TEST_URL}" 2>/dev/null; then
            echo "${C_YEL}[!] Прямой доступ к GitHub ограничен, включено зеркало: ${MIRROR}${C_RES}"
            GH_PROXY="$MIRROR"
            return 0
        fi
    done
    GH_PROXY=""
    return 0
}

# Универсальная загрузка файла с каскадным фоллбэком на зеркала GitHub
download_file() {
    DL_URL="$1"
    DL_OUT="$2"
    for PREFIX in "$GH_PROXY" "" "https://gh-proxy.com/" "https://ghproxy.net/"; do
        if curl --curves X25519:P-256 --retry 2 --connect-timeout 5 -fL -o "$DL_OUT" "${PREFIX}${DL_URL}" 2>/dev/null || \
           curl --retry 2 --connect-timeout 5 -fL -o "$DL_OUT" "${PREFIX}${DL_URL}" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Инициализация пользовательских списков и файлов провайдеров
init_user_lists() {
    mkdir -p "$SB_RULES_DIR" "$SB_PROVIDERS_DIR" "$HOMELAB_DIR" "$HOMELAB_LIB_DIR"
    chmod 755 "$HOMELAB_LIB_DIR" 2>/dev/null || true
    [ -f "$USER_DIRECT_FILE" ] || printf "+.localdomain\n+.lan\n" > "$USER_DIRECT_FILE"
    grep -qxF "+.lan" "$USER_DIRECT_FILE" 2>/dev/null || echo "+.lan" >> "$USER_DIRECT_FILE"
    [ -f "$USER_PROXY_FILE" ] || echo "+.chatgpt.com" > "$USER_PROXY_FILE"
    [ -f "$USER_BYPASS_IPS" ] || : > "$USER_BYPASS_IPS"
    [ -f "$USER_FORCE_PROXY_IPS" ] || : > "$USER_FORCE_PROXY_IPS"
    [ -s "$CUSTOM_NODES_FILE" ] || echo "proxies: []" > "$CUSTOM_NODES_FILE"
    [ -s "$WARP_NODES_FILE" ] || echo '{"outbounds": []}' > "$WARP_NODES_FILE"
    sync_user_domain_rulesets
    return 0
}

# Безопасное разделение нескольких URI-ключей (включая протоколы sing-box-extended 2026)
format_uri_keys() {
    printf "%s\n" "$1" | tr -d '\r' | sed -E 's/[[:space:],]+((vless|vmess|ss|ssr|trojan|hy2|hysteria2|hysteria|tuic|wg|wireguard|anytls|mieru|xhttp|splithttp|socks5|trusttunnel|sudoku|call|naive\+https|naive\+quic|naive|snell|openvpn|ssh):\/\/)/\n\1/g' | sed '/^[[:space:]]*$/d'
    return 0
}

# Живой сканер Anycast-узлов Cloudflare WARP с сортировкой по минимальному RTT (в обход singbox-tun)
scan_best_warp_endpoints() {
    CANDIDATES="188.114.98.224:854 188.114.97.1:500 162.159.192.1:4500 188.114.99.224:1002 162.159.195.1:2408 188.114.96.1:1701 162.159.193.1:500 188.114.97.3:4500"
    LAN_DEV_SCAN=$(get_lan_ifname)

    if [ -n "$LAN_DEV_SCAN" ] && ip link show "$LAN_DEV_SCAN" >/dev/null 2>&1; then
        PING_CMD="ping -I ${LAN_DEV_SCAN} -c 1 -W 1"
    else
        PING_CMD="ping -c 1 -W 1"
    fi

    RTT_TMP="/tmp/warp_rtt_scan.$$"
    : > "$RTT_TMP"

    for EP in $CANDIDATES; do
        EP_IP="${EP%:*}"
        P_OUT=$($PING_CMD "$EP_IP" 2>/dev/null || true)
        if printf "%s" "$P_OUT" | grep -q "time="; then
            RTT_VAL=$(printf "%s" "$P_OUT" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n 1)
            RTT_INT="${RTT_VAL%.*}"
            [ -z "$RTT_INT" ] && RTT_INT="999"
            printf "%04d %s\n" "$RTT_INT" "$EP" >> "$RTT_TMP"
        fi
    done

    ALIVE_LIST=""
    ALIVE_CNT=0
    if [ -s "$RTT_TMP" ]; then
        for EP in $(sort -n "$RTT_TMP" | awk '{print $2}'); do
            ALIVE_LIST="${ALIVE_LIST} ${EP}"
            ALIVE_CNT=$((ALIVE_CNT + 1))
            [ "$ALIVE_CNT" -ge 4 ] && break
        done
    fi
    rm -f "$RTT_TMP"

    for EP in $CANDIDATES; do
        [ "$ALIVE_CNT" -ge 4 ] && break
        case " $ALIVE_LIST " in
            *" $EP "*) ;;
            *)
                ALIVE_LIST="${ALIVE_LIST} ${EP}"
                ALIVE_CNT=$((ALIVE_CNT + 1))
                ;;
        esac
    done

    printf "%s" "$ALIVE_LIST" | sed 's/^[[:space:]]*//'
    return 0
}

# Автоматическая бесплатная генерация гибридного Amnezia WARP 2.0 (4 UDP AWG + 1 TCP MASQUE H2 + WARP+)
generate_amnezia_warp() {
    OPT_LIC="${1:-}"
    mkdir -p "$SB_PROVIDERS_DIR"
    [ -z "${GW_IP:-}" ] && load_gateway_env || true
    [ -n "$OPT_LIC" ] && WARP_LICENSE="$OPT_LIC" || true

    if ! command -v wg >/dev/null 2>&1; then
        echo "Установка генератора ключей wireguard-tools..."
        apk update >/dev/null 2>&1 || true
        apk add wireguard-tools-wg >/dev/null 2>&1 || apk add wireguard-tools >/dev/null 2>&1 || true
    fi

    PRIV_KEY=""
    PUB_KEY=""
    if command -v wg >/dev/null 2>&1; then
        PRIV_KEY=$(wg genkey 2>/dev/null || true)
        [ -n "$PRIV_KEY" ] && PUB_KEY=$(printf "%s" "$PRIV_KEY" | wg pubkey 2>/dev/null || true) || true
    fi

    WARP_IPV4=""
    REG_ID=""
    REG_TOKEN=""
    REG_OK="no"

    if [ -n "$PUB_KEY" ]; then
        TOS_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
        REG_PAYLOAD="{\"key\":\"${PUB_KEY}\",\"install_id\":\"\",\"warp_enabled\":true,\"tos\":\"${TOS_DATE}\",\"type\":\"Android\",\"locale\":\"en_US\"}"
        echo "Бесплатная регистрация личного аккаунта Cloudflare WARP (API 2026)..."

        for CURL_OPT in \
            "" \
            "-x http://127.0.0.1:7890" \
            "--connect-to api.devices.cloudflare.com:443:104.24.4.6:443" \
            "--connect-to api.devices.cloudflare.com:443:104.18.0.6:443" \
            "--connect-to api.devices.cloudflare.com:443:162.159.137.105:443" \
            "--connect-to api.devices.cloudflare.com:443:162.159.138.105:443" \
            "--connect-to api.devices.cloudflare.com:443:104.16.80.230:443"
        do
            # shellcheck disable=SC2086
            RESP=$(curl -fsSL --curves X25519:P-256 --http1.1 --connect-timeout 4 -m 6 $CURL_OPT \
                -H "User-Agent: okhttp/3.12.1" \
                -H "Content-Type: application/json" \
                -X POST "https://api.devices.cloudflare.com/v0a4471/reg" \
                -d "$REG_PAYLOAD" 2>/dev/null || true)
            if printf "%s" "$RESP" | grep -q '"v4"'; then
                WARP_IPV4=$(printf "%s" "$RESP" | sed -n 's/.*"v4":[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1)
                REG_ID=$(printf "%s" "$RESP" | sed -n 's/.*"id":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
                REG_TOKEN=$(printf "%s" "$RESP" | sed -n 's/.*"token":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
                USED_CURL_OPT="$CURL_OPT"
                REG_OK="yes"
                break
            fi
        done

        if [ "$REG_OK" = "no" ]; then
            RESP=$(curl -fsSL --curves X25519:P-256 --http1.1 --connect-timeout 4 -m 6 \
                -H "User-Agent: okhttp/3.12.1" \
                -H "Content-Type: application/json" \
                -X POST "https://zero-trust-client.cloudflareclient.com/v0a4471/reg" \
                -d "$REG_PAYLOAD" 2>/dev/null || true)
            if printf "%s" "$RESP" | grep -q '"v4"'; then
                WARP_IPV4=$(printf "%s" "$RESP" | sed -n 's/.*"v4":[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1)
                REG_ID=$(printf "%s" "$RESP" | sed -n 's/.*"id":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
                REG_TOKEN=$(printf "%s" "$RESP" | sed -n 's/.*"token":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
                USED_CURL_OPT=""
                REG_OK="yes"
            fi
        fi

        if [ "$REG_OK" = "yes" ] && [ -n "${WARP_LICENSE:-}" ] && [ -n "$REG_ID" ] && [ -n "$REG_TOKEN" ]; then
            echo "Активация лицензионного ключа Cloudflare WARP+..."
            # shellcheck disable=SC2086
            LIC_RESP=$(curl -fsSL --curves X25519:P-256 --http1.1 --connect-timeout 4 -m 6 ${USED_CURL_OPT:-} \
                -H "User-Agent: okhttp/3.12.1" \
                -H "Authorization: Bearer ${REG_TOKEN}" \
                -H "Content-Type: application/json" \
                -X PUT "https://api.devices.cloudflare.com/v0a4471/reg/${REG_ID}/account" \
                -d "{\"license\":\"${WARP_LICENSE}\"}" 2>/dev/null || true)
            if printf "%s" "$LIC_RESP" | grep -q '"warp_plus":[[:space:]]*true'; then
                echo "${C_GRN}[✓] Статус WARP+ (Argo Priority) успешно активирован!${C_RES}"
                save_gateway_env
            else
                echo "${C_YEL}[!] Лицензия WARP+ не принята API Cloudflare, используется стандартный безлимитный WARP.${C_RES}"
                WARP_LICENSE=""
                save_gateway_env
            fi
        fi
    fi

    if [ "$REG_OK" = "no" ] && is_warp_enabled; then
        OLD_PRIV=$(sed -n 's/.*"private_key":[[:space:]]*"\([^"]*\)".*/\1/p' "$WARP_NODES_FILE" 2>/dev/null | head -n 1)
        OLD_IP=$(sed -n 's/.*"\([0-9.]*\)\/32".*/\1/p' "$WARP_NODES_FILE" 2>/dev/null | head -n 1)
        if [ -n "$OLD_PRIV" ]; then
            PRIV_KEY="$OLD_PRIV"
            WARP_IPV4="${OLD_IP:-172.16.0.2}"
            REG_OK="yes"
            echo "[i] Сохранен ранее зарегистрированный ключ Amnezia WARP."
        fi
    fi

    if [ "$REG_OK" = "no" ]; then
        echo "${C_YEL}[!] Провайдер блокирует прямой доступ к API регистрации WG Cloudflare.${C_RES}"
        printf "Вставьте готовый WARP PrivateKey [или нажмите Enter для авто-регистрации через MASQUE TCP/H2]: "
        read -r USER_PRIV < /dev/tty || true
        USER_PRIV=$(printf "%s" "$USER_PRIV" | tr -d ' \t\r\n')
        if [ -n "$USER_PRIV" ]; then
            PRIV_KEY="$USER_PRIV"
            WARP_IPV4="172.16.0.2"
            REG_OK="yes"
        elif [ -n "$PRIV_KEY" ]; then
            WARP_IPV4="172.16.0.2"
            REG_OK="yes"
            echo "${C_GRN}[i] Задействован встроенный механизм авто-регистрации WARP MASQUE (TCP/H2) внутри ядра Sing-Box!${C_RES}"
        else
            echo "${C_RED}[X] Не удалось получить или сгенерировать ключ WARP.${C_RES}"
            return 1
        fi
    fi

    [ -z "$WARP_IPV4" ] && WARP_IPV4="172.16.0.2" || true

    echo "Сканирование и сортировка по пингу Anycast-узлов Cloudflare напрямую через провайдера..."
    BEST_EPS=$(scan_best_warp_endpoints)
    # shellcheck disable=SC2086
    set -- $BEST_EPS
    EP1="${1:-188.114.98.224:854}"
    EP2="${2:-188.114.97.1:500}"
    EP3="${3:-162.159.192.1:4500}"
    EP4="${4:-188.114.99.224:1002}"

    EP1_IP="${EP1%:*}"; EP1_PORT="${EP1#*:}"
    EP2_IP="${EP2%:*}"; EP2_PORT="${EP2#*:}"
    EP3_IP="${EP3%:*}"; EP3_PORT="${EP3#*:}"
    EP4_IP="${EP4%:*}"; EP4_PORT="${EP4#*:}"

    RAND_BYTE=$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' \t\r\n' || echo "5")
    AWG_JC1=$(( (RAND_BYTE % 4) + 3 ))
    AWG_JC2=$(( ((RAND_BYTE + 1) % 4) + 4 ))
    AWG_JC3=$(( ((RAND_BYTE + 2) % 4) + 3 ))
    AWG_JC4=$(( ((RAND_BYTE + 3) % 4) + 5 ))

    HEX_R1=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \t\r\n' || echo "a1b2c3d4")
    HEX_R2=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \t\r\n' || echo "e5f60718")
    HEX_R3=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \t\r\n' || echo "99887766")
    HEX_R4=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \t\r\n' || echo "55443322")

    AWG_I1_1="<b 0xc70000000108${HEX_R1}00><r 16><t>"
    AWG_I1_2="<b 0xc30000000108${HEX_R2}00><r 24><t>"
    AWG_I1_3="<r 2><b 0x818000010001000000000361706905647a656e0272750000010001c00c000100010000003c0004${HEX_R3}>"
    AWG_I1_4="<b 0xcb0000000108${HEX_R4}00><t><r 20>"

    cat << WARP_EOF > "${WARP_NODES_FILE}.tmp.$$"
{
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "☁️ WARP Fast (${EP1_IP}:${EP1_PORT})",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "${EP1_IP}",
          "port": ${EP1_PORT},
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0"
          ]
        }
      ],
      "amnezia": {
        "jc": ${AWG_JC1},
        "jmin": 36,
        "jmax": 68,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "${AWG_I1_1}"
      }
    },
    {
      "type": "wireguard",
      "tag": "☁️ WARP Reserve (${EP2_IP}:${EP2_PORT})",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "${EP2_IP}",
          "port": ${EP2_PORT},
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0"
          ]
        }
      ],
      "amnezia": {
        "jc": ${AWG_JC2},
        "jmin": 42,
        "jmax": 76,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "${AWG_I1_2}"
      }
    },
    {
      "type": "wireguard",
      "tag": "☁️ WARP Alt (${EP3_IP}:${EP3_PORT})",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "${EP3_IP}",
          "port": ${EP3_PORT},
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0"
          ]
        }
      ],
      "amnezia": {
        "jc": ${AWG_JC3},
        "jmin": 38,
        "jmax": 72,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "${AWG_I1_3}"
      }
    },
    {
      "type": "wireguard",
      "tag": "☁️ WARP Engage (${EP4_IP}:${EP4_PORT})",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "${EP4_IP}",
          "port": ${EP4_PORT},
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0"
          ]
        }
      ],
      "amnezia": {
        "jc": ${AWG_JC4},
        "jmin": 44,
        "jmax": 82,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "${AWG_I1_4}"
      }
    }
  ],
  "masque": {
    "type": "masque",
    "tag": "☁️ WARP MASQUE (TCP/H2)",
    "use_http2": true,
    "use_l4_proxy": false,
    "use_ipv6": false,
    "profile": {
      "detour": "DIRECT",
      "id": "",
      "auth_token": "",
      "license_key": "${WARP_LICENSE:-}"
    },
    "address": "162.159.198.2",
    "port": 443,
    "udp_timeout": "5m0s",
    "udp_keepalive_period": "30s",
    "reconnect_delay": "5s",
    "handshake_timeout": "10s",
    "congestion_controller": "bbr",
    "tls": {
      "server_name": "",
      "insecure": false,
      "fragment": true,
      "fragment_fallback_delay": "500ms",
      "record_fragment": true
    }
  }
}
WARP_EOF
    chmod 600 "${WARP_NODES_FILE}.tmp.$$" 2>/dev/null || true
    mv -f "${WARP_NODES_FILE}.tmp.$$" "$WARP_NODES_FILE"
    chmod 600 "$WARP_NODES_FILE" 2>/dev/null || true
    echo "${C_GRN}[✓] Гибридный пул WARP 2.0 (4 ноды UDP AWG: ${EP1}, ${EP2}, ${EP3}, ${EP4} + 1 нода TCP MASQUE H2) создан!${C_RES}"
    return 0
}

# Горячая перезагрузка всех активных провайдеров и мгновенный выбор лучшей ноды в Авто
reload_singbox_api() {
    if ! pgrep sing-box >/dev/null 2>&1; then
        return 0
    fi
    load_gateway_env
    P_LIST=""
    if [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        P_LIST=$(jq -r '.providers[]?.tag // empty' "$SB_CONF" 2>/dev/null || true)
    fi
    [ -z "$P_LIST" ] && P_LIST="custom_sub custom_sub_2 custom_sub_3 my_nodes"

    for P_TAG in $P_LIST; do
        curl -fsS -X PUT -H "Authorization: Bearer ${ADMIN_PASS}" \
            "http://127.0.0.1:9090/providers/proxies/${P_TAG}" >/dev/null 2>&1 || true
    done
    curl -g -fsS --connect-timeout 2 -m 7 -H "Authorization: Bearer ${ADMIN_PASS}" \
        "http://127.0.0.1:9090/group/%E2%9A%A1%20%D0%90%D0%B2%D1%82%D0%BE%20%28%D0%A1%D0%B0%D0%BC%D1%8B%D0%B9%20%D0%B1%D1%8B%D1%81%D1%82%D1%80%D1%8B%D0%B9%29/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=6000" >/dev/null 2>&1 || true
    return 0
}

# Очистка ссылки на подписку от несовместимых с Sing-Box параметров fmt=xray/v2ray/best
sanitize_sub_url_list() {
    RAW_URLS="$1"
    CLEAN_LIST=""
    for U in $(printf "%s\n" "$RAW_URLS" | tr ' |,' '\n\n\n'); do
        [ -z "$U" ] && continue
        C_U=$(printf "%s" "$U" | sed -E 's/([?&])fmt=(best|xray|v2ray)(&|$)/\1/; s/[?&]$//')
        if [ -z "$CLEAN_LIST" ]; then
            CLEAN_LIST="$C_U"
        else
            CLEAN_LIST="${CLEAN_LIST} ${C_U}"
        fi
    done
    printf "%s" "$CLEAN_LIST"
    return 0
}

# Распределение ввода по 3 независимым слотам: Слот 1 (HTTP), Слот 2 (my_nodes.yaml), Слот 3 (WARP + MASQUE)
apply_subscription_input() {
    RAW_INPUT="$1"
    mkdir -p "$SB_PROVIDERS_DIR"
    case "$RAW_INPUT" in
        *warp_nodes*|warp|WARP|amnezia|masque|free)
            SUB_URL=""
            USE_INITIAL_WARP="yes"
            ;;
        none|NONE|direct|DIRECT|off|OFF)
            SUB_URL=""
            USE_INITIAL_WARP="no"
            ;;
        http://*|https://*)
            CLEAN_SUB_URL=$(sanitize_sub_url_list "$RAW_INPUT")
            if [ "$CLEAN_SUB_URL" != "$RAW_INPUT" ]; then
                echo "[i] Список подписок нормализован для совместимости с Sing-Box."
            fi
            SUB_URL="$CLEAN_SUB_URL"
            USE_INITIAL_WARP="no"
            ;;
        vless://*|vmess://*|ss://*|ssr://*|trojan://*|hy2://*|hysteria2://*|hysteria://*|tuic://*|wg://*|wireguard://*|anytls://*|mieru://*|xhttp://*|splithttp://*|socks5://*|trusttunnel://*|sudoku://*|call://*|naive+https://*|naive+quic://*|naive://*|snell://*|openvpn://*|ssh://*)
            sed -i '/^proxies:[[:space:]]*\[\]/d' "$CUSTOM_NODES_FILE" 2>/dev/null || true
            format_uri_keys "$RAW_INPUT" >> "$CUSTOM_NODES_FILE"
            SUB_URL=""
            USE_INITIAL_WARP="no"
            ;;
        *)
            SUB_URL="$RAW_INPUT"
            USE_INITIAL_WARP="no"
            ;;
    esac
    return 0
}

# Загрузка и установка веб-панели Zashboard с сохранением версии
install_zashboard_ui() {
    TARGET_UI_VER="${1:-}"
    [ -z "$TARGET_UI_VER" ] && TARGET_UI_VER=$(fetch_latest_github_tag "$UI_REPO") || true

    echo "Загрузка и установка веб-панели Zashboard ${TARGET_UI_VER}..."
    rm -rf /tmp/sb_ui.tar.gz /tmp/sb_ui_extract
    mkdir -p /tmp/sb_ui_extract

    if download_file "$UI_TAR_URL" "/tmp/sb_ui.tar.gz" && tar -xzf /tmp/sb_ui.tar.gz -C /tmp/sb_ui_extract 2>/dev/null; then
        rm -rf "${SB_DIR}/ui"
        mkdir -p "${SB_DIR}/ui"
        cp -rf /tmp/sb_ui_extract/*/* "${SB_DIR}/ui/" 2>/dev/null || cp -rf /tmp/sb_ui_extract/* "${SB_DIR}/ui/"
        [ -n "$TARGET_UI_VER" ] && echo "$TARGET_UI_VER" > "$UI_VER_FILE" || true
        LATEST_UI_TAG="$TARGET_UI_VER"
        rm -rf /tmp/sb_ui.tar.gz /tmp/sb_ui_extract
        echo "${C_GRN}[✓] Веб-панель Zashboard ${TARGET_UI_VER} успешно установлена в ${SB_DIR}/ui.${C_RES}"
        return 0
    else
        rm -rf /tmp/sb_ui.tar.gz /tmp/sb_ui_extract
        echo "${C_RED}[X] Ошибка загрузки или распаковки веб-панели Zashboard!${C_RES}"
        return 1
    fi
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

# Атомарное обновление бинарников Sing-Box Extended, AdGuard Home и Zashboard (с верификацией SHA-256)
update_cores_only() {
    CHECK_UI_UPDATE="${1:-no}"
    detect_os
    check_github_mirror

    SB_TAG=$(fetch_latest_github_tag "shtorm-7/sing-box-extended")
    [ -z "$SB_TAG" ] && SB_TAG="v1.14.3-extended-2.7.3" || true
    LATEST_SB_TAG="$SB_TAG"
    SB_VER_NO_V="${SB_TAG#v}"

    INSTALLED_SB_VER=""
    if [ -x /usr/bin/sing-box ]; then
        RAW_V=$(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        [ -n "$RAW_V" ] && INSTALLED_SB_VER="v${RAW_V#v}" || true
    fi

    if [ "$INSTALLED_SB_VER" = "$SB_TAG" ]; then
        echo "${C_GRN}[✓] Ядро Sing-Box Extended ${INSTALLED_SB_VER} (${SB_ARCH}) актуально.${C_RES}"
    else
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
                        echo "${C_GRN}[✓] Sing-Box Extended безопасно обновлен до ${SB_TAG}.${C_RES}"
                    else
                        echo "${C_RED}[X] Ошибка: скачанный бинарник sing-box поврежден, оставлена текущая версия.${C_RES}"
                    fi
                fi
            fi
            rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
        else
            rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
            echo "${C_RED}[X] Не удалось скачать Sing-Box Extended ${SB_TAG}.${C_RES}"
        fi
    fi

    AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
    [ -z "$AGH_TAG" ] && AGH_TAG="v0.107.79" || true
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
        UI_TAG=$(fetch_latest_github_tag "$UI_REPO")
        LATEST_UI_TAG="$UI_TAG"
        INSTALLED_UI_VER=""
        [ -f "$UI_VER_FILE" ] && INSTALLED_UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n') || true

        if [ -f "${SB_DIR}/ui/index.html" ] && [ -n "$UI_TAG" ] && [ "$INSTALLED_UI_VER" = "$UI_TAG" ]; then
            echo "${C_GRN}[✓] Веб-панель Zashboard ${INSTALLED_UI_VER} актуальна.${C_RES}"
        else
            install_zashboard_ui "$UI_TAG" || true
        fi
    fi

    cat << VC_EOF > "$VER_CACHE_FILE" 2>/dev/null || true
LATEST_SB_TAG='${LATEST_SB_TAG}'
LATEST_AGH_TAG='${LATEST_AGH_TAG}'
LATEST_UI_TAG='${LATEST_UI_TAG}'
VC_EOF
    return 0
}

# Создание системных служб автозапуска Alpine OpenRC (с защитой сетевого шлюза от OOM-killer)
setup_init_scripts() {
    calc_hardware_limits

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
export GOGC=50
export GOMEMLIMIT=${SB_GOMEMLIMIT}
export ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true
export ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true

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
export GOGC=50
export GOMEMLIMIT=${AGH_GOMEMLIMIT}

depend() {
    need net
    after sing-box
}
INIT_AGH_ALP
    chmod +x /etc/init.d/adguardhome

    service_ctl sing-box enable
    service_ctl sing-box restart
    sleep 2
    service_ctl adguardhome enable
    service_ctl adguardhome restart
    return 0
}
# ==================== [ КОНЕЦ ЧАСТИ 3 ИЗ 6 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 4 ИЗ 6 ] ====================
# ==============================================================================
# Ядро подсистемы Homelab: Реестр модулей, Единое хранилище /srv/storage,
# Центральный HTTPS/PKI прокси Caddy (*.lan) и Файловый сервер Samba (WSDD+Avahi)
# ==============================================================================

# Активация официального репозитория community в Alpine Linux
ensure_alpine_community_repo() {
    if [ -f /etc/apk/repositories ]; then
        sed -i 's|^#[[:space:]]*\(https\?://.*/v[0-9.]*/community\)|\1|' /etc/apk/repositories 2>/dev/null || true
        sed -i 's|^#[[:space:]]*\(https\?://.*/edge/community\)|\1|' /etc/apk/repositories 2>/dev/null || true
        if ! grep -q '^https\?://.*/community' /etc/apk/repositories 2>/dev/null; then
            MAIN_REPO_LINE=$(grep -E '^https?://.*/main' /etc/apk/repositories 2>/dev/null | head -n 1 || true)
            if [ -n "$MAIN_REPO_LINE" ]; then
                COMM_REPO_LINE=$(printf "%s" "$MAIN_REPO_LINE" | sed 's|/main$|/community|')
                echo "$COMM_REPO_LINE" >> /etc/apk/repositories
            fi
        fi
    fi
    return 0
}

# Инициализация реестра модулей Homelab (/etc/sing-box/homelab/modules.state)
# Формат: ID|ENABLED|OPENRC_SVC|PORT|DOMAIN|SYS_USER|TITLE
init_homelab_registry() {
    umask 022
    mkdir -p "$HOMELAB_DIR" "$HOMELAB_LIB_DIR"
    chmod 755 "$HOMELAB_LIB_DIR" 2>/dev/null || true
    if [ ! -s "$HOMELAB_STATE" ]; then
        cat << 'REG_EOF' > "$HOMELAB_STATE"
# MODULE_ID|ENABLED|OPENRC_SVC|PORT|DOMAIN|SYS_USER|TITLE
caddy|no|caddy|443|ca.lan|caddy|Caddy HTTPS & Local PKI
samba|no|samba|445|_|homelab|Samba SMB2/3 + WSDD + Avahi
vaultwarden|no|vaultwarden|8222|vaultwarden.lan|vaultwarden|Vaultwarden (Bitwarden Server)
forgejo|no|forgejo|3001|forgejo.lan|forgejo|Forgejo (Git Service)
code|no|code-server|8443|code.lan|coder|Server-Code (VS Code Web IDE)
navidrome|no|navidrome|4533|music.lan|navidrome|Navidrome (Music Streaming)
jellyfin|no|jellyfin|8096|jellyfin.lan|jellyfin|Jellyfin (Media Server)
ytdlp|no|ytdlp-webui|8081|downloads.lan|ytdlp|yt-dlp Web UI (Video/Audio Downloader)
torrent|no|qbittorrent-nox|8080|torrents.lan|qbittorrent|qBittorrent-nox (Torrent Web UI)
REG_EOF
    fi
    return 0
}

# Проверка, включен ли модуль в реестре Homelab
is_module_enabled() {
    MOD_QUERY="$1"
    [ -f "$HOMELAB_STATE" ] || return 1
    awk -F'|' -v m="$MOD_QUERY" '$1 == m && $2 == "yes" {found=1} END {exit !found}' "$HOMELAB_STATE" 2>/dev/null
}

# Получение поля модуля из реестра (2=ENABLED, 3=SVC, 4=PORT, 5=DOMAIN, 6=USER, 7=TITLE)
get_module_field() {
    MOD_QUERY="$1"
    FIELD_IDX="$2"
    init_homelab_registry
    awk -F'|' -v m="$MOD_QUERY" -v f="$FIELD_IDX" '$1 == m {print $f; exit}' "$HOMELAB_STATE" 2>/dev/null
    return 0
}

# Обновление статуса ENABLED (yes/no) для модуля в реестре
set_module_state() {
    MOD_TARGET="$1"
    NEW_STATE="$2"
    init_homelab_registry
    awk -F'|' -v OFS='|' -v m="$MOD_TARGET" -v st="$NEW_STATE" '
        $1 == m { $2 = st }
        { print }
    ' "$HOMELAB_STATE" > "${HOMELAB_STATE}.tmp.$$" && mv -f "${HOMELAB_STATE}.tmp.$$" "$HOMELAB_STATE"
    return 0
}

# Подсчет количества активных модулей Homelab
count_enabled_homelab_modules() {
    [ -f "$HOMELAB_STATE" ] || { echo "0"; return 0; }
    awk -F'|' '$1 !~ /^#/ && $2 == "yes" {c++} END {print c+0}' "$HOMELAB_STATE" 2>/dev/null
    return 0
}

# Создание единой группы media (GID 990) и системных пользователей для Samba и сервисов общего хранилища
ensure_media_group_and_users() {
    if [ -z "${SMB_USER:-}" ] || [ -z "${ADMIN_PASS:-}" ]; then
        load_gateway_env
    fi
    [ -z "${SMB_USER:-}" ] && SMB_USER="${AGH_USER:-homelab}"

    if ! grep -q "^${MEDIA_GROUP}:" /etc/group 2>/dev/null; then
        addgroup -g "$MEDIA_GID" "$MEDIA_GROUP" 2>/dev/null || addgroup "$MEDIA_GROUP" 2>/dev/null || true
    fi

    if ! id "$SMB_USER" >/dev/null 2>&1; then
        adduser -D -H -s /sbin/nologin -G "$MEDIA_GROUP" "$SMB_USER" 2>/dev/null || \
        adduser -D -H -s /sbin/nologin "$SMB_USER" 2>/dev/null || true
    fi
    addgroup "$SMB_USER" "$MEDIA_GROUP" 2>/dev/null || true

    # Разблокировка сервисных и пользовательских аккаунтов ('!' -> '*' в /etc/shadow) для smbd, OpenRC и su
    for UNLOCK_U in "$SMB_USER" caddy vaultwarden forgejo navidrome jellyfin ytdlp qbittorrent coder homelab; do
        if [ -f /etc/shadow ] && grep -q "^${UNLOCK_U}:!" /etc/shadow 2>/dev/null; then
            sed -i "s/^${UNLOCK_U}:!/${UNLOCK_U}:*/" /etc/shadow 2>/dev/null || passwd -u "$UNLOCK_U" >/dev/null 2>&1 || true
        fi
    done

    # Добавление установленных сервисных пользователей медиаконвейера в единую группу media
    for SVC_U in jellyfin navidrome ytdlp qbittorrent coder; do
        if id "$SVC_U" >/dev/null 2>&1; then
            addgroup "$SVC_U" "$MEDIA_GROUP" 2>/dev/null || true
        fi
    done
    return 0
}

# Инициализация структуры единого хранилища /srv/storage и настройка прав (setgid 2775 + POSIX ACL)
init_homelab_storage() {
    umask 002
    ensure_media_group_and_users
    mkdir -p \
        "$STORAGE_MUSIC" \
        "$STORAGE_VIDEOS" \
        "$STORAGE_VIDEOS_MOVIES" \
        "$STORAGE_VIDEOS_SERIES" \
        "$STORAGE_DOWNLOADS" \
        "$STORAGE_DL_MUSIC" \
        "$STORAGE_DL_VIDEOS" \
        "$STORAGE_DL_OTHER" \
        "$STORAGE_INCOMPLETE" \
        "$STORAGE_INC_TORRENTS" \
        "$STORAGE_INC_YTDLP"

    repair_storage_permissions
    umask 022
    return 0
}

# Выставление эталонных прав доступа на /srv/storage (группа media, setgid 2775, POSIX ACL)
repair_storage_permissions() {
    ensure_media_group_and_users
    [ -d "$STORAGE_ROOT" ] || return 0

    chmod 755 /srv 2>/dev/null || true
    chown "${SMB_USER}:${MEDIA_GROUP}" "$STORAGE_ROOT" 2>/dev/null || chown root:"$MEDIA_GROUP" "$STORAGE_ROOT" 2>/dev/null || true
    chmod 2775 "$STORAGE_ROOT" 2>/dev/null || true

    for SUB_D in \
        "$STORAGE_MUSIC" \
        "$STORAGE_VIDEOS" \
        "$STORAGE_VIDEOS_MOVIES" \
        "$STORAGE_VIDEOS_SERIES" \
        "$STORAGE_DOWNLOADS" \
        "$STORAGE_DL_MUSIC" \
        "$STORAGE_DL_VIDEOS" \
        "$STORAGE_DL_OTHER" \
        "$STORAGE_INCOMPLETE" \
        "$STORAGE_INC_TORRENTS" \
        "$STORAGE_INC_YTDLP"; do
        [ -d "$SUB_D" ] || mkdir -p "$SUB_D" 2>/dev/null || continue
    done

    for TOP_D in "$STORAGE_MUSIC" "$STORAGE_VIDEOS" "$STORAGE_DOWNLOADS"; do
        [ -d "$TOP_D" ] || continue
        chown -R "${SMB_USER}:${MEDIA_GROUP}" "$TOP_D" 2>/dev/null || chgrp -R "$MEDIA_GROUP" "$TOP_D" 2>/dev/null || true
        find "$TOP_D" -type d -exec chmod 2775 {} + 2>/dev/null || true
        find "$TOP_D" -type f -exec chmod 0664 {} + 2>/dev/null || true
    done

    # Выделение прав владельца на временные буферы соответствующим демонам при сохранении группы media (2775)
    if id qbittorrent >/dev/null 2>&1 && [ -d "$STORAGE_INC_TORRENTS" ]; then
        chown -R "qbittorrent:${MEDIA_GROUP}" "$STORAGE_INC_TORRENTS" 2>/dev/null || true
        chmod 2775 "$STORAGE_INC_TORRENTS" 2>/dev/null || true
    fi
    if id ytdlp >/dev/null 2>&1 && [ -d "$STORAGE_INC_YTDLP" ]; then
        chown -R "ytdlp:${MEDIA_GROUP}" "$STORAGE_INC_YTDLP" 2>/dev/null || true
        chmod 2775 "$STORAGE_INC_YTDLP" 2>/dev/null || true
    fi

    # Применение наследуемых POSIX ACL (если установлен пакет acl и ФС поддерживает ACL)
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" -d -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" "$STORAGE_ROOT" 2>/dev/null || true
        setfacl -R -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" -d -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" \
            "$STORAGE_MUSIC" "$STORAGE_VIDEOS" "$STORAGE_DOWNLOADS" 2>/dev/null || true
        for ACL_U in jellyfin navidrome ytdlp qbittorrent coder; do
            if id "$ACL_U" >/dev/null 2>&1; then
                setfacl -R -m "u:${ACL_U}:rwx" -d -m "u:${ACL_U}:rwx" \
                    "$STORAGE_MUSIC" "$STORAGE_VIDEOS" "$STORAGE_DOWNLOADS" 2>/dev/null || true
            fi
        done
    fi
    return 0
}

# Вывод статистики использования единого хранилища /srv/storage
print_storage_stats() {
    init_homelab_storage
    echo "${C_CYN}=== Состояние единого файлового хранилища (${STORAGE_ROOT}) ===${C_RES}"
    df -h "$STORAGE_ROOT" 2>/dev/null | awk 'NR==1 {print "  " $0} NR==2 {printf "  Раздел: %s | Всего: %s | Занято: %s (%s) | Свободно: %s\n", $1, $2, $3, $5, $4}' || true
    echo "---------------------------------------------------------------"
    for D_ITEM in \
        "$STORAGE_MUSIC" \
        "$STORAGE_VIDEOS" \
        "$STORAGE_VIDEOS_MOVIES" \
        "$STORAGE_VIDEOS_SERIES" \
        "$STORAGE_DOWNLOADS" \
        "$STORAGE_DL_MUSIC" \
        "$STORAGE_DL_VIDEOS" \
        "$STORAGE_DL_OTHER" \
        "$STORAGE_INCOMPLETE" \
        "$STORAGE_INC_TORRENTS" \
        "$STORAGE_INC_YTDLP"; do
        if [ -d "$D_ITEM" ]; then
            D_SZ=$(du -sh "$D_ITEM" 2>/dev/null | awk '{print $1}' || echo "0")
            D_PM=$(stat -c "%a %U:%G" "$D_ITEM" 2>/dev/null || echo "н/д")
            printf "  • %-40s : %s%-8s%s (%s)\n" "$D_ITEM" "$C_BLD" "$D_SZ" "$C_RES" "$D_PM"
        fi
    done
    echo "---------------------------------------------------------------"
    return 0
}

# ==============================================================================
# Центральная система HTTPS, локальный PKI и домены *.lan (Caddy + AdGuard Home)
# ==============================================================================

# Поиск актуального пути корневого сертификата Caddy Root CA
find_caddy_root_cert() {
    for c_cand in \
        "$CADDY_ROOT_CERT" \
        "/var/lib/caddy/caddy/pki/authorities/local/root.crt" \
        "/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt" \
        "/root/.local/share/caddy/pki/authorities/local/root.crt"; do
        if [ -f "$c_cand" ]; then
            CADDY_ROOT_CERT="$c_cand"
            return 0
        fi
    done
    return 1
}

# Генерация веб-портала http://ca.lan для удобной установки корневого сертификата на Windows 11, Linux и Android
build_pki_portal() {
    umask 022
    mkdir -p "$PKI_PORTAL_DIR" /usr/local/share/ca-certificates
    chmod 755 /srv /srv/homelab "$PKI_PORTAL_DIR" 2>/dev/null || true
    CUR_LIP=$(get_current_lan_ip)

    # Принудительная инициализация локального CA Caddy от имени пользователя caddy
    if ! find_caddy_root_cert && [ -x /usr/sbin/caddy ]; then
        chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
        su -s /bin/sh caddy -c 'XDG_DATA_HOME="/var/lib/caddy" XDG_CONFIG_HOME="/var/lib/caddy" HOME="/var/lib/caddy" /usr/sbin/caddy trust' >/dev/null 2>&1 || true
        chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
        chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    fi

    if find_caddy_root_cert; then
        cp -f "$CADDY_ROOT_CERT" "${PKI_PORTAL_DIR}/homelab-root-ca.crt" 2>/dev/null || true
        cp -f "$CADDY_ROOT_CERT" "${PKI_PORTAL_DIR}/homelab-root-ca.cer" 2>/dev/null || true
        chmod 644 "${PKI_PORTAL_DIR}/homelab-root-ca.crt" "${PKI_PORTAL_DIR}/homelab-root-ca.cer" 2>/dev/null || true
        cp -f "$CADDY_ROOT_CERT" /usr/local/share/ca-certificates/homelab-root-ca.crt 2>/dev/null || true
        chmod 644 /usr/local/share/ca-certificates/homelab-root-ca.crt 2>/dev/null || true
        update-ca-certificates >/dev/null 2>&1 || true
    fi

    cat << HTML_EOF > "${PKI_PORTAL_DIR}/index.html"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Alpine Homelab PKI — Установка сертификата HTTPS</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; background: #0f172a; color: #e2e8f0; max-width: 820px; margin: 2rem auto; padding: 0 1.2rem; line-height: 1.6; }
  .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 1.5rem; margin-bottom: 1.5rem; }
  h1, h2 { color: #38bdf8; margin-top: 0; }
  .btn { display: inline-block; background: #0284c7; color: #fff; text-decoration: none; padding: 0.75rem 1.4rem; border-radius: 8px; font-weight: 600; margin-right: 0.8rem; margin-bottom: 0.5rem; }
  .btn:hover { background: #0369a1; }
  pre { background: #090d16; color: #a7f3d0; padding: 1rem; border-radius: 8px; overflow-x: auto; font-size: 0.9rem; border: 1px solid #1e293b; }
  a { color: #38bdf8; }
</style>
</head>
<body>
  <div class="card">
    <h1>🔒 Локальный Центр Сертификации (Alpine Homelab PKI)</h1>
    <p>Сервер: <b>${CUR_LIP}</b> | Чтобы браузеры доверяли локальным доменам <code>https://*.lan</code> (включая WebCrypto API и WebAssembly SDK для Vaultwarden), установите корневой сертификат:</p>
    <p>
      <a class="btn" href="/homelab-root-ca.crt" download>📥 Скачать для Windows / Linux (.crt)</a>
      <a class="btn" href="/homelab-root-ca.cer" download>📱 Скачать для Android / iOS (.cer)</a>
    </p>
  </div>

  <div class="card">
    <h2>🪟 Windows 11 / 10 (Автоматически через PowerShell от Администратора)</h2>
    <pre>Invoke-WebRequest -Uri "http://ca.lan/homelab-root-ca.crt" -OutFile "\$env:TEMP\homelab-ca.crt"; Import-Certificate -FilePath "\$env:TEMP\homelab-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root</pre>
  </div>

  <div class="card">
    <h2>🐧 Linux (Debian / Ubuntu / Mint / Arch / Fedora)</h2>
    <pre>sudo curl -fsSL http://ca.lan/homelab-root-ca.crt -o /usr/local/share/ca-certificates/homelab-ca.crt &amp;&amp; sudo update-ca-certificates</pre>
  </div>

  <div class="card">
    <h2>🤖 Android (Установка вручную)</h2>
    <ol>
      <li>Нажмите кнопку <b>«Скачать для Android (.cer)»</b> выше.</li>
      <li>Откройте <b>Настройки &rarr; Безопасность и конфиденциальность &rarr; Другие настройки безопасности &rarr; Шифрование и учетные данные</b>.</li>
      <li>Выберите <b>Установка сертификата &rarr; Сертификат CA &rarr; Все равно установить</b> и укажите скачанный файл <code>homelab-root-ca.cer</code>.</li>
    </ol>
  </div>

  <div class="card">
    <h2>🏠 Все сервисы вашего домашнего сервера</h2>
    <ul>
      <li><a href="https://${DOM_ZASHBOARD}/ui/">https://${DOM_ZASHBOARD}</a> (или <a href="https://${DOM_SINGBOX}/ui/">https://${DOM_SINGBOX}</a>) — Панель Sing-Box (Zashboard)</li>
      <li><a href="https://${DOM_ADGUARD}">https://${DOM_ADGUARD}</a> — Панель AdGuard Home</li>
      <li><a href="https://${DOM_VAULTWARDEN}">https://${DOM_VAULTWARDEN}</a> — Vaultwarden (Пароли)</li>
      <li><a href="https://${DOM_JELLYFIN}">https://${DOM_JELLYFIN}</a> — Jellyfin (Единая медиаплатформа: Видео + Музыка)</li>
      <li><a href="https://${DOM_NAVIDROME}">https://${DOM_NAVIDROME}</a> — Navidrome (Специализированный музыкальный сервер Subsonic)</li>
      <li><a href="https://${DOM_YTDLP}">https://${DOM_YTDLP}</a> — yt-dlp Web UI (Загрузчик видео/аудио)</li>
      <li><a href="https://${DOM_TORRENT}">https://${DOM_TORRENT}</a> — qBittorrent (Торренты)</li>
      <li><a href="https://${DOM_FORGEJO}">https://${DOM_FORGEJO}</a> — Forgejo (Git-сервер)</li>
      <li><a href="https://${DOM_CODE}">https://${DOM_CODE}</a> — Server-Code (VS Code в браузере)</li>
    </ul>
  </div>
</body>
</html>
HTML_EOF
    chmod 644 "${PKI_PORTAL_DIR}/index.html" 2>/dev/null || true
    chown -R caddy:caddy "$PKI_PORTAL_DIR" 2>/dev/null || true
    return 0
}

# Генерация главного файла /etc/caddy/Caddyfile (включая сертификаты для AdGuard Home и Sing-Box Zashboard)
sync_caddy_main_config() {
    umask 022
    mkdir -p /etc/caddy "$CADDY_CONFD" "$PKI_PORTAL_DIR"
    chmod 755 /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    CUR_LIP_CDY=$(get_current_lan_ip)
    cat << CADDY_MAIN > "${CADDY_CONF}.tmp.$$"
{
    local_certs
    skip_install_trust
    auto_https disable_redirects
    servers {
        protocols h1 h2
    }
    pki {
        ca local {
            name "Alpine Homelab Root CA"
            root_cn "Alpine Homelab Root CA"
            intermediate_cn "Alpine Homelab Intermediate CA"
        }
    }
}

http://${DOM_CA}, http://${CUR_LIP_CDY}, http://*.lan {
    @pki_portal host ${DOM_CA} ${CUR_LIP_CDY}
    handle @pki_portal {
        root * ${PKI_PORTAL_DIR}
        header /homelab-root-ca.cer Content-Type "application/x-x509-ca-cert"
        header /homelab-root-ca.crt Content-Type "application/x-x509-ca-cert"
        file_server
    }
    handle {
        redir https://{host}{uri} permanent
    }
}

https://${DOM_CA} {
    tls internal
    root * ${PKI_PORTAL_DIR}
    header /homelab-root-ca.cer Content-Type "application/x-x509-ca-cert"
    header /homelab-root-ca.crt Content-Type "application/x-x509-ca-cert"
    file_server
}

https://${DOM_ADGUARD} {
    tls internal
    encode zstd gzip
    reverse_proxy 127.0.0.1:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}

https://${DOM_ZASHBOARD}, https://${DOM_SINGBOX} {
    tls internal
    encode zstd gzip
    @root_ui path /
    redir @root_ui /ui/ 302
    reverse_proxy 127.0.0.1:9090 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}

import ${CADDY_CONFD}/*.caddy
CADDY_MAIN
    chmod 644 "${CADDY_CONF}.tmp.$$" 2>/dev/null || true
    mv -f "${CADDY_CONF}.tmp.$$" "$CADDY_CONF"
    chown -R caddy:caddy /etc/caddy /var/lib/caddy 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    return 0
}

# Безопасная перезагрузка Caddy с проверкой синтаксиса и сохранением владельца caddy:caddy на PKI
reload_caddy_safe() {
    [ -x /usr/sbin/caddy ] || return 0
    sync_caddy_main_config
    chown -R caddy:caddy /var/lib/caddy /etc/caddy /var/log/caddy.log 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    if su -s /bin/sh caddy -c "XDG_DATA_HOME=/var/lib/caddy XDG_CONFIG_HOME=/var/lib/caddy HOME=/var/lib/caddy /usr/sbin/caddy validate --config '$CADDY_CONF' --adapter caddyfile" >/dev/null 2>&1 || \
       XDG_DATA_HOME="/var/lib/caddy" XDG_CONFIG_HOME="/var/lib/caddy" HOME="/var/lib/caddy" /usr/sbin/caddy validate --config "$CADDY_CONF" --adapter caddyfile >/dev/null 2>&1; then
        chown -R caddy:caddy /var/lib/caddy /etc/caddy 2>/dev/null || true
        chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
        service_ctl caddy enable
        if rc-service caddy status >/dev/null 2>&1; then
            rc-service caddy restart >/dev/null 2>&1 || true
        else
            rc-service caddy start >/dev/null 2>&1 || true
        fi
        sleep 1
        # Триггер TLS handshake для гарантированной генерации локального Root CA Caddy
        curl -ksS --connect-timeout 2 -m 3 --resolve "${DOM_CA}:443:127.0.0.1" "https://${DOM_CA}/" >/dev/null 2>&1 || true
        chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
        build_pki_portal
        return 0
    else
        echo "${C_RED}[X] Ошибка валидации Caddyfile! Проверьте конфигурацию.${C_RES}" >&2
        return 1
    fi
}

# Подключение HTTPS-маршрута сервиса в /etc/caddy/conf.d/<module>.caddy
register_caddy_site() {
    SITE_MOD="$1"
    SITE_DOM="$2"
    SITE_PORT="$3"
    USE_BASIC_AUTH="${4:-no}"

    if ! is_module_enabled "caddy"; then
        install_module_caddy || return 1
    fi

    umask 022
    mkdir -p "$CADDY_CONFD"
    chmod 755 "$CADDY_CONFD" 2>/dev/null || true
    AUTH_BLOCK=""
    if [ "$USE_BASIC_AUTH" = "yes" ] && [ -x /usr/sbin/caddy ]; then
        load_gateway_env
        AUTH_USER="${SMB_USER:-${AGH_USER:-admin}}"
        C_HASH=$(/usr/sbin/caddy hash-password --plaintext "${ADMIN_PASS:-admin}" 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)
        [ -z "$C_HASH" ] && C_HASH=$(printf "%s\n" "${ADMIN_PASS:-admin}" | htpasswd -inBC 12 "$AUTH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        if [ -n "$C_HASH" ]; then
            if [ "$AUTH_USER" != "admin" ]; then
                AUTH_BLOCK="    basic_auth {
        ${AUTH_USER} ${C_HASH}
        admin ${C_HASH}
    }"
            else
                AUTH_BLOCK="    basic_auth {
        ${AUTH_USER} ${C_HASH}
    }"
            fi
        fi
    fi

    if [ "$SITE_MOD" = "vaultwarden" ]; then
        # Чистый эталонный профиль проксирования для Vaultwarden (с передачей X-Forwarded-Proto и без модификации заводских заголовков)
        cat << VW_SITE_EOF > "${CADDY_CONFD}/${SITE_MOD}.caddy"
https://${SITE_DOM} {
    tls internal
    encode zstd gzip

    request_body {
        max_size 525MB
    }

    reverse_proxy 127.0.0.1:${SITE_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
VW_SITE_EOF
    else
        cat << SITE_EOF > "${CADDY_CONFD}/${SITE_MOD}.caddy"
https://${SITE_DOM} {
    tls internal
    encode zstd gzip
${AUTH_BLOCK}
    reverse_proxy 127.0.0.1:${SITE_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}
SITE_EOF
    fi
    chmod 644 "${CADDY_CONFD}/${SITE_MOD}.caddy" 2>/dev/null || true
    reload_caddy_safe
    return 0
}

# Отключение HTTPS-маршрута сервиса из /etc/caddy/conf.d/
remove_caddy_site() {
    SITE_MOD="$1"
    rm -f "${CADDY_CONFD}/${SITE_MOD}.caddy" 2>/dev/null || true
    if is_module_enabled "caddy"; then
        reload_caddy_safe || true
    fi
    return 0
}

# Установка модуля Caddy (Центральный HTTPS Reverse Proxy & Local PKI)
install_module_caddy() {
    echo "${C_CYN}[*] Установка модуля Caddy (HTTPS Reverse Proxy & Local CA)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add caddy caddy-openrc nss-tools ca-certificates; then
        echo "${C_RED}[X] Не удалось установить пакет caddy из репозитория Alpine!${C_RES}"
        return 1
    fi

    if ! id caddy >/dev/null 2>&1; then
        addgroup -S caddy 2>/dev/null || true
        adduser -S -D -H -h /var/lib/caddy -s /sbin/nologin -G caddy caddy 2>/dev/null || true
    fi

    # Разрешаем непривилегированному пользователю caddy занимать порты 80 и 443
    mkdir -p /etc/sysctl.d
    grep -q "ip_unprivileged_port_start" /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || \
        echo "net.ipv4.ip_unprivileged_port_start = 0" >> /etc/sysctl.d/99-gateway-forward.conf
    sysctl -w net.ipv4.ip_unprivileged_port_start=0 >/dev/null 2>&1 || true

    mkdir -p /etc/caddy "$CADDY_CONFD" "$PKI_PORTAL_DIR" /var/lib/caddy
    chmod 755 /srv /srv/homelab "$PKI_PORTAL_DIR" /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    chown -R caddy:caddy /var/lib/caddy "$PKI_PORTAL_DIR" /etc/caddy 2>/dev/null || true

    cat << 'CADDY_INIT' > /etc/init.d/caddy
#!/sbin/openrc-run
name="caddy"
description="Caddy HTTPS Reverse Proxy & Local PKI"
supervisor="supervise-daemon"
command="/usr/sbin/caddy"
command_args="run --config /etc/caddy/Caddyfile --adapter caddyfile"
command_user="caddy:caddy"
output_log="/var/log/caddy.log"
error_log="/var/log/caddy.log"
rc_ulimit="-n 65535"
export XDG_DATA_HOME="/var/lib/caddy"
export XDG_CONFIG_HOME="/var/lib/caddy"
export HOME="/var/lib/caddy"

depend() {
    need net
}

start_pre() {
    checkpath -f -m 0644 -o caddy:caddy /var/log/caddy.log
    checkpath -d -m 0755 -o caddy:caddy /var/lib/caddy
    chown -R caddy:caddy /var/lib/caddy /etc/caddy 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
}
CADDY_INIT
    chmod +x /etc/init.d/caddy

    sync_caddy_main_config
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
    sync_user_domain_rulesets
    sync_dns_firewall "yes" "keep"

    set_module_state "caddy" "yes"
    if ! reload_caddy_safe; then
        echo "${C_RED}[X] Не удалось запустить службу Caddy!${C_RES}"
        return 1
    fi

    # Ожидание генерации корневого сертификата локального CA Caddy (до 6 сек)
    W_CA=0
    while [ "$W_CA" -lt 6 ]; do
        find_caddy_root_cert && break
        curl -ksS --connect-timeout 1 -m 2 --resolve "${DOM_CA}:443:127.0.0.1" "https://${DOM_CA}/" >/dev/null 2>&1 || true
        sleep 1
        W_CA=$((W_CA + 1))
    done
    build_pki_portal

    echo "${C_GRN}[✓] Caddy и локальный Центр Сертификации успешно запущены!${C_RES}"
    echo "    • Портал установки сертификата: ${C_CYN}http://${DOM_CA}${C_RES} (или http://$(get_current_lan_ip))"
    echo "    • Панель Sing-Box (HTTPS):      ${C_CYN}https://${DOM_ZASHBOARD}${C_RES}"
    echo "    • Панель AdGuard Home (HTTPS):  ${C_CYN}https://${DOM_ADGUARD}${C_RES}"
    return 0
}

remove_module_caddy() {
    echo "Остановка и отключение модуля Caddy..."
    service_ctl caddy stop
    service_ctl caddy disable
    set_module_state "caddy" "no"
    echo "${C_GRN}[✓] Модуль Caddy отключен (сертификаты PKI сохранены в /var/lib/caddy).${C_RES}"
    return 0
}

# Вывод подробной памятки по установке корневого сертификата HTTPS на клиентские устройства
show_https_ca_instructions() {
    build_pki_portal
    CUR_LIP=$(get_current_lan_ip)
    echo ""
    echo "${C_CYN}=======================================================================${C_RES}"
    echo "${C_BLD} 🔒 Установка доверенного корневого сертификата HTTPS (Windows/Linux/Android)${C_RES}"
    echo "${C_CYN}=======================================================================${C_RES}"
    if find_caddy_root_cert; then
        echo " Статус Root CA: ${C_GRN}СГЕНЕРИРОВАН И РАЗДАЕТСЯ НА ПОРТАЛЕ${C_RES}"
    else
        echo " Статус Root CA: ${C_YEL}Ожидает первого запуска Caddy${C_RES}"
    fi
    echo " Веб-портал с кнопками скачивания: ${C_GRN}http://${DOM_CA}${C_RES} (или http://${CUR_LIP}/homelab-root-ca.crt)"
    echo "-----------------------------------------------------------------------"
    echo " ${C_BLD}1. Windows 11 / 10 (PowerShell от имени Администратора — в 1 клик):${C_RES}"
    echo "    ${C_CYN}Invoke-WebRequest -Uri \"http://ca.lan/homelab-root-ca.crt\" -OutFile \"\$env:TEMP\\homelab-ca.crt\"; Import-Certificate -FilePath \"\$env:TEMP\\homelab-ca.crt\" -CertStoreLocation Cert:\\LocalMachine\\Root${C_RES}"
    echo ""
    echo " ${C_BLD}2. Linux (Debian / Ubuntu / Mint / Arch):${C_RES}"
    echo "    ${C_CYN}sudo curl -fsSL http://ca.lan/homelab-root-ca.crt -o /usr/local/share/ca-certificates/homelab-ca.crt && sudo update-ca-certificates${C_RES}"
    echo ""
    echo " ${C_BLD}3. Android:${C_RES}"
    echo "    Откройте в браузере телефона ${C_GRN}http://ca.lan${C_RES}, скачайте файл ${C_BLD}.cer${C_RES},"
    echo "    затем: Настройки -> Безопасность -> Шифрование и учетные данные ->"
    echo "    Установка сертификата -> Сертификат CA -> выберите скачанный файл."
    echo "${C_CYN}=======================================================================${C_RES}"
    return 0
}

# ==============================================================================
# Модуль Samba (SMB2/SMB3) + Сетевое обнаружение Windows 11 (wsdd) и Linux (avahi)
# ==============================================================================

# Настройка демонов сетевого обнаружения: wsdd (Windows 11 Explorer) и avahi (Linux File Managers)
setup_wsdd_and_avahi() {
    LAN_IF=$(get_lan_ifname)
    HN_SHORT=$(hostname -s 2>/dev/null || echo "homelab")
    [ -z "$HN_SHORT" ] && HN_SHORT="homelab"

    # 1. Настройка wsdd (Web Services Dynamic Discovery для Windows 10/11 без SMB1)
    if [ -f /etc/init.d/wsdd ]; then
        cat << WSDD_EOF > /etc/conf.d/wsdd
# Привязка строго к физическому LAN-интерфейсу и IPv4 (в обход singbox-tun)
WSDD_OPTS="-4 -i ${LAN_IF} -w WORKGROUP -n ${HN_SHORT}"
command_args="-4 -i ${LAN_IF} -w WORKGROUP -n ${HN_SHORT}"
WSDD_EOF
        service_ctl wsdd enable
        service_ctl wsdd restart || true
    fi

    # 2. Настройка Avahi mDNS (обнаружение шары в файловых менеджерах Linux: GNOME Files, Dolphin, Thunar)
    if [ -d /etc/avahi ]; then
        mkdir -p /etc/avahi/services
        if [ -f /etc/avahi/avahi-daemon.conf ]; then
            sed -i "s|^#*\s*use-ipv4=.*|use-ipv4=yes|; s|^#*\s*use-ipv6=.*|use-ipv6=no|; s|^#*\s*allow-interfaces=.*|allow-interfaces=${LAN_IF}|" /etc/avahi/avahi-daemon.conf 2>/dev/null || true
            if ! grep -q '^allow-interfaces=' /etc/avahi/avahi-daemon.conf 2>/dev/null; then
                sed -i "/^\[server\]/a allow-interfaces=${LAN_IF}" /etc/avahi/avahi-daemon.conf 2>/dev/null || true
            fi
        fi
        cat << AVAHI_SMB > /etc/avahi/services/smb.service
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=RackMac</txt-record>
  </service>
</service-group>
AVAHI_SMB
        service_ctl dbus enable
        service_ctl dbus start || true
        service_ctl avahi-daemon enable
        service_ctl avahi-daemon restart || true
    fi
    return 0
}

# Применение и строгая верификация пароля пользователя в базе Samba (passdb.tdb) и Unix
apply_and_verify_samba_password() {
    TARGET_SMB_USER="${1:-${SMB_USER:-homelab}}"
    TARGET_SMB_PASS="${2:-${SMB_PASS:-${ADMIN_PASS:-}}}"

    if [ -z "$TARGET_SMB_USER" ] || [ -z "$TARGET_SMB_PASS" ]; then
        echo "${C_RED}[X] Ошибка Samba: Логин или пароль пусты!${C_RES}" >&2
        return 1
    fi

    ensure_media_group_and_users
    mkdir -p /var/lib/samba/private /var/lib/samba /var/cache/samba /var/log/samba /run/samba /etc/samba
    chmod 700 /var/lib/samba/private 2>/dev/null || true
    chmod 755 /var/lib/samba /etc/samba /var/log/samba 2>/dev/null || true

    # Синхронизация системной учетной записи (разблокировка в /etc/shadow и установка пароля)
    if command -v chpasswd >/dev/null 2>&1; then
        printf "%s:%s\n" "$TARGET_SMB_USER" "$TARGET_SMB_PASS" | chpasswd >/dev/null 2>&1 || true
    fi
    if [ -f /etc/shadow ] && grep -q "^${TARGET_SMB_USER}:!" /etc/shadow 2>/dev/null; then
        sed -i "s/^${TARGET_SMB_USER}:!/${TARGET_SMB_USER}:*/" /etc/shadow 2>/dev/null || true
    fi

    if ! command -v smbpasswd >/dev/null 2>&1; then
        return 1
    fi

    # Добавление/обновление пользователя в passdb.tdb и снятие флагов блокировки/отключения
    if ! printf "%s\n%s\n" "$TARGET_SMB_PASS" "$TARGET_SMB_PASS" | smbpasswd -a -s "$TARGET_SMB_USER" >/dev/null 2>&1; then
        if command -v pdbedit >/dev/null 2>&1; then
            printf "%s\n%s\n" "$TARGET_SMB_PASS" "$TARGET_SMB_PASS" | pdbedit -a -u "$TARGET_SMB_USER" -t >/dev/null 2>&1 || return 1
        else
            return 1
        fi
    fi
    smbpasswd -e "$TARGET_SMB_USER" >/dev/null 2>&1 || true

    # Верификация наличия активного пользователя и непустого NT-хэша в базе Samba
    if command -v pdbedit >/dev/null 2>&1; then
        PDB_LINE=$(pdbedit -L -w "$TARGET_SMB_USER" 2>/dev/null | grep -E "^${TARGET_SMB_USER}:" | head -n 1 || true)
        if [ -z "$PDB_LINE" ]; then
            echo "${C_RED}[X] Ошибка: Пользователь ${TARGET_SMB_USER} отсутствует в базе passdb.tdb после smbpasswd!${C_RES}" >&2
            return 1
        fi
        NT_HASH=$(printf "%s" "$PDB_LINE" | awk -F':' '{print $4}')
        ACCT_FLAGS=$(printf "%s" "$PDB_LINE" | awk -F':' '{print $5}')
        if [ -z "$NT_HASH" ] || [ "$NT_HASH" = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" ]; then
            echo "${C_RED}[X] Ошибка: В базе Samba сохранен пустой NT-хэш для ${TARGET_SMB_USER}!${C_RES}" >&2
            return 1
        fi
        case "$ACCT_FLAGS" in
            *D*|*L*)
                echo "${C_RED}[X] Ошибка: Учетная запись Samba ${TARGET_SMB_USER} заблокирована (${ACCT_FLAGS})!${C_RES}" >&2
                return 1
                ;;
        esac
    fi

    # Если smbd уже запущен и установлен smbclient — проверяем реальную SMB2/3 авторизацию
    if command -v smbclient >/dev/null 2>&1 && rc-service samba status >/dev/null 2>&1; then
        PASS_TMP="/tmp/.smb_auth_check.$$"
        umask 077
        printf "username = %s\npassword = %s\n" "$TARGET_SMB_USER" "$TARGET_SMB_PASS" > "$PASS_TMP"
        umask 022
        SMB_CHECK_OUT=$(smbclient -L //127.0.0.1 -A "$PASS_TMP" -m SMB3 2>&1 || true)
        rm -f "$PASS_TMP" 2>/dev/null || true
        if printf "%s" "$SMB_CHECK_OUT" | grep -Eq "NT_STATUS_LOGON_FAILURE|NT_STATUS_ACCOUNT_DISABLED|NT_STATUS_ACCESS_DENIED"; then
            echo "${C_RED}[X] Ошибка проверки входа Samba (smbclient): неверный пароль или доступ запрещен!${C_RES}" >&2
            return 1
        fi
    fi
    return 0
}

# Интерактивная или автоматическая настройка учетных данных Samba
configure_samba_credentials() {
    PROMPT_MODE="${1:-auto}"
    load_gateway_env

    if [ "$PROMPT_MODE" = "interactive" ]; then
        printf "Введите имя пользователя для сетевой папки Samba [Enter = %s]: " "${SMB_USER:-${AGH_USER:-homelab}}"
        read -r IN_SMBU < /dev/tty || true
        IN_SMBU=$(printf "%s" "$IN_SMBU" | tr -d ' \t\r\n')
        [ -n "$IN_SMBU" ] && SMB_USER="$IN_SMBU"

        if [ -n "${SMB_PASS:-}" ]; then
            printf "Введите пароль для Samba [Enter = оставить сохраненный пароль Samba / 'gw' = единый пароль шлюза]: "
        else
            printf "Введите пароль для Samba [Enter = использовать единый пароль шлюза]: "
        fi
        read -r IN_SMBP < /dev/tty || true
        IN_SMBP=$(printf "%s" "$IN_SMBP" | tr -d '\r\n')
        if [ "$IN_SMBP" = "gw" ] || [ "$IN_SMBP" = "GW" ]; then
            SMB_PASS="${ADMIN_PASS:-admin}"
        elif [ -n "$IN_SMBP" ]; then
            SMB_PASS="$IN_SMBP"
        elif [ -z "${SMB_PASS:-}" ]; then
            SMB_PASS="${ADMIN_PASS:-admin}"
        fi
    else
        [ -z "${SMB_USER:-}" ] && SMB_USER="${AGH_USER:-homelab}"
        [ -z "${SMB_PASS:-}" ] && SMB_PASS="${ADMIN_PASS:-admin}"
    fi

    # Сначала сохраняем новые учетные данные на диск, и только затем создаем/обновляем системного пользователя
    save_homelab_env
    ensure_media_group_and_users
    return 0
}

# Генерация и проверка конфигурации /etc/samba/smb.conf (совместимость с Windows 11 24H2+ и Linux)
write_samba_config() {
    load_gateway_env
    LAN_IF=$(get_lan_ifname)
    HN_VAL=$(hostname -s 2>/dev/null || echo "HOMELAB")
    [ -z "$HN_VAL" ] && HN_VAL="HOMELAB"

    mkdir -p /etc/samba /var/log/samba /var/lib/samba/private /var/cache/samba /run/samba
    chmod 700 /var/lib/samba/private 2>/dev/null || true
    cat << SMB_EOF > /etc/samba/smb.conf.tmp.$$
[global]
   workgroup = WORKGROUP
   netbios name = ${HN_VAL}
   server string = Alpine Homelab Storage
   server role = standalone server
   interfaces = lo ${LAN_IF}
   bind interfaces only = yes
   hosts allow = 127. 10. 172.16. 172.17. 172.18. 172.19. 172.20. 172.21. 172.22. 172.23. 172.24. 172.25. 172.26. 172.27. 172.28. 172.29. 172.30. 172.31. 192.168. 100.64.
   security = user
   passdb backend = tdbsam:/var/lib/samba/private/passdb.tdb
   map to guest = Never
   ntlm auth = ntlmv2-only
   server min protocol = SMB2_10
   server max protocol = SMB3
   smb encrypt = desired
   server signing = auto
   disable netbios = yes
   smb ports = 445
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   use sendfile = yes
   aio read size = 16384
   aio write size = 16384
   unix charset = UTF-8
   dos charset = CP866

[storage]
   comment = Homelab Unified Storage (Music, Videos, Downloads)
   path = ${STORAGE_ROOT}
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = ${SMB_USER} @${MEDIA_GROUP}
   write list = ${SMB_USER} @${MEDIA_GROUP}
   force user = ${SMB_USER}
   force group = ${MEDIA_GROUP}
   create mask = 0664
   force create mode = 0664
   directory mask = 2775
   force directory mode = 2775
   inherit permissions = yes
   inherit acls = yes
   map archive = no
   store dos attributes = yes
SMB_EOF

    if command -v testparm >/dev/null 2>&1; then
        if ! testparm -s /etc/samba/smb.conf.tmp.$$ >/dev/null 2>&1; then
            echo "${C_RED}[X] Ошибка валидации синтаксиса smb.conf через testparm!${C_RES}" >&2
            rm -f /etc/samba/smb.conf.tmp.$$ 2>/dev/null || true
            return 1
        fi
    fi
    chmod 644 /etc/samba/smb.conf.tmp.$$ 2>/dev/null || true
    mv -f /etc/samba/smb.conf.tmp.$$ /etc/samba/smb.conf
    return 0
}

# Установка и настройка модуля Samba + WSDD + Avahi
install_module_samba() {
    PROMPT_CRED="${1:-auto}"
    echo "${C_CYN}[*] Установка модуля Samba (SMB2/SMB3) + WSDD (Windows 11) + Avahi (Linux)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add samba-server samba-common-tools samba-client wsdd wsdd-openrc avahi dbus acl shadow; then
        if ! apk add samba-server samba-common-tools wsdd wsdd-openrc avahi dbus acl; then
            echo "${C_RED}[X] Не удалось установить пакеты samba-server / wsdd!${C_RES}"
            return 1
        fi
    fi

    init_homelab_storage
    configure_samba_credentials "$PROMPT_CRED"
    repair_storage_permissions

    if ! write_samba_config; then
        return 1
    fi

    # Отключаем устаревший nmbd (SMB1 NetBIOS), оставляем только smbd
    if [ -f /etc/conf.d/samba ]; then
        sed -i 's|^daemon_list=.*|daemon_list="smbd"|' /etc/conf.d/samba 2>/dev/null || true
    fi

    if ! apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS"; then
        echo "${C_RED}[X] Не удалось применить и верифицировать пароль Samba для пользователя ${SMB_USER}!${C_RES}"
        return 1
    fi

    service_ctl samba enable
    if ! service_ctl samba restart; then
        echo "${C_RED}[X] Служба Samba (smbd) не смогла запуститься! Проверьте /var/log/samba/log.smbd.${C_RES}"
        return 1
    fi

    # Повторная проверка через живой демон smbd (если установлен smbclient)
    apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS" || return 1

    setup_wsdd_and_avahi
    sync_dns_firewall "yes" "keep"
    set_module_state "samba" "yes"

    HN_VAL=$(hostname -s 2>/dev/null || echo "HOMELAB")
    CUR_LIP=$(get_current_lan_ip)
    echo "${C_GRN}[✓] Сетевое хранилище Samba успешно запущено, пароль проверен в passdb.tdb!${C_RES}"
    echo "    • Windows 11 Проводник: ${C_CYN}\\\\${HN_VAL}\\storage${C_RES} или ${C_CYN}\\\\${CUR_LIP}\\storage${C_RES}"
    echo "    • Файловые менеджеры Linux: ${C_CYN}smb://${CUR_LIP}/storage${C_RES}"
    echo "    • Логин: ${C_BLD}${SMB_USER}${C_RES} (пароль синхронизирован и проверен)"
    return 0
}

remove_module_samba() {
    echo "Остановка и отключение Samba, WSDD и Avahi..."
    service_ctl samba stop
    service_ctl samba disable
    service_ctl wsdd stop
    service_ctl wsdd disable
    service_ctl avahi-daemon stop
    service_ctl avahi-daemon disable
    set_module_state "samba" "no"
    echo "${C_GRN}[✓] Модуль Samba отключен (все файлы в ${STORAGE_ROOT} сохранены).${C_RES}"
    return 0
}
# ==================== [ КОНЕЦ ЧАСТИ 4 ИЗ 6 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 5 ИЗ 6 ] ====================
# ==============================================================================
# Прикладные модули Homelab (Vaultwarden, Forgejo, Server-Code, Navidrome,
# Jellyfin, yt-dlp Web UI, qBittorrent-nox), Архитектура Медиатеки,
# Единый модуль тестирования прав доступа и Резервное копирование
# ==============================================================================

# 1. Модуль Vaultwarden (Локальный менеджер паролей Bitwarden)
# Поиск каталога Web Vault и проверка его целостности (index.html + .wasm)
detect_vaultwarden_web_dir() {
    for WV_CAND in \
        "/usr/share/webapps/vaultwarden-web" \
        "/usr/share/vaultwarden/web-vault" \
        "/var/lib/vaultwarden/web-vault"; do
        if [ -f "${WV_CAND}/index.html" ]; then
            printf "%s" "${WV_CAND%/}/"
            return 0
        fi
    done
    printf "/usr/share/webapps/vaultwarden-web/"
    return 1
}

# Очистка файлов Web Vault от любых старых JS/WASM sed-патчей, .orig-файлов и симлинков
clean_vaultwarden_web_vault() {
    WV_DIR_CLEAN=$(detect_vaultwarden_web_dir || true)
    WV_DIR_CLEAN="${WV_DIR_CLEAN%/}"
    [ -d "$WV_DIR_CLEAN" ] || return 0

    NEEDS_REINSTALL="no"
    if [ -d "${WV_DIR_CLEAN}/app" ]; then
        if find "${WV_DIR_CLEAN}/app" -maxdepth 1 -type l 2>/dev/null | grep -q .; then
            find "${WV_DIR_CLEAN}/app" -maxdepth 1 -type l -delete 2>/dev/null || true
            NEEDS_REINSTALL="yes"
        fi
    fi

    for ORIG_F in "${WV_DIR_CLEAN}"/*.orig "${WV_DIR_CLEAN}"/*.bak "${WV_DIR_CLEAN}"/app/*.orig "${WV_DIR_CLEAN}"/app/*.bak; do
        [ -f "$ORIG_F" ] || continue
        BASE_F="${ORIG_F%.orig}"
        BASE_F="${BASE_F%.bak}"
        mv -f "$ORIG_F" "$BASE_F" 2>/dev/null || rm -f "$ORIG_F" 2>/dev/null || true
        NEEDS_REINSTALL="yes"
    done

    if [ -f "${WV_DIR_CLEAN}/index.html" ] && grep -q "vw1375s" "${WV_DIR_CLEAN}/index.html" 2>/dev/null; then
        NEEDS_REINSTALL="yes"
    fi

    if [ "$NEEDS_REINSTALL" = "yes" ]; then
        apk fix --reinstall vaultwarden-web-vault >/dev/null 2>&1 || true
    fi
    chmod -R a+rX "$WV_DIR_CLEAN" 2>/dev/null || true
    return 0
}

# Синхронизация чистой эталонной конфигурации Vaultwarden (/etc/conf.d/vaultwarden + /var/lib/vaultwarden/.env)
sync_vaultwarden_config() {
    load_gateway_env
    ensure_media_group_and_users
    if [ -f /etc/shadow ] && grep -q "^vaultwarden:!" /etc/shadow 2>/dev/null; then
        sed -i 's/^vaultwarden:!/vaultwarden:*/' /etc/shadow 2>/dev/null || true
    fi

    mkdir -p /var/lib/vaultwarden/attachments /var/lib/vaultwarden/sends /var/lib/vaultwarden/icon_cache /var/lib/vaultwarden/tmp
    WEB_VAULT_DIR=$(detect_vaultwarden_web_dir || true)

    ESC_VW_ADM=$(escape_single_quotes "${ADMIN_PASS:-admin}")
    umask 077
    cat << VW_EOF > /etc/conf.d/vaultwarden
# Конфигурация Vaultwarden (Alpine Homelab Edition — Clean Setup)
export DATA_FOLDER="/var/lib/vaultwarden"
export DATABASE_URL="sqlite:///var/lib/vaultwarden/db.sqlite3"
export ENABLE_DB_WAL="true"
export ROCKET_ADDRESS="127.0.0.1"
export ROCKET_PORT="${PORT_VAULTWARDEN}"
export DOMAIN="https://${DOM_VAULTWARDEN}"
export WEB_VAULT_ENABLED="true"
export WEB_VAULT_FOLDER="${WEB_VAULT_DIR}"
export SIGNUPS_ALLOWED="true"
export WEBSOCKET_ENABLED="true"
export IP_HEADER="X-Real-IP"
export EXTENDED_LOGGING="true"
export LOG_LEVEL="info"
export LOG_FILE="/var/log/vaultwarden.log"
export ADMIN_TOKEN='${ESC_VW_ADM}'
VW_EOF
    chown root:vaultwarden /etc/conf.d/vaultwarden 2>/dev/null || true
    chmod 640 /etc/conf.d/vaultwarden 2>/dev/null || true

    # Дублируем конфигурацию без export в /var/lib/vaultwarden/.env для нативного dotenvy парсера Vaultwarden
    sed 's/^export //' /etc/conf.d/vaultwarden > /var/lib/vaultwarden/.env 2>/dev/null || true
    chown vaultwarden:vaultwarden /var/lib/vaultwarden/.env 2>/dev/null || true
    chmod 600 /var/lib/vaultwarden/.env 2>/dev/null || true
    umask 022

    # Если ранее через /admin был создан config.json, синхронизируем критические параметры (web_vault_enabled, domain, admin_token)
    if [ -f /var/lib/vaultwarden/config.json ] && command -v jq >/dev/null 2>&1; then
        jq --arg dom "https://${DOM_VAULTWARDEN}" --arg adm "${ADMIN_PASS:-admin}" \
           '.domain = $dom | .web_vault_enabled = true | .admin_token = $adm' \
           /var/lib/vaultwarden/config.json > /var/lib/vaultwarden/config.json.tmp 2>/dev/null && \
           mv -f /var/lib/vaultwarden/config.json.tmp /var/lib/vaultwarden/config.json 2>/dev/null || true
        chown vaultwarden:vaultwarden /var/lib/vaultwarden/config.json 2>/dev/null || true
        chmod 600 /var/lib/vaultwarden/config.json 2>/dev/null || true
    fi

    touch /var/log/vaultwarden.log 2>/dev/null || true
    chown vaultwarden:vaultwarden /var/log/vaultwarden.log 2>/dev/null || true
    chmod 640 /var/log/vaultwarden.log 2>/dev/null || true
    chown -R vaultwarden:vaultwarden /var/lib/vaultwarden 2>/dev/null || true
    chmod 750 /var/lib/vaultwarden 2>/dev/null || true

    # Очищаем Web Vault от любых прежних костылей и проверяем права чтения
    clean_vaultwarden_web_vault

    # Прописываем домен vaultwarden.lan и ca.lan в локальный /etc/hosts сервера
    CUR_LIP_VW=$(get_current_lan_ip)
    if [ -n "$CUR_LIP_VW" ] && ! grep -qE "^${CUR_LIP_VW}[[:space:]].*${DOM_VAULTWARDEN}" /etc/hosts 2>/dev/null; then
        sed -i "/${DOM_VAULTWARDEN}/d" /etc/hosts 2>/dev/null || true
        printf "%s\t%s %s\n" "$CUR_LIP_VW" "$DOM_VAULTWARDEN" "$DOM_CA" >> /etc/hosts 2>/dev/null || true
    fi
    return 0
}

# Глубокая диагностика работы Vaultwarden (DNS, чистый Web Vault, WASM, API, SQLite, Caddy HTTPS, WebSockets)
verify_vaultwarden_stack() {
    echo "${C_CYN}=== Глубокая диагностика Vaultwarden (DNS + API + Web Vault + WASM + Caddy HTTPS) ===${C_RES}"
    VW_ERR=0
    CUR_LIP_VW=$(get_current_lan_ip)

    # 1. Проверка пакетов и чистоты файлов Web Vault (без sed-костылей)
    WEB_VAULT_DIR=$(detect_vaultwarden_web_dir || true)
    if [ -f "${WEB_VAULT_DIR%/}/index.html" ]; then
        WASM_CNT=$(find "${WEB_VAULT_DIR%/}" -maxdepth 2 -name "*.wasm" 2>/dev/null | wc -l | tr -d ' \t\r\n')
        if grep -q "vw1375s" "${WEB_VAULT_DIR%/}/index.html" 2>/dev/null || ls "${WEB_VAULT_DIR%/}"/*.orig >/dev/null 2>&1; then
            echo " ${C_YEL}[WARN]${C_RES} В ${WEB_VAULT_DIR} обнаружены следы старых патчей — выполняется очистка..."
            clean_vaultwarden_web_vault
        fi
        echo " ${C_GRN}[OK]${C_RES} Каталог Web Vault: ${WEB_VAULT_DIR} (чистый, index.html найден, модулей WASM: ${WASM_CNT})"
    else
        echo " ${C_RED}[FAIL]${C_RES} Файл ${WEB_VAULT_DIR%/}/index.html не найден! Пакет vaultwarden-web-vault не установлен или поврежден."
        VW_ERR=$((VW_ERR + 1))
    fi

    # 2. Проверка владельца, прав и SQLite БД в /var/lib/vaultwarden
    if [ -d /var/lib/vaultwarden ]; then
        VW_PERM=$(stat -c "%a %U:%G" /var/lib/vaultwarden 2>/dev/null || echo "н/д")
        if su -s /bin/sh vaultwarden -c "test -r /var/lib/vaultwarden && test -w /var/lib/vaultwarden" 2>/dev/null; then
            echo " ${C_GRN}[OK]${C_RES} Директория данных /var/lib/vaultwarden (${VW_PERM}): чтение/запись от vaultwarden доступны"
        else
            echo " ${C_RED}[FAIL]${C_RES} Пользователь vaultwarden не имеет прав записи в /var/lib/vaultwarden (${VW_PERM})!"
            VW_ERR=$((VW_ERR + 1))
        fi
        if [ -f /var/lib/vaultwarden/db.sqlite3 ] && command -v sqlite3 >/dev/null 2>&1; then
            DB_CHK=$(su -s /bin/sh vaultwarden -c "sqlite3 /var/lib/vaultwarden/db.sqlite3 'PRAGMA integrity_check;'" 2>/dev/null | head -n 1 || echo "err")
            if [ "$DB_CHK" = "ok" ]; then
                echo " ${C_GRN}[OK]${C_RES} База данных SQLite (/var/lib/vaultwarden/db.sqlite3): PRAGMA integrity_check = ok"
            else
                echo " ${C_RED}[FAIL]${C_RES} Ошибка проверки базы SQLite Vaultwarden: ${DB_CHK}"
                VW_ERR=$((VW_ERR + 1))
            fi
        fi
    fi

    # 3. Проверка локального HTTP и API (127.0.0.1:8222)
    ALIVE_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 -m 4 "http://127.0.0.1:${PORT_VAULTWARDEN}/alive" 2>/dev/null || echo "000")
    CFG_JSON=$(curl -fsS --connect-timeout 2 -m 4 "http://127.0.0.1:${PORT_VAULTWARDEN}/api/config" 2>/dev/null || true)
    INDEX_HTML=$(curl -fsS --connect-timeout 2 -m 4 "http://127.0.0.1:${PORT_VAULTWARDEN}/" 2>/dev/null || true)

    if [ "$ALIVE_CODE" = "200" ] && [ -n "$CFG_JSON" ]; then
        VW_VER=$(printf "%s" "$CFG_JSON" | jq -r '.version // "ok"' 2>/dev/null || echo "ok")
        echo " ${C_GRN}[OK]${C_RES} Локальный API (127.0.0.1:${PORT_VAULTWARDEN}/alive & /api/config): HTTP 200 (версия: ${VW_VER})"
    else
        echo " ${C_RED}[FAIL]${C_RES} Локальный API Vaultwarden (127.0.0.1:${PORT_VAULTWARDEN}) не отвечает (HTTP ${ALIVE_CODE})!"
        VW_ERR=$((VW_ERR + 1))
    fi

    if printf "%s" "$INDEX_HTML" | grep -qi "<html"; then
        echo " ${C_GRN}[OK]${C_RES} Отдача интерфейса Web Vault (GET /): HTML-приложение корректно загружается"
    else
        echo " ${C_RED}[FAIL]${C_RES} Интерфейс Web Vault (GET /) не отдает HTML!"
        VW_ERR=$((VW_ERR + 1))
    fi

    # 4. Проверка HTTPS проксирования через Caddy, доверия локальному CA и отдачи WASM крипто-модуля
    HTTPS_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 -m 5 \
        --cacert "${PKI_PORTAL_DIR}/homelab-root-ca.crt" \
        --resolve "${DOM_VAULTWARDEN}:443:127.0.0.1" \
        "https://${DOM_VAULTWARDEN}/api/config" 2>/dev/null || echo "000")
    if [ "$HTTPS_CODE" = "200" ]; then
        echo " ${C_GRN}[OK]${C_RES} Caddy HTTPS Proxy (https://${DOM_VAULTWARDEN}/api/config + Root CA): HTTP 200 OK"
    else
        HTTPS_INSEC=$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 3 -m 5 \
            --resolve "${DOM_VAULTWARDEN}:443:127.0.0.1" \
            "https://${DOM_VAULTWARDEN}/api/config" 2>/dev/null || echo "000")
        echo " ${C_YEL}[WARN]${C_RES} Caddy HTTPS Proxy: с проверкой CA код ${HTTPS_CODE}, без проверки CA код ${HTTPS_INSEC}"
        [ "$HTTPS_INSEC" != "200" ] && VW_ERR=$((VW_ERR + 1))
    fi

    WASM_REL=$(cd "${WEB_VAULT_DIR%/}" 2>/dev/null && find . -maxdepth 2 -name "*.wasm" | head -n 1 | sed 's|^\./||' || true)
    if [ -n "$WASM_REL" ]; then
        WASM_ST=$(curl -ksS -o /dev/null -w '%{http_code} %{content_type}' --connect-timeout 3 -m 5 \
            --resolve "${DOM_VAULTWARDEN}:443:127.0.0.1" \
            "https://${DOM_VAULTWARDEN}/${WASM_REL}" 2>/dev/null || echo "000 none")
        if printf "%s" "$WASM_ST" | grep -q "^200 "; then
            echo " ${C_GRN}[OK]${C_RES} Отдача крипто-ядра WASM (/${WASM_REL}) через Caddy: ${WASM_ST}"
        else
            echo " ${C_RED}[FAIL]${C_RES} Ошибка отдачи WASM (/${WASM_REL}) через Caddy: ${WASM_ST}"
            VW_ERR=$((VW_ERR + 1))
        fi
    fi

    # 5. Проверка WebSocket эндпоинта (/notifications/hub)
    WS_CODE=$(curl -ksS -o /dev/null -w '%{http_code}' --connect-timeout 2 -m 4 \
        --resolve "${DOM_VAULTWARDEN}:443:127.0.0.1" \
        -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Sec-WebSocket-Version: 13" \
        "https://${DOM_VAULTWARDEN}/notifications/anonymous-hub?token=diagnostics" 2>/dev/null || echo "000")
    if [ "$WS_CODE" != "000" ] && [ "$WS_CODE" != "502" ]; then
        echo " ${C_GRN}[OK]${C_RES} Проксирование WebSocket (/notifications/*): доступно (HTTP ${WS_CODE})"
    else
        echo " ${C_RED}[FAIL]${C_RES} Проксирование WebSocket (/notifications/*) недоступно (HTTP ${WS_CODE})!"
        VW_ERR=$((VW_ERR + 1))
    fi

    echo " ${C_CYN}[i] Важно для браузера:${C_RES} Установите корневой сертификат с ${C_GRN}http://${DOM_CA}${C_RES} (или http://${CUR_LIP_VW})"
    echo "     и откройте ${C_GRN}https://${DOM_VAULTWARDEN}${C_RES} (нажмите Ctrl+Shift+R для очистки старого кэша)."
    return "$VW_ERR"
}

install_module_vaultwarden() {
    echo "${C_CYN}[*] Установка модуля Vaultwarden (Bitwarden Server + чистый Web Vault)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add vaultwarden vaultwarden-openrc vaultwarden-web-vault sqlite; then
        echo "${C_RED}[X] Не удалось установить пакеты vaultwarden и vaultwarden-web-vault!${C_RES}"
        return 1
    fi

    if ! id vaultwarden >/dev/null 2>&1; then
        addgroup -S vaultwarden 2>/dev/null || true
        adduser -S -D -H -h /var/lib/vaultwarden -s /sbin/nologin -G vaultwarden vaultwarden 2>/dev/null || true
    fi

    sync_vaultwarden_config

    # Создаем надежный OpenRC init-скрипт, гарантирующий загрузку /etc/conf.d/vaultwarden и рабочую директорию
    cat << 'VW_INIT_EOF' > /etc/init.d/vaultwarden
#!/sbin/openrc-run
name="vaultwarden"
description="Vaultwarden Bitwarden Server (Alpine Homelab Edition)"
supervisor="supervise-daemon"
command="/usr/bin/vaultwarden"
command_user="vaultwarden:vaultwarden"
directory="/var/lib/vaultwarden"
output_log="/var/log/vaultwarden.log"
error_log="/var/log/vaultwarden.log"
rc_ulimit="-n 65535"
respawn_delay=3
respawn_max=10

if [ -f /etc/conf.d/vaultwarden ]; then
    . /etc/conf.d/vaultwarden
fi

depend() {
    need net
}

start_pre() {
    checkpath -d -m 0750 -o vaultwarden:vaultwarden /var/lib/vaultwarden
    checkpath -f -m 0640 -o vaultwarden:vaultwarden /var/log/vaultwarden.log
}
VW_INIT_EOF
    chmod +x /etc/init.d/vaultwarden

    service_ctl vaultwarden enable
    if ! service_ctl vaultwarden restart; then
        echo "${C_RED}[X] Служба Vaultwarden не смогла запуститься! Проверьте /var/log/vaultwarden.log.${C_RES}"
        return 1
    fi

    # Ожидание готовности локального порта Rocket (до 8 сек)
    W_VW=0
    while [ "$W_VW" -lt 8 ]; do
        if curl -fsS --connect-timeout 1 -m 2 "http://127.0.0.1:${PORT_VAULTWARDEN}/alive" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        W_VW=$((W_VW + 1))
    done

    register_caddy_site "vaultwarden" "$DOM_VAULTWARDEN" "$PORT_VAULTWARDEN" "no"
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
    set_module_state "vaultwarden" "yes"

    verify_vaultwarden_stack || true
    echo "${C_GRN}[✓] Vaultwarden запущен: https://${DOM_VAULTWARDEN} (Админ-панель: https://${DOM_VAULTWARDEN}/admin)${C_RES}"
    return 0
}

remove_module_vaultwarden() {
    service_ctl vaultwarden stop
    service_ctl vaultwarden disable
    remove_caddy_site "vaultwarden"
    set_module_state "vaultwarden" "no"
    echo "${C_GRN}[✓] Модуль Vaultwarden отключен (база паролей в /var/lib/vaultwarden сохранена).${C_RES}"
    return 0
}

# 2. Модуль Forgejo (Локальный Git-сервер на порту 3001)
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
install_module_navidrome() {
    echo "${C_CYN}[*] Установка модуля Navidrome (Music Streaming Server — Subsonic API)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add navidrome navidrome-openrc ffmpeg; then
        echo "${C_RED}[X] Не удалось установить пакет navidrome!${C_RES}"
        return 1
    fi

    if ! id navidrome >/dev/null 2>&1; then
        addgroup -S navidrome 2>/dev/null || true
        adduser -S -D -H -h /var/lib/navidrome -s /sbin/nologin -G navidrome navidrome 2>/dev/null || true
    fi

    init_homelab_storage
    addgroup navidrome "$MEDIA_GROUP" 2>/dev/null || true
    repair_storage_permissions

    mkdir -p /etc/navidrome /var/lib/navidrome
    cat << ND_EOF > /etc/navidrome/navidrome.toml
MusicFolder = "${STORAGE_MUSIC}"
DataFolder = "/var/lib/navidrome"
Address = "127.0.0.1"
Port = ${PORT_NAVIDROME}
DefaultLanguage = "ru"
ScanSchedule = "@every 15m"
EnableTranscodingConfig = true
ND_EOF
    cp -f /etc/navidrome/navidrome.toml /var/lib/navidrome/navidrome.toml 2>/dev/null || true
    chown -R navidrome:"$MEDIA_GROUP" /var/lib/navidrome /etc/navidrome 2>/dev/null || true
    chmod 750 /var/lib/navidrome /etc/navidrome 2>/dev/null || true
    chmod 640 /etc/navidrome/navidrome.toml /var/lib/navidrome/navidrome.toml 2>/dev/null || true

    if [ -f /etc/conf.d/navidrome ]; then
        grep -q 'command_user=' /etc/conf.d/navidrome 2>/dev/null && \
            sed -i "s|^command_user=.*|command_user=\"navidrome:${MEDIA_GROUP}\"|" /etc/conf.d/navidrome 2>/dev/null || \
            echo "command_user=\"navidrome:${MEDIA_GROUP}\"" >> /etc/conf.d/navidrome
    fi

    service_ctl navidrome enable
    if ! service_ctl navidrome restart; then
        echo "${C_RED}[X] Служба Navidrome не смогла запуститься!${C_RES}"
        return 1
    fi
    register_caddy_site "navidrome" "$DOM_NAVIDROME" "$PORT_NAVIDROME" "no"
    set_module_state "navidrome" "yes"

    echo "${C_GRN}[✓] Navidrome запущен: https://${DOM_NAVIDROME} (Библиотека: ${STORAGE_MUSIC}, совместим с Jellyfin)${C_RES}"
    return 0
}

remove_module_navidrome() {
    service_ctl navidrome stop
    service_ctl navidrome disable
    remove_caddy_site "navidrome"
    set_module_state "navidrome" "no"
    echo "${C_GRN}[✓] Модуль Navidrome отключен (музыка в ${STORAGE_MUSIC} сохранена).${C_RES}"
    return 0
}

# 5. Модуль Jellyfin (Единая медиаплатформа для Видео и Музыки: Movies, Series и Music + FFmpeg + VAAPI)
install_module_jellyfin() {
    echo "${C_CYN}[*] Установка модуля Jellyfin (Unified Media Server: Movies + Series + Music + FFmpeg)...${C_RES}"
    umask 022
    if [ "${TOTAL_RAM_MB:-512}" -lt 1000 ]; then
        echo "${C_YEL}[!] Внимание: Для Jellyfin рекомендуется минимум 1.5–2 ГБ ОЗУ.${C_RES}"
    fi
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add jellyfin jellyfin-openrc jellyfin-web jellyfin-ffmpeg; then
        if ! apk add jellyfin jellyfin-openrc jellyfin-web ffmpeg; then
            echo "${C_RED}[X] Не удалось установить пакеты jellyfin!${C_RES}"
            return 1
        fi
    fi

    if ! id jellyfin >/dev/null 2>&1; then
        addgroup -S jellyfin 2>/dev/null || true
        adduser -S -D -H -h /var/lib/jellyfin -s /sbin/nologin -G jellyfin jellyfin 2>/dev/null || true
    fi

    init_homelab_storage
    for GRP_J in "$MEDIA_GROUP" video render; do
        addgroup jellyfin "$GRP_J" 2>/dev/null || true
    done
    repair_storage_permissions

    mkdir -p /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin
    chown -R jellyfin:"$MEDIA_GROUP" /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin 2>/dev/null || true
    chmod 750 /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin 2>/dev/null || true

    # Удаление флага --nowebclient в Alpine /etc/conf.d/jellyfin для активации пакета jellyfin-web
    if [ -f /etc/conf.d/jellyfin ]; then
        sed -i 's/--nowebclient//g' /etc/conf.d/jellyfin 2>/dev/null || true
        grep -q 'rc_oom_score_adj=' /etc/conf.d/jellyfin 2>/dev/null || echo 'rc_oom_score_adj="200"' >> /etc/conf.d/jellyfin
    fi

    service_ctl jellyfin enable
    if ! service_ctl jellyfin restart; then
        echo "${C_RED}[X] Служба Jellyfin не смогла запуститься!${C_RES}"
        return 1
    fi
    W_JF=0
    while [ "$W_JF" -lt 12 ]; do
        curl -sS -o /dev/null --connect-timeout 1 -m 2 "http://127.0.0.1:${PORT_JELLYFIN}" 2>/dev/null && break
        sleep 1
        W_JF=$((W_JF + 1))
    done
    register_caddy_site "jellyfin" "$DOM_JELLYFIN" "$PORT_JELLYFIN" "no"
    set_module_state "jellyfin" "yes"

    echo "${C_GRN}[✓] Jellyfin запущен: https://${DOM_JELLYFIN} (Единая медиаплатформа Видео + Музыка)${C_RES}"
    echo "    • Библиотека Фильмов (Movies):   ${C_CYN}${STORAGE_VIDEOS_MOVIES}${C_RES} (или ${STORAGE_VIDEOS})"
    echo "    • Библиотека Сериалов (Shows):   ${C_CYN}${STORAGE_VIDEOS_SERIES}${C_RES}"
    echo "    • Библиотека Музыки (Music):     ${C_CYN}${STORAGE_MUSIC}${C_RES} (полный доступ через группу ${MEDIA_GROUP} + ACL)"
    return 0
}

remove_module_jellyfin() {
    service_ctl jellyfin stop
    service_ctl jellyfin disable
    remove_caddy_site "jellyfin"
    set_module_state "jellyfin" "no"
    echo "${C_GRN}[✓] Модуль Jellyfin отключен (медиафайлы в ${STORAGE_VIDEOS} и ${STORAGE_MUSIC} сохранены).${C_RES}"
    return 0
}

# Сравнительный обзор и управление архитектурой медиатеки (Единый Jellyfin для видео+музыки vs связка с Navidrome)
show_media_architecture_advisor() {
    load_gateway_env
    init_homelab_storage
    JF_ST=$(is_module_enabled "jellyfin" && echo "${C_GRN}УСТАНОВЛЕН${C_RES}" || echo "${C_DIM}НЕ АКТИВЕН${C_RES}")
    ND_ST=$(is_module_enabled "navidrome" && echo "${C_GRN}УСТАНОВЛЕН (доп. модуль)${C_RES}" || echo "${C_DIM}ОТКЛЮЧЕН${C_RES}")

    echo ""
    echo "${C_CYN}=======================================================================${C_RES}"
    echo "${C_BLD} 🎬🎵 Архитектура медиасервера: Интеграция музыки и видео в Jellyfin${C_RES}"
    echo "${C_CYN}=======================================================================${C_RES}"
    echo " • Статус Jellyfin:  ${JF_ST} | Режим единой медиаплатформы: ${C_GRN}${JELLYFIN_UNIFIED_MEDIA:-yes}${C_RES}"
    echo " • Статус Navidrome: ${ND_ST}"
    echo "-----------------------------------------------------------------------"
    echo " ${C_BLD}Рекомендуемая структура библиотек в Jellyfin (https://${DOM_JELLYFIN}):${C_RES}"
    echo "  1. Библиотека «Movies» (Фильмы)   -> каталог: ${C_CYN}${STORAGE_VIDEOS_MOVIES}${C_RES} (и ${STORAGE_VIDEOS})"
    echo "  2. Библиотека «Shows»  (Сериалы)  -> каталог: ${C_CYN}${STORAGE_VIDEOS_SERIES}${C_RES}"
    echo "  3. Библиотека «Music»  (Музыка)   -> каталог: ${C_CYN}${STORAGE_MUSIC}${C_RES}"
    echo "-----------------------------------------------------------------------"
    echo " ${C_BLD}Сравнение возможностей (на ноябрь 2026 г.):${C_RES}"
    echo "  • ${C_GRN}Jellyfin как единая платформа (Видео + Музыка):${C_RES}"
    echo "    [+] Один сервер и единый веб-интерфейс для фильмов, сериалов и музыки."
    echo "    [+] Отличное мобильное приложение для музыки: Finamp (Android/iOS, офлайн-кэш, gapless)"
    echo "        и Symfonium, плюс штатные клиенты Jellyfin на Smart TV / ПК."
    echo "    [+] Аппаратное/программное транскодирование через jellyfin-ffmpeg (FLAC/ALAC/Opus/MP3)."
    echo "    [-] Не поддерживает протокол Subsonic API из коробки."
    echo "  • ${C_CYN}Navidrome как дополнительный музыкальный модуль:${C_RES}"
    echo "    [+] Ультра-легкий (~40-50 МБ ОЗУ), мгновенная индексация больших аудиотек."
    echo "    [+] Полная поддержка Subsonic / OpenSubsonic API (DSub, Ultrasonic, Amperfy, Supersonic)."
    echo "    [+] Оба сервиса (Jellyfin и Navidrome) могут работать ОДНОВРЕМЕННО поверх"
    echo "        единого каталога ${STORAGE_MUSIC} без конфликтов!"
    echo "-----------------------------------------------------------------------"
    echo " Выберите режим работы медиастэка:"
    echo "  1) ${C_GRN}Единая платформа Jellyfin (Видео + Музыка)${C_RES} — установить/обновить Jellyfin и выдать права на ${STORAGE_MUSIC}"
    echo "  2) ${C_CYN}Гибридный режим (Jellyfin + Navidrome одновременно)${C_RES} — оба сервиса читают ${STORAGE_MUSIC}"
    echo "  3) Отключить Navidrome (оставить только Jellyfin для экономии ОЗУ, сохранив все файлы)"
    echo "  0) Назад"
    printf "Выбор [0-3]: "
    read -r MA_ACT < /dev/tty || true
    case "$MA_ACT" in
        1)
            JELLYFIN_UNIFIED_MEDIA="yes"
            save_homelab_env
            install_module_jellyfin || true
            repair_storage_permissions
            echo "${C_GRN}[✓] Jellyfin настроен как единая медиаплатформа с полным доступом к ${STORAGE_VIDEOS} и ${STORAGE_MUSIC}!${C_RES}"
            ;;
        2)
            JELLYFIN_UNIFIED_MEDIA="yes"
            save_homelab_env
            install_module_jellyfin || true
            install_module_navidrome || true
            repair_storage_permissions
            echo "${C_GRN}[✓] Активирован гибридный режим: Jellyfin и Navidrome работают параллельно над единой медиатекой!${C_RES}"
            ;;
        3)
            JELLYFIN_UNIFIED_MEDIA="yes"
            save_homelab_env
            is_module_enabled "navidrome" && remove_module_navidrome || true
            is_module_enabled "jellyfin" || install_module_jellyfin || true
            repair_storage_permissions
            echo "${C_GRN}[✓] Navidrome отключен, Jellyfin работает как единый сервер для музыки и видео.${C_RES}"
            ;;
    esac
    return 0
}

# 6. Модуль yt-dlp с веб-интерфейсом (Очередь, прогресс, форматы, авто-сортировка Music / Videos / Movies / Series)
install_module_ytdlp() {
    echo "${C_CYN}[*] Установка модуля yt-dlp + Веб-панель загрузки (Audio -> Music / Video -> Videos)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add yt-dlp ffmpeg python3; then
        echo "${C_RED}[X] Не удалось установить пакеты yt-dlp / ffmpeg / python3!${C_RES}"
        return 1
    fi
    apk add py3-yt-dlp >/dev/null 2>&1 || true

    init_homelab_storage
    if ! id ytdlp >/dev/null 2>&1; then
        adduser -D -H -s /sbin/nologin -G "$MEDIA_GROUP" ytdlp 2>/dev/null || \
        adduser -D -H -s /sbin/nologin ytdlp 2>/dev/null || true
    fi
    addgroup ytdlp "$MEDIA_GROUP" 2>/dev/null || true

    mkdir -p "$HOMELAB_LIB_DIR"
    chmod 755 "$HOMELAB_LIB_DIR" 2>/dev/null || true
    cat << 'PY_EOF' > "$YTDLP_WEB_SCRIPT"
#!/usr/bin/env python3
import grp
import json
import os
import shutil
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

if os.path.isfile("/usr/bin/yt-dlp"):
    sys.path.insert(0, "/usr/bin/yt-dlp")
import yt_dlp

MUSIC_DIR = os.environ.get("STORAGE_MUSIC", "/srv/storage/Music")
VIDEO_DIR = os.environ.get("STORAGE_VIDEOS", "/srv/storage/Videos")
MOVIES_DIR = os.path.join(VIDEO_DIR, "Movies")
SERIES_DIR = os.path.join(VIDEO_DIR, "Series")
TEMP_DIR = os.environ.get("STORAGE_INC_YTDLP", "/srv/storage/Downloads/Incomplete/ytdlp")
LISTEN_PORT = int(os.environ.get("PORT_YTDLP", "8081"))
MEDIA_GROUP = os.environ.get("MEDIA_GROUP", "media")

os.umask(0o002)
for d in (MUSIC_DIR, VIDEO_DIR, MOVIES_DIR, SERIES_DIR, TEMP_DIR):
    os.makedirs(d, exist_ok=True)

def apply_media_perms(path):
    try:
        gid = grp.getgrnam(MEDIA_GROUP).gr_gid
    except KeyError:
        gid = -1
    if os.path.isdir(path):
        for root, dirs, files in os.walk(path):
            if gid != -1:
                try:
                    os.chown(root, -1, gid)
                except OSError:
                    pass
            try:
                os.chmod(root, 0o2775)
            except OSError:
                pass
            for f in files:
                fp = os.path.join(root, f)
                if gid != -1:
                    try:
                        os.chown(fp, -1, gid)
                    except OSError:
                        pass
                try:
                    os.chmod(fp, 0o664)
                except OSError:
                    pass
    elif os.path.isfile(path):
        if gid != -1:
            try:
                os.chown(path, -1, gid)
            except OSError:
                pass
        try:
            os.chmod(path, 0o664)
        except OSError:
            pass

JOBS = {}
JOBS_LOCK = threading.Lock()
TASK_QUEUE = []
QUEUE_COND = threading.Condition()

HTML_PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Homelab Media Downloader (yt-dlp)</title>
<style>
  body { font-family: system-ui, sans-serif; background: #0f172a; color: #f1f5f9; max-width: 920px; margin: 1.5rem auto; padding: 0 1rem; }
  .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 1.25rem; margin-bottom: 1.25rem; }
  h1 { color: #38bdf8; margin-top: 0; font-size: 1.5rem; }
  input, select, button { padding: 0.7rem 0.9rem; border-radius: 8px; border: 1px solid #475569; background: #0f172a; color: #fff; font-size: 0.95rem; }
  input[type=text] { width: 100%; box-sizing: border-box; margin-bottom: 0.8rem; }
  .row { display: flex; gap: 0.8rem; flex-wrap: wrap; align-items: center; }
  button { background: #0284c7; border: none; font-weight: 600; cursor: pointer; }
  button:hover { background: #0369a1; }
  button.sec { background: #475569; }
  table { width: 100%; border-collapse: collapse; margin-top: 0.8rem; font-size: 0.9rem; }
  th, td { text-align: left; padding: 0.6rem; border-bottom: 1px solid #334155; }
  .bar { background: #0f172a; border-radius: 6px; height: 10px; width: 120px; overflow: hidden; }
  .fill { background: #22c55e; height: 100%; }
  .st-done { color: #4ade80; font-weight: 600; }
  .st-err { color: #f87171; font-weight: 600; }
  .st-run { color: #38bdf8; font-weight: 600; }
</style>
</head>
<body>
<div class="card">
  <h1>⬇️ Загрузчик медиатеки yt-dlp (Jellyfin &amp; Navidrome)</h1>
  <form onsubmit="addTask(event)">
    <input type="text" id="url" placeholder="Вставьте ссылку на видео, трек или плейлист (YouTube, SoundCloud, VK, Rutube, Twitch...)" required>
    <div class="row">
      <select id="mode">
        <option value="video_best">🎬 Видео: Максимальное качество (MP4/MKV &rarr; Jellyfin Videos)</option>
        <option value="video_1080">🎬 Видео: До 1080p FullHD (MP4 &rarr; Jellyfin Videos)</option>
        <option value="video_720">🎬 Видео: До 720p HD (MP4 &rarr; Jellyfin Videos)</option>
        <option value="audio_mp3">🎵 Музыка: MP3 320 kbps (&rarr; Jellyfin / Navidrome Music)</option>
        <option value="audio_m4a">🎵 Музыка: M4A / AAC (&rarr; Jellyfin / Navidrome Music)</option>
        <option value="audio_flac">🎵 Музыка: FLAC Lossless (&rarr; Jellyfin / Navidrome Music)</option>
      </select>
      <select id="playlist">
        <option value="no">Один ролик / трек</option>
        <option value="yes">Весь плейлист целиком</option>
      </select>
      <button type="submit">Добавить в очередь</button>
      <button type="button" class="sec" onclick="clearFinished()">Очистить завершенные</button>
    </div>
  </form>
</div>
<div class="card">
  <h2 style="margin-top:0;font-size:1.15rem;color:#94a3b8;">Очередь и статус загрузок</h2>
  <table>
    <thead><tr><th>Название / URL</th><th>Тип</th><th>Статус</th><th>Прогресс</th><th>Скорость</th></tr></thead>
    <tbody id="jobs"></tbody>
  </table>
</div>
<script>
async function addTask(e) {
  e.preventDefault();
  const url = document.getElementById('url').value.trim();
  const mode = document.getElementById('mode').value;
  const playlist = document.getElementById('playlist').value;
  if (!url) return;
  await fetch('/api/add', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({url, mode, playlist})
  });
  document.getElementById('url').value = '';
  loadJobs();
}
async function clearFinished() {
  await fetch('/api/clear', {method: 'POST'});
  loadJobs();
}
async function loadJobs() {
  try {
    const r = await fetch('/api/jobs');
    const data = await r.json();
    const tbody = document.getElementById('jobs');
    tbody.innerHTML = data.map(j => {
      const cls = j.status === 'Готово' ? 'st-done' : (j.status.startsWith('Ошибка') ? 'st-err' : 'st-run');
      return `<tr>
        <td style="max-width:320px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="${j.title}">${j.title}</td>
        <td>${j.target}</td>
        <td class="${cls}">${j.status}</td>
        <td><div class="bar"><div class="fill" style="width:${j.percent}%"></div></div> ${j.percent}%</td>
        <td>${j.speed}</td>
      </tr>`;
    }).join('') || '<tr><td colspan="5" style="color:#64748b;">Очередь пуста</td></tr>';
  } catch (e) {}
}
setInterval(loadJobs, 1500);
loadJobs();
</script>
</body>
</html>
"""

def worker_loop():
    while True:
        with QUEUE_COND:
            while not TASK_QUEUE:
                QUEUE_COND.wait()
            job_id = TASK_QUEUE.pop(0)
        run_download(job_id)

def run_download(job_id):
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if not job:
            return
        job["status"] = "Скачивание..."
        url = job["url"]
        mode = job["mode"]
        allow_pl = job["playlist"] == "yes"

    is_audio = mode.startswith("audio_")
    final_dir = MUSIC_DIR if is_audio else VIDEO_DIR
    job_tmp = os.path.join(TEMP_DIR, job_id)
    os.makedirs(job_tmp, exist_ok=True)
    apply_media_perms(job_tmp)

    def progress_hook(d):
        with JOBS_LOCK:
            j = JOBS.get(job_id)
            if not j:
                return
            info = d.get("info_dict") or {}
            if info.get("title"):
                j["title"] = info.get("title")
            if d.get("status") == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                downloaded = d.get("downloaded_bytes") or 0
                if total > 0:
                    j["percent"] = min(99, int(downloaded * 100 / total))
                spd = d.get("speed") or 0
                j["speed"] = f"{spd / 1048576:.1f} МБ/с" if spd else "—"
            elif d.get("status") == "finished":
                j["percent"] = 99
                j["status"] = "Обработка ffmpeg..."

    ydl_opts = {
        "noplaylist": not allow_pl,
        "paths": {"home": job_tmp, "temp": job_tmp},
        "outtmpl": "%(title).150B [%(id)s].%(ext)s",
        "progress_hooks": [progress_hook],
        "quiet": True,
        "no_warnings": True,
        "Restrictfilenames": False,
    }

    if mode == "audio_mp3":
        ydl_opts["format"] = "bestaudio/best"
        ydl_opts["postprocessors"] = [{"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "320"}]
    elif mode == "audio_m4a":
        ydl_opts["format"] = "bestaudio/best"
        ydl_opts["postprocessors"] = [{"key": "FFmpegExtractAudio", "preferredcodec": "m4a", "preferredquality": "256"}]
    elif mode == "audio_flac":
        ydl_opts["format"] = "bestaudio/best"
        ydl_opts["postprocessors"] = [{"key": "FFmpegExtractAudio", "preferredcodec": "flac"}]
    elif mode == "video_1080":
        ydl_opts["format"] = "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        ydl_opts["merge_output_format"] = "mp4"
    elif mode == "video_720":
        ydl_opts["format"] = "bestvideo[height<=720]+bestaudio/best[height<=720]"
        ydl_opts["merge_output_format"] = "mp4"
    else:
        ydl_opts["format"] = "bestvideo+bestaudio/best"
        ydl_opts["merge_output_format"] = "mp4"

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])
        for fname in os.listdir(job_tmp):
            if fname.endswith((".part", ".ytdl", ".temp")):
                continue
            src = os.path.join(job_tmp, fname)
            dst = os.path.join(final_dir, fname)
            if os.path.isfile(src):
                if os.path.exists(dst):
                    os.remove(dst)
                shutil.move(src, dst)
                apply_media_perms(dst)
        with JOBS_LOCK:
            if job_id in JOBS:
                JOBS[job_id]["percent"] = 100
                JOBS[job_id]["speed"] = "—"
                JOBS[job_id]["status"] = "Готово"
    except Exception as exc:
        with JOBS_LOCK:
            if job_id in JOBS:
                JOBS[job_id]["status"] = f"Ошибка: {str(exc)[:60]}"
                JOBS[job_id]["speed"] = "—"
    finally:
        shutil.rmtree(job_tmp, ignore_errors=True)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/api/jobs":
            with JOBS_LOCK:
                out = list(JOBS.values())[::-1]
            body = json.dumps(out).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
        else:
            body = HTML_PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)

    def do_POST(self):
        p = urlparse(self.path).path
        if p == "/api/add":
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length).decode("utf-8")
            data = json.loads(raw)
            url = (data.get("url") or "").strip()
            mode = data.get("mode") or "video_best"
            pl = data.get("playlist") or "no"
            if url.startswith(("http://", "https://")):
                jid = uuid.uuid4().hex[:10]
                target_lbl = "🎵 Music (Jellyfin/Navidrome)" if mode.startswith("audio_") else "🎬 Videos (Jellyfin)"
                with JOBS_LOCK:
                    JOBS[jid] = {
                        "id": jid,
                        "url": url,
                        "title": url,
                        "mode": mode,
                        "playlist": pl,
                        "target": target_lbl,
                        "status": "В очереди",
                        "percent": 0,
                        "speed": "—",
                    }
                with QUEUE_COND:
                    TASK_QUEUE.append(jid)
                    QUEUE_COND.notify()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
        elif p == "/api/clear":
            with JOBS_LOCK:
                to_del = [k for k, v in JOBS.items() if v["status"] == "Готово" or v["status"].startswith("Ошибка")]
                for k in to_del:
                    del JOBS[k]
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"ok":true}')

if __name__ == "__main__":
    t = threading.Thread(target=worker_loop, daemon=True)
    t.start()
    srv = ThreadingHTTPServer(("127.0.0.1", LISTEN_PORT), Handler)
    srv.serve_forever()
PY_EOF
    chmod 755 "$YTDLP_WEB_SCRIPT"

    cat << YTDLP_INIT > /etc/init.d/ytdlp-webui
#!/sbin/openrc-run
name="ytdlp-webui"
description="yt-dlp Web UI Media Downloader"
supervisor="supervise-daemon"
command="/usr/bin/python3"
command_args="${YTDLP_WEB_SCRIPT}"
command_user="ytdlp:${MEDIA_GROUP}"
umask="0002"
output_log="/var/log/ytdlp-webui.log"
error_log="/var/log/ytdlp-webui.log"
export STORAGE_MUSIC="${STORAGE_MUSIC}"
export STORAGE_VIDEOS="${STORAGE_VIDEOS}"
export STORAGE_INC_YTDLP="${STORAGE_INC_YTDLP}"
export PORT_YTDLP="${PORT_YTDLP}"
export MEDIA_GROUP="${MEDIA_GROUP}"

depend() {
    need net
}

start_pre() {
    checkpath -f -m 0644 -o ytdlp:${MEDIA_GROUP} /var/log/ytdlp-webui.log
    checkpath -d -m 2775 -o ytdlp:${MEDIA_GROUP} "${STORAGE_INC_YTDLP}"
}
YTDLP_INIT
    chmod +x /etc/init.d/ytdlp-webui

    repair_storage_permissions
    service_ctl ytdlp-webui enable
    if ! service_ctl ytdlp-webui restart; then
        echo "${C_RED}[X] Служба ytdlp-webui не смогла запуститься!${C_RES}"
        return 1
    fi
    register_caddy_site "ytdlp" "$DOM_YTDLP" "$PORT_YTDLP" "yes"
    set_module_state "ytdlp" "yes"

    echo "${C_GRN}[✓] Веб-панель yt-dlp запущена: https://${DOM_YTDLP} (Логин: ${SMB_USER:-admin} / Пароль: единый пароль шлюза)${C_RES}"
    return 0
}

remove_module_ytdlp() {
    service_ctl ytdlp-webui stop
    service_ctl ytdlp-webui disable
    remove_caddy_site "ytdlp"
    set_module_state "ytdlp" "no"
    echo "${C_GRN}[✓] Модуль yt-dlp Web UI отключен.${C_RES}"
    return 0
}

# 7. Модуль qBittorrent-nox + Hardlink-импортер в медиатеку (Movies / Series / Music) без потери раздачи
install_module_torrent() {
    echo "${C_CYN}[*] Установка модуля qBittorrent-nox + Hardlink Media Pipeline...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add qbittorrent-nox qbittorrent-nox-openrc; then
        if ! apk add qbittorrent-nox; then
            echo "${C_RED}[X] Не удалось установить пакет qbittorrent-nox!${C_RES}"
            return 1
        fi
    fi

    if ! id qbittorrent >/dev/null 2>&1; then
        addgroup -S qbittorrent 2>/dev/null || true
        adduser -S -D -H -h /var/lib/qbittorrent -s /sbin/nologin -G qbittorrent qbittorrent 2>/dev/null || true
    fi

    init_homelab_storage
    addgroup qbittorrent "$MEDIA_GROUP" 2>/dev/null || true

    # Генерация хука безопасного импорта завершенных торрентов через жесткие ссылки (hardlinks cp -al)
    mkdir -p "$HOMELAB_LIB_DIR"
    chmod 755 "$HOMELAB_LIB_DIR" 2>/dev/null || true
    cat << HOOK_EOF > "$TORRENT_HOOK"
#!/bin/sh
# Авто-импорт завершенных раздач в медиатеку Jellyfin / Navidrome без остановки сидинга
umask 0002
CAT_NAME="\$(printf "%s" "\${1:-}" | tr 'A-Z' 'a-z')"
CONTENT_PATH="\${2:-}"
[ -z "\$CONTENT_PATH" ] || [ ! -e "\$CONTENT_PATH" ] && exit 0

case "\$CAT_NAME" in
    music|audio|музыка)
        DEST_DIR="${STORAGE_MUSIC}"
        ;;
    movies|movie|films|фильмы)
        DEST_DIR="${STORAGE_VIDEOS_MOVIES}"
        ;;
    series|tv|shows|сериалы)
        DEST_DIR="${STORAGE_VIDEOS_SERIES}"
        ;;
    video|videos|видео)
        DEST_DIR="${STORAGE_VIDEOS}"
        ;;
    *)
        exit 0
        ;;
esac

mkdir -p "\$DEST_DIR"
BASE_NAME="\$(basename "\$CONTENT_PATH")"
TARGET_PATH="\${DEST_DIR}/\${BASE_NAME}"

# Мгновенное создание жестких ссылок (0 лишних байт на одной ФС, раздача продолжается!)
cp -al "\$CONTENT_PATH" "\$DEST_DIR/" 2>/dev/null || cp -rf "\$CONTENT_PATH" "\$DEST_DIR/" 2>/dev/null || true
if [ -e "\$TARGET_PATH" ]; then
    chgrp -R "${MEDIA_GROUP}" "\$TARGET_PATH" 2>/dev/null || true
    find "\$TARGET_PATH" -type d -exec chmod 2775 {} + 2>/dev/null || true
    find "\$TARGET_PATH" -type f -exec chmod 0664 {} + 2>/dev/null || true
fi
exit 0
HOOK_EOF
    chmod 755 "$TORRENT_HOOK"

    QB_HOME="/var/lib/qbittorrent"
    QB_CONF_DIR="${QB_HOME}/.config/qBittorrent"
    mkdir -p "$QB_CONF_DIR"

    cat << QB_CATS > "${QB_CONF_DIR}/categories.json"
{
    "music": {
        "save_path": "${STORAGE_DL_MUSIC}"
    },
    "videos": {
        "save_path": "${STORAGE_DL_VIDEOS}"
    },
    "movies": {
        "save_path": "${STORAGE_DL_VIDEOS}"
    },
    "series": {
        "save_path": "${STORAGE_DL_VIDEOS}"
    }
}
QB_CATS

    load_gateway_env
    QB_USER="${SMB_USER:-${AGH_USER:-admin}}"
    QB_PBKDF2=""
    if command -v python3 >/dev/null 2>&1; then
        QB_PBKDF2=$(python3 - "${ADMIN_PASS:-admin}" << 'PY_QB_HASH' 2>/dev/null || true
import hashlib, base64, os, sys
pw = sys.argv[1].encode("utf-8")
salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac("sha512", pw, salt, 100000, 64)
print(f"@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(dk).decode()})")
PY_QB_HASH
)
    fi

    cat << QB_CONF > "${QB_CONF_DIR}/qBittorrent.conf"
[AutoRun]
enabled=true
program="${TORRENT_HOOK} \"%L\" \"%F\" \"%N\""

[BitTorrent]
Session\DefaultSavePath=${STORAGE_DL_OTHER}
Session\Port=${PORT_TORRENT_PEER}
Session\TempPath=${STORAGE_INC_TORRENTS}
Session\TempPathEnabled=true

[LegalNotice]
Accepted=true

[Preferences]
Downloads\SavePath=${STORAGE_DL_OTHER}
Downloads\TempPath=${STORAGE_INC_TORRENTS}
Downloads\TempPathEnabled=true
WebUI\Address=127.0.0.1
WebUI\Port=${PORT_TORRENT_WEB}
WebUI\Username=${QB_USER}
WebUI\Password_PBKDF2="${QB_PBKDF2}"
WebUI\AuthSubnetWhitelist=127.0.0.1/32, ::1/128
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\CSRFProtection=false
WebUI\HostHeaderValidation=false
WebUI\LocalHostAuth=false
QB_CONF

    chown -R qbittorrent:"$MEDIA_GROUP" "$QB_HOME" 2>/dev/null || true
    chmod 750 "$QB_HOME" 2>/dev/null || true

    cat << QB_CONF_D > /etc/conf.d/qbittorrent-nox
WEBUI_PORT=${PORT_TORRENT_WEB}
command_user="qbittorrent:${MEDIA_GROUP}"
directory="/var/lib/qbittorrent"
umask="0002"
QB_CONF_D

    cat << QB_INIT > /etc/init.d/qbittorrent-nox
#!/sbin/openrc-run
name="qbittorrent-nox"
description="qBittorrent-nox headless BitTorrent client"
supervisor="supervise-daemon"
command="/usr/bin/qbittorrent-nox"
command_args="--webui-port=\${WEBUI_PORT:-${PORT_TORRENT_WEB}}"
command_user="\${command_user:-qbittorrent:${MEDIA_GROUP}}"
directory="/var/lib/qbittorrent"
umask="0002"
output_log="/var/log/qbittorrent-nox.log"
error_log="/var/log/qbittorrent-nox.log"
rc_ulimit="-n 50000"
export HOME="/var/lib/qbittorrent"
export XDG_CONFIG_HOME="/var/lib/qbittorrent/.config"
export XDG_DATA_HOME="/var/lib/qbittorrent/.local/share"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -d -m 0750 -o qbittorrent:${MEDIA_GROUP} /var/lib/qbittorrent
    checkpath -f -m 0640 -o qbittorrent:${MEDIA_GROUP} /var/log/qbittorrent-nox.log
}
QB_INIT
    chmod +x /etc/init.d/qbittorrent-nox

    repair_storage_permissions
    service_ctl qbittorrent-nox enable
    if ! service_ctl qbittorrent-nox restart; then
        echo "${C_RED}[X] Служба qbittorrent-nox не смогла запуститься!${C_RES}"
        return 1
    fi
    sync_dns_firewall "yes" "keep"
    register_caddy_site "torrent" "$DOM_TORRENT" "$PORT_TORRENT_WEB" "yes"
    set_module_state "torrent" "yes"

    echo "${C_GRN}[✓] qBittorrent-nox запущен: https://${DOM_TORRENT} (защищен BasicAuth паролем шлюза)${C_RES}"
    echo "    Категории 'music', 'videos', 'movies', 'series' автоматически линкуются в медиатеку без потери раздачи!"
    return 0
}

remove_module_torrent() {
    service_ctl qbittorrent-nox stop
    service_ctl qbittorrent-nox disable
    remove_caddy_site "torrent"
    set_module_state "torrent" "no"
    echo "${C_GRN}[✓] Модуль qBittorrent-nox отключен (файлы в ${STORAGE_DOWNLOADS} сохранены).${C_RES}"
    return 0
}

# ==============================================================================
# ЕДИНЫЙ МОДУЛЬ ТЕСТИРОВАНИЯ И АВТОИСПРАВЛЕНИЯ ПРАВ ДОСТУПА (ТЗ Пункт 1 и 5)
# Проверяет фактические операции (Read / Write / Create / Delete / DB / Media /
# UID/GID / Groups / POSIX mode / setgid / POSIX ACL / Cross-Service Access)
# от имени каждого сервисного пользователя через su -s /bin/sh <user> -c "..."
# ==============================================================================

# Вспомогательная функция выполнения команды от имени сервисного пользователя
exec_as_service_user() {
    SVC_USR="$1"
    SVC_CMD="$2"
    if [ "$SVC_USR" = "root" ] || [ "$SVC_USR" = "$(id -un 2>/dev/null)" ]; then
        /bin/sh -c "$SVC_CMD" >/dev/null 2>&1
        return $?
    fi
    if ! id "$SVC_USR" >/dev/null 2>&1; then
        return 1
    fi
    su -s /bin/sh "$SVC_USR" -c "$SVC_CMD" >/dev/null 2>&1
    return $?
}

# Безопасное тестирование цикла Чтение / Создание / Изменение / Удаление временного файла от имени пользователя
test_user_rwcd_on_dir() {
    T_USER="$1"
    T_DIR="$2"
    R_ST="FAIL"; W_ST="FAIL"; C_ST="FAIL"; D_ST="FAIL"

    if [ ! -d "$T_DIR" ]; then
        printf "FAIL|FAIL|FAIL|FAIL"
        return 1
    fi

    if exec_as_service_user "$T_USER" "test -r '$T_DIR' && test -x '$T_DIR' && ls -la '$T_DIR' >/dev/null 2>&1"; then
        R_ST="OK"
    fi

    PROBE_FILE="${T_DIR}/.perm_probe_${T_USER}_$$.tmp"
    rm -f "$PROBE_FILE" 2>/dev/null || true

    if exec_as_service_user "$T_USER" "umask 0002; : > '$PROBE_FILE'"; then
        C_ST="OK"
        if exec_as_service_user "$T_USER" "printf 'audit_ok\n' >> '$PROBE_FILE' && grep -q 'audit_ok' '$PROBE_FILE'"; then
            W_ST="OK"
        fi
        if exec_as_service_user "$T_USER" "rm -f '$PROBE_FILE'" && [ ! -e "$PROBE_FILE" ]; then
            D_ST="OK"
        else
            rm -f "$PROBE_FILE" 2>/dev/null || true
        fi
    else
        rm -f "$PROBE_FILE" 2>/dev/null || true
    fi

    printf "%s|%s|%s|%s" "$R_ST" "$W_ST" "$C_ST" "$D_ST"
    [ "$R_ST" = "OK" ] && [ "$W_ST" = "OK" ] && [ "$C_ST" = "OK" ] && [ "$D_ST" = "OK" ]
}

# Комплексный аудит прав доступа одного сервиса с выводом полного отчета по ТЗ
audit_single_service_permissions() {
    S_ID="$1"
    S_TITLE="$2"
    S_USER="$3"
    S_REQ_GRPS="$4"
    S_DATA_DIR="$5"
    S_DB_PATH="$6"
    S_MEDIA_MODE="$7" # none | ro_music | rw_all | rw_media

    RES_READ="FAIL"
    RES_WRITE="FAIL"
    RES_CREATE="FAIL"
    RES_DELETE="FAIL"
    RES_DB="N/A"
    RES_MEDIA="N/A"
    OWN_INFO="нет данных"
    PROBLEMS=""
    RECS=""
    SVC_FAIL_CNT=0

    # 1. Проверка существования пользователя и его UID/GID/групп
    if ! id "$S_USER" >/dev/null 2>&1; then
        OWN_INFO="Пользователь '${S_USER}' НЕ СУЩЕСТВУЕТ"
        PROBLEMS="Отсутствует системный пользователь ${S_USER}; "
        RECS="Установить модуль ${S_ID} или запустить автоисправление прав; "
        SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
    else
        U_UID=$(id -u "$S_USER" 2>/dev/null || echo "?")
        U_GID=$(id -g "$S_USER" 2>/dev/null || echo "?")
        U_GRPS=$(id -Gn "$S_USER" 2>/dev/null | tr ' ' ',' || echo "?")
        OWN_INFO="UID=${U_UID}, GID=${U_GID}, Группы=[${U_GRPS}]"

        for REQ_G in $S_REQ_GRPS; do
            [ -z "$REQ_G" ] || [ "$REQ_G" = "_" ] && continue
            if ! id -Gn "$S_USER" 2>/dev/null | tr ' ' '\n' | grep -qxF "$REQ_G"; then
                PROBLEMS="${PROBLEMS}Пользователь ${S_USER} не состоит в группе '${REQ_G}'; "
                RECS="${RECS}Выполнить: addgroup ${S_USER} ${REQ_G}; "
                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
            fi
        done
    fi

    # 2. Проверка собственной директории данных/конфигурации (Read/Write/Create/Delete)
    if [ -n "$S_DATA_DIR" ] && [ "$S_DATA_DIR" != "_" ]; then
        if [ ! -d "$S_DATA_DIR" ]; then
            PROBLEMS="${PROBLEMS}Отсутствует рабочий каталог ${S_DATA_DIR}; "
            RECS="${RECS}Создать каталог ${S_DATA_DIR} и назначить владельца ${S_USER}; "
            SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
        else
            D_STAT=$(stat -c "%a %U:%G" "$S_DATA_DIR" 2>/dev/null || echo "?")
            OWN_INFO="${OWN_INFO} | Каталог ${S_DATA_DIR}: [${D_STAT}]"
            RWCD_OUT=$(test_user_rwcd_on_dir "$S_USER" "$S_DATA_DIR" || true)
            RES_READ=$(printf "%s" "$RWCD_OUT" | cut -d'|' -f1)
            RES_WRITE=$(printf "%s" "$RWCD_OUT" | cut -d'|' -f2)
            RES_CREATE=$(printf "%s" "$RWCD_OUT" | cut -d'|' -f3)
            RES_DELETE=$(printf "%s" "$RWCD_OUT" | cut -d'|' -f4)
            if [ "$RES_READ" != "OK" ] || [ "$RES_WRITE" != "OK" ] || [ "$RES_CREATE" != "OK" ] || [ "$RES_DELETE" != "OK" ]; then
                PROBLEMS="${PROBLEMS}Сбой операций R/W/C/D в ${S_DATA_DIR} от имени ${S_USER}; "
                RECS="${RECS}Выполнить chown -R ${S_USER} ${S_DATA_DIR} и chmod 750 ${S_DATA_DIR}; "
                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
            fi
        fi
    fi

    # 3. Проверка доступа к базе данных (SQLite / TDB / Конфиг)
    if [ -n "$S_DB_PATH" ] && [ "$S_DB_PATH" != "N/A" ]; then
        if [ -f "$S_DB_PATH" ]; then
            if exec_as_service_user "$S_USER" "test -r '$S_DB_PATH' && test -w '$S_DB_PATH'"; then
                RES_DB="OK"
                case "$S_DB_PATH" in
                    *.sqlite3|*.db)
                        if command -v sqlite3 >/dev/null 2>&1; then
                            if ! exec_as_service_user "$S_USER" "sqlite3 '$S_DB_PATH' 'PRAGMA quick_check;' | grep -qx 'ok'"; then
                                RES_DB="FAIL"
                                PROBLEMS="${PROBLEMS}Ошибка целостности или блокировки SQLite БД ${S_DB_PATH}; "
                                RECS="${RECS}Проверить владельца файлов -wal/-shm и права каталога БД; "
                                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
                            fi
                        elif command -v python3 >/dev/null 2>&1; then
                            if ! exec_as_service_user "$S_USER" "python3 -c \"import sqlite3; c=sqlite3.connect('$S_DB_PATH'); r=c.execute('PRAGMA quick_check').fetchone()[0]; assert r=='ok'\""; then
                                RES_DB="FAIL"
                                PROBLEMS="${PROBLEMS}Ошибка целостности или блокировки SQLite БД ${S_DB_PATH}; "
                                RECS="${RECS}Проверить владельца файлов -wal/-shm и права каталога БД; "
                                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
                            fi
                        fi
                        ;;
                esac
            else
                RES_DB="FAIL"
                PROBLEMS="${PROBLEMS}Нет прав чтения/записи файла БД ${S_DB_PATH} для ${S_USER}; "
                RECS="${RECS}Выполнить chown ${S_USER} ${S_DB_PATH} и chmod 640 ${S_DB_PATH}; "
                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
            fi
        else
            DB_PARENT=$(dirname "$S_DB_PATH")
            if [ -d "$DB_PARENT" ] && exec_as_service_user "$S_USER" "test -w '$DB_PARENT' && test -x '$DB_PARENT'"; then
                RES_DB="OK (каталог БД готов к записи)"
            else
                RES_DB="FAIL"
                PROBLEMS="${PROBLEMS}Каталог базы данных ${DB_PARENT} недоступен для записи пользователю ${S_USER}; "
                RECS="${RECS}Исправить права на ${DB_PARENT} для ${S_USER}; "
                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
            fi
        fi
    fi

    # 4. Проверка доступа к общей медиатеке /srv/storage
    case "$S_MEDIA_MODE" in
        none)
            RES_MEDIA="N/A"
            ;;
        ro_music)
            if exec_as_service_user "$S_USER" "test -r '$STORAGE_MUSIC' && test -x '$STORAGE_MUSIC'"; then
                RES_MEDIA="OK"
            else
                RES_MEDIA="FAIL"
                PROBLEMS="${PROBLEMS}Нет доступа к музыкальной библиотеке ${STORAGE_MUSIC}; "
                RECS="${RECS}Добавить ${S_USER} в группу ${MEDIA_GROUP} и применить repair_storage_permissions; "
                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
            fi
            ;;
        rw_media)
            if exec_as_service_user "$S_USER" "test -r '$STORAGE_MUSIC' && test -w '$STORAGE_MUSIC' && test -r '$STORAGE_VIDEOS' && test -w '$STORAGE_VIDEOS' && test -r '$STORAGE_VIDEOS_MOVIES' && test -r '$STORAGE_VIDEOS_SERIES'"; then
                RES_MEDIA="OK"
            else
                RES_MEDIA="FAIL"
                PROBLEMS="${PROBLEMS}Нет полного доступа к ${STORAGE_VIDEOS} (Movies/Series) и/или ${STORAGE_MUSIC}; "
                RECS="${RECS}Добавить ${S_USER} в группу ${MEDIA_GROUP} и выставить 2775 + ACL на /srv/storage; "
                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
            fi
            ;;
        rw_all)
            M_RWCD=$(test_user_rwcd_on_dir "$S_USER" "$STORAGE_MUSIC" || true)
            V_RWCD=$(test_user_rwcd_on_dir "$S_USER" "$STORAGE_VIDEOS" || true)
            D_RWCD=$(test_user_rwcd_on_dir "$S_USER" "$STORAGE_DOWNLOADS" || true)
            if [ "$M_RWCD" = "OK|OK|OK|OK" ] && [ "$V_RWCD" = "OK|OK|OK|OK" ] && [ "$D_RWCD" = "OK|OK|OK|OK" ]; then
                RES_MEDIA="OK"
                if [ "$S_DATA_DIR" = "$STORAGE_ROOT" ]; then
                    RES_READ="OK"; RES_WRITE="OK"; RES_CREATE="OK"; RES_DELETE="OK"
                fi
            else
                RES_MEDIA="FAIL"
                PROBLEMS="${PROBLEMS}Сбой записи/модификации в каталогах медиатеки (${STORAGE_ROOT}) от имени ${S_USER}; "
                RECS="${RECS}Выполнить repair_storage_permissions (группа ${MEDIA_GROUP}, setgid 2775, POSIX ACL); "
                SVC_FAIL_CNT=$((SVC_FAIL_CNT + 1))
            fi
            ;;
    esac

    [ -z "$PROBLEMS" ] && PROBLEMS="Не обнаружено (все проверки пройдены)"
    [ -z "$RECS" ] && RECS="Действий не требуется"

    ColorStatus() {
        case "$1" in
            OK*) printf "%s%s%s" "$C_GRN" "$1" "$C_RES" ;;
            N/A*) printf "%s%s%s" "$C_DIM" "$1" "$C_RES" ;;
            *) printf "%s%s%s" "$C_RED" "$1" "$C_RES" ;;
        esac
    }

    echo " ${C_BLD}▸ Сервис: ${S_TITLE} [${S_ID}] (пользователь: ${S_USER})${C_RES}"
    echo "   • Чтение:                 $(ColorStatus "$RES_READ")"
    echo "   • Запись:                 $(ColorStatus "$RES_WRITE")"
    echo "   • Создание файла:         $(ColorStatus "$RES_CREATE")"
    echo "   • Удаление тестового ф.:  $(ColorStatus "$RES_DELETE")"
    echo "   • Доступ к базе данных:   $(ColorStatus "$RES_DB")"
    echo "   • Доступ к медиатеке:     $(ColorStatus "$RES_MEDIA")"
    echo "   • Владельцы и группы:     ${OWN_INFO}"
    if [ "$SVC_FAIL_CNT" -eq 0 ]; then
        echo "   • Обнаруженные проблемы:  ${C_GRN}${PROBLEMS}${C_RES}"
        echo "   • Рекомендации:           ${C_DIM}${RECS}${C_RES}"
    else
        echo "   • Обнаруженные проблемы:  ${C_RED}${PROBLEMS}${C_RES}"
        echo "   • Рекомендации:           ${C_YEL}${RECS}${C_RES}"
    fi
    echo "-----------------------------------------------------------------------"
    return "$SVC_FAIL_CNT"
}

# Проверка дерева /srv/storage: setgid (2775), группа media, POSIX ACL и межсервисная совместимость
audit_storage_tree_and_cross_service() {
    load_gateway_env
    echo " ${C_BLD}▸ Аудит структуры общего хранилища (${STORAGE_ROOT}) и кросс-сервисного доступа${C_RES}"
    ST_ERR=0
    STORAGE_DIRS="
${STORAGE_ROOT}
${STORAGE_MUSIC}
${STORAGE_VIDEOS}
${STORAGE_VIDEOS_MOVIES}
${STORAGE_VIDEOS_SERIES}
${STORAGE_DOWNLOADS}
${STORAGE_DL_MUSIC}
${STORAGE_DL_VIDEOS}
${STORAGE_DL_OTHER}
${STORAGE_INCOMPLETE}
${STORAGE_INC_TORRENTS}
${STORAGE_INC_YTDLP}
"
    for S_DIR in $STORAGE_DIRS; do
        [ -z "$S_DIR" ] && continue
        if [ ! -d "$S_DIR" ]; then
            echo "   ${C_RED}[FAIL]${C_RES} Каталог отсутствует: ${S_DIR}"
            ST_ERR=$((ST_ERR + 1))
            continue
        fi
        D_GRP=$(stat -c "%G" "$S_DIR" 2>/dev/null || echo "?")
        D_MOD=$(stat -c "%a" "$S_DIR" 2>/dev/null || echo "0")
        SGID_OK="no"
        [ -g "$S_DIR" ] && SGID_OK="yes"
        ACL_OK="N/A"
        if command -v getfacl >/dev/null 2>&1; then
            if getfacl -p "$S_DIR" 2>/dev/null | grep -q "default:group:${MEDIA_GROUP}:rwx"; then
                ACL_OK="OK"
            else
                ACL_OK="WARN (нет default ACL)"
            fi
        fi
        if [ "$D_GRP" = "$MEDIA_GROUP" ] && [ "$SGID_OK" = "yes" ]; then
            printf "   %s[OK]%s   %-42s | mode=%s group=%s setgid=YES ACL=%s\n" "$C_GRN" "$C_RES" "$S_DIR" "$D_MOD" "$D_GRP" "$ACL_OK"
        else
            printf "   %s[FAIL]%s %-42s | mode=%s group=%s setgid=%s ACL=%s (ожидается 2775 :%s)\n" "$C_RED" "$C_RES" "$S_DIR" "$D_MOD" "$D_GRP" "$SGID_OK" "$ACL_OK" "$MEDIA_GROUP"
            ST_ERR=$((ST_ERR + 1))
        fi
    done

    # Кросс-сервисный тест: файл создает один сервис (ytdlp/qbittorrent), читает другой (jellyfin/navidrome), переименовывает и удаляет третий (homelab/Samba)
    CROSS_FILE="${STORAGE_MUSIC}/.cross_service_test_$$.tmp"
    rm -f "$CROSS_FILE" "${CROSS_FILE}.renamed" 2>/dev/null || true
    WRITER_U="${SMB_USER:-homelab}"
    id ytdlp >/dev/null 2>&1 && WRITER_U="ytdlp"
    id qbittorrent >/dev/null 2>&1 && WRITER_U="qbittorrent"

    if exec_as_service_user "$WRITER_U" "umask 0002; printf 'cross_ok\n' > '$CROSS_FILE'"; then
        F_GRP=$(stat -c "%G" "$CROSS_FILE" 2>/dev/null || echo "?")
        if [ "$F_GRP" != "$MEDIA_GROUP" ]; then
            echo "   ${C_RED}[FAIL]${C_RES} Наследование setgid: файл созданный ${WRITER_U} получил группу '${F_GRP}' вместо '${MEDIA_GROUP}'!"
            ST_ERR=$((ST_ERR + 1))
        else
            echo "   ${C_GRN}[OK]${C_RES}   Наследование setgid: тестовый файл от '${WRITER_U}' автоматически унаследовал группу '${MEDIA_GROUP}'"
        fi

        for READER_U in jellyfin navidrome "${SMB_USER:-homelab}"; do
            if id "$READER_U" >/dev/null 2>&1; then
                if ! exec_as_service_user "$READER_U" "grep -q 'cross_ok' '$CROSS_FILE'"; then
                    echo "   ${C_RED}[FAIL]${C_RES} Межсервисное чтение: пользователь '${READER_U}' не может прочитать файл, созданный '${WRITER_U}'!"
                    ST_ERR=$((ST_ERR + 1))
                fi
            fi
        done

        if id "${SMB_USER:-homelab}" >/dev/null 2>&1; then
            if exec_as_service_user "${SMB_USER:-homelab}" "mv '$CROSS_FILE' '${CROSS_FILE}.renamed' && rm -f '${CROSS_FILE}.renamed'"; then
                echo "   ${C_GRN}[OK]${C_RES}   Межсервисная модификация: '${SMB_USER:-homelab}' переименовал и удалил файл, созданный '${WRITER_U}'"
            else
                echo "   ${C_RED}[FAIL]${C_RES} Межсервисная модификация: '${SMB_USER:-homelab}' не смог переименовать/удалить файл от '${WRITER_U}'!"
                ST_ERR=$((ST_ERR + 1))
            fi
        fi
    else
        echo "   ${C_RED}[FAIL]${C_RES} Пользователь '${WRITER_U}' не смог создать тестовый файл в ${STORAGE_MUSIC}!"
        ST_ERR=$((ST_ERR + 1))
    fi
    rm -f "$CROSS_FILE" "${CROSS_FILE}.renamed" 2>/dev/null || true
    echo "-----------------------------------------------------------------------"
    return "$ST_ERR"
}

# Полное автоматическое исправление прав доступа всех сервисов и хранилища (с предварительным бэкапом)
repair_all_homelab_permissions() {
    AUTO_CONFIRM="${1:-ask}"
    load_gateway_env
    if [ "$AUTO_CONFIRM" = "ask" ] && [ -t 0 ]; then
        printf "Создать резервную копию конфигураций и автоматически исправить все права доступа? (y/n) [Enter = y]: "
        read -r FIX_ANS < /dev/tty || true
        FIX_ANS=$(printf "%s" "$FIX_ANS" | tr -d ' \t\r\n')
        [ -z "$FIX_ANS" ] && FIX_ANS="y"
        case "$FIX_ANS" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) ;;
            *) echo "[i] Автоисправление отменено пользователем."; return 0 ;;
        esac
    fi

    echo "${C_CYN}[*] Создание предварительной резервной копии конфигураций перед исправлением прав...${C_RES}"
    create_unified_backup "no" >/dev/null 2>&1 || backup_gateway_state || true

    echo "${C_CYN}[*] Восстановление эталонных пользователей, групп, setgid (2775) и POSIX ACL...${C_RES}"
    init_homelab_storage
    repair_storage_permissions

    # Права конфигураций шлюза
    chmod 600 "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" "$AGH_CONF" 2>/dev/null || true

    # Права Vaultwarden
    if id vaultwarden >/dev/null 2>&1 || [ -d /var/lib/vaultwarden ]; then
        sync_vaultwarden_config >/dev/null 2>&1 || true
    fi

    # Права Forgejo
    if id forgejo >/dev/null 2>&1 && [ -d /var/lib/forgejo ]; then
        FG_GRP=$(id -gn forgejo 2>/dev/null || echo "www-data")
        chown -R "forgejo:${FG_GRP}" /var/lib/forgejo /var/log/forgejo /etc/forgejo 2>/dev/null || true
        chmod 750 /var/lib/forgejo /var/log/forgejo /etc/forgejo 2>/dev/null || true
        [ -f /etc/forgejo/app.ini ] && chmod 640 /etc/forgejo/app.ini 2>/dev/null || true
    fi

    # Права Navidrome
    if id navidrome >/dev/null 2>&1 && [ -d /var/lib/navidrome ]; then
        addgroup navidrome "$MEDIA_GROUP" 2>/dev/null || true
        chown -R navidrome:"$MEDIA_GROUP" /var/lib/navidrome /etc/navidrome 2>/dev/null || true
        chmod 750 /var/lib/navidrome /etc/navidrome 2>/dev/null || true
    fi

    # Права Jellyfin
    if id jellyfin >/dev/null 2>&1; then
        for GRP_J in "$MEDIA_GROUP" video render; do
            addgroup jellyfin "$GRP_J" 2>/dev/null || true
        done
        for JF_D in /var/lib/jellyfin /etc/jellyfin /var/log/jellyfin /var/cache/jellyfin; do
            [ -d "$JF_D" ] && { chown -R jellyfin:"$MEDIA_GROUP" "$JF_D" 2>/dev/null || true; chmod 750 "$JF_D" 2>/dev/null || true; }
        done
    fi

    # Права yt-dlp
    if id ytdlp >/dev/null 2>&1; then
        addgroup ytdlp "$MEDIA_GROUP" 2>/dev/null || true
        touch /var/log/ytdlp-webui.log 2>/dev/null || true
        chown ytdlp:"$MEDIA_GROUP" /var/log/ytdlp-webui.log 2>/dev/null || true
        chmod 644 /var/log/ytdlp-webui.log 2>/dev/null || true
    fi

    # Права qBittorrent
    if id qbittorrent >/dev/null 2>&1 && [ -d /var/lib/qbittorrent ]; then
        addgroup qbittorrent "$MEDIA_GROUP" 2>/dev/null || true
        chown -R qbittorrent:"$MEDIA_GROUP" /var/lib/qbittorrent 2>/dev/null || true
        chmod 750 /var/lib/qbittorrent 2>/dev/null || true
    fi

    # Права Caddy
    if id caddy >/dev/null 2>&1; then
        chown -R caddy:caddy /var/lib/caddy "$PKI_PORTAL_DIR" /etc/caddy 2>/dev/null || true
        chmod 755 "$PKI_PORTAL_DIR" /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    fi

    # Права Server-Code
    if id coder >/dev/null 2>&1 && [ -d /var/lib/coder ]; then
        addgroup coder "$MEDIA_GROUP" 2>/dev/null || true
        chown -R coder:"$MEDIA_GROUP" /var/lib/coder /opt/code-server 2>/dev/null || true
    fi

    # Права Samba
    if is_module_enabled "samba" && command -v smbpasswd >/dev/null 2>&1; then
        apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS" >/dev/null 2>&1 || true
    fi

    echo "${C_GRN}[✓] Автоматическое исправление прав доступа всех сервисов и ${STORAGE_ROOT} успешно завершено!${C_RES}"
    return 0
}

# Запуск полного аудита прав доступа для всех сервисов Homelab
run_homelab_permissions_audit() {
    AUTO_FIX_MODE="${1:-interactive}"
    init_homelab_registry
    load_gateway_env
    ensure_media_group_and_users

    echo ""
    echo "${C_CYN}=======================================================================${C_RES}"
    echo "${C_BLD} 🛡️ Единый модуль диагностики прав доступа (Homelab Permissions Audit)${C_RES}"
    echo "${C_CYN}=======================================================================${C_RES}"

    TOTAL_ISSUES=0

    # Проверка общего хранилища /srv/storage и кросс-сервисного взаимодействия
    if [ -d "$STORAGE_ROOT" ]; then
        audit_storage_tree_and_cross_service || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    else
        echo " ${C_YEL}[!] Хранилище ${STORAGE_ROOT} еще не создано (будет инициализировано при установке или автоисправлении).${C_RES}"
        echo "-----------------------------------------------------------------------"
        TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
    fi

    # 1. Vaultwarden
    if is_module_enabled "vaultwarden" || [ -d /var/lib/vaultwarden ] || id vaultwarden >/dev/null 2>&1; then
        audit_single_service_permissions "vaultwarden" "Vaultwarden (Bitwarden)" "vaultwarden" "vaultwarden" "/var/lib/vaultwarden" "/var/lib/vaultwarden/db.sqlite3" "none" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 2. Forgejo
    if is_module_enabled "forgejo" || [ -d /var/lib/forgejo ] || id forgejo >/dev/null 2>&1; then
        FG_GRP_AUD=$(id -gn forgejo 2>/dev/null || echo "www-data")
        audit_single_service_permissions "forgejo" "Forgejo (Git Service)" "forgejo" "$FG_GRP_AUD" "/var/lib/forgejo" "/var/lib/forgejo/data/forgejo.db" "none" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 3. Navidrome
    if is_module_enabled "navidrome" || [ -d /var/lib/navidrome ] || id navidrome >/dev/null 2>&1; then
        audit_single_service_permissions "navidrome" "Navidrome (Music Server)" "navidrome" "navidrome ${MEDIA_GROUP}" "/var/lib/navidrome" "/var/lib/navidrome/navidrome.db" "ro_music" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 4. Jellyfin
    if is_module_enabled "jellyfin" || [ -d /var/lib/jellyfin ] || id jellyfin >/dev/null 2>&1; then
        audit_single_service_permissions "jellyfin" "Jellyfin (Unified Media)" "jellyfin" "jellyfin ${MEDIA_GROUP}" "/var/lib/jellyfin" "/var/lib/jellyfin/data/jellyfin.db" "rw_media" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 5. Samba
    if is_module_enabled "samba" || [ -f /etc/samba/smb.conf ] || id "${SMB_USER:-homelab}" >/dev/null 2>&1; then
        audit_single_service_permissions "samba" "Samba SMB2/3 Share" "${SMB_USER:-homelab}" "${MEDIA_GROUP}" "$STORAGE_ROOT" "N/A" "rw_all" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 6. yt-dlp Web UI
    if is_module_enabled "ytdlp" || [ -f "$YTDLP_WEB_SCRIPT" ] || id ytdlp >/dev/null 2>&1; then
        audit_single_service_permissions "ytdlp" "yt-dlp Web UI Downloader" "ytdlp" "${MEDIA_GROUP}" "$STORAGE_INC_YTDLP" "N/A" "rw_all" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 7. qBittorrent-nox
    if is_module_enabled "torrent" || [ -d /var/lib/qbittorrent ] || id qbittorrent >/dev/null 2>&1; then
        audit_single_service_permissions "torrent" "qBittorrent-nox" "qbittorrent" "${MEDIA_GROUP}" "/var/lib/qbittorrent" "/var/lib/qbittorrent/.config/qBittorrent/qBittorrent.conf" "rw_all" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 8. Caddy
    if is_module_enabled "caddy" || [ -d /var/lib/caddy ] || id caddy >/dev/null 2>&1; then
        audit_single_service_permissions "caddy" "Caddy HTTPS & Local PKI" "caddy" "caddy" "/var/lib/caddy" "/etc/caddy/Caddyfile" "none" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    # 9. Server-Code (VS Code)
    if is_module_enabled "code" || [ -d /var/lib/coder ] || id coder >/dev/null 2>&1; then
        audit_single_service_permissions "code" "Server-Code (VS Code Web)" "coder" "${MEDIA_GROUP}" "/var/lib/coder" "N/A" "rw_all" || TOTAL_ISSUES=$((TOTAL_ISSUES + $?))
    fi

    if [ "$TOTAL_ISSUES" -eq 0 ]; then
        echo "${C_GRN}[✓] ИТОГ АУДИТА ПРАВ: Все проверенные сервисы и каталоги настроены эталонно (проблем: 0)!${C_RES}"
        return 0
    else
        echo "${C_YEL}[!] ИТОГ АУДИТА ПРАВ: Обнаружено несоответствий: ${TOTAL_ISSUES}.${C_RES}"
        if [ "$AUTO_FIX_MODE" = "auto" ]; then
            repair_all_homelab_permissions "yes"
        elif [ "$AUTO_FIX_MODE" = "interactive" ] && [ -t 0 ]; then
            repair_all_homelab_permissions "ask"
        fi
        return 1
    fi
}

# ==============================================================================
# Универсальный диспетчер модулей Homelab (install / remove / start / stop / restart)
# ==============================================================================
homelab_module_dispatch() {
    MOD_ID="$1"
    MOD_ACT="$2"
    init_homelab_registry

    MOD_SVC=$(get_module_field "$MOD_ID" 3)
    MOD_TITLE=$(get_module_field "$MOD_ID" 7)
    if [ -z "$MOD_TITLE" ]; then
        echo "${C_RED}[X] Неизвестный модуль: ${MOD_ID}${C_RES}"
        return 1
    fi

    case "$MOD_ACT" in
        install)
            case "$MOD_ID" in
                caddy)       install_module_caddy ;;
                samba)       install_module_samba "interactive" ;;
                vaultwarden) install_module_vaultwarden ;;
                forgejo)     install_module_forgejo ;;
                code)        install_module_code ;;
                navidrome)   install_module_navidrome ;;
                jellyfin)    install_module_jellyfin ;;
                ytdlp)       install_module_ytdlp ;;
                torrent)     install_module_torrent ;;
                *)           echo "${C_RED}[X] Неизвестный модуль: ${MOD_ID}${C_RES}"; return 1 ;;
            esac
            ;;
        remove)
            case "$MOD_ID" in
                caddy)       remove_module_caddy ;;
                samba)       remove_module_samba ;;
                vaultwarden) remove_module_vaultwarden ;;
                forgejo)     remove_module_forgejo ;;
                code)        remove_module_code ;;
                navidrome)   remove_module_navidrome ;;
                jellyfin)    remove_module_jellyfin ;;
                ytdlp)       remove_module_ytdlp ;;
                torrent)     remove_module_torrent ;;
                *)           echo "${C_RED}[X] Неизвестный модуль: ${MOD_ID}${C_RES}"; return 1 ;;
            esac
            ;;
        start|stop|restart)
            if [ -n "$MOD_SVC" ]; then
                if service_ctl "$MOD_SVC" "$MOD_ACT"; then
                    [ "$MOD_ID" = "samba" ] && { service_ctl wsdd "$MOD_ACT" || true; service_ctl avahi-daemon "$MOD_ACT" || true; }
                    echo "${C_GRN}[✓] Модуль ${MOD_TITLE} (${MOD_SVC}): действие '${MOD_ACT}' выполнено успешно.${C_RES}"
                else
                    echo "${C_RED}[X] Модуль ${MOD_TITLE} (${MOD_SVC}): ошибка при выполнении '${MOD_ACT}'!${C_RES}"
                    return 1
                fi
            fi
            ;;
        update)
            echo "${C_CYN}[*] Обновление модуля ${MOD_TITLE}...${C_RES}"
            ensure_alpine_community_repo
            apk update >/dev/null 2>&1 || true
            case "$MOD_ID" in
                caddy)       apk upgrade caddy caddy-openrc ;;
                samba)       apk upgrade samba-server samba-common-tools wsdd avahi ;;
                vaultwarden) apk upgrade vaultwarden vaultwarden-openrc vaultwarden-web-vault && sync_vaultwarden_config ;;
                forgejo)     apk upgrade forgejo forgejo-openrc ;;
                code)        rm -f /opt/code-server/code; install_module_code ;;
                navidrome)   apk upgrade navidrome navidrome-openrc ffmpeg ;;
                jellyfin)    apk upgrade jellyfin jellyfin-openrc jellyfin-web jellyfin-ffmpeg ;;
                ytdlp)       apk upgrade yt-dlp py3-yt-dlp ffmpeg ;;
                torrent)     apk upgrade qbittorrent-nox qbittorrent-nox-openrc ;;
            esac
            if [ -n "$MOD_SVC" ]; then
                if service_ctl "$MOD_SVC" restart; then
                    echo "${C_GRN}[✓] Модуль ${MOD_TITLE} успешно обновлен и перезапущен.${C_RES}"
                else
                    echo "${C_RED}[X] Модуль ${MOD_TITLE} обновлен, но не смог перезапуститься!${C_RES}"
                    return 1
                fi
            fi
            ;;
    esac
    return 0
}

# ==============================================================================
# Единый модуль резервного копирования (Шлюз + БД SQLite + Caddy PKI + Конфиги)
# ==============================================================================
create_unified_backup() {
    INCLUDE_MEDIA="${1:-no}"
    STAGE_DIR="/var/lib/gateway_backup_stage"
    rm -rf "$STAGE_DIR"
    mkdir -p "${STAGE_DIR}/sqlite_dumps"
    chmod 700 "$STAGE_DIR" 2>/dev/null || true

    echo "${C_CYN}[*] Подготовка консистентной резервной копии (Шлюз + Homelab)...${C_RES}"

    # 1. Горячее безопасное резервное копирование всех баз SQLite через sqlite3 .backup
    if command -v sqlite3 >/dev/null 2>&1; then
        [ -f /var/lib/vaultwarden/db.sqlite3 ] && \
            sqlite3 /var/lib/vaultwarden/db.sqlite3 ".backup '${STAGE_DIR}/sqlite_dumps/vaultwarden.sqlite3'" 2>/dev/null || true
        [ -f /var/lib/forgejo/data/forgejo.db ] && \
            sqlite3 /var/lib/forgejo/data/forgejo.db ".backup '${STAGE_DIR}/sqlite_dumps/forgejo.sqlite3'" 2>/dev/null || true
        [ -f /var/lib/navidrome/navidrome.db ] && \
            sqlite3 /var/lib/navidrome/navidrome.db ".backup '${STAGE_DIR}/sqlite_dumps/navidrome.sqlite3'" 2>/dev/null || true
        [ -f /var/lib/jellyfin/data/jellyfin.db ] && \
            sqlite3 /var/lib/jellyfin/data/jellyfin.db ".backup '${STAGE_DIR}/sqlite_dumps/jellyfin.sqlite3'" 2>/dev/null || true
    fi

    # 2. Сбор всех конфигурационных директорий, секретов и локального CA Caddy
    BACKUP_PATHS="/etc/sing-box"
    [ -f "$AGH_CONF" ] && BACKUP_PATHS="$BACKUP_PATHS $AGH_CONF"
    [ -f "$ALPINE_NFT_CONF" ] && BACKUP_PATHS="$BACKUP_PATHS $ALPINE_NFT_CONF"
    [ -d /etc/caddy ] && BACKUP_PATHS="$BACKUP_PATHS /etc/caddy"
    [ -d /var/lib/caddy ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/caddy"
    [ -d /etc/samba ] && BACKUP_PATHS="$BACKUP_PATHS /etc/samba"
    [ -d /var/lib/samba/private ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/samba/private"
    [ -f /etc/conf.d/vaultwarden ] && BACKUP_PATHS="$BACKUP_PATHS /etc/conf.d/vaultwarden"
    [ -d /var/lib/vaultwarden ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/vaultwarden"
    [ -d /etc/forgejo ] && BACKUP_PATHS="$BACKUP_PATHS /etc/forgejo"
    [ -d /etc/navidrome ] && BACKUP_PATHS="$BACKUP_PATHS /etc/navidrome"
    [ -d /etc/jellyfin ] && BACKUP_PATHS="$BACKUP_PATHS /etc/jellyfin"
    [ -d /var/lib/qbittorrent/.config ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/qbittorrent/.config"
    [ "$INCLUDE_MEDIA" = "yes" ] && [ -d "$STORAGE_ROOT" ] && BACKUP_PATHS="$BACKUP_PATHS $STORAGE_ROOT"

    umask 077
    # shellcheck disable=SC2086
    if ! tar --exclude='*cache.db*' -czf "${BACKUP_ARCHIVE}.tmp.$$" $BACKUP_PATHS "$STAGE_DIR" 2>/dev/null; then
        rm -rf "$STAGE_DIR" "${BACKUP_ARCHIVE}.tmp.$$"
        umask 022
        echo "${C_RED}[X] Ошибка создания архива резервной копии!${C_RES}"
        return 1
    fi
    rm -rf "$STAGE_DIR"
    chmod 600 "${BACKUP_ARCHIVE}.tmp.$$" 2>/dev/null || true
    mv -f "${BACKUP_ARCHIVE}.tmp.$$" "$BACKUP_ARCHIVE"
    chmod 600 "$BACKUP_ARCHIVE" 2>/dev/null || true
    umask 022

    B_SIZE=$(du -sh "$BACKUP_ARCHIVE" 2>/dev/null | awk '{print $1}' || echo "н/д")
    echo "${C_GRN}[✓] Единый архив бэкапа успешно создан: ${BACKUP_ARCHIVE} (размер: ${B_SIZE})${C_RES}"
    return 0
}

restore_unified_backup() {
    if [ ! -f "$BACKUP_ARCHIVE" ]; then
        echo "${C_RED}[X] Файл бэкапа ${BACKUP_ARCHIVE} не найден!${C_RES}"
        return 1
    fi
    if ! tar -tzf "$BACKUP_ARCHIVE" >/dev/null 2>&1; then
        echo "${C_RED}[X] Ошибка: Архив ${BACKUP_ARCHIVE} поврежден!${C_RES}"
        return 1
    fi

    echo "${C_CYN}[*] Восстановление конфигурации шлюза и сервисов Homelab из ${BACKUP_ARCHIVE}...${C_RES}"
    service_ctl sing-box stop
    service_ctl adguardhome stop
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            [ "$M_EN" = "yes" ] && [ -n "$M_SVC" ] && service_ctl "$M_SVC" stop || true
        done < "$HOMELAB_STATE"
    fi
    rm -f /etc/sing-box/cache.db 2>/dev/null || true

    tar -xzf "$BACKUP_ARCHIVE" -C / 2>/dev/null || true

    # Восстановление консистентных SQLite-дампов поверх распакованных баз
    STAGE_RESTORE="/var/lib/gateway_backup_stage/sqlite_dumps"
    if [ -d "$STAGE_RESTORE" ]; then
        if [ -f "${STAGE_RESTORE}/vaultwarden.sqlite3" ]; then
            rm -f /var/lib/vaultwarden/db.sqlite3-wal /var/lib/vaultwarden/db.sqlite3-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/vaultwarden.sqlite3" /var/lib/vaultwarden/db.sqlite3 2>/dev/null || true
        fi
        if [ -f "${STAGE_RESTORE}/forgejo.sqlite3" ]; then
            rm -f /var/lib/forgejo/data/forgejo.db-wal /var/lib/forgejo/data/forgejo.db-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/forgejo.sqlite3" /var/lib/forgejo/data/forgejo.db 2>/dev/null || true
        fi
        if [ -f "${STAGE_RESTORE}/navidrome.sqlite3" ]; then
            rm -f /var/lib/navidrome/navidrome.db-wal /var/lib/navidrome/navidrome.db-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/navidrome.sqlite3" /var/lib/navidrome/navidrome.db 2>/dev/null || true
        fi
        if [ -f "${STAGE_RESTORE}/jellyfin.sqlite3" ]; then
            rm -f /var/lib/jellyfin/data/jellyfin.db-wal /var/lib/jellyfin/data/jellyfin.db-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/jellyfin.sqlite3" /var/lib/jellyfin/data/jellyfin.db 2>/dev/null || true
        fi
        rm -rf "/var/lib/gateway_backup_stage" 2>/dev/null || true
    fi

    chmod 600 "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" "$AGH_CONF" 2>/dev/null || true
    umask 022

    load_gateway_env
    repair_all_homelab_permissions "yes" >/dev/null 2>&1 || true
    sync_user_domain_rulesets
    sync_dns_firewall "yes" "keep"
    service_ctl sing-box start || true
    service_ctl adguardhome start || true

    # Перезапуск активных модулей Homelab после восстановления
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            if [ "$M_EN" = "yes" ] && [ -x "/etc/init.d/${M_SVC}" ]; then
                service_ctl "$M_SVC" enable
                service_ctl "$M_SVC" restart || true
            fi
        done < "$HOMELAB_STATE"
    fi
    build_pki_portal
    echo "${C_GRN}[✓] Система (Шлюз + Homelab + БД SQLite + локальный CA Caddy) успешно восстановлена!${C_RES}"
    return 0
}
# ==================== [ КОНЕЦ ЧАСТИ 5 ИЗ 6 ] =====================


# ==================== [ НАЧАЛО ЧАСТИ 6 ИЗ 6 ] ====================
# ==============================================================================
# Диагностика Homelab, Мастер установки, Меню Homelab (Пункт 13) и Главное меню
# ==============================================================================

# Сводная таблица всех модулей Homelab (статус установки, OpenRC, порт и домен)
print_homelab_services_table() {
    init_homelab_registry
    echo "${C_CYN}=== Реестр модулей домашнего сервера (Alpine Homelab Stack) ===${C_RES}"
    awk -F'|' -v c_cyn="$C_CYN" -v c_grn="$C_GRN" -v c_dim="$C_DIM" -v c_yel="$C_YEL" -v c_res="$C_RES" '
        $1 !~ /^#/ && NF >= 7 {
            idx++
            id = $1; en = $2; svc = $3; port = $4; dom = $5; title = $7
            st = (en == "yes") ? c_grn "[УСТАНОВЛЕН]" c_res : c_dim "[НЕ АКТИВЕН]" c_res
            url = (dom != "_") ? "https://" dom : "SMB :445 (LAN)"
            if (id == "caddy") url = "http://ca.lan (PKI)"
            printf "  %s[%d]%s %-12s %-22s | Порт: %-5s | %-24s | %s\n", c_cyn, idx, c_res, id, st, port, url, title
        }
    ' "$HOMELAB_STATE" 2>/dev/null || true
    echo "---------------------------------------------------------------"
    return 0
}

# Глубокая проверка состояния подсистемы Homelab (Homelab Self-Test)
run_homelab_self_test() {
    init_homelab_registry
    load_gateway_env
    CUR_LIP=$(get_current_lan_ip)

    echo "${C_CYN}=== [Homelab Self-Test] Диагностика домашнего сервера ===${C_RES}"
    if [ -d "$STORAGE_ROOT" ]; then
        ST_PERM=$(stat -c "%a %U:%G" "$STORAGE_ROOT" 2>/dev/null || echo "н/д")
        echo "${C_GRN}[✓]${C_RES} Единое хранилище (${STORAGE_ROOT}): ${C_GRN}ДОСТУПНО${C_RES} (права: ${ST_PERM})"
    else
        echo "${C_YEL}[!]${C_RES} Единое хранилище (${STORAGE_ROOT}): еще не инициализировано"
    fi

    if find_caddy_root_cert; then
        echo "${C_GRN}[✓]${C_RES} Локальный Root CA Caddy: ${C_GRN}СГЕНЕРИРОВАН${C_RES} (портал: http://${DOM_CA} / http://${CUR_LIP})"
        echo "${C_GRN}[✓]${C_RES} Панели шлюза по HTTPS: ${C_CYN}https://${DOM_ZASHBOARD}${C_RES} | ${C_CYN}https://${DOM_ADGUARD}${C_RES}"
    else
        echo "${C_DIM}[i]${C_RES} Локальный Root CA Caddy: не активен (установите модуль caddy)"
    fi

    while IFS='|' read -r M_ID M_EN M_SVC M_PORT M_DOM _M_USR M_TITLE; do
        case "$M_ID" in ''|\#*) continue ;; esac
        [ "$M_EN" = "yes" ] || continue

        if rc-service "$M_SVC" status >/dev/null 2>&1; then
            SVC_TXT="${C_GRN}ЗАПУЩЕН${C_RES}"
        else
            SVC_TXT="${C_RED}ОСТАНОВЛЕН${C_RES}"
        fi

        if [ "$M_ID" = "samba" ]; then
            WSDD_ST=$(rc-service wsdd status >/dev/null 2>&1 && echo "WSDD:OK" || echo "WSDD:OFF")
            AVAHI_ST=$(rc-service avahi-daemon status >/dev/null 2>&1 && echo "Avahi:OK" || echo "Avahi:OFF")
            PDB_ST="PDB:OK"
            if command -v pdbedit >/dev/null 2>&1; then
                pdbedit -L -w "${SMB_USER:-homelab}" 2>/dev/null | grep -q "^${SMB_USER:-homelab}:" || PDB_ST="PDB:FAIL"
            fi
            echo " • [${M_ID}] ${M_TITLE}: ${SVC_TXT} | Пользователь: ${SMB_USER:-homelab} (${PDB_ST}) | LAN: ${C_CYN}${WSDD_ST}, ${AVAHI_ST}${C_RES}"
        elif [ "$M_ID" = "caddy" ]; then
            echo " • [${M_ID}] ${M_TITLE}: ${SVC_TXT} | HTTPS :443 / PKI :80"
        elif [ "$M_ID" = "vaultwarden" ]; then
            HTTP_CODE=$(curl -k -o /dev/null -sS --connect-timeout 2 -m 3 -w '%{http_code}' "http://127.0.0.1:${M_PORT}/api/config" 2>/dev/null || echo "000")
            WV_ST="WebVault:OK"
            detect_vaultwarden_web_dir >/dev/null 2>&1 || WV_ST="WebVault:FAIL"
            echo " • [${M_ID}] ${M_TITLE}: ${SVC_TXT} | 127.0.0.1:${M_PORT} (API HTTP ${HTTP_CODE}, ${WV_ST}) -> ${C_CYN}https://${M_DOM}${C_RES}"
        else
            HTTP_CODE=$(curl -k -o /dev/null -sS --connect-timeout 2 -m 3 -w '%{http_code}' "http://127.0.0.1:${M_PORT}" 2>/dev/null || echo "000")
            echo " • [${M_ID}] ${M_TITLE}: ${SVC_TXT} | 127.0.0.1:${M_PORT} (HTTP ${HTTP_CODE}) -> ${C_CYN}https://${M_DOM}${C_RES}"
        fi
    done < "$HOMELAB_STATE"
    echo "---------------------------------------------------------------"
    return 0
}

# Мастер выбора модулей Homelab при первоначальной установке или доустановке
prompt_homelab_modules_wizard() {
    PRE_SEL="${1:-}"
    init_homelab_registry
    if [ "$PRE_SEL" = "__SKIP__" ]; then
        return 0
    elif [ -n "$PRE_SEL" ]; then
        HL_SEL="$PRE_SEL"
    else
        echo ""
        echo "${C_CYN}=== Выбор модулей домашнего сервера (Homelab & Media Stack) ===${C_RES}"
        echo " Вы можете сразу установить нужные домашние сервисы (или пропустить этот шаг):"
        echo "  ${C_CYN}[1]${C_RES} caddy       — Центральный HTTPS Reverse Proxy & Локальный CA (*.lan)"
        echo "  ${C_CYN}[2]${C_RES} samba       — Общая сетевая папка SMB2/3 + автообнаружение Windows 11 / Linux"
        echo "  ${C_CYN}[3]${C_RES} vaultwarden — Менеджер паролей Bitwarden (https://vaultwarden.lan)"
        echo "  ${C_CYN}[4]${C_RES} forgejo     — Локальный Git-сервер (https://forgejo.lan)"
        echo "  ${C_CYN}[5]${C_RES} code        — VS Code в браузере Server-Code (https://code.lan)"
        echo "  ${C_CYN}[6]${C_RES} navidrome   — Музыкальный стриминг Subsonic/Spotify-style (https://music.lan)"
        echo "  ${C_CYN}[7]${C_RES} jellyfin    — Домашний кинотеатр Jellyfin (https://jellyfin.lan)"
        echo "  ${C_CYN}[8]${C_RES} ytdlp       — Веб-панель загрузки видео и музыки yt-dlp (https://downloads.lan)"
        echo "  ${C_CYN}[9]${C_RES} torrent     — Торрент-клиент qBittorrent-nox + Hardlink-импорт (https://torrents.lan)"
        echo "---------------------------------------------------------------"
        printf "Введите номера через пробел (например: 1 2 3 6 8 9), 'all' для всех или Enter (только шлюз): "
        read -r HL_SEL < /dev/tty || true
    fi
    HL_SEL=$(printf "%s" "$HL_SEL" | tr ',' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$HL_SEL" ] || [ "$HL_SEL" = "0" ] || [ "$HL_SEL" = "none" ] && return 0

    if [ "$HL_SEL" = "all" ] || [ "$HL_SEL" = "ALL" ]; then
        HL_SEL="1 2 3 4 5 6 7 8 9"
    fi

    init_homelab_storage
    # Если выбран любой веб-модуль (3..9), автоматически устанавливаем Caddy первым
    NEED_CADDY="no"
    for ITEM in $HL_SEL; do
        case "$ITEM" in
            1|caddy|3|vaultwarden|4|forgejo|5|code|6|navidrome|7|jellyfin|8|ytdlp|9|torrent)
                NEED_CADDY="yes"
                ;;
        esac
    done
    if [ "$NEED_CADDY" = "yes" ] && ! is_module_enabled "caddy"; then
        install_module_caddy || true
    fi

    for ITEM in $HL_SEL; do
        case "$ITEM" in
            1|caddy)       is_module_enabled "caddy" || install_module_caddy || true ;;
            2|samba)       install_module_samba "auto" || true ;;
            3|vaultwarden) install_module_vaultwarden || true ;;
            4|forgejo)     install_module_forgejo || true ;;
            5|code)        install_module_code || true ;;
            6|navidrome)   install_module_navidrome || true ;;
            7|jellyfin)    install_module_jellyfin || true ;;
            8|ytdlp)       install_module_ytdlp || true ;;
            9|torrent)     install_module_torrent || true ;;
        esac
    done

    if is_module_enabled "caddy"; then
        show_https_ca_instructions
    fi
    return 0
}

# ==============================================================================
# Главный мастер установки и настройки (Эксклюзивно Alpine Linux Homelab Edition)
# ==============================================================================
run_installer() {
    umask 022
    detect_os
    disable_legacy_mihomo
    init_user_lists
    init_homelab_registry

    echo "${C_CYN}========================================================${C_RES}"
    echo "${C_BLD} Установщик Sing-Box Extended + AdGuard Home + Homelab  ${C_RES}"
    echo "${C_CYN}========================================================${C_RES}"
    echo "Система: ${OS_NAME} [${ARCH_RAW} -> ${SB_ARCH}]"
    echo "Память:  ${TOTAL_RAM_MB} МБ RAM (Лимит SB: ${SB_GOMEMLIMIT}, AGH: ${AGH_GOMEMLIMIT})"
    echo "--------------------------------------------------------"

    load_gateway_env
    SAVED_LAN_IP=$(get_current_lan_ip)
    SAVED_SUB_URL="$SUB_URL"
    SAVED_GW_IP="$GW_IP"
    SAVED_PASS="$ADMIN_PASS"
    SAVED_AGH_USER=""

    if [ -f "$AGH_CONF" ]; then
        SAVED_AGH_USER=$(sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "$AGH_CONF" | head -n 1 | tr -d ' \t\r\n"')
    fi

    # 1. Запрос ссылки на подписку, прямого ключа или бесплатного гибридного WARP
    USE_INITIAL_WARP="no"
    if [ -n "$SAVED_SUB_URL" ]; then
        printf "Введите подписку (http://...), ключ (vless://...) или 'warp' [Enter = оставить %s]: " "$SAVED_SUB_URL"
    elif has_my_nodes; then
        printf "Введите подписку (http://...), ключ или 'warp' [Enter = оставить ключи в my_nodes.yaml]: "
    elif is_warp_enabled; then
        printf "Введите подписку (http://...), ключ или 'warp' [Enter = оставить текущий Amnezia WARP]: "
    else
        printf "Введите подписку (http://...), ключ (vless://...) или 'warp' (бесплатный WARP 2.0 + MASQUE H2): "
    fi
    read -r INPUT_SUB_URL < /dev/tty || true
    INPUT_SUB_URL=$(printf "%s" "$INPUT_SUB_URL" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -n "$INPUT_SUB_URL" ]; then
        apply_subscription_input "$INPUT_SUB_URL"
    elif [ -z "$SAVED_SUB_URL" ] && ! has_my_nodes && ! is_warp_enabled; then
        printf "Прокси не указаны. Сгенерировать бесплатный безлимитный Amnezia WARP 2.0 + MASQUE H2? (y/n) [Enter = y]: "
        read -r WARP_FALLBACK < /dev/tty || true
        WARP_FALLBACK=$(printf "%s" "$WARP_FALLBACK" | tr -d ' \t\r\n')
        [ -z "$WARP_FALLBACK" ] && WARP_FALLBACK="y"
        case "$WARP_FALLBACK" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа])
                USE_INITIAL_WARP="yes"
                ;;
            *)
                echo "Бро я не буду этого делать без подписки или ключа ,_."
                exit 1
                ;;
        esac
    fi

    if [ "$USE_INITIAL_WARP" = "yes" ]; then
        printf "Если есть ключ лицензии WARP+ (Argo), вставьте его [Enter = обычный бесплатный WARP]: "
        read -r INPUT_WLIC < /dev/tty || true
        INPUT_WLIC=$(printf "%s" "$INPUT_WLIC" | tr -d ' \t\r\n')
        [ -n "$INPUT_WLIC" ] && WARP_LICENSE="$INPUT_WLIC" || true
    fi

    if [ "$USE_INITIAL_WARP" != "yes" ] && [ -n "$INPUT_SUB_URL" ] && is_warp_enabled; then
        printf "Обнаружен ранее созданный пул Amnezia WARP. Оставить его как резерв? (y/n) [Enter = y]: "
        read -r KEEP_WARP_ANS < /dev/tty || true
        KEEP_WARP_ANS=$(printf "%s" "$KEEP_WARP_ANS" | tr -d ' \t\r\n')
        [ -z "$KEEP_WARP_ANS" ] && KEEP_WARP_ANS="y"
        case "$KEEP_WARP_ANS" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) ;;
            *) echo '{"outbounds": []}' > "$WARP_NODES_FILE" ;;
        esac
    fi

    # 2. Запрос IP-адреса самого сервера и IP основного роутера
    printf "Введите локальный IP самого сервера (%s) [Enter = оставить %s]: " "$OS_NAME" "$SAVED_LAN_IP"
    read -r INPUT_LAN_IP < /dev/tty || true
    INPUT_LAN_IP=$(printf "%s" "$INPUT_LAN_IP" | tr -d ' \t\r\n')
    TARGET_LAN_IP="${INPUT_LAN_IP:-$SAVED_LAN_IP}"
    if ! is_valid_ipv4 "$TARGET_LAN_IP"; then
        echo "${C_RED}[X] Некорректный IP (${TARGET_LAN_IP}), оставлен текущий: ${SAVED_LAN_IP}${C_RES}"
        TARGET_LAN_IP="$SAVED_LAN_IP"
    fi

    if [ -n "$SAVED_GW_IP" ] && [ "$SAVED_GW_IP" != "$TARGET_LAN_IP" ]; then
        printf "Введите IP основного роутера [Enter = %s]: " "$SAVED_GW_IP"
    else
        printf "Введите IP-адрес основного роутера (отличный от %s, например %s.1): " "$TARGET_LAN_IP" "${TARGET_LAN_IP%.*}"
    fi
    read -r INPUT_GW_IP < /dev/tty || true
    INPUT_GW_IP=$(printf "%s" "$INPUT_GW_IP" | tr -d ' \t\r\n')

    if [ -n "$INPUT_GW_IP" ]; then
        GW_IP="$INPUT_GW_IP"
    else
        GW_IP="$SAVED_GW_IP"
    fi

    if ! is_valid_ipv4 "$GW_IP" || [ "$GW_IP" = "$TARGET_LAN_IP" ]; then
        echo "${C_RED}[X] Ошибка: IP основного роутера (${GW_IP}) некорректен или совпадает с IP сервера (${TARGET_LAN_IP})!${C_RES}"
        exit 1
    fi

    # 3. Запрос логина и единого пароля (AdGuard Home + Sing-Box Zashboard + Homelab)
    DEF_AGH_USER="${SAVED_AGH_USER:-admin}"
    printf "Введите логин для панели AdGuard Home [Enter = %s]: " "$DEF_AGH_USER"
    read -r INPUT_AGH_USER < /dev/tty || true
    INPUT_AGH_USER=$(printf "%s" "$INPUT_AGH_USER" | tr -d ' \t\r\n')
    AGH_USER="${INPUT_AGH_USER:-$DEF_AGH_USER}"

    if [ -n "$SAVED_PASS" ]; then
        printf "Введите единый пароль (Шлюз + AdGuard + Homelab) [Enter = оставить текущий]: "
    else
        printf "Введите единый пароль (для AdGuard Home, Sing-Box и сервисов Homelab): "
    fi
    read -r INPUT_PASS < /dev/tty || true
    INPUT_PASS=$(printf "%s" "$INPUT_PASS" | tr -d '\\r\\n')

    ADMIN_PASS="${INPUT_PASS:-$SAVED_PASS}"
    if [ -z "$ADMIN_PASS" ]; then
        echo "${C_RED}[X] Ошибка: Пароль не может быть пустым!${C_RES}"
        exit 1
    fi
    # Единый логин и пароль из начального опроса автоматически применяются для Samba и всех сервисов Homelab
    SMB_USER="$AGH_USER"
    SMB_PASS="$ADMIN_PASS"

    save_gateway_env
    save_homelab_env
    if command -v smbpasswd >/dev/null 2>&1 && id "$SMB_USER" >/dev/null 2>&1; then
        apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS" >/dev/null 2>&1 || true
    fi

    # 4. Запрос на автообновление
    if is_autoupdate_enabled; then
        DEF_AU_CHAR="y"
    else
        DEF_AU_CHAR="n"
    fi
    printf "Включить автообновление ядер и панелей в 04:00 (Бро я думаю ты осознаешь последствия ,_,)? (y/n) [Enter = %s]: " "$DEF_AU_CHAR"
    read -r INPUT_AU_ANS < /dev/tty || true
    INPUT_AU_ANS=$(printf "%s" "$INPUT_AU_ANS" | tr -d ' \t\r\n')
    [ -z "$INPUT_AU_ANS" ] && INPUT_AU_ANS="$DEF_AU_CHAR"
    case "$INPUT_AU_ANS" in
        [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) ENABLE_AU="yes" ;;
        *) ENABLE_AU="no" ;;
    esac

    # 5. Запрос выбора модулей Homelab сразу на старте (чтобы установка шла полностью без остановок)
    echo ""
    echo "${C_CYN}=== Выбор модулей домашнего сервера (Homelab & Media Stack) ===${C_RES}"
    echo " Вы можете сразу выбрать нужные домашние сервисы (логин/пароль Samba и сервисов = ${AGH_USER}):"
    echo "  ${C_CYN}[1]${C_RES} caddy       — Центральный HTTPS Reverse Proxy & Локальный CA (*.lan)"
    echo "  ${C_CYN}[2]${C_RES} samba       — Общая сетевая папка SMB2/3 + автообнаружение Windows 11 / Linux"
    echo "  ${C_CYN}[3]${C_RES} vaultwarden — Менеджер паролей Bitwarden (https://vaultwarden.lan)"
    echo "  ${C_CYN}[4]${C_RES} forgejo     — Локальный Git-сервер (https://forgejo.lan)"
    echo "  ${C_CYN}[5]${C_RES} code        — VS Code в браузере Server-Code (https://code.lan)"
    echo "  ${C_CYN}[6]${C_RES} navidrome   — Музыкальный стриминг Subsonic/Spotify-style (https://music.lan)"
    echo "  ${C_CYN}[7]${C_RES} jellyfin    — Домашний кинотеатр Jellyfin (https://jellyfin.lan)"
    echo "  ${C_CYN}[8]${C_RES} ytdlp       — Веб-панель загрузки видео и музыки yt-dlp (https://downloads.lan)"
    echo "  ${C_CYN}[9]${C_RES} torrent     — Торрент-клиент qBittorrent-nox + Hardlink-импорт (https://torrents.lan)"
    echo "---------------------------------------------------------------"
    printf "Введите номера через пробел (например: 1 2 3 6 8 9), 'all' для всех или Enter (только шлюз): "
    read -r PRE_HL_SEL < /dev/tty || true
    PRE_HL_SEL=$(printf "%s" "$PRE_HL_SEL" | tr ',' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$PRE_HL_SEL" ] || [ "$PRE_HL_SEL" = "0" ] || [ "$PRE_HL_SEL" = "none" ] && PRE_HL_SEL="__SKIP__"

    echo "--------------------------------------------------------"
    echo "Итоговая конфигурация развертывания:"
    echo " - ОС и Память:     ${OS_NAME} | ${TOTAL_RAM_MB} МБ RAM"
    echo " - Ядро шлюза:      shtorm-7/sing-box-extended (${SB_ARCH}, лимит ${SB_GOMEMLIMIT})"
    echo " - IP сервера (LAN):${TARGET_LAN_IP} (интерфейс $(get_lan_ifname), маска /24)"
    echo " - Основной роутер: ${GW_IP}"
    echo " - DNS и Домены:    AdGuard Home (0.0.0.0:53 + *.lan) -> Sing-Box (127.0.0.1:1053)"
    echo " - Хранилище:       ${STORAGE_ROOT} (Music, Videos/Movies, Videos/Series, Downloads)"
    echo " - Единый логин:    ${AGH_USER} (AdGuard + Samba + Homelab) / Пароль: [СКРЫТ]"
    echo " - Модули Homelab:  ${PRE_HL_SEL}"
    echo "--------------------------------------------------------"

    sync_clock() {
        echo "Синхронизация системных часов..."
        /usr/sbin/ntpd -n -q -p 162.159.200.1 -p 216.239.35.0 -p ntp.ix.ru -p pool.ntp.org 2>/dev/null || true
        if [ "$(date +%Y)" -lt 2026 ]; then
            TS=$(wget -qO- "http://1.1.1.1/cdn-cgi/trace" 2>/dev/null | awk -F= '/^ts=/ {split($2,a,"."); print a[1]}')
            [ -n "$TS" ] && date -s "@$TS" >/dev/null 2>&1 || true
        fi
        hwclock -w -u 2>/dev/null || true
        rc-update add ntpd default >/dev/null 2>&1 || true
        rc-service ntpd start >/dev/null 2>&1 || true
        return 0
    }

    # ЭТАП 1: Настройка сети, синхронизация времени и установка базовых пакетов Alpine Linux
    write_resolv_conf "nameserver ${GW_IP}
nameserver 77.88.8.8
nameserver 77.88.8.1"

    LAN_IF_INIT=$(get_lan_ifname)
    ip -4 route show default 2>/dev/null | grep -q "default" || \
        ip -4 route add default via "$GW_IP" dev "$LAN_IF_INIT" 2>/dev/null || true

    sync_clock
    ensure_alpine_community_repo

    echo "Проверка и установка базовых пакетов Alpine Linux..."
    ALP_PKGS="ca-certificates curl gzip tar jq iproute2 conntrack-tools wireguard-tools-wg apache2-utils nftables tzdata sqlite acl"
    apk update >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    apk add $ALP_PKGS || true
    disable_apache_daemon
    ensure_alpine_modules

    if [ -f /usr/share/zoneinfo/Europe/Moscow ] && [ ! -f /etc/localtime ]; then
        cp -f /usr/share/zoneinfo/Europe/Moscow /etc/localtime 2>/dev/null || true
        echo "Europe/Moscow" > /etc/timezone 2>/dev/null || true
    fi

    write_alpine_static_interfaces "$LAN_IF_INIT" "$TARGET_LAN_IP" "$GW_IP"
    if [ "$TARGET_LAN_IP" = "$SAVED_LAN_IP" ]; then
        killall -9 udhcpc >/dev/null 2>&1 || true
        ip -4 addr replace "${TARGET_LAN_IP}/24" dev "$LAN_IF_INIT" 2>/dev/null || true
        ip link set "$LAN_IF_INIT" up 2>/dev/null || true
        ip -4 route replace default via "$GW_IP" dev "$LAN_IF_INIT" 2>/dev/null || true
    fi

    CURRENT_IP="$TARGET_LAN_IP"

    mkdir -p /etc/sysctl.d
    cat << SYS_EOF > /etc/sysctl.d/99-gateway-forward.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 0
net.core.default_qdisc = fq_codel
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_max = ${SYS_BUF_MAX}
net.core.wmem_max = ${SYS_BUF_MAX}
net.netfilter.nf_conntrack_max = ${SYS_CONNTRACK_MAX}
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 180
net.ipv4.tcp_congestion_control = bbr
fs.inotify.max_user_watches = 524288
net.ipv4.ip_unprivileged_port_start = 0
SYS_EOF

    sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || true
    sync_dns_firewall "yes" "keep"

    if [ "$USE_INITIAL_WARP" = "yes" ]; then
        generate_amnezia_warp "${WARP_LICENSE:-}" || true
    fi

    # ЭТАП 2: Загрузка/обновление ядер Sing-Box Extended и AdGuard Home
    update_cores_only "no"

    # ЭТАП 3: Генерация конфига Sing-Box Extended и установка веб-панели Zashboard
    service_ctl sing-box stop
    if [ ! -f "${SB_DIR}/ui/index.html" ]; then
        install_zashboard_ui || true
    else
        echo "${C_GRN}[✓] Веб-панель Zashboard уже установлена.${C_RES}"
    fi
    generate_singbox_config

    # ЭТАП 4: Настройка AdGuard Home с автоматической поддержкой локальных доменов *.lan
    echo "Генерация bcrypt-хэша пароля..."
    AGH_PASS_HASH=""
    if command -v htpasswd >/dev/null 2>&1; then
        AGH_PASS_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH=$(htpasswd -nbBC 10 "$AGH_USER" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true) || true
    fi
    disable_apache_daemon
    [ -z "$AGH_PASS_HASH" ] && { echo "${C_RED}[X] Ошибка генерации bcrypt-хэша!${C_RES}"; exit 1; }

    service_ctl adguardhome stop
    mkdir -p /etc/AdGuardHome/data

    if [ -f "$AGH_CONF" ]; then
        awk -v u="$AGH_USER" -v h="$AGH_PASS_HASH" -v gw="$GW_IP" '
            /^users:/ {
                print "users:"
                print "  - name: " u
                print "    password: " h
                in_users=1; next
            }
            in_users && /^[^[:space:]]/ { in_users=0 }
            in_users { next }
            /^[[:space:]]*upstream_dns:/ {
                print "  upstream_dns: [127.0.0.1:1053]"
                in_list=1; next
            }
            /^[[:space:]]*bootstrap_dns:/ {
                print "  bootstrap_dns: [" gw ", 77.88.8.8, 77.88.8.1]"
                in_list=1; next
            }
            /^[[:space:]]*local_ptr_upstreams:/ {
                print "  local_ptr_upstreams: [" gw ":53]"
                in_list=1; next
            }
            in_list && /^[[:space:]]*-/ { next }
            in_list { in_list=0 }
            { print }
        ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv "${AGH_CONF}.tmp" "$AGH_CONF"
        grep -q "aaaa_disabled:" "$AGH_CONF" 2>/dev/null || sed -i '/cache_size:/a \  aaaa_disabled: true' "$AGH_CONF" 2>/dev/null || true
        sync_agh_homelab_rewrites "$CURRENT_IP"
        chmod 600 "$AGH_CONF" 2>/dev/null || true
    else
        cat << AGH_EOF > "$AGH_CONF"
http:
  address: 0.0.0.0:3000
  session_ttl: 720h
users:
  - name: ${AGH_USER}
    password: ${AGH_PASS_HASH}
auth_attempts: 5
block_auth_min: 15
language: ru
theme: auto
dns:
  bind_hosts: [0.0.0.0]
  port: 53
  upstream_dns: [127.0.0.1:1053]
  bootstrap_dns: [${GW_IP}, 77.88.8.8, 77.88.8.1]
  upstream_mode: load_balance
  cache_enabled: false
  cache_size: 0
  aaaa_disabled: true
  enable_dnssec: false
  use_private_ptr_resolvers: true
  local_ptr_upstreams: [${GW_IP}:53]
  serve_plain_dns: true
  pending_requests: { enabled: true }
tls: { enabled: false }
querylog: { enabled: true, interval: 24h, file_enabled: false }
statistics: { enabled: true, interval: 24h }
filters:
  - { enabled: true, url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt, name: AdGuard DNS filter, id: 1 }
  - { enabled: true, url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt, name: AdAway Default Blocklist, id: 2 }
  - { enabled: true, url: https://filters.adtidy.org/extension/chromium/filters/1.txt, name: AdGuard Russian Filter, id: 3 }
filtering: { protection_enabled: true, filtering_enabled: true }
schema_version: 34
AGH_EOF
        sync_agh_homelab_rewrites "$CURRENT_IP"
        chmod 600 "$AGH_CONF" 2>/dev/null || true
    fi

    # ЭТАП 5: Регистрация и запуск служб шлюза
    setup_init_scripts

    write_resolv_conf "nameserver 127.0.0.1
nameserver ${GW_IP}
nameserver 77.88.8.8"

    enable_watchdog
    if [ "$ENABLE_AU" = "yes" ]; then
        enable_autoupdate
    else
        disable_autoupdate
    fi

    # ЭТАП 6: Автоматическая установка выбранных на старте модулей Homelab
    prompt_homelab_modules_wizard "${PRE_HL_SEL:-__SKIP__}"

    # ЭТАП 7: Итоговый Self-Test 2.0
    reload_singbox_api
    run_self_test

    echo "${C_CYN}========================================================${C_RES}"
    echo "${C_GRN} Развертывание на ${OS_NAME} успешно завершено!${C_RES}"
    echo " - IP-адрес сервера:   ${C_BLD}${CURRENT_IP}${C_RES} (интерфейс $(get_lan_ifname), маска /24)"
    echo " - Основной роутер:    ${GW_IP}"
    echo " - Панель Sing-Box:    ${C_CYN}https://${DOM_ZASHBOARD}${C_RES} (http://${CURRENT_IP}:9090/ui)"
    echo " - Панель AdGuard:     ${C_CYN}https://${DOM_ADGUARD}${C_RES} (http://${CURRENT_IP}:3000)"
    echo " - Портал сертификата: ${C_CYN}http://${DOM_CA}${C_RES}"
    echo " - Вызов меню:         ${C_GRN}gateway${C_RES} (Раздел Homelab — пункт 13)"
    echo "${C_CYN}========================================================${C_RES}"

    if [ "$TARGET_LAN_IP" != "$SAVED_LAN_IP" ]; then
        apply_network_ips "$TARGET_LAN_IP" "$GW_IP" || true
    fi
    return 0
}

# Матрица глубокой диагностики шлюза и стека Homelab (Self-Test 2.0)
run_self_test() {
    set +e
    detect_os
    echo "${C_CYN}=== [Self-Test 2.0] Матрица диагностики шлюза и Homelab (${OS_NAME}) ===${C_RES}"
    WAIT_CNT=0
    while [ "$WAIT_CNT" -lt 12 ]; do
        if pgrep sing-box >/dev/null 2>&1 && ip link show singbox-tun >/dev/null 2>&1; then
            break
        fi
        sleep 1
        WAIT_CNT=$((WAIT_CNT + 1))
    done

    load_gateway_env
    calc_hardware_limits
    LAN_IF_NOW=$(get_lan_ifname)
    if is_dhcp_server_enabled; then
        DHCP_ST="${C_GRN}ВКЛ${C_RES}"
    else
        DHCP_ST="${C_DIM}ВЫКЛ${C_RES}"
    fi
    echo " • Сеть сервера: ${C_BLD}[${OS_NAME} (${LAN_IF_NOW}): $(get_current_lan_ip)]${C_RES} -> [Роутер: ${GW_IP}] | DHCP: ${DHCP_ST}"
    print_proxy_slots_report

    SB_PID=$(pgrep sing-box 2>/dev/null | head -n 1 || true)
    if [ -n "$SB_PID" ]; then
        SB_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${SB_PID}/status" 2>/dev/null || echo "активен")
        echo "${C_GRN}[✓]${C_RES} Служба Sing-Box Extended: ${C_GRN}ЗАПУЩЕНА${C_RES} (PID ${SB_PID}, ОЗУ: ${SB_RSS} / лимит ${SB_GOMEMLIMIT})"
    else
        echo "${C_RED}[X] Служба Sing-Box Extended: ОСТАНОВЛЕНА${C_RES}"
    fi

    AGH_PID=$(pgrep AdGuardHome 2>/dev/null | head -n 1 || true)
    if [ -n "$AGH_PID" ]; then
        AGH_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${AGH_PID}/status" 2>/dev/null || echo "активен")
        echo "${C_GRN}[✓]${C_RES} Служба AdGuard Home (:53): ${C_GRN}ЗАПУЩЕНА${C_RES} (PID ${AGH_PID}, ОЗУ: ${AGH_RSS} / лимит ${AGH_GOMEMLIMIT})"
    else
        echo "${C_RED}[X] Служба AdGuard Home: ОСТАНОВЛЕНА${C_RES}"
    fi

    if ip link show singbox-tun >/dev/null 2>&1; then
        echo "${C_GRN}[✓]${C_RES} TUN-интерфейс (singbox-tun): ${C_GRN}АКТИВЕН${C_RES} (MTU 1492, mixed stack)"
    else
        echo "${C_RED}[X] TUN-интерфейс (singbox-tun): НЕ НАЙДЕН${C_RES}"
    fi

    RP_STAT=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "unknown")
    BBR_STAT=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    CT_CNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
    echo "${C_GRN}[✓]${C_RES} Сетевой стек: TCP ${C_CYN}${BBR_STAT}${C_RES} | rp_filter=${RP_STAT} | Сессии Conntrack: ${C_BLD}${CT_CNT}${C_RES} из ${SYS_CONNTRACK_MAX}"

    if is_killswitch_enabled; then
        echo "${C_GRN}[✓]${C_RES} Защита от утечек: ${C_GRN}Kill-Switch АКТИВЕН${C_RES} + блок Type 65 (HTTPS/ECH), IPv6 и DoT 853"
    else
        echo "${C_GRN}[✓]${C_RES} Защита от утечек: Блок Type 65 (HTTPS/ECH), IPv6 Drop, DoT/DoQ 853 Reject и DNS 53 Redirect"
    fi

    if [ -f "$SB_CONF" ] && [ -n "$SB_PID" ]; then
        ACTIVE_NODE=$(curl -fsS --connect-timeout 3 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null | jq -r '.proxies["⚡ Авто (Самый быстрый)"].now // empty' 2>/dev/null)
        [ -n "$ACTIVE_NODE" ] && echo "${C_GRN}[✓]${C_RES} Активная нода (Авто): ${C_CYN}${ACTIVE_NODE}${C_RES}" || true
        CF_TRACE=$(curl -fsS --curves X25519:P-256 --connect-timeout 4 -x http://127.0.0.1:7890 "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null | grep -E '^(ip|loc|warp|colo)=' | tr '\n' ' ' || true)
        if [ -n "$CF_TRACE" ]; then
            echo "${C_GRN}[✓]${C_RES} Внешний выход через туннель (Cloudflare Trace): ${C_GRN}${CF_TRACE}${C_RES}"
            PING_RU=$(curl -o /dev/null -fsS --curves X25519:P-256 --connect-timeout 2 -w '%{time_connect}' "http://ya.ru" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f ms", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            PING_CF=$(curl -o /dev/null -fsS --curves X25519:P-256 --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "http://cp.cloudflare.com/generate_204" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f ms", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            PING_GG=$(curl -o /dev/null -fsS --curves X25519:P-256 --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "https://www.youtube.com/generate_204" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f ms", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            PING_AI=$(curl -o /dev/null -sS --curves X25519:P-256 --connect-timeout 3 -m 4 -x http://127.0.0.1:7890 -w '%{time_appconnect}' "https://api.openai.com" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f ms", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            echo "${C_GRN}[✓]${C_RES} Матрица задержек: РФ (ya.ru): ${C_BLD}${PING_RU}${C_RES} | CF: ${C_BLD}${PING_CF}${C_RES} | YouTube: ${C_BLD}${PING_GG}${C_RES} | OpenAI (TLS): ${C_BLD}${PING_AI}${C_RES}"
        else
            echo "${C_YEL}[!] Туннель еще прогревается или подписка недоступна.${C_RES}"
        fi
    fi

    if [ "$(count_enabled_homelab_modules)" -gt 0 ]; then
        echo "---------------------------------------------------------------"
        run_homelab_self_test
    fi
    return 0
}

# ==============================================================================
# Интерактивное подменю Homelab & Media Stack (Пункт 13 из 11 разделов по ТЗ)
# ==============================================================================
show_homelab_menu() {
    init_homelab_registry
    load_gateway_env
    while true; do
        clear
        echo "${C_CYN}=======================================================================${C_RES}"
        echo "${C_BLD} 🏠 Управление домашним сервером (Alpine Linux Homelab & Media Stack)  ${C_RES}"
        echo "${C_CYN}=======================================================================${C_RES}"
        print_homelab_services_table
        echo "  ${C_CYN}1)${C_RES} Просмотр установленных сервисов, процессов и URL"
        echo "  ${C_CYN}2)${C_RES} Установка дополнительных компонентов Homelab"
        echo "  ${C_CYN}3)${C_RES} Удаление отдельных компонентов (с сохранением данных)"
        echo "  ${C_CYN}4)${C_RES} Обновление компонентов Homelab"
        echo "  ${C_CYN}5)${C_RES} Управление службами (Старт / Стоп / Перезапуск)"
        echo "  ${C_CYN}6)${C_RES} Просмотр логов сервисов Homelab"
        echo "  ${C_CYN}7)${C_RES} Проверка состояния Homelab (Homelab Self-Test)"
        echo "  ${C_CYN}8)${C_RES} Управление общим хранилищем (${STORAGE_ROOT})"
        echo "  ${C_CYN}9)${C_RES} Настройка Samba и обнаружения в сети (Windows 11 / Linux)"
        echo "  ${C_CYN}10)${C_RES} Управление локальными доменами (*.lan) и HTTPS (Root CA)"
        echo "  ${C_CYN}11)${C_RES} Управление резервным копированием (Unified Backup & Restore)"
        echo "  ${C_CYN}12)${C_RES} ${C_GRN}🛡️ Диагностика и автоисправление прав доступа всех сервисов (Permissions Audit)${C_RES}"
        echo "  ${C_CYN}13)${C_RES} ${C_CYN}🎬🎵 Архитектура медиатеки: Интеграция музыки и видео в Jellyfin vs Navidrome${C_RES}"
        echo "  ${C_CYN}14)${C_RES} ${C_GRN}🔐 Глубокая диагностика и починка Vaultwarden (API + Web Vault + HTTPS)${C_RES}"
        echo "  ${C_CYN}0)${C_RES} Назад в главное меню шлюза"
        echo "-----------------------------------------------------------------------"
        printf "Выберите действие [0-14]: "
        read -r HL_ACT < /dev/tty || true

        case "$HL_ACT" in
            ""|0)
                break
                ;;
            1)
                echo ""
                run_homelab_self_test
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            2)
                prompt_homelab_modules_wizard
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            3)
                printf "Введите ID модуля для удаления (caddy/samba/vaultwarden/forgejo/code/navidrome/jellyfin/ytdlp/torrent): "
                read -r RM_MOD < /dev/tty || true
                RM_MOD=$(printf "%s" "$RM_MOD" | tr -d ' \t\r\n')
                if [ -n "$RM_MOD" ]; then
                    homelab_module_dispatch "$RM_MOD" "remove" || true
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            4)
                printf "Введите ID модуля для обновления (или 'all' для всех установленных): "
                read -r UP_MOD < /dev/tty || true
                UP_MOD=$(printf "%s" "$UP_MOD" | tr -d ' \t\r\n')
                if [ "$UP_MOD" = "all" ]; then
                    while IFS='|' read -r M_ID M_EN _REST; do
                        case "$M_ID" in ''|\#*) continue ;; esac
                        [ "$M_EN" = "yes" ] && homelab_module_dispatch "$M_ID" "update"
                    done < "$HOMELAB_STATE"
                elif [ -n "$UP_MOD" ]; then
                    homelab_module_dispatch "$UP_MOD" "update" || true
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            5)
                printf "Введите ID модуля (caddy/samba/vaultwarden/forgejo/code/navidrome/jellyfin/ytdlp/torrent): "
                read -r CTL_MOD < /dev/tty || true
                CTL_MOD=$(printf "%s" "$CTL_MOD" | tr -d ' \t\r\n')
                printf "Действие (start / stop / restart): "
                read -r CTL_OP < /dev/tty || true
                CTL_OP=$(printf "%s" "$CTL_OP" | tr -d ' \t\r\n')
                if [ -n "$CTL_MOD" ] && [ -n "$CTL_OP" ]; then
                    homelab_module_dispatch "$CTL_MOD" "$CTL_OP" || true
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            6)
                echo "Доступные журналы: 1) caddy  2) vaultwarden  3) ytdlp  4) code-server  5) samba  6) forgejo  7) messages"
                printf "Выберите журнал [1-7]: "
                read -r LOG_SEL < /dev/tty || true
                case "$LOG_SEL" in
                    1) tail -n 40 /var/log/caddy.log 2>/dev/null || true ;;
                    2) tail -n 40 /var/log/vaultwarden.log 2>/dev/null || true ;;
                    3) tail -n 40 /var/log/ytdlp-webui.log 2>/dev/null || true ;;
                    4) tail -n 40 /var/log/code-server.log 2>/dev/null || true ;;
                    5) tail -n 40 /var/log/samba/log.smbd 2>/dev/null || true ;;
                    6) tail -n 40 /var/log/forgejo/*.log 2>/dev/null || true ;;
                    7) tail -n 40 /var/log/messages 2>/dev/null || true ;;
                esac
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            7)
                echo ""
                run_homelab_self_test
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            8)
                echo ""
                print_storage_stats
                echo " 1) Починить и синхронизировать права доступа (setgid 2775 + группа media + POSIX ACL)"
                echo " 2) Запустить полный аудит прав доступа всех сервисов (Permissions Audit)"
                echo " 3) Очистить временный буфер незавершенных загрузок (${STORAGE_INCOMPLETE})"
                echo " 0) Назад"
                printf "Выбор [0-3]: "
                read -r ST_OP < /dev/tty || true
                case "$ST_OP" in
                    1)
                        repair_storage_permissions
                        echo "${C_GRN}[✓] Права доступа на ${STORAGE_ROOT} успешно восстановлены!${C_RES}"
                        ;;
                    2)
                        run_homelab_permissions_audit "interactive" || true
                        ;;
                    3)
                        rm -rf "${STORAGE_INC_TORRENTS:?}/"* "${STORAGE_INC_YTDLP:?}/"* 2>/dev/null || true
                        repair_storage_permissions
                        echo "${C_GRN}[✓] Временные буферы загрузок очищены.${C_RES}"
                        ;;
                esac
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            9)
                echo ""
                echo "${C_CYN}=== Настройка Samba и сетевого обнаружения (WSDD + Avahi) ===${C_RES}"
                echo " • Текущий пользователь Samba: ${C_BLD}${SMB_USER:-homelab}${C_RES}"
                echo " 1) Установить / Перенастроить Samba и сменить логин/пароль шары"
                echo " 2) Проверить и принудительно синхронизировать текущий пароль Samba в passdb.tdb"
                echo " 3) Перезапустить службы обнаружения Windows 11 (wsdd) и Linux (avahi)"
                echo " 0) Назад"
                printf "Выбор [0-3]: "
                read -r SMB_OP < /dev/tty || true
                case "$SMB_OP" in
                    1) install_module_samba "interactive" || true ;;
                    2)
                        load_gateway_env
                        if apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS"; then
                            echo "${C_GRN}[✓] Пароль Samba для пользователя '${SMB_USER}' успешно проверен и синхронизирован в passdb.tdb!${C_RES}"
                        fi
                        ;;
                    3) setup_wsdd_and_avahi; echo "${C_GRN}[✓] Службы wsdd и avahi-daemon перезапущены.${C_RES}" ;;
                esac
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            10)
                sync_agh_homelab_rewrites "$(get_current_lan_ip)"
                reload_caddy_safe || true
                show_https_ca_instructions
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            11)
                echo ""
                echo "${C_CYN}=== Единая система резервного копирования (Шлюз + Homelab) ===${C_RES}"
                echo " 1) Создать бэкап конфигураций, БД SQLite и сертификатов CA (без медиафайлов)"
                echo " 2) Создать ПОЛНЫЙ бэкап (включая медиафайлы в ${STORAGE_ROOT})"
                echo " 3) Восстановить систему из архива (${BACKUP_ARCHIVE})"
                echo " 4) Отправить архив бэкапа в Telegram"
                echo " 0) Назад"
                printf "Выбор [0-4]: "
                read -r BK_OP < /dev/tty || true
                case "$BK_OP" in
                    1)
                        create_unified_backup "no"
                        is_telegram_configured && send_telegram_backup "$BACKUP_ARCHIVE" || true
                        ;;
                    2)
                        create_unified_backup "yes"
                        ;;
                    3)
                        restore_unified_backup || true
                        ;;
                    4)
                        [ -f "$BACKUP_ARCHIVE" ] || create_unified_backup "no"
                        send_telegram_backup "$BACKUP_ARCHIVE" || true
                        ;;
                esac
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            12)
                run_homelab_permissions_audit "interactive" || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            13)
                show_media_architecture_advisor || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
            14)
                echo ""
                clean_vaultwarden_web_vault
                sync_vaultwarden_config
                sync_agh_homelab_rewrites "$(get_current_lan_ip)"
                is_module_enabled "vaultwarden" && service_ctl vaultwarden restart || true
                is_module_enabled "caddy" && register_caddy_site "vaultwarden" "$DOM_VAULTWARDEN" "$PORT_VAULTWARDEN" "no" >/dev/null 2>&1 || true
                sleep 1
                verify_vaultwarden_stack || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty
                ;;
        esac
    done
    return 0
}

# Безопасная самоустановка скрипта в качестве системной команды gateway (с очисткой CRLF)
INSTALL_PATH="/usr/bin/gateway"
SCRIPT_BASE="$(basename "$0" 2>/dev/null || true)"
if [ -f "$0" ] && [ "$0" != "$INSTALL_PATH" ] && [ "$SCRIPT_BASE" != "sh" ] && [ "$SCRIPT_BASE" != "ash" ] && [ "$SCRIPT_BASE" != "-sh" ] && [ "$SCRIPT_BASE" != "-ash" ]; then
    sed -i 's/\r$//; 1s/^\xEF\xBB\xBF//' "$0" 2>/dev/null || true
    cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    detect_os
    echo "${C_GRN}[✓] Команда 'gateway' (Alpine Linux Homelab Edition) установлена в систему (${OS_NAME}).${C_RES}"
fi

# ==============================================================================
# Главное интерактивное меню управления (Шлюз + Пункт 13 Homelab)
# ==============================================================================
show_menu() {
    set +e
    detect_os
    init_user_lists
    init_homelab_registry
    refresh_remote_versions "no"
    while true; do
        clear
        echo "${C_CYN}========================================================${C_RES}"
        echo "${C_BLD}  Панель управления (Alpine Linux Homelab Edition)      ${C_RES}"
        echo "${C_CYN}========================================================${C_RES}"
        print_gateway_header
        echo "--------------------------------------------------------"
        echo " ${C_CYN}1)${C_RES} Статус служб, матрица пинга и рентген сайтов (Self-Test 2.0)"
        echo " ${C_CYN}2)${C_RES} Управление прокси: Подписки / Ключи / WARP + ${C_GRN}SSH-пульт нод${C_RES}"
        echo " ${C_CYN}3)${C_RES} Обновить ядра Sing-Box Extended, AdGuard Home и Zashboard"
        echo " ${C_CYN}4)${C_RES} Перезапустить службы + пересобрать конфиг и сбросить кэш"
        echo " ${C_CYN}5)${C_RES} Посмотреть живые логи Sing-Box"
        echo " ${C_CYN}6)${C_RES} Полная перенастройка сервера (Мастер установки)"
        echo " ${C_CYN}7)${C_RES} Свои домены (В прокси / Напрямую) + ${C_GRN}🕵️ Детектор сайта${C_RES}"
        echo " ${C_CYN}8)${C_RES} Маршрутизация устройств по IP + ${C_GRN}🔍 Авто-поиск в LAN${C_RES}"
        echo " ${C_CYN}9)${C_RES} Сервисный режим, пароль и ${C_GRN}☁️ Единый бэкап в Telegram${C_RES}"
        echo " ${C_CYN}10)${C_RES} Автообновление (04:00), Авто-Доктор (Watchdog) и Telegram"
        echo " ${C_CYN}11)${C_RES} Аппаратный Kill-Switch (защита от утечек при падении Sing-Box)"
        echo " ${C_CYN}12)${C_RES} Сетевые настройки: IP сервера / роутера + Умный DHCP Sidecar"
        echo " ${C_CYN}13)${C_RES} ${C_GRN}🏠 Управление домашним сервером (Homelab & Media Stack)${C_RES}"
        echo " ${C_CYN}0)${C_RES} Выход"
        echo "--------------------------------------------------------"
        printf "Выберите действие [0-13]: "
        read -r CHOICE < /dev/tty || true

        case "$CHOICE" in
            1)
                echo ""
                run_self_test
                echo "--- Прослушиваемые порты ---"
                ss -tulpn 2>/dev/null | grep -E ':(53|80|443|445|1053|3000|3001|4533|7890|8080|8081|8096|8222|8443|9090)\b' || true
                echo "--------------------------------------------------------"
                printf "Нажмите Enter для возврата в меню (или введите 'd' для проверки любого сайта): "
                read -r ST_ACT < /dev/tty || true
                if [ "$ST_ACT" = "d" ] || [ "$ST_ACT" = "D" ]; then
                    inspect_domain_route || true
                    printf "\nНажмите Enter для возврата в меню..."
                    read -r _ < /dev/tty
                fi
                ;;
            2)
                while true; do
                    clear
                    echo "${C_CYN}=== Управление источниками прокси (3 независимых слота) ===${C_RES}"
                    print_proxy_slots_report
                    echo "---------------------------------------------------------------"
                    echo " 1) Указать / заменить основную подписку (http://...) [Слот 1]"
                    echo " 2) Добавить дополнительную подписку в пул (Мульти-Саб) [Слот 1]"
                    echo " 3) Отключить и очистить все подписки по ссылке [Слот 1]"
                    echo " 4) Посмотреть пронумерованный список личных ключей [Слот 2]"
                    echo " 5) Добавить личный ключ (vless/hy2/tuic/ss/wg/anytls...) [Слот 2]"
                    echo " 6) Удалить один конкретный личный ключ по номеру [Слот 2]"
                    echo " 7) Очистить все личные ключи в my_nodes.yaml [Слот 2]"
                    echo " 8) Включить / перевыпустить гибридный WARP 2.0 + MASQUE H2 [Слот 3]"
                    echo " 9) Отключить и полностью очистить ноды Amnezia WARP 2.0 [Слот 3]"
                    echo " 10) Режим «Белые списки» (показать/скрыть РФ-каскады в подписке) [Слот 1]"
                    echo " 11) ${C_GRN}⚡ Мини-пульт управления нодами и группами прямо из SSH${C_RES}"
                    echo " 12) ${C_GRN}🩺 Поштучно проверить и оживить ноды с молнией (⚡)${C_RES}"
                    echo " 0) Назад в главное меню"
                    echo "---------------------------------------------------------------"
                    printf "Выбор [0-12]: "
                    read -r SUB_ACT < /dev/tty || true
                    case "$SUB_ACT" in
                        ""|0) break ;;
                        1)
                            printf "Введите ссылку на подписку (или несколько через пробел): "
                            read -r NEW_SUB < /dev/tty || true
                            NEW_SUB=$(printf "%s" "$NEW_SUB" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            if [ -n "$NEW_SUB" ] && [ -f "$SB_CONF" ]; then
                                backup_gateway_state
                                load_gateway_env
                                apply_subscription_input "$NEW_SUB"
                                [ "${USE_INITIAL_WARP:-no}" = "yes" ] && generate_amnezia_warp || true
                                apply_and_verify_singbox "Обновление подписки (Слот 1)" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        2)
                            printf "Введите дополнительную ссылку на подписку (http://...): "
                            read -r EXTRA_SUB < /dev/tty || true
                            EXTRA_SUB=$(printf "%s" "$EXTRA_SUB" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            case "$EXTRA_SUB" in
                                http://*|https://*)
                                    backup_gateway_state
                                    load_gateway_env
                                    CLEAN_EXTRA=$(sanitize_sub_url_list "$EXTRA_SUB")
                                    SUB_URL="${SUB_URL:+${SUB_URL} }${CLEAN_EXTRA}"
                                    apply_and_verify_singbox "Добавление дополнительной подписки в Слот 1" || true
                                    ;;
                                *) echo "${C_RED}[X] Ссылка должна начинаться с http:// или https://${C_RES}" ;;
                            esac
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        3)
                            backup_gateway_state
                            load_gateway_env
                            SUB_URL=""
                            apply_and_verify_singbox "Очистка подписок по ссылке (Слот 1)" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        4)
                            echo ""
                            list_my_nodes
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        5)
                            printf "Вставьте один или несколько ключей (vless://, hy2://, ss://, tuic://, wg://, anytls://): "
                            read -r EXTRA_KEY < /dev/tty || true
                            EXTRA_KEY=$(printf "%s" "$EXTRA_KEY" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            if [ -n "$EXTRA_KEY" ]; then
                                backup_gateway_state
                                load_gateway_env
                                sed -i '/^proxies:[[:space:]]*\[\]/d' "$CUSTOM_NODES_FILE" 2>/dev/null || true
                                format_uri_keys "$EXTRA_KEY" >> "$CUSTOM_NODES_FILE"
                                apply_and_verify_singbox "Добавление личного ключа в Слот 2 (my_nodes)" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        6)
                            echo ""
                            list_my_nodes
                            if has_my_nodes; then
                                printf "\nВведите номер ключа для удаления [Enter = отмена]: "
                                read -r DEL_NUM < /dev/tty || true
                                DEL_NUM=$(printf "%s" "$DEL_NUM" | tr -d ' \t\r\n')
                                if [ -n "$DEL_NUM" ]; then
                                    backup_gateway_state
                                    load_gateway_env
                                    delete_my_node_by_index "$DEL_NUM" && apply_and_verify_singbox "Удаление ключа #${DEL_NUM}" || true
                                fi
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        7)
                            backup_gateway_state
                            load_gateway_env
                            echo "proxies: []" > "$CUSTOM_NODES_FILE"
                            apply_and_verify_singbox "Очистка всех личных ключей (Слот 2)" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        8)
                            backup_gateway_state
                            load_gateway_env
                            printf "Вставьте ключ лицензии WARP+ (если есть) [Enter = бесплатный WARP]: "
                            read -r W_LIC_IN < /dev/tty || true
                            W_LIC_IN=$(printf "%s" "$W_LIC_IN" | tr -d ' \t\r\n')
                            generate_amnezia_warp "$W_LIC_IN" && apply_and_verify_singbox "Обновление гибридного WARP 2.0 + MASQUE H2" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        9)
                            backup_gateway_state
                            load_gateway_env
                            echo '{"outbounds": []}' > "$WARP_NODES_FILE"
                            WARP_LICENSE=""
                            apply_and_verify_singbox "Отключение Amnezia WARP 2.0 (Слот 3)" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        10)
                            backup_gateway_state
                            load_gateway_env
                            if [ "${ALLOW_RU_NODES:-no}" = "yes" ]; then
                                ALLOW_RU_NODES="no"
                                ACT_MSG="Скрытие нод РФ/Белые списки в подписке"
                            else
                                ALLOW_RU_NODES="yes"
                                ACT_MSG="Показ каскадных нод РФ/Белые списки в подписке"
                            fi
                            save_gateway_env
                            apply_and_verify_singbox "$ACT_MSG" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        11) manage_nodes_cli_menu || true ;;
                        12)
                            diagnose_failed_nodes || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                    esac
                done
                ;;
            3)
                echo "Проверка и атомарное обновление ядер и веб-панели Zashboard..."
                update_cores_only "yes"
                service_ctl sing-box restart
                service_ctl adguardhome restart
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            4)
                echo "Пересборка эталонного конфига Sing-Box Extended и сброс conntrack..."
                backup_gateway_state
                load_gateway_env
                if apply_and_verify_singbox "Актуализация групп и перезапуск служб"; then
                    conntrack -F >/dev/null 2>&1 || true
                    service_ctl adguardhome restart
                    echo "${C_GRN}[✓] Таблица conntrack очищена, службы успешно перезапущены.${C_RES}"
                fi
                sleep 2
                ;;
            5)
                echo "${C_CYN}=== Последние записи лога Sing-Box Extended (${OS_NAME}) ===${C_RES}"
                show_singbox_logs 45
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            6)
                run_installer
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            7)
                while true; do
                    clear
                    echo "${C_CYN}=== Пользовательские правила доменов и Детектор сайта ===${C_RES}"
                    echo "Домены В ПРОКСИ (${USER_PROXY_FILE} -> группа 🌐 Остальной трафик):"
                    list_entries_numbered "$USER_PROXY_FILE"
                    echo "--------------------------------------------------------"
                    echo "Домены НАПРЯМУЮ (${USER_DIRECT_FILE} -> DIRECT, высший приоритет):"
                    list_entries_numbered "$USER_DIRECT_FILE"
                    echo "--------------------------------------------------------"
                    echo " 1) Добавить домен(ы) В ПРОКСИ (можно вставлять ссылки https://...)"
                    echo " 2) Добавить домен(ы) НАПРЯМУЮ (можно вставлять ссылки https://...)"
                    echo " 3) Удалить один домен из списка В ПРОКСИ по номеру"
                    echo " 4) Удалить один домен из списка НАПРЯМУЮ по номеру"
                    echo " 5) Сбросить оба списка доменов по умолчанию"
                    echo " 6) ${C_GRN}🕵️ Проверить любой сайт / домен (Рентген маршрута)${C_RES}"
                    echo " 0) Назад в главное меню"
                    echo "--------------------------------------------------------"
                    printf "Выбор [0-6]: "
                    read -r DOM_ACT < /dev/tty || true
                    case "$DOM_ACT" in
                        ""|0) break ;;
                        1)
                            printf "Введите домен или ссылку (можно несколько через пробел): "
                            read -r D_IN < /dev/tty || true
                            D_IN=$(printf "%s" "$D_IN" | tr -d '\r\n')
                            if [ -n "$D_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                ADDED_LIST=""
                                for D_ITEM in $(printf "%s\n" "$D_IN" | tr ' ,' '\n\n'); do
                                    [ -z "$D_ITEM" ] && continue
                                    CLEAN_D=$(sanitize_domain_entry "$D_ITEM" || true)
                                    if [ -n "$CLEAN_D" ]; then
                                        awk -v d="$CLEAN_D" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.localdomain"}' "$USER_DIRECT_FILE" > "${USER_DIRECT_FILE}.tmp" && mv "${USER_DIRECT_FILE}.tmp" "$USER_DIRECT_FILE"
                                        grep -qxF "$CLEAN_D" "$USER_PROXY_FILE" 2>/dev/null || echo "$CLEAN_D" >> "$USER_PROXY_FILE"
                                        ADDED_LIST="${ADDED_LIST} ${CLEAN_D}"
                                    fi
                                done
                                [ -n "$ADDED_LIST" ] && apply_and_verify_singbox "Добавление в прокси:${ADDED_LIST}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        2)
                            printf "Введите домен или ссылку (можно несколько через пробел): "
                            read -r D_IN < /dev/tty || true
                            D_IN=$(printf "%s" "$D_IN" | tr -d '\r\n')
                            if [ -n "$D_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                ADDED_LIST=""
                                for D_ITEM in $(printf "%s\n" "$D_IN" | tr ' ,' '\n\n'); do
                                    [ -z "$D_ITEM" ] && continue
                                    CLEAN_D=$(sanitize_domain_entry "$D_ITEM" || true)
                                    if [ -n "$CLEAN_D" ]; then
                                        awk -v d="$CLEAN_D" 'NF && $0 != d {print; kept++} END {if (kept+0 == 0) print "+.chatgpt.com"}' "$USER_PROXY_FILE" > "${USER_PROXY_FILE}.tmp" && mv "${USER_PROXY_FILE}.tmp" "$USER_PROXY_FILE"
                                        grep -qxF "$CLEAN_D" "$USER_DIRECT_FILE" 2>/dev/null || echo "$CLEAN_D" >> "$USER_DIRECT_FILE"
                                        ADDED_LIST="${ADDED_LIST} ${CLEAN_D}"
                                    fi
                                done
                                [ -n "$ADDED_LIST" ] && apply_and_verify_singbox "Добавление напрямую (DIRECT):${ADDED_LIST}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        3)
                            printf "Введите номер домена из списка В ПРОКСИ для удаления: "
                            read -r DEL_D_IDX < /dev/tty || true
                            DEL_D_IDX=$(printf "%s" "$DEL_D_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_D_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_VAL=$(get_entry_by_index "$USER_PROXY_FILE" "$DEL_D_IDX")
                                delete_entry_by_index "$USER_PROXY_FILE" "$DEL_D_IDX" "+.chatgpt.com" && apply_and_verify_singbox "Удаление ${DEL_VAL}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        4)
                            printf "Введите номер домена из списка НАПРЯМУЮ для удаления: "
                            read -r DEL_D_IDX < /dev/tty || true
                            DEL_D_IDX=$(printf "%s" "$DEL_D_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_D_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_VAL=$(get_entry_by_index "$USER_DIRECT_FILE" "$DEL_D_IDX")
                                delete_entry_by_index "$USER_DIRECT_FILE" "$DEL_D_IDX" "+.localdomain" && apply_and_verify_singbox "Удаление ${DEL_VAL}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        5)
                            backup_gateway_state
                            load_gateway_env
                            printf "+.localdomain\n+.lan\n" > "$USER_DIRECT_FILE"
                            echo "+.chatgpt.com" > "$USER_PROXY_FILE"
                            apply_and_verify_singbox "Сброс пользовательских списков доменов" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        6)
                            inspect_domain_route || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                    esac
                done
                ;;
            8)
                while true; do
                    clear
                    echo "${C_CYN}=== Маршрутизация устройств по IP (Авто-сканер LAN) ===${C_RES}"
                    discover_lan_devices
                    echo "--------------------------------------------------------"
                    echo "Устройства в обходе (всегда DIRECT):"
                    list_entries_numbered "$USER_BYPASS_IPS"
                    echo "--------------------------------------------------------"
                    echo "Устройства в Full-VPN (группа '📺 Устройства (Full-VPN)'):"
                    list_entries_numbered "$USER_FORCE_PROXY_IPS"
                    echo "--------------------------------------------------------"
                    echo " 1) Добавить устройство в ОБХОД (DIRECT) — по номеру из LAN или по IP"
                    echo " 2) Добавить устройство в FULL-VPN — по номеру из LAN или по IP"
                    echo " 3) Удалить один IP из списка ОБХОД (DIRECT) по номеру"
                    echo " 4) Удалить один IP из списка FULL-VPN по номеру"
                    echo " 5) Очистить оба списка IP"
                    echo " s) ${C_GRN}🔄 Активно просканировать всю подсеть LAN${C_RES}"
                    echo " 0) Назад в главное меню"
                    echo "--------------------------------------------------------"
                    printf "Выбор [0-5 / s]: "
                    read -r BYP_ACT < /dev/tty || true
                    case "$BYP_ACT" in
                        ""|0) break ;;
                        s|S) scan_lan_subnet ;;
                        1)
                            printf "Введите номер устройства из таблицы LAN ИЛИ его IP-адрес (для DIRECT): "
                            read -r RAW_DEV_IN < /dev/tty || true
                            IP_IN=$(resolve_device_ip_input "$RAW_DEV_IN" || true)
                            if [ -n "$IP_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                sed -i "\|^${IP_IN}$|d" "$USER_FORCE_PROXY_IPS" 2>/dev/null || true
                                grep -qxF "$IP_IN" "$USER_BYPASS_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_BYPASS_IPS"
                                apply_and_verify_singbox "Добавление IP ${IP_IN} в DIRECT" && conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        2)
                            printf "Введите номер устройства из таблицы LAN ИЛИ его IP-адрес (для Full-VPN): "
                            read -r RAW_DEV_IN < /dev/tty || true
                            IP_IN=$(resolve_device_ip_input "$RAW_DEV_IN" || true)
                            if [ -n "$IP_IN" ]; then
                                backup_gateway_state
                                load_gateway_env
                                sed -i "\|^${IP_IN}$|d" "$USER_BYPASS_IPS" 2>/dev/null || true
                                grep -qxF "$IP_IN" "$USER_FORCE_PROXY_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_FORCE_PROXY_IPS"
                                apply_and_verify_singbox "Добавление IP ${IP_IN} в Full-VPN" && conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        3)
                            printf "Введите номер IP из списка ОБХОД (DIRECT) для удаления: "
                            read -r DEL_I_IDX < /dev/tty || true
                            DEL_I_IDX=$(printf "%s" "$DEL_I_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_I_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_IP=$(get_entry_by_index "$USER_BYPASS_IPS" "$DEL_I_IDX")
                                delete_entry_by_index "$USER_BYPASS_IPS" "$DEL_I_IDX" "" && apply_and_verify_singbox "Удаление IP ${DEL_IP}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        4)
                            printf "Введите номер IP из списка FULL-VPN для удаления: "
                            read -r DEL_I_IDX < /dev/tty || true
                            DEL_I_IDX=$(printf "%s" "$DEL_I_IDX" | tr -d ' \t\r\n')
                            if [ -n "$DEL_I_IDX" ]; then
                                backup_gateway_state
                                load_gateway_env
                                DEL_IP=$(get_entry_by_index "$USER_FORCE_PROXY_IPS" "$DEL_I_IDX")
                                delete_entry_by_index "$USER_FORCE_PROXY_IPS" "$DEL_I_IDX" "" && apply_and_verify_singbox "Удаление IP ${DEL_IP}" || true
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        5)
                            backup_gateway_state
                            load_gateway_env
                            : > "$USER_BYPASS_IPS"
                            : > "$USER_FORCE_PROXY_IPS"
                            apply_and_verify_singbox "Очистка списков маршрутизации по IP" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                    esac
                done
                ;;
            9)
                while true; do
                    load_gateway_env
                    clear
                    echo "${C_CYN}=== Сервисный режим, смена пароля и Единый бэкап ===${C_RES}"
                    echo " • Облако Telegram: $(is_telegram_configured && echo "${C_GRN}ПОДКЛЮЧЕНО (Chat ID: ${TG_CHAT_ID})${C_RES}" || echo "${C_DIM}НЕ НАСТРОЕНО${C_RES}")"
                    echo "--------------------------------------------------------"
                    echo " 1) Пауза: переключить весь трафик в DIRECT (без остановки DNS)"
                    echo " 2) Возобновить работу по правилам (mode: rule)"
                    echo " 3) Создать единый бэкап (Шлюз + Homelab БД + CA) + отправка в TG"
                    echo " 4) Восстановить систему из бэкапа (${BACKUP_ARCHIVE})"
                    echo " 5) Сменить единый пароль (Sing-Box + AdGuard Home + Homelab)"
                    echo " 6) ${C_GRN}☁️ Отправить текущий файл бэкапа себе в Telegram${C_RES}"
                    echo " 7) ⚙️ Настроить Telegram-бота (Токен и Chat ID)"
                    echo " 0) Назад в главное меню"
                    echo "--------------------------------------------------------"
                    printf "Выбор [0-7]: "
                    read -r SRV_ACT < /dev/tty || true
                    case "$SRV_ACT" in
                        ""|0) break ;;
                        1)
                            curl -fsS -X PATCH -H "Authorization: Bearer ${ADMIN_PASS}" -H "Content-Type: application/json" \
                                -d '{"mode":"direct"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                            echo "${C_GRN}[✓] Шлюз переведен в режим паузы (DIRECT).${C_RES}"
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        2)
                            curl -fsS -X PATCH -H "Authorization: Bearer ${ADMIN_PASS}" -H "Content-Type: application/json" \
                                -d '{"mode":"rule"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                            echo "${C_GRN}[✓] Режим маршрутизации по правилам (rule) восстановлен.${C_RES}"
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        3)
                            create_unified_backup "no"
                            is_telegram_configured && send_telegram_backup "$BACKUP_ARCHIVE" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        4)
                            restore_unified_backup || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        5)
                            printf "Введите новый единый пароль: "
                            read -r NEW_P_IN < /dev/tty || true
                            NEW_P_IN=$(printf "%s" "$NEW_P_IN" | tr -d '\r\n')
                            [ -n "$NEW_P_IN" ] && change_unified_password "$NEW_P_IN" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        6)
                            [ -f "$BACKUP_ARCHIVE" ] || create_unified_backup "no"
                            send_telegram_backup "$BACKUP_ARCHIVE" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        7)
                            configure_telegram_menu || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                    esac
                done
                ;;
            10)
                while true; do
                    load_gateway_env
                    clear
                    echo "${C_CYN}=== Автообновление (04:00), Авто-Доктор (Watchdog) и Telegram ===${C_RES}"
                    echo " • Автообновление ядер (04:00): $(is_autoupdate_enabled && echo "${C_GRN}ВКЛЮЧЕНО${C_RES}" || echo "${C_DIM}ВЫКЛЮЧЕНО${C_RES}")"
                    echo " • Авто-Доктор (Шлюз+Homelab):  $(is_watchdog_enabled && echo "${C_GRN}ВКЛЮЧЕН (каждые 5 мин)${C_RES}" || echo "${C_DIM}ВЫКЛЮЧЕН${C_RES}")"
                    echo " • Уведомления в Telegram:      $(is_telegram_configured && echo "${C_GRN}ВКЛЮЧЕНЫ (Chat ID: ${TG_CHAT_ID})${C_RES}" || echo "${C_DIM}НЕ НАСТРОЕНЫ${C_RES}")"
                    echo "--------------------------------------------------------"
                    echo " 1) Включить Автообновление (04:00) + Watchdog"
                    echo " 2) Выключить Автообновление (оставить только Watchdog)"
                    echo " 3) Включить / Выключить Авто-Доктор (Watchdog)"
                    echo " 4) Посмотреть лог последнего автообновления (${AUTOUPDATE_LOG})"
                    echo " 5) ⚙️ Настроить уведомления и облачный бэкап в Telegram"
                    echo " 0) Назад в главное меню"
                    echo "--------------------------------------------------------"
                    printf "Выбор [0-5]: "
                    read -r AU_ACT < /dev/tty || true
                    case "$AU_ACT" in
                        ""|0) break ;;
                        1) enable_autoupdate; enable_watchdog; echo "${C_GRN}[✓] Автообновление и Watchdog включены.${C_RES}"; sleep 1 ;;
                        2) disable_autoupdate; enable_watchdog; echo "${C_GRN}[✓] Автообновление отключено.${C_RES}"; sleep 1 ;;
                        3)
                            if is_watchdog_enabled; then
                                disable_watchdog; echo "${C_YEL}[✓] Watchdog отключен.${C_RES}"
                            else
                                enable_watchdog; echo "${C_GRN}[✓] Watchdog включен.${C_RES}"
                            fi
                            sleep 1
                            ;;
                        4)
                            [ -f "$AUTOUPDATE_LOG" ] && cat "$AUTOUPDATE_LOG" || echo "[i] Лог пуст."
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        5) configure_telegram_menu || true ;;
                    esac
                done
                ;;
            11)
                while true; do
                    clear
                    echo "${C_CYN}=== Аппаратный Kill-Switch (nftables на $(get_lan_ifname)) ===${C_RES}"
                    echo " • Текущий статус: $(is_killswitch_enabled && echo "${C_GRN}ВКЛЮЧЕН (строгая блокировка)${C_RES}" || echo "${C_CYN}ВЫКЛЮЧЕН (стандартная защита)${C_RES}")"
                    echo "--------------------------------------------------------"
                    echo " 1) ВКЛЮЧИТЬ строгий Kill-Switch"
                    echo " 2) ВЫКЛЮЧИТЬ строгий Kill-Switch"
                    echo " 0) Назад"
                    printf "Выбор [0-2]: "
                    read -r KS_ACT < /dev/tty || true
                    case "$KS_ACT" in
                        ""|0) break ;;
                        1) sync_dns_firewall "yes" "yes"; echo "${C_GRN}[✓] Kill-Switch ВКЛЮЧЕН.${C_RES}"; sleep 1 ;;
                        2) sync_dns_firewall "yes" "no"; echo "${C_GRN}[✓] Kill-Switch ВЫКЛЮЧЕН.${C_RES}"; sleep 1 ;;
                    esac
                done
                ;;
            12)
                while true; do
                    CUR_LAN_NOW=$(get_current_lan_ip)
                    load_gateway_env
                    clear
                    echo "${C_CYN}=== Сетевые настройки сервера и Умный DHCP Sidecar ===${C_RES}"
                    echo " • Текущий IP сервера (${OS_NAME}): ${C_BLD}${CUR_LAN_NOW}${C_RES} ($(get_lan_ifname), /24)"
                    echo " • Текущий IP основного роутера:   ${GW_IP}"
                    echo " • Умный DHCP-сервер на шлюзе:     $(is_dhcp_server_enabled && echo "${C_GRN}ВКЛЮЧЕН${C_RES}" || echo "${C_DIM}ВЫКЛЮЧЕН${C_RES}")"
                    echo "----------------------------------------------------------"
                    echo " 1) Сменить IP-адрес самого сервера (${OS_NAME})"
                    echo " 2) Сменить IP-адрес основного роутера"
                    echo " 3) Сменить оба адреса сразу"
                    echo " 4) ВКЛЮЧИТЬ Умный DHCP-сервер на шлюзе"
                    echo " 5) ВЫКЛЮЧИТЬ DHCP-сервер на шлюзе"
                    echo " 0) Назад"
                    printf "Выбор [0-5]: "
                    read -r NET_ACT < /dev/tty || true
                    case "$NET_ACT" in
                        ""|0) break ;;
                        1)
                            printf "Введите новый IP для сервера [текущий %s]: " "$CUR_LAN_NOW"
                            read -r NEW_L < /dev/tty || true
                            NEW_L=$(printf "%s" "$NEW_L" | tr -d ' \t\r\n')
                            if [ -n "$NEW_L" ] && apply_network_ips "$NEW_L" "$GW_IP"; then
                                [ "$NEW_L" != "$CUR_LAN_NOW" ] && exit 0
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        2)
                            printf "Введите новый IP основного роутера [текущий %s]: " "$GW_IP"
                            read -r NEW_G < /dev/tty || true
                            NEW_G=$(printf "%s" "$NEW_G" | tr -d ' \t\r\n')
                            [ -n "$NEW_G" ] && apply_network_ips "$CUR_LAN_NOW" "$NEW_G" || true
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        3)
                            printf "Введите новый IP для сервера [текущий %s]: " "$CUR_LAN_NOW"
                            read -r NEW_L < /dev/tty || true
                            NEW_L=$(printf "%s" "$NEW_L" | tr -d ' \t\r\n')
                            printf "Введите новый IP основного роутера [текущий %s]: " "$GW_IP"
                            read -r NEW_G < /dev/tty || true
                            NEW_G=$(printf "%s" "$NEW_G" | tr -d ' \t\r\n')
                            if [ -n "$NEW_L" ] && [ -n "$NEW_G" ] && apply_network_ips "$NEW_L" "$NEW_G"; then
                                [ "$NEW_L" != "$CUR_LAN_NOW" ] && exit 0
                            fi
                            printf "\nНажмите Enter для продолжения..."
                            read -r _ < /dev/tty
                            ;;
                        4) configure_smart_dhcp "on"; sleep 1 ;;
                        5) configure_smart_dhcp "off"; sleep 1 ;;
                    esac
                done
                ;;
            13)
                show_homelab_menu
                ;;
            0)
                exit 0
                ;;
        esac
    done
}

# Маршрутизация аргументов командной строки (Обратная совместимость + команды Homelab и Backup)
case "${1:-}" in
    autoupdate)
        run_autoupdate
        ;;
    watchdog)
        run_watchdog
        ;;
    test|status)
        run_self_test
        ;;
    install)
        run_installer
        ;;
    homelab)
        case "${2:-}" in
            status|test)      run_homelab_self_test ;;
            perms|audit)      run_homelab_permissions_audit "${3:-interactive}" ;;
            fix-perms|repair) repair_all_homelab_permissions "yes" ;;
            media)            show_media_architecture_advisor ;;
            vaultwarden)      verify_vaultwarden_stack ;;
            install)          [ -n "${3:-}" ] && homelab_module_dispatch "$3" "install" || prompt_homelab_modules_wizard ;;
            remove)           [ -n "${3:-}" ] && homelab_module_dispatch "$3" "remove" ;;
            restart)          [ -n "${3:-}" ] && homelab_module_dispatch "$3" "restart" ;;
            *)                show_homelab_menu ;;
        esac
        ;;
    backup)
        case "${2:-create}" in
            create)   create_unified_backup "no" ;;
            full)     create_unified_backup "yes" ;;
            restore)  restore_unified_backup ;;
            telegram) [ -f "$BACKUP_ARCHIVE" ] || create_unified_backup "no"; send_telegram_backup "$BACKUP_ARCHIVE" ;;
        esac
        ;;
    *)
        if [ ! -f "$SB_CONF" ]; then
            run_installer
        else
            show_menu
        fi
        ;;
esac
# ==================== [ КОНЕЦ ЧАСТИ 6 ИЗ 6 ] =====================
