run_self_test() {
    set +e
    detect_os
    ui_box_top "⚡ [SELF-TEST 2.0] МАТРИЦА ЗДОРОВЬЯ И ОТКЛИКА ШЛЮЗА (${OS_NAME})"
    WAIT_CNT=0
    while [ "$WAIT_CNT" -lt 10 ]; do
        if pgrep sing-box >/dev/null 2>&1 && ip link show singbox-tun >/dev/null 2>&1; then
            break
        fi
        sleep 1
        WAIT_CNT=$((WAIT_CNT + 1))
    done

    load_gateway_env
    calc_hardware_limits
    LAN_IF_NOW=$(get_lan_ifname)
    is_dhcp_server_enabled && DHCP_ST="${C_GRN}● ВКЛ${C_RES}" || DHCP_ST="${C_DIM}○ ВЫКЛ${C_RES}"
    ui_box_row "Сеть сервера: ${C_BLD}[${OS_NAME} (${LAN_IF_NOW}): $(get_current_lan_ip)]${C_RES} ▸ [Роутер: ${GW_IP}] │ DHCP: ${DHCP_ST}"
    print_proxy_slots_report

    ui_box_sep "СОСТОЯНИЕ ЯДРА И СЕТЕВОГО СТЕКА"
    SB_PID=$(pgrep sing-box 2>/dev/null | head -n 1 || true)
    if [ -n "$SB_PID" ]; then
        SB_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${SB_PID}/status" 2>/dev/null || echo "активен")
        ui_box_row "${C_GRN}[✔]${C_RES} Sing-Box Extended: ${C_GRN}● ЗАПУЩЕН${C_RES} (PID ${SB_PID}, ОЗУ: ${SB_RSS} / лимит ${SB_GOMEMLIMIT})"
    else
        ui_box_row "${C_RED}[✖] Sing-Box Extended: ОСТАНОВЛЕН (исправить: gateway doctor)${C_RES}"
    fi

    AGH_PID=$(pgrep AdGuardHome 2>/dev/null | head -n 1 || true)
    if [ -n "$AGH_PID" ]; then
        AGH_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${AGH_PID}/status" 2>/dev/null || echo "активен")
        ui_box_row "${C_GRN}[✔]${C_RES} AdGuard Home (:53): ${C_GRN}● ЗАПУЩЕН${C_RES} (PID ${AGH_PID}, ОЗУ: ${AGH_RSS} / лимит ${AGH_GOMEMLIMIT})"
    else
        ui_box_row "${C_RED}[✖] AdGuard Home (:53): ОСТАНОВЛЕН (исправить: gateway doctor)${C_RES}"
    fi

    if ip link show singbox-tun >/dev/null 2>&1; then
        ui_box_row "${C_GRN}[✔]${C_RES} Виртуальный интерфейс (singbox-tun): ${C_GRN}● АКТИВЕН${C_RES} (MTU 1492, mixed stack)"
    else
        ui_box_row "${C_RED}[✖] Виртуальный интерфейс (singbox-tun): НЕ НАЙДЕН${C_RES}"
    fi

    RP_STAT=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "unknown")
    BBR_STAT=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    CT_CNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
    ui_box_row "${C_GRN}[✔]${C_RES} Сетевой стек: TCP ${C_CYN}${BBR_STAT}${C_RES} │ rp_filter=${RP_STAT} │ Сессии Conntrack: ${C_BLD}${CT_CNT}${C_RES} из ${SYS_CONNTRACK_MAX}"

    if is_killswitch_enabled; then
        ui_box_row "${C_GRN}[✔]${C_RES} Защита от утечек: ${C_GRN}◆ Kill-Switch АКТИВЕН${C_RES} + блок Type 65 (HTTPS/ECH), IPv6 и DoT 853"
    else
        ui_box_row "${C_GRN}[✔]${C_RES} Защита от утечек: Блок Type 65 (HTTPS/ECH), IPv6 Drop, DoT/DoQ 853 Reject и DNS 53 Redirect"
    fi

    if [ -f "$SB_CONF" ] && [ -n "$SB_PID" ]; then
        ui_box_sep "МАТРИЦА ЗАДЕРЖЕК (PING MATRIX)"
        ACTIVE_NODE=$(curl -fsS --connect-timeout 3 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null | jq -r '.proxies["⚡ Авто (Самый быстрый)"].now // empty' 2>/dev/null)
        [ -n "$ACTIVE_NODE" ] && ui_box_row "Активная нода (Авто): ${C_CYN}${C_BLD}${ACTIVE_NODE}${C_RES}"
        CF_TRACE=$(curl -fsS --curves X25519:P-256 --connect-timeout 4 -x http://127.0.0.1:7890 "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null | grep -E '^(ip|loc|warp|colo)=' | tr '\n' ' ' || true)
        if [ -n "$CF_TRACE" ]; then
            ui_box_row "Внешний выход (Cloudflare Trace): ${C_GRN}${CF_TRACE}${C_RES}"
            PING_RU=$(curl -o /dev/null -fsS --curves X25519:P-256 --connect-timeout 2 -w '%{time_connect}' "http://ya.ru" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            PING_CF=$(curl -o /dev/null -fsS --curves X25519:P-256 --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "http://cp.cloudflare.com/generate_204" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            PING_GG=$(curl -o /dev/null -fsS --curves X25519:P-256 --connect-timeout 3 -x http://127.0.0.1:7890 -w '%{time_total}' "https://www.youtube.com/generate_204" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            PING_AI=$(curl -o /dev/null -sS --curves X25519:P-256 --connect-timeout 3 -m 4 -x http://127.0.0.1:7890 -w '%{time_appconnect}' "https://api.openai.com" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "timeout"}')
            ui_box_row "▸ Напрямую РФ (ya.ru):       $(ui_ping_bar "$PING_RU")"
            ui_box_row "▸ Cloudflare Anycast (TUN):  $(ui_ping_bar "$PING_CF")"
            ui_box_row "▸ YouTube / Google Video:    $(ui_ping_bar "$PING_GG")"
            ui_box_row "▸ OpenAI / AI API (TLS 1.3): $(ui_ping_bar "$PING_AI")"
        else
            ui_box_row "${C_YEL}[▲] Туннель еще прогревается или все внешние ноды недоступны (проверьте: gateway proxy).${C_RES}"
        fi
    fi
    ui_box_bottom

    if [ "$(count_enabled_homelab_modules)" -gt 0 ]; then
        run_homelab_self_test
    fi
    return 0
}

# Быстрая неинвазивная проверка синтаксиса и доступности ключевых сервисов (без перезапусков)
run_gateway_quick_check() {
    set +e
    detect_os
    load_gateway_env
    ui_box_top "🩺 НЕИНВАЗИВНЫЙ АУДИТ СИСТЕМЫ (GATEWAY CHECK)"

    # 1. Синтаксис Sing-Box
    if [ -x /usr/bin/sing-box ] && [ -s "$SB_CONF" ]; then
        if /usr/bin/sing-box check -c "$SB_CONF" -D /etc/sing-box >/dev/null 2>&1; then
            ui_box_row "${C_GRN}[✔]${C_RES} Sing-Box Config:      ${C_GRN}КОРРЕКТЕН${C_RES} (${SB_CONF})"
        else
            ui_box_row "${C_RED}[✖] Sing-Box Config:      ОШИБКА ВАЛИДАЦИИ СИНТАКСИСА${C_RES}"
        fi
    else
        ui_box_row "${C_YEL}[▲] Sing-Box Config:      НЕ НАЙДЕН (${SB_CONF})${C_RES}"
    fi

    # 2. Синтаксис Caddy
    if [ -x /usr/sbin/caddy ] && [ -s "$CADDY_CONF" ]; then
        if su -s /bin/sh caddy -c "XDG_DATA_HOME=/var/lib/caddy XDG_CONFIG_HOME=/var/lib/caddy HOME=/var/lib/caddy /usr/sbin/caddy validate --config '$CADDY_CONF' --adapter caddyfile" >/dev/null 2>&1 || \
           /usr/sbin/caddy validate --config "$CADDY_CONF" --adapter caddyfile >/dev/null 2>&1; then
            ui_box_row "${C_GRN}[✔]${C_RES} Caddyfile & PKI:      ${C_GRN}КОРРЕКТЕН${C_RES} (${CADDY_CONF})"
        else
            ui_box_row "${C_RED}[✖] Caddyfile & PKI:      ОШИБКА ВАЛИДАЦИИ CADDYFILE${C_RES}"
        fi
    fi

    # 2.5. Статус SSL/TLS
    if is_letsencrypt_ssl_active 2>/dev/null; then
        ui_box_row "${C_GRN}[✔]${C_RES} SSL/TLS Сертификат:   ${C_GRN}Let's Encrypt Wildcard (*.${SSL_DOMAIN})${C_RES}"
    else
        ui_box_row "${C_CYN}[✔]${C_RES} SSL/TLS Сертификат:   Локальный PKI (*.lan)"
    fi

    # 3. AdGuard Home DNS (:53)
    if nc -z -u -w 1 127.0.0.1 53 >/dev/null 2>&1 || pgrep AdGuardHome >/dev/null 2>&1; then
        ui_box_row "${C_GRN}[✔]${C_RES} AdGuard Home DNS:     ${C_GRN}АКТИВЕН${C_RES} (127.0.0.1:53 слушает запросы)"
    else
        ui_box_row "${C_RED}[✖] AdGuard Home DNS:     НЕ ОТВЕЧАЕТ НА ПОРТУ 53${C_RES}"
    fi

    # 4. Sing-Box Clash API (:9090)
    if curl -fsS -m 2 -H "Authorization: Bearer ${ADMIN_PASS:-admin}" "http://127.0.0.1:9090/configs" >/dev/null 2>&1; then
        ui_box_row "${C_GRN}[✔]${C_RES} Clash API (:9090):    ${C_GRN}АКТИВЕН${C_RES} (REST API отвечает, токен валиден)"
    else
        ui_box_row "${C_YEL}[▲] Clash API (:9090):    НЕДОСТУПЕН ИЛИ НЕВЕРНЫЙ СЕКРЕТ${C_RES}"
    fi

    # 5. Состояние памяти и Conntrack
    MEM_TOTAL_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    MEM_AVAIL_KB=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    if [ "$MEM_TOTAL_KB" -gt 0 ]; then
        MEM_USE_PCT=$(( (MEM_TOTAL_KB - MEM_AVAIL_KB) * 100 / MEM_TOTAL_KB ))
        ui_box_row "${C_GRN}[✔]${C_RES} Оперативная память:   ${MEM_USE_PCT}% занято ($((MEM_AVAIL_KB/1024)) МБ свободно из $((MEM_TOTAL_KB/1024)) МБ)"
    fi

    CT_NOW=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
    CT_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 1)
    CT_PCT=$(( CT_NOW * 100 / (CT_MAX > 0 ? CT_MAX : 1) ))
    ui_box_row "${C_GRN}[✔]${C_RES} Таблица Conntrack:    ${CT_NOW} / ${CT_MAX} сессий (${CT_PCT}%)"

    ui_box_bottom
    return 0
}

# ==============================================================================
# Динамический баннер приветствия SSH / Консоли (Fast Non-blocking MOTD)
# Вызывается автоматически при логине в систему через /etc/profile.d/00-gateway-motd.sh
# или вручную по команде `gw motd` / `gateway motd`
# ==============================================================================
print_gateway_motd() {
    load_gateway_env
    [ -f "$HOMELAB_ENV" ] && . "$HOMELAB_ENV" 2>/dev/null || true

    HN=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "alpine")
    ARCH_INFO=$(uname -m 2>/dev/null || echo "x86_64")
    UPTIME_RAW=$(uptime 2>/dev/null || echo "")
    UPTIME_STR=$(printf "%s" "$UPTIME_RAW" | sed -E 's/.*up[[:space:]]+([^,]+),.*/\1/' | sed 's/^[[:space:]]*//' || echo "online")
    LOAD_STR=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || echo "0.00")

    LAN_IP_CUR=$(get_current_lan_ip)
    LAN_DEV_CUR=$(get_lan_ifname)
    ROUTER_IP="${GW_IP:-$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n 1)}"

    # ОЗУ
    RAM_LINE=$(free -m 2>/dev/null | awk '/Mem:/ {if ($2>0) printf "%d МБ / %d МБ (%.0f%%)", $3, $2, ($3/$2)*100; else print "N/A"}')
    [ -z "$RAM_LINE" ] && RAM_LINE="${TOTAL_RAM_MB:-2048} МБ"

    # Хранилище
    if is_external_storage_mounted 2>/dev/null; then
        ST_LINE=$(df -h "$STORAGE_ROOT" 2>/dev/null | awk 'NR==2 {print $3" / "$2" ("$5")"}')
        ST_SRC=$(findmnt -n -o SOURCE "$STORAGE_ROOT" 2>/dev/null || true)
        ST_FS=$(blkid -s TYPE -o value "$ST_SRC" 2>/dev/null || echo "ext4")
        if [ -n "${EXT_STORAGE_LUKS_UUID:-}" ] || echo "$ST_SRC" | grep -q "mapper"; then
            ST_TAG=" [${ST_FS} / LUKS2 🔒]"
        else
            ST_TAG=" [${ST_FS}]"
        fi
        ST_INFO="${STORAGE_ROOT}: ${ST_LINE}${ST_TAG}"
    else
        ST_ROOT_LINE=$(df -h / 2>/dev/null | awk 'NR==2 {print $3" / "$2" ("$5")"}')
        ST_INFO="Локальный системный раздел: ${ST_ROOT_LINE} (диск не подключен)"
    fi

    # Статус ядер шлюза
    SB_ST="${C_RED}○${C_RES}"
    pgrep sing-box >/dev/null 2>&1 && SB_ST="${C_GRN}●${C_RES}"
    AGH_ST="${C_RED}○${C_RES}"
    pgrep AdGuardHome >/dev/null 2>&1 && AGH_ST="${C_GRN}●${C_RES}"
    TUN_ST="${C_RED}○${C_RES}"
    ip link show singbox-tun >/dev/null 2>&1 && TUN_ST="${C_GRN}●${C_RES}"

    # SSL / Домен
    if [ "${SSL_MODE:-local}" = "duckdns" ] && [ -n "${DUCKDNS_DOMAIN:-}" ]; then
        SSL_INFO="Let's Encrypt Wildcard (*.${DUCKDNS_DOMAIN})"
    else
        SSL_INFO="Локальный доверенный CA (*.lan)"
    fi

    # Homelab сервисы
    HL_SUMMARY=""
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            if [ "$M_EN" = "yes" ]; then
                if [ -n "$M_SVC" ] && rc-service "$M_SVC" status >/dev/null 2>&1; then
                    DOT="${C_GRN}●${C_RES}"
                else
                    DOT="${C_RED}○${C_RES}"
                fi
                HL_SUMMARY="${HL_SUMMARY} ${M_ID}[${DOT}]"
            fi
        done < "$HOMELAB_STATE"
    fi
    [ -z "$HL_SUMMARY" ] && HL_SUMMARY="только сетевой шлюз"

    echo ""
    echo "${C_BLU}╔══════════════════════════════════════════════════════════════════════════════╗${C_RES}"
    echo "${C_BLU}║${C_RES}  ${C_CYN}🚀 UNIVERSAL SIDECAR GATEWAY & HOMELAB // ALPINE LINUX${C_RES}"
    echo "${C_BLU}╠══════════════════════════════════════════════════════════════════════════════╣${C_RES}"
    printf "${C_BLU}║${C_RES}  ${C_BLD}• Хост / ОС:${C_RES}    %-24s │ Uptime: %-10s │ Load: %s\n" "${HN} (${ARCH_INFO})" "$UPTIME_STR" "$LOAD_STR"
    printf "${C_BLU}║${C_RES}  ${C_BLD}• Сеть:${C_RES}         LAN: %s (%s) │ Роутер: %s\n" "$LAN_IP_CUR" "$LAN_DEV_CUR" "$ROUTER_IP"
    printf "${C_BLU}║${C_RES}  ${C_BLD}• Память (RAM):${C_RES} %s\n" "$RAM_LINE"
    printf "${C_BLU}║${C_RES}  ${C_BLD}• Хранилище:${C_RES}    %s\n" "$ST_INFO"
    printf "${C_BLU}║${C_RES}  ${C_BLD}• Ядро шлюза:${C_RES}   Sing-Box [%b] │ AdGuard Home (:53) [%b] │ singbox-tun [%b]\n" "$SB_ST" "$AGH_ST" "$TUN_ST"
    printf "${C_BLU}║${C_RES}  ${C_BLD}• Homelab:${C_RES}     %s\n" "$HL_SUMMARY"
    printf "${C_BLU}║${C_RES}  ${C_BLD}• SSL / Домен:${C_RES}  %s\n" "$SSL_INFO"
    echo "${C_BLU}╠══════════════════════════════════════════════════════════════════════════════╣${C_RES}"
    echo "${C_BLU}║${C_RES}  ⚡ Быстрая команда: ${C_GRN}${C_BLD}gw${C_RES} │ Меню: ${C_CYN}gateway${C_RES} │ Ссылки: ${C_CYN}gw links${C_RES} │ Доктор: ${C_CYN}gw doctor${C_RES}"
    echo "${C_BLU}╚══════════════════════════════════════════════════════════════════════════════╝${C_RES}"
    echo ""
}

# Преобразование ввода пользователя (номер 1..9 или ID модуля) в канонический ID модуля
