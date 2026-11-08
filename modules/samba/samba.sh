#!/bin/sh
set -e

# ==============================================================================
# Модуль Samba (SMB2/3) + WSDD + Avahi
# Единое сетевое хранилище (Storage, Music, Videos, Downloads)
# ==============================================================================

if [ -z "${GATEWAY_DIR:-}" ]; then
    GATEWAY_DIR="$(cd -P "$(dirname "$0")/../.." && pwd)"
    . "${GATEWAY_DIR}/lib/constants.sh"
    . "${GATEWAY_DIR}/lib/ui.sh"
    . "${GATEWAY_DIR}/lib/core.sh"
    . "${GATEWAY_DIR}/lib/env.sh"
    . "${GATEWAY_DIR}/lib/env_store.sh"
    . "${GATEWAY_DIR}/modules/network/lan.sh"
    . "${GATEWAY_DIR}/modules/network/firewall.sh"
    . "${GATEWAY_DIR}/modules/adguard/adguard.sh"
    . "${GATEWAY_DIR}/modules/homelab/registry.sh"
fi

setup_wsdd_and_avahi() {
    LAN_IF=$(get_lan_ifname)
    HN_SHORT=$(hostname -s 2>/dev/null || echo "homelab")
    [ -z "$HN_SHORT" ] && HN_SHORT="homelab"

    # 1. Настройка wsdd (Web Services Dynamic Discovery для Windows 10/11 без SMB1)
    if [ -f /etc/init.d/wsdd ]; then
        cat << WSDD_EOF > /etc/conf.d/wsdd
# Привязка строго к физическому LAN-интерфейсу и IPv4 (в обход singbox-tun)
WSDD_OPTS="-4 -i ${LAN_IF} -w WORKGROUP -n ${HN_SHORT}"
command_args="-4 -i ${LAN_IF} -w WORKGROUP -n ${HN_SHORT}"
WSDD_EOF
        service_ctl wsdd enable
        service_ctl wsdd restart || true
    fi

    # 2. Настройка Avahi mDNS (обнаружение шары в файловых менеджерах Linux: GNOME Files, Dolphin, Thunar)
    if [ -d /etc/avahi ]; then
        mkdir -p /etc/avahi/services
        if [ -f /etc/avahi/avahi-daemon.conf ]; then
            sed -i "s|^#*\s*use-ipv4=.*|use-ipv4=yes|; s|^#*\s*use-ipv6=.*|use-ipv6=no|; s|^#*\s*allow-interfaces=.*|allow-interfaces=${LAN_IF}|" /etc/avahi/avahi-daemon.conf 2>/dev/null || true
            if ! grep -q '^allow-interfaces=' /etc/avahi/avahi-daemon.conf 2>/dev/null; then
                sed -i "/^\[server\]/a allow-interfaces=${LAN_IF}" /etc/avahi/avahi-daemon.conf 2>/dev/null || true
            fi
        fi
        cat << AVAHI_SMB > /etc/avahi/services/smb.service
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=RackMac</txt-record>
  </service>
</service-group>
AVAHI_SMB
        service_ctl dbus enable
        service_ctl dbus start || true
        service_ctl avahi-daemon enable
        service_ctl avahi-daemon restart || true
    fi
    return 0
}

# Применение и строгая верификация пароля пользователя в базе Samba (passdb.tdb) и Unix
apply_and_verify_samba_password() {
    TARGET_SMB_USER="${1:-${SMB_USER:-homelab}}"
    TARGET_SMB_PASS="${2:-${SMB_PASS:-${ADMIN_PASS:-}}}"

    if [ -z "$TARGET_SMB_USER" ] || [ -z "$TARGET_SMB_PASS" ]; then
        echo "${C_RED}[X] Ошибка Samba: Логин или пароль пусты!${C_RES}" >&2
        return 1
    fi

    ensure_media_group_and_users
    mkdir -p /var/lib/samba/private /var/lib/samba /var/cache/samba /var/log/samba /run/samba /etc/samba
    chmod 700 /var/lib/samba/private 2>/dev/null || true
    chmod 755 /var/lib/samba /etc/samba /var/log/samba 2>/dev/null || true

    # Синхронизация системной учетной записи (разблокировка в /etc/shadow и установка пароля)
    if command -v chpasswd >/dev/null 2>&1; then
        printf "%s:%s\n" "$TARGET_SMB_USER" "$TARGET_SMB_PASS" | chpasswd >/dev/null 2>&1 || true
    fi
    if [ -f /etc/shadow ] && grep -q "^${TARGET_SMB_USER}:!" /etc/shadow 2>/dev/null; then
        sed -i "s/^${TARGET_SMB_USER}:!/${TARGET_SMB_USER}:*/" /etc/shadow 2>/dev/null || true
    fi

    if ! command -v smbpasswd >/dev/null 2>&1; then
        return 1
    fi

    # Добавление/обновление пользователя в passdb.tdb и снятие флагов блокировки/отключения
    if ! printf "%s\n%s\n" "$TARGET_SMB_PASS" "$TARGET_SMB_PASS" | smbpasswd -a -s "$TARGET_SMB_USER" >/dev/null 2>&1; then
        if command -v pdbedit >/dev/null 2>&1; then
            printf "%s\n%s\n" "$TARGET_SMB_PASS" "$TARGET_SMB_PASS" | pdbedit -a -u "$TARGET_SMB_USER" -t >/dev/null 2>&1 || return 1
        else
            return 1
        fi
    fi
    smbpasswd -e "$TARGET_SMB_USER" >/dev/null 2>&1 || true

    # Верификация наличия активного пользователя и непустого NT-хэша в базе Samba
    if command -v pdbedit >/dev/null 2>&1; then
        PDB_LINE=$(pdbedit -L -w "$TARGET_SMB_USER" 2>/dev/null | grep -E "^${TARGET_SMB_USER}:" | head -n 1 || true)
        if [ -z "$PDB_LINE" ]; then
            echo "${C_RED}[X] Ошибка: Пользователь ${TARGET_SMB_USER} отсутствует в базе passdb.tdb после smbpasswd!${C_RES}" >&2
            return 1
        fi
        NT_HASH=$(printf "%s" "$PDB_LINE" | awk -F':' '{print $4}')
        ACCT_FLAGS=$(printf "%s" "$PDB_LINE" | awk -F':' '{print $5}')
        if [ -z "$NT_HASH" ] || [ "$NT_HASH" = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" ]; then
            echo "${C_RED}[X] Ошибка: В базе Samba сохранен пустой NT-хэш для ${TARGET_SMB_USER}!${C_RES}" >&2
            return 1
        fi
        case "$ACCT_FLAGS" in
            *D*|*L*)
                echo "${C_RED}[X] Ошибка: Учетная запись Samba ${TARGET_SMB_USER} заблокирована (${ACCT_FLAGS})!${C_RES}" >&2
                return 1
                ;;
        esac
    fi

    # Если smbd уже запущен и установлен smbclient — проверяем реальную SMB2/3 авторизацию
    if command -v smbclient >/dev/null 2>&1 && rc-service samba status >/dev/null 2>&1; then
        PASS_TMP="/tmp/.smb_auth_check.$$"
        trap 'rm -f "$PASS_TMP" 2>/dev/null || true' EXIT INT TERM
        umask 077
        printf "username = %s\npassword = %s\n" "$TARGET_SMB_USER" "$TARGET_SMB_PASS" > "$PASS_TMP"
        umask 022
        SMB_CHECK_OUT=$(smbclient -L //127.0.0.1 -A "$PASS_TMP" -m SMB3 2>&1 || true)
        rm -f "$PASS_TMP" 2>/dev/null || true
        trap - EXIT INT TERM
        if printf "%s" "$SMB_CHECK_OUT" | grep -Eq "NT_STATUS_LOGON_FAILURE|NT_STATUS_ACCOUNT_DISABLED|NT_STATUS_ACCESS_DENIED"; then
            echo "${C_RED}[X] Ошибка проверки входа Samba (smbclient): неверный пароль или доступ запрещен!${C_RES}" >&2
            return 1
        fi
    fi
    return 0
}

# Интерактивная или автоматическая настройка учетных данных Samba
configure_samba_credentials() {
    PROMPT_MODE="${1:-auto}"
    load_gateway_env

    if [ "$PROMPT_MODE" = "interactive" ]; then
        printf "Введите имя пользователя для сетевой папки Samba [Enter = %s]: " "${SMB_USER:-${AGH_USER:-homelab}}"
        read -r IN_SMBU < /dev/tty || true
        IN_SMBU=$(printf "%s" "$IN_SMBU" | tr -d ' \t\r\n')
        [ -n "$IN_SMBU" ] && SMB_USER="$IN_SMBU"

        if [ -n "${SMB_PASS:-}" ]; then
            printf "Введите пароль для Samba [Enter = оставить сохраненный пароль Samba / 'gw' = единый пароль шлюза]: "
        else
            printf "Введите пароль для Samba [Enter = использовать единый пароль шлюза]: "
        fi
        read -r IN_SMBP < /dev/tty || true
        IN_SMBP=$(printf "%s" "$IN_SMBP" | tr -d '\r\n')
        if [ "$IN_SMBP" = "gw" ] || [ "$IN_SMBP" = "GW" ]; then
            SMB_PASS="${ADMIN_PASS:-admin}"
        elif [ -n "$IN_SMBP" ]; then
            SMB_PASS="$IN_SMBP"
        elif [ -z "${SMB_PASS:-}" ]; then
            SMB_PASS="${ADMIN_PASS:-admin}"
        fi
    else
        [ -z "${SMB_USER:-}" ] && SMB_USER="${AGH_USER:-homelab}"
        [ -z "${SMB_PASS:-}" ] && SMB_PASS="${ADMIN_PASS:-admin}"
    fi

    # Сначала сохраняем новые учетные данные на диск, и только затем создаем/обновляем системного пользователя
    save_homelab_env
    ensure_media_group_and_users
    return 0
}

# Генерация и проверка конфигурации /etc/samba/smb.conf (совместимость с Windows 11 24H2+ и Linux)
write_samba_config() {
    load_gateway_env
    LAN_IF=$(get_lan_ifname)
    HN_VAL=$(hostname -s 2>/dev/null || echo "HOMELAB")
    [ -z "$HN_VAL" ] && HN_VAL="HOMELAB"

    mkdir -p /etc/samba /var/log/samba /var/lib/samba/private /var/cache/samba /run/samba
    chmod 700 /var/lib/samba/private 2>/dev/null || true
    cat << SMB_EOF > /etc/samba/smb.conf.tmp.$$
[global]
   workgroup = WORKGROUP
   netbios name = ${HN_VAL}
   server string = Alpine Homelab Storage
   server role = standalone server
   interfaces = lo ${LAN_IF}
   bind interfaces only = yes
   hosts allow = 127. 10. 172.16. 172.17. 172.18. 172.19. 172.20. 172.21. 172.22. 172.23. 172.24. 172.25. 172.26. 172.27. 172.28. 172.29. 172.30. 172.31. 192.168. 100.64.
   security = user
   passdb backend = tdbsam:/var/lib/samba/private/passdb.tdb
   map to guest = Never
   ntlm auth = ntlmv2-only
   server min protocol = SMB2_10
   server max protocol = SMB3
   smb encrypt = desired
   server signing = mandatory
   disable netbios = yes
   smb ports = 445
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   use sendfile = yes
   aio read size = 16384
   aio write size = 16384
   unix charset = UTF-8
   dos charset = CP866

[storage]
   comment = Homelab Unified Storage
   path = ${STORAGE_ROOT}
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = ${SMB_USER} @${MEDIA_GROUP}
   write list = ${SMB_USER} @${MEDIA_GROUP}
   force user = ${SMB_USER}
   force group = ${MEDIA_GROUP}
   create mask = 0664
   force create mode = 0664
   directory mask = 2775
   force directory mode = 2775
   inherit permissions = yes
   inherit acls = yes
   map archive = no
   map hidden = no
   map system = no
   store dos attributes = no
   mangled names = no
   hide dot files = yes

[Music]
   comment = Homelab Music Library
   path = ${STORAGE_MUSIC}
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = ${SMB_USER} @${MEDIA_GROUP}
   write list = ${SMB_USER} @${MEDIA_GROUP}
   force user = ${SMB_USER}
   force group = ${MEDIA_GROUP}
   create mask = 0664
   force create mode = 0664
   directory mask = 2775
   force directory mode = 2775
   inherit permissions = yes
   inherit acls = yes
   map archive = no
   map hidden = no
   map system = no
   store dos attributes = no
   mangled names = no
   hide dot files = yes

[Videos]
   comment = Homelab Videos Library
   path = ${STORAGE_VIDEOS}
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = ${SMB_USER} @${MEDIA_GROUP}
   write list = ${SMB_USER} @${MEDIA_GROUP}
   force user = ${SMB_USER}
   force group = ${MEDIA_GROUP}
   create mask = 0664
   force create mode = 0664
   directory mask = 2775
   force directory mode = 2775
   inherit permissions = yes
   inherit acls = yes
   map archive = no
   map hidden = no
   map system = no
   store dos attributes = no
   mangled names = no
   hide dot files = yes

[Downloads]
   comment = Homelab Downloads & Torrents
   path = ${STORAGE_DOWNLOADS}
   browseable = yes
   writable = yes
   read only = no
   guest ok = no
   valid users = ${SMB_USER} @${MEDIA_GROUP}
   write list = ${SMB_USER} @${MEDIA_GROUP}
   force user = ${SMB_USER}
   force group = ${MEDIA_GROUP}
   create mask = 0664
   force create mode = 0664
   directory mask = 2775
   force directory mode = 2775
   inherit permissions = yes
   inherit acls = yes
   map archive = no
   map hidden = no
   map system = no
   store dos attributes = no
   mangled names = no
   hide dot files = yes
SMB_EOF

    if command -v testparm >/dev/null 2>&1; then
        if ! testparm -s /etc/samba/smb.conf.tmp.$$ >/dev/null 2>&1; then
            echo "${C_RED}[X] Ошибка валидации синтаксиса smb.conf через testparm!${C_RES}" >&2
            rm -f /etc/samba/smb.conf.tmp.$$ 2>/dev/null || true
            return 1
        fi
    fi
    chmod 644 /etc/samba/smb.conf.tmp.$$ 2>/dev/null || true
    mv -f /etc/samba/smb.conf.tmp.$$ /etc/samba/smb.conf
    return 0
}

# Установка и настройка модуля Samba + WSDD + Avahi
install_module_samba() {
    PROMPT_CRED="${1:-auto}"
    echo "${C_CYN}[*] Установка модуля Samba (SMB2/SMB3) + WSDD (Windows 11) + Avahi (Linux)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add samba-server samba-common-tools samba-client wsdd wsdd-openrc avahi dbus acl shadow; then
        if ! apk add samba-server samba-common-tools wsdd wsdd-openrc avahi dbus acl; then
            echo "${C_RED}[X] Не удалось установить пакеты samba-server / wsdd!${C_RES}"
            return 1
        fi
    fi

    init_homelab_storage
    configure_samba_credentials "$PROMPT_CRED"
    repair_storage_permissions

    if ! write_samba_config; then
        return 1
    fi

    # Отключаем устаревший nmbd (SMB1 NetBIOS), оставляем только smbd
    if [ -f /etc/conf.d/samba ]; then
        sed -i 's|^daemon_list=.*|daemon_list="smbd"|' /etc/conf.d/samba 2>/dev/null || true
    fi

    if ! apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS"; then
        echo "${C_RED}[X] Не удалось применить и верифицировать пароль Samba для пользователя ${SMB_USER}!${C_RES}"
        return 1
    fi

    service_ctl samba enable
    if ! service_ctl samba restart; then
        echo "${C_RED}[X] Служба Samba (smbd) не смогла запуститься! Проверьте /var/log/samba/log.smbd.${C_RES}"
        return 1
    fi

    # Повторная проверка через живой демон smbd (если установлен smbclient)
    apply_and_verify_samba_password "$SMB_USER" "$SMB_PASS" || return 1

    setup_wsdd_and_avahi
    sync_dns_firewall "yes" "keep"
    set_module_state "samba" "yes"

    HN_VAL=$(hostname -s 2>/dev/null || echo "HOMELAB")
    CUR_LIP=$(get_current_lan_ip)
    echo "${C_GRN}[✓] Сетевое хранилище Samba успешно запущено, пароль проверен в passdb.tdb!${C_RES}"
    echo "    • Windows 11 Проводник: ${C_CYN}\\\\${HN_VAL}\\storage${C_RES} или ${C_CYN}\\\\${CUR_LIP}\\storage${C_RES}"
    echo "    • Файловые менеджеры Linux: ${C_CYN}smb://${CUR_LIP}/storage${C_RES}"
    echo "    • Логин: ${C_BLD}${SMB_USER}${C_RES} (пароль синхронизирован и проверен)"
    return 0
}

remove_module_samba() {
    echo "Остановка и отключение Samba, WSDD и Avahi..."
    service_ctl samba stop || true
    service_ctl samba disable || true
    service_ctl wsdd stop || true
    service_ctl wsdd disable || true
    service_ctl avahi-daemon stop || true
    service_ctl avahi-daemon disable || true
    set_module_state "samba" "no"
    echo "${C_GRN}[✓] Модуль Samba отключен (все файлы в ${STORAGE_ROOT} сохранены).${C_RES}"
    return 0
}

if [ "${0##*/}" = "samba.sh" ]; then
    case "${1:-status}" in
        install) install_module_samba "${2:-auto}" ;;
        remove)  remove_module_samba ;;
        restart) service_ctl samba restart ;;
        status)  service_ctl samba status ;;
        *)       echo "Использование: $0 [install|remove|restart|status]" ;;
    esac
fi
