check_singbox_config() {
    ENABLE_DEPRECATED_WIREGUARD_OUTBOUND=true ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS=true \
        /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" >/dev/null 2>&1
}

# Проверка 3 независимых слотов прокси: Слот 1 (Подписки HTTP), Слот 2 (my_nodes), Слот 3 (WARP + MASQUE)
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
        awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {found=1} END {exit !found}' "$CUSTOM_NODES_FILE" 2>/dev/null
}

count_my_nodes() {
    if [ -s "$CUSTOM_NODES_FILE" ] && ! grep -q '^proxies:[[:space:]]*\[\][[:space:]]*$' "$CUSTOM_NODES_FILE" 2>/dev/null; then
        awk 'NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {c++} END {print c+0}' "$CUSTOM_NODES_FILE" 2>/dev/null
    else
        echo "0"
    fi
    return 0
}

is_warp_enabled() {
    [ -f "$WARP_NODES_FILE" ] && grep -Eq '"type":[[:space:]]*"(wireguard|masque)"' "$WARP_NODES_FILE" 2>/dev/null
}

is_telegram_configured() {
    [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]
}

# Проверка состояния аппаратного Kill-Switch в /etc/nftables.nft
is_killswitch_enabled() {
    [ -f "$ALPINE_NFT_CONF" ] && grep -q "#KILLSWITCH_ACTIVE" "$ALPINE_NFT_CONF" 2>/dev/null
}

# Проверка состояния DHCP-сервера на шлюзе (AdGuard Home или legacy dnsmasq)
is_dhcp_server_enabled() {
    if [ -f "$AGH_CONF" ]; then
        if awk '/^dhcp:/{in_dhcp=1; next} in_dhcp && /^[a-zA-Z0-9_]+:/{in_dhcp=0} in_dhcp && /^[[:space:]]*enabled:[[:space:]]*true/{found=1} END{exit !found}' "$AGH_CONF" 2>/dev/null; then
            return 0
        fi
    fi
    [ -f "$ALPINE_DHCP_CONF" ] && pgrep dnsmasq >/dev/null 2>&1
}

# Формирование списка IP-исключений (bypass_devices.conf) для корректной работы DIRECT при включенном Kill-Switch
