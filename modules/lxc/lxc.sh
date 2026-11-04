#!/bin/sh
# ==============================================================================
# Модуль LXC (Linux Containers) для Universal Gateway & Homelab
# Полноценная виртуализация ОС на базе пространств имен ядра и cgroups v2.
# Поддержка официальных шаблонов (images.linuxcontainers.org), снимков (снапшотов),
# сетевой изоляции (lxcbr0 / macvlan) и интеграции с хранилищем /srv/storage/lxc.
# ==============================================================================

LXC_STORAGE_DIR="/srv/storage/lxc"
LXC_VAR_LIB="/var/lib/lxc"

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
    command -v lxc-create >/dev/null 2>&1 || MISSING_LXC_PKGS="$MISSING_LXC_PKGS lxc lxc-openrc lxc-bridge lxc-download lxc-templates lxcfs lxcfs-openrc bridge-utils dnsmasq cgroup-tools"
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
                # Переносим существующие контейнеры при первой привязке
                cp -a "${LXC_VAR_LIB}/." "${LXC_STORAGE_DIR}/" 2>/dev/null || true
                rm -rf "$LXC_VAR_LIB"
            fi
            ln -sfn "$LXC_STORAGE_DIR" "$LXC_VAR_LIB"
        fi
    else
        mkdir -p "$LXC_VAR_LIB"
        chmod 755 "$LXC_VAR_LIB" 2>/dev/null || true
    fi

    # 4. Настройка сетевого моста lxcbr0 и DHCP (dnsmasq с port=0)
    mkdir -p /etc/conf.d /etc/lxc
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

    # port=0 отключает встроенный DNS dnsmasq, чтобы не конфликтовать с AdGuard Home (:53)
    # dhcp-option передает контейнерам адрес шлюза как DNS-резолвер
    cat << 'DNSM_EOF' > /etc/lxc/dnsmasq.conf
port=0
dhcp-option=option:dns-server,10.0.3.1
DNSM_EOF

    # Конфигурация интерфейса по умолчанию для новых контейнеров
    cat << 'DEF_EOF' > /etc/lxc/default.conf
lxc.net.0.type = veth
lxc.net.0.link = lxcbr0
lxc.net.0.flags = up
lxc.net.0.hwaddr = 10:66:6a:xx:xx:xx
DEF_EOF

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
    printf "  ${C_CYN}%-16s %-12s %-16s %-10s %-8s %-10s${C_RES}\n" "ИМЯ" "СТАТУС" "IPV4" "ПАМЯТЬ" "АВТО" "СНАПШОТЫ"
    echo "  ──────────────────────────────────────────────────────────────────────────"

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

        # Цветовая подсветка
        if [ "$STATE" = "RUNNING" ]; then
            STATE_FMT="${C_GRN}● RUNNING${C_RES} "
        else
            STATE_FMT="${C_DGR}○ STOPPED${C_RES} "
        fi

        printf "  %-16s %b %-16s %-10s %-8s %-10s\n" \
               "$CT_NAME" "$STATE_FMT" "$IPV4" "$MEM_USE" "$AUTO_VAL" "${SNAPS_COUNT} шт."
    done

    if [ "$CT_FOUND" -eq 0 ]; then
        ui_box_row "Контейнеры еще не созданы. Для создания выберите пункт 'Создать контейнер'."
    fi
    ui_box_bottom
    echo ""
    return 0
}

# Интерактивное создание нового контейнера с загрузкой официального шаблона
lxc_create_wizard() {
    ensure_lxc_subsystem "no"
    ui_banner "LXC // МАСТЕР СОЗДАНИЯ КОНТЕЙНЕРА"

    LXC_ARCH=$(get_lxc_system_arch)

    echo "${C_BOLD}Введите имя нового контейнера (латиница, цифры, дефис):${C_RES}"
    read -r CT_NAME
    CT_NAME=$(echo "$CT_NAME" | tr -cd 'a-zA-Z0-9_-')
    if [ -z "$CT_NAME" ]; then
        ui_warn_msg "Имя контейнера не может быть пустым. Отмена."
        return 1
    fi

    if [ -d "${LXC_VAR_LIB}/${CT_NAME}" ]; then
        ui_warn_msg "Контейнер с именем '${CT_NAME}' уже существует!"
        return 1
    fi

    echo ""
    ui_info_msg "Выберите дистрибутив операционной системы для загрузки:"
    echo "  1) Alpine Linux 3.24 (Ультралегкий ~2MB, рекомендован для микросервисов)"
    echo "  2) Alpine Linux 3.23"
    echo "  3) Debian 12 (Bookworm) (Стандартный серверный glibc дистрибутив)"
    echo "  4) Ubuntu 24.04 LTS (Noble Numbat)"
    echo "  5) Ubuntu 22.04 LTS (Jammy Jellyfish)"
    echo "  6) AlmaLinux 9 (RHEL 9 совместимый корпоративный Linux)"
    echo "  7) Arch Linux (Свежие rolling-release пакеты)"
    echo "  8) Ввести произвольный дистрибутив и релиз из images.linuxcontainers.org"
    echo ""
    printf "Ваш выбор [1-8, по умолчанию 1]: "
    read -r DIST_CHOICE

    T_DIST="alpine"
    T_REL="3.24"
    case "$DIST_CHOICE" in
        2) T_DIST="alpine"; T_REL="3.23" ;;
        3) T_DIST="debian"; T_REL="bookworm" ;;
        4) T_DIST="ubuntu"; T_REL="noble" ;;
        5) T_DIST="ubuntu"; T_REL="jammy" ;;
        6) T_DIST="almalinux"; T_REL="9" ;;
        7) T_DIST="archlinux"; T_REL="current" ;;
        8)
            echo "Введите название дистрибутива (например, fedora, debian, opensuse):"
            read -r T_DIST
            echo "Введите версию релиза (например, 41, sid, tumbleweed):"
            read -r T_REL
            ;;
        *) T_DIST="alpine"; T_REL="3.24" ;;
    esac

    echo ""
    ui_info_msg "Выберите режим сетевого подключения:"
    echo "  1) NAT / Изолированный мост lxcbr0 (10.0.3.X, DNS AdGuard, трафик через Sing-Box) [Рекомендуется]"
    echo "  2) Прямой мост в домашнюю сеть (Macvlan на $(get_lan_ifname), свой IP от домашнего роутера)"
    printf "Ваш выбор [1-2, по умолчанию 1]: "
    read -r NET_CHOICE
    [ -z "$NET_CHOICE" ] && NET_CHOICE="1"

    echo ""
    ui_info_msg "Ограничение оперативной памяти (cgroups v2):"
    echo "  Введите лимит (например: 256M, 512M, 1G) или нажмите Enter для безлимитного:"
    read -r MEM_LIMIT

    echo ""
    ui_info_msg "Включить автозапуск контейнера при старте сервера Gateway?"
    printf "Автозапуск (y/n, по умолчанию y): "
    read -r AUTO_START_ANS
    [ -z "$AUTO_START_ANS" ] && AUTO_START_ANS="y"

    echo ""
    ui_box_top "🚀 ПАРАМЕТРЫ СОЗДАНИЯ КОНТЕЙНЕРА"
    ui_box_row "• Имя:          ${CT_NAME}"
    ui_box_row "• Дистрибутив:  ${T_DIST} (релиз: ${T_REL}, архитектура: ${LXC_ARCH})"
    ui_box_row "• Сеть:         $([ "$NET_CHOICE" = "2" ] && echo "Macvlan (LAN direct)" || echo "NAT (lxcbr0, 10.0.3.X)")"
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
    CT_CONF="${LXC_VAR_LIB}/${CT_NAME}/config"
    if [ -f "$CT_CONF" ]; then
        ui_step_progress 2 3 "Применение параметров сети, лимитов и автозапуска..."

        if [ "$NET_CHOICE" = "2" ]; then
            # Переопределение на Macvlan
            LAN_IF=$(get_lan_ifname)
            sed -i '/lxc\.net\.0\./d' "$CT_CONF"
            cat << NET_MACVLAN >> "$CT_CONF"
lxc.net.0.type = macvlan
lxc.net.0.macvlan.mode = bridge
lxc.net.0.link = ${LAN_IF}
lxc.net.0.flags = up
lxc.net.0.hwaddr = 10:66:6a:$(hexdump -n 3 -e '/1 ":%02x"' /dev/urandom 2>/dev/null | cut -c 2- || echo "11:22:33")
NET_MACVLAN
        fi

        if [ -n "$MEM_LIMIT" ]; then
            sed -i '/lxc\.cgroup2\.memory\.max/d' "$CT_CONF"
            echo "lxc.cgroup2.memory.max = ${MEM_LIMIT}" >> "$CT_CONF"
        fi

        if [ "$AUTO_START_ANS" = "y" ] || [ "$AUTO_START_ANS" = "Y" ]; then
            sed -i '/lxc\.start\.auto/d' "$CT_CONF"
            echo "lxc.start.auto = 1" >> "$CT_CONF"
            echo "lxc.start.delay = 3" >> "$CT_CONF"
        fi
    fi

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
        read -r NAME
    fi
    [ -z "$NAME" ] && return 1

    case "$ACTION" in
        start)
            ui_info_msg "Запуск контейнера ${NAME}..."
            lxc-start -n "$NAME" && ui_ok_msg "Контейнер ${NAME} запущен." || ui_warn_msg "Ошибка запуска ${NAME}."
            ;;
        stop)
            ui_info_msg "Остановка контейнера ${NAME}..."
            lxc-stop -n "$NAME" -t 10 && ui_ok_msg "Контейнер ${NAME} остановлен." || lxc-stop -n "$NAME" -k
            ;;
        restart)
            ui_info_msg "Перезапуск контейнера ${NAME}..."
            lxc-stop -n "$NAME" -t 5 2>/dev/null || true
            sleep 1
            lxc-start -n "$NAME" && ui_ok_msg "Контейнер ${NAME} перезапущен." || ui_warn_msg "Ошибка перезапуска."
            ;;
        attach)
            ui_info_msg "Вход в интерактивную сессию контейнера ${NAME} (выход: exit)..."
            lxc-attach -n "$NAME"
            ;;
        delete|destroy)
            ui_warn_msg "ВНИМАНИЕ! Контейнер '${NAME}' и все его файлы будут безвозвратно удалены."
            printf "Вы уверены? (yes/no): "
            read -r CONFIRM
            if [ "$CONFIRM" = "yes" ]; then
                lxc-stop -n "$NAME" -k 2>/dev/null || true
                lxc-destroy -n "$NAME" -f && ui_ok_msg "Контейнер ${NAME} успешно удален." || ui_warn_msg "Ошибка удаления."
            else
                ui_info_msg "Удаление отменено."
            fi
            ;;
        autostart)
            CT_CONF="${LXC_VAR_LIB}/${NAME}/config"
            if [ ! -f "$CT_CONF" ]; then
                ui_warn_msg "Контейнер ${NAME} не найден."
                return 1
            fi
            MODE="$3"
            if [ "$MODE" = "on" ] || { [ -z "$MODE" ] && ! grep -q "^lxc\.start\.auto[ \t]*=[ \t]*1" "$CT_CONF"; }; then
                sed -i '/lxc\.start\.auto/d' "$CT_CONF"
                echo "lxc.start.auto = 1" >> "$CT_CONF"
                echo "lxc.start.delay = 3" >> "$CT_CONF"
                ui_ok_msg "Автозапуск для '${NAME}' ВКЛЮЧЕН."
            else
                sed -i '/lxc\.start\.auto/d' "$CT_CONF"
                sed -i '/lxc\.start\.delay/d' "$CT_CONF"
                ui_info_msg "Автозапуск для '${NAME}' ВЫКЛЮЧЕН."
            fi
            ;;
    esac
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
        read -r NAME
    fi
    [ -z "$NAME" ] && return 1

    case "$SUBACTION" in
        create|snap)
            ui_info_msg "Создание снимка (снапшота) контейнера ${NAME}..."
            # Директории требуют остановки или флага --allowrunning
            lxc-snapshot -n "$NAME" --allowrunning 2>/dev/null || {
                lxc-stop -n "$NAME" -t 5 2>/dev/null || true
                lxc-snapshot -n "$NAME"
                lxc-start -n "$NAME" 2>/dev/null || true
            }
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
        restore)
            if [ -z "$SNAPNAME" ]; then
                ui_info_msg "Доступные снимки:"
                lxc-snapshot -n "$NAME" -L 2>/dev/null || true
                echo "Введите имя снимка для отката (например: snap0):"
                read -r SNAPNAME
            fi
            [ -z "$SNAPNAME" ] && return 1

            ui_warn_msg "Откат контейнера ${NAME} к снимку ${SNAPNAME} уничтожит текущие несохраненные изменения!"
            printf "Продолжить откат? (yes/no): "
            read -r C_ROLL
            if [ "$C_ROLL" = "yes" ]; then
                lxc-stop -n "$NAME" -k 2>/dev/null || true
                if lxc-snapshot -n "$NAME" -r "$SNAPNAME"; then
                    ui_ok_msg "Контейнер ${NAME} успешно восстановлен из снимка ${SNAPNAME}!"
                    lxc-start -n "$NAME" 2>/dev/null || true
                else
                    ui_warn_msg "Ошибка восстановления из снимка."
                fi
            fi
            ;;
        delete)
            if [ -z "$SNAPNAME" ]; then
                echo "Введите имя снимка для удаления (например: snap0):"
                read -r SNAPNAME
            fi
            [ -z "$SNAPNAME" ] && return 1
            lxc-snapshot -n "$NAME" -d "$SNAPNAME" && ui_ok_msg "Снимок ${SNAPNAME} удален." || ui_warn_msg "Ошибка удаления снимка."
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
    return 0
}

# Интерактивное TUI меню управления LXC контейнерами
lxc_interactive_menu() {
    ensure_lxc_subsystem "no"
    while true; do
        ui_banner "LXC // УПРАВЛЕНИЕ КОНТЕЙНЕРАМИ И СНАПШОТАМИ"
        lxc_list_containers

        echo "  ${C_BOLD}Действия:${C_RES}"
        echo "  1) ➕ Создать новый контейнер (Alpine, Debian, Ubuntu, Arch...)"
        echo "  2) ▶  Запустить контейнер"
        echo "  3) ⏹  Остановить контейнер"
        echo "  4) 🔄 Перезапустить контейнер"
        echo "  5) 💻 Войти в терминал контейнера (lxc-attach)"
        echo "  6) 📸 Управление снимками (Снапшоты: создать / список / откат)"
        echo "  7) ⚙  Переключить автозапуск при старте сервера"
        echo "  8) 🗑  Удалить контейнер"
        echo "  0) ⬅  Назад в главное меню"
        echo ""
        printf "Выберите действие [0-8]: "
        read -r M_ACT
        case "$M_ACT" in
            1) lxc_create_wizard ;;
            2) lxc_control "start" ;;
            3) lxc_control "stop" ;;
            4) lxc_control "restart" ;;
            5) lxc_control "attach" ;;
            6)
                echo "Введите имя контейнера для работы со снимками:"
                read -r S_CT
                if [ -n "$S_CT" ]; then
                    echo "  1) Создать снимок (snapshot)"
                    echo "  2) Список снимков"
                    echo "  3) Восстановить из снимка"
                    echo "  4) Удалить снимок"
                    printf "Действие [1-4]: "
                    read -r SS_ACT
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
                read -r A_CT
                [ -n "$A_CT" ] && lxc_control "autostart" "$A_CT"
                ;;
            8) lxc_control "delete" ;;
            0|q|Q) break ;;
        esac
        echo ""
        echo "Нажмите Enter для продолжения..."
        read -r _DUMMY
    done
    return 0
}
