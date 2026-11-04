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

# Преобразование ввода пользователя (номер 1..9 или ID модуля) в канонический ID модуля
