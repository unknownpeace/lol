#!/bin/sh
set -e

# ==============================================================================
# Умный загрузчик: поддержка curl | sh, прямого запуска и установки gateway
# ==============================================================================
if [ ! -t 0 ]; then
    case "$0" in
        *sh|*ash|*dash)
            BOOTSTRAP_FILE="/tmp/setup_gateway_$$.sh"
            cat > "$BOOTSTRAP_FILE"
            chmod +x "$BOOTSTRAP_FILE"
            exec /bin/sh "$BOOTSTRAP_FILE" "$@" < /dev/tty
            ;;
    esac
fi

INSTALL_PATH="/usr/bin/gateway"
SCRIPT_BASE="$(basename "$0" 2>/dev/null || true)"
if [ -f "$0" ] && [ "$0" != "$INSTALL_PATH" ] && [ "$SCRIPT_BASE" != "sh" ] && [ "$SCRIPT_BASE" != "ash" ] && [ "$SCRIPT_BASE" != "-sh" ] && [ "$SCRIPT_BASE" != "-ash" ]; then
    cp -f "$0" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
fi

# ==============================================================================
# Глобальные пути и переменные (OpenWrt 23.x / 24.x / 25.x + APK/OPKG — 2026)
# ==============================================================================
MIHOMO_DIR="/etc/mihomo"
MIHOMO_CONF="${MIHOMO_DIR}/config.yaml"
MIHOMO_RULES_DIR="${MIHOMO_DIR}/rule_sets"
MIHOMO_PROVIDERS_DIR="${MIHOMO_DIR}/proxy_providers"
CUSTOM_SUB_FILE="${MIHOMO_PROVIDERS_DIR}/custom_sub.yaml"
CUSTOM_NODES_FILE="${MIHOMO_PROVIDERS_DIR}/my_nodes.yaml"
WARP_NODES_FILE="${MIHOMO_PROVIDERS_DIR}/warp_nodes.yaml"
USER_DIRECT_FILE="${MIHOMO_RULES_DIR}/user_direct_domains.list"
USER_PROXY_FILE="${MIHOMO_RULES_DIR}/user_proxy_domains.list"
USER_BYPASS_IPS="${MIHOMO_DIR}/bypass_devices.conf"
USER_FORCE_PROXY_IPS="${MIHOMO_DIR}/force_proxy_devices.conf"
BACKUP_ARCHIVE="/root/gateway_backup.tar.gz"
CRON_FILE="/etc/crontabs/root"
AUTOUPDATE_LOG="/var/log/gateway_autoupdate.log"
UI_TYPE_FILE="/etc/mihomo/ui/.ui_type"
UI_VER_FILE="/etc/mihomo/ui/.ui_version"
AGH_CONF="/etc/AdGuardHome/AdGuardHome.yaml"
SYSUPGRADE_CONF="/etc/sysupgrade.conf"
SUB_FILTER_REGEX="(?i)(剩余|过期|到期|官网|流量|套餐|重置|expire|traffic|website|official|осталось|трафик|истекает|подписк|тариф|инфо|новост|поддержк|канал|бот|t[.]me/)"
GH_PROXY=""
LATEST_MIHOMO_TAG=""
LATEST_AGH_TAG=""
LATEST_UI_TAG=""
LAN_DEV="br-lan"
PKG_MGR="apk"
LOW_RAM_SYSTEM="no"

# ==============================================================================
# Аппаратная диагностика и поддержка пакетных менеджеров (APK и OPKG)
# ==============================================================================
detect_pkg_manager() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MGR="opkg"
    else
        echo "[X] Ошибка: Не найден пакетный менеджер (требуется apk или opkg)."
        exit 1
    fi
}

detect_os() {
    if [ ! -f /etc/openwrt_release ]; then
        echo "[X] Ошибка: Скрипт предназначен исключительно для OpenWrt."
        exit 1
    fi

    detect_pkg_manager

    OS_VER=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d"'" -f2 || echo "Unknown")
    OS_NAME="OpenWrt (${OS_VER}, ${PKG_MGR})"
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64)
            if grep -q "avx2" /proc/cpuinfo 2>/dev/null; then
                MIHOMO_ARCH="amd64-v3"
            else
                MIHOMO_ARCH="amd64-compatible"
            fi
            AGH_ARCH="amd64"
            ;;
        aarch64|arm64)
            MIHOMO_ARCH="arm64"
            AGH_ARCH="arm64"
            ;;
        armv7l|armv7)
            MIHOMO_ARCH="armv7"
            AGH_ARCH="armv7"
            ;;
        mips|mipsel)
            MIHOMO_ARCH="mips-softfloat"
            AGH_ARCH="mipsle-softfloat"
            ;;
        *)
            echo "[X] Ошибка: Неподдерживаемая архитектура ${ARCH_RAW}."
            exit 1
            ;;
    esac
}

detect_lan_dev() {
    LAN_DEV=$(uci -q get network.lan.device 2>/dev/null || true)
    [ -z "$LAN_DEV" ] && LAN_DEV=$(uci -q get network.lan.ifname 2>/dev/null || true)
    [ -z "$LAN_DEV" ] && LAN_DEV=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
    [ -z "$LAN_DEV" ] && LAN_DEV="br-lan"
}

check_system_memory() {
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    [ -z "$TOTAL_RAM_KB" ] && TOTAL_RAM_KB=524288
    TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))

    if [ "$TOTAL_RAM_MB" -lt 240 ]; then
        LOW_RAM_SYSTEM="yes"
        SWAP_TOTAL=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
        if [ "${SWAP_TOTAL:-0}" -eq 0 ]; then
            install_packages "zram-swap"
            if [ -x /etc/init.d/zram ]; then
                uci set zram.@zram[0].zram_size_mb="$((TOTAL_RAM_MB / 2))" 2>/dev/null || true
                uci commit zram 2>/dev/null || true
                /etc/init.d/zram enable 2>/dev/null || true
                /etc/init.d/zram restart 2>/dev/null || true
            fi
        fi
    else
        LOW_RAM_SYSTEM="no"
    fi
}

install_packages() {
    PKGS="$*"
    [ -z "$PKGS" ] && return 0
    detect_pkg_manager
    NEED_PKGS=""
    for pkg in $PKGS; do
        if [ "$PKG_MGR" = "apk" ]; then
            apk info -e "$pkg" >/dev/null 2>&1 || NEED_PKGS="$NEED_PKGS $pkg"
        else
            opkg list-installed "$pkg" 2>/dev/null | grep -q "^$pkg" || NEED_PKGS="$NEED_PKGS $pkg"
        fi
    done

    if [ -n "$NEED_PKGS" ]; then
        echo "Установка необходимых пакетов (${PKG_MGR}): ${NEED_PKGS}..."
        if [ "$PKG_MGR" = "apk" ]; then
            apk update --allow-untrusted >/dev/null 2>&1 || true
            # shellcheck disable=SC2086
            apk add --allow-untrusted $NEED_PKGS >/dev/null 2>&1 || true
        else
            opkg update >/dev/null 2>&1 || true
            # shellcheck disable=SC2086
            opkg install $NEED_PKGS >/dev/null 2>&1 || true
        fi
    fi
}

# Защита файлов шлюза от удаления при обновлении прошивки OpenWrt (sysupgrade / owut)
ensure_sysupgrade_persistence() {
    touch "$SYSUPGRADE_CONF" 2>/dev/null || return 0
    for item in \
        "/usr/bin/gateway" \
        "/usr/bin/mihomo" \
        "/usr/bin/AdGuardHome" \
        "/etc/mihomo" \
        "/etc/AdGuardHome" \
        "/etc/init.d/mihomo" \
        "/etc/init.d/adguardhome" \
        "/etc/sysctl.d/99-gateway-forward.conf" \
        "/etc/nftables.d"
    do
        grep -qxF "$item" "$SYSUPGRADE_CONF" 2>/dev/null || echo "$item" >> "$SYSUPGRADE_CONF"
    done
}

# Отключение фонового демона apache (устанавливается как зависимость apache-utils для htpasswd)
disable_apache_daemon() {
    for srv in apache apache2 httpd; do
        if [ -x "/etc/init.d/${srv}" ]; then
            "/etc/init.d/${srv}" stop >/dev/null 2>&1 || true
            "/etc/init.d/${srv}" disable >/dev/null 2>&1 || true
        fi
    done
}

# Определение параметров текущей выбранной веб-панели
detect_current_ui() {
    CUR_UI_TYPE=""
    if [ -f "$UI_TYPE_FILE" ]; then
        CUR_UI_TYPE=$(cat "$UI_TYPE_FILE" 2>/dev/null | tr -d ' \t\r\n')
    elif grep -qi "zashboard" "$MIHOMO_CONF" 2>/dev/null; then
        CUR_UI_TYPE="zashboard"
    elif [ -f "$MIHOMO_CONF" ]; then
        CUR_UI_TYPE="metacubexd"
    fi

    if [ "$CUR_UI_TYPE" = "zashboard" ]; then
        CUR_UI_NAME="Zashboard"
        CUR_UI_REPO="Zephyruso/zashboard"
        CUR_UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
    else
        CUR_UI_TYPE="metacubexd"
        CUR_UI_NAME="MetaCubeXD"
        CUR_UI_REPO="MetaCubeX/metacubexd"
        CUR_UI_TAR_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.tar.gz"
    fi
}

# Определение текущего режима блокировки рекламы и роли DNS
detect_adblock_mode() {
    MIHOMO_ADBLOCK="no"
    AGH_ADBLOCK="no"
    AGH_DNS_ACTIVE="no"

    if [ -f "$MIHOMO_CONF" ] && grep -q '^[[:space:]]*- RULE-SET,ads_domain,' "$MIHOMO_CONF" 2>/dev/null; then
        MIHOMO_ADBLOCK="yes"
    fi

    if grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null && pgrep AdGuardHome >/dev/null 2>&1; then
        AGH_DNS_ACTIVE="yes"
        if [ -f "$AGH_CONF" ] && grep -q 'filtering_enabled:[[:space:]]*true' "$AGH_CONF" 2>/dev/null; then
            AGH_ADBLOCK="yes"
        fi
    fi

    if [ "$AGH_DNS_ACTIVE" = "yes" ] && [ "$AGH_ADBLOCK" = "yes" ] && [ "$MIHOMO_ADBLOCK" = "yes" ]; then
        ADBLOCK_MODE="both"
        ADBLOCK_STAT="[AGH + Mihomo]"
        ADBLOCK_DESC="двойной щит (DNS AGH + .mrs/SNI)"
    elif [ "$AGH_DNS_ACTIVE" = "yes" ] && [ "$AGH_ADBLOCK" = "yes" ]; then
        ADBLOCK_MODE="agh"
        ADBLOCK_STAT="[AdGuard Home]"
        ADBLOCK_DESC="DNS и фильтрация через AGH"
    elif [ "$MIHOMO_ADBLOCK" = "yes" ]; then
        ADBLOCK_MODE="mihomo"
        ADBLOCK_STAT="[Mihomo .mrs] "
        ADBLOCK_DESC="DNS 0.0.0.0:53 + .mrs/SNI (AGH остановлен)"
    else
        ADBLOCK_MODE="off"
        ADBLOCK_STAT="[ВЫКЛЮЧЕНА]   "
        ADBLOCK_DESC="реклама и трекеры не режутся"
    fi
}

# Проверка, активны ли ноды Amnezia WARP
is_warp_enabled() {
    [ -f "$WARP_NODES_FILE" ] && grep -q "type: wireguard" "$WARP_NODES_FILE" 2>/dev/null
}

# Проверка состояния аппаратного Kill-Switch
is_killswitch_enabled() {
    [ -f /etc/nftables.d/97-mihomo-anti-leak.nft ] && grep -q "#KILLSWITCH_ACTIVE" /etc/nftables.d/97-mihomo-anti-leak.nft 2>/dev/null
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

    detect_lan_dev
    mkdir -p /etc/nftables.d

    # 1. Выравнивание TCP MSS (защита от PMTU Blackhole и детекта MTU в Sidecar-схеме)
    cat << 'NFT_MSS' > /etc/nftables.d/98-mihomo-mss-clamp.nft
chain mihomo_mss_clamp {
    type filter hook forward priority mangle; policy accept;
    oifname "mihomo-tun" tcp flags syn tcp option maxseg size set rt mtu
    iifname "mihomo-tun" tcp flags syn tcp option maxseg size set rt mtu
}
NFT_MSS

    # 2. Защита от утечек (Anti-Leak): жесткий блок IPv6 форвардинга, DoT/DoQ (853) и Kill-Switch
    if [ "$KS_STATE" = "yes" ]; then
        cat << NFT_LEAK_KS > /etc/nftables.d/97-mihomo-anti-leak.nft
#KILLSWITCH_ACTIVE
chain mihomo_anti_leak {
    type filter hook forward priority filter - 5; policy accept;
    meta nfproto ipv6 drop
    iifname "${LAN_DEV}" meta l4proto { tcp, udp } th dport 853 reject
    iifname "${LAN_DEV}" oifname "${LAN_DEV}" ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } reject
}
NFT_LEAK_KS
    else
        cat << NFT_LEAK > /etc/nftables.d/97-mihomo-anti-leak.nft
chain mihomo_anti_leak {
    type filter hook forward priority filter - 5; policy accept;
    meta nfproto ipv6 drop
    iifname "${LAN_DEV}" meta l4proto { tcp, udp } th dport 853 reject
}
NFT_LEAK
    fi

    # 3. Принудительный перехват любых сторонних DNS-запросов (зашитых 8.8.8.8 на Smart TV / IoT)
    if [ "$USE_DNS_REDIRECT" = "yes" ]; then
        cat << NFT_OWRT > /etc/nftables.d/99-agh-dns-redirect.nft
chain agh_dns_prerouting {
    type nat hook prerouting priority dstnat - 5; policy accept;
    iifname "${LAN_DEV}" meta l4proto { tcp, udp } th dport 53 redirect to :53
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

# Подготовка, очистка багов и миграция конфига Mihomo
ensure_mihomo_config_tags() {
    [ -f "$MIHOMO_CONF" ] || return 0

    # Исправление экранирования t\.me/
    sed -i 's/t\\\.me\//t[.]me\//g' "$MIHOMO_CONF" 2>/dev/null || true

    # КРИТИЧЕСКИЙ БАГФИКС: удаление '*' из fake-ip-filter (blacklist)
    sed -i '/^[[:space:]]*-[[:space:]]*"\*"/d' "$MIHOMO_CONF" 2>/dev/null || true

    # КРИТИЧЕСКИЙ БАГФИКС: удаление "*": "${GW_IP}" из nameserver-policy для исключения утечек DNS
    sed -i '/^[[:space:]]*"\*":[[:space:]]*"\${GW_IP}"/d' "$MIHOMO_CONF" 2>/dev/null || true
    sed -i 's/^[[:space:]]*"\*":[[:space:]]*"[0-9.]*"/# &/' "$MIHOMO_CONF" 2>/dev/null || true

    if ! grep -q "#DNS_HIJACK" "$MIHOMO_CONF" 2>/dev/null; then
        if grep -q "dns-hijack:" "$MIHOMO_CONF" 2>/dev/null; then
            sed -i '/dns-hijack:/ s/$/ #DNS_HIJACK/' "$MIHOMO_CONF"
            sed -i '/- "any:53"/ s/$/ #DNS_HIJACK/' "$MIHOMO_CONF"
            sed -i '/- "tcp:\/\/any:53"/ s/$/ #DNS_HIJACK/' "$MIHOMO_CONF"
        else
            awk '
                /^[[:space:]]*udp-timeout:/ {
                    print
                    print "#  dns-hijack: #DNS_HIJACK"
                    print "#    - \"any:53\" #DNS_HIJACK"
                    print "#    - \"tcp://any:53\" #DNS_HIJACK"
                    next
                }
                { print }
            ' "$MIHOMO_CONF" > "${MIHOMO_CONF}.tmp" && mv "${MIHOMO_CONF}.tmp" "$MIHOMO_CONF"
        fi
    fi

    if ! grep -q "#ADBLOCK_MIHOMO" "$MIHOMO_CONF" 2>/dev/null; then
        if grep -q "ads_domain:" "$MIHOMO_CONF" 2>/dev/null; then
            awk '
                /^  - name: "🛑 Реклама"/ { in_ag=3 }
                in_ag > 0 { print $0 " #ADBLOCK_MIHOMO"; in_ag--; next }
                /^  ads_domain:/ { in_ap=4 }
                in_ap > 0 { print $0 " #ADBLOCK_MIHOMO"; in_ap--; next }
                /^  telemetry_domain:/ { in_tp=4 }
                in_tp > 0 { print $0 " #ADBLOCK_MIHOMO"; in_tp--; next }
                /RULE-SET,(ads_domain|telemetry_domain),/ { print $0 " #ADBLOCK_MIHOMO"; next }
                { print }
            ' "$MIHOMO_CONF" > "${MIHOMO_CONF}.tmp" && mv "${MIHOMO_CONF}.tmp" "$MIHOMO_CONF"
        else
            check_github_mirror
            awk -v gh="$GH_PROXY" '
                /^  - name: "🇷🇺 Россия"/ {
                    print "#  - name: \"🛑 Реклама\" #ADBLOCK_MIHOMO"
                    print "#    type: select #ADBLOCK_MIHOMO"
                    print "#    proxies: [REJECT, REJECT-DROP, DIRECT] #ADBLOCK_MIHOMO"
                }
                /^  ai_domain:/ {
                    print "#  ads_domain: #ADBLOCK_MIHOMO"
                    print "#    <<: *mrs_domain #ADBLOCK_MIHOMO"
                    print "#    path: ./rule_sets/category-ads-all.mrs #ADBLOCK_MIHOMO"
                    print "#    url: \"" gh "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ads-all.mrs\" #ADBLOCK_MIHOMO"
                    print "#  telemetry_domain: #ADBLOCK_MIHOMO"
                    print "#    <<: *mrs_domain #ADBLOCK_MIHOMO"
                    print "#    path: ./rule_sets/category-telemetry.mrs #ADBLOCK_MIHOMO"
                    print "#    url: \"" gh "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-telemetry.mrs\" #ADBLOCK_MIHOMO"
                }
                /^  - RULE-SET,private_ip,DIRECT,no-resolve/ {
                    print
                    print "#  - RULE-SET,ads_domain,🛑 Реклама #ADBLOCK_MIHOMO"
                    print "#  - RULE-SET,telemetry_domain,🛑 Реклама #ADBLOCK_MIHOMO"
                    next
                }
                { print }
            ' "$MIHOMO_CONF" > "${MIHOMO_CONF}.tmp" && mv "${MIHOMO_CONF}.tmp" "$MIHOMO_CONF"
        fi
    fi

    # Авто-миграция конфига для пула warp_nodes
    if ! grep -q "warp_nodes:" "$MIHOMO_CONF" 2>/dev/null; then
        awk '
            /^  my_nodes:/ {
                print "  warp_nodes:"
                print "    type: file"
                print "    path: ./proxy_providers/warp_nodes.yaml"
                print "    health-check: *hc_default"
                print "    override:"
                print "      udp: true"
            }
            {
                gsub(/use: \[custom_sub, my_nodes\]/, "use: [custom_sub, my_nodes, warp_nodes]")
                print
            }
        ' "$MIHOMO_CONF" > "${MIHOMO_CONF}.tmp" && mv "${MIHOMO_CONF}.tmp" "$MIHOMO_CONF"
    fi
}

# Автоустановка и инициализация AdGuard Home
ensure_agh_installed() {
    detect_os
    if [ ! -x /usr/bin/AdGuardHome ]; then
        USE_AGH="yes" update_cores_only "no"
    fi

    if [ ! -f "$AGH_CONF" ]; then
        GW_IP_CUR=$(sed -n 's/^[[:space:]]*"+\.lan":[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" 2>/dev/null | head -n 1 | tr -d ' \t\r\n')
        [ -z "$GW_IP_CUR" ] && GW_IP_CUR=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')
        PASS_CUR=$(sed -n 's/^secret:[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" 2>/dev/null | head -n 1 | tr -d '\r\n')
        [ -z "$PASS_CUR" ] && PASS_CUR="admin"

        if ! command -v htpasswd >/dev/null 2>&1; then
            install_packages "apache-utils"
            disable_apache_daemon
        fi

        AGH_PASS_HASH=$(printf "%s\n" "$PASS_CUR" | htpasswd -inBC 10 "admin" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH=$(htpasswd -nbBC 10 "admin" "$PASS_CUR" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH='$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'

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
  bootstrap_dns: [${GW_IP_CUR}, 77.88.8.8, 77.88.8.1]
  upstream_mode: load_balance
  cache_enabled: false
  cache_size: 0
  aaaa_disabled: true
  enable_dnssec: false
  use_private_ptr_resolvers: true
  local_ptr_upstreams: [${GW_IP_CUR}:53]
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

# Применение выбранного режима блокировки рекламы и роли DNS (agh | mihomo | both | off)
apply_adblock_mode() {
    MODE="$1"
    [ -f "$MIHOMO_CONF" ] || return 0
    cp -f "$MIHOMO_CONF" "${MIHOMO_CONF}.bak"
    ensure_mihomo_config_tags

    case "$MODE" in
        mihomo)
            echo "Остановка AdGuard Home и передача роли DNS (0.0.0.0:53) в Mihomo..."
            /etc/init.d/adguardhome stop 2>/dev/null || true
            /etc/init.d/adguardhome disable 2>/dev/null || true
            sync_dns_firewall "yes" "keep"

            sed -i 's/^[[:space:]]*listen:[[:space:]]*127\.0\.0\.1:1053/  listen: 0.0.0.0:53/' "$MIHOMO_CONF"
            sed -i '/#DNS_HIJACK$/ s/^#*//' "$MIHOMO_CONF"
            sed -i '/#ADBLOCK_MIHOMO$/ s/^#*//' "$MIHOMO_CONF"

            if /usr/bin/mihomo -d "$MIHOMO_DIR" -t >/dev/null 2>&1; then
                /etc/init.d/mihomo restart 2>/dev/null || true
                echo "[✓] AdGuard Home остановлен. Mihomo принял на себя роль DNS (0.0.0.0:53) и блокировку рекламы (.mrs + SNI)."
            else
                mv "${MIHOMO_CONF}.bak" "$MIHOMO_CONF"
                echo "[X] Ошибка проверки конфига Mihomo! Выполнен авто-откат."
                return 1
            fi
            ;;

        agh)
            echo "Переключение DNS и фильтрации рекламы на AdGuard Home..."
            ensure_agh_installed
            sed -i 's/^[[:space:]]*listen:[[:space:]]*0\.0\.0\.0:53/  listen: 127.0.0.1:1053/' "$MIHOMO_CONF"
            sed -i '/#DNS_HIJACK$/ s/^#*/#/' "$MIHOMO_CONF"
            sed -i '/#ADBLOCK_MIHOMO$/ s/^#*/#/' "$MIHOMO_CONF"

            if /usr/bin/mihomo -d "$MIHOMO_DIR" -t >/dev/null 2>&1; then
                /etc/init.d/mihomo restart 2>/dev/null || true
                set_agh_filtering "true"
                /etc/init.d/adguardhome enable 2>/dev/null || true
                /etc/init.d/adguardhome restart 2>/dev/null || true
                sync_dns_firewall "yes" "keep"
                echo "[✓] Роль DNS (0.0.0.0:53) и фильтрация рекламы переданы AdGuard Home (Mihomo переведен на 127.0.0.1:1053)."
            else
                mv "${MIHOMO_CONF}.bak" "$MIHOMO_CONF"
                echo "[X] Ошибка проверки конфига Mihomo! Выполнен авто-откат."
                return 1
            fi
            ;;

        both)
            echo "Включение режима двойного щита (DNS AdGuard Home + правила .mrs в Mihomo)..."
            ensure_agh_installed
            sed -i 's/^[[:space:]]*listen:[[:space:]]*0\.0\.0\.0:53/  listen: 127.0.0.1:1053/' "$MIHOMO_CONF"
            sed -i '/#DNS_HIJACK$/ s/^#*/#/' "$MIHOMO_CONF"
            sed -i '/#ADBLOCK_MIHOMO$/ s/^#*//' "$MIHOMO_CONF"

            if /usr/bin/mihomo -d "$MIHOMO_DIR" -t >/dev/null 2>&1; then
                /etc/init.d/mihomo restart 2>/dev/null || true
                set_agh_filtering "true"
                /etc/init.d/adguardhome enable 2>/dev/null || true
                /etc/init.d/adguardhome restart 2>/dev/null || true
                sync_dns_firewall "yes" "keep"
                echo "[✓] Включен двойной щит: AdGuard Home (DNS 0.0.0.0:53) + Mihomo (.mrs + SNI)."
            else
                mv "${MIHOMO_CONF}.bak" "$MIHOMO_CONF"
                echo "[X] Ошибка проверки конфига Mihomo! Выполнен авто-откат."
                return 1
            fi
            ;;

        off)
            echo "Отключение фильтрации рекламы (режим отладки)..."
            if pgrep AdGuardHome >/dev/null 2>&1; then
                set_agh_filtering "false"
            fi
            sed -i '/#ADBLOCK_MIHOMO$/ s/^#*/#/' "$MIHOMO_CONF"
            if /usr/bin/mihomo -d "$MIHOMO_DIR" -t >/dev/null 2>&1; then
                reload_mihomo_api
                echo "[✓] Блокировка рекламы полностью отключена (текущая схема DNS сохранена)."
            else
                mv "${MIHOMO_CONF}.bak" "$MIHOMO_CONF"
                echo "[X] Ошибка проверки конфига Mihomo! Выполнен авто-откат."
                return 1
            fi
            ;;
    esac
}

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
    if ! pgrep mihomo >/dev/null 2>&1; then
        /etc/init.d/mihomo start 2>/dev/null || true
    fi
    if grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null && [ -x /usr/bin/AdGuardHome ]; then
        if ! pgrep AdGuardHome >/dev/null 2>&1; then
            /etc/init.d/adguardhome start 2>/dev/null || true
        fi
    fi
    reload_mihomo_api
    echo "=== [$(date '+%Y-%m-%d %H:%M:%S')] Автообновление завершено ==="
}

# Получение последнего тега релиза с GitHub
fetch_latest_github_tag() {
    REPO="$1"
    TAG=$(curl -fsSL --connect-timeout 3 -m 5 "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | head -n 1 | cut -d'"' -f4 || true)
    if [ -z "$TAG" ]; then
        TAG=$(curl -fsSLI --connect-timeout 3 -m 5 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" 2>/dev/null | awk -F'/' '{print $NF}' | tr -d '\r\n' || true)
        [ "$TAG" = "latest" ] && TAG=""
    fi
    printf "%s" "$TAG"
}

# Кэширование актуальных версий с GitHub
refresh_remote_versions() {
    detect_current_ui
    LATEST_MIHOMO_TAG=$(fetch_latest_github_tag "MetaCubeX/mihomo")
    if [ -x /usr/bin/AdGuardHome ] || grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null; then
        LATEST_AGH_TAG=$(fetch_latest_github_tag "AdguardTeam/AdGuardHome")
    fi
    if [ -f /etc/mihomo/ui/index.html ]; then
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

    if pgrep mihomo >/dev/null 2>&1; then
        M_STAT="[ЗАПУЩЕН]     "
    else
        M_STAT="[ОСТАНОВЛЕН]  "
    fi

    if [ -x /usr/bin/mihomo ]; then
        M_VER=$(/usr/bin/mihomo -v 2>/dev/null | head -n 1 | awk '{print $3}' || true)
        [ -z "$M_VER" ] && M_VER="неизвестно"
    else
        M_VER="не установлен"
    fi

    if [ -n "$LATEST_MIHOMO_TAG" ] && [ "$M_VER" != "не установлен" ]; then
        if [ "$M_VER" = "$LATEST_MIHOMO_TAG" ]; then
            M_VER_INFO="${M_VER} (актуальна)"
        else
            M_VER_INFO="${M_VER} -> ДОСТУПНА ${LATEST_MIHOMO_TAG}!"
        fi
    else
        M_VER_INFO="${M_VER}"
    fi

    if pgrep AdGuardHome >/dev/null 2>&1; then
        A_STAT="[ЗАПУЩЕН]     "
    elif grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null; then
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
        W_INFO="8 нод (Cloudflare AWG 2.0 + Европа 🇳🇱🇫🇮🇩🇪🇵🇱)"
    else
        W_STAT="[ВЫКЛЮЧЕН]    "
        W_INFO="можно включить бесплатно в пункте 2"
    fi

    if [ -f /etc/mihomo/ui/index.html ]; then
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
        KS_INFO="строгая блокировка утечек мимо mihomo-tun"
    else
        KS_STAT="[СТАНДАРТ]    "
        KS_INFO="защита IPv6 + DoT/DoQ + перехват DNS 53"
    fi

    if is_autoupdate_enabled; then
        AU_STAT="[ВКЛЮЧЕНО]    "
        AU_INFO="ежедневно в 04:00 (поставил и забыл)"
    else
        AU_STAT="[ВЫКЛЮЧЕНО]   "
        AU_INFO="только вручную"
    fi

    echo " Mihomo:        ${M_STAT}${M_VER_INFO}"
    echo " AdGuard Home:  ${A_STAT}${A_VER_INFO}"
    echo " Amnezia WARP:  ${W_STAT}${W_INFO}"
    echo " Антиреклама:   ${ADBLOCK_STAT}${ADBLOCK_DESC}"
    echo " Kill-Switch:   ${KS_STAT}${KS_INFO}"
    echo " Веб-панель:    ${UI_STAT}${UI_VER_INFO}"
    echo " Автоапдейт:    ${AU_STAT}${AU_INFO}"
}

# Каскадный выбор зеркала GitHub при блокировках ТСПУ
check_github_mirror() {
    TEST_URL="https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/private.mrs"
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
    mkdir -p "$MIHOMO_RULES_DIR" "$MIHOMO_PROVIDERS_DIR"
    [ -f "$USER_DIRECT_FILE" ] || echo "+.localdomain" > "$USER_DIRECT_FILE"
    [ -f "$USER_PROXY_FILE" ] || echo "+.chatgpt.com" > "$USER_PROXY_FILE"
    [ -f "$USER_BYPASS_IPS" ] || : > "$USER_BYPASS_IPS"
    [ -f "$USER_FORCE_PROXY_IPS" ] || : > "$USER_FORCE_PROXY_IPS"
    [ -s "$CUSTOM_NODES_FILE" ] || echo "proxies: []" > "$CUSTOM_NODES_FILE"
    [ -s "$WARP_NODES_FILE" ] || echo "proxies: []" > "$WARP_NODES_FILE"
}

# Безопасное разделение нескольких URI-ключей без повреждения параметров
format_uri_keys() {
    printf "%s\n" "$1" | sed -E 's/[[:space:],]+((vless|vmess|ss|ssr|trojan|hy2|hysteria2|tuic|wg|wireguard|anytls|mieru|xhttp|splithttp|socks5):\/\/)/\n\1/g' | sed '/^[[:space:]]*$/d'
}

# Генератор случайных чисел для рандомизации AmneziaWG параметров
get_random_range() {
    R_MIN="$1"
    R_MAX="$2"
    awk -v min="$R_MIN" -v max="$R_MAX" 'BEGIN{srand(); print int(min+rand()*(max-min+1))}'
}

# Автоматическая генерация Amnezia WARP (Cloudflare WARP + AmneziaWG 2.0 обфускация)
generate_amnezia_warp() {
    mkdir -p "$MIHOMO_PROVIDERS_DIR"
    if ! command -v wg >/dev/null 2>&1; then
        echo "Установка wireguard-tools..."
        install_packages "wireguard-tools"
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
        echo "Бесплатная регистрация нового аккаунта Cloudflare WARP..."

        for CURL_OPT in \
            "-x http://127.0.0.1:7890" \
            "" \
            "--connect-to api.cloudflareclient.com:443:104.16.80.230:443" \
            "--connect-to api.cloudflareclient.com:443:104.17.143.163:443" \
            "--connect-to api.cloudflareclient.com:443:162.159.138.105:443" \
            "--connect-to api.cloudflareclient.com:443:162.159.137.105:443" \
            "--connect-to api.cloudflareclient.com:443:172.67.73.32:443"
        do
            # shellcheck disable=SC2086
            RESP=$(curl -fsSL --connect-timeout 4 -m 7 $CURL_OPT \
                -H "User-Agent: okhttp/3.12.1" \
                -H "Content-Type: application/json" \
                -X POST "https://api.cloudflareclient.com/v0a1922/reg" \
                -d "$REG_PAYLOAD" 2>/dev/null || true)
            if printf "%s" "$RESP" | grep -q '"v4"'; then
                WARP_IPV4=$(printf "%s" "$RESP" | sed -n 's/.*"v4":[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1)
                REG_OK="yes"
                break
            fi
        done
    fi

    # Фоллбэк на публичные зеркала генератора WARP
    if [ "$REG_OK" = "no" ]; then
        for MIRROR_API in "https://warp.llimonix.pw/api/warp" "https://warp-reg.vercel.app/api/warp"; do
            RESP_M=$(curl -fsSL --connect-timeout 4 -m 7 "$MIRROR_API" 2>/dev/null || true)
            M_PRIV=$(printf "%s" "$RESP_M" | sed -n 's/.*"private_key":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
            M_IPV4=$(printf "%s" "$RESP_M" | sed -n 's/.*"v4":[[:space:]]*"\([0-9.]*\)".*/\1/p' | head -n 1)
            if [ -n "$M_PRIV" ]; then
                PRIV_KEY="$M_PRIV"
                [ -n "$M_IPV4" ] && WARP_IPV4="$M_IPV4"
                REG_OK="yes"
                break
            fi
        done
    fi

    # Если уже есть рабочий ключ в warp_nodes.yaml и API недоступен
    if [ "$REG_OK" = "no" ] && is_warp_enabled; then
        OLD_PRIV=$(sed -n 's/^[[:space:]]*private-key:[[:space:]]*"\([^"]*\)".*/\1/p' "$WARP_NODES_FILE" 2>/dev/null | head -n 1)
        OLD_IP=$(sed -n 's/^[[:space:]]*ip:[[:space:]]*\([0-9.]*\).*/\1/p' "$WARP_NODES_FILE" 2>/dev/null | head -n 1)
        if [ -n "$OLD_PRIV" ]; then
            PRIV_KEY="$OLD_PRIV"
            WARP_IPV4="${OLD_IP:-172.16.0.2}"
            REG_OK="yes"
            echo "[i] Сохранен ранее зарегистрированный ключ Amnezia WARP."
        fi
    fi

    # Ручной ввод PrivateKey
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

    # Динамическая рандомизация параметров AWG для обхода эвристического анализа ТСПУ
    AWG_JC=$(get_random_range 3 7)
    AWG_JMIN=$(get_random_range 35 48)
    AWG_JMAX=$(get_random_range 65 92)

    cat << WARP_EOF > "$WARP_NODES_FILE"
proxies:
  - name: "☁️ WARP Fast (162.159.192.1:4500)"
    type: wireguard
    server: 162.159.192.1
    port: 4500
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: &awg_warp
      jc: ${AWG_JC}
      jmin: ${AWG_JMIN}
      jmax: ${AWG_JMAX}
      s1: 0
      s2: 0
      h1: 1
      h2: 2
      h3: 3
      h4: 4
      i1: "<r 2><b 0x8580000100010000000004796162730679616e6465780272750000010001c00c000100010000026d000457fa27d1>"

  - name: "☁️ WARP Reserve (188.114.97.1:500)"
    type: wireguard
    server: 188.114.97.1
    port: 500
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: *awg_warp

  - name: "☁️ WARP Alt (188.114.99.224:1002)"
    type: wireguard
    server: 188.114.99.224
    port: 1002
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: *awg_warp

  - name: "☁️ WARP Engage (2408)"
    type: wireguard
    server: engage.cloudflareclient.com
    port: 2408
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: *awg_warp

  - name: "🇳🇱 WARP Нидерланды (AI / ChatGPT)"
    type: wireguard
    server: nl.tribukvy.ltd
    port: 4500
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: *awg_warp

  - name: "🇫🇮 WARP Финляндия (AI / ChatGPT)"
    type: wireguard
    server: fi.tribukvy.ltd
    port: 4500
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: *awg_warp

  - name: "🇩🇪 WARP Германия (AI / ChatGPT)"
    type: wireguard
    server: de.tribukvy.ltd
    port: 4500
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: *awg_warp

  - name: "🇵🇱 WARP Польша (AI / ChatGPT)"
    type: wireguard
    server: pl.tribukvy.ltd
    port: 4500
    ip: ${WARP_IPV4}
    private-key: "${PRIV_KEY}"
    public-key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    allowed-ips: ["0.0.0.0/0"]
    udp: true
    mtu: 1280
    remote-dns-resolve: true
    dns: [1.1.1.1, 8.8.8.8]
    amnezia-wg-option: *awg_warp
WARP_EOF

    echo "[✓] Пул Amnezia WARP (8 нод: Cloudflare AWG 2.0 + Европа) успешно сгенерирован (IP: ${WARP_IPV4}, JC: ${AWG_JC})!"
    return 0
}

# Горячая перезагрузка конфигурации и провайдеров Mihomo через REST API + сброс Fake-IP
reload_mihomo_api() {
    if ! pgrep mihomo >/dev/null 2>&1; then
        return 0
    fi
    API_SECRET=""
    [ -f "$MIHOMO_CONF" ] && API_SECRET=$(sed -n 's/^secret:[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" | head -n 1 | tr -d '\r\n')
    curl -fsS -X PUT -H "Authorization: Bearer ${API_SECRET}" -H "Content-Type: application/json" \
        -d "{\"path\":\"${MIHOMO_CONF}\"}" "http://127.0.0.1:9090/configs?force=true" >/dev/null 2>&1 || true
    curl -fsS -X POST -H "Authorization: Bearer ${API_SECRET}" \
        "http://127.0.0.1:9090/cache/fakeip/flush" >/dev/null 2>&1 || true
    curl -fsS -X PUT -H "Authorization: Bearer ${API_SECRET}" \
        "http://127.0.0.1:9090/providers/proxies/custom_sub" >/dev/null 2>&1 || true
    curl -fsS -X PUT -H "Authorization: Bearer ${API_SECRET}" \
        "http://127.0.0.1:9090/providers/proxies/my_nodes" >/dev/null 2>&1 || true
    curl -fsS -X PUT -H "Authorization: Bearer ${API_SECRET}" \
        "http://127.0.0.1:9090/providers/proxies/warp_nodes" >/dev/null 2>&1 || true
    curl -fsS -X PUT -H "Authorization: Bearer ${API_SECRET}" \
        "http://127.0.0.1:9090/providers/rules/user_direct_domains" >/dev/null 2>&1 || true
    curl -fsS -X PUT -H "Authorization: Bearer ${API_SECRET}" \
        "http://127.0.0.1:9090/providers/rules/user_proxy_domains" >/dev/null 2>&1 || true
}

# Обработка подписки, одиночных ключей или режима Amnezia WARP
apply_subscription_input() {
    RAW_INPUT="$1"
    mkdir -p "$MIHOMO_PROVIDERS_DIR"
    case "$RAW_INPUT" in
        warp|WARP|amnezia|free)
            echo "proxies: []" > "$CUSTOM_SUB_FILE"
            SUB_URL="file://warp_nodes.yaml (Amnezia WARP)"
            PROVIDER_TYPE="warp"
            ;;
        http://*|https://*)
            SUB_URL="$RAW_INPUT"
            PROVIDER_TYPE="http"
            ;;
        vless://*|vmess://*|ss://*|ssr://*|trojan://*|hy2://*|hysteria2://*|tuic://*|wg://*|wireguard://*|anytls://*|mieru://*|xhttp://*|splithttp://*|socks5://*)
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

# Загрузка и установка веб-панели Mihomo
install_mihomo_ui() {
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
    rm -rf /tmp/mihomo_ui.tar.gz /tmp/mihomo_ui_extract
    mkdir -p /tmp/mihomo_ui_extract

    if download_file "$TARGET_UI_TAR_URL" "/tmp/mihomo_ui.tar.gz" && tar -xzf /tmp/mihomo_ui.tar.gz -C /tmp/mihomo_ui_extract 2>/dev/null; then
        rm -rf /etc/mihomo/ui
        mkdir -p /etc/mihomo/ui
        cp -rf /tmp/mihomo_ui_extract/*/* /etc/mihomo/ui/ 2>/dev/null || cp -rf /tmp/mihomo_ui_extract/* /etc/mihomo/ui/
        echo "$TARGET_UI_TYPE" > "$UI_TYPE_FILE"
        [ -n "$TARGET_UI_VER" ] && echo "$TARGET_UI_VER" > "$UI_VER_FILE"
        LATEST_UI_TAG="$TARGET_UI_VER"
        rm -rf /tmp/mihomo_ui.tar.gz /tmp/mihomo_ui_extract
        echo "[✓] Веб-панель ${TARGET_UI_NAME} ${TARGET_UI_VER} успешно установлена в /etc/mihomo/ui."
    else
        rm -rf /tmp/mihomo_ui.tar.gz /tmp/mihomo_ui_extract
        echo "[X] Ошибка загрузки веб-панели ${TARGET_UI_NAME}!"
        return 1
    fi
}

# Атомарное обновление бинарников Mihomo, AdGuard Home и UI с проверкой валидности
update_cores_only() {
    CHECK_UI_UPDATE="${1:-no}"
    detect_os
    check_github_mirror

    MIHOMO_TAG=$(fetch_latest_github_tag "MetaCubeX/mihomo")
    [ -z "$MIHOMO_TAG" ] && MIHOMO_TAG="v1.19.33"
    LATEST_MIHOMO_TAG="$MIHOMO_TAG"
    INSTALLED_MIHOMO_VER=""
    [ -x /usr/bin/mihomo ] && INSTALLED_MIHOMO_VER=$(/usr/bin/mihomo -v 2>/dev/null | head -n 1 | awk '{print $3}' || true)

    if [ "$INSTALLED_MIHOMO_VER" = "$MIHOMO_TAG" ]; then
        echo "[✓] Ядро Mihomo ${INSTALLED_MIHOMO_VER} (${MIHOMO_ARCH}) актуально."
    else
        echo "Загрузка Mihomo ${MIHOMO_TAG} (${MIHOMO_ARCH})..."
        rm -f /tmp/mihomo.gz /tmp/mihomo.new
        MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_TAG}/mihomo-linux-${MIHOMO_ARCH}-${MIHOMO_TAG}.gz"
        if ! download_file "$MIHOMO_URL" "/tmp/mihomo.gz" && [ "$MIHOMO_ARCH" = "amd64-v3" ]; then
            MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_TAG}/mihomo-linux-amd64-${MIHOMO_TAG}.gz"
            download_file "$MIHOMO_URL" "/tmp/mihomo.gz" || true
        fi
        if [ -f "/tmp/mihomo.gz" ] && gunzip -c /tmp/mihomo.gz > /tmp/mihomo.new 2>/dev/null; then
            chmod +x /tmp/mihomo.new
            if /tmp/mihomo.new -v >/dev/null 2>&1; then
                /etc/init.d/mihomo stop 2>/dev/null || true
                mv -f /tmp/mihomo.new /usr/bin/mihomo
                rm -f /tmp/mihomo.gz
                echo "[✓] Mihomo успешно обновлен до ${MIHOMO_TAG}."
            else
                rm -f /tmp/mihomo.gz /tmp/mihomo.new
                echo "[X] Ошибка: скачанный бинарник Mihomo поврежден, оставлена текущая версия."
            fi
        else
            rm -f /tmp/mihomo.gz /tmp/mihomo.new
            echo "[X] Не удалось скачать Mihomo ${MIHOMO_TAG}."
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
                        echo "[✓] AdGuard Home успешно обновлен до ${AGH_TAG}."
                    else
                        echo "[X] Ошибка проверки AdGuard Home, оставлена текущая версия."
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

        if [ -f /etc/mihomo/ui/index.html ] && [ -n "$UI_TAG" ] && [ "$INSTALLED_UI_VER" = "$UI_TAG" ]; then
            echo "[✓] Веб-панель ${CUR_UI_NAME} ${INSTALLED_UI_VER} актуальна."
        else
            install_mihomo_ui "$CUR_UI_TYPE" "$CUR_UI_NAME" "$CUR_UI_TAR_URL" "$UI_TAG"
        fi
    fi
}

# Сборка правил маршрутизации по локальным IP (DIRECT и Full-VPN)
build_device_ip_rules() {
    BYPASS_RULES_STR=""
    FORCE_PROXY_RULES_STR=""
    if [ -f "$USER_BYPASS_IPS" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            CLEAN_IP=$(printf "%s" "$line" | tr -d ' \t\r\n')
            if [ -n "$CLEAN_IP" ]; then
                case "$CLEAN_IP" in
                    */*) BYPASS_CIDR="$CLEAN_IP" ;;
                    *)   BYPASS_CIDR="${CLEAN_IP}/32" ;;
                esac
                BYPASS_RULES_STR="${BYPASS_RULES_STR}  - SRC-IP-CIDR,${BYPASS_CIDR},DIRECT #DEVICE_IP_RULE\n"
            fi
        done < "$USER_BYPASS_IPS"
    fi
    if [ -f "$USER_FORCE_PROXY_IPS" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            CLEAN_IP=$(printf "%s" "$line" | tr -d ' \t\r\n')
            if [ -n "$CLEAN_IP" ]; then
                case "$CLEAN_IP" in
                    */*) FORCE_CIDR="$CLEAN_IP" ;;
                    *)   FORCE_CIDR="${CLEAN_IP}/32" ;;
                esac
                FORCE_PROXY_RULES_STR="${FORCE_PROXY_RULES_STR}  - SRC-IP-CIDR,${FORCE_CIDR},📺 Устройства (Full-VPN) #DEVICE_IP_RULE\n"
            fi
        done < "$USER_FORCE_PROXY_IPS"
    fi
}

# Пересборка списка SRC-IP-CIDR в config.yaml
sync_device_ips_in_config() {
    [ -f "$MIHOMO_CONF" ] || return 0
    cp -f "$MIHOMO_CONF" "${MIHOMO_CONF}.bak"
    sed -i '/#DEVICE_IP_RULE$/d' "$MIHOMO_CONF"
    sed -i '/- SRC-IP-CIDR,.*,\(DIRECT\|⚡ Авто (Самый быстрый)\|📺 Устройства (Full-VPN)\)/d' "$MIHOMO_CONF"
    build_device_ip_rules

    awk -v bypass="$BYPASS_RULES_STR" -v force="$FORCE_PROXY_RULES_STR" '
        /^  - RULE-SET,private_ip,DIRECT,no-resolve/ {
            print
            if (bypass != "") printf "%s", bypass
            next
        }
        /^  - DST-PORT,6881-6889,/ {
            print
            if (force != "") printf "%s", force
            next
        }
        { print }
    ' "$MIHOMO_CONF" > "${MIHOMO_CONF}.tmp" && mv "${MIHOMO_CONF}.tmp" "$MIHOMO_CONF"

    if /usr/bin/mihomo -d "$MIHOMO_DIR" -t >/dev/null 2>&1; then
        reload_mihomo_api
    else
        mv "${MIHOMO_CONF}.bak" "$MIHOMO_CONF"
        echo "[X] Ошибка синтаксиса IP! Выполнен авто-откат."
    fi
}

# ==============================================================================
# Главный мастер установки и настройки
# ==============================================================================
run_installer() {
    detect_os
    detect_lan_dev
    check_system_memory
    init_user_lists

    echo "========================================================"
    echo "  Установщик шлюза Mihomo + AdGuard Home (OpenWrt 2026) "
    echo "========================================================"
    echo "Система: ${OS_NAME} [${ARCH_RAW} -> ${MIHOMO_ARCH}]"
    echo "Сетевой интерфейс LAN: ${LAN_DEV}"
    if [ "$LOW_RAM_SYSTEM" = "yes" ]; then
        echo "Внимание: Обнаружено < 256MB RAM. Включен zram-swap. Рекомендуется режим 'Только Mihomo'."
    fi
    echo "--------------------------------------------------------"

    SAVED_SUB_URL=""
    SAVED_GW_IP=""
    SAVED_USE_AGH=""
    SAVED_AGH_USER=""
    SAVED_PASS=""
    SAVED_UI_TYPE=""

    if [ -f "$MIHOMO_CONF" ]; then
        SAVED_SUB_URL=$(sed -n '/custom_sub:/,/health-check:/ s/^[[:space:]]*url:[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" | head -n 1 | tr -d ' \t\r\n')
        if [ -z "$SAVED_SUB_URL" ]; then
            if is_warp_enabled; then
                SAVED_SUB_URL="warp"
            elif [ -f "$CUSTOM_SUB_FILE" ]; then
                SAVED_SUB_URL="file://custom_sub.yaml"
            fi
        fi
        SAVED_GW_IP=$(sed -n 's/^[[:space:]]*"+\.lan":[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" | head -n 1 | tr -d ' \t\r\n')
        SAVED_PASS=$(sed -n 's/^secret:[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" | head -n 1 | tr -d '\r\n')
        if grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null; then
            SAVED_USE_AGH="yes"
        else
            SAVED_USE_AGH="no"
        fi
        if grep -qi "zashboard" "$MIHOMO_CONF" 2>/dev/null; then
            SAVED_UI_TYPE="zashboard"
        elif grep -qi "metacubexd" "$MIHOMO_CONF" 2>/dev/null; then
            SAVED_UI_TYPE="metacubexd"
        fi
    fi

    if [ -z "$SAVED_GW_IP" ]; then
        SAVED_GW_IP=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')
    fi

    if [ -f "$AGH_CONF" ]; then
        SAVED_AGH_USER=$(sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "$AGH_CONF" | head -n 1 | tr -d ' \t\r\n"')
    fi

    # 1. Запрос ссылки на подписку, прямого ключа или бесплатного Amnezia WARP
    if [ -n "$SAVED_SUB_URL" ]; then
        printf "Введите подписку, ключ (vless/hy2...) или 'warp' [Enter = оставить %s]: " "$SAVED_SUB_URL"
    else
        printf "Введите подписку (http://...), ключ (vless://...) или 'warp' (бесплатный Amnezia WARP): "
    fi
    read -r INPUT_SUB_URL < /dev/tty || true
    INPUT_SUB_URL=$(printf "%s" "$INPUT_SUB_URL" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [ -n "$INPUT_SUB_URL" ]; then
        RAW_SUB_CHOICE="$INPUT_SUB_URL"
    else
        RAW_SUB_CHOICE="$SAVED_SUB_URL"
    fi

    if [ -z "$RAW_SUB_CHOICE" ]; then
        printf "Подписка не указана. Сгенерировать бесплатный безлимитный Amnezia WARP? (y/n) [Enter = y]: "
        read -r WARP_FALLBACK < /dev/tty || true
        WARP_FALLBACK=$(printf "%s" "$WARP_FALLBACK" | tr -d ' \t\r\n')
        [ -z "$WARP_FALLBACK" ] && WARP_FALLBACK="y"
        case "$WARP_FALLBACK" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа])
                RAW_SUB_CHOICE="warp"
                ;;
            *)
                echo "[X] Ошибка: Требуется подписка, vless/hy2 ключ или Amnezia WARP."
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
    echo "  1) Только AdGuard Home (DNS 0.0.0.0:53 + блок-листы AGH, Mihomo на 1053)"
    echo "  2) Только Mihomo (.mrs списки + SNI, Mihomo берет DNS 0.0.0.0:53, AGH остановлен)"
    echo "  3) Оба: AdGuard Home + Mihomo (двойной щит: DNS AGH + .mrs в Mihomo)"
    echo "  4) Выключить блокировку рекламы (AGH как чистый DNS без фильтрации)"
    DEF_ADB_CHOICE="1"
    [ "$SAVED_USE_AGH" = "no" ] && DEF_ADB_CHOICE="2"
    [ "$LOW_RAM_SYSTEM" = "yes" ] && DEF_ADB_CHOICE="2"
    printf "Ваш выбор (1-4) [Enter = %s]: " "$DEF_ADB_CHOICE"
    read -r INPUT_ADB_CHOICE < /dev/tty || true
    INPUT_ADB_CHOICE=$(printf "%s" "$INPUT_ADB_CHOICE" | tr -d ' \t\r\n')
    [ -z "$INPUT_ADB_CHOICE" ] && INPUT_ADB_CHOICE="$DEF_ADB_CHOICE"

    case "$INPUT_ADB_CHOICE" in
        2)
            USE_AGH="no"
            SELECTED_ADBLOCK="mihomo"
            ADBLOCK_SUMMARY="Только Mihomo (.mrs + SNI, DNS 0.0.0.0:53)"
            DNS_MODE_DESC="Mihomo напрямую (0.0.0.0:53 + DNAT/dns-hijack, AGH остановлен)"
            ;;
        3)
            USE_AGH="yes"
            SELECTED_ADBLOCK="both"
            ADBLOCK_SUMMARY="AdGuard Home + Mihomo (двойной щит)"
            DNS_MODE_DESC="AdGuard Home (0.0.0.0:53 + DNAT) -> Mihomo (127.0.0.1:1053)"
            ;;
        4)
            USE_AGH="yes"
            SELECTED_ADBLOCK="off"
            ADBLOCK_SUMMARY="Выключена (режим отладки)"
            DNS_MODE_DESC="AdGuard Home (0.0.0.0:53 + DNAT) -> Mihomo (127.0.0.1:1053)"
            ;;
        *)
            USE_AGH="yes"
            SELECTED_ADBLOCK="agh"
            ADBLOCK_SUMMARY="Только AdGuard Home (DNS)"
            DNS_MODE_DESC="AdGuard Home (0.0.0.0:53 + DNAT) -> Mihomo (127.0.0.1:1053)"
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
            printf "Введите единый пароль (AdGuard + Mihomo) [Enter = оставить текущий]: "
        else
            printf "Введите единый пароль (для панели AdGuard Home и secret в Mihomo): "
        fi
        read -r INPUT_PASS < /dev/tty || true
        INPUT_PASS=$(printf "%s" "$INPUT_PASS" | tr -d '\r\n')
    else
        AGH_USER="${SAVED_AGH_USER:-admin}"
        if [ -n "$SAVED_PASS" ]; then
            printf "Введите пароль (secret) для Mihomo [Enter = оставить текущий]: "
        else
            printf "Введите пароль (secret) для веб-панели Mihomo: "
        fi
        read -r INPUT_PASS < /dev/tty || true
        INPUT_PASS=$(printf "%s" "$INPUT_PASS" | tr -d '\r\n')
    fi

    ADMIN_PASS="${INPUT_PASS:-$SAVED_PASS}"
    if [ -z "$ADMIN_PASS" ]; then
        echo "[X] Ошибка: Пароль не может быть пустым!"
        exit 1
    fi

    # 5. Выбор веб-панели управления Mihomo
    DEF_UI_CHOICE="1"
    [ "$SAVED_UI_TYPE" = "zashboard" ] && DEF_UI_CHOICE="2"

    echo "Выберите веб-панель для Mihomo:"
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

    # 6. Запрос на автообновление
    DEF_AU_CHAR=$(is_autoupdate_enabled && echo "y" || echo "n")
    printf "Включить автообновление ядер и панелей (каждый день в 04:00)? (y/n) [Enter = %s]: " "$DEF_AU_CHAR"
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
    echo " - Сеть LAN:        ${LAN_DEV}"
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

    # ЭТАП 1: Сеть, TCP BBR, тюнинг буферов и сброс rp_filter
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

    CURRENT_IP=$(uci -q get network.lan.ipaddr || ip -4 addr show "${LAN_DEV}" 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')
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

    REQ_PKGS="ca-certificates curl gzip tar kmod-tun kmod-tcp-bbr kmod-nft-tproxy ip-full conntrack wireguard-tools"
    [ "$USE_AGH" = "yes" ] && REQ_PKGS="$REQ_PKGS apache-utils"
    install_packages "$REQ_PKGS"
    disable_apache_daemon

    modprobe tun 2>/dev/null || true
    modprobe tcp_bbr 2>/dev/null || true
    sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || true
    [ -e /dev/net/tun ] || { mkdir -p /dev/net && mknod /dev/net/tun c 10 200; }

    # Генерация пула Amnezia WARP при выборе бесплатного режима
    if [ "$PROVIDER_TYPE" = "warp" ]; then
        generate_amnezia_warp || true
    fi

    # ЭТАП 2: Загрузка/обновление ядер Mihomo и AdGuard Home
    update_cores_only "no"

    # ЭТАП 3: Генерация конфигурации Mihomo
    /etc/init.d/mihomo stop 2>/dev/null || true

    if [ "$PROVIDER_TYPE" = "http" ] && [ -n "$SAVED_SUB_URL" ] && [ "$SUB_URL" != "$SAVED_SUB_URL" ]; then
        rm -f "$CUSTOM_SUB_FILE" 2>/dev/null || true
    fi

    INSTALLED_UI_TYPE=""
    [ -f "$UI_TYPE_FILE" ] && INSTALLED_UI_TYPE=$(cat "$UI_TYPE_FILE" 2>/dev/null | tr -d ' \t\r\n')

    if [ "$INSTALLED_UI_TYPE" != "$UI_TYPE" ] || [ ! -f /etc/mihomo/ui/index.html ]; then
        install_mihomo_ui "$UI_TYPE" "$UI_NAME" "$UI_TAR_URL"
    else
        echo "[✓] Веб-панель ${UI_NAME} уже установлена."
    fi

    if [ "$USE_AGH" = "yes" ]; then
        MIHOMO_DNS_LISTEN="127.0.0.1:1053"
        HIJACK_PRE="#"
    else
        MIHOMO_DNS_LISTEN="0.0.0.0:53"
        HIJACK_PRE=""
    fi

    if [ "$SELECTED_ADBLOCK" = "mihomo" ] || [ "$SELECTED_ADBLOCK" = "both" ]; then
        ADB_PRE=""
    else
        ADB_PRE="#"
    fi

    if [ "$PROVIDER_TYPE" = "file" ] || [ "$PROVIDER_TYPE" = "warp" ]; then
        [ -s "$CUSTOM_SUB_FILE" ] || echo "proxies: []" > "$CUSTOM_SUB_FILE"
        CUSTOM_SUB_BLOCK="  custom_sub:\n    type: file\n    path: ./proxy_providers/custom_sub.yaml"
    else
        CUSTOM_SUB_BLOCK="  custom_sub:\n    type: http\n    url: \"${SUB_URL}\"\n    path: ./proxy_providers/custom_sub.yaml\n    interval: 86400\n    exclude-filter: \"${SUB_FILTER_REGEX}\""
    fi

    build_device_ip_rules
    [ -f "$MIHOMO_CONF" ] && cp -f "$MIHOMO_CONF" "${MIHOMO_CONF}.bak"

    cat << CONFIG_EOF > "$MIHOMO_CONF"
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: rule
log-level: warning
ipv6: false
unified-delay: true
tcp-concurrent: true
global-client-fingerprint: chrome
keep-alive-interval: 15
keep-alive-idle: 600
disable-keep-alive: false
find-process-mode: off
geodata-mode: false
geodata-loader: memconservative
geo-auto-update: true
geo-update-interval: 24
geox-url:
  mmdb: "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country-lite.mmdb"
  asn: "${GH_PROXY}https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb"
external-controller: 0.0.0.0:9090
secret: "${ADMIN_PASS}"
external-ui: ui
external-ui-url: "${GH_PROXY}${UI_URL}"
profile:
  store-selected: true
  store-fake-ip: true
tun:
  enable: true
  stack: mixed
  device: mihomo-tun
  auto-route: true
  auto-detect-interface: true
  auto-redirect: true
  strict-route: true
  endpoint-independent-nat: true
  gso: true
  gso-max-size: 65536
  udp-timeout: 300
${HIJACK_PRE}  dns-hijack: #DNS_HIJACK
${HIJACK_PRE}    - "any:53" #DNS_HIJACK
${HIJACK_PRE}    - "tcp://any:53" #DNS_HIJACK
sniffer:
  enable: true
  force-dns-mapping: true
  parse-pure-ip: true
  override-destination: false
  sniff:
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
  skip-domain:
    - "Mijia Cloud"
    - "+.lan"
    - "+.local"
    - "+.home.arpa"
    - "+.internal"
    - "+.push.apple.com"
    - "+.mtalk.google.com"
    - "+.courier.push.apple.com"
    - "+.tailscale.com"
dns:
  enable: true
  listen: ${MIHOMO_DNS_LISTEN}
  ipv6: false
  prefer-h3: false
  cache-algorithm: arc
  use-hosts: true
  use-system-hosts: true
  respect-rules: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter-mode: blacklist
  fake-ip-filter:
    - "+.lan"
    - "+.local"
    - "+.home.arpa"
    - "+.internal"
    - "+.localdomain"
    - "localhost"
    - "+.localhost"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "+.xboxlive.com"
    - "xbox.*.microsoft.com"
    - "+.battlenet.com.cn"
    - "+.stun.*.*"
    - "+.stun.*.*.*"
    - "+.stun.playstation.net"
    - "+.srv.nintendo.net"
    - "+.steamcontent.com"
    - "+.push.apple.com"
    - "+.courier.push.apple.com"
    - "time.*.apple.com"
    - "+.tailscale.com"
    - "rule-set:private_domain"
    - "rule-set:ntp_domain"
    - "rule-set:stun_domain"
    - "rule-set:torrent_domain"
    - "rule-set:user_direct_domains"
    - "rule-set:ru_domain"
    - "+.market.xiaomi.com"
    - "+.connectivitycheck.gstatic.com"
    - "+.connectivitycheck.android.com"
    - "+.captive.apple.com"
  default-nameserver:
    - 77.88.8.8
    - 77.88.8.1
  nameserver: &proxy_dns
    - "https://cloudflare-dns.com/dns-query#⚡ Авто (Самый быстрый)"
    - "https://dns.google/dns-query#⚡ Авто (Самый быстрый)"
    - "https://dns.quad9.net/dns-query#⚡ Авто (Самый быстрый)"
  nameserver-policy:
    "rule-set:private_domain": "${GW_IP}"
    "+.lan": "${GW_IP}"
    "+.local": "${GW_IP}"
    "+.home.arpa": "${GW_IP}"
    "+.internal": "${GW_IP}"
    "+.localdomain": "${GW_IP}"
    "+.in-addr.arpa": "${GW_IP}"
    "rule-set:user_proxy_domains": *proxy_dns
    "rule-set:inside_ru_blocked": *proxy_dns
    "rule-set:refilter_domain": *proxy_dns
    "rule-set:ru_media_blocked": *proxy_dns
    "rule-set:ntp_domain": &ru_bootstrap_dns
      - "https://common.dot.dns.yandex.net/dns-query#DIRECT"
      - "tls://common.dot.dns.yandex.net#DIRECT"
      - 77.88.8.8
      - 77.88.8.1
    "+.connectivitycheck.gstatic.com": *ru_bootstrap_dns
    "+.connectivitycheck.android.com": *ru_bootstrap_dns
    "+.msftconnecttest.com": *ru_bootstrap_dns
    "+.msftncsi.com": *ru_bootstrap_dns
    "+.captive.apple.com": *ru_bootstrap_dns
    "rule-set:user_direct_domains": *ru_bootstrap_dns
    "rule-set:ru_domain": *ru_bootstrap_dns
  proxy-server-nameserver:
    - "https://common.dot.dns.yandex.net/dns-query#DIRECT"
    - "tls://common.dot.dns.yandex.net#DIRECT"
    - 77.88.8.8
    - 77.88.8.1
  direct-nameserver:
    - "https://common.dot.dns.yandex.net/dns-query#DIRECT"
    - "tls://common.dot.dns.yandex.net#DIRECT"
    - 77.88.8.8
    - 77.88.8.1
  direct-nameserver-follow-policy: true
proxy-providers:
$(printf '%b' "$CUSTOM_SUB_BLOCK")
    health-check: &hc_default
      enable: true
      url: "https://www.gstatic.com/generate_204"
      interval: 180
      timeout: 5000
      lazy: true
      expected-status: 204
    override:
      udp: true
      client-fingerprint: chrome
  warp_nodes:
    type: file
    path: ./proxy_providers/warp_nodes.yaml
    health-check: *hc_default
    override:
      udp: true
  my_nodes:
    type: file
    path: ./proxy_providers/my_nodes.yaml
    health-check: *hc_default
    override:
      udp: true
      client-fingerprint: chrome
proxy-groups:
  - name: "⚡ Авто (Самый быстрый)"
    type: url-test
    use: [custom_sub, my_nodes, warp_nodes]
    url: "https://www.gstatic.com/generate_204"
    interval: 180
    tolerance: 35
    timeout: 5000
    lazy: true
    expected-status: 204
  - name: "🛡️ Авто-резерв (Fallback)"
    type: fallback
    use: [custom_sub, my_nodes, warp_nodes]
    url: "https://www.gstatic.com/generate_204"
    interval: 180
    timeout: 5000
    lazy: true
    expected-status: 204
  - name: "🔓 Обход блокировок"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)", "🐟 Прочий трафик", DIRECT]
    use: [custom_sub, my_nodes, warp_nodes]
  - name: "☁️ Cloudflare & CDN"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)", "🔓 Обход блокировок", DIRECT]
    use: [custom_sub, my_nodes, warp_nodes]
  - name: "▶️ YouTube"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)"]
    use: [custom_sub, my_nodes, warp_nodes]
  - name: "🤖 Нейросети (AI)"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)"]
    use: [custom_sub, my_nodes, warp_nodes]
    exclude-filter: "(?i)^☁️ WARP"
  - name: "👾 Discord & Игры"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)", DIRECT]
    use: [custom_sub, my_nodes, warp_nodes]
  - name: "💬 Мессенджеры & Связь"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)", DIRECT]
    use: [custom_sub, my_nodes, warp_nodes]
  - name: "🎵 Spotify"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)", DIRECT]
    use: [custom_sub, my_nodes, warp_nodes]
    exclude-filter: "(?i)^☁️ WARP"
  - name: "📺 Устройства (Full-VPN)"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)", "🔓 Обход блокировок", DIRECT]
    use: [custom_sub, my_nodes, warp_nodes]
  - name: "🧲 Торренты"
    type: select
    proxies: [DIRECT, "⚡ Авто (Самый быстрый)", REJECT]
    use: [custom_sub, my_nodes, warp_nodes]
${ADB_PRE}  - name: "🛑 Реклама" #ADBLOCK_MIHOMO
${ADB_PRE}    type: select #ADBLOCK_MIHOMO
${ADB_PRE}    proxies: [REJECT, REJECT-DROP, DIRECT] #ADBLOCK_MIHOMO
  - name: "🇷🇺 Россия"
    type: select
    proxies: [DIRECT, "⚡ Авто (Самый быстрый)"]
  - name: "🐟 Прочий трафик"
    type: select
    proxies: ["⚡ Авто (Самый быстрый)", "🛡️ Авто-резерв (Fallback)", DIRECT]
    use: [custom_sub, my_nodes, warp_nodes]
rule-providers:
  user_direct_domains:
    type: file
    behavior: domain
    format: text
    path: ./rule_sets/user_direct_domains.list
  user_proxy_domains:
    type: file
    behavior: domain
    format: text
    path: ./rule_sets/user_proxy_domains.list
  private_domain: &mrs_domain
    type: http
    behavior: domain
    format: mrs
    interval: 86400
    path: ./rule_sets/private_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/private.mrs"
  private_ip: &mrs_ip
    type: http
    behavior: ipcidr
    format: mrs
    interval: 86400
    path: ./rule_sets/private_ip.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/private.mrs"
  ntp_domain:
    <<: *mrs_domain
    path: ./rule_sets/category-ntp.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ntp.mrs"
  stun_domain:
    <<: *mrs_domain
    path: ./rule_sets/category-stun.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-stun.mrs"
${ADB_PRE}  ads_domain: #ADBLOCK_MIHOMO
${ADB_PRE}    <<: *mrs_domain #ADBLOCK_MIHOMO
${ADB_PRE}    path: ./rule_sets/category-ads-all.mrs #ADBLOCK_MIHOMO
${ADB_PRE}    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ads-all.mrs" #ADBLOCK_MIHOMO
${ADB_PRE}  telemetry_domain: #ADBLOCK_MIHOMO
${ADB_PRE}    <<: *mrs_domain #ADBLOCK_MIHOMO
${ADB_PRE}    path: ./rule_sets/category-telemetry.mrs #ADBLOCK_MIHOMO
${ADB_PRE}    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-telemetry.mrs" #ADBLOCK_MIHOMO
  ai_domain:
    <<: *mrs_domain
    path: ./rule_sets/category-ai-!cn.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ai-!cn.mrs"
  spotify_domain:
    <<: *mrs_domain
    path: ./rule_sets/spotify_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/spotify.mrs"
  torrent_domain:
    <<: *mrs_domain
    path: ./rule_sets/tracker.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/tracker.mrs"
  youtube_domain:
    <<: *mrs_domain
    path: ./rule_sets/youtube_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/youtube.mrs"
  roblox_domain:
    <<: *mrs_domain
    path: ./rule_sets/roblox_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/roblox.mrs"
  discord_domain:
    <<: *mrs_domain
    path: ./rule_sets/discord_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/discord.mrs"
  discord_voice_ip:
    <<: *mrs_ip
    path: ./rule_sets/discord_voice_ip.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/other/discord-voice-ip-list.mrs"
  communication_domain:
    <<: *mrs_domain
    path: ./rule_sets/communication_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-communication.mrs"
  telegram_ip:
    <<: *mrs_ip
    path: ./rule_sets/telegram_ip.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/telegram.mrs"
  cloudflare_domain:
    <<: *mrs_domain
    path: ./rule_sets/cloudflare_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cloudflare.mrs"
  cloudflare_ip:
    <<: *mrs_ip
    path: ./rule_sets/cloudflare_ip.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cloudflare.mrs"
  refilter_domain:
    <<: *mrs_domain
    path: ./rule_sets/refilter_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/re-filter/domain-rule.mrs"
  refilter_ip:
    <<: *mrs_ip
    path: ./rule_sets/refilter_ip.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/re-filter/ip-rule.mrs"
  inside_ru_blocked:
    <<: *mrs_domain
    path: ./rule_sets/inside_ru_blocked.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/ru-bundle/itdoginfo-inside-russia.mrs"
  ru_media_blocked:
    <<: *mrs_domain
    path: ./rule_sets/category-media-ru-blocked.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-media-ru-blocked.mrs"
  ru_domain:
    <<: *mrs_domain
    path: ./rule_sets/ru_domain.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ru.mrs"
  ru_ip:
    <<: *mrs_ip
    path: ./rule_sets/ru_ip.mrs
    url: "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/ru.mrs"
rules:
  - RULE-SET,private_domain,DIRECT
  - RULE-SET,private_ip,DIRECT,no-resolve
$(printf '%b' "$BYPASS_RULES_STR")
  - RULE-SET,user_direct_domains,DIRECT
  - RULE-SET,user_proxy_domains,🔓 Обход блокировок
  - DST-PORT,853,REJECT
  - DST-PORT,123,DIRECT
  - RULE-SET,ntp_domain,DIRECT
${ADB_PRE}  - RULE-SET,ads_domain,🛑 Реклама #ADBLOCK_MIHOMO
${ADB_PRE}  - RULE-SET,telemetry_domain,🛑 Реклама #ADBLOCK_MIHOMO
  - RULE-SET,torrent_domain,🧲 Торренты
  - DST-PORT,6881-6889,🧲 Торренты
$(printf '%b' "$FORCE_PROXY_RULES_STR")
  - RULE-SET,ai_domain,🤖 Нейросети (AI)
  - RULE-SET,spotify_domain,🎵 Spotify
  - AND,((RULE-SET,youtube_domain),(NETWORK,udp),(DST-PORT,443)),REJECT
  - RULE-SET,youtube_domain,▶️ YouTube
  - RULE-SET,roblox_domain,👾 Discord & Игры
  - RULE-SET,discord_domain,👾 Discord & Игры
  - RULE-SET,discord_voice_ip,👾 Discord & Игры,no-resolve
  - RULE-SET,stun_domain,💬 Мессенджеры & Связь
  - RULE-SET,communication_domain,💬 Мессенджеры & Связь
  - RULE-SET,telegram_ip,💬 Мессенджеры & Связь,no-resolve
  - RULE-SET,inside_ru_blocked,🔓 Обход блокировок
  - RULE-SET,refilter_domain,🔓 Обход блокировок
  - RULE-SET,ru_media_blocked,🔓 Обход блокировок
  - RULE-SET,refilter_ip,🔓 Обход блокировок,no-resolve
  - RULE-SET,cloudflare_domain,☁️ Cloudflare & CDN
  - RULE-SET,cloudflare_ip,☁️ Cloudflare & CDN,no-resolve
  - RULE-SET,ru_domain,🇷🇺 Россия
  - RULE-SET,ru_ip,🇷🇺 Россия,no-resolve
  - AND,((NETWORK,udp),(DST-PORT,50000-50100)),👾 Discord & Игры
  - AND,((NETWORK,udp),(DST-PORT,3478)),💬 Мессенджеры & Связь
  - AND,((NETWORK,udp),(DST-PORT,5349)),💬 Мессенджеры & Связь
  - AND,((NETWORK,udp),(DST-PORT,19302)),💬 Мессенджеры & Связь
  - AND,((NETWORK,udp),(DST-PORT,50101-65535)),💬 Мессенджеры & Связь
  - MATCH,🐟 Прочий трафик
CONFIG_EOF

    # ЭТАП 4: Настройка AdGuard Home
    if [ "$USE_AGH" = "yes" ]; then
        echo "Генерация bcrypt-хэша пароля..."
        AGH_PASS_HASH=""
        if command -v htpasswd >/dev/null 2>&1; then
            AGH_PASS_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
            [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH=$(htpasswd -nbBC 10 "$AGH_USER" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        fi
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
            echo "[✓] AdGuardHome.yaml обновлен (фильтры сохранены, aaaa_disabled: true активен)."
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
        /etc/init.d/adguardhome stop 2>/dev/null || true
        /etc/init.d/adguardhome disable 2>/dev/null || true
    fi

    # ЭТАП 5: Регистрация служб procd
    cat << 'INIT_MIHOMO' > /etc/init.d/mihomo
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/mihomo -d /etc/mihomo
    procd_set_param file /etc/mihomo/config.yaml
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_set_param limits nofile="65535 65535"
    procd_close_instance
}
INIT_MIHOMO
    chmod +x /etc/init.d/mihomo
    /etc/init.d/mihomo enable 2>/dev/null || true
    /etc/init.d/mihomo restart 2>/dev/null || /etc/init.d/mihomo start 2>/dev/null || true

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
    echo " - Сеть LAN:           ${LAN_DEV}"
    echo " - Основной роутер:    ${GW_IP}"
    echo " - Антиреклама:        ${ADBLOCK_SUMMARY}"
    echo " - Панель Mihomo:      http://${CURRENT_IP}:9090/ui [${UI_NAME}] (пароль: ${ADMIN_PASS})"
    if [ "$USE_AGH" = "yes" ]; then
        echo " - Панель AdGuard:     http://${CURRENT_IP}:3000 (логин: ${AGH_USER} / пароль: ${ADMIN_PASS})"
    fi
    echo " - Вызов меню шлюза:   gateway"
    echo "========================================================"
}

# Расширенная диагностика шлюза и проверка на утечки (Self-Test + Anti-Leak)
run_self_test() {
    echo "=== [Self-Test] Диагностика прозрачного шлюза и Anti-Leak ==="
    WAIT_CNT=0
    while [ "$WAIT_CNT" -lt 12 ]; do
        if pgrep mihomo >/dev/null 2>&1 && ip link show mihomo-tun >/dev/null 2>&1; then
            break
        fi
        sleep 1
        WAIT_CNT=$((WAIT_CNT + 1))
    done

    if pgrep mihomo >/dev/null 2>&1; then
        echo "[✓] Служба Mihomo: ЗАПУЩЕНА"
    else
        echo "[X] Служба Mihomo: ОСТАНОВЛЕНА"
    fi

    if pgrep AdGuardHome >/dev/null 2>&1; then
        echo "[✓] Служба AdGuard Home: ЗАПУЩЕНА"
    else
        echo "[i] Служба AdGuard Home: ОСТАНОВЛЕНА (DNS обрабатывает Mihomo)"
    fi

    if is_warp_enabled; then
        echo "[✓] Пул Amnezia WARP: АКТИВЕН (8 нод Cloudflare AWG 2.0 + EU)"
    fi

    detect_adblock_mode
    echo "[✓] Режим антирекламы: ${ADBLOCK_STAT} ${ADBLOCK_DESC}"

    if ip link show mihomo-tun >/dev/null 2>&1; then
        echo "[✓] TUN-интерфейс (mihomo-tun): АКТИВЕН"
    else
        echo "[X] TUN-интерфейс (mihomo-tun): НЕ НАЙДЕН"
    fi

    RP_STAT=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "unknown")
    BBR_STAT=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    echo "[✓] Сетевой стек: TCP ${BBR_STAT} | rp_filter=${RP_STAT} (Sidecar OK)"

    if is_killswitch_enabled; then
        echo "[✓] Защита от утечек (Kill-Switch): АКТИВНА (строгий запрет обхода TUN на ${LAN_DEV})"
    else
        echo "[✓] Защита от утечек: IPv6 Drop + DoT/DoQ 853 Reject + DNS 53 Redirect активны (${LAN_DEV})"
    fi

    if [ -f "$MIHOMO_CONF" ] && pgrep mihomo >/dev/null 2>&1; then
        SECRET=$(sed -n 's/^secret:[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" | head -n 1 | tr -d '\r\n')
        ACTIVE_NODE=$(curl -fsS --connect-timeout 3 -H "Authorization: Bearer ${SECRET}" "http://127.0.0.1:9090/proxies" 2>/dev/null | sed -n 's/.*"⚡ Авто (Самый быстрый)".*"now":"\([^"]*\)".*/\1/p' | head -n 1)
        [ -n "$ACTIVE_NODE" ] && echo "[✓] Активная нода (Авто): ${ACTIVE_NODE}"
        CF_TRACE=$(curl -fsS --connect-timeout 4 -x http://127.0.0.1:7890 "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null | grep -E '^(ip|loc|warp|colo)=' | tr '\n' ' ' || true)
        if [ -n "$CF_TRACE" ]; then
            echo "[✓] Внешний выход через туннель (Cloudflare Trace): ${CF_TRACE}"
        else
            echo "[!] Туннель еще прогревается или подписка недоступна."
        fi
    fi
}

# ==============================================================================
# Интерактивное меню управления (OpenWrt)
# ==============================================================================
show_menu() {
    detect_os
    detect_lan_dev
    init_user_lists
    ensure_mihomo_config_tags
    ensure_sysupgrade_persistence
    refresh_remote_versions
    while true; do
        clear
        echo "========================================================"
        echo "     Панель управления шлюзом (OpenWrt Unified Core)    "
        echo "========================================================"
        print_gateway_header
        echo "--------------------------------------------------------"
        echo " 1) Статус служб и глубокий тест на утечки (Self-Test)"
        echo " 2) Подписка, личные ключи и бесплатный Amnezia WARP"
        echo " 3) Обновить ядра Mihomo, AdGuard Home и веб-панель"
        echo " 4) Перезапустить службы + сброс conntrack и Fake-IP кэша"
        echo " 5) Посмотреть живые логи Mihomo (logread)"
        echo " 6) Полная перенастройка шлюза (Мастер установки)"
        echo " 7) Сменить веб-панель Mihomo (MetaCubeXD / Zashboard)"
        echo " 8) Свои домены: добавить/очистить (В прокси / Напрямую)"
        echo " 9) Маршрутизация устройств по IP (Обход DIRECT / Full-VPN)"
        echo " 10) Режим паузы / Бэкап и восстановление настроек"
        echo " 11) Автообновление ядер и панелей (04:00 ежедневно)"
        echo " 12) Блокировка рекламы и DNS: переключить (AGH / Mihomo / Оба / Выкл)"
        echo " 13) Аппаратный Kill-Switch (защита от утечек при падении Mihomo)"
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
                echo "=== Управление подпиской, ключами и Amnezia WARP ==="
                echo " 1) Заменить основную подписку (http://...), основной ключ или 'warp'"
                echo " 2) Добавить дополнительный личный ключ (vless/hy2/ss/tuic/anytls) в пул my_nodes"
                echo " 3) Очистить дополнительные личные ключи (${CUSTOM_NODES_FILE})"
                echo " 4) Сгенерировать / обновить БЕСПЛАТНЫЙ Amnezia WARP (8 нод: Cloudflare AWG 2.0 + Европа)"
                echo " 5) Отключить / очистить ноды Amnezia WARP (${WARP_NODES_FILE})"
                echo " 0) Назад"
                printf "Выбор [0-5]: "
                read -r SUB_ACT < /dev/tty || true
                case "$SUB_ACT" in
                    1)
                        printf "Введите новую ссылку (http://...), прямой ключ (vless/hy2...) или 'warp': "
                        read -r NEW_SUB < /dev/tty || true
                        NEW_SUB=$(printf "%s" "$NEW_SUB" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        if [ -n "$NEW_SUB" ] && [ -f "$MIHOMO_CONF" ]; then
                            cp -f "$MIHOMO_CONF" "${MIHOMO_CONF}.bak"
                            apply_subscription_input "$NEW_SUB"
                            if [ "$PROVIDER_TYPE" = "warp" ]; then
                                generate_amnezia_warp || true
                            fi
                            if [ "$PROVIDER_TYPE" = "file" ] || [ "$PROVIDER_TYPE" = "warp" ]; then
                                awk '
                                    /^  custom_sub:/ {
                                        print "  custom_sub:"
                                        print "    type: file"
                                        print "    path: ./proxy_providers/custom_sub.yaml"
                                        in_sub=1; next
                                    }
                                    in_sub && /^    health-check:/ { in_sub=0 }
                                    in_sub { next }
                                    { print }
                                ' "$MIHOMO_CONF" > "${MIHOMO_CONF}.tmp" && mv "${MIHOMO_CONF}.tmp" "$MIHOMO_CONF"
                            else
                                rm -f "$CUSTOM_SUB_FILE" 2>/dev/null || true
                                awk -v url="$SUB_URL" -v flt="$SUB_FILTER_REGEX" '
                                    /^  custom_sub:/ {
                                        print "  custom_sub:"
                                        print "    type: http"
                                        print "    url: \"" url "\""
                                        print "    path: ./proxy_providers/custom_sub.yaml"
                                        print "    interval: 86400"
                                        print "    exclude-filter: \"" flt "\""
                                        in_sub=1; next
                                    }
                                    in_sub && /^    health-check:/ { in_sub=0 }
                                    in_sub { next }
                                    { print }
                                ' "$MIHOMO_CONF" > "${MIHOMO_CONF}.tmp" && mv "${MIHOMO_CONF}.tmp" "$MIHOMO_CONF"
                            fi
                            reload_mihomo_api
                            echo "[✓] Основной источник прокси успешно обновлен на лету!"
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
                            reload_mihomo_api
                            echo "[✓] Ключ добавлен в пул my_nodes и подключен к автовыбору!"
                        fi
                        sleep 2
                        ;;
                    3)
                        echo "proxies: []" > "$CUSTOM_NODES_FILE"
                        reload_mihomo_api
                        echo "[✓] Дополнительные личные ключи очищены."
                        sleep 2
                        ;;
                    4)
                        if generate_amnezia_warp; then
                            ensure_mihomo_config_tags
                            reload_mihomo_api
                            echo "[✓] 8 нод Amnezia WARP подключены ко всем группам в веб-панели!"
                        fi
                        sleep 3
                        ;;
                    5)
                        echo "proxies: []" > "$WARP_NODES_FILE"
                        reload_mihomo_api
                        echo "[✓] Пул нод Amnezia WARP отключен и очищен."
                        sleep 2
                        ;;
                esac
                ;;
            3)
                echo "Проверка и тихое обновление ядер и веб-панели..."
                update_cores_only "yes"
                /etc/init.d/mihomo restart 2>/dev/null || true
                if grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null && [ -x /usr/bin/AdGuardHome ]; then
                    /etc/init.d/adguardhome restart 2>/dev/null || true
                fi
                refresh_remote_versions
                printf "\nНажмите Enter для возврата в меню..."
                read -r _ < /dev/tty
                ;;
            4)
                echo "Проверка синтаксиса конфигурации Mihomo..."
                if /usr/bin/mihomo -d "$MIHOMO_DIR" -t; then
                    reload_mihomo_api
                    conntrack -F >/dev/null 2>&1 || true
                    /etc/init.d/mihomo restart 2>/dev/null || true
                    if grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null; then
                        /etc/init.d/adguardhome restart 2>/dev/null || true
                    fi
                    echo "[✓] Кэш Fake-IP и таблица conntrack очищены, службы успешно перезапущены."
                else
                    echo "[X] Конфигурация повреждена! Проверьте ошибки выше."
                fi
                sleep 2
                ;;
            5)
                echo "=== Последние записи лога Mihomo ==="
                if command -v logread >/dev/null 2>&1; then
                    logread -e mihomo | tail -n 45
                else
                    /usr/bin/mihomo -d "$MIHOMO_DIR" -t
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
                if [ ! -f "$MIHOMO_CONF" ]; then
                    echo "[X] Конфигурация не найдена. Запустите пункт 6."
                    sleep 2
                    continue
                fi
                check_github_mirror
                echo "Выберите веб-панель Mihomo:"
                echo " 1) MetaCubeXD"
                echo " 2) Zashboard"
                printf "Ваш выбор [1-2]: "
                read -r UI_SEL < /dev/tty || true
                case "$UI_SEL" in
                    2)
                        NEW_UI_TYPE="zashboard"
                        NEW_UI_NAME="Zashboard"
                        NEW_UI_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
                        NEW_UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
                        ;;
                    1)
                        NEW_UI_TYPE="metacubexd"
                        NEW_UI_NAME="MetaCubeXD"
                        NEW_UI_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
                        NEW_UI_TAR_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.tar.gz"
                        ;;
                    *)
                        continue
                        ;;
                esac
                sed -i "s|^external-ui-url:.*|external-ui-url: \"${GH_PROXY}${NEW_UI_URL}\"|" "$MIHOMO_CONF"
                install_mihomo_ui "$NEW_UI_TYPE" "$NEW_UI_NAME" "$NEW_UI_TAR_URL"
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
                            reload_mihomo_api
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
                            reload_mihomo_api
                            echo "[✓] Добавлено напрямую: $D_IN"
                        fi
                        sleep 2
                        ;;
                    3)
                        echo "+.localdomain" > "$USER_DIRECT_FILE"
                        echo "+.chatgpt.com" > "$USER_PROXY_FILE"
                        reload_mihomo_api
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
                            sync_device_ips_in_config
                            conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            echo "[✓] Устройство ${IP_IN} теперь идет мимо прокси (DIRECT)."
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
                            sync_device_ips_in_config
                            conntrack -D -s "$IP_IN" >/dev/null 2>&1 || true
                            echo "[✓] Трафик устройства ${IP_IN} направлен в группу '📺 Устройства (Full-VPN)'."
                        fi
                        sleep 2
                        ;;
                    3)
                        : > "$USER_BYPASS_IPS"
                        : > "$USER_FORCE_PROXY_IPS"
                        sync_device_ips_in_config
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
                SECRET=$(sed -n 's/^secret:[[:space:]]*"\([^"]*\)".*/\1/p' "$MIHOMO_CONF" 2>/dev/null | head -n 1 | tr -d '\r\n')
                case "$SRV_ACT" in
                    1)
                        curl -fsS -X PATCH -H "Authorization: Bearer ${SECRET}" -H "Content-Type: application/json" \
                            -d '{"mode":"direct"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                        echo "[✓] Шлюз переведен в режим паузы (весь трафик идет напрямую в DIRECT)."
                        sleep 2
                        ;;
                    2)
                        curl -fsS -X PATCH -H "Authorization: Bearer ${SECRET}" -H "Content-Type: application/json" \
                            -d '{"mode":"rule"}' "http://127.0.0.1:9090/configs" >/dev/null 2>&1 || true
                        echo "[✓] Режим маршрутизации по правилам (rule) восстановлен."
                        sleep 2
                        ;;
                    3)
                        tar -czf "$BACKUP_ARCHIVE" /etc/mihomo /etc/AdGuardHome/AdGuardHome.yaml 2>/dev/null || \
                        tar -czf "$BACKUP_ARCHIVE" /etc/mihomo 2>/dev/null
                        echo "[✓] Архив сохранен в ${BACKUP_ARCHIVE}"
                        sleep 2
                        ;;
                    4)
                        if [ -f "$BACKUP_ARCHIVE" ]; then
                            tar -xzf "$BACKUP_ARCHIVE" -C /
                            /etc/init.d/mihomo restart 2>/dev/null || true
                            if grep -q "listen: 127.0.0.1:1053" "$MIHOMO_CONF" 2>/dev/null; then
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
                echo "=== Автообновление Mihomo, AdGuard Home и веб-панелей ==="
                if is_autoupdate_enabled; then
                    echo " Текущий статус: ВКЛЮЧЕНО (каждый день в 04:00)"
                else
                    echo " Текущий статус: ВЫКЛЮЧЕНО"
                fi
                echo "--------------------------------------------------------"
                echo " 1) Включить (поставил и забыл — автоматически обновляет ядра в 04:00)"
                echo " 2) Выключить (обновлять только вручную через пункт 3)"
                echo " 3) Посмотреть лог последнего автообновления (${AUTOUPDATE_LOG})"
                echo " 0) Назад"
                printf "Выбор: "
                read -r AU_ACT < /dev/tty || true
                case "$AU_ACT" in
                    1)
                        enable_autoupdate
                        echo "[✓] Автообновление включено (ежедневно в 04:00)."
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
                echo " 1) Только AdGuard Home (DNS 0.0.0.0:53 + фильтрация AGH, Mihomo на 1053)"
                echo " 2) Только Mihomo (.mrs списки + SNI, AGH останавливается, DNS 0.0.0.0:53 берет Mihomo)"
                echo " 3) Оба: AdGuard Home + Mihomo (двойной щит: DNS AGH + .mrs/SNI в Mihomo)"
                echo " 4) Выключить блокировку рекламы (режим отладки)"
                echo " 0) Назад"
                printf "Выбор [0-4]: "
                read -r ADB_ACT < /dev/tty || true
                case "$ADB_ACT" in
                    1) apply_adblock_mode "agh";    sleep 2 ;;
                    2) apply_adblock_mode "mihomo"; sleep 2 ;;
                    3) apply_adblock_mode "both";   sleep 2 ;;
                    4) apply_adblock_mode "off";    sleep 2 ;;
                esac
                ;;
            13)
                echo "=== Аппаратный Kill-Switch (fw4 / nftables) ==="
                echo "Блокирует любую прямую маршрутизацию из ${LAN_DEV} в основной роутер в обход mihomo-tun."
                echo "Если служба Mihomo упадет, клиенты гарантированно не «светят» реальный российский IP провайдера."
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

# ==============================================================================
# Маршрутизация аргументов командной строки
# ==============================================================================
if [ "${1:-}" = "autoupdate" ]; then
    run_autoupdate
elif [ ! -f "$MIHOMO_CONF" ] || [ "${1:-}" = "install" ]; then
    run_installer
else
    show_menu
fi
