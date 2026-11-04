prompt_homelab_modules_wizard() {
    PRE_SEL="${1:-}"
    init_homelab_registry
    if [ "$PRE_SEL" = "__SKIP__" ]; then
        return 0
    elif [ -n "$PRE_SEL" ]; then
        HL_SEL="$PRE_SEL"
    else
        echo ""
        ui_box_top "Выбор модулей домашнего сервера (Homelab & Media Stack)"
        echo " Вы можете сразу установить нужные домашние сервисы (или пропустить этот шаг):"
        echo "  ${C_CYN}[1]${C_RES} caddy       — Центральный HTTPS Reverse Proxy & Локальный CA (*.lan)"
        echo "  ${C_CYN}[2]${C_RES} samba       — Общая сетевая папка SMB2/3 + автообнаружение Windows 11 / Linux"
        echo "  ${C_CYN}[3]${C_RES} vaultwarden — Менеджер паролей Bitwarden (https://vaultwarden.lan)"
        echo "  ${C_CYN}[4]${C_RES} forgejo     — Локальный Git-сервер (https://forgejo.lan)"
        echo "  ${C_CYN}[5]${C_RES} code        — VS Code в браузере Server-Code (https://code.lan)"
        echo "  ${C_CYN}[6]${C_RES} navidrome   — Музыкальный стриминг Subsonic/Spotify-style (https://music.lan)"
        echo "  ${C_CYN}[7]${C_RES} jellyfin    — Домашний кинотеатр Jellyfin (https://jellyfin.lan)"
        echo "  ${C_CYN}[8]${C_RES} ytdlp       — Веб-панель загрузки видео и музыки yt-dlp (https://downloads.lan)"
        echo "  ${C_CYN}[9]${C_RES} torrent     — Торрент-клиент qBittorrent-nox + Hardlink-импорт (https://torrents.lan)"
        ui_box_sep
        printf "Введите номера через пробел (например: 1 2 3 6 8 9), 'all' для всех или Enter (только шлюз): "
        read -r HL_SEL < /dev/tty || true
    fi
    HL_SEL=$(printf "%s" "$HL_SEL" | tr ',' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$HL_SEL" ] || [ "$HL_SEL" = "0" ] || [ "$HL_SEL" = "none" ] && return 0

    if [ "$HL_SEL" = "all" ] || [ "$HL_SEL" = "ALL" ]; then
        HL_SEL="1 2 3 4 5 6 7 8 9"
    fi

    init_homelab_storage
    # Если выбран любой веб-модуль (3..9), автоматически устанавливаем Caddy первым
    NEED_CADDY="no"
    for ITEM in $HL_SEL; do
        case "$ITEM" in
            1|caddy|3|vaultwarden|4|forgejo|5|code|6|navidrome|7|jellyfin|8|ytdlp|9|torrent)
                NEED_CADDY="yes"
                ;;
        esac
    done
    if [ "$NEED_CADDY" = "yes" ] && ! is_module_enabled "caddy"; then
        install_module_caddy || true
    fi

    for ITEM in $HL_SEL; do
        case "$ITEM" in
            1|caddy)       is_module_enabled "caddy" || install_module_caddy || true ;;
            2|samba)       install_module_samba "auto" || true ;;
            3|vaultwarden) install_module_vaultwarden || true ;;
            4|forgejo)     install_module_forgejo || true ;;
            5|code)        install_module_code || true ;;
            6|navidrome)   install_module_navidrome || true ;;
            7|jellyfin)    install_module_jellyfin || true ;;
            8|ytdlp)       install_module_ytdlp || true ;;
            9|torrent)     install_module_torrent || true ;;
        esac
    done

    if is_module_enabled "caddy"; then
        show_https_ca_instructions
    fi
    return 0
}

# ==============================================================================
# Главный мастер установки и настройки (Эксклюзивно Alpine Linux Homelab Edition)
# Поддерживает как интерактивный режим, так и полностью тихий запуск:
#   gateway install --answers /path/to/gateway.answers
# ==============================================================================
run_installer() {
    umask 022
    detect_os
    init_user_lists
    init_homelab_registry

    # 0. Обработка аргументов командной строки и поиск файла автоматических ответов
    ANSWERS_FILE=""
    IS_UNATTENDED="no"

    while [ $# -gt 0 ]; do
        case "$1" in
            --answers=*)
                ANSWERS_FILE="${1#*=}"
                IS_UNATTENDED="yes"
                shift
                ;;
            --answers|-a|-f|--file)
                ANSWERS_FILE="${2:-}"
                IS_UNATTENDED="yes"
                shift 2 2>/dev/null || shift
                ;;
            --unattended|-y)
                IS_UNATTENDED="yes"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -z "$ANSWERS_FILE" ]; then
        for cand in "${GATEWAY_DIR}/gateway.answers" "./gateway.answers" "/opt/gateway/gateway.answers" "/etc/gateway/gateway.answers" "/root/gateway.answers"; do
            if [ -f "$cand" ]; then
                ANSWERS_FILE="$cand"
                IS_UNATTENDED="yes"
                break
            fi
        done
    fi

    ANS_STORAGE_DISK="none"
    ANS_STORAGE_ACTION="mount"
    ANS_STORAGE_FS="ext4"
    ANS_STORAGE_LUKS="no"
    ANS_STORAGE_LUKS_PASS=""
    ANS_SSL_TYPE="local"
    ANS_DUCK_SUB=""
    ANS_DUCK_TOK=""

    if [ "$IS_UNATTENDED" = "yes" ]; then
        if [ ! -f "$ANSWERS_FILE" ]; then
            ui_warn_box "Указанный файл ответов не найден: ${ANSWERS_FILE}"
            return 1
        fi
        ui_banner "UNATTENDED INSTALLER // ТИХАЯ УСТАНОВКА ИЗ ФАЙЛА ОТВЕТОВ"
        echo "Файл ответов: ${C_CYN}${ANSWERS_FILE}${C_RES}"
        echo "Режим:        ${C_GRN}Полностью автономный запуск (Zero-Touch)${C_RES}"
        ui_box_sep
        # shellcheck source=/dev/null
        . "$ANSWERS_FILE"

        USE_INITIAL_WARP="no"
        ANS_SUB="${SUB_URL:-warp}"
        if [ "$ANS_SUB" = "warp" ] || [ -z "$ANS_SUB" ]; then
            USE_INITIAL_WARP="yes"
            apply_subscription_input "warp"
        else
            apply_subscription_input "$ANS_SUB"
        fi

        LAN_IP_DETECTED=$(get_current_lan_ip)
        if [ -z "${TARGET_LAN_IP:-}" ] || [ "$TARGET_LAN_IP" = "auto" ]; then
            TARGET_LAN_IP="$LAN_IP_DETECTED"
        fi
        if ! is_valid_ipv4 "$TARGET_LAN_IP"; then
            TARGET_LAN_IP="$LAN_IP_DETECTED"
        fi

        GW_IP_DETECTED=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n 1)
        [ -z "$GW_IP_DETECTED" ] && GW_IP_DETECTED="${TARGET_LAN_IP%.*}.1"
        if [ -z "${GW_IP:-}" ] || [ "$GW_IP" = "auto" ]; then
            GW_IP="$GW_IP_DETECTED"
        fi
        if ! is_valid_ipv4 "$GW_IP" || [ "$GW_IP" = "$TARGET_LAN_IP" ]; then
            GW_IP="$GW_IP_DETECTED"
        fi

        AGH_USER="${ADMIN_USER:-admin}"
        if [ -z "${ADMIN_PASS:-}" ]; then
            ADMIN_PASS=$(tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom 2>/dev/null | head -c 16)
            [ -z "$ADMIN_PASS" ] && ADMIN_PASS="GateWay_$(date +%s)"
            ui_info_msg "Сгенерирован мастер-пароль: ${ADMIN_PASS}"
        fi
        SMB_USER="$AGH_USER"
        SMB_PASS="$ADMIN_PASS"

        case "${ENABLE_AUTOUPDATE:-no}" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) ENABLE_AU="yes" ;;
            *) ENABLE_AU="no" ;;
        esac

        PRE_HL_SEL="${HOMELAB_MODULES:-none}"
        [ -z "$PRE_HL_SEL" ] || [ "$PRE_HL_SEL" = "0" ] || [ "$PRE_HL_SEL" = "none" ] && PRE_HL_SEL="__SKIP__"
        if [ "$PRE_HL_SEL" = "all" ] || [ "$PRE_HL_SEL" = "ALL" ]; then
            PRE_HL_SEL="1 2 3 4 5 6 7 8 9"
        fi

        ANS_STORAGE_DISK="${STORAGE_DISK:-none}"
        ANS_STORAGE_ACTION="${STORAGE_ACTION:-mount}"
        ANS_STORAGE_FS="${STORAGE_FS:-ext4}"
        ANS_STORAGE_LUKS="${STORAGE_LUKS:-no}"
        ANS_STORAGE_LUKS_PASS="${STORAGE_LUKS_PASS:-$ADMIN_PASS}"
        ANS_SSL_TYPE="${SSL_TYPE:-local}"
        ANS_DUCK_SUB="${DUCKDNS_SUBDOMAIN:-}"
        ANS_DUCK_TOK="${DUCKDNS_TOKEN:-}"
    else
        ui_banner "INSTALLER WIZARD // МАСТЕР УСТАНОВКИ ШЛЮЗА И HOMELAB"
        echo "Система: ${OS_NAME} [${ARCH_RAW} -> ${SB_ARCH}]"
        echo "Память:  ${TOTAL_RAM_MB} МБ RAM (Лимит SB: ${SB_GOMEMLIMIT}, AGH: ${AGH_GOMEMLIMIT})"
        ui_box_sep

        load_gateway_env
        SAVED_LAN_IP=$(get_current_lan_ip)
        SAVED_SUB_URL="$SUB_URL"
        SAVED_GW_IP="$GW_IP"
        SAVED_PASS="$ADMIN_PASS"
        SAVED_AGH_USER=""

        if [ -f "$AGH_CONF" ]; then
            SAVED_AGH_USER=$(sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "$AGH_CONF" | head -n 1 | tr -d ' \t\r\n"')
        fi

        # 1. Запрос ссылки на подписку, прямого ключа или бесплатного гибридного WARP
        USE_INITIAL_WARP="no"
        if [ -n "$SAVED_SUB_URL" ]; then
            printf "Введите подписку (http://...), ключ (vless://...) или 'warp' [Enter = оставить %s]: " "$SAVED_SUB_URL"
        elif has_my_nodes; then
            printf "Введите подписку (http://...), ключ или 'warp' [Enter = оставить ключи в my_nodes.yaml]: "
        elif is_warp_enabled; then
            printf "Введите подписку (http://...), ключ или 'warp' [Enter = оставить текущий Amnezia WARP]: "
        else
            printf "Введите подписку (http://...), ключ (vless://...) или 'warp' (бесплатный WARP 2.0 + MASQUE H2): "
        fi
        read -r INPUT_SUB_URL < /dev/tty || true
        INPUT_SUB_URL=$(printf "%s" "$INPUT_SUB_URL" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ -n "$INPUT_SUB_URL" ]; then
            apply_subscription_input "$INPUT_SUB_URL"
        elif [ -z "$SAVED_SUB_URL" ] && ! has_my_nodes && ! is_warp_enabled; then
            printf "Прокси не указаны. Сгенерировать бесплатный безлимитный Amnezia WARP 2.0 + MASQUE H2? (y/n) [Enter = y]: "
            read -r WARP_FALLBACK < /dev/tty || true
            WARP_FALLBACK=$(printf "%s" "$WARP_FALLBACK" | tr -d ' \t\r\n')
            [ -z "$WARP_FALLBACK" ] && WARP_FALLBACK="y"
            case "$WARP_FALLBACK" in
                [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа])
                    USE_INITIAL_WARP="yes"
                    ;;
                *)
                    echo "Бро я не буду этого делать без подписки или ключа ,_."
                    exit 1
                    ;;
            esac
        fi

        if [ "$USE_INITIAL_WARP" = "yes" ]; then
            printf "Если есть ключ лицензии WARP+ (Argo), вставьте его [Enter = обычный бесплатный WARP]: "
            read -r INPUT_WLIC < /dev/tty || true
            INPUT_WLIC=$(printf "%s" "$INPUT_WLIC" | tr -d ' \t\r\n')
            [ -n "$INPUT_WLIC" ] && WARP_LICENSE="$INPUT_WLIC" || true
        fi

        if [ "$USE_INITIAL_WARP" != "yes" ] && [ -n "$INPUT_SUB_URL" ] && is_warp_enabled; then
            printf "Обнаружен ранее созданный пул Amnezia WARP. Оставить его как резерв? (y/n) [Enter = y]: "
            read -r KEEP_WARP_ANS < /dev/tty || true
            KEEP_WARP_ANS=$(printf "%s" "$KEEP_WARP_ANS" | tr -d ' \t\r\n')
            [ -z "$KEEP_WARP_ANS" ] && KEEP_WARP_ANS="y"
            case "$KEEP_WARP_ANS" in
                [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) ;;
                *) echo '{"outbounds": []}' > "$WARP_NODES_FILE" ;;
            esac
        fi

        # 2. Запрос IP-адреса самого сервера и IP основного роутера
        printf "Введите локальный IP самого сервера (%s) [Enter = оставить %s]: " "$OS_NAME" "$SAVED_LAN_IP"
        read -r INPUT_LAN_IP < /dev/tty || true
        INPUT_LAN_IP=$(printf "%s" "$INPUT_LAN_IP" | tr -d ' \t\r\n')
        TARGET_LAN_IP="${INPUT_LAN_IP:-$SAVED_LAN_IP}"
        if ! is_valid_ipv4 "$TARGET_LAN_IP"; then
            echo "${C_RED}[X] Некорректный IP (${TARGET_LAN_IP}), оставлен текущий: ${SAVED_LAN_IP}${C_RES}"
            TARGET_LAN_IP="$SAVED_LAN_IP"
        fi

        if [ -n "$SAVED_GW_IP" ] && [ "$SAVED_GW_IP" != "$TARGET_LAN_IP" ]; then
            printf "Введите IP основного роутера [Enter = %s]: " "$SAVED_GW_IP"
        else
            printf "Введите IP-адрес основного роутера (отличный от %s, например %s.1): " "$TARGET_LAN_IP" "${TARGET_LAN_IP%.*}"
        fi
        read -r INPUT_GW_IP < /dev/tty || true
        INPUT_GW_IP=$(printf "%s" "$INPUT_GW_IP" | tr -d ' \t\r\n')

        if [ -n "$INPUT_GW_IP" ]; then
            GW_IP="$INPUT_GW_IP"
        else
            GW_IP="$SAVED_GW_IP"
        fi

        if ! is_valid_ipv4 "$GW_IP" || [ "$GW_IP" = "$TARGET_LAN_IP" ]; then
            echo "${C_RED}[X] Ошибка: IP основного роутера (${GW_IP}) некорректен или совпадает с IP сервера (${TARGET_LAN_IP})!${C_RES}"
            exit 1
        fi

        # 3. Запрос логина и единого пароля (AdGuard Home + Sing-Box Zashboard + Homelab)
        DEF_AGH_USER="${SAVED_AGH_USER:-admin}"
        printf "Введите логин для панели AdGuard Home [Enter = %s]: " "$DEF_AGH_USER"
        read -r INPUT_AGH_USER < /dev/tty || true
        INPUT_AGH_USER=$(printf "%s" "$INPUT_AGH_USER" | tr -d ' \t\r\n')
        AGH_USER="${INPUT_AGH_USER:-$DEF_AGH_USER}"

        if [ -n "$SAVED_PASS" ]; then
            printf "Введите единый пароль (Шлюз + AdGuard + Homelab) [Enter = оставить текущий]: "
        else
            printf "Введите единый пароль (для AdGuard Home, Sing-Box и сервисов Homelab): "
        fi
        read -r INPUT_PASS < /dev/tty || true
        INPUT_PASS=$(printf "%s" "$INPUT_PASS" | tr -d '\r\n')

        ADMIN_PASS="${INPUT_PASS:-$SAVED_PASS}"
        if [ -z "$ADMIN_PASS" ]; then
            echo "${C_RED}[X] Ошибка: Пароль не может быть пустым!${C_RES}"
            exit 1
        fi
        # Единый логин и пароль из начального опроса автоматически применяются для Samba и всех сервисов Homelab
        SMB_USER="$AGH_USER"
        SMB_PASS="$ADMIN_PASS"

        # 4. Запрос на автообновление
        if is_autoupdate_enabled; then
            DEF_AU_CHAR="y"
        else
            DEF_AU_CHAR="n"
        fi
        printf "Включить автообновление ядер и панелей в 04:00 (Бро я думаю ты осознаешь последствия ,_,)? (y/n) [Enter = %s]: " "$DEF_AU_CHAR"
        read -r INPUT_AU_ANS < /dev/tty || true
        INPUT_AU_ANS=$(printf "%s" "$INPUT_AU_ANS" | tr -d ' \t\r\n')
        [ -z "$INPUT_AU_ANS" ] && INPUT_AU_ANS="$DEF_AU_CHAR"
        case "$INPUT_AU_ANS" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) ENABLE_AU="yes" ;;
            *) ENABLE_AU="no" ;;
        esac

        # 5. Запрос выбора модулей Homelab сразу на старте (чтобы установка шла полностью без остановок)
        echo ""
        ui_box_top "Выбор модулей домашнего сервера (Homelab & Media Stack)"
        echo " Вы можете сразу выбрать нужные домашние сервисы (логин/пароль Samba и сервисов = ${AGH_USER}):"
        echo "  ${C_CYN}[1]${C_RES} caddy       — Центральный HTTPS Reverse Proxy & Локальный CA (*.lan)"
        echo "  ${C_CYN}[2]${C_RES} samba       — Общая сетевая папка SMB2/3 + автообнаружение Windows 11 / Linux"
        echo "  ${C_CYN}[3]${C_RES} vaultwarden — Менеджер паролей Bitwarden (https://vaultwarden.lan)"
        echo "  ${C_CYN}[4]${C_RES} forgejo     — Локальный Git-сервер (https://forgejo.lan)"
        echo "  ${C_CYN}[5]${C_RES} code        — VS Code в браузере Server-Code (https://code.lan)"
        echo "  ${C_CYN}[6]${C_RES} navidrome   — Музыкальный стриминг Subsonic/Spotify-style (https://music.lan)"
        echo "  ${C_CYN}[7]${C_RES} jellyfin    — Домашний кинотеатр Jellyfin (https://jellyfin.lan)"
        echo "  ${C_CYN}[8]${C_RES} ytdlp       — Веб-панель загрузки видео и музыки yt-dlp (https://downloads.lan)"
        echo "  ${C_CYN}[9]${C_RES} torrent     — Торрент-клиент qBittorrent-nox + Hardlink-импорт (https://torrents.lan)"
        ui_box_sep
        printf "Введите номера через пробел (например: 1 2 3 6 8 9), 'all' для всех или Enter (только шлюз): "
        read -r PRE_HL_SEL < /dev/tty || true
        PRE_HL_SEL=$(printf "%s" "$PRE_HL_SEL" | tr ',' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$PRE_HL_SEL" ] || [ "$PRE_HL_SEL" = "0" ] || [ "$PRE_HL_SEL" = "none" ] && PRE_HL_SEL="__SKIP__"
    fi

    ui_box_sep
    echo "Итоговая конфигурация развертывания:"
    echo " - ОС и Память:     ${OS_NAME} | ${TOTAL_RAM_MB} МБ RAM"
    echo " - Ядро шлюза:      shtorm-7/sing-box-extended (${SB_ARCH}, лимит ${SB_GOMEMLIMIT})"
    echo " - IP сервера (LAN):${TARGET_LAN_IP} (интерфейс $(get_lan_ifname), маска /24)"
    echo " - Основной роутер: ${GW_IP}"
    echo " - DNS и Домены:    AdGuard Home (0.0.0.0:53 + *.lan) -> Sing-Box (127.0.0.1:1053)"
    echo " - Хранилище:       ${STORAGE_ROOT} (Music, Videos/Movies, Videos/Series, Downloads)"
    echo " - Единый логин:    ${AGH_USER} (AdGuard + Samba + Homelab) / Пароль: [СКРЫТ]"
    echo " - Модули Homelab:  ${PRE_HL_SEL}"
    ui_box_sep

    sync_clock() {
        echo "Синхронизация системных часов..."
        /usr/sbin/ntpd -n -q -p 162.159.200.1 -p 216.239.35.0 -p ntp.ix.ru -p pool.ntp.org 2>/dev/null || true
        if [ "$(date +%Y)" -lt 2026 ]; then
            TS=$(wget -qO- "http://1.1.1.1/cdn-cgi/trace" 2>/dev/null | awk -F= '/^ts=/ {split($2,a,"."); print a[1]}')
            [ -n "$TS" ] && date -s "@$TS" >/dev/null 2>&1 || true
        fi
        hwclock -w -u 2>/dev/null || true
        rc-update add ntpd default >/dev/null 2>&1 || true
        rc-service ntpd start >/dev/null 2>&1 || true
        return 0
    }

    # ЭТАП 1: Настройка сети, синхронизация времени и установка базовых пакетов Alpine Linux
    write_resolv_conf "nameserver ${GW_IP}
nameserver 77.88.8.8
nameserver 77.88.8.1"

    LAN_IF_INIT=$(get_lan_ifname)
    ip -4 route show default 2>/dev/null | grep -q "default" || \
        ip -4 route add default via "$GW_IP" dev "$LAN_IF_INIT" 2>/dev/null || true

    sync_clock
    ensure_alpine_community_repo

    echo "Проверка и установка базовых пакетов Alpine Linux..."
    ALP_PKGS="ca-certificates curl gzip tar jq iproute2 conntrack-tools wireguard-tools-wg apache2-utils nftables tzdata sqlite acl"
    apk update >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    apk add $ALP_PKGS || true
    disable_apache_daemon
    ensure_alpine_modules

    if [ -f /usr/share/zoneinfo/Europe/Moscow ] && [ ! -f /etc/localtime ]; then
        cp -f /usr/share/zoneinfo/Europe/Moscow /etc/localtime 2>/dev/null || true
        echo "Europe/Moscow" > /etc/timezone 2>/dev/null || true
    fi

    write_alpine_static_interfaces "$LAN_IF_INIT" "$TARGET_LAN_IP" "$GW_IP"
    if [ "$TARGET_LAN_IP" = "$SAVED_LAN_IP" ]; then
        killall -9 udhcpc >/dev/null 2>&1 || true
        ip -4 addr replace "${TARGET_LAN_IP}/24" dev "$LAN_IF_INIT" 2>/dev/null || true
        ip link set "$LAN_IF_INIT" up 2>/dev/null || true
        ip -4 route replace default via "$GW_IP" dev "$LAN_IF_INIT" 2>/dev/null || true
    fi

    CURRENT_IP="$TARGET_LAN_IP"

    mkdir -p /etc/sysctl.d
    cat << SYS_EOF > /etc/sysctl.d/99-gateway-forward.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 0
net.core.default_qdisc = fq_codel
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_max = ${SYS_BUF_MAX}
net.core.wmem_max = ${SYS_BUF_MAX}
net.netfilter.nf_conntrack_max = ${SYS_CONNTRACK_MAX}
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 180
net.ipv4.tcp_congestion_control = bbr
fs.inotify.max_user_watches = 524288
net.ipv4.ip_unprivileged_port_start = 0
SYS_EOF

    sysctl -e -p /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || true
    sync_dns_firewall "yes" "keep"

    if [ "$USE_INITIAL_WARP" = "yes" ]; then
        generate_amnezia_warp "${WARP_LICENSE:-}" || true
    fi

    # ЭТАП 2: Загрузка/обновление ядер Sing-Box Extended и AdGuard Home
    update_cores_only "no"

    # ЭТАП 3: Генерация конфига Sing-Box Extended и установка веб-панели Zashboard
    service_ctl sing-box stop
    if [ ! -f "${SB_DIR}/ui/index.html" ]; then
        install_zashboard_ui || true
    else
        echo "${C_GRN}[✓] Веб-панель Zashboard уже установлена.${C_RES}"
    fi
    generate_singbox_config

    # ЭТАП 4: Настройка AdGuard Home с автоматической поддержкой локальных доменов *.lan
    echo "Генерация bcrypt-хэша пароля..."
    AGH_PASS_HASH=""
    if command -v htpasswd >/dev/null 2>&1; then
        AGH_PASS_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$AGH_PASS_HASH" ] && AGH_PASS_HASH=$(htpasswd -nbBC 10 "$AGH_USER" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true) || true
    fi
    disable_apache_daemon
    [ -z "$AGH_PASS_HASH" ] && { echo "${C_RED}[X] Ошибка генерации bcrypt-хэша!${C_RES}"; exit 1; }

    service_ctl adguardhome stop
    mkdir -p /etc/AdGuardHome/data

    if [ -f "$AGH_CONF" ]; then
        awk -v u="$AGH_USER" -v h="$AGH_PASS_HASH" -v gw="$GW_IP" '
            /^users:/ {
                print "users:"
                print "  - name: " u
                print "    password: " h
                in_users=1; next
            }
            in_users && /^[^[:space:]]/ { in_users=0 }
            in_users { next }
            /^[[:space:]]*upstream_dns:/ {
                print "  upstream_dns: [127.0.0.1:1053]"
                in_list=1; next
            }
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
        ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv "${AGH_CONF}.tmp" "$AGH_CONF"
        grep -q "aaaa_disabled:" "$AGH_CONF" 2>/dev/null || sed -i '/cache_size:/a \  aaaa_disabled: true' "$AGH_CONF" 2>/dev/null || true
        sync_agh_homelab_rewrites "$CURRENT_IP"
        chmod 600 "$AGH_CONF" 2>/dev/null || true
    else
        cat << AGH_EOF > "$AGH_CONF"
http:
  address: 0.0.0.0:3000
  session_ttl: 720h
users:
  - name: ${AGH_USER}
    password: ${AGH_PASS_HASH}
auth_attempts: 5
block_auth_min: 15
language: ru
theme: auto
dns:
  bind_hosts: [0.0.0.0]
  port: 53
  upstream_dns: [127.0.0.1:1053]
  bootstrap_dns: [${GW_IP}, 77.88.8.8, 77.88.8.1]
  upstream_mode: load_balance
  cache_enabled: false
  cache_size: 0
  aaaa_disabled: true
  enable_dnssec: false
  use_private_ptr_resolvers: true
  local_ptr_upstreams: [${GW_IP}:53]
  serve_plain_dns: true
  pending_requests: { enabled: true }
tls: { enabled: false }
querylog: { enabled: true, interval: 24h, file_enabled: false }
statistics: { enabled: true, interval: 24h }
filters:
  - { enabled: true, url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt, name: AdGuard DNS filter, id: 1 }
  - { enabled: true, url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt, name: AdAway Default Blocklist, id: 2 }
  - { enabled: true, url: https://filters.adtidy.org/extension/chromium/filters/1.txt, name: AdGuard Russian Filter, id: 3 }
filtering: { protection_enabled: true, filtering_enabled: true }
schema_version: 34
AGH_EOF
        sync_agh_homelab_rewrites "$CURRENT_IP"
        chmod 600 "$AGH_CONF" 2>/dev/null || true
    fi

    # ЭТАП 5: Регистрация и запуск служб шлюза
    setup_init_scripts

    write_resolv_conf "nameserver 127.0.0.1
nameserver ${GW_IP}
nameserver 77.88.8.8"

    enable_watchdog
    if [ "$ENABLE_AU" = "yes" ]; then
        enable_autoupdate
    else
        disable_autoupdate
    fi

    # ЭТАП 5.5: Автоматическая настройка внешнего накопителя из файла ответов
    if [ "$IS_UNATTENDED" = "yes" ] && [ -n "$ANS_STORAGE_DISK" ] && [ "$ANS_STORAGE_DISK" != "none" ]; then
        ui_step_progress 1 1 "Настройка внешнего хранилища (${ANS_STORAGE_DISK})..."
        if [ "$ANS_STORAGE_DISK" = "auto" ]; then
            AUTO_D=$(get_first_available_external_disk)
            if [ -n "$AUTO_D" ]; then
                ANS_STORAGE_DISK="$AUTO_D"
                ui_info_msg "Автоматически обнаружен внешний накопитель: ${ANS_STORAGE_DISK}"
            else
                ui_warn_box "STORAGE_DISK='auto', но внешние накопители не обнаружены." \
                            "Хранилище останется на системном разделе."
                ANS_STORAGE_DISK=""
            fi
        fi
        if [ -n "$ANS_STORAGE_DISK" ]; then
            if [ "$ANS_STORAGE_ACTION" = "format" ]; then
                format_and_mount_external_drive "$ANS_STORAGE_DISK" "$ANS_STORAGE_FS" "$ANS_STORAGE_LUKS" "YES" "$ANS_STORAGE_LUKS_PASS" || true
            else
                mount_external_drive_to_storage "$ANS_STORAGE_DISK" "yes" "$ANS_STORAGE_LUKS_PASS" || true
            fi
        fi
    fi

    # ЭТАП 6: Автоматическая установка выбранных на старте модулей Homelab
    prompt_homelab_modules_wizard "${PRE_HL_SEL:-__SKIP__}"

    # ЭТАП 6.5: Автоматическая настройка Let's Encrypt Wildcard DuckDNS из файла ответов
    if [ "$IS_UNATTENDED" = "yes" ] && [ "$ANS_SSL_TYPE" = "duckdns" ] && [ -n "$ANS_DUCK_SUB" ] && [ -n "$ANS_DUCK_TOK" ]; then
        ui_step_progress 1 1 "Выпуск Let's Encrypt Wildcard сертификата DuckDNS (${ANS_DUCK_SUB})..."
        if issue_duckdns_cert "$ANS_DUCK_SUB" "$ANS_DUCK_TOK"; then
            sync_caddy_main_config
            reload_caddy_safe
            sync_agh_homelab_rewrites "$CURRENT_IP"
        fi
    fi

    # ЭТАП 7: Итоговый Self-Test 2.0
    reload_singbox_api
    run_self_test

    ui_box_top "=================================================="
    echo "${C_GRN} Развертывание на ${OS_NAME} успешно завершено!${C_RES}"
    echo " - IP-адрес сервера:   ${C_BLD}${CURRENT_IP}${C_RES} (интерфейс $(get_lan_ifname), маска /24)"
    echo " - Основной роутер:    ${GW_IP}"
    echo " - Панель Sing-Box:    ${C_CYN}https://${DOM_ZASHBOARD}${C_RES} (http://${CURRENT_IP}:9090/ui)"
    echo " - Панель AdGuard:     ${C_CYN}https://${DOM_ADGUARD}${C_RES} (http://${CURRENT_IP}:3000)"
    echo " - Портал сертификата: ${C_CYN}http://${DOM_CA}${C_RES}"
    echo " - Быстрый вызов:      ${C_GRN}gw${C_RES} (или ${C_GRN}gateway${C_RES})"
    ui_box_top "=================================================="
    print_quick_access_card

    if [ "$TARGET_LAN_IP" != "$SAVED_LAN_IP" ]; then
        apply_network_ips "$TARGET_LAN_IP" "$GW_IP" || true
    fi
    return 0
}

# Матрица глубокой диагностики шлюза и стека Homelab (Self-Test 2.0 с визуальными шкалами Ping Matrix)
