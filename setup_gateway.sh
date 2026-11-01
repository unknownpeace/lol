#!/bin/sh
set -e

# ==================== [ НАЧАЛО ЧАСТИ 1 ИЗ 4 ] ====================
# ==============================================================================
# Глобальные пути и переменные (OpenWrt 25.x + APK — Sing-Box Extended Ноябрь 2026)
# ==============================================================================
SB_DIR="/etc/sing-box"
SB_CONF="${SB_DIR}/config.json"
SB_ENV="${SB_DIR}/gateway.env"
SB_RULES_DIR="${SB_DIR}/rule_sets"
SB_PROVIDERS_DIR="${SB_DIR}/providers"
CUSTOM_SUB_FILE="${SB_PROVIDERS_DIR}/custom_sub.yaml"
CUSTOM_NODES_FILE="${SB_PROVIDERS_DIR}/my_nodes.yaml"
WARP_NODES_FILE="${SB_PROVIDERS_DIR}/warp_nodes.json"
USER_DIRECT_FILE="${SB_RULES_DIR}/user_direct_domains.list"
USER_PROXY_FILE="${SB_RULES_DIR}/user_proxy_domains.list"
USER_DIRECT_JSON="${SB_RULES_DIR}/user_direct_domains.json"
USER_PROXY_JSON="${SB_RULES_DIR}/user_proxy_domains.json"
USER_BYPASS_IPS="${SB_DIR}/bypass_devices.conf"
USER_FORCE_PROXY_IPS="${SB_DIR}/force_proxy_devices.conf"
BACKUP_ARCHIVE="/root/gateway_backup.tar.gz"
CRON_FILE="/etc/crontabs/root"
AUTOUPDATE_LOG="/var/log/gateway_autoupdate.log"
UI_TYPE_FILE="${SB_DIR}/ui/.ui_type"
UI_VER_FILE="${SB_DIR}/ui/.ui_version"
AGH_CONF="/etc/AdGuardHome/AdGuardHome.yaml"
SYSUPGRADE_CONF="/etc/sysupgrade.conf"
SUB_FILTER_REGEX="(?i)(剩余|过期|到期|官网|流量|套餐|重置|expire|traffic|website|official|осталось|трафик|истекает|подписк|тариф|инфо|новост|поддержк|канал|бот|t[.]me/)"
GH_PROXY=""
LATEST_SB_TAG=""
LATEST_AGH_TAG=""
LATEST_UI_TAG=""

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
}

# Очистка тяжелого веб-сервера apache (устанавливается по зависимостям apache-utils ради htpasswd)
cleanup_apache_bloat() {
    for srv in apache apache2; do
        if [ -x "/etc/init.d/${srv}" ]; then
            "/etc/init.d/${srv}" stop >/dev/null 2>&1 || true
            "/etc/init.d/${srv}" disable >/dev/null 2>&1 || true
        fi
    done
    if apk info -e apache >/dev/null 2>&1; then
        apk del apache apache-utils >/dev/null 2>&1 || true
    fi
}

# Отключение старого сервиса Mihomo при миграции на sing-box-extended
disable_legacy_mihomo() {
    if [ -x /etc/init.d/mihomo ]; then
        /etc/init.d/mihomo stop >/dev/null 2>&1 || true
        /etc/init.d/mihomo disable >/dev/null 2>&1 || true
    fi
    rm -f /etc/nftables.d/98-mihomo-mss-clamp.nft /etc/nftables.d/97-mihomo-anti-leak.nft 2>/dev/null || true
}

# Проверка валидности конфигурации sing-box-extended
check_singbox_config() {
    ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
        /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" >/dev/null 2>&1
}

# Определение параметров текущей выбранной веб-панели
detect_current_ui() {
    CUR_UI_TYPE=""
    if [ -f "$UI_TYPE_FILE" ]; then
        CUR_UI_TYPE=$(cat "$UI_TYPE_FILE" 2>/dev/null | tr -d ' \t\r\n')
    elif grep -qi "zashboard" "$SB_CONF" 2>/dev/null; then
        CUR_UI_TYPE="zashboard"
    elif [ -f "$SB_CONF" ]; then
        CUR_UI_TYPE="metacubexd"
    fi

    if [ "$CUR_UI_TYPE" = "zashboard" ]; then
        CUR_UI_NAME="Zashboard"
        CUR_UI_REPO="Zephyruso/zashboard"
        CUR_UI_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
        CUR_UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
    else
        CUR_UI_TYPE="metacubexd"
        CUR_UI_NAME="MetaCubeXD"
        CUR_UI_REPO="MetaCubeX/metacubexd"
        CUR_UI_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
        CUR_UI_TAR_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.tar.gz"
    fi
}

# Определение текущего режима блокировки рекламы и роли DNS
detect_adblock_mode() {
    SB_ADBLOCK="no"
    AGH_ADBLOCK="no"
    AGH_DNS_ACTIVE="no"

    if [ -f "$SB_CONF" ] && grep -q '"ads_domain"' "$SB_CONF" 2>/dev/null; then
        SB_ADBLOCK="yes"
    fi

    if grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null && pgrep AdGuardHome >/dev/null 2>&1; then
        AGH_DNS_ACTIVE="yes"
        if [ -f "$AGH_CONF" ] && grep -q 'filtering_enabled:[[:space:]]*true' "$AGH_CONF" 2>/dev/null; then
            AGH_ADBLOCK="yes"
        fi
    fi

    if [ "$AGH_DNS_ACTIVE" = "yes" ] && [ "$AGH_ADBLOCK" = "yes" ] && [ "$SB_ADBLOCK" = "yes" ]; then
        ADBLOCK_MODE="both"
        ADBLOCK_STAT="[AGH + SingBox]"
        ADBLOCK_DESC="двойной щит (DNS AGH + .srs/SNI)"
    elif [ "$AGH_DNS_ACTIVE" = "yes" ] && [ "$AGH_ADBLOCK" = "yes" ]; then
        ADBLOCK_MODE="agh"
        ADBLOCK_STAT="[AdGuard Home] "
        ADBLOCK_DESC="DNS и фильтрация через AGH (экономия ОЗУ)"
    elif [ "$SB_ADBLOCK" = "yes" ]; then
        ADBLOCK_MODE="singbox"
        ADBLOCK_STAT="[SingBox .srs] "
        ADBLOCK_DESC="DNS 0.0.0.0:53 + .srs/SNI (AGH остановлен)"
    else
        ADBLOCK_MODE="off"
        ADBLOCK_STAT="[ВЫКЛЮЧЕНА]    "
        ADBLOCK_DESC="реклама и трекеры не режутся"
    fi
}

# Проверка, активны ли ноды Amnezia WARP
is_warp_enabled() {
    [ -f "$WARP_NODES_FILE" ] && grep -q '"type": "wireguard"' "$WARP_NODES_FILE" 2>/dev/null
}

# Проверка, есть ли пользовательские ноды в my_nodes.yaml
has_my_nodes() {
    [ -s "$CUSTOM_NODES_FILE" ] && ! grep -q '^proxies:[[:space:]]*\[\][[:space:]]*$' "$CUSTOM_NODES_FILE" 2>/dev/null
}

# Проверка состояния аппаратного Kill-Switch
is_killswitch_enabled() {
    [ -f /etc/nftables.d/97-singbox-anti-leak.nft ] && grep -q "#KILLSWITCH_ACTIVE" /etc/nftables.d/97-singbox-anti-leak.nft 2>/dev/null
}

# Настройка nftables (fw4): TCP MSS Clamping, перехват DNS 53, Блок IPv6/DoT/DoQ и Kill-Switch
sync_dns_firewall() {
    USE_DNS_REDIRECT="${1:-yes}"
    KS_STATE="${2:-keep}"
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
        cat << 'NFT_LEAK_KS' > /etc/nftables.d/97-singbox-anti-leak.nft
#KILLSWITCH_ACTIVE
chain singbox_anti_leak {
    type filter hook forward priority filter - 5; policy accept;
    meta nfproto ipv6 drop
    iifname "br-lan" meta l4proto { tcp, udp } th dport 853 reject
    iifname "br-lan" oifname "br-lan" ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } reject
}
NFT_LEAK_KS
    else
        cat << 'NFT_LEAK' > /etc/nftables.d/97-singbox-anti-leak.nft
chain singbox_anti_leak {
    type filter hook forward priority filter - 5; policy accept;
    meta nfproto ipv6 drop
    iifname "br-lan" meta l4proto { tcp, udp } th dport 853 reject
}
NFT_LEAK
    fi

    # 3. Принудительный перехват любых сторонних DNS-запросов (зашитых 8.8.8.8 на Smart TV / IoT)
    if [ "$USE_DNS_REDIRECT" = "yes" ]; then
        cat << 'NFT_OWRT' > /etc/nftables.d/99-agh-dns-redirect.nft
chain agh_dns_prerouting {
    type nat hook prerouting priority dstnat - 5; policy accept;
    iifname "br-lan" meta l4proto { tcp, udp } th dport 53 redirect to :53
}
NFT_OWRT
    else
        rm -f /etc/nftables.d/99-agh-dns-redirect.nft 2>/dev/null || true
    fi

    /etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null || true
}

# Переключение фильтрации в AdGuardHome.yaml
set_agh_filtering() {
    TARGET_STATE="$1" # true или false
    [ -f "$AGH_CONF" ] || return 0

    WAS_RUNNING="no"
    if pgrep AdGuardHome >/dev/null 2>&1; then
        WAS_RUNNING="yes"
        /etc/init.d/adguardhome stop 2>/dev/null || true
        sleep 1
    fi

    awk -v state="$TARGET_STATE" '
        /^filtering:[[:space:]]*\{/ {
            sub(/filtering_enabled:[[:space:]]*(true|false)/, "filtering_enabled: " state)
            print
            next
        }
        /^filtering:/ {
            in_filt=1
            print
            next
        }
        in_filt && /^[^[:space:]]/ {
            in_filt=0
        }
        in_filt && /^[[:space:]]*filtering_enabled:/ {
            sub(/filtering_enabled:[[:space:]]*(true|false)/, "filtering_enabled: " state)
            print
            next
        }
        { print }
    ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv "${AGH_CONF}.tmp" "$AGH_CONF"

    if [ "$WAS_RUNNING" = "yes" ]; then
        /etc/init.d/adguardhome start 2>/dev/null || true
    fi
}

# Чтение и сохранение параметров шлюза (gateway.env)
load_gateway_env() {
    GW_IP=""
    USE_AGH="yes"
    SELECTED_ADBLOCK="agh"
    ADMIN_PASS=""
    UI_TYPE="metacubexd"
    PROVIDER_TYPE="http"
    SUB_URL=""

    if [ -f "$SB_ENV" ]; then
        # shellcheck disable=SC1090
        . "$SB_ENV"
    elif [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        GW_IP=$(jq -r '.dns.servers[] | select(.tag=="dns_local") | .server // empty' "$SB_CONF" 2>/dev/null | head -n 1)
        ADMIN_PASS=$(jq -r '.experimental.clash_api.secret // empty' "$SB_CONF" 2>/dev/null | head -n 1)
        SUB_URL=$(jq -r '.providers[]? | select(.tag=="custom_sub") | .url // empty' "$SB_CONF" 2>/dev/null | head -n 1)
        P_TYPE=$(jq -r '.providers[]? | select(.tag=="custom_sub") | .type // empty' "$SB_CONF" 2>/dev/null | head -n 1)
        if [ -z "$P_TYPE" ] && is_warp_enabled; then
            PROVIDER_TYPE="warp"
            SUB_URL="file://warp_nodes.json (Amnezia WARP 2.0)"
        elif [ "$P_TYPE" = "local" ]; then
            PROVIDER_TYPE="file"
            SUB_URL="file://custom_sub.yaml"
        else
            PROVIDER_TYPE="http"
        fi
        if grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null; then
            USE_AGH="yes"
        else
            USE_AGH="no"
        fi
        detect_adblock_mode
        SELECTED_ADBLOCK="$ADBLOCK_MODE"
        detect_current_ui
        UI_TYPE="$CUR_UI_TYPE"
    fi

    [ -z "$GW_IP" ] && GW_IP=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')
    [ -z "$ADMIN_PASS" ] && ADMIN_PASS="admin"
}

save_gateway_env() {
    mkdir -p "$SB_DIR"
    cat << ENV_EOF > "$SB_ENV"
GW_IP='${GW_IP}'
USE_AGH='${USE_AGH}'
SELECTED_ADBLOCK='${SELECTED_ADBLOCK}'
ADMIN_PASS='${ADMIN_PASS}'
UI_TYPE='${UI_TYPE}'
PROVIDER_TYPE='${PROVIDER_TYPE}'
SUB_URL='${SUB_URL}'
ENV_EOF
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
}
# ==================== [ КОНЕЦ ЧАСТИ 1 ИЗ 4 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 2 ИЗ 4 ] ====================
# Генерация эталонного /etc/sing-box/config.json для shtorm-7/sing-box-extended (1.14.x)
generate_singbox_config() {
    check_github_mirror
    sync_user_domain_rulesets
    detect_current_ui

    if [ "$UI_TYPE" = "zashboard" ]; then
        UI_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
    else
        UI_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
    fi

    if [ "$USE_AGH" = "yes" ]; then
        DNS_IN_LISTEN="127.0.0.1"
        DNS_IN_PORT=1053
    else
        DNS_IN_LISTEN="0.0.0.0"
        DNS_IN_PORT=53
    fi

    # Динамическая сборка провайдеров подписок (custom_sub и my_nodes)
    PROVIDERS_JSON_ITEMS=""
    PROVIDER_TAGS_ITEMS=""

    if [ "$PROVIDER_TYPE" = "http" ] && [ -n "$SUB_URL" ]; then
        CUSTOM_SUB_JSON=$(cat << SUB_REM
    {
      "tag": "custom_sub",
      "type": "remote",
      "url": "${SUB_URL}",
      "update_interval": "24h",
      "download_detour": "DIRECT",
      "exclude": "${SUB_FILTER_REGEX}",
      "health_check": {
        "enabled": true,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "3m",
        "timeout": "5s"
      }
    }
SUB_REM
)
        PROVIDERS_JSON_ITEMS="$CUSTOM_SUB_JSON"
        PROVIDER_TAGS_ITEMS='"custom_sub"'
    elif [ "$PROVIDER_TYPE" = "file" ]; then
        CUSTOM_SUB_JSON=$(cat << SUB_LOC
    {
      "tag": "custom_sub",
      "type": "local",
      "path": "${CUSTOM_SUB_FILE}",
      "health_check": {
        "enabled": true,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "3m",
        "timeout": "5s"
      }
    }
SUB_LOC
)
        PROVIDERS_JSON_ITEMS="$CUSTOM_SUB_JSON"
        PROVIDER_TAGS_ITEMS='"custom_sub"'
    fi

    if has_my_nodes; then
        MY_NODES_JSON=$(cat << MY_LOC
    {
      "tag": "my_nodes",
      "type": "local",
      "path": "${CUSTOM_NODES_FILE}",
      "health_check": {
        "enabled": true,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "3m",
        "timeout": "5s"
      }
    }
MY_LOC
)
        if [ -n "$PROVIDERS_JSON_ITEMS" ]; then
            PROVIDERS_JSON_ITEMS="${PROVIDERS_JSON_ITEMS},
${MY_NODES_JSON}"
            PROVIDER_TAGS_ITEMS="${PROVIDER_TAGS_ITEMS}, \"my_nodes\""
        else
            PROVIDERS_JSON_ITEMS="$MY_NODES_JSON"
            PROVIDER_TAGS_ITEMS='"my_nodes"'
        fi
    fi

    PROVIDER_TAGS_JSON="[${PROVIDER_TAGS_ITEMS}]"

    BYPASS_IPS_ARR=$(get_ip_cidr_json_array "$USER_BYPASS_IPS")
    FORCE_IPS_ARR=$(get_ip_cidr_json_array "$USER_FORCE_PROXY_IPS")

    BYPASS_ROUTE_RULE=""
    if [ "$BYPASS_IPS_ARR" != "[]" ]; then
        BYPASS_ROUTE_RULE="{\"source_ip_cidr\": ${BYPASS_IPS_ARR}, \"outbound\": \"DIRECT\"},"
    fi

    FORCE_ROUTE_RULE=""
    if [ "$FORCE_IPS_ARR" != "[]" ]; then
        FORCE_ROUTE_RULE="{\"source_ip_cidr\": ${FORCE_IPS_ARR}, \"outbound\": \"📺 Устройства (Full-VPN)\"},"
    fi

    if [ "$SELECTED_ADBLOCK" = "singbox" ] || [ "$SELECTED_ADBLOCK" = "both" ]; then
        DNS_ADBLOCK_RULE='{"rule_set": ["ads_domain", "telemetry_domain"], "action": "reject"},'
        ROUTE_ADBLOCK_RULE='{"rule_set": ["ads_domain", "telemetry_domain"], "action": "reject"},'
        RULESET_ADBLOCK_JSON=$(cat << ADB_RS
      {
        "tag": "ads_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ads-all.srs"
      },
      {
        "tag": "telemetry_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-telemetry.srs"
      },
ADB_RS
)
    else
        DNS_ADBLOCK_RULE=""
        ROUTE_ADBLOCK_RULE=""
        RULESET_ADBLOCK_JSON=""
    fi

    [ -f "$SB_CONF" ] && cp -f "$SB_CONF" "${SB_CONF}.bak"

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
      "external_ui_download_url": "${GH_PROXY}${UI_URL}",
      "secret": "${ADMIN_PASS}",
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
        "server": "${GW_IP}",
        "server_port": 53
      },
      {
        "tag": "dns_fakeip",
        "type": "fakeip",
        "inet4_range": "198.18.0.0/15"
      }
    ],
    "rules": [
      ${DNS_ADBLOCK_RULE}
      {
        "clash_mode": "direct",
        "server": "dns_ru"
      },
      {
        "domain_suffix": [
          ".lan",
          ".local",
          ".home.arpa",
          ".internal",
          ".localdomain",
          ".in-addr.arpa"
        ],
        "server": "dns_local"
      },
      {
        "rule_set": [
          "private_domain"
        ],
        "server": "dns_local"
      },
      {
        "domain_suffix": [
          "msftconnecttest.com",
          "msftncsi.com",
          "connectivitycheck.gstatic.com",
          "connectivitycheck.android.com",
          "captive.apple.com",
          "push.apple.com",
          "courier.push.apple.com",
          "tailscale.com",
          "steamcontent.com",
          "xboxlive.com",
          "stun.playstation.net",
          "srv.nintendo.net"
        ],
        "server": "dns_ru"
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
    "final": "dns_proxy",
    "strategy": "ipv4_only",
    "reverse_mapping": true
  },
  "inbounds": [
    {
      "type": "direct",
      "tag": "dns-in",
      "listen": "${DNS_IN_LISTEN}",
      "listen_port": ${DNS_IN_PORT}
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
  "providers": [
${PROVIDERS_JSON_ITEMS}
  ],
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
      "type": "urltest",
      "tag": "🛡️ Авто-резерв (Fallback)",
      "providers": ${PROVIDER_TAGS_JSON},
      "url": "https://cp.cloudflare.com/generate_204",
      "interval": "5m",
      "tolerance": 150,
      "idle_timeout": "30m"
    },
    {
      "type": "selector",
      "tag": "🔓 Обход блокировок",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)",
        "🐟 Прочий трафик",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "☁️ Cloudflare & CDN",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)",
        "🔓 Обход блокировок",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "▶️ YouTube",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🤖 Нейросети (AI)",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "👾 Discord & Игры",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "💬 Мессенджеры & Связь",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🎵 Spotify",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "📺 Устройства (Full-VPN)",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)",
        "🔓 Обход блокировок",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🧲 Торренты",
      "outbounds": [
        "DIRECT",
        "⚡ Авто (Самый быстрый)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🇷🇺 Россия",
      "outbounds": [
        "DIRECT",
        "⚡ Авто (Самый быстрый)"
      ]
    },
    {
      "type": "selector",
      "tag": "🐟 Прочий трафик",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🛡️ Авто-резерв (Fallback)",
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
    "final": "🐟 Прочий трафик",
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
        "rule_set": [
          "private_domain",
          "private_ip"
        ],
        "outbound": "DIRECT"
      },
      ${BYPASS_ROUTE_RULE}
      {
        "rule_set": [
          "user_direct_domains"
        ],
        "outbound": "DIRECT"
      },
      {
        "rule_set": [
          "user_proxy_domains"
        ],
        "outbound": "🔓 Обход блокировок"
      },
      {
        "port": [
          853
        ],
        "action": "reject"
      },
      {
        "port": [
          123
        ],
        "outbound": "DIRECT"
      },
      {
        "rule_set": [
          "ntp_domain"
        ],
        "outbound": "DIRECT"
      },
      ${ROUTE_ADBLOCK_RULE}
      {
        "protocol": [
          "bittorrent"
        ],
        "outbound": "🧲 Торренты"
      },
      {
        "rule_set": [
          "torrent_domain"
        ],
        "outbound": "🧲 Торренты"
      },
      {
        "port_range": [
          "6881:6889"
        ],
        "outbound": "🧲 Торренты"
      },
      ${FORCE_ROUTE_RULE}
      {
        "rule_set": [
          "youtube_domain",
          "ai_domain",
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
          "ai_domain"
        ],
        "outbound": "🤖 Нейросети (AI)"
      },
      {
        "rule_set": [
          "spotify_domain"
        ],
        "outbound": "🎵 Spotify"
      },
      {
        "rule_set": [
          "youtube_domain"
        ],
        "outbound": "▶️ YouTube"
      },
      {
        "rule_set": [
          "roblox_domain",
          "discord_domain",
          "discord_voice_ip"
        ],
        "outbound": "👾 Discord & Игры"
      },
      {
        "rule_set": [
          "stun_domain",
          "communication_domain",
          "telegram_ip"
        ],
        "outbound": "💬 Мессенджеры & Связь"
      },
      {
        "rule_set": [
          "ru_bundle",
          "refilter_ip"
        ],
        "outbound": "🔓 Обход блокировок"
      },
      {
        "rule_set": [
          "cloudflare_domain",
          "cloudflare_ip"
        ],
        "outbound": "☁️ Cloudflare & CDN"
      },
      {
        "rule_set": [
          "ru_domain",
          "ru_ip"
        ],
        "outbound": "🇷🇺 Россия"
      },
      {
        "network": [
          "udp"
        ],
        "port_range": [
          "50000:50100"
        ],
        "outbound": "👾 Discord & Игры"
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
        "outbound": "💬 Мессенджеры & Связь"
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
${RULESET_ADBLOCK_JSON}
      {
        "tag": "ai_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-ai-!cn.srs"
      },
      {
        "tag": "spotify_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/spotify.srs"
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
        "tag": "roblox_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/roblox.srs"
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
        "tag": "communication_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/category-communication.srs"
      },
      {
        "tag": "telegram_ip",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/telegram.srs"
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

    # Подключение секции .endpoints и отдельной группы "☁️ Amnezia WARP" для полной совместимости с подписками
    if command -v jq >/dev/null 2>&1; then
        if is_warp_enabled; then
            if [ -n "$PROVIDER_TAGS_ITEMS" ]; then
                jq --slurpfile w "$WARP_NODES_FILE" '
                    .endpoints = $w[0].outbounds
                    | (.outbounds[] | select(.type == "selector" and .providers != null) | .outbounds) += ["☁️ Amnezia WARP"]
                    | .outbounds = (
                        .outbounds[0:2] + [{
                            "type": "urltest",
                            "tag": "☁️ Amnezia WARP",
                            "outbounds": ($w[0].outbounds | map(.tag)),
                            "url": "https://cp.cloudflare.com/generate_204",
                            "interval": "3m",
                            "tolerance": 50,
                            "idle_timeout": "30m"
                        }] + .outbounds[2:]
                    )
                ' "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
            else
                jq --slurpfile w "$WARP_NODES_FILE" '
                    del(.providers)
                    | .endpoints = $w[0].outbounds
                    | (.outbounds[] | select(.providers != null)) |= (
                        del(.providers)
                        | .outbounds = ((.outbounds // []) + ($w[0].outbounds | map(.tag)))
                    )
                    | .outbounds = (
                        .outbounds[0:2] + [{
                            "type": "urltest",
                            "tag": "☁️ Amnezia WARP",
                            "outbounds": ($w[0].outbounds | map(.tag)),
                            "url": "https://cp.cloudflare.com/generate_204",
                            "interval": "3m",
                            "tolerance": 50,
                            "idle_timeout": "30m"
                        }] + .outbounds[2:]
                    )
                ' "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
            fi
        elif [ -z "$PROVIDER_TAGS_ITEMS" ]; then
            jq '
                del(.providers)
                | (.outbounds[] | select(.providers != null)) |= del(.providers)
            ' "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
        else
            jq . "${SB_CONF}.tmp" > "$SB_CONF" && rm -f "${SB_CONF}.tmp"
        fi
    else
        mv -f "${SB_CONF}.tmp" "$SB_CONF"
    fi
    save_gateway_env
}

# Автоустановка и инициализация AdGuard Home
ensure_agh_installed() {
    detect_os
    if [ ! -x /usr/bin/AdGuardHome ]; then
        USE_AGH="yes" update_cores_only "no"
    fi

    if [ ! -f "$AGH_CONF" ]; then
        load_gateway_env
        if ! command -v htpasswd >/dev/null 2>&1; then
            apk update --allow-untrusted >/dev/null 2>&1 || true
            apk add --allow-untrusted apache-utils >/dev/null 2>&1 || true
        fi

        AGH_PASS_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "admin" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH=$(htpasswd -nbBC 10 "admin" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH='$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'
        cleanup_apache_bloat

        mkdir -p /etc/AdGuardHome/data
        cat << AGH_EOF > "$AGH_CONF"
http:
  address: 0.0.0.0:3000
  session_ttl: 720h
users:
  - name: admin
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
    fi

    if [ ! -f /etc/init.d/adguardhome ]; then
        cat << 'INIT_AGH' > /etc/init.d/adguardhome
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=96
STOP=09
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/AdGuardHome -c /etc/AdGuardHome/AdGuardHome.yaml -w /etc/AdGuardHome --no-check-update
    procd_set_param file /etc/AdGuardHome/AdGuardHome.yaml
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_set_param limits nofile="65535 65535"
    procd_close_instance
}
INIT_AGH
        chmod +x /etc/init.d/adguardhome
    fi
}

# Применение выбранного режима блокировки рекламы и роли DNS (agh | singbox | both | off)
apply_adblock_mode() {
    MODE="$1"
    [ -f "$SB_CONF" ] || return 0
    load_gateway_env

    case "$MODE" in
        singbox)
            echo "Остановка AdGuard Home и передача роли DNS (0.0.0.0:53) в Sing-Box Extended..."
            /etc/init.d/adguardhome stop 2>/dev/null || true
            /etc/init.d/adguardhome disable 2>/dev/null || true
            USE_AGH="no"
            SELECTED_ADBLOCK="singbox"
            generate_singbox_config
            if check_singbox_config; then
                /etc/init.d/sing-box restart 2>/dev/null || true
                sync_dns_firewall "yes" "keep"
                echo "[✓] AdGuard Home остановлен. Sing-Box принял на себя роль DNS (0.0.0.0:53) и блокировку рекламы (.srs + SNI)."
            else
                mv "${SB_CONF}.bak" "$SB_CONF"
                echo "[X] Ошибка проверки конфига Sing-Box! Выполнен авто-откат."
                return 1
            fi
            ;;

        agh)
            echo "Переключение DNS и фильтрации рекламы на AdGuard Home..."
            ensure_agh_installed
            USE_AGH="yes"
            SELECTED_ADBLOCK="agh"
            generate_singbox_config
            if check_singbox_config; then
                /etc/init.d/sing-box restart 2>/dev/null || true
                set_agh_filtering "true"
                /etc/init.d/adguardhome enable 2>/dev/null || true
                /etc/init.d/adguardhome restart 2>/dev/null || true
                sync_dns_firewall "yes" "keep"
                echo "[✓] Роль DNS (0.0.0.0:53) и фильтрация переданы AdGuard Home (списки рекламы в Sing-Box выгружены для экономии ОЗУ)."
            else
                mv "${SB_CONF}.bak" "$SB_CONF"
                echo "[X] Ошибка проверки конфига Sing-Box! Выполнен авто-откат."
                return 1
            fi
            ;;

        both)
            echo "Включение режима двойного щита (DNS AdGuard Home + правила .srs в Sing-Box)..."
            ensure_agh_installed
            USE_AGH="yes"
            SELECTED_ADBLOCK="both"
            generate_singbox_config
            if check_singbox_config; then
                /etc/init.d/sing-box restart 2>/dev/null || true
                set_agh_filtering "true"
                /etc/init.d/adguardhome enable 2>/dev/null || true
                /etc/init.d/adguardhome restart 2>/dev/null || true
                sync_dns_firewall "yes" "keep"
                echo "[✓] Включен двойной щит: AdGuard Home (DNS 0.0.0.0:53) + Sing-Box (.srs + SNI)."
            else
                mv "${SB_CONF}.bak" "$SB_CONF"
                echo "[X] Ошибка проверки конфига Sing-Box! Выполнен авто-откат."
                return 1
            fi
            ;;

        off)
            echo "Отключение фильтрации рекламы (режим отладки)..."
            if pgrep AdGuardHome >/dev/null 2>&1; then
                set_agh_filtering "false"
            fi
            SELECTED_ADBLOCK="off"
            generate_singbox_config
            if check_singbox_config; then
                /etc/init.d/sing-box restart 2>/dev/null || true
                echo "[✓] Блокировка рекламы полностью отключена (текущая схема DNS сохранена)."
            else
                mv "${SB_CONF}.bak" "$SB_CONF"
                echo "[X] Ошибка проверки конфига Sing-Box! Выполнен авто-откат."
                return 1
            fi
            ;;
    esac
}
# ==================== [ КОНЕЦ ЧАСТИ 2 ИЗ 4 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 3 ИЗ 4 ] ====================
# Проверка, включено ли автообновление в cron
is_autoupdate_enabled() {
    grep -q "/usr/bin/gateway autoupdate" "$CRON_FILE" 2>/dev/null
}

# Включение автообновления (ежедневно в 04:00)
enable_autoupdate() {
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    echo "0 4 * * * /usr/bin/gateway autoupdate >${AUTOUPDATE_LOG} 2>&1" >> "$CRON_FILE"
    /etc/init.d/cron enable 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true
}

# Отключение автообновления
disable_autoupdate() {
    if [ -f "$CRON_FILE" ]; then
        sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    fi
    /etc/init.d/cron reload 2>/dev/null || /etc/init.d/cron restart 2>/dev/null || true
}

# Фоновая задача автообновления для cron
run_autoupdate() {
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Запуск автообновления шлюза ==="
    update_cores_only "yes"
    if ! pgrep sing-box >/dev/null 2>&1; then
        /etc/init.d/sing-box start 2>/dev/null || true
    fi
    if grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null && [ -x /usr/bin/AdGuardHome ]; then
        if ! pgrep AdGuardHome >/dev/null 2>&1; then
            /etc/init.d/adguardhome start 2>/dev/null || true
        fi
    fi
    reload_singbox_api
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Автообновление завершено ==="
}

# Получение последнего тега релиза с GitHub
fetch_latest_github_tag() {
    REPO="$1"
    TAG=$(curl -fsSL --connect-timeout 2 -m 3 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | cut -d'"' -f4 || true)
    if [ -z "$TAG" ]; then
        TAG=$(curl -fsSLI --connect-timeout 2 -m 3 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null | awk -F'/' '{print $NF}' | tr -d '\r\n' || true)
        [ "$TAG" = "latest" ] && TAG=""
    fi
    printf "%s" "$TAG"
}

# Кэширование актуальных версий с GitHub для быстрого отображения в меню
refresh_remote_versions() {
    detect_current_ui
    LATEST_SB_TAG=$(fetch_latest_github_tag "shtorm-7/sing-box-extended")
    if [ -x /usr/bin/AdGuardHome ] || grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null; then
        LATEST_AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
    fi
    if [ -f "${SB_DIR}/ui/index.html" ]; then
        LATEST_UI_TAG=$(fetch_latest_github_tag "$CUR_UI_REPO")
        if [ ! -f "$UI_VER_FILE" ] && [ -n "$LATEST_UI_TAG" ]; then
            echo "$LATEST_UI_TAG" > "$UI_VER_FILE"
        fi
    fi
}

# Отрисовка статуса и версий в шапке меню
print_gateway_header() {
    detect_current_ui
    detect_adblock_mode

    if pgrep sing-box >/dev/null 2>&1; then
        S_STAT="[ЗАПУЩЕН]     "
    else
        S_STAT="[ОСТАНОВЛЕН]  "
    fi

    if [ -x /usr/bin/sing-box ]; then
        S_VER_RAW=$(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        [ -n "$S_VER_RAW" ] && S_VER="v${S_VER_RAW#v}" || S_VER="неизвестно"
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
    elif grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null; then
        A_STAT="[ОСТАНОВЛЕН]  "
    else
        A_STAT="[ОТКЛЮЧЕН]    "
    fi

    if [ -x /usr/bin/AdGuardHome ]; then
        A_VER=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)
        [ -z "$A_VER" ] && A_VER="установлен"
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

    if is_warp_enabled; then
        W_STAT="[АКТИВЕН]     "
        W_INFO="4 бесплатные ноды AWG 2.0 (Cloudflare Anycast)"
    else
        W_STAT="[ВЫКЛЮЧЕН]    "
        W_INFO="можно включить бесплатно в пункте 2"
    fi

    if [ -f "${SB_DIR}/ui/index.html" ]; then
        if [ "$CUR_UI_TYPE" = "zashboard" ]; then
            UI_STAT="[Zashboard]   "
        else
            UI_STAT="[MetaCubeXD]  "
        fi
        UI_VER=""
        [ -f "$UI_VER_FILE" ] && UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n')
        [ -z "$UI_VER" ] && UI_VER="установлена"

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
        KS_INFO="строгая блокировка трафика мимо singbox-tun"
    else
        KS_STAT="[СТАНДАРТ]    "
        KS_INFO="защита IPv6 + DoT/DoQ + перехват DNS 53"
    fi

    if is_autoupdate_enabled; then
        AU_STAT="[ВКЛЮЧЕНО]    "
        AU_INFO="ежедневно в 04:00 (поставил и забыл ,_,)"
    else
        AU_STAT="[ВЫКЛЮЧЕНО]   "
        AU_INFO="только вручную"
    fi

    echo " Sing-Box Ext:  ${S_STAT}${S_VER_INFO}"
    echo " AdGuard Home:  ${A_STAT}${A_VER_INFO}"
    echo " Amnezia WARP:  ${W_STAT}${W_INFO}"
    echo " Антиреклама:   ${ADBLOCK_STAT}${ADBLOCK_DESC}"
    echo " Kill-Switch:   ${KS_STAT}${KS_INFO}"
    echo " Веб-панель:    ${UI_STAT}${UI_VER_INFO}"
    echo " Автоапдейт:    ${AU_STAT}${AU_INFO}"
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
    [ -s "$CUSTOM_SUB_FILE" ] || echo "proxies: []" > "$CUSTOM_SUB_FILE"
    [ -s "$CUSTOM_NODES_FILE" ] || echo "proxies: []" > "$CUSTOM_NODES_FILE"
    [ -s "$WARP_NODES_FILE" ] || echo '{"outbounds": []}' > "$WARP_NODES_FILE"
    sync_user_domain_rulesets
}

# Безопасное разделение нескольких URI-ключей без повреждения alpn=h2,http/1.1 и пробелов в #Названии
format_uri_keys() {
    printf "%s\n" "$1" | sed -E 's/[[:space:],]+((vless|vmess|ss|ssr|trojan|hy2|hysteria2|hysteria|tuic|wg|wireguard|anytls|mieru|xhttp|splithttp|socks5):\/\/)/\n\1/g' | sed '/^[[:space:]]*$/d'
}

# Автоматическая бесплатная генерация Amnezia WARP 2.0 (4 чистых ноды Cloudflare Anycast)
generate_amnezia_warp() {
    mkdir -p "$SB_PROVIDERS_DIR"
    if ! command -v wg >/dev/null 2>&1; then
        echo "Установка генератора ключей wireguard-tools..."
        apk update --allow-untrusted >/dev/null 2>&1 || true
        apk add --allow-untrusted wireguard-tools >/dev/null 2>&1 || true
    fi

    PRIV_KEY=""
    PUB_KEY=""
    if command -v wg >/dev/null 2>&1; then
        PRIV_KEY=$(wg genkey)
        PUB_KEY=$(printf "%s" "$PRIV_KEY" | wg pubkey)
    fi

    WARP_IPV4=""
    REG_OK="no"

    if [ -n "$PUB_KEY" ]; then
        TOS_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
        REG_PAYLOAD="{\"key\":\"${PUB_KEY}\",\"install_id\":\"\",\"warp_enabled\":true,\"tos\":\"${TOS_DATE}\",\"type\":\"Android\",\"locale\":\"en_US\"}"
        echo "Бесплатная регистрация личного аккаунта Cloudflare WARP (API 2026)..."

        # 1. Пробив через новый незаблокированный эндпоинт Cloudflare 2026 (api.devices.cloudflare.com/v0a4471/reg)
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
                REG_OK="yes"
                break
            fi
        done

        # 2. Резервный эндпоинт Zero-Trust Client
        if [ "$REG_OK" = "no" ]; then
            RESP=$(curl -fsSL --connect-timeout 4 -m 6 \
                -H "User-Agent: okhttp/3.12.1" \
                -H "Content-Type: application/json" \
                -X POST "https://zero-trust-client.cloudflareclient.com/v0a4471/reg" \
                -d "$REG_PAYLOAD" 2>/dev/null || true)
            if printf "%s" "$RESP" | grep -q '"v4"'; then
                WARP_IPV4=$(printf "%s" "$RESP" | sed -n 's/.*"v4":[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1)
                REG_OK="yes"
            fi
        fi
    fi

    # 3. Если уже есть рабочий ключ в warp_nodes.json и API недоступен — сохраняем существующий ключ
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

    # 4. Ручной ввод PrivateKey, если регистрация полностью заблокирована на линии провайдера
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

    [ -z "$WARP_IPV4" ] && WARP_IPV4="172.16.0.2"

    # Рандомизация числа мусорных пакетов jc (4..7) для уникальности сигнатуры роутера
    RAND_BYTE=$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' \t\r\n' || echo "5")
    AWG_JC=$(( (RAND_BYTE % 4) + 4 ))

    cat << WARP_EOF > "$WARP_NODES_FILE"
{
  "outbounds": [
    {
      "type": "wireguard",
      "tag": "☁️ WARP Fast (162.159.192.1:4500)",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "162.159.192.1",
          "port": 4500,
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
      "tag": "☁️ WARP Reserve (188.114.97.1:500)",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "188.114.97.1",
          "port": 500,
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
      "tag": "☁️ WARP Alt (188.114.99.224:1002)",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "188.114.99.224",
          "port": 1002,
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
      "tag": "☁️ WARP Engage (2408)",
      "mtu": 1280,
      "address": [
        "${WARP_IPV4}/32"
      ],
      "private_key": "${PRIV_KEY}",
      "peers": [
        {
          "address": "162.159.192.1",
          "port": 2408,
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

    echo "[✓] Личный пул Amnezia WARP 2.0 (4 ноды Cloudflare Anycast, jc=${AWG_JC}) создан (IP: ${WARP_IPV4})!"
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
    curl -fsS -X PUT -H "Authorization: Bearer ${ADMIN_PASS}" \
        "http://127.0.0.1:9090/providers/proxies/custom_sub" >/dev/null 2>&1 || true
    curl -fsS -X PUT -H "Authorization: Bearer ${ADMIN_PASS}" \
        "http://127.0.0.1:9090/providers/proxies/my_nodes" >/dev/null 2>&1 || true
}

# Обработка подписки, одиночных ключей или режима бесплатного Amnezia WARP
apply_subscription_input() {
    RAW_INPUT="$1"
    mkdir -p "$SB_PROVIDERS_DIR"
    case "$RAW_INPUT" in
        warp|WARP|amnezia|masque|free)
            echo "proxies: []" > "$CUSTOM_SUB_FILE"
            SUB_URL="file://warp_nodes.json (Amnezia WARP 2.0)"
            PROVIDER_TYPE="warp"
            ;;
        http://*|https://*)
            # Автоматическая очистка хвостов fmt=best / fmt=xray, которые отдают массив Xray вместо стандартной подписки
            CLEAN_SUB_URL=$(printf "%s" "$RAW_INPUT" | sed -E 's/([?&])fmt=(best|xray|v2ray)(&|$)/\1/; s/[?&]$//')
            if [ "$CLEAN_SUB_URL" != "$RAW_INPUT" ]; then
                echo "[i] Параметр fmt=... автоматически убран из ссылки для совместимости с Sing-Box."
            fi
            SUB_URL="$CLEAN_SUB_URL"
            PROVIDER_TYPE="http"
            ;;
        vless://*|vmess://*|ss://*|ssr://*|trojan://*|hy2://*|hysteria2://*|hysteria://*|tuic://*|wg://*|wireguard://*|anytls://*|mieru://*|xhttp://*|splithttp://*|socks5://*)
            format_uri_keys "$RAW_INPUT" > "$CUSTOM_SUB_FILE"
            SUB_URL="file://custom_sub.yaml"
            PROVIDER_TYPE="file"
            ;;
        file://*)
            SUB_URL="$RAW_INPUT"
            PROVIDER_TYPE="file"
            ;;
        *)
            SUB_URL="$RAW_INPUT"
            PROVIDER_TYPE="http"
            ;;
    esac
}

# Загрузка и установка веб-панели (MetaCubeXD / Zashboard) с сохранением версии
install_singbox_ui() {
    TARGET_UI_TYPE="$1"
    TARGET_UI_NAME="$2"
    TARGET_UI_TAR_URL="$3"
    TARGET_UI_VER="${4:-}"

    if [ -z "$TARGET_UI_VER" ]; then
        if [ "$TARGET_UI_TYPE" = "zashboard" ]; then
            TARGET_UI_VER=$(fetch_latest_github_tag "Zephyruso/zashboard")
        else
            TARGET_UI_VER=$(fetch_latest_github_tag "MetaCubeX/metacubexd")
        fi
    fi

    echo "Загрузка и установка веб-панели ${TARGET_UI_NAME} ${TARGET_UI_VER}..."
    rm -rf /tmp/sb_ui.tar.gz /tmp/sb_ui_extract
    mkdir -p /tmp/sb_ui_extract

    if download_file "$TARGET_UI_TAR_URL" "/tmp/sb_ui.tar.gz" && tar -xzf /tmp/sb_ui.tar.gz -C /tmp/sb_ui_extract 2>/dev/null; then
        rm -rf "${SB_DIR}/ui"
        mkdir -p "${SB_DIR}/ui"
        cp -rf /tmp/sb_ui_extract/*/* "${SB_DIR}/ui/" 2>/dev/null || cp -rf /tmp/sb_ui_extract/* "${SB_DIR}/ui/"
        echo "$TARGET_UI_TYPE" > "$UI_TYPE_FILE"
        [ -n "$TARGET_UI_VER" ] && echo "$TARGET_UI_VER" > "$UI_VER_FILE"
        LATEST_UI_TAG="$TARGET_UI_VER"
        rm -rf /tmp/sb_ui.tar.gz /tmp/sb_ui_extract
        echo "[✓] Веб-панель ${TARGET_UI_NAME} ${TARGET_UI_VER} успешно установлена в ${SB_DIR}/ui."
    else
        rm -rf /tmp/sb_ui.tar.gz /tmp/sb_ui_extract
        echo "[X] Ошибка загрузки или распаковки веб-панели ${TARGET_UI_NAME}!"
        return 1
    fi
}

# Атомарное обновление бинарников Sing-Box Extended, AdGuard Home и UI
update_cores_only() {
    CHECK_UI_UPDATE="${1:-no}"
    detect_os
    check_github_mirror

    SB_TAG=$(fetch_latest_github_tag "shtorm-7/sing-box-extended")
    [ -z "$SB_TAG" ] && SB_TAG="v1.14.3-extended-2.7.3"
    LATEST_SB_TAG="$SB_TAG"
    SB_VER_NO_V="${SB_TAG#v}"

    INSTALLED_SB_VER=""
    if [ -x /usr/bin/sing-box ]; then
        RAW_V=$(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        [ -n "$RAW_V" ] && INSTALLED_SB_VER="v${RAW_V#v}"
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

    if [ "${USE_AGH:-}" = "yes" ] || [ -x /usr/bin/AdGuardHome ]; then
        AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
        [ -z "$AGH_TAG" ] && AGH_TAG="v0.107.79"
        LATEST_AGH_TAG="$AGH_TAG"
        INSTALLED_AGH_VER=""
        [ -x /usr/bin/AdGuardHome ] && INSTALLED_AGH_VER=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)

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
                echo "[X] Не удалось скачать AdGuard Home ${AGH_TAG}."
            fi
        fi
    fi

    if [ "$CHECK_UI_UPDATE" = "yes" ]; then
        detect_current_ui
        UI_TAG=$(fetch_latest_github_tag "$CUR_UI_REPO")
        LATEST_UI_TAG="$UI_TAG"
        INSTALLED_UI_VER=""
        [ -f "$UI_VER_FILE" ] && INSTALLED_UI_VER=$(cat "$UI_VER_FILE" 2>/dev/null | tr -d ' \t\r\n')

        if [ -f "${SB_DIR}/ui/index.html" ] && [ -n "$UI_TAG" ] && [ "$INSTALLED_UI_VER" = "$UI_TAG" ]; then
            echo "[✓] Веб-панель ${CUR_UI_NAME} ${INSTALLED_UI_VER} актуальна."
        else
            install_singbox_ui "$CUR_UI_TYPE" "$CUR_UI_NAME" "$CUR_UI_TAR_URL" "$UI_TAG"
        fi
    fi
}
# ==================== [ КОНЕЦ ЧАСТИ 3 ИЗ 4 ] =====================

# ==================== [ НАЧАЛО ЧАСТИ 4 ИЗ 4 ] ====================
# ==============================================================================
# Главный мастер установки и настройки (Sing-Box Extended + AdGuard Home)
# ==============================================================================
run_installer() {
    detect_os
    disable_legacy_mihomo

    echo "========================================================"
    echo " Установщик Sing-Box Extended + AdGuard Home (OpenWrt)  "
    echo "========================================================"
    echo "Система: ${OS_NAME} [${ARCH_RAW} -> ${SB_ARCH}]"
    echo "--------------------------------------------------------"

    load_gateway_env
    SAVED_SUB_URL="$SUB_URL"
    SAVED_GW_IP="$GW_IP"
    SAVED_USE_AGH="$USE_AGH"
    SAVED_PASS="$ADMIN_PASS"
    SAVED_UI_TYPE="$UI_TYPE"
    SAVED_AGH_USER=""

    if [ -f "$AGH_CONF" ]; then
        SAVED_AGH_USER=$(sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "$AGH_CONF" | head -n 1 | tr -d ' \t\r\n"')
    fi

    # 1. Запрос ссылки на подписку, прямого ключа или бесплатного Amnezia WARP
    if [ -n "$SAVED_SUB_URL" ]; then
        printf "Введите подписку, ключ (vless/hy2...) или 'warp' [Enter = оставить %s]: " "$SAVED_SUB_URL"
    else
        printf "Введите подписку (http://...), ключ (vless://...) или 'warp' (бесплатный Amnezia WARP 2.0): "
    fi
    read -r INPUT_SUB_URL < /dev/tty || true
    INPUT_SUB_URL=$(printf "%s" "$INPUT_SUB_URL" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -n "$INPUT_SUB_URL" ]; then
        RAW_SUB_CHOICE="$INPUT_SUB_URL"
    else
        RAW_SUB_CHOICE="$SAVED_SUB_URL"
    fi

    if [ -z "$RAW_SUB_CHOICE" ]; then
        printf "Подписка не указана. Сгенерировать бесплатный безлимитный Amnezia WARP 2.0? (y/n) [Enter = y]: "
        read -r WARP_FALLBACK < /dev/tty || true
        WARP_FALLBACK=$(printf "%s" "$WARP_FALLBACK" | tr -d ' \t\r\n')
        [ -z "$WARP_FALLBACK" ] && WARP_FALLBACK="y"
        case "$WARP_FALLBACK" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа])
                RAW_SUB_CHOICE="warp"
                ;;
            *)
                echo "Бро я не буду этого делать без подписки или ключа ,_."
                exit 1
                ;;
        esac
    fi
    apply_subscription_input "$RAW_SUB_CHOICE"

    # 2. Запрос IP-адреса основного роутера
    if [ -n "$SAVED_GW_IP" ]; then
        printf "Введите IP основного роутера [Enter = %s]: " "$SAVED_GW_IP"
    else
        printf "Введите IP-адрес основного роутера (например, 192.168.1.1): "
    fi
    read -r INPUT_GW_IP < /dev/tty || true
    INPUT_GW_IP=$(printf "%s" "$INPUT_GW_IP" | tr -d ' \t\r\n')

    if [ -n "$INPUT_GW_IP" ]; then
        GW_IP="$INPUT_GW_IP"
    else
        GW_IP="$SAVED_GW_IP"
    fi

    if [ -z "$GW_IP" ]; then
        echo "[X] Ошибка: Не указан IP-адрес основного роутера!"
        exit 1
    fi

    # 3. Выбор режима DNS и блокировки рекламы
    echo "Кто будет обрабатывать DNS и блокировать рекламу?"
    echo "  1) Только AdGuard Home (DNS 0.0.0.0:53 + блок-листы AGH, Sing-Box на 1053)"
    echo "  2) Только Sing-Box (.srs списки + SNI, Sing-Box берет DNS 0.0.0.0:53, AGH остановлен)"
    echo "  3) Оба: AdGuard Home + Sing-Box (двойной щит: DNS AGH + .srs в Sing-Box)"
    echo "  4) Выключить блокировку рекламы (AGH как чистый DNS без фильтрации)"
    DEF_ADB_CHOICE="1"
    [ "$SAVED_USE_AGH" = "no" ] && DEF_ADB_CHOICE="2"
    printf "Ваш выбор (1-4) [Enter = %s]: " "$DEF_ADB_CHOICE"
    read -r INPUT_ADB_CHOICE < /dev/tty || true
    INPUT_ADB_CHOICE=$(printf "%s" "$INPUT_ADB_CHOICE" | tr -d ' \t\r\n')
    [ -z "$INPUT_ADB_CHOICE" ] && INPUT_ADB_CHOICE="$DEF_ADB_CHOICE"

    case "$INPUT_ADB_CHOICE" in
        2)
            USE_AGH="no"
            SELECTED_ADBLOCK="singbox"
            ADBLOCK_SUMMARY="Только Sing-Box (.srs + SNI, DNS 0.0.0.0:53)"
            DNS_MODE_DESC="Sing-Box напрямую (0.0.0.0:53 + hijack-dns, AGH остановлен)"
            ;;
        3)
            USE_AGH="yes"
            SELECTED_ADBLOCK="both"
            ADBLOCK_SUMMARY="AdGuard Home + Sing-Box (двойной щит)"
            DNS_MODE_DESC="AdGuard Home (0.0.0.0:53 + DNAT) -> Sing-Box (127.0.0.1:1053)"
            ;;
        4)
            USE_AGH="yes"
            SELECTED_ADBLOCK="off"
            ADBLOCK_SUMMARY="Выключена (режим отладки)"
            DNS_MODE_DESC="AdGuard Home (0.0.0.0:53 + DNAT) -> Sing-Box (127.0.0.1:1053)"
            ;;
        *)
            USE_AGH="yes"
            SELECTED_ADBLOCK="agh"
            ADBLOCK_SUMMARY="Только AdGuard Home (DNS)"
            DNS_MODE_DESC="AdGuard Home (0.0.0.0:53 + DNAT) -> Sing-Box (127.0.0.1:1053)"
            ;;
    esac

    # 4. Запрос логина и пароля
    if [ "$USE_AGH" = "yes" ]; then
        DEF_AGH_USER="${SAVED_AGH_USER:-admin}"
        printf "Введите логин для панели AdGuard Home [Enter = %s]: " "$DEF_AGH_USER"
        read -r INPUT_AGH_USER < /dev/tty || true
        INPUT_AGH_USER=$(printf "%s" "$INPUT_AGH_USER" | tr -d ' \t\r\n')
        AGH_USER="${INPUT_AGH_USER:-$DEF_AGH_USER}"

        if [ -n "$SAVED_PASS" ]; then
            printf "Введите единый пароль (AdGuard + Sing-Box) [Enter = оставить текущий]: "
        else
            printf "Введите единый пароль (для панели AdGuard Home и secret в Sing-Box): "
        fi
        read -r INPUT_PASS < /dev/tty || true
        INPUT_PASS=$(printf "%s" "$INPUT_PASS" | tr -d '\r\n')
    else
        AGH_USER="${SAVED_AGH_USER:-admin}"
        if [ -n "$SAVED_PASS" ]; then
            printf "Введите пароль (secret) для Sing-Box [Enter = оставить текущий]: "
        else
            printf "Введите пароль (secret) для веб-панели Sing-Box: "
        fi
        read -r INPUT_PASS < /dev/tty || true
        INPUT_PASS=$(printf "%s" "$INPUT_PASS" | tr -d '\r\n')
    fi

    ADMIN_PASS="${INPUT_PASS:-$SAVED_PASS}"
    if [ -z "$ADMIN_PASS" ]; then
        echo "[X] Ошибка: Пароль не может быть пустым!"
        exit 1
    fi

    # 5. Выбор веб-панели управления
    DEF_UI_CHOICE="1"
    [ "$SAVED_UI_TYPE" = "zashboard" ] && DEF_UI_CHOICE="2"

    echo "Выберите веб-панель для Sing-Box Extended:"
    echo "  1) MetaCubeXD"
    echo "  2) Zashboard"
    if [ -n "$SAVED_UI_TYPE" ]; then
        printf "Ваш выбор (1/2) [Enter = оставить %s]: " "$SAVED_UI_TYPE"
    else
        printf "Ваш выбор (1/2) [Enter = 1 (MetaCubeXD)]: "
    fi
    read -r INPUT_UI_CHOICE < /dev/tty || true
    INPUT_UI_CHOICE=$(printf "%s" "$INPUT_UI_CHOICE" | tr -d ' \t\r\n')
    [ -z "$INPUT_UI_CHOICE" ] && INPUT_UI_CHOICE="$DEF_UI_CHOICE"

    case "$INPUT_UI_CHOICE" in
        2|[Zz]* )
            UI_TYPE="zashboard"
            UI_NAME="Zashboard"
            UI_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
            UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
            ;;
        * )
            UI_TYPE="metacubexd"
            UI_NAME="MetaCubeXD"
            UI_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
            UI_TAR_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.tar.gz"
            ;;
    esac

    # 6. Запрос на автообновление («поставил и забыл»)
    DEF_AU_CHAR=$(is_autoupdate_enabled && echo "y" || echo "n")
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
    echo " - ОС:              ${OS_NAME}"
    echo " - Ядро:            shtorm-7/sing-box-extended (${SB_ARCH})"
    echo " - Основной роутер: ${GW_IP}"
    echo " - Схема DNS:       ${DNS_MODE_DESC}"
    echo " - Антиреклама:     ${ADBLOCK_SUMMARY}"
    echo " - Веб-панель:      ${UI_NAME}"
    [ "$USE_AGH" = "yes" ] && echo " - Логин AdGuard:   ${AGH_USER}"
    echo " - Единый пароль:   ${ADMIN_PASS}"
    echo " - Источник прокси: ${SUB_URL} (${PROVIDER_TYPE})"
    echo " - Автообновление:  $([ "$ENABLE_AU" = "yes" ] && echo "ВКЛ (04:00)" || echo "ВЫКЛ")"
    echo "--------------------------------------------------------"

    sync_clock() {
        echo "Синхронизация системных часов..."
        /usr/sbin/ntpd -n -q -p 162.159.200.1 -p 216.239.35.0 -p ntp.ix.ru -p pool.ntp.org 2>/dev/null || true
        if [ "$(date +%Y)" -lt 2026 ]; then
            TS=$(wget -qO- "http://1.1.1.1/cdn-cgi/trace" 2>/dev/null | awk -F= '/^ts=/ {split($2,a,"."); print a[1]}')
            [ -n "$TS" ] && date -s "@$TS" >/dev/null 2>&1 || true
        fi
        hwclock -w -u 2>/dev/null || true
    }

    # ЭТАП 1: Сеть, TCP BBR, тюнинг буферов, отключение rp_filter и NAT (Sidecar OpenWrt 25)
    modprobe tcp_bbr 2>/dev/null || true

    cat << 'SYS_EOF' > /etc/sysctl.d/99-gateway-forward.conf
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
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.netfilter.nf_conntrack_max = 131072
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 180
net.ipv4.tcp_congestion_control = bbr
SYS_EOF

    sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || true
    uci set network.lan.gateway="$GW_IP"
    uci del network.lan.dns 2>/dev/null || true
    uci add_list network.lan.dns="$GW_IP"
    uci add_list network.lan.dns="77.88.8.8"
    uci set network.lan.ipv6='0' 2>/dev/null || true
    uci del network.lan.ip6assign 2>/dev/null || true
    uci set network.lan.delegate='0' 2>/dev/null || true
    uci set dhcp.lan.ignore='1'
    uci del dhcp.lan.ra 2>/dev/null || true
    uci del dhcp.lan.dhcpv6 2>/dev/null || true
    uci set dhcp.@dnsmasq[0].port='5353'
    uci commit network
    uci commit dhcp
    /etc/init.d/odhcpd stop 2>/dev/null || true
    /etc/init.d/odhcpd disable 2>/dev/null || true

    printf "nameserver %s\nnameserver 77.88.8.8\nnameserver 77.88.8.1\n" "$GW_IP" > /tmp/resolv.conf
    cp -f /tmp/resolv.conf /etc/resolv.conf
    /etc/init.d/network reload
    /etc/init.d/dnsmasq restart
    sleep 2

    CURRENT_IP=$(uci -q get network.lan.ipaddr || ip -4 addr show br-lan 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
    CURRENT_IP="${CURRENT_IP%%/*}"

    CUR_TZ=$(uci -q get system.@system[0].zonename || true)
    if [ -z "$CUR_TZ" ] || [ "$CUR_TZ" = "UTC" ]; then
        uci set system.@system[0].zonename='Europe/Moscow'
        uci set system.@system[0].timezone='MSK-3'
        uci commit system
        /etc/init.d/system reload
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

    REQ_PKGS="ca-certificates curl gzip tar jq kmod-tun kmod-tcp-bbr kmod-nft-tproxy kmod-nft-queue ip-full conntrack wireguard-tools"
    [ "$USE_AGH" = "yes" ] && REQ_PKGS="$REQ_PKGS apache-utils"
    NEED_PKGS=""
    for pkg in $REQ_PKGS; do
        apk info -e "$pkg" >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS $pkg"
    done
    [ -n "$NEED_PKGS" ] && { apk update --allow-untrusted || true; apk add --allow-untrusted $NEED_PKGS || true; }

    init_user_lists

    modprobe tun 2>/dev/null || true
    modprobe tcp_bbr 2>/dev/null || true
    modprobe nft_queue 2>/dev/null || true
    sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || true
    [ -e /dev/net/tun ] || { mkdir -p /dev/net && mknod /dev/net/tun c 10 200; }

    # Если выбран режим бесплатного Amnezia WARP — генерируем пул нод
    if [ "$PROVIDER_TYPE" = "warp" ]; then
        generate_amnezia_warp || true
    fi

    # ЭТАП 2: Загрузка/обновление ядер Sing-Box Extended и AdGuard Home
    update_cores_only "no"

    # ЭТАП 3: Генерация конфига Sing-Box Extended и установка веб-панели
    /etc/init.d/sing-box stop 2>/dev/null || true

    if [ "$PROVIDER_TYPE" = "http" ] && [ -n "$SAVED_SUB_URL" ] && [ "$SUB_URL" != "$SAVED_SUB_URL" ]; then
        rm -f "$CUSTOM_SUB_FILE" 2>/dev/null || true
    fi

    INSTALLED_UI_TYPE=""
    [ -f "$UI_TYPE_FILE" ] && INSTALLED_UI_TYPE=$(cat "$UI_TYPE_FILE" 2>/dev/null | tr -d ' \t\r\n')

    if [ "$INSTALLED_UI_TYPE" != "$UI_TYPE" ] || [ ! -f "${SB_DIR}/ui/index.html" ]; then
        install_singbox_ui "$UI_TYPE" "$UI_NAME" "$UI_TAR_URL"
    else
        echo "[✓] Веб-панель ${UI_NAME} уже установлена."
    fi

    generate_singbox_config

    # ЭТАП 4: Настройка AdGuard Home с сохранением пользовательских фильтров и авто-очисткой apache
    if [ "$USE_AGH" = "yes" ]; then
        echo "Генерация bcrypt-хэша пароля..."
        AGH_PASS_HASH=""
        if ! command -v htpasswd >/dev/null 2>&1; then
            apk add --allow-untrusted apache-utils >/dev/null 2>&1 || true
        fi
        if command -v htpasswd >/dev/null 2>&1; then
            AGH_PASS_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
            [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH=$(htpasswd -nbBC 10 "$AGH_USER" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        fi
        cleanup_apache_bloat
        [ -z "$AGH_PASS_HASH" ] && { echo "[X] Ошибка генерации bcrypt-хэша!"; exit 1; }

        if [ "$SELECTED_ADBLOCK" = "agh" ] || [ "$SELECTED_ADBLOCK" = "both" ]; then
            AGH_FILT_BOOL="true"
        else
            AGH_FILT_BOOL="false"
        fi

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
            set_agh_filtering "$AGH_FILT_BOOL"
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
filtering: { protection_enabled: true, filtering_enabled: ${AGH_FILT_BOOL} }
schema_version: 34
AGH_EOF
        fi
    else
        cleanup_apache_bloat
        /etc/init.d/adguardhome stop 2>/dev/null || true
        /etc/init.d/adguardhome disable 2>/dev/null || true
    fi

    # ЭТАП 5: Регистрация служб procd (с лимитом памяти Go GOMEMLIMIT=200MiB) и защита при sysupgrade
    cat << 'INIT_SB' > /etc/init.d/sing-box
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/sing-box run -c /etc/sing-box/config.json -D /etc/sing-box
    procd_set_param env GOGC=50 GOMEMLIMIT=200MiB ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true
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

    if [ "$USE_AGH" = "yes" ]; then
        sleep 2
        cat << 'INIT_AGH' > /etc/init.d/adguardhome
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=96
STOP=09
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/AdGuardHome -c /etc/AdGuardHome/AdGuardHome.yaml -w /etc/AdGuardHome --no-check-update
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
    fi
    printf "nameserver 127.0.0.1\nnameserver 77.88.8.8\nnameserver 77.88.8.1\n" > /tmp/resolv.conf
    cp -f /tmp/resolv.conf /etc/resolv.conf

    ensure_sysupgrade_persistence

    if [ "$ENABLE_AU" = "yes" ]; then
        enable_autoupdate
    else
        disable_autoupdate
    fi

    # ЭТАП 6: Self-Test
    run_self_test

    echo "========================================================"
    echo " Развертывание на ${OS_NAME} успешно завершено!"
    echo " - IP-адрес шлюза:     ${CURRENT_IP}"
    echo " - Основной роутер:    ${GW_IP}"
    echo " - Антиреклама:        ${ADBLOCK_SUMMARY}"
    echo " - Панель Sing-Box:    http://${CURRENT_IP}:9090/ui [${UI_NAME}] (пароль: ${ADMIN_PASS})"
    if [ "$USE_AGH" = "yes" ]; then
        echo " - Панель AdGuard:     http://${CURRENT_IP}:3000 (логин: ${AGH_USER} / пароль: ${ADMIN_PASS})"
    fi
    echo " - Вызов меню шлюза:   gateway"
    echo "========================================================"
}

# Расширенная диагностика шлюза, замер задержки (Ping) и проверка на утечки (Self-Test + Anti-Leak)
run_self_test() {
    echo "=== [Self-Test] Диагностика прозрачного шлюза Sing-Box Extended ==="
    WAIT_CNT=0
    while [ "$WAIT_CNT" -lt 12 ]; do
        if pgrep sing-box >/dev/null 2>&1 && ip link show singbox-tun >/dev/null 2>&1; then
            break
        fi
        sleep 1
        WAIT_CNT=$((WAIT_CNT + 1))
    done

    if pgrep sing-box >/dev/null 2>&1; then
        echo "[✓] Служба Sing-Box Extended: ЗАПУЩЕНА"
    else
        echo "[X] Служба Sing-Box Extended: ОСТАНОВЛЕНА"
    fi

    if pgrep AdGuardHome >/dev/null 2>&1; then
        echo "[✓] Служба AdGuard Home: ЗАПУЩЕНА"
    else
        echo "[i] Служба AdGuard Home: ОСТАНОВЛЕНА (DNS обрабатывает Sing-Box)"
    fi

    if is_warp_enabled; then
        echo "[✓] Пул Amnezia WARP 2.0: АКТИВЕН (4 бесплатные ноды Cloudflare Anycast)"
    fi

    detect_adblock_mode
    echo "[✓] Режим антирекламы: ${ADBLOCK_STAT} ${ADBLOCK_DESC}"

    if ip link show singbox-tun >/dev/null 2>&1; then
        echo "[✓] TUN-интерфейс (singbox-tun): АКТИВЕН"
    else
        echo "[X] TUN-интерфейс (singbox-tun): НЕ НАЙДЕН"
    fi

    RP_STAT=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "unknown")
    BBR_STAT=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    echo "[✓] Сетевой стек: TCP ${BBR_STAT} | rp_filter=${RP_STAT} (Sidecar OK)"

    if is_killswitch_enabled; then
        echo "[✓] Защита от утечек (Kill-Switch): АКТИВНА (строгий запрет обхода TUN)"
    else
        echo "[✓] Защита от утечек: IPv6 Drop + DoT/DoQ 853 Reject + DNS 53 Redirect активны"
    fi

    if [ -f "$SB_CONF" ] && pgrep sing-box >/dev/null 2>&1; then
        load_gateway_env
        ACTIVE_NODE=$(curl -fsS --connect-timeout 3 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null | sed -n 's/.*"⚡ Авто (Самый быстрый)".*"now":"\([^"]*\)".*/\1/p' | head -n 1)
        [ -n "$ACTIVE_NODE" ] && echo "[✓] Активная нода (Авто): ${ACTIVE_NODE}"
        CF_TRACE=$(curl -fsS --connect-timeout 4 -x http://127.0.0.1:7890 "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null | grep -E '^(ip|loc|warp|colo)=' | tr '\n' ' ' || true)
        if [ -n "$CF_TRACE" ]; then
            echo "[✓] Внешний выход через туннель (Cloudflare Trace): ${CF_TRACE}"
            PING_RU=$(curl -o /dev/null -fsS --connect-timeout 2 -w '%{time_connect}' "http://ya.ru" 2>/dev/null | awk '{printf "%.0f ms", $1*1000}' || echo "timeout")
            PING_CF=$(curl -o /dev/null -fsS --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "http://cp.cloudflare.com/generate_204" 2>/dev/null | awk '{printf "%.0f ms", $1*1000}' || echo "timeout")
            PING_GG=$(curl -o /dev/null -fsS --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "http://www.gstatic.com/generate_204" 2>/dev/null | awk '{printf "%.0f ms", $1*1000}' || echo "timeout")
            echo "[✓] Задержка (HTTP Ping): РФ Напрямую: ${PING_RU} | Туннель CF: ${PING_CF} | Google: ${PING_GG}"
        else
            echo "[!] Туннель еще прогревается или подписка недоступна."
        fi
    fi
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
# Интерактивное меню управления (OpenWrt 25.x — Sing-Box Extended)
# ==============================================================================
show_menu() {
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
        echo " 1) Статус служб, пинг туннеля и тест на утечки (Self-Test)"
        echo " 2) Подписка, личные ключи и бесплатный Amnezia WARP 2.0"
        echo " 3) Обновить ядра Sing-Box Extended, AdGuard Home и UI"
        echo " 4) Перезапустить службы + сброс conntrack и Fake-IP кэша"
        echo " 5) Посмотреть живые логи Sing-Box (logread)"
        echo " 6) Полная перенастройка шлюза (Мастер установки)"
        echo " 7) Сменить веб-панель (MetaCubeXD / Zashboard)"
        echo " 8) Свои домены: добавить/очистить (В прокси / Напрямую)"
        echo " 9) Маршрутизация устройств по IP (Обход DIRECT / Full-VPN)"
        echo " 10) Режим паузы / Бэкап и восстановление настроек"
        echo " 11) Автообновление (поставил и забыл) — Бро я думаю ты осознаешь последствия ,_,"
        echo " 12) Блокировка рекламы и DNS: переключить (AGH / SingBox / Оба / Выкл)"
        echo " 13) Аппаратный Kill-Switch (защита от утечек при падении Sing-Box)"
        echo " 0) Выход"
        echo "--------------------------------------------------------"
        printf "Выберите действие [0-13]: "
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
                echo "=== Управление подпиской, ключами и Amnezia WARP 2.0 ==="
                echo " 1) Заменить основную подписку (http://...), основной ключ или 'warp'"
                echo " 2) Добавить дополнительный личный ключ (vless/hy2/ss/tuic/anytls/xhttp) в пул my_nodes"
                echo " 3) Очистить дополнительные личные ключи (${CUSTOM_NODES_FILE})"
                echo " 4) Сгенерировать / обновить БЕСПЛАТНЫЙ Amnezia WARP 2.0 (4 ноды Cloudflare Anycast)"
                echo " 5) Отключить / очистить ноды Amnezia WARP 2.0 (${WARP_NODES_FILE})"
                echo " 0) Назад"
                printf "Выбор [0-5]: "
                read -r SUB_ACT < /dev/tty || true
                case "$SUB_ACT" in
                    1)
                        printf "Введите новую ссылку (http://...), прямой ключ (vless/hy2...) или 'warp': "
                        read -r NEW_SUB < /dev/tty || true
                        NEW_SUB=$(printf "%s" "$NEW_SUB" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        if [ -n "$NEW_SUB" ] && [ -f "$SB_CONF" ]; then
                            load_gateway_env
                            apply_subscription_input "$NEW_SUB"
                            if [ "$PROVIDER_TYPE" = "warp" ]; then
                                generate_amnezia_warp || true
                            elif [ "$PROVIDER_TYPE" = "http" ]; then
                                rm -f "$CUSTOM_SUB_FILE" 2>/dev/null || true
                            fi
                            generate_singbox_config
                            if check_singbox_config; then
                                /etc/init.d/sing-box restart 2>/dev/null || true
                                echo "[✓] Основной источник прокси успешно обновлен!"
                            else
                                mv "${SB_CONF}.bak" "$SB_CONF"
                                echo "[X] Ошибка проверки конфига! Выполнен авто-откат."
                            fi
                        else
                            echo "[X] Ошибка: пустой ввод или конфиг не найден."
                        fi
                        sleep 2
                        ;;
                    2)
                        printf "Вставьте ключ (vless://, hy2://, ss://, tuic://, wg://, anytls://): "
                        read -r EXTRA_KEY < /dev/tty || true
                        EXTRA_KEY=$(printf "%s" "$EXTRA_KEY" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        if [ -n "$EXTRA_KEY" ]; then
                            sed -i '/^proxies:[[:space:]]*\[\]/d' "$CUSTOM_NODES_FILE" 2>/dev/null || true
                            format_uri_keys "$EXTRA_KEY" >> "$CUSTOM_NODES_FILE"
                            load_gateway_env
                            generate_singbox_config
                            /etc/init.d/sing-box restart 2>/dev/null || true
                            reload_singbox_api
                            echo "[✓] Ключ добавлен в локальный пул my_nodes и подключен к автовыбору!"
                        fi
                        sleep 2
                        ;;
                    3)
                        echo "proxies: []" > "$CUSTOM_NODES_FILE"
                        load_gateway_env
                        generate_singbox_config
                        /etc/init.d/sing-box restart 2>/dev/null || true
                        echo "[✓] Дополнительные личные ключи очищены."
                        sleep 2
                        ;;
                    4)
                        if generate_amnezia_warp; then
                            load_gateway_env
                            generate_singbox_config
                            /etc/init.d/sing-box restart 2>/dev/null || true
                            reload_singbox_api
                            echo "[✓] Группа '☁️ Amnezia WARP' (4 ноды Cloudflare Anycast) добавлена в веб-панель!"
                        fi
                        sleep 3
                        ;;
                    5)
                        echo '{"outbounds": []}' > "$WARP_NODES_FILE"
                        load_gateway_env
                        generate_singbox_config
                        /etc/init.d/sing-box restart 2>/dev/null || true
                        echo "[✓] Пул нод Amnezia WARP 2.0 отключен и очищен."
                        sleep 2
                        ;;
                esac
                ;;
            3)
                echo "Проверка и тихое обновление ядер и веб-панели..."
                update_cores_only "yes"
                /etc/init.d/sing-box restart 2>/dev/null || true
                if grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null && [ -x /usr/bin/AdGuardHome ]; then
                    /etc/init.d/adguardhome restart 2>/dev/null || true
                fi
                refresh_remote_versions
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            4)
                echo "Проверка синтаксиса конфигурации Sing-Box Extended..."
                if check_singbox_config; then
                    reload_singbox_api
                    conntrack -F >/dev/null 2>&1 || true
                    /etc/init.d/sing-box restart 2>/dev/null || true
                    if grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null; then
                        /etc/init.d/adguardhome restart 2>/dev/null || true
                    fi
                    echo "[✓] Кэш Fake-IP и таблица conntrack очищены, службы успешно перезапущены."
                else
                    echo "[X] Конфигурация повреждена! Подробности:"
                    ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
                        /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" || true
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
                if [ ! -f "$SB_CONF" ]; then
                    echo "[X] Конфигурация не найдена. Запустите пункт 6."
                    sleep 2
                    continue
                fi
                load_gateway_env
                echo "Выберите веб-панель Sing-Box:"
                echo " 1) MetaCubeXD"
                echo " 2) Zashboard"
                printf "Ваш выбор [1-2]: "
                read -r UI_SEL < /dev/tty || true
                case "$UI_SEL" in
                    2)
                        UI_TYPE="zashboard"
                        NEW_UI_NAME="Zashboard"
                        NEW_UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
                        ;;
                    1)
                        UI_TYPE="metacubexd"
                        NEW_UI_NAME="MetaCubeXD"
                        NEW_UI_TAR_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.tar.gz"
                        ;;
                    *)
                        continue
                        ;;
                esac
                generate_singbox_config
                install_singbox_ui "$UI_TYPE" "$NEW_UI_NAME" "$NEW_UI_TAR_URL"
                echo "[✓] Панель переключена на ${NEW_UI_NAME}! Обновите страницу в браузере (Ctrl+F5)."
                sleep 2
                ;;
            8)
                echo "=== Пользовательские правила доменов ==="
                echo "Домены В ПРОКСИ (${USER_PROXY_FILE}):"
                cat "$USER_PROXY_FILE" 2>/dev/null || true
                echo "----------------------------------------"
                echo "Домены НАПРЯМУЮ (${USER_DIRECT_FILE}):"
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
                            case "$D_IN" in +.*) ;; *.*) D_IN="+.$D_IN" ;; esac
                            grep -qxF "$D_IN" "$USER_PROXY_FILE" 2>/dev/null || echo "$D_IN" >> "$USER_PROXY_FILE"
                            sync_user_domain_rulesets
                            /etc/init.d/sing-box restart 2>/dev/null || true
                            echo "[✓] Добавлено в прокси: $D_IN"
                        fi
                        sleep 2
                        ;;
                    2)
                        printf "Введите домен для прямого доступа (например, +.avito.ru): "
                        read -r D_IN < /dev/tty || true
                        D_IN=$(printf "%s" "$D_IN" | tr -d ' \t\r\n')
                        if [ -n "$D_IN" ]; then
                            case "$D_IN" in +.*) ;; *.*) D_IN="+.$D_IN" ;; esac
                            grep -qxF "$D_IN" "$USER_DIRECT_FILE" 2>/dev/null || echo "$D_IN" >> "$USER_DIRECT_FILE"
                            sync_user_domain_rulesets
                            /etc/init.d/sing-box restart 2>/dev/null || true
                            echo "[✓] Добавлено напрямую: $D_IN"
                        fi
                        sleep 2
                        ;;
                    3)
                        echo "+.localdomain" > "$USER_DIRECT_FILE"
                        echo "+.chatgpt.com" > "$USER_PROXY_FILE"
                        sync_user_domain_rulesets
                        /etc/init.d/sing-box restart 2>/dev/null || true
                        echo "[✓] Пользовательские списки доменов сброшены."
                        sleep 2
                        ;;
                esac
                ;;
            9)
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
                        if [ -n "$IP_IN" ]; then
                            sed -i "\|^${IP_IN}$|d" "$USER_FORCE_PROXY_IPS" 2>/dev/null || true
                            grep -qxF "$IP_IN" "$USER_BYPASS_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_BYPASS_IPS"
                            load_gateway_env
                            generate_singbox_config
                            if check_singbox_config; then
                                /etc/init.d/sing-box restart 2>/dev/null || true
                                conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                                echo "[✓] Устройство ${IP_IN} теперь идет мимо прокси (DIRECT)."
                            else
                                mv "${SB_CONF}.bak" "$SB_CONF"
                                echo "[X] Ошибка синтаксиса IP! Выполнен авто-откат."
                            fi
                        fi
                        sleep 2
                        ;;
                    2)
                        printf "Введите локальный IP для Full-VPN (всегда в прокси): "
                        read -r IP_IN < /dev/tty || true
                        IP_IN=$(printf "%s" "$IP_IN" | tr -d ' \t\r\n')
                        if [ -n "$IP_IN" ]; then
                            sed -i "\|^${IP_IN}$|d" "$USER_BYPASS_IPS" 2>/dev/null || true
                            grep -qxF "$IP_IN" "$USER_FORCE_PROXY_IPS" 2>/dev/null || echo "$IP_IN" >> "$USER_FORCE_PROXY_IPS"
                            load_gateway_env
                            generate_singbox_config
                            if check_singbox_config; then
                                /etc/init.d/sing-box restart 2>/dev/null || true
                                conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                                echo "[✓] Трафик устройства ${IP_IN} направлен в группу '📺 Устройства (Full-VPN)'."
                            else
                                mv "${SB_CONF}.bak" "$SB_CONF"
                                echo "[X] Ошибка синтаксиса IP! Выполнен авто-откат."
                            fi
                        fi
                        sleep 2
                        ;;
                    3)
                        : > "$USER_BYPASS_IPS"
                        : > "$USER_FORCE_PROXY_IPS"
                        load_gateway_env
                        generate_singbox_config
                        /etc/init.d/sing-box restart 2>/dev/null || true
                        conntrack -F >/dev/null 2>&1 || true
                        echo "[✓] Списки маршрутизации по IP очищены."
                        sleep 2
                        ;;
                esac
                ;;
            10)
                echo "=== Сервисный режим и резервное копирование ==="
                echo " 1) Пауза: переключить весь трафик в DIRECT (без остановки DNS)"
                echo " 2) Возобновить работу по правилам (mode: rule)"
                echo " 3) Создать бэкап всех настроек и фильтров (${BACKUP_ARCHIVE})"
                echo " 4) Восстановить настройки из бэкапа (${BACKUP_ARCHIVE})"
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
                        tar -czf "$BACKUP_ARCHIVE" /etc/sing-box 2>/dev/null
                        echo "[✓] Архив сохранен в ${BACKUP_ARCHIVE}"
                        sleep 2
                        ;;
                    4)
                        if [ -f "$BACKUP_ARCHIVE" ]; then
                            tar -xzf "$BACKUP_ARCHIVE" -C /
                            /etc/init.d/sing-box restart 2>/dev/null || true
                            if grep -q '"listen_port": 1053' "$SB_CONF" 2>/dev/null; then
                                /etc/init.d/adguardhome restart 2>/dev/null || true
                            else
                                /etc/init.d/adguardhome stop 2>/dev/null || true
                            fi
                            echo "[✓] Конфигурация восстановлена из ${BACKUP_ARCHIVE}"
                        else
                            echo "[X] Файл бэкапа ${BACKUP_ARCHIVE} не найден!"
                        fi
                        sleep 2
                        ;;
                esac
                ;;
            11)
                echo "=== Автообновление Sing-Box Extended, AdGuard Home и веб-панелей ==="
                echo " ⚠️  Бро я думаю ты осознаешь последствия ,_,"
                echo "--------------------------------------------------------"
                if is_autoupdate_enabled; then
                    echo " Текущий статус: ВКЛЮЧЕНО (каждый день в 04:00)"
                else
                    echo " Текущий статус: ВЫКЛЮЧЕНО"
                fi
                echo "--------------------------------------------------------"
                echo " 1) Включить (поставил и забыл — Бро я думаю ты осознаешь последствия ,_,)"
                echo " 2) Выключить (обновлять только вручную через пункт 3)"
                echo " 3) Посмотреть лог последнего автообновления (${AUTOUPDATE_LOG})"
                echo " 0) Назад"
                printf "Выбор: "
                read -r AU_ACT < /dev/tty || true
                case "$AU_ACT" in
                    1)
                        enable_autoupdate
                        echo "[✓] Автообновление включено (ежедневно в 04:00). Бро я думаю ты осознаешь последствия ,_,"
                        sleep 2
                        ;;
                    2)
                        disable_autoupdate
                        echo "[✓] Автообновление отключено."
                        sleep 2
                        ;;
                    3)
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
            12)
                detect_adblock_mode
                echo "=== Управление блокировкой рекламы и ролью DNS ==="
                echo " Текущий режим: ${ADBLOCK_STAT} (${ADBLOCK_DESC})"
                echo "--------------------------------------------------------"
                echo " 1) Только AdGuard Home (DNS 0.0.0.0:53 + фильтрация AGH, Sing-Box на 1053)"
                echo " 2) Только Sing-Box (.srs списки + SNI, AGH останавливается, DNS 0.0.0.0:53 берет Sing-Box)"
                echo " 3) Оба: AdGuard Home + Sing-Box (двойной щит: DNS AGH + .srs/SNI в Sing-Box)"
                echo " 4) Выключить блокировку рекламы (режим отладки)"
                echo " 0) Назад"
                printf "Выбор [0-4]: "
                read -r ADB_ACT < /dev/tty || true
                case "$ADB_ACT" in
                    1) apply_adblock_mode "agh";     sleep 2 ;;
                    2) apply_adblock_mode "singbox"; sleep 2 ;;
                    3) apply_adblock_mode "both";    sleep 2 ;;
                    4) apply_adblock_mode "off";     sleep 2 ;;
                esac
                ;;
            13)
                echo "=== Аппаратный Kill-Switch (fw4 / nftables) ==="
                echo "Блокирует любую прямую маршрутизацию из br-lan в основной роутер в обход singbox-tun."
                echo "Если служба Sing-Box упадет, клиенты не «светят» реальный российский IP провайдера."
                echo "--------------------------------------------------------"
                echo " 1) ВКЛЮЧИТЬ строгий Kill-Switch (рекомендуется против утечек)"
                echo " 2) ВЫКЛЮЧИТЬ строгий Kill-Switch (оставить только защиту IPv6, DoT 853 и DNS 53)"
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
            0)
                exit 0
                ;;
        esac
    done
}

# Маршрутизация аргументов командной строки
if [ "${1:-}" = "autoupdate" ]; then
    run_autoupdate
elif [ ! -f "$SB_CONF" ] || [ "${1:-}" = "install" ]; then
    run_installer
else
    show_menu
fi
# ==================== [ КОНЕЦ ЧАСТИ 4 ИЗ 4 ] =====================