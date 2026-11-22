#!/bin/sh
# ==============================================================================
# Модуль LXC (Linux Containers) для Universal Gateway & Homelab
# Полноценная виртуализация ОС на базе пространств имен ядра и cgroups v2.
# Поддержка официальных шаблонов (images.linuxcontainers.org), снимков (снапшотов),
# сетевой изоляции (lxcbr0 / macvlan) и интеграции с хранилищем /srv/storage/lxc.
# ==============================================================================

LXC_STORAGE_DIR="/srv/storage/lxc"
LXC_VAR_LIB="/var/lib/lxc"

_lxc_is_valid_name() {
    _nm="${1:-}"
    [ -n "$_nm" ] || return 1
    case "$_nm" in
        .|..|-*) return 1 ;;
    esac
    printf "%s" "$_nm" | grep -Eq '^[A-Za-z0-9_-]{1,64}$'
}

_lxc_is_valid_ipv4() {
    [ -n "${1:-}" ] && is_valid_ipv4 "$1"
}

_lxc_apply_macvlan_config() {
    _mv_conf="$1"
    LAN_IF=$(get_lan_ifname)
    MAC_TAIL=$(_lxc_gen_mac_tail) || {
        ui_warn_msg "Не удалось сгенерировать случайный MAC-адрес."
        return 1
    }
    sed -i '/lxc\.net\.0\./d' "$_mv_conf"
    cat << NET_MACVLAN >> "$_mv_conf"
lxc.net.0.type = macvlan
lxc.net.0.macvlan.mode = bridge
lxc.net.0.link = ${LAN_IF}
lxc.net.0.flags = up
lxc.net.0.hwaddr = 10:66:6a:${MAC_TAIL}
NET_MACVLAN
    return 0
}

_lxc_is_valid_ipv4_cidr() {
    _cidr="${1:-}"
    [ -n "$_cidr" ] || return 1
    case "$_cidr" in
        */*)
            _ip_p="${_cidr%%/*}"
            _pfx="${_cidr#*/}"
            _lxc_is_valid_ipv4 "$_ip_p" || return 1
            case "$_pfx" in
                ''|*[!0-9]*) return 1 ;;
            esac
            [ "$_pfx" -ge 1 ] && [ "$_pfx" -le 32 ] || return 1
            printf "%s/%s" "$_ip_p" "$_pfx"
            return 0
            ;;
        *)
            _lxc_is_valid_ipv4 "$_cidr" || return 1
            printf "%s/24" "$_cidr"
            return 0
            ;;
    esac
}

_lxc_normalize_mem_limit() {
    _ml=$(printf "%s" "${1:-}" | tr -d ' \t\r\n')
    case "$_ml" in
        ""|none|0)
            printf "none"
            return 0
            ;;
    esac
    if printf "%s" "$_ml" | grep -Eq '^[1-9][0-9]*[KkMmGg]$'; then
        printf "%s" "$_ml"
        return 0
    fi
    if printf "%s" "$_ml" | grep -Eq '^[1-9][0-9]*$'; then
        printf "%sM" "$_ml"
        return 0
    fi
    return 1
}

_lxc_gen_mac_tail() {
    _mt=$(hexdump -n 3 -e '/1 ":%02x"' /dev/urandom 2>/dev/null | cut -c 2- || true)
    if [ -z "$_mt" ]; then
        _mt=$(od -An -N3 -tx1 /dev/urandom 2>/dev/null | awk '{printf "%s:%s:%s", $1, $2, $3}' || true)
    fi
    if printf "%s" "$_mt" | grep -Eq '^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$'; then
        printf "%s" "$_mt"
        return 0
    fi
    return 1
}

# Определение архитектуры для шаблонов images.linuxcontainers.org
get_lxc_system_arch() {
    ARCH=$(uname -m 2>/dev/null || echo "x86_64")
    case "$ARCH" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7*)  echo "armhf" ;;
        *)       echo "$ARCH" ;;
    esac
}

# Инициализация и проверка подсистемы LXC (пакеты, cgroups v2, bridge lxcbr0, хранилище)
ensure_lxc_subsystem() {
    SILENT="${1:-no}"
    [ "$SILENT" != "yes" ] && ui_info_msg "Проверка и подготовка подсистемы контейнеров LXC..."

    # 1. Проверка системных пакетов
    MISSING_LXC_PKGS=""
    command -v lxc-create >/dev/null 2>&1 || MISSING_LXC_PKGS="$MISSING_LXC_PKGS lxc lxc-openrc lxc-bridge lxc-download lxc-templates lxcfs lxcfs-openrc bridge-utils dnsmasq cgroup-tools rsync"
    command -v rsync >/dev/null 2>&1 || MISSING_LXC_PKGS="$MISSING_LXC_PKGS rsync"
    if [ -n "$MISSING_LXC_PKGS" ]; then
        [ "$SILENT" != "yes" ] && ui_step_progress 1 4 "Установка пакетов LXC и утилит виртуализации..."
        apk add --no-cache $MISSING_LXC_PKGS >/dev/null 2>&1 || true
    fi

    # 2. Инициализация cgroups v2
    if ! mount | grep -q "cgroup2 on /sys/fs/cgroup"; then
        [ "$SILENT" != "yes" ] && ui_step_progress 2 4 "Монтирование контрольных групп cgroups v2..."
        rc-service cgroups start >/dev/null 2>&1 || true
    fi
    rc-update add cgroups boot >/dev/null 2>&1 || true

    # 3. Привязка каталога хранения контейнеров к /srv/storage/lxc
    if [ -d "/srv/storage" ] && mountpoint -q /srv/storage 2>/dev/null; then
        mkdir -p "$LXC_STORAGE_DIR"
        chmod 755 "$LXC_STORAGE_DIR" 2>/dev/null || true
        if [ ! -L "$LXC_VAR_LIB" ]; then
            if [ -d "$LXC_VAR_LIB" ]; then
                # Останавливаем контейнеры и безопасно переносим с проверкой cp -a перед rm -rf
                if command -v lxc-stop >/dev/null 2>&1; then
                    for _old_ct in "${LXC_VAR_LIB}/"*; do
                        [ -d "$_old_ct" ] && [ -f "${_old_ct}/config" ] || continue
                        _old_n=$(basename "$_old_ct")
                        if lxc-info -n "$_old_n" 2>/dev/null | grep -q "State:.*RUNNING"; then
                            lxc-stop -n "$_old_n" -t 15 >/dev/null 2>&1 || lxc-stop -n "$_old_n" -k >/dev/null 2>&1 || true
                        fi
                    done
                fi
                if cp -a "${LXC_VAR_LIB}/." "${LXC_STORAGE_DIR}/"; then
                    rm -rf "$LXC_VAR_LIB"
                else
                    ui_warn_msg "Ошибка переноса ${LXC_VAR_LIB} в ${LXC_STORAGE_DIR}! Исходные файлы сохранены."
                    return 1
                fi
            fi
            ln -sfn "$LXC_STORAGE_DIR" "$LXC_VAR_LIB"
        fi
        command -v ensure_openrc_mount_guard >/dev/null 2>&1 && ensure_openrc_mount_guard "lxc" >/dev/null 2>&1 || true
    else
        mkdir -p "$LXC_VAR_LIB"
        chmod 755 "$LXC_VAR_LIB" 2>/dev/null || true
    fi

    # 4. Настройка сетевого моста lxcbr0 и DHCP (создаем только если отсутствуют, чтобы не затирать правки пользователя)
    mkdir -p /etc/conf.d /etc/lxc
    if [ ! -s /etc/conf.d/dnsmasq.lxcbr0 ]; then
        cat << 'CONF_EOF' > /etc/conf.d/dnsmasq.lxcbr0
rc_before="lxc"
BRIDGE_ADDR="10.0.3.1"
BRIDGE_NETMASK="255.255.255.0"
BRIDGE_NETWORK="10.0.3.0/24"
BRIDGE_DHCP_RANGE="10.0.3.2,10.0.3.254"
BRIDGE_DHCP_MAX="253"
BRIDGE_MAC="00:16:3e:00:00:00"
DNSMASQ_CONFFILE="/etc/lxc/dnsmasq.conf"
DISABLE_IPTABLES="yes"
CONF_EOF
    fi

    # port=0 отключает встроенный DNS dnsmasq, чтобы не конфликтовать с AdGuard Home (:53)
    if [ ! -s /etc/lxc/dnsmasq.conf ]; then
        cat << 'DNSM_EOF' > /etc/lxc/dnsmasq.conf
port=0
dhcp-option=option:dns-server,10.0.3.1
DNSM_EOF
    fi

    # Конфигурация интерфейса по умолчанию для новых контейнеров
    if [ ! -s /etc/lxc/default.conf ]; then
        cat << 'DEF_EOF' > /etc/lxc/default.conf
lxc.net.0.type = veth
lxc.net.0.link = lxcbr0
lxc.net.0.flags = up
lxc.net.0.hwaddr = 10:66:6a:xx:xx:xx
DEF_EOF
    fi

    # 5. Запуск и регистрация служб в OpenRC
    rc-service dnsmasq.lxcbr0 start >/dev/null 2>&1 || true
    rc-update add dnsmasq.lxcbr0 default >/dev/null 2>&1 || true

    rc-service lxcfs start >/dev/null 2>&1 || true
    rc-update add lxcfs default >/dev/null 2>&1 || true

    rc-service lxc start >/dev/null 2>&1 || true
    rc-update add lxc default >/dev/null 2>&1 || true

    [ "$SILENT" != "yes" ] && ui_ok_msg "Подсистема LXC активна. Мост lxcbr0 (10.0.3.1/24) готов к работе."
    return 0
}

# Табличный список всех контейнеров, их IP, ОЗУ, статуса и автозапуска
lxc_list_containers() {
    ensure_lxc_subsystem "yes"
    ui_box_top "📦 СПИСОК КОНТЕЙНЕРОВ LXC (LINUX CONTAINERS)"
    ui_box_row "${C_CYN}ИМЯ              СТАТУС       IPV4             ПАМЯТЬ     АВТО     СНАПШОТЫ${C_RES}"
    ui_box_row "─────────────────────────────────────────────────────────────────────────────"

    REAL_LXC_PATH=$(readlink -f "$LXC_VAR_LIB" 2>/dev/null || echo "$LXC_VAR_LIB")
    CT_FOUND=0

    for CT_DIR in "${REAL_LXC_PATH}/"*; do
        [ -d "$CT_DIR" ] || continue
        CT_NAME=$(basename "$CT_DIR")
        [ "$CT_NAME" = "*" ] && continue
        [ -f "${CT_DIR}/config" ] || continue
        CT_FOUND=$(( CT_FOUND + 1 ))

        # Определение статуса и PID
        STATE="STOPPED"
        IPV4="-"
        MEM_USE="-"
        if command -v lxc-info >/dev/null 2>&1; then
            INFO_OUT=$(lxc-info -n "$CT_NAME" 2>/dev/null || true)
            if echo "$INFO_OUT" | grep -q "State:.*RUNNING"; then
                STATE="RUNNING"
                IPV4=$(echo "$INFO_OUT" | awk '/IP:/ {print $2}' | paste -sd "," - || echo "-")
                [ -z "$IPV4" ] && IPV4="-"
                RAW_MEM=$(echo "$INFO_OUT" | awk '/Memory use:/ {print $3, $4}' || true)
                [ -n "$RAW_MEM" ] && MEM_USE="$RAW_MEM"
            fi
        fi

        # Проверка автозапуска
        AUTO_VAL="нет"
        if grep -q "^lxc\.start\.auto[ \t]*=[ \t]*1" "${CT_DIR}/config" 2>/dev/null; then
            AUTO_VAL="да"
        fi

        # Подсчет снапшотов
        SNAPS_COUNT=0
        if [ -d "${CT_DIR}/snaps" ]; then
            SNAPS_COUNT=$(ls -1 "${CT_DIR}/snaps" 2>/dev/null | wc -l || echo 0)
        fi

        # Цветовая подсветка (фиксированная визуальная ширина 12 символов)
        if [ "$STATE" = "RUNNING" ]; then
            STATE_FMT="${C_GRN}● RUNNING${C_RES}   "
        else
            STATE_FMT="${C_DIM}○ STOPPED${C_RES}   "
        fi

        # Компенсация UTF-8 кириллицы для столбца АВТО (визуальная ширина 8 символов)
        if [ "$AUTO_VAL" = "да" ]; then
            AUTO_FMT="да      "
        else
            AUTO_FMT="нет     "
        fi

        CT_ROW=$(printf "%-16s %b %-16s %-10s %s %s" \
            "$CT_NAME" "$STATE_FMT" "$IPV4" "$MEM_USE" "$AUTO_FMT" "${SNAPS_COUNT} шт.")
        ui_box_row "$CT_ROW"
    done

    if [ "$CT_FOUND" -eq 0 ]; then
        ui_box_row "Контейнеры еще не созданы. Для создания выберите пункт 'Создать контейнер'."
    fi
    ui_box_bottom
    echo ""
    return 0
}

# Автоконфигурация сетевых интерфейсов и DHCP/DNS внутри rootfs гостевых ОС
# Сохраняет статическую конфигурацию LXC и исключает утечку DNS мимо шлюза
lxc_autoseed_container_network() {
    CT_NAME="$1"
    DNS_IN="${2:-}"
    FORCE_DNS="${3:-no}"
    _lxc_is_valid_name "$CT_NAME" || return 1

    CT_DIR="${LXC_VAR_LIB}/${CT_NAME}"
    CT_CONF="${CT_DIR}/config"
    ROOTFS="${CT_DIR}/rootfs"
    [ -d "$ROOTFS" ] || return 0

    _has_static=""
    _is_macvlan="no"
    if [ -f "$CT_CONF" ]; then
        _has_static=$(awk -F= '/^[[:space:]]*lxc\.net\.0\.ipv4\.address/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$CT_CONF" 2>/dev/null || true)
        grep -q '^[[:space:]]*lxc\.net\.0\.type[[:space:]]*=[[:space:]]*macvlan' "$CT_CONF" 2>/dev/null && _is_macvlan="yes"
    fi

    DNS_IP="$DNS_IN"
    if [ -z "$DNS_IP" ] && [ -s "${CT_DIR}/.gw_dns" ]; then
        DNS_IP=$(tr -d ' \t\r\n' < "${CT_DIR}/.gw_dns" 2>/dev/null || true)
    fi
    if [ -z "$DNS_IP" ]; then
        if [ "$_is_macvlan" = "yes" ]; then
            DNS_IP=$(get_default_router_ip 2>/dev/null || echo "${DEFAULT_ROUTER_IP:-192.168.1.5}")
        else
            DNS_IP="10.0.3.1"
        fi
    fi

    # 1. Debian / Ubuntu / Kali / Devuan (/etc/network/interfaces)
    if [ -d "${ROOTFS}/etc/network" ]; then
        if [ -n "$_has_static" ]; then
            if [ -f "${ROOTFS}/etc/network/interfaces" ] && grep -q "iface eth0 inet dhcp" "${ROOTFS}/etc/network/interfaces" 2>/dev/null; then
                sed -i 's/iface eth0 inet dhcp/iface eth0 inet manual/g' "${ROOTFS}/etc/network/interfaces" 2>/dev/null || true
            elif [ ! -f "${ROOTFS}/etc/network/interfaces" ] || ! grep -q "eth0" "${ROOTFS}/etc/network/interfaces" 2>/dev/null; then
                cat << 'EOF' >> "${ROOTFS}/etc/network/interfaces"

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual
EOF
            fi
        elif [ ! -f "${ROOTFS}/etc/network/interfaces" ] || ! grep -q "eth0" "${ROOTFS}/etc/network/interfaces" 2>/dev/null; then
            cat << 'EOF' >> "${ROOTFS}/etc/network/interfaces"

auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
        fi
    fi

    # 2. systemd-networkd (Debian, Kali, Ubuntu, Arch Linux, AlmaLinux, Fedora)
    if [ -d "${ROOTFS}/etc/systemd" ]; then
        mkdir -p "${ROOTFS}/etc/systemd/network"
        if [ -n "$_has_static" ]; then
            cat << 'EOF' > "${ROOTFS}/etc/systemd/network/80-container-eth0.network"
[Match]
Name=eth0

[Network]
DHCP=no
KeepConfiguration=yes
EOF
        elif [ ! -f "${ROOTFS}/etc/systemd/network/80-container-eth0.network" ]; then
            cat << 'EOF' > "${ROOTFS}/etc/systemd/network/80-container-eth0.network"
[Match]
Name=eth0

[Network]
DHCP=yes
EOF
        fi
        mkdir -p "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
        for srv in systemd-networkd.service systemd-resolved.service; do
            for pfx in /lib/systemd/system /usr/lib/systemd/system; do
                if [ -f "${ROOTFS}${pfx}/${srv}" ]; then
                    ln -sf "${pfx}/${srv}" "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${srv}" 2>/dev/null || true
                fi
            done
        done
    fi

    # 3. Alpine Linux (OpenRC): /etc/network/interfaces уже настроен на шаге 1, включаем автозапуск networking
    if [ -d "${ROOTFS}/etc/runlevels" ] && [ -f "${ROOTFS}/etc/init.d/networking" ]; then
        mkdir -p "${ROOTFS}/etc/runlevels/default"
        ln -sf /etc/init.d/networking "${ROOTFS}/etc/runlevels/default/networking" 2>/dev/null || true
    fi

    # 4. Базовый resolv.conf (строго через шлюз/роутер, без утечки на 1.1.1.1)
    if [ "$FORCE_DNS" = "force" ] || [ ! -s "${ROOTFS}/etc/resolv.conf" ] || grep -q "1\.1\.1\.1" "${ROOTFS}/etc/resolv.conf" 2>/dev/null; then
        [ -L "${ROOTFS}/etc/resolv.conf" ] && rm -f "${ROOTFS}/etc/resolv.conf" 2>/dev/null || true
        printf "nameserver %s\n" "$DNS_IP" > "${ROOTFS}/etc/resolv.conf"
    fi
}

# Интерактивное создание нового контейнера с загрузкой официального шаблона
lxc_create_wizard() {
    ensure_lxc_subsystem "no"
    ui_banner "LXC // МАСТЕР СОЗДАНИЯ КОНТЕЙНЕРА"

    LXC_ARCH=$(get_lxc_system_arch)

    echo "${C_BLD}Введите имя нового контейнера (латиница, цифры, - и _):${C_RES}"
    read -r CT_NAME < /dev/tty || return 1
    CT_NAME=$(printf "%s" "$CT_NAME" | tr -d ' \t\r\n')
    if ! _lxc_is_valid_name "$CT_NAME"; then
        ui_warn_msg "Некорректное имя контейнера (допустимы только латиница, цифры, '-' и '_'). Отмена."
        return 1
    fi

    if [ -d "${LXC_VAR_LIB}/${CT_NAME}" ]; then
        ui_warn_msg "Контейнер с именем '${CT_NAME}' уже существует!"
        return 1
    fi

    echo ""
    ensure_gateway_runtime_dir || return 1
    CACHE_FILE="${GATEWAY_RUNTIME_DIR:-/run/gateway}/lxc_templates_${LXC_ARCH}.txt"

    # Загружаем актуальный индекс образов images.linuxcontainers.org
    if [ ! -s "$CACHE_FILE" ] || [ -n "$(find "$CACHE_FILE" -mmin +60 2>/dev/null)" ]; then
        ui_step_progress 1 4 "Загрузка официального каталога образов images.linuxcontainers.org (${LXC_ARCH})..."
        curl -s --connect-timeout 8 "https://images.linuxcontainers.org/meta/1.0/index-system" 2>/dev/null | \
            awk -F';' -v a="$LXC_ARCH" '$3 == a && $4 == "default" {print $1, $2}' | \
            sort -u -k1,1 -k2,2 > "${CACHE_FILE}.tmp" 2>/dev/null
        if [ -s "${CACHE_FILE}.tmp" ]; then
            mv -f "${CACHE_FILE}.tmp" "$CACHE_FILE"
        else
            rm -f "${CACHE_FILE}.tmp" 2>/dev/null || true
        fi
    fi

    # Резервный список шаблонов на случай отсутствия связи с сервером
    if [ ! -s "$CACHE_FILE" ]; then
        cat << 'FALLBACK_EOF' > "$CACHE_FILE"
almalinux 9
almalinux 10
alpine 3.21
alpine 3.22
alpine 3.23
alpine 3.24
alpine edge
alt p11
archlinux current
cachyos current
centos 9-Stream
centos 10-Stream
debian bookworm
debian trixie
devuan daedalus
fedora 43
fedora 44
kali current
mint wilma
nixos 26.05
opensuse tumbleweed
rockylinux 9
ubuntu jammy
ubuntu noble
voidlinux current
FALLBACK_EOF
    fi

    TOTAL_TMPL=$(wc -l < "$CACHE_FILE" | tr -d ' ')

    ui_box_top "🌐 ОФИЦИАЛЬНЫЙ КАТАЛОГ ШАБЛОНОВ LXC (images.linuxcontainers.org / ${LXC_ARCH})"
    awk '{lines[NR] = sprintf("  %2d) %-13s (%s)", NR, $1, $2)}
    END {
        half = int((NR + 1) / 2)
        for (i = 1; i <= half; i++) {
            right = (i + half <= NR) ? lines[i + half] : ""
            printf "%-38s%s\n", lines[i], right
        }
    }' "$CACHE_FILE"
    echo ""
    echo "   0) Ввести произвольный дистрибутив и релиз вручную"
    ui_box_bottom
    echo ""

    # Номер Alpine по умолчанию
    DEFAULT_NUM=$(grep -n "^alpine 3\.24" "$CACHE_FILE" 2>/dev/null | cut -d: -f1 || echo "")
    [ -z "$DEFAULT_NUM" ] && DEFAULT_NUM=$(grep -n "^alpine" "$CACHE_FILE" 2>/dev/null | head -n1 | cut -d: -f1 || echo "1")

    printf "Выберите номер шаблона [1-%s, 0 для ручного ввода, по умолчанию %s]: " "$TOTAL_TMPL" "$DEFAULT_NUM"
    read -r DIST_CHOICE < /dev/tty || DIST_CHOICE=""
    [ -z "$DIST_CHOICE" ] && DIST_CHOICE="$DEFAULT_NUM"

    T_DIST="alpine"
    T_REL="3.24"
    if [ "$DIST_CHOICE" = "0" ]; then
        echo "Введите название дистрибутива (например, fedora, debian, kali, opensuse):"
        read -r T_DIST < /dev/tty || T_DIST=""
        echo "Введите версию релиза (например, current, bookworm, noble, 41):"
        read -r T_REL < /dev/tty || T_REL=""
    elif [ "$DIST_CHOICE" -ge 1 ] 2>/dev/null && [ "$DIST_CHOICE" -le "$TOTAL_TMPL" ] 2>/dev/null; then
        SELECTED_LINE=$(sed -n "${DIST_CHOICE}p" "$CACHE_FILE")
        T_DIST=$(echo "$SELECTED_LINE" | awk '{print $1}')
        T_REL=$(echo "$SELECTED_LINE" | awk '{print $2}')
    else
        ui_warn_msg "Некорректный выбор. Используется Alpine по умолчанию."
        T_DIST="alpine"
        T_REL="3.24"
    fi

    echo ""
    ui_info_msg "Выберите режим сетевого подключения:"
    echo "  1) NAT / Изолированный мост lxcbr0 (10.0.3.X, DNS AdGuard, трафик через Sing-Box) [Рекомендуется]"
    echo "  2) Прямой мост в домашнюю сеть (Macvlan на $(get_lan_ifname), свой IP от домашнего роутера)"
    printf "Ваш выбор [1-2, по умолчанию 1]: "
    read -r NET_CHOICE < /dev/tty || NET_CHOICE="1"
    [ -z "$NET_CHOICE" ] && NET_CHOICE="1"

    echo ""
    ui_info_msg "Конфигурация IP адреса контейнера:"
    echo "  1) Динамический DHCP (автоматическое получение адреса) [Рекомендуется]"
    echo "  2) Статический IPv4 (ручная фиксация адреса, шлюза и DNS)"
    printf "Ваш выбор [1-2, по умолчанию 1]: "
    read -r IP_MODE_CHOICE < /dev/tty || IP_MODE_CHOICE="1"
    [ -z "$IP_MODE_CHOICE" ] && IP_MODE_CHOICE="1"

    STATIC_IP=""
    STATIC_GW=""
    STATIC_DNS=""
    if [ "$IP_MODE_CHOICE" = "2" ]; then
        DEFAULT_GW="10.0.3.1"
        [ "$NET_CHOICE" = "2" ] && DEFAULT_GW="$(get_default_router_ip)"
        echo "Введите статический IPv4 с CIDR маской (например, $([ "$NET_CHOICE" = "2" ] && echo "192.168.1.150/24" || echo "10.0.3.50/24")):"
        read -r RAW_STATIC_IP < /dev/tty || RAW_STATIC_IP=""
        RAW_STATIC_IP=$(printf "%s" "$RAW_STATIC_IP" | tr -d ' \t\r\n')
        STATIC_IP=$(_lxc_is_valid_ipv4_cidr "$RAW_STATIC_IP" || true)
        if [ -z "$STATIC_IP" ]; then
            ui_warn_msg "Некорректный статический IPv4/CIDR (${RAW_STATIC_IP}). Отмена."
            return 1
        fi
        echo "Введите шлюз по умолчанию [Enter для ${DEFAULT_GW}]:"
        read -r STATIC_GW < /dev/tty || STATIC_GW=""
        STATIC_GW=$(printf "%s" "$STATIC_GW" | tr -d ' \t\r\n')
        [ -z "$STATIC_GW" ] && STATIC_GW="$DEFAULT_GW"
        if ! _lxc_is_valid_ipv4 "$STATIC_GW"; then
            ui_warn_msg "Некорректный IPv4 шлюза (${STATIC_GW}). Отмена."
            return 1
        fi
        echo "Введите DNS сервер [Enter для ${DEFAULT_GW}]:"
        read -r STATIC_DNS < /dev/tty || STATIC_DNS=""
        STATIC_DNS=$(printf "%s" "$STATIC_DNS" | tr -d ' \t\r\n')
        [ -z "$STATIC_DNS" ] && STATIC_DNS="$DEFAULT_GW"
        if ! _lxc_is_valid_ipv4 "$STATIC_DNS"; then
            ui_warn_msg "Некорректный IPv4 DNS (${STATIC_DNS}). Отмена."
            return 1
        fi
    else
        [ "$NET_CHOICE" = "2" ] && STATIC_DNS="$(get_default_router_ip)" || STATIC_DNS="10.0.3.1"
    fi

    echo ""
    ui_info_msg "Ограничение оперативной памяти (cgroups v2):"
    echo "  Введите лимит (например: 256M, 512M, 1G — число без суффикса считается МБ) или Enter для безлимитного:"
    read -r RAW_MEM_LIMIT < /dev/tty || RAW_MEM_LIMIT=""
    MEM_LIMIT=$(_lxc_normalize_mem_limit "$RAW_MEM_LIMIT" || true)
    if [ -z "$MEM_LIMIT" ]; then
        ui_warn_msg "Некорректный формат лимита памяти (${RAW_MEM_LIMIT}). Пример: 512M или 1G."
        return 1
    fi
    [ "$MEM_LIMIT" = "none" ] && MEM_LIMIT=""

    echo ""
    ui_info_msg "Включить автозапуск контейнера при старте сервера Gateway?"
    printf "Автозапуск (y/n, по умолчанию y): "
    read -r AUTO_START_ANS < /dev/tty || AUTO_START_ANS="y"
    [ -z "$AUTO_START_ANS" ] && AUTO_START_ANS="y"

    echo ""
    ui_box_top "🚀 ПАРАМЕТРЫ СОЗДАНИЯ КОНТЕЙНЕРА"
    ui_box_row "• Имя:          ${CT_NAME}"
    ui_box_row "• Дистрибутив:  ${T_DIST} (релиз: ${T_REL}, архитектура: ${LXC_ARCH})"
    ui_box_row "• Сеть:         $([ "$NET_CHOICE" = "2" ] && echo "Macvlan (LAN direct)" || echo "NAT (lxcbr0, 10.0.3.X)")"
    ui_box_row "• Режим IP:     $([ -n "$STATIC_IP" ] && echo "Статический (${STATIC_IP}, шлюз ${STATIC_GW})" || echo "DHCP (Автоматически)")"
    ui_box_row "• Лимит ОЗУ:    $([ -n "$MEM_LIMIT" ] && echo "$MEM_LIMIT" || echo "Без ограничений")"
    ui_box_row "• Автозапуск:   $([ "$AUTO_START_ANS" = "y" ] && echo "Включен (lxc.start.auto = 1)" || echo "Выключен")"
    ui_box_bottom
    echo ""

    ui_step_progress 1 3 "Загрузка официального шаблона из images.linuxcontainers.org..."
    if ! lxc-create -t download -n "$CT_NAME" -- -d "$T_DIST" -r "$T_REL" -a "$LXC_ARCH"; then
        ui_warn_box "Не удалось создать контейнер из шаблона." \
                    "Проверьте соединение с images.linuxcontainers.org или правильность релиза."
        return 1
    fi

    # Настройка конфигурационного файла контейнера
    CT_DIR="${LXC_VAR_LIB}/${CT_NAME}"
    CT_CONF="${CT_DIR}/config"
    printf "%s\n" "${STATIC_DNS:-10.0.3.1}" > "${CT_DIR}/.gw_dns" 2>/dev/null || true
    if [ -f "$CT_CONF" ]; then
        ui_step_progress 2 3 "Применение параметров сети, лимитов и автозапуска..."

        if [ "$NET_CHOICE" = "2" ]; then
            _lxc_apply_macvlan_config "$CT_CONF" || return 1
        fi

        if [ -n "$STATIC_IP" ]; then
            sed -i '/lxc\.net\.0\.ipv4\./d' "$CT_CONF"
            echo "lxc.net.0.ipv4.address = ${STATIC_IP}" >> "$CT_CONF"
            [ -n "$STATIC_GW" ] && echo "lxc.net.0.ipv4.gateway = ${STATIC_GW}" >> "$CT_CONF"
        fi

        if [ -n "$MEM_LIMIT" ]; then
            sed -i '/lxc\.cgroup2\.memory\.max/d' "$CT_CONF"
            echo "lxc.cgroup2.memory.max = ${MEM_LIMIT}" >> "$CT_CONF"
        fi

        if [ "$AUTO_START_ANS" = "y" ] || [ "$AUTO_START_ANS" = "Y" ]; then
            sed -i '/lxc\.start\.auto/d; /lxc\.start\.delay/d' "$CT_CONF"
            echo "lxc.start.auto = 1" >> "$CT_CONF"
            echo "lxc.start.delay = 3" >> "$CT_CONF"
        fi
    fi

    # Автонастройка сетевых сервисов внутри гостевого rootfs
    lxc_autoseed_container_network "$CT_NAME" "${STATIC_DNS:-10.0.3.1}" "force"

    ui_step_progress 3 3 "Запуск контейнера ${CT_NAME}..."
    lxc-start -n "$CT_NAME" 2>/dev/null || true
    sleep 2

    ui_ok_msg "Контейнер '${CT_NAME}' успешно создан и запущен!"
    echo "• Для входа в консоль выполните: ${C_CYN}gw lxc attach ${CT_NAME}${C_RES}"
    echo "• Для просмотра IP и статуса:     ${C_CYN}gw lxc list${C_RES}"
    return 0
}

# Управление состоянием контейнера (start / stop / restart / attach)
lxc_control() {
    ACTION="$1"
    NAME="$2"

    if [ -z "$NAME" ]; then
        echo "Введите имя контейнера:"
        read -r NAME < /dev/tty || return 1
    fi
    NAME=$(printf "%s" "$NAME" | tr -d ' \t\r\n')
    if ! _lxc_is_valid_name "$NAME"; then
        ui_warn_msg "Некорректное имя контейнера '${NAME}'."
        return 1
    fi
    if [ ! -f "${LXC_VAR_LIB}/${NAME}/config" ]; then
        ui_warn_msg "Контейнер '${NAME}' не найден."
        return 1
    fi

    case "$ACTION" in
        start)
            ui_info_msg "Запуск контейнера ${NAME}..."
            lxc_autoseed_container_network "$NAME"
            lxc-start -n "$NAME" && ui_ok_msg "Контейнер ${NAME} запущен." || { ui_warn_msg "Ошибка запуска ${NAME}."; return 1; }
            ;;
        stop)
            ui_info_msg "Остановка контейнера ${NAME}..."
            lxc-stop -n "$NAME" -t 10 && ui_ok_msg "Контейнер ${NAME} остановлен." || lxc-stop -n "$NAME" -k
            ;;
        restart)
            ui_info_msg "Перезапуск контейнера ${NAME}..."
            lxc_autoseed_container_network "$NAME"
            lxc-stop -n "$NAME" -t 10 2>/dev/null || true
            sleep 1
            lxc-start -n "$NAME" && ui_ok_msg "Контейнер ${NAME} перезапущен." || { ui_warn_msg "Ошибка перезапуска."; return 1; }
            ;;
        fix-net|net-fix)
            ui_info_msg "Автоисправление сетевой конфигурации для '${NAME}'..."
            lxc_autoseed_container_network "$NAME" "" "force"
            if lxc-info -n "$NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
                lxc-attach -n "$NAME" -- ip link set eth0 up 2>/dev/null || true
                if ! awk -F= '/^[[:space:]]*lxc\.net\.0\.ipv4\.address/ {found=1} END {exit !found}' "${LXC_VAR_LIB}/${NAME}/config" 2>/dev/null; then
                    lxc-attach -n "$NAME" -- systemctl enable --now systemd-networkd 2>/dev/null || \
                    lxc-attach -n "$NAME" -- dhclient eth0 2>/dev/null || \
                    lxc-attach -n "$NAME" -- udhcpc -i eth0 2>/dev/null || true
                fi
            fi
            ui_ok_msg "Сетевая конфигурация для '${NAME}' успешно применена."
            ;;
        attach)
            ui_info_msg "Вход в интерактивную сессию контейнера ${NAME} (выход: exit)..."
            lxc-attach -n "$NAME"
            ;;
        delete|destroy)
            ui_warn_msg "ВНИМАНИЕ! Контейнер '${NAME}' и все его файлы будут безвозвратно удалены."
            printf "Вы уверены? (yes/no): "
            read -r CONFIRM < /dev/tty || CONFIRM=""
            if [ "$CONFIRM" = "yes" ]; then
                lxc-stop -n "$NAME" -k 2>/dev/null || true
                lxc-destroy -n "$NAME" -s -f && ui_ok_msg "Контейнер ${NAME} успешно удален." || { ui_warn_msg "Ошибка удаления."; return 1; }
            else
                ui_info_msg "Удаление отменено."
            fi
            ;;
        autostart)
            CT_CONF="${LXC_VAR_LIB}/${NAME}/config"
            MODE="$3"
            if [ "$MODE" = "on" ] || { [ -z "$MODE" ] && ! grep -q "^lxc\.start\.auto[ \t]*=[ \t]*1" "$CT_CONF"; }; then
                sed -i '/lxc\.start\.auto/d; /lxc\.start\.delay/d' "$CT_CONF"
                echo "lxc.start.auto = 1" >> "$CT_CONF"
                echo "lxc.start.delay = 3" >> "$CT_CONF"
                ui_ok_msg "Автозапуск для '${NAME}' ВКЛЮЧЕН."
            else
                sed -i '/lxc\.start\.auto/d; /lxc\.start\.delay/d' "$CT_CONF"
                ui_info_msg "Автозапуск для '${NAME}' ВЫКЛЮЧЕН."
            fi
            ;;
    esac
    return 0
}

# Идемпотентное обновление ресурсов и опций в config существующего контейнера
lxc_apply_config_updates() {
    CT_NAME="$1"
    UPD_MEM="${2:-__KEEP__}"
    UPD_CPU="${3:-__KEEP__}"
    UPD_AUTO="${4:-__KEEP__}"
    UPD_NEST="${5:-__KEEP__}"
    UPD_STOR="${6:-__KEEP__}"
    _lxc_is_valid_name "$CT_NAME" || return 1
    CT_CONF="${LXC_VAR_LIB}/${CT_NAME}/config"
    [ -f "$CT_CONF" ] || return 1

    if [ "$UPD_MEM" != "__KEEP__" ]; then
        _norm_mem=$(_lxc_normalize_mem_limit "$UPD_MEM" || true)
        [ -z "$_norm_mem" ] && return 1
        sed -i '/^lxc\.cgroup2\.memory\.max/d' "$CT_CONF" 2>/dev/null || true
        if [ "$_norm_mem" != "none" ]; then
            echo "lxc.cgroup2.memory.max = ${_norm_mem}" >> "$CT_CONF"
        fi
    fi

    if [ "$UPD_CPU" != "__KEEP__" ]; then
        if [ -n "$UPD_CPU" ] && [ "$UPD_CPU" != "none" ] && [ "$UPD_CPU" != "0" ]; then
            printf "%s" "$UPD_CPU" | grep -Eq '^[0-9]+([.][0-9]+)?$' || return 1
            awk -v c="$UPD_CPU" 'BEGIN { exit (c + 0 > 0 ? 0 : 1) }' || return 1
            sed -i '/^lxc\.cgroup2\.cpu\.max/d' "$CT_CONF" 2>/dev/null || true
            CPU_QUOTA=$(awk -v c="$UPD_CPU" 'BEGIN { v = int((c + 0) * 100000); if (v < 10000) v = 10000; printf "%d", v }' 2>/dev/null || echo "")
            [ -n "$CPU_QUOTA" ] && echo "lxc.cgroup2.cpu.max = ${CPU_QUOTA} 100000" >> "$CT_CONF"
        else
            sed -i '/^lxc\.cgroup2\.cpu\.max/d' "$CT_CONF" 2>/dev/null || true
        fi
    fi

    if [ "$UPD_AUTO" != "__KEEP__" ]; then
        sed -i '/^lxc\.start\.auto/d; /^lxc\.start\.delay/d' "$CT_CONF" 2>/dev/null || true
        if [ "$UPD_AUTO" = "yes" ] || [ "$UPD_AUTO" = "on" ] || [ "$UPD_AUTO" = "true" ] || [ "$UPD_AUTO" = "1" ]; then
            echo "lxc.start.auto = 1" >> "$CT_CONF"
            echo "lxc.start.delay = 3" >> "$CT_CONF"
        fi
    fi

    if [ "$UPD_NEST" != "__KEEP__" ]; then
        awk '
            /^# --- GW_NESTING_BEGIN ---/ { skip=1; next }
            /^# --- GW_NESTING_END ---/ { skip=0; next }
            !skip { print }
        ' "$CT_CONF" > "${CT_CONF}.tmp.$$" && mv -f "${CT_CONF}.tmp.$$" "$CT_CONF"
        if [ "$UPD_NEST" = "yes" ] || [ "$UPD_NEST" = "on" ] || [ "$UPD_NEST" = "true" ] || [ "$UPD_NEST" = "1" ]; then
            cat << 'NEST_EOF' >> "$CT_CONF"
# --- GW_NESTING_BEGIN ---
lxc.include = /usr/share/lxc/config/nesting.conf
# --- GW_NESTING_END ---
NEST_EOF
        fi
    fi

    if [ "$UPD_STOR" != "__KEEP__" ]; then
        awk '
            /^# --- GW_STORAGE_BEGIN ---/ { skip=1; next }
            /^# --- GW_STORAGE_END ---/ { skip=0; next }
            !skip { print }
        ' "$CT_CONF" > "${CT_CONF}.tmp.$$" && mv -f "${CT_CONF}.tmp.$$" "$CT_CONF"
        if [ "$UPD_STOR" = "yes" ] || [ "$UPD_STOR" = "on" ] || [ "$UPD_STOR" = "true" ] || [ "$UPD_STOR" = "1" ]; then
            ST_MNT_PATH="${STORAGE_SHARED:-${STORAGE_ROOT:-/srv/storage}/Shared}"
            mkdir -p "$ST_MNT_PATH" "${LXC_VAR_LIB}/${CT_NAME}/rootfs/mnt/storage" 2>/dev/null || true
            cat << STOR_EOF >> "$CT_CONF"
# --- GW_STORAGE_BEGIN ---
lxc.mount.entry = ${ST_MNT_PATH} mnt/storage none bind,create=dir,rw 0 0
# --- GW_STORAGE_END ---
STOR_EOF
        fi
    fi
    return 0
}

# Неинтерактивное создание контейнера LXC по JSON-спецификации (для Web Dashboard и CLI)
lxc_create_from_spec() {
    SPEC_FILE="$1"
    if [ -z "$SPEC_FILE" ] || [ ! -s "$SPEC_FILE" ]; then
        ui_warn_msg "Файл спецификации контейнера LXC отсутствует."
        return 1
    fi

    RAW_CT_NAME=$(jq -r '.name // empty' "$SPEC_FILE" 2>/dev/null | tr -d ' \t\r\n')
    if ! _lxc_is_valid_name "$RAW_CT_NAME"; then
        ui_warn_msg "Некорректное имя контейнера '${RAW_CT_NAME}' (допустимы латиница, цифры, '-' и '_')."
        return 1
    fi
    CT_NAME="$RAW_CT_NAME"

    T_DIST=$(jq -r '.distro // empty' "$SPEC_FILE" 2>/dev/null | tr -cd 'A-Za-z0-9._-')
    T_REL=$(jq -r '.release // empty' "$SPEC_FILE" 2>/dev/null | tr -cd 'A-Za-z0-9._-')
    T_VAR=$(jq -r '.variant // "default"' "$SPEC_FILE" 2>/dev/null | tr -cd 'A-Za-z0-9._-')
    T_ARCH=$(jq -r '.arch // empty' "$SPEC_FILE" 2>/dev/null | tr -cd 'A-Za-z0-9_-')
    NET_MODE=$(jq -r '.net_mode // "nat"' "$SPEC_FILE" 2>/dev/null)
    RAW_STATIC_IP=$(jq -r '.static_ip // empty' "$SPEC_FILE" 2>/dev/null | tr -d ' \t\r\n')
    RAW_STATIC_GW=$(jq -r '.static_gw // empty' "$SPEC_FILE" 2>/dev/null | tr -d ' \t\r\n')
    RAW_STATIC_DNS=$(jq -r '.static_dns // empty' "$SPEC_FILE" 2>/dev/null | tr -d ' \t\r\n')
    RAW_MEM_LIMIT=$(jq -r '.mem_limit // empty' "$SPEC_FILE" 2>/dev/null | tr -d ' \t\r\n')
    RAW_CPU_LIMIT=$(jq -r '.cpu_limit // empty' "$SPEC_FILE" 2>/dev/null | tr -d ' \t\r\n')
    AUTO_EN=$(jq -r 'if .autostart == true or .autostart == "yes" then "yes" else "no" end' "$SPEC_FILE" 2>/dev/null)
    NEST_EN=$(jq -r 'if .nesting == true or .nesting == "yes" then "yes" else "no" end' "$SPEC_FILE" 2>/dev/null)
    STOR_EN=$(jq -r 'if .storage_mount == true or .storage_mount == "yes" then "yes" else "no" end' "$SPEC_FILE" 2>/dev/null)
    START_NOW=$(jq -r 'if .start_now == false or .start_now == "no" then "no" else "yes" end' "$SPEC_FILE" 2>/dev/null)
    ROOT_PASS=$(jq -r '.root_pass // empty' "$SPEC_FILE" 2>/dev/null | tr -d '\r\n')

    [ -z "$T_VAR" ] && T_VAR="default"
    [ -z "$T_ARCH" ] && T_ARCH=$(get_lxc_system_arch)

    MEM_LIMIT=""
    if [ -n "$RAW_MEM_LIMIT" ]; then
        MEM_LIMIT=$(_lxc_normalize_mem_limit "$RAW_MEM_LIMIT" || true)
        if [ -z "$MEM_LIMIT" ]; then
            ui_warn_msg "Некорректный лимит ОЗУ (${RAW_MEM_LIMIT}). Пример: 512M, 2G."
            return 1
        fi
    fi
    [ -z "$MEM_LIMIT" ] && MEM_LIMIT="none"

    CPU_LIMIT=""
    if [ -n "$RAW_CPU_LIMIT" ] && [ "$RAW_CPU_LIMIT" != "none" ] && [ "$RAW_CPU_LIMIT" != "0" ]; then
        if ! printf "%s" "$RAW_CPU_LIMIT" | grep -Eq '^[0-9]+([.][0-9]+)?$' || ! awk -v c="$RAW_CPU_LIMIT" 'BEGIN { exit (c + 0 > 0 ? 0 : 1) }'; then
            ui_warn_msg "Некорректный лимит CPU (${RAW_CPU_LIMIT})."
            return 1
        fi
        CPU_LIMIT="$RAW_CPU_LIMIT"
    else
        CPU_LIMIT="none"
    fi

    STATIC_IP=""
    if [ -n "$RAW_STATIC_IP" ]; then
        STATIC_IP=$(_lxc_is_valid_ipv4_cidr "$RAW_STATIC_IP" || true)
        if [ -z "$STATIC_IP" ]; then
            ui_warn_msg "Некорректный static_ip (${RAW_STATIC_IP})."
            return 1
        fi
    fi

    STATIC_GW=""
    if [ -n "$RAW_STATIC_GW" ]; then
        if ! _lxc_is_valid_ipv4 "$RAW_STATIC_GW"; then
            ui_warn_msg "Некорректный static_gw (${RAW_STATIC_GW})."
            return 1
        fi
        STATIC_GW="$RAW_STATIC_GW"
    fi

    STATIC_DNS=""
    if [ -n "$RAW_STATIC_DNS" ]; then
        if ! _lxc_is_valid_ipv4 "$RAW_STATIC_DNS"; then
            ui_warn_msg "Некорректный static_dns (${RAW_STATIC_DNS})."
            return 1
        fi
        STATIC_DNS="$RAW_STATIC_DNS"
    fi

    if [ -z "$CT_NAME" ] || [ -z "$T_DIST" ] || [ -z "$T_REL" ]; then
        ui_warn_msg "Не указано имя контейнера, дистрибутив или релиз."
        return 1
    fi

    ensure_lxc_subsystem "no"
    REAL_LXC_PATH=$(readlink -f "$LXC_VAR_LIB" 2>/dev/null || echo "$LXC_VAR_LIB")
    if [ -d "${REAL_LXC_PATH}/${CT_NAME}" ] || [ -d "${LXC_VAR_LIB}/${CT_NAME}" ]; then
        ui_warn_msg "Контейнер '${CT_NAME}' уже существует!"
        return 1
    fi

    ui_step_progress 1 4 "Загрузка образа ${T_DIST} ${T_REL} (${T_VAR}, ${T_ARCH}) с images.linuxcontainers.org..."
    if ! lxc-create -t download -n "$CT_NAME" -- -d "$T_DIST" -r "$T_REL" -a "$T_ARCH" --variant "$T_VAR"; then
        ui_warn_box "Не удалось загрузить или создать контейнер ${CT_NAME}." \
                    "Проверьте доступ к images.linuxcontainers.org и корректность дистрибутива/релиза."
        return 1
    fi

    CT_DIR="${LXC_VAR_LIB}/${CT_NAME}"
    CT_CONF="${CT_DIR}/config"
    printf "%s %s (%s)\n" "$T_DIST" "$T_REL" "$T_VAR" > "${CT_DIR}/.gw_os" 2>/dev/null || true

    ui_step_progress 2 4 "Настройка сети (${NET_MODE}), ресурсов и монтирования..."
    if [ -f "$CT_CONF" ]; then
        if [ "$NET_MODE" = "macvlan" ]; then
            _lxc_apply_macvlan_config "$CT_CONF" || return 1
            [ -z "$STATIC_DNS" ] && STATIC_DNS=$(get_default_router_ip)
            [ -n "$STATIC_IP" ] && [ -z "$STATIC_GW" ] && STATIC_GW=$(get_default_router_ip)
        else
            [ -z "$STATIC_DNS" ] && STATIC_DNS="10.0.3.1"
        fi
        printf "%s\n" "$STATIC_DNS" > "${CT_DIR}/.gw_dns" 2>/dev/null || true

        if [ -n "$STATIC_IP" ]; then
            sed -i '/lxc\.net\.0\.ipv4\./d' "$CT_CONF"
            echo "lxc.net.0.ipv4.address = ${STATIC_IP}" >> "$CT_CONF"
            if [ -n "$STATIC_GW" ]; then
                echo "lxc.net.0.ipv4.gateway = ${STATIC_GW}" >> "$CT_CONF"
            elif [ "$NET_MODE" != "macvlan" ]; then
                echo "lxc.net.0.ipv4.gateway = 10.0.3.1" >> "$CT_CONF"
            fi
        fi

        lxc_apply_config_updates "$CT_NAME" "$MEM_LIMIT" "$CPU_LIMIT" "$AUTO_EN" "$NEST_EN" "$STOR_EN"
    fi

    ui_step_progress 3 4 "Автоконфигурация сети и DNS внутри контейнера..."
    lxc_autoseed_container_network "$CT_NAME" "${STATIC_DNS:-10.0.3.1}" "force"

    if [ "$START_NOW" = "yes" ]; then
        ui_step_progress 4 4 "Запуск контейнера ${CT_NAME} и ожидание IP-адреса..."
        if lxc-start -n "$CT_NAME"; then
            _w=0
            while [ "$_w" -lt 8 ]; do
                _ip_chk=$(lxc-info -n "$CT_NAME" 2>/dev/null | awk '/IP:/ {print $2; exit}' || true)
                [ -n "$_ip_chk" ] && break
                sleep 1
                _w=$((_w + 1))
            done
        else
            ui_warn_msg "Контейнер создан, но не смог стартовать автоматически."
        fi
    else
        ui_step_progress 4 4 "Завершение подготовки (автостарт после создания пропущен)..."
    fi

    if [ -n "$ROOT_PASS" ]; then
        _pw_ok="no"
        if lxc-info -n "$CT_NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
            printf "root:%s\n" "$ROOT_PASS" | lxc-attach -n "$CT_NAME" -- chpasswd >/dev/null 2>&1 && _pw_ok="yes"
        elif [ -d "${CT_DIR}/rootfs" ]; then
            for _cpw in /usr/sbin/chpasswd /sbin/chpasswd /usr/bin/chpasswd; do
                if [ -x "${CT_DIR}/rootfs${_cpw}" ]; then
                    printf "root:%s\n" "$ROOT_PASS" | chroot "${CT_DIR}/rootfs" "$_cpw" >/dev/null 2>&1 && _pw_ok="yes"
                    break
                fi
            done
        fi
        if [ "$_pw_ok" = "yes" ]; then
            ui_ok_msg "Пароль пользователя root установлен."
        else
            ui_warn_msg "Не удалось установить пароль пользователя root внутри контейнера ${CT_NAME}."
        fi
    fi

    ui_ok_msg "Контейнер '${CT_NAME}' (${T_DIST} ${T_REL}) успешно развёрнут!"
    return 0
}

# Управление снимками (снапшотами) контейнера
lxc_manage_snapshots() {
    ARG1="${1:-}"
    ARG2="${2:-}"
    ARG3="${3:-}"

    # Поддержка любого порядка аргументов: gw lxc snap <имя> <действие> ИЛИ gw lxc snap <действие> <имя>
    case "$ARG1" in
        create|snap|list|ls|restore|revert|delete|del|rm)
            SUBACTION="$ARG1"
            NAME="$ARG2"
            SNAPNAME="$ARG3"
            ;;
        *)
            NAME="$ARG1"
            SUBACTION="$ARG2"
            SNAPNAME="$ARG3"
            ;;
    esac
    [ -z "$SUBACTION" ] && SUBACTION="list"

    if [ -z "$NAME" ]; then
        echo "Введите имя контейнера:"
        read -r NAME < /dev/tty || return 1
    fi
    NAME=$(printf "%s" "$NAME" | tr -d ' \t\r\n')
    if ! _lxc_is_valid_name "$NAME"; then
        ui_warn_msg "Некорректное имя контейнера '${NAME}'."
        return 1
    fi
    if [ ! -f "${LXC_VAR_LIB}/${NAME}/config" ]; then
        ui_warn_msg "Контейнер '${NAME}' не найден."
        return 1
    fi

    case "$SUBACTION" in
        create|snap)
            ui_info_msg "Создание снимка (снапшота) контейнера ${NAME}..."
            _was_running="no"
            if lxc-info -n "$NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
                _was_running="yes"
                if ! lxc-stop -n "$NAME" -t 15 >/dev/null 2>&1; then
                    if ! lxc-stop -n "$NAME" -k >/dev/null 2>&1; then
                        ui_warn_msg "Не удалось остановить контейнер ${NAME} перед созданием снимка."
                        return 1
                    fi
                fi
            fi
            if ! lxc-snapshot -n "$NAME"; then
                ui_warn_msg "Ошибка создания снимка контейнера ${NAME}."
                [ "$_was_running" = "yes" ] && { lxc-start -n "$NAME" >/dev/null 2>&1 || true; }
                return 1
            fi
            if [ "$_was_running" = "yes" ]; then
                lxc-start -n "$NAME" >/dev/null 2>&1 || ui_warn_msg "Снимок создан, но контейнер ${NAME} не смог запуститься обратно."
            fi
            ui_ok_msg "Снимок контейнера ${NAME} успешно создан."
            lxc-snapshot -n "$NAME" -L 2>/dev/null || true
            ;;
        list|ls)
            ui_box_top "📸 СНИМКИ (СНАПШОТЫ) ДЛЯ КОНТЕЙНЕРА ${NAME}"
            SN_LINES=$(lxc-snapshot -n "$NAME" -L 2>/dev/null || true)
            if [ -n "$SN_LINES" ]; then
                printf "%s\n" "$SN_LINES" | while read -r line; do
                    ui_box_row "  • ${line}"
                done
            else
                ui_box_row "  У контейнера ${NAME} пока нет сохраненных снимков."
            fi
            ui_box_bottom
            ;;
        restore|revert)
            if [ -z "$SNAPNAME" ]; then
                ui_info_msg "Доступные снимки:"
                lxc-snapshot -n "$NAME" -L 2>/dev/null || true
                echo "Введите имя снимка для отката (например: snap0):"
                read -r SNAPNAME < /dev/tty || return 1
            fi
            SNAPNAME=$(printf "%s" "$SNAPNAME" | tr -d ' \t\r\n')
            _lxc_is_valid_name "$SNAPNAME" || { ui_warn_msg "Некорректное имя снимка."; return 1; }

            ui_warn_msg "Откат контейнера ${NAME} к снимку ${SNAPNAME} уничтожит текущие несохраненные изменения!"
            printf "Продолжить откат? (yes/no): "
            read -r C_ROLL < /dev/tty || C_ROLL=""
            if [ "$C_ROLL" = "yes" ]; then
                lxc-stop -n "$NAME" -k 2>/dev/null || true
                if lxc-snapshot -n "$NAME" -r "$SNAPNAME"; then
                    ui_ok_msg "Контейнер ${NAME} успешно восстановлен из снимка ${SNAPNAME}!"
                    lxc-start -n "$NAME" 2>/dev/null || true
                else
                    ui_warn_msg "Ошибка восстановления из снимка."
                    return 1
                fi
            fi
            ;;
        delete|del|rm)
            if [ -z "$SNAPNAME" ]; then
                echo "Введите имя снимка для удаления (например: snap0):"
                read -r SNAPNAME < /dev/tty || return 1
            fi
            SNAPNAME=$(printf "%s" "$SNAPNAME" | tr -d ' \t\r\n')
            _lxc_is_valid_name "$SNAPNAME" || { ui_warn_msg "Некорректное имя снимка."; return 1; }
            lxc-snapshot -n "$NAME" -d "$SNAPNAME" && ui_ok_msg "Снимок ${SNAPNAME} удален." || { ui_warn_msg "Ошибка удаления снимка."; return 1; }
            ;;
        *)
            echo "Использование: gw lxc snap <имя> [create|list|restore|delete] [имя_снимка]"
            ;;
    esac
    return 0
}

# Диагностика и самоисцеление подсистемы LXC для gw doctor
check_and_heal_lxc_doctor() {
    # 1. Проверяем наличие пакетов lxc
    if ! command -v lxc-create >/dev/null 2>&1; then
        return 0
    fi

    # 2. Проверяем монтирование cgroups v2
    if ! mount | grep -q "cgroup2 on /sys/fs/cgroup"; then
        rc-service cgroups start >/dev/null 2>&1 || true
    fi

    # 3. Проверяем сетевой мост lxcbr0 и dnsmasq
    if [ -f "/etc/conf.d/dnsmasq.lxcbr0" ]; then
        if ! grep -q 'port=0' /etc/lxc/dnsmasq.conf 2>/dev/null; then
            echo 'port=0' >> /etc/lxc/dnsmasq.conf
            echo 'dhcp-option=option:dns-server,10.0.3.1' >> /etc/lxc/dnsmasq.conf
        fi
        if ! pgrep -f "dnsmasq.*lxcbr0" >/dev/null 2>&1; then
            rc-service dnsmasq.lxcbr0 restart >/dev/null 2>&1 || true
        fi
    fi

    # 4. Проверяем службу lxcfs
    if [ -f "/etc/init.d/lxcfs" ] && ! pgrep lxcfs >/dev/null 2>&1; then
        rc-service lxcfs start >/dev/null 2>&1 || true
    fi

    # 5. Привязка Mount Guard к lxc при внешнем хранилище и изоляция legacy storage_mount от корня /srv/storage
    if [ -L "$LXC_VAR_LIB" ]; then
        command -v ensure_openrc_mount_guard >/dev/null 2>&1 && ensure_openrc_mount_guard "lxc" >/dev/null 2>&1 || true
    fi
    _st_root="${STORAGE_ROOT:-/srv/storage}"
    _st_shared="${STORAGE_SHARED:-${_st_root}/Shared}"
    _real_lxc=$(readlink -f "$LXC_VAR_LIB" 2>/dev/null || echo "$LXC_VAR_LIB")
    if [ -d "$_real_lxc" ]; then
        for _ct_c in "${_real_lxc}"/*/config; do
            [ -f "$_ct_c" ] || continue
            if grep -q "lxc\.mount\.entry[[:space:]]*=[[:space:]]*${_st_root}[[:space:]]*mnt/storage" "$_ct_c" 2>/dev/null; then
                mkdir -p "$_st_shared" 2>/dev/null || true
                sed -i "s|lxc\.mount\.entry[[:space:]]*=[[:space:]]*${_st_root}[[:space:]]*mnt/storage|lxc.mount.entry = ${_st_shared} mnt/storage|g" "$_ct_c" 2>/dev/null || true
            fi
        done
    fi
    return 0
}

# Интерактивное TUI меню управления LXC контейнерами
lxc_interactive_menu() {
    ensure_lxc_subsystem "no"
    while true; do
        ui_banner "LXC // УПРАВЛЕНИЕ КОНТЕЙНЕРАМИ И СНАПШОТАМИ"
        lxc_list_containers

        echo "  ${C_BLD}Действия:${C_RES}"
        echo "  1) ➕ Создать новый контейнер (Alpine, Debian, Ubuntu, Arch...)"
        echo "  2) ▶  Запустить контейнер"
        echo "  3) ⏹  Остановить контейнер"
        echo "  4) 🔄 Перезапустить контейнер"
        echo "  5) 💻 Войти в терминал контейнера (lxc-attach)"
        echo "  6) 📸 Управление снимками (Снапшоты: создать / список / откат)"
        echo "  7) ⚙  Переключить автозапуск при старте сервера"
        echo "  8) 🔧 Автоисправление сети контейнера (DHCP / DNS)"
        echo "  9) 🗑  Удалить контейнер"
        echo "  0) ⬅  Назад в главное меню"
        echo ""
        printf "Выберите действие [0-9]: "
        read -r M_ACT < /dev/tty || break
        case "$M_ACT" in
            1) lxc_create_wizard ;;
            2) lxc_control "start" ;;
            3) lxc_control "stop" ;;
            4) lxc_control "restart" ;;
            5) lxc_control "attach" ;;
            6)
                echo "Введите имя контейнера для работы со снимками:"
                read -r S_CT < /dev/tty || S_CT=""
                if [ -n "$S_CT" ]; then
                    echo "  1) Создать снимок (snapshot)"
                    echo "  2) Список снимков"
                    echo "  3) Восстановить из снимка"
                    echo "  4) Удалить снимок"
                    printf "Действие [1-4]: "
                    read -r SS_ACT < /dev/tty || SS_ACT=""
                    case "$SS_ACT" in
                        1) lxc_manage_snapshots "create" "$S_CT" ;;
                        2) lxc_manage_snapshots "list" "$S_CT" ;;
                        3) lxc_manage_snapshots "restore" "$S_CT" ;;
                        4) lxc_manage_snapshots "delete" "$S_CT" ;;
                    esac
                fi
                ;;
            7)
                echo "Введите имя контейнера для переключения автозапуска:"
                read -r A_CT < /dev/tty || A_CT=""
                [ -n "$A_CT" ] && lxc_control "autostart" "$A_CT"
                ;;
            8)
                echo "Введите имя контейнера для автоисправления сети:"
                read -r N_CT < /dev/tty || N_CT=""
                [ -n "$N_CT" ] && lxc_control "fix-net" "$N_CT"
                ;;
            9) lxc_control "delete" ;;
            0|q|Q) break ;;
        esac
        echo ""
        echo "Нажмите Enter для продолжения..."
        read -r _DUMMY < /dev/tty || true
    done
    return 0
}
