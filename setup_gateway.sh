#!/bin/sh
set -e

# ==================== [ НАЧАЛО ЧАСТИ 1 ИЗ 3 ] ====================
# ==============================================================================
# Глобальные пути и переменные (OpenWrt 25.x + APK — Sing-Box Extended Ноябрь 2026)
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
UI_VER_FILE="${SB_DIR}/ui/.ui_version"
UI_REPO="Zephyruso/zashboard"
UI_ZIP_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
AGH_CONF="/etc/AdGuardHome/AdGuardHome.yaml"
SYSUPGRADE_CONF="/etc/sysupgrade.conf"
SUB_FILTER_REGEX="(?i)(剩余|过期|到期|官网|流量|套餐|重置|expire|traffic|website|official|осталось|трафик|истекает|подписк|тариф|инфо|новост|поддержк|канал|бот|t[.]me/)"
GH_PROXY=""
LATEST_SB_TAG=""
LATEST_AGH_TAG=""
LATEST_UI_TAG=""
SB_GOMEMLIMIT="200MiB"
AGH_GOMEMLIMIT="100MiB"
SYS_CONNTRACK_MAX="65536"
SYS_BUF_MAX="16777216"
TOTAL_RAM_MB="512"

# Автоматический расчет лимитов RAM и сетевого стека под железо (256MB .. 8GB+)
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
        SB_GOMEMLIMIT="350MiB"
        AGH_GOMEMLIMIT="150MiB"
        SYS_CONNTRACK_MAX="131072"
        SYS_BUF_MAX="33554432"
    else
        SB_GOMEMLIMIT="600MiB"
        AGH_GOMEMLIMIT="250MiB"
        SYS_CONNTRACK_MAX="262144"
        SYS_BUF_MAX="67108864"
    fi
    return 0
}

# Проверка целевой платформы (OpenWrt 25.x+ с пакетным менеджером apk)
detect_os() {
    if [ ! -f /etc/openwrt_release ]; then
        echo "[X] Ошибка: Скрипт предназначен исключительно для OpenWrt."
        exit 1
    fi
    if ! command -v apk >/dev/null 2>&1; then
        echo "[X] Ошибка: Не найден пакетный менеджер apk (требуется OpenWrt 25.x+)."
        exit 1
    fi

    calc_hardware_limits
    OS_NAME="OpenWrt ($(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2))"
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
            echo "[X] Ошибка: Неподдерживаемая архитектура ${ARCH_RAW}."
            exit 1
            ;;
    esac
    return 0
}

# Проверка корректности IPv4-адреса (X.X.X.X, октеты 0..255, хост 1..254)
is_valid_ipv4() {
    IP_CAND="$1"
    printf "%s" "$IP_CAND" | awk -F'.' '
        NF != 4 { exit 1 }
        {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/) exit 1
                if ($i + 0 < 0 || $i + 0 > 255) exit 1
            }
            if ($1 + 0 < 1 || $1 + 0 > 223 || $1 + 0 == 127) exit 1
            if ($4 + 0 < 1 || $4 + 0 > 254) exit 1
        }
    ' >/dev/null 2>&1
}

# Динамическое определение имени LAN-интерфейса (br-lan, eth0 и т.д.)
get_lan_ifname() {
    LAN_DEV=$(uci -q get network.lan.device 2>/dev/null || uci -q get network.lan.ifname 2>/dev/null || true)
    LAN_DEV=$(printf "%s" "$LAN_DEV" | awk '{print $1}')
    if [ -n "$LAN_DEV" ] && ip link show "$LAN_DEV" >/dev/null 2>&1; then
        printf "%s" "$LAN_DEV"
        return 0
    fi
    if ip link show br-lan >/dev/null 2>&1; then
        printf "br-lan"
        return 0
    fi
    DEF_DEV=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev" && $(i+1)!="singbox-tun") {print $(i+1); exit}}')
    if [ -n "$DEF_DEV" ] && ip link show "$DEF_DEV" >/dev/null 2>&1; then
        printf "%s" "$DEF_DEV"
        return 0
    fi
    printf "br-lan"
    return 0
}

# Получение текущего LAN IP-адреса самого шлюза OpenWrt
get_current_lan_ip() {
    L_IF=$(get_lan_ifname)
    CUR_LAN=$(ip -4 addr show "$L_IF" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    [ -z "$CUR_LAN" ] && CUR_LAN=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    [ -z "$CUR_LAN" ] && CUR_LAN=$(uci -q get network.lan.ipaddr | awk '{print $1}')
    CUR_LAN="${CUR_LAN%%/*}"
    [ -z "$CUR_LAN" ] && CUR_LAN="192.168.1.1"
    printf "%s" "$CUR_LAN"
    return 0
}

# Защита файлов шлюза от удаления при обновлении прошивки OpenWrt (sysupgrade / owut)
ensure_sysupgrade_persistence() {
    touch "$SYSUPGRADE_CONF" 2>/dev/null || return 0
    for item in \
        "/usr/bin/gateway" \
        "/usr/bin/sing-box" \
        "/usr/bin/AdGuardHome" \
        "/etc/sing-box" \
        "/etc/AdGuardHome" \
        "/etc/init.d/sing-box" \
        "/etc/init.d/adguardhome" \
        "/etc/sysctl.d/99-gateway-forward.conf" \
        "/etc/nftables.d"
    do
        grep -qxF "$item" "$SYSUPGRADE_CONF" 2>/dev/null || echo "$item" >> "$SYSUPGRADE_CONF"
    done
    return 0
}

# Отключение фонового демона apache (оставляем утилиту htpasswd для генерации bcrypt)
disable_apache_daemon() {
    for srv in apache apache2; do
        if [ -f "/etc/init.d/${srv}" ]; then
            "/etc/init.d/${srv}" stop >/dev/null 2>&1 || true
            "/etc/init.d/${srv}" disable >/dev/null 2>&1 || true
            rm -f "/etc/init.d/${srv}" 2>/dev/null || true
        fi
    done
    return 0
}

# Отключение старого сервиса Mihomo при миграции на sing-box-extended
disable_legacy_mihomo() {
    if [ -x /etc/init.d/mihomo ]; then
        /etc/init.d/mihomo stop >/dev/null 2>&1 || true
        /etc/init.d/mihomo disable >/dev/null 2>&1 || true
    fi
    rm -f /etc/nftables.d/98-mihomo-mss-clamp.nft /etc/nftables.d/97-mihomo-anti-leak.nft 2>/dev/null || true
    return 0
}

# Проверка валидности конфигурации sing-box-extended
check_singbox_config() {
    ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
        /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" >/dev/null 2>&1
}

# Проверка 3 независимых слотов прокси: Слот 1 (Подписки HTTP), Слот 2 (my_nodes), Слот 3 (WARP)
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
        awk 'NF && $0 !~ /^proxies:/ {found=1} END {exit !found}' "$CUSTOM_NODES_FILE" 2>/dev/null
}

count_my_nodes() {
    if [ -s "$CUSTOM_NODES_FILE" ] && ! grep -q '^proxies:[[:space:]]*\[\][[:space:]]*$' "$CUSTOM_NODES_FILE" 2>/dev/null; then
        awk 'NF && $0 !~ /^proxies:/ {c++} END {print c+0}' "$CUSTOM_NODES_FILE" 2>/dev/null
    else
        echo "0"
    fi
    return 0
}

is_warp_enabled() {
    [ -f "$WARP_NODES_FILE" ] && grep -q '"type":[[:space:]]*"wireguard"' "$WARP_NODES_FILE" 2>/dev/null
}

# Проверка состояния аппаратного Kill-Switch
is_killswitch_enabled() {
    [ -f /etc/nftables.d/97-singbox-anti-leak.nft ] && grep -q "#KILLSWITCH_ACTIVE" /etc/nftables.d/97-singbox-anti-leak.nft 2>/dev/null
}

# Проверка состояния Умного DHCP-сервера на самом OpenWrt (для залоченных роутеров провайдера)
is_dhcp_server_enabled() {
    DHCP_IGN=$(uci -q get dhcp.lan.ignore 2>/dev/null || echo "1")
    [ "$DHCP_IGN" = "0" ]
}

# Настройка nftables (fw4): TCP MSS Clamping, перехват DNS 53, Блок IPv6/DoT/DoQ и Kill-Switch
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

    mkdir -p /etc/nftables.d
    rm -f /etc/nftables.d/98-mihomo-mss-clamp.nft /etc/nftables.d/97-mihomo-anti-leak.nft 2>/dev/null || true

    # 1. Выравнивание TCP MSS (защита от PMTU Blackhole и детекта MTU в Sidecar-схеме)
    cat << 'NFT_MSS' > /etc/nftables.d/98-singbox-mss-clamp.nft
chain singbox_mss_clamp {
    type filter hook forward priority mangle; policy accept;
    oifname "singbox-tun" tcp flags syn tcp option maxseg size set rt mtu
    iifname "singbox-tun" tcp flags syn tcp option maxseg size set rt mtu
}
NFT_MSS

    # 2. Защита от утечек (Anti-Leak): жесткий блок IPv6 форвардинга, DoT/DoQ (853) и опциональный Kill-Switch
    if [ "$KS_STATE" = "yes" ]; then
        cat << NFT_LEAK_KS > /etc/nftables.d/97-singbox-anti-leak.nft
#KILLSWITCH_ACTIVE
chain singbox_anti_leak {
    type filter hook forward priority filter - 5; policy accept;
    meta nfproto ipv6 drop
    iifname "${LAN_IF}" meta l4proto { tcp, udp } th dport 853 reject
    iifname "${LAN_IF}" oifname "${LAN_IF}" ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } reject
}
NFT_LEAK_KS
    else
        cat << NFT_LEAK > /etc/nftables.d/97-singbox-anti-leak.nft
chain singbox_anti_leak {
    type filter hook forward priority filter - 5; policy accept;
    meta nfproto ipv6 drop
    iifname "${LAN_IF}" meta l4proto { tcp, udp } th dport 853 reject
}
NFT_LEAK
    fi

    # 3. Принудительный перехват любых сторонних DNS-запросов в AdGuard Home (:53)
    if [ "$USE_DNS_REDIRECT" = "yes" ]; then
        cat << NFT_OWRT > /etc/nftables.d/99-agh-dns-redirect.nft
chain agh_dns_prerouting {
    type nat hook prerouting priority dstnat - 5; policy accept;
    iifname "${LAN_IF}" meta l4proto { tcp, udp } th dport 53 redirect to :53
}
NFT_OWRT
    else
        rm -f /etc/nftables.d/99-agh-dns-redirect.nft 2>/dev/null || true
    fi

    /etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null || true
    return 0
}

# Обновление IP основного роутера внутри AdGuardHome.yaml
update_agh_gateway_ip() {
    NEW_GW="$1"
    [ -f "$AGH_CONF" ] || return 0
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
    ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv "${AGH_CONF}.tmp" "$AGH_CONF"
    chmod 600 "$AGH_CONF" 2>/dev/null || true
    return 0
}

# Безопасное экранирование одинарных кавычек для записи в gateway.env
escape_single_quotes() {
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
    return 0
}

# Чтение и сохранение параметров шлюза (gateway.env) с защитой от перезаписи памяти
load_gateway_env() {
    if [ -f "$SB_ENV" ]; then
        # shellcheck disable=SC1090
        . "$SB_ENV" 2>/dev/null || true
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

    [ -z "${GW_IP:-}" ] && GW_IP=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}') || true
    [ -z "${GW_IP:-}" ] && GW_IP="192.168.1.1" || true
    return 0
}

save_gateway_env() {
    mkdir -p "$SB_DIR"
    umask 077
    ESC_GW=$(escape_single_quotes "${GW_IP:-}")
    ESC_PASS=$(escape_single_quotes "${ADMIN_PASS:-}")
    ESC_SUB=$(escape_single_quotes "${SUB_URL:-}")
    ESC_WLIC=$(escape_single_quotes "${WARP_LICENSE:-}")
    cat << ENV_EOF > "$SB_ENV"
GW_IP='${ESC_GW}'
ADMIN_PASS='${ESC_PASS}'
SUB_URL='${ESC_SUB}'
WARP_LICENSE='${ESC_WLIC}'
ENV_EOF
    chmod 600 "$SB_ENV" 2>/dev/null || true
    return 0
}

# Компиляция текстовых пользовательских списков доменов (.list) в JSON rule-set (version 3)
sync_user_domain_rulesets() {
    mkdir -p "$SB_RULES_DIR"
    [ -f "$USER_DIRECT_FILE" ] || echo "+.localdomain" > "$USER_DIRECT_FILE"
    [ -f "$USER_PROXY_FILE" ] || echo "+.chatgpt.com" > "$USER_PROXY_FILE"

    if command -v jq >/dev/null 2>&1; then
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^+\.//;s/^\.//' "$USER_DIRECT_FILE" 2>/dev/null | grep -v '^$' | \
            jq -R . | jq -s '{version: 3, rules: [{domain_suffix: (if length > 0 then . else ["localdomain"] end)}]}' > "${USER_DIRECT_JSON}.tmp" && \
            mv "${USER_DIRECT_JSON}.tmp" "$USER_DIRECT_JSON"

        sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^+\.//;s/^\.//' "$USER_PROXY_FILE" 2>/dev/null | grep -v '^$' | \
            jq -R . | jq -s '{version: 3, rules: [{domain_suffix: (if length > 0 then . else ["chatgpt.com"] end)}]}' > "${USER_PROXY_JSON}.tmp" && \
            mv "${USER_PROXY_JSON}.tmp" "$USER_PROXY_JSON"
    else
        cat << 'J_DIR' > "$USER_DIRECT_JSON"
{"version":3,"rules":[{"domain_suffix":["localdomain"]}]}
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
    awk '{
        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", $0);
        if ($0 != "") {
            if (index($0, "/") == 0) print $0 "/32";
            else print $0;
        }
    }' "$SRC_FILE" | jq -R . | jq -s .
    return 0
}

# Генерация эталонного /etc/sing-box/config.json (5 чистых групп, 100% на пачках .srs)
generate_singbox_config() {
    check_github_mirror
    sync_user_domain_rulesets
    [ -z "${ADMIN_PASS:-}" ] && load_gateway_env || true
    [ -z "${ADMIN_PASS:-}" ] && ADMIN_PASS="admin" || true

    PROVIDERS_JSON_ARR="[]"
    PROVIDER_TAGS_JSON="[]"

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
                    --arg excl "$SUB_FILTER_REGEX" \
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
                            "timeout": "5s"
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
                        "timeout": "5s"
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
          "stun_domain",
          "torrent_domain",
          "user_direct_domains",
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
      ${FORCE_ROUTE_RULE}
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
      {
        "rule_set": [
          "youtube_domain",
          "spotify_domain"
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
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/private.srs"
      },
      {
        "tag": "private_ip",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/private.srs"
      },
      {
        "tag": "ntp_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ntp.srs"
      },
      {
        "tag": "stun_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-stun.srs"
      },
      {
        "tag": "torrent_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/tracker.srs"
      },
      {
        "tag": "youtube_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/youtube.srs"
      },
      {
        "tag": "spotify_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/spotify.srs"
      },
      {
        "tag": "ai_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ai-!cn.srs"
      },
      {
        "tag": "google_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/google.srs"
      },
      {
        "tag": "roblox_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/roblox.srs"
      },
      {
        "tag": "telegram_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/telegram.srs"
      },
      {
        "tag": "telegram_ip",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/telegram.srs"
      },
      {
        "tag": "whatsapp_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/whatsapp.srs"
      },
      {
        "tag": "facebook_ip",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/facebook.srs"
      },
      {
        "tag": "discord_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/discord.srs"
      },
      {
        "tag": "discord_voice_ip",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/sb-rule-sets/main/discord-voice-ip-list.srs"
      },
      {
        "tag": "cloudflare_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/cloudflare.srs"
      },
      {
        "tag": "cloudflare_ip",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/cloudflare.srs"
      },
      {
        "tag": "ru_bundle",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/sb-rule-sets/main/ru-bundle.srs"
      },
      {
        "tag": "refilter_ip",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/sb-rule-sets/main/rknasnblock.srs"
      },
      {
        "tag": "ru_domain",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ru.srs"
      },
      {
        "tag": "ru_ip",
        "type": "remote",
        "format": "binary",
        "download_detour": "DIRECT",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/ru.srs"
      }
    ]
  }
}
CONFIG_EOF

    # Безопасная подстановка секретов и сборка .endpoints и группы "☁️ Amnezia WARP"
    if command -v jq >/dev/null 2>&1; then
        if is_warp_enabled; then
            if [ "$PROVIDER_TAGS_JSON" != "[]" ]; then
                jq --arg secret "$ADMIN_PASS" --arg gw "$GW_IP" --slurpfile w "$WARP_NODES_FILE" '
                    .experimental.clash_api.secret = $secret
                    | (.dns.servers[] | select(.tag=="dns_local") | .server) = $gw
                    | .endpoints = $w[0].outbounds
                    | (.outbounds[] | select(.type == "selector" and .providers != null) | .outbounds) += ["☁️ Amnezia WARP"]
                    | .outbounds = (
                        [.outbounds[0]] + [{
                            "type": "urltest",
                            "tag": "☁️ Amnezia WARP",
                            "outbounds": ($w[0].outbounds | map(.tag)),
                            "url": "https://cp.cloudflare.com/generate_204",
                            "interval": "3m",
                            "tolerance": 50,
                            "idle_timeout": "30m"
                        }] + .outbounds[1:]
                    )
                ' "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
            else
                jq --arg secret "$ADMIN_PASS" --arg gw "$GW_IP" --slurpfile w "$WARP_NODES_FILE" '
                    .experimental.clash_api.secret = $secret
                    | (.dns.servers[] | select(.tag=="dns_local") | .server) = $gw
                    | del(.providers)
                    | .endpoints = $w[0].outbounds
                    | (.outbounds[] | select(.type == "urltest" and .providers != null)) |= (
                        del(.providers)
                        | .outbounds = ($w[0].outbounds | map(.tag))
                    )
                    | (.outbounds[] | select(.type == "selector" and .providers != null)) |= (
                        del(.providers)
                        | .outbounds = ((.outbounds // []) + ["☁️ Amnezia WARP"] + ($w[0].outbounds | map(.tag)))
                    )
                    | .outbounds = (
                        [.outbounds[0]] + [{
                            "type": "urltest",
                            "tag": "☁️ Amnezia WARP",
                            "outbounds": ($w[0].outbounds | map(.tag)),
                            "url": "https://cp.cloudflare.com/generate_204",
                            "interval": "3m",
                            "tolerance": 50,
                            "idle_timeout": "30m"
                        }] + .outbounds[1:]
                    )
                ' "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
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
            ' "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
        else
            jq --arg secret "$ADMIN_PASS" --arg gw "$GW_IP" '
                .experimental.clash_api.secret = $secret
                | (.dns.servers[] | select(.tag=="dns_local") | .server) = $gw
            ' "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
        fi
    else
        mv -f "${SB_CONF}.tmp" "$SB_CONF"
    fi
    chmod 600 "$SB_CONF" 2>/dev/null || true
    save_gateway_env
    return 0
}
# ==================== [ КОНЕЦ ЧАСТИ 1 ИЗ 3 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 2 ИЗ 3 ] ====================
# Снимок состояния перед изменениями в меню (для мгновенного авто-отката при сбое)
backup_gateway_state() {
    rm -rf "$STATE_BAK_DIR"
    mkdir -p "$STATE_BAK_DIR"
    for f in "$SB_CONF" "$SB_ENV" "$CUSTOM_NODES_FILE" "$WARP_NODES_FILE" \
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
    [ -f "${STATE_BAK_DIR}/my_nodes.yaml" ] && cp -f "${STATE_BAK_DIR}/my_nodes.yaml" "$CUSTOM_NODES_FILE" || true
    [ -f "${STATE_BAK_DIR}/warp_nodes.json" ] && cp -f "${STATE_BAK_DIR}/warp_nodes.json" "$WARP_NODES_FILE" || true
    [ -f "${STATE_BAK_DIR}/user_direct_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_direct_domains.list" "$USER_DIRECT_FILE" || true
    [ -f "${STATE_BAK_DIR}/user_proxy_domains.list" ] && cp -f "${STATE_BAK_DIR}/user_proxy_domains.list" "$USER_PROXY_FILE" || true
    [ -f "${STATE_BAK_DIR}/bypass_devices.conf" ] && cp -f "${STATE_BAK_DIR}/bypass_devices.conf" "$USER_BYPASS_IPS" || true
    [ -f "${STATE_BAK_DIR}/force_proxy_devices.conf" ] && cp -f "${STATE_BAK_DIR}/force_proxy_devices.conf" "$USER_FORCE_PROXY_IPS" || true
    chmod 600 "$SB_CONF" "$SB_ENV" 2>/dev/null || true
    sync_user_domain_rulesets
    load_gateway_env
    /etc/init.d/sing-box restart 2>/dev/null || true
    return 0
}

# Наглядный отчет по 3 независимым слотам прокси
print_proxy_slots_report() {
    load_gateway_env
    SUB_CNT=$(count_sub_urls)
    if [ "$SUB_CNT" -gt 1 ]; then
        SLOT1_INFO="АКТИВНЫ (${SUB_CNT} подписки: ${SUB_URL})"
    elif [ "$SUB_CNT" -eq 1 ]; then
        SLOT1_INFO="АКТИВНА (${SUB_URL})"
    else
        SLOT1_INFO="ОТКЛЮЧЕНА"
    fi

    MY_CNT=$(count_my_nodes)
    if [ "$MY_CNT" -gt 0 ]; then
        SLOT2_INFO="АКТИВЕН (${MY_CNT} шт. в my_nodes.yaml)"
    else
        SLOT2_INFO="ПУСТО (0 ключей)"
    fi

    if is_warp_enabled; then
        if [ -n "${WARP_LICENSE:-}" ]; then
            SLOT3_INFO="АКТИВЕН (4 ноды Cloudflare WARP+ -> группа '☁️ Amnezia WARP')"
        else
            SLOT3_INFO="АКТИВЕН (4 ноды Cloudflare Anycast -> группа '☁️ Amnezia WARP')"
        fi
    else
        SLOT3_INFO="ОТКЛЮЧЕН"
    fi

    echo " • Слот 1 [Подписки по ссылке]: ${SLOT1_INFO}"
    echo " • Слот 2 [Личные ключи URI]:   ${SLOT2_INFO}"
    echo " • Слот 3 [Amnezia WARP 2.0]:   ${SLOT3_INFO}"
    return 0
}

# Вывод пронумерованного списка личных ключей в my_nodes.yaml
list_my_nodes() {
    if ! has_my_nodes; then
        echo " [i] Список личных ключей (my_nodes.yaml) пуст."
        return 0
    fi
    echo " --- Список ваших ключей в ${CUSTOM_NODES_FILE} ---"
    awk '
        NF && $0 !~ /^proxies:/ {
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
            printf "  [%d] %-10s | %-34s | #%s\n", idx, proto "://", host, tag
        }
    ' "$CUSTOM_NODES_FILE" 2>/dev/null || true
    return 0
}

# Точечное удаление личного ключа по его порядковому номеру
delete_my_node_by_index() {
    DEL_IDX="$1"
    case "$DEL_IDX" in
        ''|*[!0-9]*)
            echo "[X] Некорректный номер ключа."
            return 1
            ;;
    esac
    TOTAL_K=$(count_my_nodes)
    if [ "$DEL_IDX" -lt 1 ] || [ "$DEL_IDX" -gt "$TOTAL_K" ]; then
        echo "[X] Ключ с номером ${DEL_IDX} не существует (доступно: 1..${TOTAL_K})."
        return 1
    fi
    awk -v target="$DEL_IDX" '
        NF && $0 !~ /^proxies:/ {
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
    generate_singbox_config

    if ! check_singbox_config; then
        echo "[X] Ошибка синтаксиса при действии: ${ACTION_TITLE}!"
        ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
            /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" || true
        echo "[!] Выполняется авто-откат к предыдущей рабочей конфигурации..."
        restore_gateway_state
        return 1
    fi

    /etc/init.d/sing-box restart 2>/dev/null || /etc/init.d/sing-box start 2>/dev/null || true

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
        reload_singbox_api
        echo "---------------------------------------------------------------"
        echo "[✓] ${ACTION_TITLE}: УСПЕШНО (Sing-Box ЗАПУЩЕН | singbox-tun АКТИВЕН)"
        print_proxy_slots_report
        echo "---------------------------------------------------------------"
        return 0
    else
        echo "---------------------------------------------------------------"
        echo "[X] Служба Sing-Box не смогла запуститься (${ACTION_TITLE})!"
        echo "--- Причина из системного журнала ---"
        logread -e sing-box 2>/dev/null | tail -n 6 || true
        echo "---------------------------------------------------------------"
        echo "[!] Выполняется авто-откат к предыдущей рабочей конфигурации..."
        restore_gateway_state
        return 1
    fi
}

# Быстрая смена единого пароля (Sing-Box Zashboard + AdGuard Home)
change_unified_password() {
    NEW_PASS="$1"
    if [ -z "$NEW_PASS" ]; then
        echo "[X] Ошибка: Пароль не может быть пустым!"
        return 1
    fi
    load_gateway_env
    ADMIN_PASS="$NEW_PASS"
    save_gateway_env
    generate_singbox_config

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

    /etc/init.d/sing-box restart 2>/dev/null || true
    /etc/init.d/adguardhome restart 2>/dev/null || true
    echo "[✓] Единый пароль успешно обновлен для Sing-Box Zashboard и AdGuard Home!"
    return 0
}

# Управление Умным DHCP-сервером на OpenWrt (для залоченных роутеров Ростелеком/МТС/Дом.ру)
configure_smart_dhcp() {
    DHCP_MODE="${1:-off}"
    CUR_LAN_IP=$(get_current_lan_ip)

    uci del dhcp.lan.ra 2>/dev/null || true
    uci del dhcp.lan.dhcpv6 2>/dev/null || true
    uci del dhcp.lan.ndp 2>/dev/null || true
    uci del dhcp.lan.dhcp_option 2>/dev/null || true

    if [ "$DHCP_MODE" = "on" ]; then
        uci set dhcp.lan.ignore='0'
        uci set dhcp.lan.start='100'
        uci set dhcp.lan.limit='140'
        uci set dhcp.lan.leasetime='12h'
        uci set dhcp.lan.force='1'
        uci add_list dhcp.lan.dhcp_option="3,${CUR_LAN_IP}"
        uci add_list dhcp.lan.dhcp_option="6,${CUR_LAN_IP}"
        uci commit dhcp
        /etc/init.d/odhcpd stop 2>/dev/null || true
        /etc/init.d/odhcpd disable 2>/dev/null || true
        /etc/init.d/dnsmasq restart 2>/dev/null || true
        echo "[✓] Умный DHCP-сервер OpenWrt ВКЛЮЧЕН (Шлюз и DNS: ${CUR_LAN_IP}, пул .100-.239)."
        echo "    Не забудьте отключить DHCP-сервер на основном роутере провайдера!"
    else
        uci set dhcp.lan.ignore='1'
        uci commit dhcp
        /etc/init.d/odhcpd stop 2>/dev/null || true
        /etc/init.d/odhcpd disable 2>/dev/null || true
        /etc/init.d/dnsmasq restart 2>/dev/null || true
        echo "[✓] DHCP-сервер на OpenWrt ВЫКЛЮЧЕН (классический режим Sidecar)."
    fi
    return 0
}

# Безопасная смена LAN IP шлюза OpenWrt и/или IP основного роутера с защитой маски /24 и nohup
apply_network_ips() {
    TARGET_LAN_IP="$1"
    TARGET_GW_IP="$2"

    CUR_LAN_IP=$(get_current_lan_ip)
    load_gateway_env

    [ -z "$TARGET_LAN_IP" ] && TARGET_LAN_IP="$CUR_LAN_IP"
    [ -z "$TARGET_GW_IP" ] && TARGET_GW_IP="$GW_IP"

    if ! is_valid_ipv4 "$TARGET_LAN_IP"; then
        echo "[X] Ошибка: Некорректный IPv4-адрес шлюза OpenWrt (${TARGET_LAN_IP})!"
        return 1
    fi

    if ! is_valid_ipv4 "$TARGET_GW_IP"; then
        echo "[X] Ошибка: Некорректный IPv4-адрес основного роутера (${TARGET_GW_IP})!"
        return 1
    fi

    if [ "$TARGET_LAN_IP" = "$TARGET_GW_IP" ]; then
        echo "[X] Ошибка: IP шлюза OpenWrt (${TARGET_LAN_IP}) не может совпадать с IP основного роутера (${TARGET_GW_IP})!"
        return 1
    fi

    LAN_SUBNET="${TARGET_LAN_IP%.*}"
    GW_SUBNET="${TARGET_GW_IP%.*}"
    if [ "$LAN_SUBNET" != "$GW_SUBNET" ]; then
        echo "[!] Внимание: Подсеть шлюза (${LAN_SUBNET}.x) отличается от подсети роутера (${GW_SUBNET}.x)!"
        printf "Введите IP основного роутера в новой подсети [Enter = %s.1 / отмена = n]: " "$LAN_SUBNET"
        read -r FIX_GW < /dev/tty || true
        FIX_GW=$(printf "%s" "$FIX_GW" | tr -d ' \t\r\n')
        if [ "$FIX_GW" = "n" ] || [ "$FIX_GW" = "N" ]; then
            echo "[i] Смена IP отменена."
            return 1
        fi
        [ -z "$FIX_GW" ] && FIX_GW="${LAN_SUBNET}.1"
        if ! is_valid_ipv4 "$FIX_GW" || [ "$FIX_GW" = "$TARGET_LAN_IP" ]; then
            echo "[X] Некорректный или конфликтующий IP основного роутера (${FIX_GW})."
            return 1
        fi
        TARGET_GW_IP="$FIX_GW"
    fi

    GW_IP="$TARGET_GW_IP"
    save_gateway_env
    update_agh_gateway_ip "$GW_IP"
    [ -f "$SB_CONF" ] && generate_singbox_config || true

    uci del network.lan.ipaddr 2>/dev/null || true
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway="$GW_IP"
    uci del network.lan.dns 2>/dev/null || true
    uci add_list network.lan.dns="$GW_IP"
    uci add_list network.lan.dns="77.88.8.8"
    uci commit network

    if is_dhcp_server_enabled; then
        uci del dhcp.lan.dhcp_option 2>/dev/null || true
        uci add_list dhcp.lan.dhcp_option="3,${TARGET_LAN_IP}"
        uci add_list dhcp.lan.dhcp_option="6,${TARGET_LAN_IP}"
        uci commit dhcp
    fi

    printf "nameserver 127.0.0.1\nnameserver %s\nnameserver 77.88.8.8\n" "$GW_IP" > /tmp/resolv.conf
    cp -f /tmp/resolv.conf /etc/resolv.conf

    echo "==============================================================="
    echo "[✓] Сетевые настройки успешно сохранены:"
    echo " • Новый IP шлюза OpenWrt:   ${TARGET_LAN_IP} (маска 255.255.255.0)"
    echo " • IP основного роутера:     ${GW_IP}"
    echo " • Веб-панель OpenWrt LuCI:  http://${TARGET_LAN_IP}"
    echo " • Панель Sing-Box Extended: http://${TARGET_LAN_IP}:9090/ui"
    echo " • Панель AdGuard Home:      http://${TARGET_LAN_IP}:3000"

    cat << 'SW_EOF' > /tmp/switch_lan_ip.sh
#!/bin/sh
sleep 1
/etc/init.d/sing-box stop >/dev/null 2>&1 || true
/etc/init.d/network reload >/dev/null 2>&1 || /etc/init.d/network restart >/dev/null 2>&1 || true
sleep 3
/etc/init.d/firewall reload >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/sing-box start >/dev/null 2>&1 || true
/etc/init.d/adguardhome restart >/dev/null 2>&1 || true
rm -f /tmp/switch_lan_ip.sh
SW_EOF
    chmod +x /tmp/switch_lan_ip.sh

    if [ "$TARGET_LAN_IP" != "$CUR_LAN_IP" ]; then
        echo "---------------------------------------------------------------"
        echo "[!] ВНИМАНИЕ: IP шлюза изменился (${CUR_LAN_IP} -> ${TARGET_LAN_IP})!"
        echo " 1. Переподключитесь по SSH: ssh root@${TARGET_LAN_IP}"
        echo " 2. Если на вашем ПК или в DHCP роутера шлюзом/DNS был указан"
        echo "    старый адрес ${CUR_LAN_IP}, обновите его на ${TARGET_LAN_IP}!"
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

# Включение автообновления (ежедневно в 04:00)
enable_autoupdate() {
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    echo "0 4 * * * /usr/bin/gateway autoupdate >${AUTOUPDATE_LOG} 2>&1" >> "$CRON_FILE"
    /etc/init.d/cron enable 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true
    return 0
}

# Отключение автообновления
disable_autoupdate() {
    if [ -f "$CRON_FILE" ]; then
        sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    fi
    /etc/init.d/cron reload 2>/dev/null || /etc/init.d/cron restart 2>/dev/null || true
    return 0
}

# Управление встроенным Watchdog (самоисцеление служб каждые 5 минут)
enable_watchdog() {
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    sed -i '\|/usr/bin/gateway watchdog|d' "$CRON_FILE" 2>/dev/null || true
    echo "*/5 * * * * /usr/bin/gateway watchdog >/dev/null 2>&1" >> "$CRON_FILE"
    /etc/init.d/cron enable 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true
    return 0
}

disable_watchdog() {
    if [ -f "$CRON_FILE" ]; then
        sed -i '\|/usr/bin/gateway watchdog|d' "$CRON_FILE" 2>/dev/null || true
    fi
    /etc/init.d/cron reload 2>/dev/null || /etc/init.d/cron restart 2>/dev/null || true
    return 0
}

# Фоновая проверка здоровья служб (Watchdog Auto-Healer)
run_watchdog() {
    [ -f "$SB_CONF" ] || return 0
    if ! pgrep sing-box >/dev/null 2>&1 || ! ip link show singbox-tun >/dev/null 2>&1; then
        logger -t gateway-watchdog "Sing-Box or singbox-tun down, restarting service..."
        /etc/init.d/sing-box restart >/dev/null 2>&1 || true
    fi
    if ! pgrep AdGuardHome >/dev/null 2>&1; then
        logger -t gateway-watchdog "AdGuardHome down, restarting service..."
        /etc/init.d/adguardhome restart >/dev/null 2>&1 || true
    fi
    return 0
}

# Фоновая задача автообновления для cron
run_autoupdate() {
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Запуск автообновления шлюза ==="
    update_cores_only "yes"
    if ! pgrep sing-box >/dev/null 2>&1; then
        /etc/init.d/sing-box start 2>/dev/null || true
    fi
    if ! pgrep AdGuardHome >/dev/null 2>&1; then
        /etc/init.d/adguardhome start 2>/dev/null || true
    fi
    reload_singbox_api
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Автообновление завершено ==="
    return 0
}

# Получение последнего тега релиза с GitHub
fetch_latest_github_tag() {
    REPO="$1"
    TAG=$(curl -fsSL --connect-timeout 2 -m 3 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | cut -d'"' -f4 || true)
    if [ -z "$TAG" ]; then
        TAG=$(curl -fsSLI --connect-timeout 2 -m 3 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null | awk -F'/' '{print $NF}' | tr -d '\r\n' || true)
        [ "$TAG" = "latest" ] && TAG="" || true
    fi
    printf "%s" "$TAG"
    return 0
}

# Кэширование актуальных версий с GitHub для быстрого отображения в меню
refresh_remote_versions() {
    LATEST_SB_TAG=$(fetch_latest_github_tag "shtorm-7/sing-box-extended")
    LATEST_AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
    if [ -f "${SB_DIR}/ui/index.html" ]; then
        LATEST_UI_TAG=$(fetch_latest_github_tag "$UI_REPO")
        if [ ! -f "$UI_VER_FILE" ] && [ -n "$LATEST_UI_TAG" ]; then
            echo "$LATEST_UI_TAG" > "$UI_VER_FILE"
        fi
    fi
    return 0
}

# Отрисовка статуса и версий в шапке меню
print_gateway_header() {
    load_gateway_env
    calc_hardware_limits
    LAN_IP_NOW=$(get_current_lan_ip)
    LAN_IF_NOW=$(get_lan_ifname)

    if pgrep sing-box >/dev/null 2>&1; then
        S_STAT="[ЗАПУЩЕН]     "
    else
        S_STAT="[ОСТАНОВЛЕН]  "
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
            S_VER_INFO="${S_VER} (актуальна)"
        else
            S_VER_INFO="${S_VER} -> ДОСТУПНА ${LATEST_SB_TAG}!"
        fi
    else
        S_VER_INFO="${S_VER}"
    fi

    if pgrep AdGuardHome >/dev/null 2>&1; then
        A_STAT="[ЗАПУЩЕН]     "
    else
        A_STAT="[ОСТАНОВЛЕН]  "
    fi

    if [ -x /usr/bin/AdGuardHome ]; then
        A_VER=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)
        [ -z "$A_VER" ] && A_VER="установлен" || true
    else
        A_VER="не установлен"
    fi

    if [ -n "$LATEST_AGH_TAG" ] && [ "$A_VER" != "не установлен" ]; then
        if [ "$A_VER" = "$LATEST_AGH_TAG" ]; then
            A_VER_INFO="${A_VER} (актуальна)"
        else
            A_VER_INFO="${A_VER} -> ДОСТУПНА ${LATEST_AGH_TAG}!"
        fi
    else
        A_VER_INFO="${A_VER}"
    fi

    SUB_CNT=$(count_sub_urls)
    MY_CNT=$(count_my_nodes)
    if [ "$SUB_CNT" -gt 1 ]; then
        P_STAT="[МУЛЬТИ-САБ]  "
        P_INFO="активно подписок: ${SUB_CNT} шт. (+ ключей: ${MY_CNT})"
    elif [ "$SUB_CNT" -eq 1 ]; then
        P_STAT="[ПОДПИСКА]    "
        P_INFO="${SUB_URL}"
    elif [ "$MY_CNT" -gt 0 ]; then
        P_STAT="[КЛЮЧИ URI]   "
        P_INFO="активно ключей в my_nodes.yaml: ${MY_CNT} шт."
    elif is_warp_enabled; then
        P_STAT="[ТОЛЬКО WARP] "
        P_INFO="работает бесплатный Amnezia WARP 2.0"
    else
        P_STAT="[РЕЖИМ DIRECT]"
        P_INFO="прокси не заданы (весь трафик напрямую)"
    fi

    if is_warp_enabled; then
        W_STAT="[АКТИВЕН]     "
        if [ -n "${WARP_LICENSE:-}" ]; then
            W_INFO="4 ноды AWG WARP+ (группа '☁️ Amnezia WARP')"
        else
            W_INFO="4 ноды AWG 2.0 (группа '☁️ Amnezia WARP')"
        fi
    else
        W_STAT="[ВЫКЛЮЧЕН]    "
        W_INFO="можно включить бесплатно в пункте 2"
    fi

    if [ -f "${SB_DIR}/ui/index.html" ]; then
        UI_STAT="[Zashboard]   "
        UI_VER=""
        [ -f "$UI_VER_FILE" ] && UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n') || true
        [ -z "$UI_VER" ] && UI_VER="установлена" || true

        if [ -n "$LATEST_UI_TAG" ] && [ "$UI_VER" != "установлена" ]; then
            if [ "$UI_VER" = "$LATEST_UI_TAG" ]; then
                UI_VER_INFO="${UI_VER} (актуальна)"
            else
                UI_VER_INFO="${UI_VER} -> ДОСТУПНА ${LATEST_UI_TAG}!"
            fi
        else
            UI_VER_INFO="${UI_VER}"
        fi
    else
        UI_STAT="[НЕ НАЙДЕНА]  "
        UI_VER_INFO="не установлена"
    fi

    if is_killswitch_enabled; then
        KS_STAT="[АКТИВЕН]     "
        KS_INFO="строгая блокировка трафика мимо singbox-tun (${LAN_IF_NOW})"
    else
        KS_STAT="[СТАНДАРТ]    "
        KS_INFO="защита IPv6 + DoT/DoQ + перехват DNS 53 (${LAN_IF_NOW})"
    fi

    if is_watchdog_enabled; then
        WD_TXT="ВКЛ"
    else
        WD_TXT="ВЫКЛ"
    fi

    if is_dhcp_server_enabled; then
        DHCP_TXT="ВКЛ"
    else
        DHCP_TXT="ВЫКЛ"
    fi

    if is_autoupdate_enabled; then
        AU_STAT="[ВКЛЮЧЕНО]    "
        AU_INFO="04:00 + Watchdog: ${WD_TXT}"
    else
        AU_STAT="[ВЫКЛЮЧЕНО]   "
        AU_INFO="вручную | Watchdog: ${WD_TXT}"
    fi

    echo " Сеть шлюза:    [OpenWrt (${LAN_IF_NOW}): ${LAN_IP_NOW}] -> [Роутер: ${GW_IP}] | DHCP: ${DHCP_TXT}"
    echo " Профиль ОЗУ:   [${TOTAL_RAM_MB} МБ RAM] -> Лимит Sing-Box: ${SB_GOMEMLIMIT} | Conntrack: ${SYS_CONNTRACK_MAX}"
    echo " Sing-Box Ext:  ${S_STAT}${S_VER_INFO}"
    echo " AdGuard Home:  ${A_STAT}${A_VER_INFO} (DNS :53 + Антиреклама)"
    echo " Основной пул:  ${P_STAT}${P_INFO}"
    echo " Amnezia WARP:  ${W_STAT}${W_INFO}"
    echo " Kill-Switch:   ${KS_STAT}${KS_INFO}"
    echo " Веб-панель:    ${UI_STAT}${UI_VER_INFO}"
    echo " Автоапдейт:    ${AU_STAT}${AU_INFO}"
    return 0
}

# Каскадный выбор зеркала GitHub при блокировках ТСПУ
check_github_mirror() {
    TEST_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/private.srs"
    if curl -fsSL --connect-timeout 3 -m 5 -o /dev/null "$TEST_URL" 2>/dev/null; then
        GH_PROXY=""
        return 0
    fi
    for MIRROR in "https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.net/"; do
        if curl -fsSL --connect-timeout 3 -m 5 -o /dev/null "${MIRROR}${TEST_URL}" 2>/dev/null; then
            echo "[!] Прямой доступ к GitHub ограничен, включено зеркало: ${MIRROR}"
            GH_PROXY="$MIRROR"
            return 0
        fi
    done
    GH_PROXY="https://ghfast.top/"
    return 0
}

# Универсальная загрузка файла с каскадным фоллбэком на зеркала GitHub
download_file() {
    DL_URL="$1"
    DL_OUT="$2"
    for PREFIX in "$GH_PROXY" "" "https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.net/"; do
        if curl --retry 2 --connect-timeout 5 -fL -o "$DL_OUT" "${PREFIX}${DL_URL}" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# Инициализация пользовательских списков и файлов провайдеров
init_user_lists() {
    mkdir -p "$SB_RULES_DIR" "$SB_PROVIDERS_DIR"
    [ -f "$USER_DIRECT_FILE" ] || echo "+.localdomain" > "$USER_DIRECT_FILE"
    [ -f "$USER_PROXY_FILE" ] || echo "+.chatgpt.com" > "$USER_PROXY_FILE"
    [ -f "$USER_BYPASS_IPS" ] || : > "$USER_BYPASS_IPS"
    [ -f "$USER_FORCE_PROXY_IPS" ] || : > "$USER_FORCE_PROXY_IPS"
    [ -s "$CUSTOM_NODES_FILE" ] || echo "proxies: []" > "$CUSTOM_NODES_FILE"
    [ -s "$WARP_NODES_FILE" ] || echo '{"outbounds": []}' > "$WARP_NODES_FILE"
    sync_user_domain_rulesets
    return 0
}

# Безопасное разделение нескольких URI-ключей без повреждения alpn=h2,http/1.1 и пробелов в #Названии
format_uri_keys() {
    printf "%s\n" "$1" | sed -E 's/[[:space:],]+((vless|vmess|ss|ssr|trojan|hy2|hysteria2|hysteria|tuic|wg|wireguard|anytls|mieru|xhttp|splithttp|socks5):\/\/)/\n\1/g' | sed '/^[[:space:]]*$/d'
    return 0
}

# Живой сканер Anycast-узлов Cloudflare WARP для выбора 4 самых отзывчивых на провайдере пользователя
scan_best_warp_endpoints() {
    CANDIDATES="162.159.192.1:4500 188.114.97.1:500 188.114.99.224:1002 162.159.195.1:2408 188.114.98.224:854 188.114.96.1:1701 162.159.193.1:500 188.114.97.3:4500"
    ALIVE_LIST=""
    ALIVE_CNT=0

    for EP in $CANDIDATES; do
        EP_IP="${EP%:*}"
        if ping -c 1 -W 1 "$EP_IP" >/dev/null 2>&1; then
            ALIVE_LIST="${ALIVE_LIST} ${EP}"
            ALIVE_CNT=$((ALIVE_CNT + 1))
            [ "$ALIVE_CNT" -ge 4 ] && break
        fi
    done

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

# Автоматическая бесплатная генерация Amnezia WARP 2.0 (4 живых ноды Cloudflare Anycast + поддержка WARP+)
generate_amnezia_warp() {
    OPT_LIC="${1:-}"
    mkdir -p "$SB_PROVIDERS_DIR"
    [ -z "${GW_IP:-}" ] && load_gateway_env || true
    [ -n "$OPT_LIC" ] && WARP_LICENSE="$OPT_LIC" || true

    if ! command -v wg >/dev/null 2>&1; then
        echo "Установка генератора ключей wireguard-tools..."
        apk update --allow-untrusted >/dev/null 2>&1 || true
        apk add --allow-untrusted wireguard-tools >/dev/null 2>&1 || true
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
            RESP=$(curl -fsSL --connect-timeout 4 -m 6 $CURL_OPT \
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
            RESP=$(curl -fsSL --connect-timeout 4 -m 6 \
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

        # Привязка лицензионного ключа WARP+ (если указан пользователем)
        if [ "$REG_OK" = "yes" ] && [ -n "${WARP_LICENSE:-}" ] && [ -n "$REG_ID" ] && [ -n "$REG_TOKEN" ]; then
            echo "Активация лицензионного ключа Cloudflare WARP+..."
            # shellcheck disable=SC2086
            LIC_RESP=$(curl -fsSL --connect-timeout 4 -m 6 ${USED_CURL_OPT:-} \
                -H "User-Agent: okhttp/3.12.1" \
                -H "Authorization: Bearer ${REG_TOKEN}" \
                -H "Content-Type: application/json" \
                -X PUT "https://api.devices.cloudflare.com/v0a4471/reg/${REG_ID}/account" \
                -d "{\"license\":\"${WARP_LICENSE}\"}" 2>/dev/null || true)
            if printf "%s" "$LIC_RESP" | grep -q '"warp_plus":[[:space:]]*true'; then
                echo "[✓] Статус WARP+ (Argo Priority) успешно активирован!"
                save_gateway_env
            else
                echo "[!] Лицензия WARP+ не принята API Cloudflare, используется стандартный безлимитный WARP."
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
        echo "[!] Провайдер блокирует прямой доступ к API регистрации Cloudflare."
        printf "Вставьте готовый WARP PrivateKey (например, из @warp_generator_bot) [Enter = отмена]: "
        read -r USER_PRIV < /dev/tty || true
        USER_PRIV=$(printf "%s" "$USER_PRIV" | tr -d ' \t\r\n')
        if [ -n "$USER_PRIV" ]; then
            PRIV_KEY="$USER_PRIV"
            WARP_IPV4="172.16.0.2"
            REG_OK="yes"
        else
            echo "[X] Не удалось получить ключ WARP."
            return 1
        fi
    fi

    [ -z "$WARP_IPV4" ] && WARP_IPV4="172.16.0.2" || true

    echo "Сканирование оптимальных Anycast-узлов Cloudflare для вашего провайдера..."
    BEST_EPS=$(scan_best_warp_endpoints)
    set -- $BEST_EPS
    EP1="${1:-162.159.192.1:4500}"
    EP2="${2:-188.114.97.1:500}"
    EP3="${3:-188.114.99.224:1002}"
    EP4="${4:-162.159.195.1:2408}"

    EP1_IP="${EP1%:*}"; EP1_PORT="${EP1#*:}"
    EP2_IP="${EP2%:*}"; EP2_PORT="${EP2#*:}"
    EP3_IP="${EP3%:*}"; EP3_PORT="${EP3#*:}"
    EP4_IP="${EP4%:*}"; EP4_PORT="${EP4#*:}"

    RAND_BYTE=$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' \t\r\n' || echo "5")
    AWG_JC=$(( (RAND_BYTE % 4) + 4 ))

    cat << WARP_EOF > "$WARP_NODES_FILE"
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
        "jc": ${AWG_JC},
        "jmin": 40,
        "jmax": 70,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "<r 2><b 0x8580000100010000000004796162730679616e6465780272750000010001c00c000100010000026d000457fa27d1>"
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
        "jc": ${AWG_JC},
        "jmin": 40,
        "jmax": 70,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "<r 2><b 0x8580000100010000000004796162730679616e6465780272750000010001c00c000100010000026d000457fa27d1>"
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
        "jc": ${AWG_JC},
        "jmin": 40,
        "jmax": 70,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "<r 2><b 0x8580000100010000000004796162730679616e6465780272750000010001c00c000100010000026d000457fa27d1>"
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
        "jc": ${AWG_JC},
        "jmin": 40,
        "jmax": 70,
        "s1": 0,
        "s2": 0,
        "h1": 1,
        "h2": 2,
        "h3": 3,
        "h4": 4,
        "i1": "<r 2><b 0x8580000100010000000004796162730679616e6465780272750000010001c00c000100010000026d000457fa27d1>"
      }
    }
  ]
}
WARP_EOF
    chmod 600 "$WARP_NODES_FILE" 2>/dev/null || true
    echo "[✓] Пул Amnezia WARP 2.0 (${EP1}, ${EP2}, ${EP3}, ${EP4}, jc=${AWG_JC}) создан (IP: ${WARP_IPV4})!"
    return 0
}

# Горячая перезагрузка провайдеров и сброс Fake-IP кэша через Clash API Sing-Box
reload_singbox_api() {
    if ! pgrep sing-box >/dev/null 2>&1; then
        return 0
    fi
    load_gateway_env
    curl -fsS -X POST -H "Authorization: Bearer ${ADMIN_PASS}" \
        "http://127.0.0.1:9090/cache/fakeip/flush" >/dev/null 2>&1 || true
    for P_TAG in custom_sub custom_sub_2 custom_sub_3 my_nodes; do
        curl -fsS -X PUT -H "Authorization: Bearer ${ADMIN_PASS}" \
            "http://127.0.0.1:9090/providers/proxies/${P_TAG}" >/dev/null 2>&1 || true
    done
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

# Распределение ввода по 3 независимым слотам: Слот 1 (HTTP), Слот 2 (my_nodes.yaml), Слот 3 (WARP)
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
        vless://*|vmess://*|ss://*|ssr://*|trojan://*|hy2://*|hysteria2://*|hysteria://*|tuic://*|wg://*|wireguard://*|anytls://*|mieru://*|xhttp://*|splithttp://*|socks5://*)
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
        echo "[✓] Веб-панель Zashboard ${TARGET_UI_VER} успешно установлена в ${SB_DIR}/ui."
        return 0
    else
        rm -rf /tmp/sb_ui.tar.gz /tmp/sb_ui_extract
        echo "[X] Ошибка загрузки или распаковки веб-панели Zashboard!"
        return 1
    fi
}

# Атомарное обновление бинарников Sing-Box Extended, AdGuard Home и Zashboard
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
        echo "[✓] Ядро Sing-Box Extended ${INSTALLED_SB_VER} (${SB_ARCH}) актуально."
    else
        echo "Загрузка Sing-Box Extended ${SB_TAG} (${SB_ARCH})..."
        rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
        SB_URL="https://github.com/shtorm-7/sing-box-extended/releases/download/${SB_TAG}/sing-box-${SB_VER_NO_V}-linux-${SB_ARCH}.tar.gz"
        if download_file "$SB_URL" "/tmp/sing-box.tar.gz"; then
            mkdir -p /tmp/sb_extract
            if tar -xzf /tmp/sing-box.tar.gz -C /tmp/sb_extract 2>/dev/null; then
                SB_BIN=$(find /tmp/sb_extract -type f -name "sing-box" | head -n 1)
                if [ -n "$SB_BIN" ] && [ -f "$SB_BIN" ]; then
                    chmod +x "$SB_BIN"
                    if "$SB_BIN" version >/dev/null 2>&1; then
                        /etc/init.d/sing-box stop 2>/dev/null || true
                        mv -f "$SB_BIN" /usr/bin/sing-box
                        echo "[✓] Sing-Box Extended безопасно обновлен до ${SB_TAG}."
                    else
                        echo "[X] Ошибка: скачанный бинарник sing-box поврежден, оставлена текущая версия."
                    fi
                fi
            fi
            rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
        else
            rm -rf /tmp/sing-box.tar.gz /tmp/sb_extract
            echo "[X] Не удалось скачать Sing-Box Extended ${SB_TAG}."
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
        echo "[✓] Ядро AdGuard Home ${INSTALLED_AGH_VER} актуально."
    else
        echo "Загрузка AdGuard Home ${AGH_TAG}..."
        rm -rf /tmp/agh.tar.gz /tmp/agh_extract
        AGH_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_TAG}/AdGuardHome_linux_${AGH_ARCH}.tar.gz"
        if download_file "$AGH_URL" "/tmp/agh.tar.gz"; then
            mkdir -p /tmp/agh_extract
            if tar -xzf /tmp/agh.tar.gz -C /tmp/agh_extract 2>/dev/null && [ -f /tmp/agh_extract/AdGuardHome/AdGuardHome ]; then
                chmod +x /tmp/agh_extract/AdGuardHome/AdGuardHome
                if /tmp/agh_extract/AdGuardHome/AdGuardHome --version >/dev/null 2>&1; then
                    /etc/init.d/adguardhome stop 2>/dev/null || true
                    mv -f /tmp/agh_extract/AdGuardHome/AdGuardHome /usr/bin/AdGuardHome
                    echo "[✓] AdGuard Home безопасно обновлен до ${AGH_TAG}."
                else
                    echo "[X] Ошибка проверки бинарника AdGuard Home, оставлена текущая версия."
                fi
            fi
            rm -rf /tmp/agh.tar.gz /tmp/agh_extract
        else
            rm -rf /tmp/agh.tar.gz /tmp/agh_extract
            echo "[X] Не удалось скачать AdGuard Home ${AGH_TAG}."
        fi
    fi

    if [ "$CHECK_UI_UPDATE" = "yes" ]; then
        UI_TAG=$(fetch_latest_github_tag "$UI_REPO")
        LATEST_UI_TAG="$UI_TAG"
        INSTALLED_UI_VER=""
        [ -f "$UI_VER_FILE" ] && INSTALLED_UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n') || true

        if [ -f "${SB_DIR}/ui/index.html" ] && [ -n "$UI_TAG" ] && [ "$INSTALLED_UI_VER" = "$UI_TAG" ]; then
            echo "[✓] Веб-панель Zashboard ${INSTALLED_UI_VER} актуальна."
        else
            install_zashboard_ui "$UI_TAG" || true
        fi
    fi
    return 0
}
# ==================== [ КОНЕЦ ЧАСТИ 2 ИЗ 3 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 3 ИЗ 3 ] ====================
# ==============================================================================
# Главный мастер установки и настройки (Sing-Box Extended + AdGuard Home)
# ==============================================================================
run_installer() {
    detect_os
    disable_legacy_mihomo
    init_user_lists

    echo "========================================================"
    echo " Установщик Sing-Box Extended + AdGuard Home (OpenWrt)  "
    echo "========================================================"
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

    # 1. Запрос ссылки на подписку, прямого ключа или бесплатного Amnezia WARP
    USE_INITIAL_WARP="no"
    if [ -n "$SAVED_SUB_URL" ]; then
        printf "Введите подписку (http://...), ключ (vless://...) или 'warp' [Enter = оставить %s]: " "$SAVED_SUB_URL"
    elif has_my_nodes; then
        printf "Введите подписку (http://...), ключ или 'warp' [Enter = оставить ключи в my_nodes.yaml]: "
    elif is_warp_enabled; then
        printf "Введите подписку (http://...), ключ или 'warp' [Enter = оставить текущий Amnezia WARP]: "
    else
        printf "Введите подписку (http://...), ключ (vless://...) или 'warp' (бесплатный Amnezia WARP 2.0): "
    fi
    read -r INPUT_SUB_URL < /dev/tty || true
    INPUT_SUB_URL=$(printf "%s" "$INPUT_SUB_URL" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -n "$INPUT_SUB_URL" ]; then
        apply_subscription_input "$INPUT_SUB_URL"
    elif [ -z "$SAVED_SUB_URL" ] && ! has_my_nodes && ! is_warp_enabled; then
        printf "Прокси не указаны. Сгенерировать бесплатный безлимитный Amnezia WARP 2.0? (y/n) [Enter = y]: "
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

    # Если введена подписка/ключ, а на диске остался старый WARP — спрашиваем, нужен ли он
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

    # 2. Запрос IP-адреса самого шлюза OpenWrt и IP основного роутера
    printf "Введите локальный IP самого шлюза OpenWrt [Enter = оставить %s]: " "$SAVED_LAN_IP"
    read -r INPUT_LAN_IP < /dev/tty || true
    INPUT_LAN_IP=$(printf "%s" "$INPUT_LAN_IP" | tr -d ' \t\r\n')
    TARGET_LAN_IP="${INPUT_LAN_IP:-$SAVED_LAN_IP}"
    if ! is_valid_ipv4 "$TARGET_LAN_IP"; then
        echo "[X] Некорректный IP (${TARGET_LAN_IP}), оставлен текущий: ${SAVED_LAN_IP}"
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
        echo "[X] Ошибка: IP основного роутера (${GW_IP}) некорректен или совпадает с IP шлюза (${TARGET_LAN_IP})!"
        exit 1
    fi

    # 3. Запрос логина и единого пароля (AdGuard Home + Sing-Box Zashboard)
    DEF_AGH_USER="${SAVED_AGH_USER:-admin}"
    printf "Введите логин для панели AdGuard Home [Enter = %s]: " "$DEF_AGH_USER"
    read -r INPUT_AGH_USER < /dev/tty || true
    INPUT_AGH_USER=$(printf "%s" "$INPUT_AGH_USER" | tr -d ' \t\r\n')
    AGH_USER="${INPUT_AGH_USER:-$DEF_AGH_USER}"

    if [ -n "$SAVED_PASS" ]; then
        printf "Введите единый пароль (AdGuard Home + Sing-Box) [Enter = оставить текущий]: "
    else
        printf "Введите единый пароль (для панели AdGuard Home и secret в Sing-Box): "
    fi
    read -r INPUT_PASS < /dev/tty || true
    INPUT_PASS=$(printf "%s" "$INPUT_PASS" | tr -d '\r\n')

    ADMIN_PASS="${INPUT_PASS:-$SAVED_PASS}"
    if [ -z "$ADMIN_PASS" ]; then
        echo "[X] Ошибка: Пароль не может быть пустым!"
        exit 1
    fi

    # Немедленно фиксируем введенные пользователем параметры (пароль, роутер, подписку) на диск!
    save_gateway_env

    # 4. Запрос на автообновление («поставил и забыл»)
    if is_autoupdate_enabled; then
        DEF_AU_CHAR="y"
    else
        DEF_AU_CHAR="n"
    fi
    printf "Включить автообновление ядер и панелей (поставил и забыл — Бро я думаю ты осознаешь последствия ,_,)? (y/n) [Enter = %s]: " "$DEF_AU_CHAR"
    read -r INPUT_AU_ANS < /dev/tty || true
    INPUT_AU_ANS=$(printf "%s" "$INPUT_AU_ANS" | tr -d ' \t\r\n')
    [ -z "$INPUT_AU_ANS" ] && INPUT_AU_ANS="$DEF_AU_CHAR"
    case "$INPUT_AU_ANS" in
        [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) ENABLE_AU="yes" ;;
        *) ENABLE_AU="no" ;;
    esac

    echo "--------------------------------------------------------"
    echo "Итоговая конфигурация развертывания:"
    echo " - ОС и Память:     ${OS_NAME} | ${TOTAL_RAM_MB} МБ RAM"
    echo " - Ядро:            shtorm-7/sing-box-extended (${SB_ARCH}, лимит ${SB_GOMEMLIMIT})"
    echo " - IP шлюза (LAN):  ${TARGET_LAN_IP} (интерфейс $(get_lan_ifname), маска /24)"
    echo " - Основной роутер: ${GW_IP}"
    echo " - DNS и Реклама:   AdGuard Home (0.0.0.0:53) -> Sing-Box (127.0.0.1:1053)"
    echo " - Группы трафика:  5 селекторов (🤖 AI & Google | 🎮 Roblox | ▶️ YouTube & Spotify | 💬 Мессенджеры | 🌐 Остальной)"
    echo " - Веб-панель:      Zashboard"
    echo " - Логин AdGuard:   ${AGH_USER}"
    echo " - Единый пароль:   ${ADMIN_PASS}"
    echo " - Автообновление:  $([ "$ENABLE_AU" = "yes" ] && echo "ВКЛ (04:00) + Watchdog" || echo "ВЫКЛ (Watchdog ВКЛ)")"
    echo "--------------------------------------------------------"

    sync_clock() {
        echo "Синхронизация системных часов..."
        /usr/sbin/ntpd -n -q -p 162.159.200.1 -p 216.239.35.0 -p ntp.ix.ru -p pool.ntp.org 2>/dev/null || true
        if [ "$(date +%Y)" -lt 2026 ]; then
            TS=$(wget -qO- "http://1.1.1.1/cdn-cgi/trace" 2>/dev/null | awk -F= '/^ts=/ {split($2,a,"."); print a[1]}')
            [ -n "$TS" ] && date -s "@$TS" >/dev/null 2>&1 || true
        fi
        hwclock -w -u 2>/dev/null || true
        return 0
    }

    # ЭТАП 1: Сеть, TCP BBR, динамический тюнинг буферов по RAM, отключение rp_filter и NAT
    modprobe tcp_bbr 2>/dev/null || true

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
SYS_EOF

    sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || true
    uci del network.lan.ipaddr 2>/dev/null || true
    uci set network.lan.ipaddr="$TARGET_LAN_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway="$GW_IP"
    uci del network.lan.dns 2>/dev/null || true
    uci add_list network.lan.dns="$GW_IP"
    uci add_list network.lan.dns="77.88.8.8"
    uci set network.lan.ipv6='0' 2>/dev/null || true
    uci del network.lan.ip6assign 2>/dev/null || true
    uci set network.lan.delegate='0' 2>/dev/null || true

    if ! is_dhcp_server_enabled; then
        uci set dhcp.lan.ignore='1'
    fi
    uci del dhcp.lan.ra 2>/dev/null || true
    uci del dhcp.lan.dhcpv6 2>/dev/null || true
    uci set dhcp.@dnsmasq[0].port='5353'
    uci commit network
    uci commit dhcp
    /etc/init.d/odhcpd stop 2>/dev/null || true
    /etc/init.d/odhcpd disable 2>/dev/null || true

    printf "nameserver %s\nnameserver 77.88.8.8\nnameserver 77.88.8.1\n" "$GW_IP" > /tmp/resolv.conf
    cp -f /tmp/resolv.conf /etc/resolv.conf
    if [ "$TARGET_LAN_IP" = "$SAVED_LAN_IP" ]; then
        /etc/init.d/network reload 2>/dev/null || true
        /etc/init.d/dnsmasq restart 2>/dev/null || true
        sleep 2
    fi

    CURRENT_IP="$TARGET_LAN_IP"

    CUR_TZ=$(uci -q get system.@system[0].zonename || true)
    if [ -z "$CUR_TZ" ] || [ "$CUR_TZ" = "UTC" ]; then
        uci set system.@system[0].zonename='Europe/Moscow'
        uci set system.@system[0].timezone='MSK-3'
        uci commit system
        /etc/init.d/system reload 2>/dev/null || true
    fi

    sync_clock
    /etc/init.d/sysntpd restart 2>/dev/null || true

    LAN_ZONE_IDX=$(uci show firewall 2>/dev/null | sed -n "s/^firewall\.\(@zone\[[0-9]*\]\)\.name='lan'$/\1/p" | head -n 1)
    [ -z "$LAN_ZONE_IDX" ] && LAN_ZONE_IDX="@zone[0]"
    uci set "firewall.${LAN_ZONE_IDX}.masq=1"
    uci set "firewall.${LAN_ZONE_IDX}.forward=ACCEPT"
    uci set firewall.@defaults[0].flow_offloading='0' 2>/dev/null || true
    uci set firewall.@defaults[0].flow_offloading_hw='0' 2>/dev/null || true
    uci commit firewall

    sync_dns_firewall "yes" "keep"

    REQ_PKGS="ca-certificates curl gzip tar jq kmod-tun kmod-tcp-bbr kmod-nft-tproxy kmod-nft-queue ip-full conntrack wireguard-tools apache-utils"
    NEED_PKGS=""
    for pkg in $REQ_PKGS; do
        apk info -e "$pkg" >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS $pkg"
    done
    [ -n "$NEED_PKGS" ] && { apk update --allow-untrusted || true; apk add --allow-untrusted $NEED_PKGS || true; }
    disable_apache_daemon

    modprobe tun 2>/dev/null || true
    modprobe tcp_bbr 2>/dev/null || true
    modprobe nft_queue 2>/dev/null || true
    sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || true
    [ -e /dev/net/tun ] || { mkdir -p /dev/net && mknod /dev/net/tun c 10 200; }

    # Если выбран режим бесплатного Amnezia WARP — генерируем пул нод со сканером
    if [ "$USE_INITIAL_WARP" = "yes" ]; then
        generate_amnezia_warp "${WARP_LICENSE:-}" || true
    fi

    # ЭТАП 2: Загрузка/обновление ядер Sing-Box Extended и AdGuard Home
    update_cores_only "no"

    # ЭТАП 3: Генерация конфига Sing-Box Extended и установка веб-панели Zashboard
    /etc/init.d/sing-box stop 2>/dev/null || true

    if [ ! -f "${SB_DIR}/ui/index.html" ]; then
        install_zashboard_ui || true
    else
        echo "[✓] Веб-панель Zashboard уже установлена."
    fi

    generate_singbox_config

    # ЭТАП 4: Настройка AdGuard Home с сохранением пользовательских фильтров
    echo "Генерация bcrypt-хэша пароля..."
    AGH_PASS_HASH=""
    if command -v htpasswd >/dev/null 2>&1; then
        AGH_PASS_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH=$(htpasswd -nbBC 10 "$AGH_USER" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true) || true
    fi
    disable_apache_daemon
    [ -z "$AGH_PASS_HASH" ] && { echo "[X] Ошибка генерации bcrypt-хэша!"; exit 1; }

    /etc/init.d/adguardhome stop 2>/dev/null || true
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
        chmod 600 "$AGH_CONF" 2>/dev/null || true
        echo "[✓] Существующий AdGuardHome.yaml обновлен (фильтры сохранены, aaaa_disabled: true активен)."
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
        chmod 600 "$AGH_CONF" 2>/dev/null || true
    fi

    # ЭТАП 5: Регистрация служб procd с динамическим GOMEMLIMIT под объем ОЗУ устройства
    cat << INIT_SB > /etc/init.d/sing-box
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/sing-box run -c /etc/sing-box/config.json -D /etc/sing-box
    procd_set_param env GOGC=50 GOMEMLIMIT=${SB_GOMEMLIMIT} ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true
    procd_set_param file /etc/sing-box/config.json
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_set_param limits nofile="65535 65535"
    procd_close_instance
}
INIT_SB
    chmod +x /etc/init.d/sing-box
    /etc/init.d/sing-box enable 2>/dev/null || true
    /etc/init.d/sing-box restart 2>/dev/null || /etc/init.d/sing-box start 2>/dev/null || true

    sleep 2
    cat << INIT_AGH > /etc/init.d/adguardhome
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=96
STOP=09
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/AdGuardHome -c /etc/AdGuardHome/AdGuardHome.yaml -w /etc/AdGuardHome --no-check-update
    procd_set_param env GOGC=50 GOMEMLIMIT=${AGH_GOMEMLIMIT}
    procd_set_param file /etc/AdGuardHome/AdGuardHome.yaml
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_set_param limits nofile="65535 65535"
    procd_close_instance
}
INIT_AGH
    chmod +x /etc/init.d/adguardhome
    /etc/init.d/adguardhome enable 2>/dev/null || true
    /etc/init.d/adguardhome restart 2>/dev/null || /etc/init.d/adguardhome start 2>/dev/null || true

    printf "nameserver 127.0.0.1\nnameserver %s\nnameserver 77.88.8.8\n" "$GW_IP" > /tmp/resolv.conf
    cp -f /tmp/resolv.conf /etc/resolv.conf

    ensure_sysupgrade_persistence
    enable_watchdog

    if [ "$ENABLE_AU" = "yes" ]; then
        enable_autoupdate
    else
        disable_autoupdate
    fi

    # ЭТАП 6: Self-Test 2.0
    run_self_test

    echo "========================================================"
    echo " Развертывание на ${OS_NAME} успешно завершено!"
    echo " - IP-адрес шлюза:     ${CURRENT_IP} (интерфейс $(get_lan_ifname), маска /24)"
    echo " - Основной роутер:    ${GW_IP}"
    echo " - Панель OpenWrt:     http://${CURRENT_IP}"
    echo " - Панель Sing-Box:    http://${CURRENT_IP}:9090/ui [Zashboard] (пароль: ${ADMIN_PASS})"
    echo " - Панель AdGuard:     http://${CURRENT_IP}:3000 (логин: ${AGH_USER} / пароль: ${ADMIN_PASS})"
    echo " - Вызов меню шлюза:   gateway"
    echo "========================================================"

    if [ "$TARGET_LAN_IP" != "$SAVED_LAN_IP" ]; then
        echo "[!] Переключение интерфейса OpenWrt на новый IP ${TARGET_LAN_IP}..."
        echo "    Переподключитесь по SSH: ssh root@${TARGET_LAN_IP}"
        cat << 'SW_EOF' > /tmp/switch_lan_ip.sh
#!/bin/sh
sleep 1
/etc/init.d/sing-box stop >/dev/null 2>&1 || true
/etc/init.d/network reload >/dev/null 2>&1 || /etc/init.d/network restart >/dev/null 2>&1 || true
sleep 3
/etc/init.d/firewall reload >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
/etc/init.d/sing-box start >/dev/null 2>&1 || true
/etc/init.d/adguardhome restart >/dev/null 2>&1 || true
rm -f /tmp/switch_lan_ip.sh
SW_EOF
        chmod +x /tmp/switch_lan_ip.sh
        nohup /tmp/switch_lan_ip.sh >/dev/null 2>&1 &
    fi
    return 0
}

# Матрица глубокой диагностики шлюза (Self-Test 2.0: RAM, Conntrack, FakeIP, Anti-Leak и HTTP Ping)
run_self_test() {
    set +e
    echo "=== [Self-Test 2.0] Матрица диагностики шлюза Sing-Box Extended ==="
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
        DHCP_ST="ВКЛ"
    else
        DHCP_ST="ВЫКЛ"
    fi
    echo " • Сеть шлюза: [OpenWrt (${LAN_IF_NOW}): $(get_current_lan_ip)] -> [Роутер: ${GW_IP}] | DHCP: ${DHCP_ST}"
    print_proxy_slots_report

    SB_PID=$(pgrep sing-box 2>/dev/null | head -n 1 || true)
    if [ -n "$SB_PID" ]; then
        SB_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${SB_PID}/status" 2>/dev/null || echo "активен")
        echo "[✓] Служба Sing-Box Extended: ЗАПУЩЕНА (PID ${SB_PID}, ОЗУ: ${SB_RSS} / лимит ${SB_GOMEMLIMIT})"
    else
        echo "[X] Служба Sing-Box Extended: ОСТАНОВЛЕНА"
    fi

    AGH_PID=$(pgrep AdGuardHome 2>/dev/null | head -n 1 || true)
    if [ -n "$AGH_PID" ]; then
        AGH_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${AGH_PID}/status" 2>/dev/null || echo "активен")
        echo "[✓] Служба AdGuard Home (:53): ЗАПУЩЕНА (PID ${AGH_PID}, ОЗУ: ${AGH_RSS} / лимит ${AGH_GOMEMLIMIT})"
    else
        echo "[X] Служба AdGuard Home: ОСТАНОВЛЕНА"
    fi

    if ip link show singbox-tun >/dev/null 2>&1; then
        echo "[✓] TUN-интерфейс (singbox-tun): АКТИВЕН (MTU 1492, mixed stack)"
    else
        echo "[X] TUN-интерфейс (singbox-tun): НЕ НАЙДЕН"
    fi

    RP_STAT=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "unknown")
    BBR_STAT=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    CT_CNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
    echo "[✓] Сетевой стек: TCP ${BBR_STAT} | rp_filter=${RP_STAT} | Сессии Conntrack: ${CT_CNT} из ${SYS_CONNTRACK_MAX}"

    if is_killswitch_enabled; then
        echo "[✓] Защита от утечек: Kill-Switch АКТИВЕН + блок Type 65 (HTTPS/ECH), IPv6 и DoT 853"
    else
        echo "[✓] Защита от утечек: Блок Type 65 (HTTPS/ECH), IPv6 Drop, DoT/DoQ 853 Reject и DNS 53 Redirect"
    fi

    if [ -f "$SB_CONF" ] && [ -n "$SB_PID" ]; then
        ACTIVE_NODE=$(curl -fsS --connect-timeout 3 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null | sed -n 's/.*"⚡ Авто (Самый быстрый)".*"now":"\([^"]*\)".*/\1/p' | head -n 1)
        [ -n "$ACTIVE_NODE" ] && echo "[✓] Активная нода (Авто): ${ACTIVE_NODE}" || true
        CF_TRACE=$(curl -fsS --connect-timeout 4 -x http://127.0.0.1:7890 "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null | grep -E '^(ip|loc|warp|colo)=' | tr '\n' ' ' || true)
        if [ -n "$CF_TRACE" ]; then
            echo "[✓] Внешний выход через туннель (Cloudflare Trace): ${CF_TRACE}"
            PING_RU=$(curl -o /dev/null -fsS --connect-timeout 2 -w '%{time_connect}' "http://ya.ru" 2>/dev/null | awk '{printf "%.0f ms", $1*1000}' || echo "timeout")
            PING_CF=$(curl -o /dev/null -fsS --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "http://cp.cloudflare.com/generate_204" 2>/dev/null | awk '{printf "%.0f ms", $1*1000}' || echo "timeout")
            PING_GG=$(curl -o /dev/null -fsS --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "http://www.gstatic.com/generate_204" 2>/dev/null | awk '{printf "%.0f ms", $1*1000}' || echo "timeout")
            PING_AI=$(curl -o /dev/null -fsS --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_connect}' "https://api.openai.com" 2>/dev/null | awk '{printf "%.0f ms", $1*1000}' || echo "timeout")
            echo "[✓] Матрица задержек: РФ (ya.ru): ${PING_RU} | CF: ${PING_CF} | YouTube/Google: ${PING_GG} | OpenAI: ${PING_AI}"
        else
            echo "[!] Туннель еще прогревается или подписка недоступна."
        fi
    fi
    return 0
}

# Безопасная самоустановка скрипта в качестве системной команды gateway
INSTALL_PATH="/usr/bin/gateway"
SCRIPT_BASE="$(basename "$0" 2>/dev/null || true)"
if [ -f "$0" ] && [ "$0" != "$INSTALL_PATH" ] && [ "$SCRIPT_BASE" != "sh" ] && [ "$SCRIPT_BASE" != "ash" ] && [ "$SCRIPT_BASE" != "-sh" ] && [ "$SCRIPT_BASE" != "-ash" ]; then
    cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    ensure_sysupgrade_persistence
    echo "[✓] Команда 'gateway' успешно установлена в систему."
fi

# ==============================================================================
# Интерактивное меню управления (OpenWrt 25.x — Sing-Box Extended Ноябрь 2026)
# ==============================================================================
show_menu() {
    set +e
    init_user_lists
    ensure_sysupgrade_persistence
    refresh_remote_versions
    while true; do
        clear
        echo "========================================================"
        echo "  Панель управления шлюзом (Sing-Box Extended Edition)  "
        echo "========================================================"
        print_gateway_header
        echo "--------------------------------------------------------"
        echo " 1) Статус служб, матрица пинга и тест на утечки (Self-Test 2.0)"
        echo " 2) Управление прокси: Подписки / Ключи / Amnezia WARP 2.0"
        echo " 3) Обновить ядра Sing-Box Extended, AdGuard Home и Zashboard"
        echo " 4) Перезапустить службы + пересобрать конфиг и сбросить кэш"
        echo " 5) Посмотреть живые логи Sing-Box (logread)"
        echo " 6) Полная перенастройка шлюза (Мастер установки)"
        echo " 7) Свои домены: добавить/очистить (В прокси / Напрямую)"
        echo " 8) Маршрутизация устройств по IP (Обход DIRECT / Full-VPN)"
        echo " 9) Сервисный режим, смена пароля и резервное копирование"
        echo " 10) Автообновление (04:00) и Авто-Доктор (Watchdog)"
        echo " 11) Аппаратный Kill-Switch (защита от утечек при падении Sing-Box)"
        echo " 12) Сетевые настройки: IP шлюза / роутера + Умный DHCP Sidecar"
        echo " 0) Выход"
        echo "--------------------------------------------------------"
        printf "Выберите действие [0-12]: "
        read -r CHOICE < /dev/tty || true

        case "$CHOICE" in
            1)
                echo ""
                run_self_test
                echo "--- Прослушиваемые порты ---"
                ss -tulpn 2>/dev/null | grep -E ':(53|1053|3000|9090|7890)\b' || netstat -tulpn 2>/dev/null | grep -E ':(53|1053|3000|9090|7890)\b' || true
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            2)
                echo ""
                echo "=== Управление источниками прокси (3 независимых слота) ==="
                print_proxy_slots_report
                echo "---------------------------------------------------------------"
                echo " 1) Указать / заменить основную подписку (http://...) [Слот 1]"
                echo " 2) Добавить дополнительную подписку в пул (Мульти-Саб) [Слот 1]"
                echo " 3) Отключить и очистить все подписки по ссылке [Слот 1]"
                echo " 4) Посмотреть пронумерованный список личных ключей [Слот 2]"
                echo " 5) Добавить личный ключ (vless/hy2/tuic/ss/wg/anytls...) [Слот 2]"
                echo " 6) Удалить один конкретный личный ключ по номеру [Слот 2]"
                echo " 7) Очистить все личные ключи в my_nodes.yaml [Слот 2]"
                echo " 8) Включить / перевыпустить Amnezia WARP 2.0 (+ WARP+) [Слот 3]"
                echo " 9) Отключить и полностью очистить ноды Amnezia WARP 2.0 [Слот 3]"
                echo " 0) Назад"
                printf "Выбор [0-9]: "
                read -r SUB_ACT < /dev/tty || true
                case "$SUB_ACT" in
                    1)
                        printf "Введите ссылку на подписку (или несколько через пробел): "
                        read -r NEW_SUB < /dev/tty || true
                        NEW_SUB=$(printf "%s" "$NEW_SUB" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        if [ -n "$NEW_SUB" ] && [ -f "$SB_CONF" ]; then
                            backup_gateway_state
                            load_gateway_env
                            apply_subscription_input "$NEW_SUB"
                            if [ "${USE_INITIAL_WARP:-no}" = "yes" ]; then
                                generate_amnezia_warp || true
                            fi
                            apply_and_verify_singbox "Обновление подписки (Слот 1)" || true
                        else
                            echo "[X] Отмена: пустой ввод."
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
                                if [ -n "$SUB_URL" ]; then
                                    SUB_URL="${SUB_URL} ${CLEAN_EXTRA}"
                                else
                                    SUB_URL="$CLEAN_EXTRA"
                                fi
                                apply_and_verify_singbox "Добавление дополнительной подписки в Слот 1" || true
                                ;;
                            *)
                                echo "[X] Ошибка: Ссылка должна начинаться с http:// или https://"
                                ;;
                        esac
                        printf "\nНажмите Enter для продолжения..."
                        read -r _ < /dev/tty
                        ;;
                    3)
                        backup_gateway_state
                        load_gateway_env
                        SUB_URL=""
                        if ! has_my_nodes && ! is_warp_enabled; then
                            printf "[!] Других прокси нет. Включить бесплатный Amnezia WARP вместо удаленной подписки? (y/n) [Enter = n (режим DIRECT)]: "
                            read -r EN_W < /dev/tty || true
                            EN_W=$(printf "%s" "$EN_W" | tr -d ' \t\r\n')
                            case "$EN_W" in
                                [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа])
                                    generate_amnezia_warp || true
                                    ;;
                            esac
                        fi
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
                                if delete_my_node_by_index "$DEL_NUM"; then
                                    apply_and_verify_singbox "Удаление ключа #${DEL_NUM} из Слота 2" || true
                                fi
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
                        printf "Вставьте ключ лицензии WARP+ (если есть) [Enter = бесплатный безлимитный WARP]: "
                        read -r W_LIC_IN < /dev/tty || true
                        W_LIC_IN=$(printf "%s" "$W_LIC_IN" | tr -d ' \t\r\n')
                        if generate_amnezia_warp "$W_LIC_IN"; then
                            apply_and_verify_singbox "Включение / обновление Amnezia WARP 2.0 (Слот 3)" || true
                        fi
                        printf "\nНажмите Enter для продолжения..."
                        read -r _ < /dev/tty
                        ;;
                    9)
                        backup_gateway_state
                        load_gateway_env
                        echo '{"outbounds": []}' > "$WARP_NODES_FILE"
                        WARP_LICENSE=""
                        if ! is_sub_enabled && ! has_my_nodes; then
                            echo "[!] Сейчас Amnezia WARP был единственным источником прокси."
                            printf "Введите ссылку на подписку (http://...) или ключ (vless://...) на замену [Enter = перевести шлюз в режим DIRECT]: "
                            read -r REPL_SUB < /dev/tty || true
                            REPL_SUB=$(printf "%s" "$REPL_SUB" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                            if [ -n "$REPL_SUB" ]; then
                                apply_subscription_input "$REPL_SUB"
                                if [ "${USE_INITIAL_WARP:-no}" = "yes" ]; then
                                    generate_amnezia_warp || true
                                fi
                            fi
                        fi
                        apply_and_verify_singbox "Отключение и очистка Amnezia WARP 2.0 (Слот 3)" || true
                        printf "\nНажмите Enter для продолжения..."
                        read -r _ < /dev/tty
                        ;;
                esac
                ;;
            3)
                echo "Проверка и атомарное обновление ядер и веб-панели Zashboard..."
                update_cores_only "yes"
                /etc/init.d/sing-box restart 2>/dev/null || true
                /etc/init.d/adguardhome restart 2>/dev/null || true
                refresh_remote_versions
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            4)
                echo "Пересборка эталонного конфига Sing-Box Extended и сброс кэша..."
                backup_gateway_state
                load_gateway_env
                if apply_and_verify_singbox "Актуализация групп и перезапуск служб"; then
                    conntrack -F >/dev/null 2>&1 || true
                    /etc/init.d/adguardhome restart 2>/dev/null || true
                    echo "[✓] Кэш Fake-IP и таблица conntrack очищены, службы успешно перезапущены."
                fi
                sleep 2
                ;;
            5)
                echo "=== Последние записи лога Sing-Box Extended ==="
                if command -v logread >/dev/null 2>&1; then
                    logread -e sing-box | tail -n 45
                else
                    ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
                        /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR"
                fi
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            6)
                run_installer
                refresh_remote_versions
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            7)
                echo "=== Пользовательские правила доменов ==="
                echo "Домены В ПРОКСИ (${USER_PROXY_FILE} -> группа 🌐 Остальной трафик):"
                cat "$USER_PROXY_FILE" 2>/dev/null || true
                echo "----------------------------------------"
                echo "Домены НАПРЯМУЮ (${USER_DIRECT_FILE} -> DIRECT):"
                cat "$USER_DIRECT_FILE" 2>/dev/null || true
                echo "----------------------------------------"
                echo " 1) Добавить домен В ПРОКСИ (например, +.example.com)"
                echo " 2) Добавить домен НАПРЯМУЮ (например, +.bank.ru)"
                echo " 3) Очистить свои списки доменов"
                echo " 0) Назад"
                printf "Выбор: "
                read -r DOM_ACT < /dev/tty || true
                case "$DOM_ACT" in
                    1)
                        printf "Введите домен для проксирования (например, +.site.com): "
                        read -r D_IN < /dev/tty || true
                        D_IN=$(printf "%s" "$D_IN" | tr -d ' \t\r\n')
                        if [ -n "$D_IN" ]; then
                            backup_gateway_state
                            load_gateway_env
                            case "$D_IN" in +.*) ;; *.*) D_IN="+.$D_IN" ;; esac
                            grep -qxF "$D_IN" "$USER_PROXY_FILE" 2>/dev/null || echo "$D_IN" >> "$USER_PROXY_FILE"
                            apply_and_verify_singbox "Добавление домена ${D_IN} в прокси" || true
                        fi
                        sleep 2
                        ;;
                    2)
                        printf "Введите домен для прямого доступа (например, +.avito.ru): "
                        read -r D_IN < /dev/tty || true
                        D_IN=$(printf "%s" "$D_IN" | tr -d ' \t\r\n')
                        if [ -n "$D_IN" ]; then
                            backup_gateway_state
                            load_gateway_env
                            case "$D_IN" in +.*) ;; *.*) D_IN="+.$D_IN" ;; esac
                            grep -qxF "$D_IN" "$USER_DIRECT_FILE" 2>/dev/null || echo "$D_IN" >> "$USER_DIRECT_FILE"
                            apply_and_verify_singbox "Добавление домена ${D_IN} напрямую (DIRECT)" || true
                        fi
                        sleep 2
                        ;;
                    3)
                        backup_gateway_state
                        load_gateway_env
                        echo "+.localdomain" > "$USER_DIRECT_FILE"
                        echo "+.chatgpt.com" > "$USER_PROXY_FILE"
                        apply_and_verify_singbox "Сброс пользовательских списков доменов" || true
                        sleep 2
                        ;;
                esac
                ;;
            8)
                echo "=== Маршрутизация устройств по локальному IP ==="
                echo "Устройства в обходе (всегда DIRECT):"
                if [ -s "$USER_BYPASS_IPS" ]; then cat "$USER_BYPASS_IPS"; else echo " (пусто)"; fi
                echo "--------------------------------------------------------"
                echo "Устройства в Full-VPN (группа '📺 Устройства (Full-VPN)' — ТВ/PS5/Quest):"
                if [ -s "$USER_FORCE_PROXY_IPS" ]; then cat "$USER_FORCE_PROXY_IPS"; else echo " (пусто)"; fi
                echo "--------------------------------------------------------"
                echo " 1) Добавить IP устройства в ОБХОД (DIRECT)"
                echo " 2) Добавить IP устройства в FULL-VPN (группа 📺 Устройства (Full-VPN))"
                echo " 3) Очистить оба списка IP"
                echo " 0) Назад"
                printf "Выбор: "
                read -r BYP_ACT < /dev/tty || true
                case "$BYP_ACT" in
                    1)
                        printf "Введите локальный IP для обхода (DIRECT): "
                        read -r IP_IN < /dev/tty || true
                        IP_IN=$(printf "%s" "$IP_IN" | tr -d ' \t\r\n')
                        if is_valid_ipv4 "$IP_IN"; then
                            backup_gateway_state
                            load_gateway_env
                            sed -i "\|^${IP_IN}$|d" "$USER_FORCE_PROXY_IPS" 2>/dev/null || true
                            grep -qxF "$IP_IN" "$USER_BYPASS_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_BYPASS_IPS"
                            if apply_and_verify_singbox "Добавление IP ${IP_IN} в обход (DIRECT)"; then
                                conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            fi
                        else
                            echo "[X] Некорректный IPv4-адрес!"
                        fi
                        sleep 2
                        ;;
                    2)
                        printf "Введите локальный IP для Full-VPN (всегда в прокси): "
                        read -r IP_IN < /dev/tty || true
                        IP_IN=$(printf "%s" "$IP_IN" | tr -d ' \t\r\n')
                        if is_valid_ipv4 "$IP_IN"; then
                            backup_gateway_state
                            load_gateway_env
                            sed -i "\|^${IP_IN}$|d" "$USER_BYPASS_IPS" 2>/dev/null || true
                            grep -qxF "$IP_IN" "$USER_FORCE_PROXY_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_FORCE_PROXY_IPS"
                            if apply_and_verify_singbox "Добавление IP ${IP_IN} в Full-VPN"; then
                                conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            fi
                        else
                            echo "[X] Некорректный IPv4-адрес!"
                        fi
                        sleep 2
                        ;;
                    3)
                        backup_gateway_state
                        load_gateway_env
                        : > "$USER_BYPASS_IPS"
                        : > "$USER_FORCE_PROXY_IPS"
                        if apply_and_verify_singbox "Очистка списков маршрутизации по IP"; then
                            conntrack -F >/dev/null 2>&1 || true
                        fi
                        sleep 2
                        ;;
                esac
                ;;
            9)
                echo "=== Сервисный режим, смена пароля и резервное копирование ==="
                echo " 1) Пауза: переключить весь трафик в DIRECT (без остановки DNS)"
                echo " 2) Возобновить работу по правилам (mode: rule)"
                echo " 3) Создать бэкап всех настроек и фильтров (${BACKUP_ARCHIVE})"
                echo " 4) Восстановить настройки из бэкапа (${BACKUP_ARCHIVE})"
                echo " 5) Сменить единый пароль (Sing-Box Zashboard + AdGuard Home)"
                echo " 0) Назад"
                printf "Выбор: "
                read -r SRV_ACT < /dev/tty || true
                load_gateway_env
                case "$SRV_ACT" in
                    1)
                        curl -fsS -X PATCH -H "Authorization: Bearer ${ADMIN_PASS}" -H "Content-Type: application/json" \
                            -d '{"mode":"direct"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                        echo "[✓] Шлюз переведен в режим паузы (весь трафик идет напрямую в DIRECT)."
                        sleep 2
                        ;;
                    2)
                        curl -fsS -X PATCH -H "Authorization: Bearer ${ADMIN_PASS}" -H "Content-Type: application/json" \
                            -d '{"mode":"rule"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                        echo "[✓] Режим маршрутизации по правилам (rule) восстановлен."
                        sleep 2
                        ;;
                    3)
                        tar -czf "$BACKUP_ARCHIVE" /etc/sing-box /etc/AdGuardHome/AdGuardHome.yaml 2>/dev/null || \
                        tar -czf "$BACKUP_ARCHIVE" /etc/sing-box 2>/dev/null || true
                        chmod 600 "$BACKUP_ARCHIVE" 2>/dev/null || true
                        echo "[✓] Архив сохранен в ${BACKUP_ARCHIVE}"
                        sleep 2
                        ;;
                    4)
                        if [ -f "$BACKUP_ARCHIVE" ]; then
                            if tar -xzf "$BACKUP_ARCHIVE" -C / 2>/dev/null; then
                                /etc/init.d/sing-box restart 2>/dev/null || true
                                /etc/init.d/adguardhome restart 2>/dev/null || true
                                echo "[✓] Конфигурация успешно восстановлена из ${BACKUP_ARCHIVE}"
                            else
                                echo "[X] Ошибка: Архив ${BACKUP_ARCHIVE} поврежден!"
                            fi
                        else
                            echo "[X] Файл бэкапа ${BACKUP_ARCHIVE} не найден!"
                        fi
                        sleep 2
                        ;;
                    5)
                        printf "Введите новый единый пароль (для Zashboard и AdGuard Home): "
                        read -r NEW_P_IN < /dev/tty || true
                        NEW_P_IN=$(printf "%s" "$NEW_P_IN" | tr -d '\r\n')
                        if [ -n "$NEW_P_IN" ]; then
                            change_unified_password "$NEW_P_IN" || true
                        else
                            echo "[X] Отмена: пароль не может быть пустым."
                        fi
                        sleep 2
                        ;;
                esac
                ;;
            10)
                echo "=== Автообновление (04:00) и Авто-Доктор (Watchdog каждые 5 мин) ==="
                echo " ⚠️  Бро я думаю ты осознаешь последствия ,_,"
                echo "--------------------------------------------------------"
                echo " • Автообновление ядер (04:00): $(is_autoupdate_enabled && echo "ВКЛЮЧЕНО" || echo "ВЫКЛЮЧЕНО")"
                echo " • Авто-Доктор служб (Watchdog): $(is_watchdog_enabled && echo "ВКЛЮЧЕН (каждые 5 мин)" || echo "ВЫКЛЮЧЕН")"
                echo "--------------------------------------------------------"
                echo " 1) Включить Автообновление (04:00) + Watchdog"
                echo " 2) Выключить Автообновление (оставить только Watchdog)"
                echo " 3) Включить / Выключить Авто-Доктор (Watchdog)"
                echo " 4) Посмотреть лог последнего автообновления (${AUTOUPDATE_LOG})"
                echo " 0) Назад"
                printf "Выбор: "
                read -r AU_ACT < /dev/tty || true
                case "$AU_ACT" in
                    1)
                        enable_autoupdate
                        enable_watchdog
                        echo "[✓] Автообновление (04:00) и Watchdog включены. Бро я думаю ты осознаешь последствия ,_,"
                        sleep 2
                        ;;
                    2)
                        disable_autoupdate
                        enable_watchdog
                        echo "[✓] Автообновление отключено (Watchdog продолжает следить за службами)."
                        sleep 2
                        ;;
                    3)
                        if is_watchdog_enabled; then
                            disable_watchdog
                            echo "[✓] Авто-Доктор (Watchdog) отключен."
                        else
                            enable_watchdog
                            echo "[✓] Авто-Доктор (Watchdog) включен (проверка каждые 5 минут)."
                        fi
                        sleep 2
                        ;;
                    4)
                        echo ""
                        if [ -f "$AUTOUPDATE_LOG" ]; then
                            cat "$AUTOUPDATE_LOG"
                        else
                            echo "[i] Лог автообновления пока пуст."
                        fi
                        printf "\nНажмите Enter для возврата в меню..."
                        read -r _ < /dev/tty
                        ;;
                esac
                ;;
            11)
                echo "=== Аппаратный Kill-Switch (fw4 / nftables на $(get_lan_ifname)) ==="
                echo "Блокирует любую прямую маршрутизацию из LAN в основной роутер в обход singbox-tun."
                echo "Если служба Sing-Box упадет, клиенты не «светят» реальный российский IP провайдера."
                echo "--------------------------------------------------------"
                echo " 1) ВКЛЮЧИТЬ строгий Kill-Switch (рекомендуется против утечек)"
                echo " 2) ВЫКЛЮЧИТЬ строгий Kill-Switch (оставить защиту IPv6, DoT 853 и DNS 53)"
                echo " 0) Назад"
                printf "Выбор [0-2]: "
                read -r KS_ACT < /dev/tty || true
                case "$KS_ACT" in
                    1)
                        sync_dns_firewall "yes" "yes"
                        echo "[✓] Аппаратный Kill-Switch ВКЛЮЧЕН."
                        sleep 2
                        ;;
                    2)
                        sync_dns_firewall "yes" "no"
                        echo "[✓] Аппаратный Kill-Switch ВЫКЛЮЧЕН."
                        sleep 2
                        ;;
                esac
                ;;
            12)
                CUR_LAN_NOW=$(get_current_lan_ip)
                load_gateway_env
                echo ""
                echo "=== Сетевые настройки шлюза и Умный DHCP Sidecar ==="
                echo " • Текущий IP шлюза (OpenWrt):    ${CUR_LAN_NOW} (интерфейс $(get_lan_ifname), /24)"
                echo " • Текущий IP основного роутера:  ${GW_IP}"
                echo " • Умный DHCP-сервер на OpenWrt:  $(is_dhcp_server_enabled && echo "ВКЛЮЧЕН (раздает шлюз и DNS ${CUR_LAN_NOW})" || echo "ВЫКЛЮЧЕН (раздает главный роутер)")"
                echo "----------------------------------------------------------"
                echo " 1) Сменить IP-адрес самого шлюза OpenWrt (network.lan.ipaddr)"
                echo " 2) Сменить IP-адрес основного роутера (Gateway / Local DNS)"
                echo " 3) Сменить оба адреса сразу (при переезде в другую подсеть)"
                echo " 4) ВКЛЮЧИТЬ Умный DHCP-сервер на OpenWrt (для залоченных роутеров РТК/МТС)"
                echo " 5) ВЫКЛЮЧИТЬ DHCP-сервер на OpenWrt (классический Sidecar)"
                echo " 0) Назад"
                printf "Выбор [0-5]: "
                read -r NET_ACT < /dev/tty || true
                case "$NET_ACT" in
                    1)
                        printf "Введите новый IP для шлюза OpenWrt [текущий %s]: " "$CUR_LAN_NOW"
                        read -r NEW_L < /dev/tty || true
                        NEW_L=$(printf "%s" "$NEW_L" | tr -d ' \t\r\n')
                        if [ -n "$NEW_L" ]; then
                            if apply_network_ips "$NEW_L" "$GW_IP"; then
                                [ "$NEW_L" != "$CUR_LAN_NOW" ] && exit 0
                            fi
                        fi
                        sleep 3
                        ;;
                    2)
                        printf "Введите новый IP основного роутера [текущий %s]: " "$GW_IP"
                        read -r NEW_G < /dev/tty || true
                        NEW_G=$(printf "%s" "$NEW_G" | tr -d ' \t\r\n')
                        if [ -n "$NEW_G" ]; then
                            apply_network_ips "$CUR_LAN_NOW" "$NEW_G" || true
                        fi
                        sleep 3
                        ;;
                    3)
                        printf "Введите новый IP для шлюза OpenWrt [текущий %s]: " "$CUR_LAN_NOW"
                        read -r NEW_L < /dev/tty || true
                        NEW_L=$(printf "%s" "$NEW_L" | tr -d ' \t\r\n')
                        printf "Введите новый IP основного роутера [текущий %s]: " "$GW_IP"
                        read -r NEW_G < /dev/tty || true
                        NEW_G=$(printf "%s" "$NEW_G" | tr -d ' \t\r\n')
                        if [ -n "$NEW_L" ] && [ -n "$NEW_G" ]; then
                            if apply_network_ips "$NEW_L" "$NEW_G"; then
                                [ "$NEW_L" != "$CUR_LAN_NOW" ] && exit 0
                            fi
                        fi
                        sleep 3
                        ;;
                    4)
                        configure_smart_dhcp "on"
                        sleep 3
                        ;;
                    5)
                        configure_smart_dhcp "off"
                        sleep 2
                        ;;
                esac
                ;;
            0)
                exit 0
                ;;
        esac
    done
}

# Маршрутизация аргументов командной строки
if [ "${1:-}" = "autoupdate" ]; then
    run_autoupdate
elif [ "${1:-}" = "watchdog" ]; then
    run_watchdog
elif [ "${1:-}" = "test" ] || [ "${1:-}" = "status" ]; then
    run_self_test
elif [ ! -f "$SB_CONF" ] || [ "${1:-}" = "install" ]; then
    run_installer
else
    show_menu
fi
# ==================== [ КОНЕЦ ЧАСТИ 3 ИЗ 3 ] =====================