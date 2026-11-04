configure_smart_dhcp() {
    DHCP_MODE="${1:-off}"
    CUR_LAN_IP=$(get_current_lan_ip)
    LAN_IF=$(get_lan_ifname)
    LAN_SUB="${CUR_LAN_IP%.*}"

    if [ "$DHCP_MODE" = "on" ]; then
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
        echo "${C_GRN}[✓] Умный DHCP-сервер на Alpine ВКЛЮЧЕН (Шлюз и DNS: ${CUR_LAN_IP}, пул .100-.239).${C_RES}"
        echo "    Не забудьте отключить DHCP-сервер на основном роутере провайдера!"
    else
        rm -f "$ALPINE_DHCP_CONF" 2>/dev/null || true
        service_ctl dnsmasq stop
        service_ctl dnsmasq disable
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

    cat << SW_ALP > /tmp/switch_lan_ip.sh
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
rm -f /tmp/switch_lan_ip.sh
SW_ALP
    chmod +x /tmp/switch_lan_ip.sh

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
        nohup /tmp/switch_lan_ip.sh >/dev/null 2>&1 &
    else
        ui_box_bottom
        /tmp/switch_lan_ip.sh
    fi
    return 0
}

# Проверка, включено ли автообновление и Watchdog в cron
