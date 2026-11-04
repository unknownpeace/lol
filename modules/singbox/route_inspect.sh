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
    ui_box_top "🕵️ Рентген маршрута для домена: ${C_BLD}${CLEAN_HOST}${C_RES}${C_CYN}"

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
    ui_box_sep
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

# Поштучная диагностика и оживление нод с «молнией» (⚡) без залповой перегрузки
