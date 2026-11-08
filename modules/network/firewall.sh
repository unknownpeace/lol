get_nft_bypass_saddr_clause() {
    if [ ! -s "$USER_BYPASS_IPS" ]; then
        printf ""
        return 0
    fi
    BYP_CSV=$(awk '{
        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", $0);
        if ($0 != "" && $0 !~ /^#/) {
            if (c++) printf ", %s", $0;
            else printf "%s", $0;
        }
    }' "$USER_BYPASS_IPS" 2>/dev/null || true)
    if [ -n "$BYP_CSV" ]; then
        printf "ip saddr != { %s } " "$BYP_CSV"
    fi
    return 0
}

# Динамическое формирование списков разрешенных LAN-портов (Шлюз + активные сервисы Homelab) для nftables
get_homelab_nft_tcp_ports() {
    TCP_LIST="22, 53, 80, 443, 445, 3000, 5357, 7890, 9090, ${PORT_TORRENT_PEER}"
    printf "%s" "$TCP_LIST"
    return 0
}

get_homelab_nft_udp_ports() {
    UDP_LIST="53, 67, 443, 3702, 5353, 7890, ${PORT_TORRENT_PEER}"
    printf "%s" "$UDP_LIST"
    return 0
}

# Настройка нативного nftables на Alpine Linux (защита input_protect для Шлюза и Homelab + Kill-Switch 2.0)
sync_dns_firewall() {
    USE_DNS_REDIRECT="${1:-yes}"
    KS_STATE="${2:-keep}"
    LAN_IF=$(get_lan_ifname)

    if [ "$KS_STATE" = "keep" ]; then
        if is_killswitch_enabled; then
            KS_STATE="yes"
        else
            KS_STATE="no"
        fi
    fi

    BYP_SADDR_CLAUSE=$(get_nft_bypass_saddr_clause)
    LAN_TCP_PORTS=$(get_homelab_nft_tcp_ports)
    LAN_UDP_PORTS=$(get_homelab_nft_udp_ports)

    KS_COMMENT=""
    KS_RULE=""
    if [ "$KS_STATE" = "yes" ]; then
        KS_COMMENT="#KILLSWITCH_ACTIVE"
        KS_RULE="iifname \"${LAN_IF}\" oifname != { \"singbox-tun\", \"lo\" } ${BYP_SADDR_CLAUSE}ip daddr != { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } reject"
    fi

    DNS_RULE=""
    if [ "$USE_DNS_REDIRECT" = "yes" ]; then
        DNS_RULE="iifname \"${LAN_IF}\" meta l4proto { tcp, udp } th dport 53 redirect to :53"
    fi

    cat << NFT_ALPINE > "${ALPINE_NFT_CONF}.tmp.$$"
#!/usr/sbin/nft -f
${KS_COMMENT}

table inet gateway_fw
delete table inet gateway_fw

table inet gateway_fw {
    chain input_protect {
        type filter hook input priority filter - 5; policy accept;
        iifname "lo" accept
        ct state established,related accept
        meta l4proto { tcp, udp } th dport 853 reject
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16 } tcp dport { ${LAN_TCP_PORTS} } accept
        ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16 } udp dport { ${LAN_UDP_PORTS} } accept
        ip daddr { 224.0.0.251, 239.255.255.250 } udp dport { 3702, 5353 } accept
        tcp dport { 80, 443, 445, 3000, 3001, 5357, 7890, 8081, 8222, 8443, 9090, 9091 } drop
        udp dport { 443, 3702, 5353, 7890 } drop
    }

    chain forward_mss {
        type filter hook forward priority mangle; policy accept;
        oifname "singbox-tun" tcp flags syn tcp option maxseg size set rt mtu
        iifname "singbox-tun" tcp flags syn tcp option maxseg size set rt mtu
    }

    chain forward_filter {
        type filter hook forward priority filter - 5; policy accept;
        meta nfproto ipv6 drop
        iifname "${LAN_IF}" meta l4proto { tcp, udp } th dport 853 reject
        ${KS_RULE}
    }

    chain prerouting_dns {
        type nat hook prerouting priority dstnat - 5; policy accept;
        ${DNS_RULE}
    }

    chain postrouting_nat {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "${LAN_IF}" masquerade
    }
}
NFT_ALPINE
    chmod +x "${ALPINE_NFT_CONF}.tmp.$$" 2>/dev/null || true
    if ! command -v nft >/dev/null 2>&1; then
        rm -f "${ALPINE_NFT_CONF}.tmp.$$"
        return 0
    fi
    if nft --check -f "${ALPINE_NFT_CONF}.tmp.$$" >/dev/null 2>&1; then
        mv -f "${ALPINE_NFT_CONF}.tmp.$$" "$ALPINE_NFT_CONF"
        nft -f "$ALPINE_NFT_CONF" 2>/dev/null || true
    else
        rm -f "${ALPINE_NFT_CONF}.tmp.$$"
        echo "${C_RED}[X] Ошибка проверки синтаксиса nftables! Сохранена предыдущая конфигурация.${C_RES}" >&2
        return 1
    fi
    rc-update add nftables default >/dev/null 2>&1 || true
    rc-service nftables start >/dev/null 2>&1 || true
    return 0
}

# Вычисление актуальных метрик загрузки ОЗУ и заполнения хранилища /srv/storage
