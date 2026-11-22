#!/bin/sh
# Зондирование сети на наличие активного стороннего DHCP-сервера (роутера)
detect_external_dhcp_server() {
    T_IF="${1:-$(get_lan_ifname)}"
    # Быстрый опрос сети через встроенный udhcpc (таймаут 2 сек, без изменения IP)
    DHCP_OUT=$(udhcpc -i "$T_IF" -n -q -t 1 -T 2 -s /bin/true 2>&1 || true)
    if echo "$DHCP_OUT" | grep -qi "lease of\|obtained\|offered"; then
        return 0 # Найден сторонний DHCP
    fi
    return 1 # Сторонний DHCP не обнаружен
}

configure_smart_dhcp() {
    DHCP_MODE="${1:-off}"
    CUR_LAN_IP="${2:-$(get_current_lan_ip)}"
    LAN_IF=$(get_lan_ifname)
    LAN_SUB="${CUR_LAN_IP%.*}"

    if [ "$DHCP_MODE" = "on" ]; then
        LOCAL_DHCP_WAS_ON="no"
        if is_dhcp_server_enabled; then
            LOCAL_DHCP_WAS_ON="yes"
            service_ctl adguardhome stop >/dev/null 2>&1 || true
            sleep 1
        fi

        # Защитная проверка: если в сети уже есть активный DHCP-сервер, запрещаем включение
        if detect_external_dhcp_server "$LAN_IF"; then
            [ "$LOCAL_DHCP_WAS_ON" = "yes" ] && service_ctl adguardhome start >/dev/null 2>&1 || true
            echo "${C_RED}[X] Ошибка: В локальной сети (${LAN_IF}) обнаружен активный сторонний DHCP-сервер (роутер)!${C_RES}"
            echo "    Включение DHCP на AdGuard Home отменено во избежание конфликта адресов."
            echo "    Сначала отключите DHCP-сервер в настройках вашего роутера."
            return 1
        fi

        if [ -f "$AGH_CONF" ]; then
            echo "Настройка встроенного DHCPv4 в AdGuard Home..."
            if [ "$LOCAL_DHCP_WAS_ON" != "yes" ]; then
                service_ctl adguardhome stop
                sleep 1
            fi

            awk -v iface="${LAN_IF}" -v gw="${CUR_LAN_IP}" -v r_start="${LAN_SUB}.100" -v r_end="${LAN_SUB}.239" '
            function print_dhcp_block() {
                print "dhcp:"
                print "  enabled: true"
                print "  interface_name: " iface
                print "  local_domain_name: lan"
                print "  dhcpv4:"
                print "    gateway_ip: " gw
                print "    subnet_mask: 255.255.255.0"
                print "    range_start: " r_start
                print "    range_end: " r_end
                print "    lease_duration: 86400"
                print "    icmp_timeout_msec: 1000"
                print "    options: []"
                print "  dhcpv6:"
                print "    range_start: \"\""
                print "    lease_duration: 86400"
                print "    ra_slaac_only: false"
                print "    ra_allow_slaac: false"
            }
            BEGIN { in_dhcp = 0; seen_dhcp = 0 }
            /^dhcp:/ {
                in_dhcp = 1
                seen_dhcp = 1
                print_dhcp_block()
                next
            }
            in_dhcp {
                if ($0 ~ /^[a-zA-Z0-9_]+:/) {
                    in_dhcp = 0
                    print $0
                }
                next
            }
            !in_dhcp {
                print $0
            }
            END {
                if (!seen_dhcp) {
                    print_dhcp_block()
                }
            }
            ' "$AGH_CONF" > "${AGH_CONF}.tmp.$$" 2>/dev/null || true

            if [ -s "${AGH_CONF}.tmp.$$" ]; then
                chmod 600 "${AGH_CONF}.tmp.$$" 2>/dev/null || true
                mv -f "${AGH_CONF}.tmp.$$" "$AGH_CONF"
            else
                rm -f "${AGH_CONF}.tmp.$$" 2>/dev/null || true
            fi

            is_openwrt 2>/dev/null && prepare_openwrt_dnsmasq_for_adguard
            service_ctl adguardhome start || true

            echo "${C_GRN}[✓] DHCP-сервер AdGuard Home ВКЛЮЧЕН (Шлюз: ${CUR_LAN_IP}, DNS: ${CUR_LAN_IP}, пул ${LAN_SUB}.100-.239).${C_RES}"
            return 0
        fi

        echo "${C_RED}[X] Ошибка: Конфигурация AdGuard Home (${AGH_CONF}) не найдена!${C_RES}"
        echo "    Сначала выполните первичную настройку шлюза (gateway install)."
        return 1
    else
        if [ -f "$AGH_CONF" ]; then
            service_ctl adguardhome stop
            sleep 1
            awk '
            BEGIN { in_dhcp = 0 }
            /^dhcp:/ { in_dhcp = 1; print; next }
            in_dhcp && /^[a-zA-Z0-9_]+:/ { in_dhcp = 0 }
            in_dhcp && /^[[:space:]]*enabled:[[:space:]]*true/ { sub(/true/, "false") }
            { print }
            ' "$AGH_CONF" > "${AGH_CONF}.tmp.$$" 2>/dev/null || true
            if [ -s "${AGH_CONF}.tmp.$$" ]; then
                chmod 600 "${AGH_CONF}.tmp.$$" 2>/dev/null || true
                mv -f "${AGH_CONF}.tmp.$$" "$AGH_CONF"
            else
                rm -f "${AGH_CONF}.tmp.$$" 2>/dev/null || true
            fi
            is_openwrt 2>/dev/null && prepare_openwrt_dnsmasq_for_adguard
            service_ctl adguardhome start || true
        fi
        echo "${C_GRN}[✓] DHCP-сервер на ${OS_NAME:-шлюзе} ВЫКЛЮЧЕН (классический режим Sidecar).${C_RES}"
    fi
    return 0
}

# Проверка занятости целевого IP в локальной сети (защита от конфликта с уже работающим шлюзом)
check_ip_conflict_on_lan() {
    PROBE_IP="$1"
    SELF_IP="${2:-$(get_current_lan_ip)}"
    [ -z "$PROBE_IP" ] || [ "$PROBE_IP" = "$SELF_IP" ] && return 0
    if ping -c 1 -W 1 "$PROBE_IP" >/dev/null 2>&1 || \
       ip neigh show "$PROBE_IP" 2>/dev/null | grep -qE "lladdr[[:space:]]+[0-9a-fA-F:]{17}"; then
        echo "${C_RED}[X] КОНФЛИКТ АДРЕСОВ: IP ${PROBE_IP} уже используется другим устройством в сети!${C_RES}"
        echo "    Выберите свободный адрес, чтобы не нарушить работу основного роутера или второго шлюза."
        return 1
    fi
    return 0
}

# Запись статической конфигурации сети UCI для OpenWrt
write_openwrt_static_network() {
    O_IP="$1"
    O_GW="$2"
    command -v uci >/dev/null 2>&1 || return 0
    uci set network.lan.proto='static'
    uci set network.lan.ipaddr="$O_IP"
    uci set network.lan.netmask='255.255.255.0'
    uci set network.lan.gateway="$O_GW"
    uci -q delete network.lan.dns
    uci add_list network.lan.dns='127.0.0.1'
    uci add_list network.lan.dns="$O_GW"
    uci commit network
    return 0
}

# Запись статической конфигурации сети в /etc/network/interfaces для Alpine Linux
write_alpine_static_interfaces() {
    A_IF="$1"
    A_IP="$2"
    A_GW="$3"
    cat << NET_ALP > /etc/network/interfaces
auto lo
iface lo inet loopback

auto ${A_IF}
iface ${A_IF} inet static
    address ${A_IP}
    netmask 255.255.255.0
    gateway ${A_GW}
NET_ALP
    return 0
}

# Безопасная смена LAN IP шлюза и/или IP основного роутера (Alpine / OpenWrt)
apply_network_ips() {
    TARGET_LAN_IP="$1"
    TARGET_GW_IP="$2"

    CUR_LAN_IP=$(get_current_lan_ip)
    LAN_IF=$(get_lan_ifname)
    load_gateway_env

    [ -z "$TARGET_LAN_IP" ] && TARGET_LAN_IP="$CUR_LAN_IP"
    [ -z "$TARGET_GW_IP" ] && TARGET_GW_IP="$GW_IP"

    if ! is_valid_ipv4 "$TARGET_LAN_IP"; then
        echo "${C_RED}[X] Ошибка: Некорректный IPv4-адрес шлюза (${TARGET_LAN_IP})!${C_RES}"
        return 1
    fi

    if ! is_valid_ipv4 "$TARGET_GW_IP"; then
        echo "${C_RED}[X] Ошибка: Некорректный IPv4-адрес основного роутера (${TARGET_GW_IP})!${C_RES}"
        return 1
    fi

    if [ "$TARGET_LAN_IP" = "$TARGET_GW_IP" ]; then
        echo "${C_RED}[X] Ошибка: IP шлюза (${TARGET_LAN_IP}) не может совпадать с IP основного роутера (${TARGET_GW_IP})!${C_RES}"
        return 1
    fi

    check_ip_conflict_on_lan "$TARGET_LAN_IP" "$CUR_LAN_IP" || return 1

    LAN_SUBNET="${TARGET_LAN_IP%.*}"
    GW_SUBNET="${TARGET_GW_IP%.*}"
    if [ "$LAN_SUBNET" != "$GW_SUBNET" ]; then
        if [ ! -t 0 ] || [ "${IS_UNATTENDED:-no}" = "yes" ]; then
            echo "${C_RED}[X] Ошибка: Подсеть шлюза (${LAN_SUBNET}.x) отличается от подсети роутера (${GW_SUBNET}.x) в неинтерактивном режиме!${C_RES}"
            return 1
        fi
        echo "${C_YEL}[!] Внимание: Подсеть шлюза (${LAN_SUBNET}.x) отличается от подсети роутера (${GW_SUBNET}.x)!${C_RES}"
        printf "Введите IP основного роутера в новой подсети [Enter = %s.1 / отмена = n]: " "$LAN_SUBNET"
        read -r FIX_GW < /dev/tty || true
        FIX_GW=$(printf "%s" "$FIX_GW" | tr -d ' \t\r\n')
        if [ "$FIX_GW" = "n" ] || [ "$FIX_GW" = "N" ]; then
            echo "[i] Смена IP отменена."
            return 1
        fi
        [ -z "$FIX_GW" ] && FIX_GW="${LAN_SUBNET}.1"
        if ! is_valid_ipv4 "$FIX_GW" || [ "$FIX_GW" = "$TARGET_LAN_IP" ]; then
            echo "${C_RED}[X] Некорректный или конфликтующий IP основного роутера (${FIX_GW}).${C_RES}"
            return 1
        fi
        TARGET_GW_IP="$FIX_GW"
    fi

    GW_IP="$TARGET_GW_IP"
    save_gateway_env
    update_agh_gateway_ip "$GW_IP" "$TARGET_LAN_IP"
    ACT_SVC=$(get_active_core_service)
    if [ -f "$SB_CONF" ] || [ -f "$MIHOMO_CONF" ]; then
        GW_TARGET_LAN_IP_OVERRIDE="$TARGET_LAN_IP"
        export GW_TARGET_LAN_IP_OVERRIDE
        core_generate_config || true
        unset GW_TARGET_LAN_IP_OVERRIDE
    fi

    if is_openwrt 2>/dev/null; then
        write_openwrt_static_network "$TARGET_LAN_IP" "$GW_IP"
    else
        write_alpine_static_interfaces "$LAN_IF" "$TARGET_LAN_IP" "$GW_IP"
    fi
    if is_dhcp_server_enabled; then
        configure_smart_dhcp "on" "$TARGET_LAN_IP" >/dev/null 2>&1 || true
    fi

    ensure_gateway_runtime_dir || return 1
    SW_SCRIPT=$(mktemp "${GATEWAY_RUNTIME_DIR:-/run/gateway}/switch_lan_ip.XXXXXX" 2>/dev/null || printf "%s" "${GATEWAY_RUNTIME_DIR:-/run/gateway}/switch_lan_ip.$$.sh")
    if is_openwrt 2>/dev/null; then
        cat << SW_OWRT > "$SW_SCRIPT"
#!/bin/sh
sleep 1
/etc/init.d/${ACT_SVC} stop >/dev/null 2>&1 || true
/etc/init.d/network reload >/dev/null 2>&1 || true
sleep 2
ip -4 route replace default via ${GW_IP} dev ${LAN_IF} >/dev/null 2>&1 || true
printf "nameserver 127.0.0.1\nnameserver %s\nnameserver 77.88.8.8\n" "${GW_IP}" > /tmp/resolv.conf.tmp.\$\$ 2>/dev/null && \
    chmod 0644 /tmp/resolv.conf.tmp.\$\$ 2>/dev/null && \
    mv -f /tmp/resolv.conf.tmp.\$\$ /tmp/resolv.conf 2>/dev/null || true
fw4 reload >/dev/null 2>&1 || /etc/init.d/firewall reload >/dev/null 2>&1 || true
/etc/init.d/${ACT_SVC} start >/dev/null 2>&1 || true
/etc/init.d/adguardhome restart >/dev/null 2>&1 || true
rm -f "\$0" 2>/dev/null || true
SW_OWRT
    else
        cat << SW_ALP > "$SW_SCRIPT"
#!/bin/sh
sleep 1
rc-service ${ACT_SVC} stop >/dev/null 2>&1 || true
killall -9 udhcpc >/dev/null 2>&1 || true
if [ "${TARGET_LAN_IP}" != "${CUR_LAN_IP}" ]; then
    ip -4 addr flush dev ${LAN_IF} >/dev/null 2>&1 || true
fi
ip -4 addr replace ${TARGET_LAN_IP}/24 dev ${LAN_IF} >/dev/null 2>&1 || true
ip link set ${LAN_IF} up >/dev/null 2>&1 || true
ip -4 route replace default via ${GW_IP} dev ${LAN_IF} >/dev/null 2>&1 || true
sleep 2
nft -f ${ALPINE_NFT_CONF} >/dev/null 2>&1 || true
rc-service ${ACT_SVC} start >/dev/null 2>&1 || true
rc-service adguardhome restart >/dev/null 2>&1 || true
rc-service caddy reload >/dev/null 2>&1 || rc-service caddy restart >/dev/null 2>&1 || true
rc-service samba restart >/dev/null 2>&1 || true
rc-service wsdd restart >/dev/null 2>&1 || true
rc-service avahi-daemon restart >/dev/null 2>&1 || true
rm -f "\$0" 2>/dev/null || true
SW_ALP
    fi
    chmod 700 "$SW_SCRIPT"

    write_resolv_conf "nameserver 127.0.0.1
nameserver ${GW_IP}
nameserver 77.88.8.8"

    ui_box_top "✅ СЕТЕВЫЕ НАСТРОЙКИ СОХРАНЕНЫ (${OS_NAME})"
    ui_box_row "${C_GRN}[✓] Сетевые настройки успешно сохранены (${OS_NAME}):${C_RES}"
    echo " • Новый IP сервера (${LAN_IF}):   ${TARGET_LAN_IP} (маска 255.255.255.0)"
    echo " • IP основного роутера:     ${GW_IP}"
    echo " • Панель $(get_active_ui_name): http://${TARGET_LAN_IP}:9090/ui"
    echo " • Панель AdGuard Home:      http://${TARGET_LAN_IP}:3000"
    echo " • Локальные домены *.lan:   перенаправлены на ${TARGET_LAN_IP}"

    if [ "$TARGET_LAN_IP" != "$CUR_LAN_IP" ]; then
        ui_box_sep
        echo "${C_YEL}[!] ВНИМАНИЕ: IP сервера изменился (${CUR_LAN_IP} -> ${TARGET_LAN_IP})!${C_RES}"
        echo " 1. Переподключитесь по SSH: ssh root@${TARGET_LAN_IP}"
        echo " 2. Обновите адрес шлюза/DNS на устройствах или в роутере на ${TARGET_LAN_IP}!"
        ui_box_bottom
        nohup "$SW_SCRIPT" >/dev/null 2>&1 &
    else
        ui_box_bottom
        "$SW_SCRIPT"
    fi
    return 0
}
