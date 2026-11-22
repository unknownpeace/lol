#!/bin/sh
# ==============================================================================
# Генератор /etc/mihomo/config.yaml (Mihomo MetaCubeX: Zero-Leak ИИ, Гейминг, .lan)
# Полный функциональный паритет с Sing-Box Extended + единые списки маршрутизации
# ==============================================================================

yaml_sq() {
    printf "'%s'" "$(printf "%s" "${1:-}" | tr -d '\r\n' | sed "s/'/''/g")"
}

generate_mihomo_config() {
    _OVERRIDE_CORE="${1:-}"
    calc_hardware_limits >/dev/null 2>&1 || true
    check_github_mirror
    sync_user_domain_rulesets
    load_gateway_env || true
    [ -n "$_OVERRIDE_CORE" ] && CORE_ENGINE="$_OVERRIDE_CORE" || true
    [ -z "${ADMIN_PASS:-}" ] && ADMIN_PASS="admin" || true
    [ -z "${GW_IP:-}" ] && GW_IP=$(get_default_router_ip) || true
    CUR_LIP_MH=$(get_current_lan_ip)

    if [ "${TOTAL_RAM_MB:-512}" -le 1200 ]; then
        MH_UT_INT=600
    else
        MH_UT_INT=180
    fi

    mkdir -p "$MIHOMO_DIR" "${MIHOMO_DIR}/providers" "${MIHOMO_DIR}/rules"
    chmod 700 "$MIHOMO_DIR" 2>/dev/null || true

    ACTIVE_SUB_REGEX=$(get_sub_filter_regex)
    HAS_USER_PROXY="no"
    grep -q '[^[:space:]]' "$USER_PROXY_FILE" 2>/dev/null && HAS_USER_PROXY="yes" || true
    HAS_USER_DIRECT="no"
    grep -q '[^[:space:]]' "$USER_DIRECT_FILE" 2>/dev/null && HAS_USER_DIRECT="yes" || true

    USE_SUB="no"
    USE_MY="no"
    USE_WARP="no"
    is_sub_enabled && USE_SUB="yes" || true
    has_my_nodes && USE_MY="yes" || true

    # Подготовка YAML-прокси для Amnezia WARP из Слот 3 (WireGuard + amnezia-wg-option)
    WARP_PROXIES_YAML=""
    WARP_TAGS_YAML=""
    if is_warp_enabled && command -v jq >/dev/null 2>&1; then
        WARP_TMP_Y=$(jq -r '
            [.outbounds[]? | select(.type=="wireguard" and (.private_key // "") != "" and (.peers | length) > 0)]
            | if length == 0 then empty else .[] |
              "  - name: " + (.tag | @json) + "\n" +
              "    type: wireguard\n" +
              "    server: " + (.peers[0].address | @json) + "\n" +
              "    port: " + (.peers[0].port | tostring) + "\n" +
              "    ip: " + (((.address[0] // "172.16.0.2") | split("/")[0]) | @json) + "\n" +
              "    public-key: " + (.peers[0].public_key | @json) + "\n" +
              "    private-key: " + (.private_key | @json) + "\n" +
              "    udp: true\n" +
              "    mtu: " + ((.mtu // 1280) | tostring) + "\n" +
              "    remote-dns-resolve: false\n" +
              "    allowed-ips: [\"0.0.0.0/0\"]" +
              (if .amnezia then
                "\n    amnezia-wg-option:\n" +
                "      jc: " + ((.amnezia.jc // 4) | tostring) + "\n" +
                "      jmin: " + ((.amnezia.jmin // 40) | tostring) + "\n" +
                "      jmax: " + ((.amnezia.jmax // 70) | tostring) + "\n" +
                "      s1: " + ((.amnezia.s1 // 0) | tostring) + "\n" +
                "      s2: " + ((.amnezia.s2 // 0) | tostring) + "\n" +
                "      h1: " + ((.amnezia.h1 // 1) | tostring) + "\n" +
                "      h2: " + ((.amnezia.h2 // 2) | tostring) + "\n" +
                "      h3: " + ((.amnezia.h3 // 3) | tostring) + "\n" +
                "      h4: " + ((.amnezia.h4 // 4) | tostring) + "\n" +
                "      i1: " + ((.amnezia.i1 // "") | @json)
              else "" end)
            end
        ' "$WARP_NODES_FILE" 2>/dev/null || true)
        if [ -n "$WARP_TMP_Y" ]; then
            USE_WARP="yes"
            WARP_PROXIES_YAML="$WARP_TMP_Y"
            WARP_TAGS_YAML=$(jq -r '
                .outbounds[]? | select(.type=="wireguard" and (.private_key // "") != "" and (.peers | length) > 0)
                | "      - " + (.tag | @json)
            ' "$WARP_NODES_FILE" 2>/dev/null || true)
        fi
    fi

    USE_PROVIDERS="no"
    if [ "$USE_SUB" = "yes" ] || [ "$USE_MY" = "yes" ]; then
        USE_PROVIDERS="yes"
    fi

    IS_DIRECT_ONLY="no"
    if [ "$USE_PROVIDERS" = "no" ] && [ "$USE_WARP" = "no" ]; then
        IS_DIRECT_ONLY="yes"
    fi

    FORCE_IPS_YAML=""
    FORCE_QUIC_YAML=""
    FORCE_FAKEIP_YAML=""
    if [ -s "$USER_FORCE_PROXY_IPS" ]; then
        while IFS= read -r _f_line || [ -n "$_f_line" ]; do
            _f_line=$(printf "%s" "$_f_line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            case "$_f_line" in
                ""|\#*) continue ;;
            esac
            _f_cidr=""
            if is_valid_ipv4 "$_f_line"; then
                _f_cidr="${_f_line}/32"
            elif is_valid_ipv4_cidr "$_f_line"; then
                _f_cidr="$_f_line"
            fi
            if [ -n "$_f_cidr" ]; then
                FORCE_IPS_YAML="${FORCE_IPS_YAML}  - \"SRC-IP-CIDR,${_f_cidr},📺 Устройства (Full-VPN)\"
"
                FORCE_QUIC_YAML="${FORCE_QUIC_YAML}  - \"AND,((SRC-IP-CIDR,${_f_cidr}),(NETWORK,UDP),(DST-PORT,443)),REJECT\"
"
                FORCE_FAKEIP_YAML="${FORCE_FAKEIP_YAML}    - \"SRC-IP-CIDR,${_f_cidr},fake-ip\"
"
            fi
        done < "$USER_FORCE_PROXY_IPS"
    fi

    BYPASS_IPS_YAML=""
    if [ -s "$USER_BYPASS_IPS" ]; then
        while IFS= read -r _b_line || [ -n "$_b_line" ]; do
            _b_line=$(printf "%s" "$_b_line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            case "$_b_line" in
                ""|\#*) continue ;;
            esac
            _b_cidr=""
            if is_valid_ipv4 "$_b_line"; then
                _b_cidr="${_b_line}/32"
            elif is_valid_ipv4_cidr "$_b_line"; then
                _b_cidr="$_b_line"
            fi
            if [ -n "$_b_cidr" ]; then
                BYPASS_IPS_YAML="${BYPASS_IPS_YAML}  - \"SRC-IP-CIDR,${_b_cidr},DIRECT\"
"
            fi
        done < "$USER_BYPASS_IPS"
    fi

    [ -f "$MIHOMO_CONF" ] && cp -f "$MIHOMO_CONF" "${MIHOMO_CONF}.bak" || true

    cat << MH_HEAD > "${MIHOMO_CONF}.tmp.$$"
# Generated automatically for Mihomo (MetaCubeX) — DO NOT EDIT MANUALLY
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: rule
log-level: warning
ipv6: false
unified-delay: true
tcp-concurrent: true
find-process-mode: off

external-controller: 0.0.0.0:9090
external-ui: $(yaml_sq "${UI_DIR}")
secret: $(yaml_sq "${ADMIN_PASS}")

profile:
  store-selected: true
  store-fake-ip: true

hosts:
MH_HEAD

    for _ldom in $HOMELAB_LAN_DOMAINS; do
        printf "  '%s': %s\n" "$_ldom" "$CUR_LIP_MH" >> "${MIHOMO_CONF}.tmp.$$"
    done
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        printf "  '*.%s': %s\n" "${SSL_DOMAIN}" "$CUR_LIP_MH" >> "${MIHOMO_CONF}.tmp.$$"
        printf "  '%s': %s\n" "${SSL_DOMAIN}" "$CUR_LIP_MH" >> "${MIHOMO_CONF}.tmp.$$"
    fi

    cat << MH_TUN >> "${MIHOMO_CONF}.tmp.$$"

tun:
  enable: true
  device: ${CORE_TUN_IF}
  stack: system
  mtu: 1400
  inet4-address:
    - 172.19.0.1/30
  auto-route: true
  auto-redirect: true
  strict-route: true
  auto-detect-interface: true

sniffer:
  enable: true
  parse-pure-ip: true
  override-destination: false
  sniff:
    HTTP:
      ports: [80, 8080-8880]
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]

dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  use-hosts: true
  respect-rules: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter-mode: rule
  default-nameserver:
    - 9.9.9.9
    - 77.88.8.1
  proxy-server-nameserver:
    - https://9.9.9.9/dns-query
    - https://77.88.8.1/dns-query
  direct-nameserver:
    - https://77.88.8.1/dns-query
    - https://9.9.9.9/dns-query
MH_TUN

    if [ "$IS_DIRECT_ONLY" = "yes" ]; then
        cat << 'MH_DNS_DIR' >> "${MIHOMO_CONF}.tmp.$$"
  nameserver:
    - https://77.88.8.1/dns-query
MH_DNS_DIR
    else
        cat << 'MH_DNS_PRX' >> "${MIHOMO_CONF}.tmp.$$"
  nameserver:
    - 'https://8.8.8.8/dns-query#⚡ Авто (Самый быстрый)'
MH_DNS_PRX
    fi

    {
        echo "  nameserver-policy:"
        emit_yaml_ns_policy "    " "$DDR_BLOCK_DOMAINS" "" "'rcode://name_error'"
        printf "    '*.lan': '%s:53'\n" "$GW_IP"
        printf "    '*.home.arpa': '%s:53'\n" "$GW_IP"
        printf "    '*.local': '%s:53'\n" "$GW_IP"
        printf "    'rule-set:private_domain': '%s:53'\n" "$GW_IP"
        emit_yaml_ns_policy "    " "$BOOTSTRAP_DIRECT_DOMAINS" "" "'https://9.9.9.9/dns-query#DIRECT'"
        echo "    '*.alpinelinux.org': 'https://9.9.9.9/dns-query#DIRECT'"
        emit_yaml_ns_policy "    " "$GAME_CDN_DIRECT_DOMAINS" "+." "'https://77.88.8.1/dns-query#DIRECT'"
        for _rs in ntp_domain torrent_domain steam_domain epicgames_domain riot_domain ea_domain ubisoft_domain blizzard_domain playstation_domain xbox_domain nintendo_domain ru_domain google_domain; do
            printf "    'rule-set:%s': 'https://77.88.8.1/dns-query#DIRECT'\n" "$_rs"
        done
        if [ "$HAS_USER_DIRECT" = "yes" ]; then
            echo "    'rule-set:user_direct_domains': 'https://77.88.8.1/dns-query#DIRECT'"
        fi

        if [ "$IS_DIRECT_ONLY" = "yes" ]; then
            AI_NS="'https://77.88.8.1/dns-query#DIRECT'"
        else
            AI_NS="'https://1.1.1.1/dns-query#🤖 Нейросети (ИИ)'"
        fi
        if [ "$HAS_USER_PROXY" = "yes" ]; then
            echo "    'rule-set:user_proxy_domains': 'https://8.8.8.8/dns-query#⚡ Авто (Самый быстрый)'"
        fi
        emit_yaml_ns_policy "    " "$AI_EXPLICIT_DOMAINS" "+." "$AI_NS"
        for _rs in ai_domain google_gemini_domain openai_domain anthropic_domain perplexity_domain xai_domain cursor_domain copilot_domain; do
            printf "    'rule-set:%s': %s\n" "$_rs" "$AI_NS"
        done

        echo "  fake-ip-filter:"
        emit_yaml_typed_rules "    " "DOMAIN" "$DDR_BLOCK_DOMAINS" "real-ip"
        emit_yaml_typed_rules "    " "DOMAIN-SUFFIX" "lan home.arpa local" "real-ip"
        echo '    - "RULE-SET,private_domain,real-ip"'
        emit_yaml_typed_rules "    " "DOMAIN" "$BOOTSTRAP_DIRECT_DOMAINS" "real-ip"
        echo '    - "DOMAIN-SUFFIX,alpinelinux.org,real-ip"'
        echo '    - "RULE-SET,ntp_domain,real-ip"'
        [ "$HAS_USER_DIRECT" = "yes" ] && echo '    - "RULE-SET,user_direct_domains,real-ip"'
        echo '    - "RULE-SET,torrent_domain,real-ip"'
        emit_yaml_typed_rules "    " "DOMAIN-SUFFIX" "$GAME_CDN_DIRECT_DOMAINS" "real-ip"
        for _rs in steam_domain epicgames_domain riot_domain ea_domain ubisoft_domain blizzard_domain playstation_domain xbox_domain nintendo_domain; do
            printf '    - "RULE-SET,%s,real-ip"\n' "$_rs"
        done
        if [ "$IS_DIRECT_ONLY" = "yes" ]; then
            echo '    - "MATCH,real-ip"'
        else
            [ -n "$FORCE_FAKEIP_YAML" ] && printf "%s" "$FORCE_FAKEIP_YAML"
            [ "$HAS_USER_PROXY" = "yes" ] && echo '    - "RULE-SET,user_proxy_domains,fake-ip"'
            emit_yaml_typed_rules "    " "DOMAIN-SUFFIX" "$AI_EXPLICIT_DOMAINS" "fake-ip"
            for _rs in ai_domain google_gemini_domain openai_domain anthropic_domain perplexity_domain xai_domain cursor_domain copilot_domain; do
                printf '    - "RULE-SET,%s,fake-ip"\n' "$_rs"
            done
            for _rs in youtube_domain spotify_domain twitch_domain telegram_domain whatsapp_domain discord_domain meta_domain roblox_domain tiktok_domain ru_bundle; do
                printf '    - "RULE-SET,%s,fake-ip"\n' "$_rs"
            done
            emit_yaml_typed_rules "    " "DOMAIN-SUFFIX" "$SPOTIFY_EXTRA_DOMAINS $TWITCH_EXTRA_DOMAINS $ROBLOX_EXTRA_DOMAINS" "fake-ip"
            echo '    - "RULE-SET,ru_domain,real-ip"'
            echo '    - "RULE-SET,google_domain,real-ip"'
            echo '    - "MATCH,fake-ip"'
        fi
    } >> "${MIHOMO_CONF}.tmp.$$"

    # Proxies (fail-closed dummy when providers active + WireGuard WARP)
    {
        if [ "$USE_PROVIDERS" = "yes" ] || [ "$USE_WARP" = "yes" ]; then
            echo ""
            echo "proxies:"
            if [ "$USE_PROVIDERS" = "yes" ]; then
                echo '  - name: "⛔ Нет рабочих нод"'
                echo '    type: socks5'
                echo '    server: 127.0.0.1'
                echo '    port: 1'
            fi
            [ -n "$WARP_PROXIES_YAML" ] && printf "%s\n" "$WARP_PROXIES_YAML"
        fi
    } >> "${MIHOMO_CONF}.tmp.$$"

    # Proxy providers (Slot 1 HTTPS subscriptions + Slot 2 my_nodes.yaml)
    USE_TAGS_YAML=""
    if [ "$USE_PROVIDERS" = "yes" ]; then
        {
            echo ""
            echo "proxy-providers:"
            if [ "$USE_SUB" = "yes" ]; then
                IDX=0
                for U_ITEM in $(printf "%s\n" "$SUB_URL" | tr ' |' '\n\n' | grep -E '^https?://'); do
                    IDX=$((IDX + 1))
                    if [ "$IDX" -eq 1 ]; then
                        P_TAG="custom_sub"
                    else
                        P_TAG="custom_sub_${IDX}"
                    fi
                    USE_TAGS_YAML="${USE_TAGS_YAML}
      - ${P_TAG}"
                    cat << MH_PROV
  ${P_TAG}:
    type: http
    url: $(yaml_sq "$U_ITEM")
    path: ./providers/${P_TAG}.yaml
    interval: 86400
    header:
      User-Agent: ["clash.meta"]
    exclude-filter: $(yaml_sq "$ACTIVE_SUB_REGEX")
    health-check:
      enable: false
MH_PROV
                done
            fi
            if [ "$USE_MY" = "yes" ]; then
                USE_TAGS_YAML="${USE_TAGS_YAML}
      - my_nodes"
                cat << MH_MYPROV
  my_nodes:
    type: file
    path: $(yaml_sq "$CUSTOM_NODES_FILE")
    health-check:
      enable: false
MH_MYPROV
            fi
        } >> "${MIHOMO_CONF}.tmp.$$"
    fi

    # Proxy groups (identical naming & logic to Sing-Box)
    {
        echo ""
        echo "proxy-groups:"

        emit_selector_tail() {
            _allow_direct="$1"
            if [ "$USE_PROVIDERS" = "yes" ]; then
                [ "$USE_WARP" = "yes" ] && echo '      - "☁️ Amnezia WARP"'
                [ "$_allow_direct" = "yes" ] && echo '      - "DIRECT"'
                echo "    use:${USE_TAGS_YAML}"
            elif [ "$USE_WARP" = "yes" ]; then
                echo '      - "☁️ Amnezia WARP"'
                printf "%s\n" "$WARP_TAGS_YAML"
                [ "$_allow_direct" = "yes" ] && echo '      - "DIRECT"'
            else
                [ "$_allow_direct" = "yes" ] && echo '      - "DIRECT"'
            fi
        }

        if [ "$USE_PROVIDERS" = "yes" ]; then
            cat << MH_SEL_SUB | awk 'NF'
  - name: "🤖 Нейросети (ИИ)"
    type: select
    proxies:
      - "🤖 Авто-ИИ"
      - "🇺🇸 США"
      - "🇩🇪 Германия"
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "no")
  - name: "🇩🇪 Германия"
    type: select
    proxies:
      - "🇩🇪 Авто-DE"
    use:${USE_TAGS_YAML}
    filter: $(yaml_sq "$FILTER_DE_INCLUDE")
    exclude-filter: $(yaml_sq "$FILTER_DE_EXCLUDE")
  - name: "🇺🇸 США"
    type: select
    proxies:
      - "🇺🇸 Авто-US"
    use:${USE_TAGS_YAML}
    filter: $(yaml_sq "$FILTER_US_INCLUDE")
  - name: "💬 Мессенджеры"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
      - "DIRECT"
$(emit_selector_tail "no")
  - name: "▶️ YouTube & Медиа"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
      - "DIRECT"
$(emit_selector_tail "no")
  - name: "🎮 Гейминг"
    type: select
    proxies:
      - "DIRECT"
      - "🎮 Авто-Гейминг"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "no")
  - name: "🧱 Roblox"
    type: select
    proxies:
      - "🇩🇪 Германия"
      - "⚡ Авто (Самый быстрый)"
      - "🇺🇸 США"
      - "🎮 Авто-Гейминг"
      - "DIRECT"
$(emit_selector_tail "no")
  - name: "🛑 Обход блокировок"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
      - "DIRECT"
$(emit_selector_tail "no")
  - name: "🌐 Google & Android"
    type: select
    proxies:
      - "DIRECT"
      - "⚡ Авто (Самый быстрый)"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
$(emit_selector_tail "no")
  - name: "🧲 Торренты"
    type: select
    proxies:
      - "DIRECT"
      - "⚡ Авто (Самый быстрый)"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
$(emit_selector_tail "no")
MH_SEL_SUB
            if [ -n "$FORCE_IPS_YAML" ]; then
                cat << MH_FORCE_GRP | awk 'NF'
  - name: "📺 Устройства (Full-VPN)"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
      - "🌐 Остальной трафик"
      - "DIRECT"
$(emit_selector_tail "no")
MH_FORCE_GRP
            fi
            cat << MH_REST_SUB | awk 'NF'
  - name: "🌐 Остальной трафик"
    type: select
    proxies:
      - "DIRECT"
      - "⚡ Авто (Самый быстрый)"
      - "🇩🇪 Германия"
      - "🇺🇸 США"
$(emit_selector_tail "no")
  - name: "🤖 Авто-ИИ"
    type: url-test
    proxies:
      - "⛔ Нет рабочих нод"
    use:${USE_TAGS_YAML}
    filter: $(yaml_sq "$FILTER_AI_INCLUDE")
    url: "https://www.gstatic.com/generate_204"
    interval: ${MH_UT_INT}
    tolerance: 50
  - name: "🎮 Авто-Гейминг"
    type: url-test
    proxies:
      - "⛔ Нет рабочих нод"
    use:${USE_TAGS_YAML}
    filter: $(yaml_sq "$FILTER_GAME_INCLUDE")
    url: "https://www.gstatic.com/generate_204"
    interval: ${MH_UT_INT}
    tolerance: 25
  - name: "🇺🇸 Авто-US"
    type: url-test
    proxies:
      - "⛔ Нет рабочих нод"
    use:${USE_TAGS_YAML}
    filter: $(yaml_sq "$FILTER_US_INCLUDE")
    url: "https://www.gstatic.com/generate_204"
    interval: ${MH_UT_INT}
    tolerance: 40
  - name: "🇩🇪 Авто-DE"
    type: url-test
    proxies:
      - "⛔ Нет рабочих нод"
    use:${USE_TAGS_YAML}
    filter: $(yaml_sq "$FILTER_DE_INCLUDE")
    exclude-filter: $(yaml_sq "$FILTER_DE_EXCLUDE")
    url: "https://www.gstatic.com/generate_204"
    interval: ${MH_UT_INT}
    tolerance: 35
  - name: "⚡ Авто (Самый быстрый)"
    type: url-test
    proxies:
      - "🇩🇪 Авто-DE"
      - "🇺🇸 Авто-US"
      - "⛔ Нет рабочих нод"
    use:${USE_TAGS_YAML}
    exclude-filter: $(yaml_sq "$FILTER_AUTO_EXCLUDE")
    url: "https://www.gstatic.com/generate_204"
    interval: ${MH_UT_INT}
    tolerance: 35
MH_REST_SUB
        else
            # WARP-only or DIRECT-only (no regional/provider groups)
            cat << MH_SEL_NOWP | awk 'NF'
  - name: "🤖 Нейросети (ИИ)"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "yes")
  - name: "💬 Мессенджеры"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "yes")
  - name: "▶️ YouTube & Медиа"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "yes")
  - name: "🎮 Гейминг"
    type: select
    proxies:
      - "DIRECT"
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "no")
  - name: "🧱 Roblox"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "yes")
  - name: "🛑 Обход блокировок"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "yes")
  - name: "🌐 Google & Android"
    type: select
    proxies:
      - "DIRECT"
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "no")
  - name: "🧲 Торренты"
    type: select
    proxies:
      - "DIRECT"
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "no")
MH_SEL_NOWP
            if [ -n "$FORCE_IPS_YAML" ]; then
                cat << MH_FORCE_NOWP | awk 'NF'
  - name: "📺 Устройства (Full-VPN)"
    type: select
    proxies:
      - "⚡ Авто (Самый быстрый)"
      - "🌐 Остальной трафик"
$(emit_selector_tail "yes")
MH_FORCE_NOWP
            fi
            cat << MH_REST_NOWP | awk 'NF'
  - name: "🌐 Остальной трафик"
    type: select
    proxies:
      - "DIRECT"
      - "⚡ Авто (Самый быстрый)"
$(emit_selector_tail "no")
  - name: "⚡ Авто (Самый быстрый)"
    type: url-test
    proxies:
$(emit_selector_tail "yes")
    url: "https://www.gstatic.com/generate_204"
    interval: ${MH_UT_INT}
    tolerance: 50
MH_REST_NOWP
        fi

        if [ "$USE_WARP" = "yes" ]; then
            cat << MH_WARP_GRP
  - name: "☁️ Amnezia WARP"
    type: url-test
    proxies:
${WARP_TAGS_YAML}
    url: "https://cp.cloudflare.com/generate_204"
    interval: ${MH_UT_INT}
    tolerance: 50
MH_WARP_GRP
        fi
    } >> "${MIHOMO_CONF}.tmp.$$"

    # Rule providers (.mrs + local text lists)
    emit_mrs_provider() {
        _tag="$1"
        _beh="$2"
        _url="$3"
        cat << MH_RP
  ${_tag}:
    type: http
    behavior: ${_beh}
    format: mrs
    url: $(yaml_sq "${GH_PROXY}${_url}")
    path: ./rules/${_tag}.mrs
    interval: 86400
MH_RP
    }

    {
        echo ""
        echo "rule-providers:"
        if [ "$HAS_USER_DIRECT" = "yes" ]; then
            cat << MH_UD
  user_direct_domains:
    type: file
    behavior: domain
    format: text
    path: $(yaml_sq "$USER_DIRECT_FILE")
MH_UD
        fi
        if [ "$HAS_USER_PROXY" = "yes" ]; then
            cat << MH_UP
  user_proxy_domains:
    type: file
    behavior: domain
    format: text
    path: $(yaml_sq "$USER_PROXY_FILE")
MH_UP
        fi

        emit_mrs_provider "private_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/private.mrs"
        emit_mrs_provider "private_ip" "ipcidr" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/private.mrs"
        emit_mrs_provider "ntp_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ntp.mrs"
        emit_mrs_provider "torrent_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/tracker.mrs"
        emit_mrs_provider "youtube_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/youtube.mrs"
        emit_mrs_provider "spotify_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/spotify.mrs"
        emit_mrs_provider "twitch_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/twitch.mrs"
        emit_mrs_provider "meta_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/meta.mrs"
        emit_mrs_provider "ai_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ai-!cn.mrs"
        emit_mrs_provider "google_gemini_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/google-gemini.mrs"
        emit_mrs_provider "openai_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/openai.mrs"
        emit_mrs_provider "anthropic_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/anthropic.mrs"
        emit_mrs_provider "perplexity_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/perplexity.mrs"
        emit_mrs_provider "xai_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/xai.mrs"
        emit_mrs_provider "cursor_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cursor.mrs"
        emit_mrs_provider "copilot_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github-copilot.mrs"
        emit_mrs_provider "google_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/google.mrs"
        emit_mrs_provider "roblox_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/roblox.mrs"
        emit_mrs_provider "tiktok_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/tiktok.mrs"
        emit_mrs_provider "steam_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/steam.mrs"
        emit_mrs_provider "epicgames_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/epicgames.mrs"
        emit_mrs_provider "riot_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/riot.mrs"
        emit_mrs_provider "ea_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/ea.mrs"
        emit_mrs_provider "ubisoft_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/ubisoft.mrs"
        emit_mrs_provider "blizzard_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/blizzard.mrs"
        emit_mrs_provider "playstation_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/playstation.mrs"
        emit_mrs_provider "xbox_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/xbox.mrs"
        emit_mrs_provider "nintendo_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/nintendo.mrs"
        emit_mrs_provider "telegram_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/telegram.mrs"
        emit_mrs_provider "telegram_ip" "ipcidr" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/telegram.mrs"
        emit_mrs_provider "whatsapp_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/whatsapp.mrs"
        emit_mrs_provider "facebook_ip" "ipcidr" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/facebook.mrs"
        emit_mrs_provider "discord_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/discord.mrs"
        emit_mrs_provider "discord_voice_ip" "ipcidr" "https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/other/discord-voice-ip-list.mrs"
        emit_mrs_provider "cloudflare_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cloudflare.mrs"
        emit_mrs_provider "cloudflare_ip" "ipcidr" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/cloudflare.mrs"
        emit_mrs_provider "ru_bundle" "domain" "https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/ru-bundle/rule.mrs"
        emit_mrs_provider "refilter_ip" "ipcidr" "https://raw.githubusercontent.com/legiz-ru/mihomo-rule-sets/main/ru-bundle/rknasnblock.mrs"
        emit_mrs_provider "ru_domain" "domain" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ru.mrs"
        emit_mrs_provider "ru_ip" "ipcidr" "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geoip/ru.mrs"
    } >> "${MIHOMO_CONF}.tmp.$$"

    # Routing rules (strict parity with Sing-Box rule precedence)
    {
        echo ""
        echo "rules:"
        emit_yaml_typed_rules "  " "DOMAIN-SUFFIX" "lan home.arpa local alpinelinux.org" "DIRECT"
        emit_yaml_typed_rules "  " "DOMAIN" "$BOOTSTRAP_DIRECT_DOMAINS" "DIRECT"
        [ -n "$BYPASS_IPS_YAML" ] && printf "%s\n" "$BYPASS_IPS_YAML"
        echo '  - "IP-CIDR,198.18.0.0/15,REJECT,no-resolve"'
        echo '  - "RULE-SET,private_domain,DIRECT"'
        echo '  - "RULE-SET,private_ip,DIRECT,no-resolve"'
        [ "$HAS_USER_DIRECT" = "yes" ] && echo '  - "RULE-SET,user_direct_domains,DIRECT"'
        echo '  - "RULE-SET,ntp_domain,DIRECT"'
        echo '  - "DST-PORT,123,DIRECT"'
        echo '  - "DST-PORT,853,REJECT"'

        # QUIC block (UDP:443 -> REJECT) for AI + key proxy domains + Full-VPN devices
        emit_yaml_quic_reject_rules "  " "DOMAIN-SUFFIX" "$AI_EXPLICIT_DOMAINS $SPOTIFY_EXTRA_DOMAINS $TWITCH_EXTRA_DOMAINS $ROBLOX_EXTRA_DOMAINS"
        [ "$HAS_USER_PROXY" = "yes" ] && emit_yaml_quic_reject_rules "  " "RULE-SET" "user_proxy_domains"
        emit_yaml_quic_reject_rules "  " "RULE-SET" "ai_domain google_gemini_domain openai_domain anthropic_domain perplexity_domain xai_domain cursor_domain copilot_domain youtube_domain spotify_domain twitch_domain meta_domain discord_domain roblox_domain tiktok_domain cloudflare_domain ru_bundle"
        for _iprs in refilter_ip facebook_ip cloudflare_ip; do
            printf '  - "AND,((RULE-SET,%s),(NETWORK,UDP),(DST-PORT,443)),REJECT,no-resolve"\n' "$_iprs"
        done
        [ -n "$FORCE_QUIC_YAML" ] && printf "%s" "$FORCE_QUIC_YAML"

        [ -n "$FORCE_IPS_YAML" ] && printf "%s" "$FORCE_IPS_YAML"
        echo '  - "RULE-SET,torrent_domain,🧲 Торренты"'
        echo '  - "DST-PORT,6881-6889,🧲 Торренты"'
        echo '  - "SRC-PORT,51413,🧲 Торренты"'
        [ "$HAS_USER_PROXY" = "yes" ] && echo '  - "RULE-SET,user_proxy_domains,🛑 Обход блокировок"'

        # AI rules BEFORE Google & DIRECT
        emit_yaml_typed_rules "  " "DOMAIN-SUFFIX" "$AI_EXPLICIT_DOMAINS" "🤖 Нейросети (ИИ)"
        emit_yaml_typed_rules "  " "RULE-SET" "ai_domain google_gemini_domain openai_domain anthropic_domain perplexity_domain xai_domain cursor_domain copilot_domain" "🤖 Нейросети (ИИ)"

        # Media & Messengers
        emit_yaml_typed_rules "  " "RULE-SET" "youtube_domain spotify_domain twitch_domain" "▶️ YouTube & Медиа"
        emit_yaml_typed_rules "  " "DOMAIN-SUFFIX" "$SPOTIFY_EXTRA_DOMAINS $TWITCH_EXTRA_DOMAINS" "▶️ YouTube & Медиа"
        emit_yaml_typed_rules "  " "RULE-SET" "telegram_domain whatsapp_domain discord_domain" "💬 Мессенджеры"
        echo '  - "RULE-SET,telegram_ip,💬 Мессенджеры,no-resolve"'
        echo '  - "RULE-SET,discord_voice_ip,💬 Мессенджеры,no-resolve"'

        # Gaming (CDNs DIRECT first, then selector) + Roblox (Germany by default before ru_bundle)
        emit_yaml_typed_rules "  " "DOMAIN-SUFFIX" "$GAME_CDN_DIRECT_DOMAINS" "DIRECT"
        echo '  - "DOMAIN-SUFFIX,steamcommunity.com,🎮 Гейминг"'
        emit_yaml_typed_rules "  " "RULE-SET" "steam_domain epicgames_domain riot_domain ea_domain ubisoft_domain blizzard_domain playstation_domain xbox_domain nintendo_domain" "🎮 Гейминг"
        emit_yaml_typed_rules "  " "DOMAIN-SUFFIX" "$ROBLOX_EXTRA_DOMAINS" "🧱 Roblox"
        echo '  - "RULE-SET,roblox_domain,🧱 Roblox"'

        # Google, Block Bypass, RU Direct, Final
        echo '  - "RULE-SET,google_domain,🌐 Google & Android"'
        emit_yaml_typed_rules "  " "RULE-SET" "ru_bundle meta_domain tiktok_domain cloudflare_domain" "🛑 Обход блокировок"
        echo '  - "RULE-SET,refilter_ip,🛑 Обход блокировок,no-resolve"'
        echo '  - "RULE-SET,facebook_ip,🛑 Обход блокировок,no-resolve"'
        echo '  - "RULE-SET,cloudflare_ip,🛑 Обход блокировок,no-resolve"'
        echo '  - "RULE-SET,ru_domain,DIRECT"'
        echo '  - "RULE-SET,ru_ip,DIRECT,no-resolve"'
        echo '  - "MATCH,🌐 Остальной трафик"'
    } >> "${MIHOMO_CONF}.tmp.$$"

    if ! atomic_commit_tmp "${MIHOMO_CONF}.tmp.$$" "$MIHOMO_CONF" 0600 "root:root"; then
        [ -f "${MIHOMO_CONF}.bak" ] && cp -f "${MIHOMO_CONF}.bak" "$MIHOMO_CONF" 2>/dev/null || true
        chmod 600 "$MIHOMO_CONF" 2>/dev/null || true
        return 1
    fi
    [ -f "$SB_ENV" ] || save_gateway_env
    return 0
}
