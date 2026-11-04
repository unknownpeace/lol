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
