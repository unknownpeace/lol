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
