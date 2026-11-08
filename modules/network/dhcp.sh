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
    CUR_LAN_IP=$(get_current_lan_ip)
    LAN_IF=$(get_lan_ifname)
    LAN_SUB="${CUR_LAN_IP%.*}"

    if [ "$DHCP_MODE" = "on" ]; then
        # Защитная проверка: если в сети уже есть активный DHCP-сервер, запрещаем включение
        if detect_external_dhcp_server "$LAN_IF"; then
            echo "${C_RED}[X] Ошибка: В локальной сети (${LAN_IF}) обнаружен активный сторонний DHCP-сервер (роутер)!${C_RES}"
            echo "    Включение DHCP на AdGuard Home отменено во избежание конфликта адресов."
            echo "    Сначала отключите DHCP-сервер в настройках вашего роутера."
            return 1
        fi

        if [ -f "$AGH_CONF" ]; then
            echo "Настройка встроенного DHCPv4 в AdGuard Home..."
            rc-service adguardhome stop >/dev/null 2>&1 || true
            sleep 1

            awk -v iface="${LAN_IF}" -v gw="${CUR_LAN_IP}" -v r_start="${LAN_SUB}.100" -v r_end="${LAN_SUB}.239" '
            BEGIN { in_dhcp = 0 }
            /^dhcp:/ {
                in_dhcp = 1
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
            ' "$AGH_CONF" > "${AGH_CONF}.tmp.$$" 2>/dev/null || true

            if [ -s "${AGH_CONF}.tmp.$$" ]; then
                mv -f "${AGH_CONF}.tmp.$$" "$AGH_CONF"
            else
                rm -f "${AGH_CONF}.tmp.$$" 2>/dev/null || true
            fi

            rc-service adguardhome start >/dev/null 2>&1 || true

            # Удаляем legacy dnsmasq если остался
            if [ -f "$ALPINE_DHCP_CONF" ]; then
                rm -f "$ALPINE_DHCP_CONF" 2>/dev/null || true
                service_ctl dnsmasq stop || true
                service_ctl dnsmasq disable || true
            fi

            echo "${C_GRN}[✓] DHCP-сервер AdGuard Home ВКЛЮЧЕН (Шлюз: ${CUR_LAN_IP}, DNS: ${CUR_LAN_IP}, пул ${LAN_SUB}.100-.239).${C_RES}"
            return 0
        fi

        # Фоллбэк на dnsmasq если AGH еще не установлен
        if ! command -v dnsmasq >/dev/null 2>&1; then
            echo "Установка пакета dnsmasq для DHCP-сервера..."
            apk update >/dev/null 2>&1 || true
            apk add dnsmasq >/dev/null 2>&1 || true
        fi
        mkdir -p /etc/dnsmasq.d /var/lib/misc
        cat << ALP_DHCP > "$ALPINE_DHCP_CONF"
port=5353
interface=${LAN_IF}
bind-interfaces
dhcp-authoritative
dhcp-range=${LAN_SUB}.100,${LAN_SUB}.239,255.255.255.0,12h
dhcp-option=3,${CUR_LAN_IP}
dhcp-option=6,${CUR_LAN_IP}
ALP_DHCP
        service_ctl dnsmasq enable
        service_ctl dnsmasq restart
        echo "${C_GRN}[✓] DHCP-сервер на Alpine ВКЛЮЧЕН (Шлюз и DNS: ${CUR_LAN_IP}, пул .100-.239).${C_RES}"
    else
        if [ -f "$AGH_CONF" ]; then
            rc-service adguardhome stop >/dev/null 2>&1 || true
            sleep 1
            sed -i '/^dhcp:/,/^[a-zA-Z0-9_]\+:/s/enabled: true/enabled: false/' "$AGH_CONF" 2>/dev/null || true
            rc-service adguardhome start >/dev/null 2>&1 || true
        fi
        rm -f "$ALPINE_DHCP_CONF" 2>/dev/null || true
        service_ctl dnsmasq stop || true
        service_ctl dnsmasq disable || true
        echo "${C_GRN}[✓] DHCP-сервер на Alpine ВЫКЛЮЧЕН (классический режим Sidecar).${C_RES}"
    fi
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

# Безопасная смена LAN IP шлюза и/или IP основного роутера на Alpine Linux (с обновлением *.lan в AdGuard Home)
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

    LAN_SUBNET="${TARGET_LAN_IP%.*}"
    GW_SUBNET="${TARGET_GW_IP%.*}"
    if [ "$LAN_SUBNET" != "$GW_SUBNET" ]; then
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
    [ -f "$SB_CONF" ] && generate_singbox_config || true

    write_alpine_static_interfaces "$LAN_IF" "$TARGET_LAN_IP" "$GW_IP"
    if [ -f "$ALPINE_DHCP_CONF" ]; then
        configure_smart_dhcp "on" >/dev/null 2>&1 || true
    fi

    SW_SCRIPT="/tmp/switch_lan_ip.$$.sh"
    cat << SW_ALP > "$SW_SCRIPT"
#!/bin/sh
sleep 1
rc-service sing-box stop >/dev/null 2>&1 || true
killall -9 udhcpc >/dev/null 2>&1 || true
if [ "${TARGET_LAN_IP}" != "${CUR_LAN_IP}" ]; then
    ip -4 addr flush dev ${LAN_IF} >/dev/null 2>&1 || true
fi
ip -4 addr replace ${TARGET_LAN_IP}/24 dev ${LAN_IF} >/dev/null 2>&1 || true
ip link set ${LAN_IF} up >/dev/null 2>&1 || true
ip -4 route replace default via ${GW_IP} dev ${LAN_IF} >/dev/null 2>&1 || true
sleep 2
nft -f ${ALPINE_NFT_CONF} >/dev/null 2>&1 || true
rc-service sing-box start >/dev/null 2>&1 || true
rc-service adguardhome restart >/dev/null 2>&1 || true
rc-service caddy reload >/dev/null 2>&1 || rc-service caddy restart >/dev/null 2>&1 || true
rc-service samba restart >/dev/null 2>&1 || true
rc-service wsdd restart >/dev/null 2>&1 || true
rc-service avahi-daemon restart >/dev/null 2>&1 || true
rm -f "$0" 2>/dev/null || true
SW_ALP
    chmod 700 "$SW_SCRIPT"

    write_resolv_conf "nameserver 127.0.0.1
nameserver ${GW_IP}
nameserver 77.88.8.8"

    ui_box_bottom
    echo "${C_GRN}[✓] Сетевые настройки успешно сохранены (${OS_NAME}):${C_RES}"
    echo " • Новый IP сервера (${LAN_IF}):   ${TARGET_LAN_IP} (маска 255.255.255.0)"
    echo " • IP основного роутера:     ${GW_IP}"
    echo " • Панель Sing-Box Extended: http://${TARGET_LAN_IP}:9090/ui (https://${DOM_ZASHBOARD})"
    echo " • Панель AdGuard Home:      http://${TARGET_LAN_IP}:3000 (https://${DOM_ADGUARD})"
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

# Проверка, включено ли автообновление и Watchdog в cron
