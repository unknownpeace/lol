#!/bin/sh
get_agh_admin_user() {
    if [ -f "${AGH_CONF:-/etc/AdGuardHome/AdGuardHome.yaml}" ]; then
        sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "${AGH_CONF:-/etc/AdGuardHome/AdGuardHome.yaml}" 2>/dev/null | head -n 1 | tr -d ' \t\r\n"' || true
    fi
    return 0
}

# Освобождение порта 53 и отключение DHCPv4/v6/RA в OpenWrt dnsmasq/odhcpd для передачи DNS в AdGuard Home
prepare_openwrt_dnsmasq_for_adguard() {
    is_openwrt 2>/dev/null || return 0
    if command -v uci >/dev/null 2>&1; then
        uci set dhcp.@dnsmasq[0].port='0' 2>/dev/null || true
        uci set dhcp.lan.ignore='1' 2>/dev/null || true
        uci set dhcp.lan.dhcpv4='disabled' 2>/dev/null || true
        uci set dhcp.lan.dhcpv6='disabled' 2>/dev/null || true
        uci set dhcp.lan.ra='disabled' 2>/dev/null || true
        uci commit dhcp 2>/dev/null || true
    fi
    service_ctl odhcpd stop
    service_ctl odhcpd disable
    service_ctl dnsmasq restart || service_ctl dnsmasq stop || true
    return 0
}

# Автоматическая синхронизация DNS Rewrites (*.lan -> LAN_IP с enabled: true) в AdGuardHome.yaml
sync_agh_homelab_rewrites() {
    [ -z "${SSL_TYPE:-}" ] && load_gateway_env || true
    TARGET_LAN_IP="${1:-$(get_current_lan_ip)}"
    [ -f "$AGH_CONF" ] || return 0
    AGH_WAS_RUNNING="no"
    if pgrep AdGuardHome >/dev/null 2>&1; then
        AGH_WAS_RUNNING="yes"
        service_ctl adguardhome stop
    fi

    if is_openwrt 2>/dev/null; then
        DOMS_STR="adguard.lan zashboard.lan singbox.lan mihomo.lan panel.lan"
    else
        DOMS_STR="*.lan ca.lan adguard.lan zashboard.lan singbox.lan mihomo.lan panel.lan vaultwarden.lan forgejo.lan downloads.lan torrents.lan code.lan"
        if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
            DOMS_STR="${DOMS_STR} *.${SSL_DOMAIN} ${SSL_DOMAIN} vaultwarden.${SSL_DOMAIN} forgejo.${SSL_DOMAIN} downloads.${SSL_DOMAIN} torrents.${SSL_DOMAIN} code.${SSL_DOMAIN} adguard.${SSL_DOMAIN} zashboard.${SSL_DOMAIN} singbox.${SSL_DOMAIN} mihomo.${SSL_DOMAIN} panel.${SSL_DOMAIN}"
        fi
    fi

    awk -v lip="$TARGET_LAN_IP" -v dom_list="$DOMS_STR" '
        function print_rewrites() {
            print "  rewrites:"
            cnt = split(dom_list, doms, " ")
            for (i = 1; i <= cnt; i++) {
                print "    - domain: '\''" doms[i] "'\''"
                print "      answer: " lip
                print "      enabled: true"
            }
            wrote_rew = 1
        }
        BEGIN { seen_flt = 0; in_flt = 0; in_rew = 0; wrote_rew = 0 }
        /^filtering:[[:space:]]*\{/ {
            seen_flt = 1
            print "filtering:"
            line = $0
            sub(/^filtering:[[:space:]]*\{[[:space:]]*/, "", line)
            sub(/\}[[:space:]]*$/, "", line)
            n = split(line, kv, ",")
            has_prot = 0; has_filt = 0
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", kv[i])
                if (kv[i] != "") {
                    print "  " kv[i]
                    if (kv[i] ~ /^protection_enabled:/) has_prot = 1
                    if (kv[i] ~ /^filtering_enabled:/) has_filt = 1
                }
            }
            if (!has_prot) print "  protection_enabled: true"
            if (!has_filt) print "  filtering_enabled: true"
            print_rewrites()
            next
        }
        /^filtering:[[:space:]]*$/ {
            seen_flt = 1
            in_flt = 1
            print
            next
        }
        in_flt && /^[^[:space:]]/ {
            if (!wrote_rew) print_rewrites()
            in_flt = 0
            in_rew = 0
            print
            next
        }
        in_flt && /^[[:space:]]*rewrites:/ {
            print_rewrites()
            in_rew = 1
            next
        }
        in_rew {
            if (/^[[:space:]]*-/ || /^[[:space:]]+(domain|answer|enabled):/) {
                next
            } else {
                in_rew = 0
            }
        }
        { print }
        END {
            if (!seen_flt) {
                print "filtering:"
                print "  protection_enabled: true"
                print "  filtering_enabled: true"
                print_rewrites()
            } else if (in_flt && !wrote_rew) {
                print_rewrites()
            }
        }
    ' "$AGH_CONF" > "${AGH_CONF}.tmp.$$"
    atomic_commit_tmp "${AGH_CONF}.tmp.$$" "$AGH_CONF" 0600 "root:root" || true

    if [ "$AGH_WAS_RUNNING" = "yes" ]; then
        service_ctl adguardhome start || true
    fi
    return 0
}

# Обновление IP основного роутера и LAN IP для *.lan внутри AdGuardHome.yaml
update_agh_gateway_ip() {
    NEW_GW="$1"
    NEW_LAN="${2:-$(get_current_lan_ip)}"
    [ -f "$AGH_CONF" ] || return 0
    AGH_WAS_RUNNING="no"
    if pgrep AdGuardHome >/dev/null 2>&1; then
        AGH_WAS_RUNNING="yes"
        service_ctl adguardhome stop
    fi
    awk -v gw="$NEW_GW" '
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
    ' "$AGH_CONF" > "${AGH_CONF}.tmp.$$"
    atomic_commit_tmp "${AGH_CONF}.tmp.$$" "$AGH_CONF" 0600 "root:root" || true
    sync_agh_homelab_rewrites "$NEW_LAN"
    if [ "$AGH_WAS_RUNNING" = "yes" ]; then
        service_ctl adguardhome start || true
    fi
    return 0
}

# Безопасная очистка и экранирование ввода пользователя (от CRLF, кавычек и мусора буфера обмена)
