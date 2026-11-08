scan_lan_subnet() {
    CUR_LAN=$(get_current_lan_ip)
    LAN_SUB="${CUR_LAN%.*}"
    echo "Сканирование подсети ${LAN_SUB}.0/24 (опрос живых устройств ~1.5 сек)..."
    I_HOST=1
    while [ "$I_HOST" -le 254 ]; do
        ping -c 1 -W 1 "${LAN_SUB}.${I_HOST}" >/dev/null 2>&1 &
        if [ $((I_HOST % 64)) -eq 0 ]; then
            wait 2>/dev/null || true
        fi
        I_HOST=$((I_HOST + 1))
    done
    wait 2>/dev/null || true
    return 0
}

# Авто-сканер живых устройств в локальной сети (ARP + DHCP Leases Alpine Linux) для Пункта 8
discover_lan_devices() {
    load_gateway_env
    CUR_LAN=$(get_current_lan_ip)
    rm -f "$LAN_SCAN_CACHE"
    touch "$LAN_SCAN_CACHE"

    LEASE_F=""
    if [ -f "$AGH_LEASES_JSON" ]; then
        # Конвертируем AdGuard Home leases.json во временный формат ip mac hostname
        LEASE_F="/tmp/agh_leases.tmp"
        if command -v jq >/dev/null 2>&1; then
            jq -r '.leases[]? | [0, .mac, .ip, (.hostname // "*")] | @tsv' "$AGH_LEASES_JSON" > "$LEASE_F" 2>/dev/null || true
        elif command -v python3 >/dev/null 2>&1; then
            python3 -c "
import json
try:
    with open('${AGH_LEASES_JSON}') as f:
        data = json.load(f)
    with open('${LEASE_F}', 'w') as out:
        for item in data.get('leases', []):
            ip = item.get('ip', '')
            mac = item.get('mac', '')
            host = item.get('hostname', '*') or '*'
            if ip and mac:
                out.write(f'0 {mac} {ip} {host}\n')
except Exception:
    pass
" 2>/dev/null || true
        fi
    elif [ -f /var/lib/misc/dnsmasq.leases ]; then
        LEASE_F="/var/lib/misc/dnsmasq.leases"
    fi

    echo " ${C_CYN}--- Обнаруженные устройства в локальной сети (ARP + DHCP) ---${C_RES}"
    # shellcheck disable=SC2086
    awk -v gw="$GW_IP" -v self="$CUR_LAN" -v out_cache="$LAN_SCAN_CACHE" \
        -v byp_f="$USER_BYPASS_IPS" -v vpn_f="$USER_FORCE_PROXY_IPS" \
        -v c_cyn="$C_CYN" -v c_grn="$C_GRN" -v c_yel="$C_YEL" -v c_dim="$C_DIM" -v c_res="$C_RES" '
        BEGIN {
            while ((getline line < byp_f) > 0) {
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
                if (line != "") byp[line] = 1
            }
            close(byp_f)
            while ((getline line < vpn_f) > 0) {
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
                if (line != "") vpn[line] = 1
            }
            close(vpn_f)
        }
        FILENAME ~ /leases$/ {
            ip = $3; mac = tolower($2); host = $4
            if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && ip != self) {
                ips[ip] = 1
                if (mac != "") macs[ip] = mac
                if (host != "" && host != "*") names[ip] = host
            }
            next
        }
        FILENAME == "/proc/net/arp" && FNR > 1 {
            ip = $1; flags = $3; mac = tolower($4)
            if (ip != self && flags != "0x0" && mac != "00:00:00:00:00:00") {
                ips[ip] = 1
                if (macs[ip] == "") macs[ip] = mac
            }
            next
        }
        END {
            idx = 0
            for (ip in ips) {
                idx++
                m = (macs[ip] != "") ? macs[ip] : "неизвестен"
                n = (names[ip] != "") ? names[ip] : "Устройство LAN"
                if (ip == gw) n = "Основной роутер (" n ")"
                st = c_dim "[По правилам]" c_res
                if (byp[ip]) st = c_yel "[В ОБХОДЕ: DIRECT]" c_res
                if (vpn[ip]) st = c_grn "[В FULL-VPN]" c_res
                printf "  %s[%d]%s %-15s | %-17s | %-22s %s\n", c_cyn, idx, c_res, ip, m, n, st
                print ip > out_cache
            }
            if (idx == 0) {
                printf "  %s(активные соседи в ARP/DHCP пока не обнаружены — нажмите [s] для опроса сети)%s\n", c_dim, c_res
            }
        }
    ' $LEASE_F /proc/net/arp 2>/dev/null || true
    return 0
}

# Преобразование ввода пользователя (IP или номер из авто-сканера LAN) в IPv4
resolve_device_ip_input() {
    RAW_IN=$(printf "%s" "$1" | tr -d ' \t\r\n')
    [ -z "$RAW_IN" ] && return 1
    case "$RAW_IN" in
        *[!0-9]*)
            if is_valid_ipv4 "$RAW_IN"; then
                printf "%s" "$RAW_IN"
                return 0
            fi
            return 1
            ;;
        *)
            if [ -s "$LAN_SCAN_CACHE" ]; then
                PICKED_IP=$(awk -v target="$RAW_IN" 'NR == target {print $1; exit}' "$LAN_SCAN_CACHE" 2>/dev/null)
                if [ -n "$PICKED_IP" ] && is_valid_ipv4 "$PICKED_IP"; then
                    printf "%s" "$PICKED_IP"
                    return 0
                fi
            fi
            return 1
            ;;
    esac
}

# Интерактивный «Детектор сайта» (Рентген маршрута домена: AdGuard + FakeIP + Homelab .lan + TLS-пинг)
