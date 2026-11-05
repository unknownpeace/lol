get_agh_admin_user() {
    if [ -f "${AGH_CONF:-/etc/AdGuardHome/AdGuardHome.yaml}" ]; then
        sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "${AGH_CONF:-/etc/AdGuardHome/AdGuardHome.yaml}" 2>/dev/null | head -n 1 | tr -d ' \t\r\n"' || true
    fi
    return 0
}

# Автоматическая синхронизация DNS Rewrites (*.lan -> LAN_IP с enabled: true) в AdGuardHome.yaml
sync_agh_homelab_rewrites() {
    TARGET_LAN_IP="${1:-$(get_current_lan_ip)}"
    [ -f "$AGH_CONF" ] || return 0
    AGH_WAS_RUNNING="no"
    if pgrep AdGuardHome >/dev/null 2>&1; then
        AGH_WAS_RUNNING="yes"
        rc-service adguardhome stop >/dev/null 2>&1 || /etc/init.d/adguardhome stop >/dev/null 2>&1 || true
    fi

    DOMS_STR="*.lan ca.lan adguard.lan zashboard.lan singbox.lan vaultwarden.lan forgejo.lan music.lan jellyfin.lan downloads.lan torrents.lan code.lan"
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        DOMS_STR="${DOMS_STR} *.${SSL_DOMAIN} ${SSL_DOMAIN} vaultwarden.${SSL_DOMAIN} forgejo.${SSL_DOMAIN} music.${SSL_DOMAIN} jellyfin.${SSL_DOMAIN} downloads.${SSL_DOMAIN} torrents.${SSL_DOMAIN} code.${SSL_DOMAIN} adguard.${SSL_DOMAIN} zashboard.${SSL_DOMAIN} singbox.${SSL_DOMAIN}"
    fi

    awk -v lip="$TARGET_LAN_IP" -v dom_list="$DOMS_STR" '
        BEGIN { in_flt=0; in_rew=0 }
        /^filtering:/ { in_flt=1; print; next }
        in_flt && /^[^[:space:]]/ { in_flt=0; in_rew=0; print; next }
        in_flt && /^[[:space:]]*rewrites:/ {
            print "  rewrites:"
            cnt = split(dom_list, doms, " ")
            for (i = 1; i <= cnt; i++) {
                print "    - domain: '\''" doms[i] "'\''"
                print "      answer: " lip
                print "      enabled: true"
            }
            in_rew=1
            next
        }
        in_rew {
            if (/^[[:space:]]*-/ || /^[[:space:]]+(domain|answer|enabled):/) {
                next
            } else {
                in_rew=0
            }
        }
        { print }
    ' "$AGH_CONF" > "${AGH_CONF}.tmp.$$"
    atomic_commit_tmp "${AGH_CONF}.tmp.$$" "$AGH_CONF" 0600 "root:root" || true

    if [ "$AGH_WAS_RUNNING" = "yes" ]; then
        rc-service adguardhome start >/dev/null 2>&1 || /etc/init.d/adguardhome start >/dev/null 2>&1 || true
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
        rc-service adguardhome stop >/dev/null 2>&1 || /etc/init.d/adguardhome stop >/dev/null 2>&1 || true
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
        rc-service adguardhome start >/dev/null 2>&1 || /etc/init.d/adguardhome start >/dev/null 2>&1 || true
    fi
    return 0
}

# Безопасная очистка и экранирование ввода пользователя (от CRLF, кавычек и мусора буфера обмена)
