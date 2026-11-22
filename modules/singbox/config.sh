#!/bin/sh
# Генерация эталонного /etc/sing-box/config.json (Sing-Box Extended 1.14.3: Zero-Leak ИИ, Гейминг, Германия, США, .lan)
generate_singbox_config() {
    _OVERRIDE_CORE="${1:-}"
    calc_hardware_limits >/dev/null 2>&1 || true
    check_github_mirror
    sync_user_domain_rulesets
    load_gateway_env || true
    [ -n "$_OVERRIDE_CORE" ] && CORE_ENGINE="$_OVERRIDE_CORE" || true
    [ -z "${ADMIN_PASS:-}" ] && ADMIN_PASS="admin" || true
    [ -z "${GW_IP:-}" ] && GW_IP=$(get_default_router_ip) || true
    CUR_LIP_SB=$(get_current_lan_ip)

    if [ "${TOTAL_RAM_MB:-512}" -le 600 ]; then
        SB_DNS_CACHE="2048"
        SB_UT_INT="10m"
        SB_UT_IDLE="15m"
    elif [ "${TOTAL_RAM_MB:-512}" -le 1200 ]; then
        SB_DNS_CACHE="4096"
        SB_UT_INT="10m"
        SB_UT_IDLE="15m"
    else
        SB_DNS_CACHE="8192"
        SB_UT_INT="3m"
        SB_UT_IDLE="30m"
    fi

    PROVIDERS_JSON_ARR="[]"
    PROVIDER_TAGS_JSON="[]"
    ACTIVE_SUB_REGEX=$(get_sub_filter_regex)

    if command -v jq >/dev/null 2>&1; then
        # Слот 1: Поддержка одной или нескольких HTTP(S) подписок
        if is_sub_enabled; then
            IDX=0
            for U_ITEM in $(printf "%s\n" "$SUB_URL" | tr ' |' '\n\n' | grep -E '^https?://'); do
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
                        "user_agent": "clash.meta",
                        "update_interval": "24h",
                        "download_detour": "DIRECT",
                        "exclude": $excl,
                        "health_check": {
                            "enabled": false
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
                        "enabled": false
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
    FORCE_QUIC_RULE=""
    if [ "$FORCE_IPS_ARR" != "[]" ]; then
        FORCE_OUTBOUND_GROUP=$(cat << FORCE_GRP
    {
      "type": "selector",
      "tag": "📺 Устройства (Full-VPN)",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🇩🇪 Германия",
        "🇺🇸 США",
        "🌐 Остальной трафик",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
FORCE_GRP
)
        FORCE_QUIC_RULE="{\"source_ip_cidr\": ${FORCE_IPS_ARR}, \"network\": [\"udp\"], \"port\": [443], \"action\": \"reject\"},"
        FORCE_ROUTE_RULE="{\"source_ip_cidr\": ${FORCE_IPS_ARR}, \"outbound\": \"📺 Устройства (Full-VPN)\"},"
    fi

    DNS_FINAL_TAG="dns_proxy"
    if ! is_sub_enabled && ! has_my_nodes && ! is_warp_enabled; then
        DNS_FINAL_TAG="dns_ru"
    fi

    FORCE_DNS_RULES=""
    if [ "$FORCE_IPS_ARR" != "[]" ] && [ "$DNS_FINAL_TAG" != "dns_ru" ]; then
        FORCE_DNS_RULES=$(cat << FORCE_DNS_EOF
      {
        "source_ip_cidr": ${FORCE_IPS_ARR},
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      },
      {
        "source_ip_cidr": ${FORCE_IPS_ARR},
        "server": "dns_proxy"
      },
FORCE_DNS_EOF
)
    fi

    CATCHALL_FAKEIP_RULE=""
    if [ "$DNS_FINAL_TAG" != "dns_ru" ]; then
        CATCHALL_FAKEIP_RULE=$(cat << 'CA_FIP_EOF'
      ,{
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      }
CA_FIP_EOF
)
    fi

    CUR_UI_DL_URL="$ZASHBOARD_ZIP_URL"
    [ "$(get_active_ui)" = "metacubexd" ] && CUR_UI_DL_URL="$METACUBEXD_TAR_URL"

    SB_HOMELAB_LIST="$HOMELAB_LAN_DOMAINS"
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        SB_HOMELAB_LIST="${SB_HOMELAB_LIST} $(emit_homelab_le_domains "$SSL_DOMAIN")"
    fi
    SB_HOMELAB_DOMS_ARR=$(emit_json_string_array "$SB_HOMELAB_LIST")
    SB_DDR_DOMS_ARR=$(emit_json_string_array "$DDR_BLOCK_DOMAINS")
    SB_BOOTSTRAP_DOMS_ARR=$(emit_json_string_array "$BOOTSTRAP_DIRECT_DOMAINS")
    SB_GAME_CDN_DNS_ARR=$(emit_json_string_array "steamstatic.com $GAME_CDN_DIRECT_DOMAINS")
    SB_GAME_CDN_ROUTE_ARR=$(emit_json_string_array "$GAME_CDN_DIRECT_DOMAINS")
    SB_AI_DOMS_ARR=$(emit_json_string_array "$AI_EXPLICIT_DOMAINS")
    SB_ROBLOX_DOMS_ARR=$(emit_json_string_array "$ROBLOX_EXTRA_DOMAINS")
    SB_MEDIA_EXTRA_DOMS_ARR=$(emit_json_string_array "$SPOTIFY_EXTRA_DOMAINS $TWITCH_EXTRA_DOMAINS")
    SB_HOMELAB_HOSTS_JSON=""
    for _hdom in $SB_HOMELAB_LIST; do
        [ -z "$_hdom" ] && continue
        if [ -z "$SB_HOMELAB_HOSTS_JSON" ]; then
            SB_HOMELAB_HOSTS_JSON=$(printf '          "%s": ["%s"]' "$_hdom" "$CUR_LIP_SB")
        else
            SB_HOMELAB_HOSTS_JSON=$(printf '%s,\n          "%s": ["%s"]' "$SB_HOMELAB_HOSTS_JSON" "$_hdom" "$CUR_LIP_SB")
        fi
    done

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
      "store_fakeip": true,
      "store_warp_config": true,
      "store_masque_config": true
    },
    "clash_api": {
      "external_controller": "0.0.0.0:9090",
      "external_ui": "${UI_DIR}",
      "external_ui_download_url": "${GH_PROXY}${CUR_UI_DL_URL}",
      "secret": "PLACEHOLDER_SECRET",
      "default_mode": "rule"
    },
    "unified_delay": {
      "enabled": true
    }
  },
  "http_clients": [
    {
      "tag": "default",
      "detour": "DIRECT"
    }
  ],
  "dns": {
    "servers": [
      {
        "tag": "dns_ai",
        "type": "https",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "🤖 Нейросети (ИИ)"
      },
      {
        "tag": "dns_proxy",
        "type": "https",
        "server": "8.8.8.8",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "⚡ Авто (Самый быстрый)"
      },
      {
        "tag": "dns_ru",
        "type": "https",
        "server": "77.88.8.1",
        "server_port": 443,
        "path": "/dns-query",
        "tls": {
          "enabled": true,
          "server_name": "common.dot.dns.yandex.net"
        },
        "detour": "DIRECT"
      },
      {
        "tag": "dns_bootstrap",
        "type": "https",
        "server": "9.9.9.9",
        "server_port": 443,
        "path": "/dns-query",
        "tls": {
          "enabled": true,
          "server_name": "dns.quad9.net"
        },
        "detour": "DIRECT"
      },
      {
        "tag": "dns_local",
        "type": "udp",
        "server": "${GW_IP}",
        "server_port": 53
      },
      {
        "tag": "dns_homelab",
        "type": "hosts",
        "predefined": {
${SB_HOMELAB_HOSTS_JSON}
        }
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
        "domain": ${SB_HOMELAB_DOMS_ARR},
        "query_type": [
          "A"
        ],
        "server": "dns_homelab"
      },
      {
        "domain": ${SB_DDR_DOMS_ARR},
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
        "domain_suffix": [
          ".lan",
          ".home.arpa",
          ".local"
        ],
        "server": "dns_local"
      },
      {
        "rule_set": [
          "private_domain"
        ],
        "server": "dns_local"
      },
      ${FORCE_DNS_RULES}
      {
        "domain": ${SB_BOOTSTRAP_DOMS_ARR},
        "server": "dns_bootstrap"
      },
      {
        "domain_suffix": [
          "alpinelinux.org"
        ],
        "server": "dns_bootstrap"
      },
      {
        "rule_set": [
          "ntp_domain",
          "user_direct_domains",
          "torrent_domain"
        ],
        "server": "dns_ru"
      },
      {
        "domain_suffix": ${SB_GAME_CDN_DNS_ARR},
        "server": "dns_ru"
      },
      {
        "rule_set": [
          "steam_domain",
          "epicgames_domain",
          "riot_domain",
          "ea_domain",
          "ubisoft_domain",
          "blizzard_domain",
          "playstation_domain",
          "xbox_domain",
          "nintendo_domain"
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
        "domain_suffix": ${SB_AI_DOMS_ARR},
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      },
      {
        "domain_suffix": ${SB_AI_DOMS_ARR},
        "server": "dns_ai"
      },
      {
        "rule_set": [
          "ai_domain",
          "google_gemini_domain",
          "openai_domain",
          "anthropic_domain",
          "perplexity_domain",
          "xai_domain",
          "cursor_domain",
          "copilot_domain"
        ],
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      },
      {
        "rule_set": [
          "ai_domain",
          "google_gemini_domain",
          "openai_domain",
          "anthropic_domain",
          "perplexity_domain",
          "xai_domain",
          "cursor_domain",
          "copilot_domain"
        ],
        "server": "dns_ai"
      },
      {
        "rule_set": [
          "youtube_domain",
          "spotify_domain",
          "twitch_domain",
          "telegram_domain",
          "whatsapp_domain",
          "discord_domain",
          "meta_domain",
          "roblox_domain",
          "tiktok_domain",
          "ru_bundle"
        ],
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      },
      {
        "domain_suffix": ${SB_MEDIA_EXTRA_DOMS_ARR},
        "query_type": [
          "A"
        ],
        "server": "dns_fakeip",
        "rewrite_ttl": 1
      },
      {
        "domain_suffix": ${SB_ROBLOX_DOMS_ARR},
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
        "rule_set": [
          "google_domain"
        ],
        "server": "dns_ru"
      }${CATCHALL_FAKEIP_RULE}
    ],
    "final": "${DNS_FINAL_TAG}",
    "strategy": "ipv4_only",
    "reverse_mapping": true,
    "cache_capacity": ${SB_DNS_CACHE}
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
      "interface_name": "${CORE_TUN_IF}",
      "address": [
        "172.19.0.1/30"
      ],
      "mtu": 1400,
      "auto_route": true,
      "auto_redirect": true,
      "strict_route": true,
      "stack": "system",
      "udp_timeout": "5m"
    }
  ],
  "providers": ${PROVIDERS_JSON_ARR},
  "outbounds": [
    {
      "type": "selector",
      "tag": "🤖 Нейросети (ИИ)",
      "outbounds": [
        "🤖 Авто-ИИ",
        "🇺🇸 США",
        "🇩🇪 Германия",
        "⚡ Авто (Самый быстрый)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🇩🇪 Германия",
      "outbounds": [
        "🇩🇪 Авто-DE"
      ],
      "providers": ${PROVIDER_TAGS_JSON},
      "include": "PLACEHOLDER_DE_INC",
      "exclude": "PLACEHOLDER_DE_EXCL"
    },
    {
      "type": "selector",
      "tag": "🇺🇸 США",
      "outbounds": [
        "🇺🇸 Авто-US"
      ],
      "providers": ${PROVIDER_TAGS_JSON},
      "include": "PLACEHOLDER_US_INC"
    },
    {
      "type": "selector",
      "tag": "💬 Мессенджеры",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🇩🇪 Германия",
        "🇺🇸 США",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "▶️ YouTube & Медиа",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🇩🇪 Германия",
        "🇺🇸 США",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🎮 Гейминг",
      "outbounds": [
        "DIRECT",
        "🎮 Авто-Гейминг",
        "🇩🇪 Германия",
        "🇺🇸 США",
        "⚡ Авто (Самый быстрый)"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🧱 Roblox",
      "outbounds": [
        "🇩🇪 Германия",
        "⚡ Авто (Самый быстрый)",
        "🇺🇸 США",
        "🎮 Авто-Гейминг",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🛑 Обход блокировок",
      "outbounds": [
        "⚡ Авто (Самый быстрый)",
        "🇩🇪 Германия",
        "🇺🇸 США",
        "DIRECT"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🌐 Google & Android",
      "outbounds": [
        "DIRECT",
        "⚡ Авто (Самый быстрый)",
        "🇩🇪 Германия",
        "🇺🇸 США"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "selector",
      "tag": "🧲 Торренты",
      "outbounds": [
        "DIRECT",
        "⚡ Авто (Самый быстрый)",
        "🇩🇪 Германия",
        "🇺🇸 США"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    ${FORCE_OUTBOUND_GROUP}
    {
      "type": "selector",
      "tag": "🌐 Остальной трафик",
      "outbounds": [
        "DIRECT",
        "⚡ Авто (Самый быстрый)",
        "🇩🇪 Германия",
        "🇺🇸 США"
      ],
      "providers": ${PROVIDER_TAGS_JSON}
    },
    {
      "type": "urltest",
      "tag": "🤖 Авто-ИИ",
      "outbounds": [
        "⛔ Нет рабочих нод"
      ],
      "providers": ${PROVIDER_TAGS_JSON},
      "include": "PLACEHOLDER_AI_INC",
      "url": "https://www.gstatic.com/generate_204",
      "interval": "${SB_UT_INT}",
      "tolerance": 50,
      "idle_timeout": "${SB_UT_IDLE}"
    },
    {
      "type": "urltest",
      "tag": "🎮 Авто-Гейминг",
      "outbounds": [
        "⛔ Нет рабочих нод"
      ],
      "providers": ${PROVIDER_TAGS_JSON},
      "include": "PLACEHOLDER_GAME_INC",
      "url": "https://www.gstatic.com/generate_204",
      "interval": "${SB_UT_INT}",
      "tolerance": 25,
      "idle_timeout": "${SB_UT_IDLE}"
    },
    {
      "type": "urltest",
      "tag": "🇺🇸 Авто-US",
      "outbounds": [
        "⛔ Нет рабочих нод"
      ],
      "providers": ${PROVIDER_TAGS_JSON},
      "include": "PLACEHOLDER_US_INC",
      "url": "https://www.gstatic.com/generate_204",
      "interval": "${SB_UT_INT}",
      "tolerance": 40,
      "idle_timeout": "${SB_UT_IDLE}"
    },
    {
      "type": "urltest",
      "tag": "🇩🇪 Авто-DE",
      "outbounds": [
        "⛔ Нет рабочих нод"
      ],
      "providers": ${PROVIDER_TAGS_JSON},
      "include": "PLACEHOLDER_DE_INC",
      "exclude": "PLACEHOLDER_DE_EXCL",
      "url": "https://www.gstatic.com/generate_204",
      "interval": "${SB_UT_INT}",
      "tolerance": 35,
      "idle_timeout": "${SB_UT_IDLE}"
    },
    {
      "type": "urltest",
      "tag": "⚡ Авто (Самый быстрый)",
      "outbounds": [
        "🇩🇪 Авто-DE",
        "🇺🇸 Авто-US",
        "⛔ Нет рабочих нод"
      ],
      "providers": ${PROVIDER_TAGS_JSON},
      "exclude": "PLACEHOLDER_AUTO_EXCL",
      "url": "https://www.gstatic.com/generate_204",
      "interval": "${SB_UT_INT}",
      "tolerance": 35,
      "idle_timeout": "${SB_UT_IDLE}"
    },
    {
      "type": "direct",
      "tag": "DIRECT"
    },
    {
      "type": "socks",
      "tag": "⛔ Нет рабочих нод",
      "server": "127.0.0.1",
      "server_port": 1
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "default_http_client": "default",
    "default_domain_resolver": {
      "server": "dns_bootstrap",
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
          ".local",
          "alpinelinux.org"
        ],
        "outbound": "DIRECT"
      },
      {
        "domain": ${SB_HOMELAB_DOMS_ARR},
        "outbound": "DIRECT"
      },
      {
        "domain": ${SB_BOOTSTRAP_DOMS_ARR},
        "outbound": "DIRECT"
      },
      ${BYPASS_ROUTE_RULE}
      {
        "rule_set": [
          "private_domain",
          "private_ip",
          "user_direct_domains",
          "ntp_domain"
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
        "domain_suffix": ${SB_AI_DOMS_ARR},
        "network": [
          "udp"
        ],
        "port": [
          443
        ],
        "action": "reject"
      },
      {
        "domain_suffix": ${SB_MEDIA_EXTRA_DOMS_ARR},
        "network": [
          "udp"
        ],
        "port": [
          443
        ],
        "action": "reject"
      },
      {
        "domain_suffix": ${SB_ROBLOX_DOMS_ARR},
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
          "user_proxy_domains",
          "ai_domain",
          "google_gemini_domain",
          "openai_domain",
          "anthropic_domain",
          "perplexity_domain",
          "xai_domain",
          "cursor_domain",
          "copilot_domain",
          "youtube_domain",
          "spotify_domain",
          "twitch_domain",
          "meta_domain",
          "facebook_ip",
          "discord_domain",
          "roblox_domain",
          "tiktok_domain",
          "cloudflare_domain",
          "cloudflare_ip",
          "ru_bundle",
          "refilter_ip"
        ],
        "network": [
          "udp"
        ],
        "port": [
          443
        ],
        "action": "reject"
      },
      ${FORCE_QUIC_RULE}
      ${FORCE_ROUTE_RULE}
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
        "rule_set": [
          "user_proxy_domains"
        ],
        "outbound": "🛑 Обход блокировок"
      },
      {
        "domain_suffix": ${SB_AI_DOMS_ARR},
        "outbound": "🤖 Нейросети (ИИ)"
      },
      {
        "rule_set": [
          "ai_domain",
          "google_gemini_domain",
          "openai_domain",
          "anthropic_domain",
          "perplexity_domain",
          "xai_domain",
          "cursor_domain",
          "copilot_domain"
        ],
        "outbound": "🤖 Нейросети (ИИ)"
      },
      {
        "rule_set": [
          "youtube_domain",
          "spotify_domain",
          "twitch_domain"
        ],
        "outbound": "▶️ YouTube & Медиа"
      },
      {
        "domain_suffix": ${SB_MEDIA_EXTRA_DOMS_ARR},
        "outbound": "▶️ YouTube & Медиа"
      },
      {
        "rule_set": [
          "telegram_domain",
          "telegram_ip",
          "whatsapp_domain",
          "discord_domain",
          "discord_voice_ip"
        ],
        "outbound": "💬 Мессенджеры"
      },
      {
        "domain_suffix": ${SB_GAME_CDN_ROUTE_ARR},
        "outbound": "DIRECT"
      },
      {
        "domain_suffix": [
          "steamcommunity.com"
        ],
        "outbound": "🎮 Гейминг"
      },
      {
        "rule_set": [
          "steam_domain",
          "epicgames_domain",
          "riot_domain",
          "ea_domain",
          "ubisoft_domain",
          "blizzard_domain",
          "playstation_domain",
          "xbox_domain",
          "nintendo_domain"
        ],
        "outbound": "🎮 Гейминг"
      },
      {
        "domain_suffix": ${SB_ROBLOX_DOMS_ARR},
        "outbound": "🧱 Roblox"
      },
      {
        "rule_set": [
          "roblox_domain"
        ],
        "outbound": "🧱 Roblox"
      },
      {
        "rule_set": [
          "google_domain"
        ],
        "outbound": "🌐 Google & Android"
      },
      {
        "rule_set": [
          "ru_bundle",
          "refilter_ip",
          "meta_domain",
          "facebook_ip",
          "tiktok_domain",
          "cloudflare_domain",
          "cloudflare_ip"
        ],
        "outbound": "🛑 Обход блокировок"
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
        "tag": "google_gemini_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/google-gemini.srs"
      },
      {
        "tag": "openai_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/openai.srs"
      },
      {
        "tag": "anthropic_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/anthropic.srs"
      },
      {
        "tag": "perplexity_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/perplexity.srs"
      },
      {
        "tag": "xai_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/xai.srs"
      },
      {
        "tag": "cursor_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/cursor.srs"
      },
      {
        "tag": "copilot_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/github-copilot.srs"
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
        "tag": "tiktok_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/tiktok.srs"
      },
      {
        "tag": "steam_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/steam.srs"
      },
      {
        "tag": "epicgames_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/epicgames.srs"
      },
      {
        "tag": "riot_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/riot.srs"
      },
      {
        "tag": "ea_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/ea.srs"
      },
      {
        "tag": "ubisoft_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/ubisoft.srs"
      },
      {
        "tag": "blizzard_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/blizzard.srs"
      },
      {
        "tag": "playstation_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/playstation.srs"
      },
      {
        "tag": "xbox_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/xbox.srs"
      },
      {
        "tag": "nintendo_domain",
        "type": "remote",
        "format": "binary",
        "update_interval": "24h",
        "url": "${GH_PROXY}https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/nintendo.srs"
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

    # Подстановка секретов, regex-фильтров групп и сборка WARP / DIRECT-only вариантов через jq (fail-closed)
    if ! command -v jq >/dev/null 2>&1; then
        echo "${C_RED}[X] Ошибка: Утилита jq не найдена — генерация ${SB_CONF} отменена!${C_RES}" >&2
        rm -f "${SB_CONF}.tmp"
        [ -f "${SB_CONF}.bak" ] && cp -f "${SB_CONF}.bak" "$SB_CONF" 2>/dev/null || true
        return 1
    fi

    _jq_ok=0
    _jq_filters='(.outbounds[] | select(.tag == "⚡ Авто (Самый быстрый)") | .exclude) = $auto_exc
        | (.outbounds[] | select(.tag == "🤖 Авто-ИИ") | .include) = $ai_inc
        | (.outbounds[] | select(.tag == "🇩🇪 Германия" or .tag == "🇩🇪 Авто-DE") | .include) = $de_inc
        | (.outbounds[] | select(.tag == "🇩🇪 Германия" or .tag == "🇩🇪 Авто-DE") | .exclude) = $de_exc
        | (.outbounds[] | select(.tag == "🇺🇸 США" or .tag == "🇺🇸 Авто-US") | .include) = $us_inc
        | (.outbounds[] | select(.tag == "🎮 Авто-Гейминг") | .include) = $game_inc'
    _jq_drop='["🤖 Авто-ИИ", "🇩🇪 Авто-DE", "🇩🇪 Германия", "🇺🇸 Авто-US", "🇺🇸 США", "🎮 Авто-Гейминг", "⛔ Нет рабочих нод"] as $drop_tags'

    if is_warp_enabled; then
        _jq_warp_init='($w[0].masque // {
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
                "server_name": "engage.cloudflareclient.com",
                "insecure": false,
                "fragment": true,
                "fragment_fallback_delay": "500ms",
                "record_fragment": true
            }
        }) as $msq
        | ([($w[0].outbounds // [])[] | select((.private_key // "") != "")]) as $valid_wg
        | (($valid_wg | map(.tag)) + [$msq.tag]) as $warp_tags
        | .experimental.clash_api.secret = $secret
        | (.dns.servers[] | select(.tag == "dns_local") | .server) = $gw
        | .endpoints = $valid_wg'
        _jq_warp_tail='([.outbounds[] | select(.tag != "DIRECT" and .tag != "⛔ Нет рабочих нод")]) as $main
        | ([.outbounds[] | select(.tag == "DIRECT" or .tag == "⛔ Нет рабочих нод")]) as $tail
        | .outbounds = ($main + [{
            "type": "urltest",
            "tag": "☁️ Amnezia WARP",
            "outbounds": $warp_tags,
            "url": "https://cp.cloudflare.com/generate_204",
            "interval": $ut_int,
            "tolerance": 50,
            "idle_timeout": $ut_idle
        }, $msq] + $tail)'

        if [ "$PROVIDER_TAGS_JSON" != "[]" ]; then
            jq --arg secret "$ADMIN_PASS" --arg gw "${GW_IP}" --arg wlic "${WARP_LICENSE:-}" --arg ut_int "$SB_UT_INT" --arg ut_idle "$SB_UT_IDLE" \
               --arg ai_inc "$FILTER_AI_INCLUDE" --arg de_inc "$FILTER_DE_INCLUDE" --arg de_exc "$FILTER_DE_EXCLUDE" \
               --arg us_inc "$FILTER_US_INCLUDE" --arg game_inc "$FILTER_GAME_INCLUDE" --arg auto_exc "$FILTER_AUTO_EXCLUDE" \
               --slurpfile w "$WARP_NODES_FILE" "
                ${_jq_warp_init}
                | ${_jq_filters}
                | (.outbounds[] | select(.type == \"selector\" and .providers != null and .tag != \"🇩🇪 Германия\" and .tag != \"🇺🇸 США\") | .outbounds) += [\"☁️ Amnezia WARP\", \$msq.tag]
                | ${_jq_warp_tail}
            " "${SB_CONF}.tmp" > "${SB_CONF}.final.$$" 2>/dev/null && _jq_ok=1 || true
        else
            jq --arg secret "$ADMIN_PASS" --arg gw "${GW_IP}" --arg wlic "${WARP_LICENSE:-}" --arg ut_int "$SB_UT_INT" --arg ut_idle "$SB_UT_IDLE" \
               --slurpfile w "$WARP_NODES_FILE" "
                ${_jq_drop}
                | ${_jq_warp_init}
                | del(.providers)
                | .outbounds |= map(select(.tag as \$t | (\$drop_tags | index(\$t) | not)))
                | (.outbounds[] | select(.type == \"urltest\" and .providers != null)) |= (
                    del(.providers, .exclude, .include)
                    | .outbounds = \$warp_tags
                )
                | (.outbounds[] | select(.type == \"selector\" and .providers != null)) |= (
                    del(.providers, .exclude, .include)
                    | .outbounds = ((.outbounds | map(select(. as \$o | (\$drop_tags | index(\$o) | not)))) + [\"☁️ Amnezia WARP\"] + \$warp_tags)
                )
                | ${_jq_warp_tail}
            " "${SB_CONF}.tmp" > "${SB_CONF}.final.$$" 2>/dev/null && _jq_ok=1 || true
        fi
    elif [ "$PROVIDER_TAGS_JSON" = "[]" ]; then
        jq --arg secret "$ADMIN_PASS" --arg gw "${GW_IP}" "
            ${_jq_drop}
            | .experimental.clash_api.secret = \$secret
            | (.dns.servers[] | select(.tag == \"dns_local\") | .server) = \$gw
            | (.dns.servers[] | select(.tag == \"dns_ai\" or .tag == \"dns_proxy\") | .detour) = \"DIRECT\"
            | del(.providers)
            | .outbounds |= map(select(.tag as \$t | (\$drop_tags | index(\$t) | not)))
            | (.outbounds[] | select(.type == \"urltest\" and .providers != null)) |= (
                del(.providers, .exclude, .include)
                | .outbounds = [\"DIRECT\"]
            )
            | (.outbounds[] | select(.providers != null)) |= (
                del(.providers, .exclude, .include)
                | .outbounds = (
                    (.outbounds // [] | map(select(. as \$o | (\$drop_tags | index(\$o) | not))))
                    | if length == 0 then [\"DIRECT\"] else . end
                )
            )
        " "${SB_CONF}.tmp" > "${SB_CONF}.final.$$" 2>/dev/null && _jq_ok=1 || true
    else
        jq --arg secret "$ADMIN_PASS" --arg gw "${GW_IP}" \
           --arg ai_inc "$FILTER_AI_INCLUDE" --arg de_inc "$FILTER_DE_INCLUDE" --arg de_exc "$FILTER_DE_EXCLUDE" \
           --arg us_inc "$FILTER_US_INCLUDE" --arg game_inc "$FILTER_GAME_INCLUDE" --arg auto_exc "$FILTER_AUTO_EXCLUDE" "
            .experimental.clash_api.secret = \$secret
            | (.dns.servers[] | select(.tag == \"dns_local\") | .server) = \$gw
            | ${_jq_filters}
        " "${SB_CONF}.tmp" > "${SB_CONF}.final.$$" 2>/dev/null && _jq_ok=1 || true
    fi
    rm -f "${SB_CONF}.tmp"
    if [ "$_jq_ok" -eq 1 ] && [ -s "${SB_CONF}.final.$$" ]; then
        chmod 600 "${SB_CONF}.final.$$" 2>/dev/null || true
        mv -f "${SB_CONF}.final.$$" "$SB_CONF"
        chmod 600 "$SB_CONF" 2>/dev/null || true
    else
        rm -f "${SB_CONF}.final.$$"
        [ -f "${SB_CONF}.bak" ] && cp -f "${SB_CONF}.bak" "$SB_CONF" 2>/dev/null || true
        chmod 600 "$SB_CONF" 2>/dev/null || true
        return 1
    fi
    [ -f "$SB_ENV" ] || save_gateway_env
    return 0
}
