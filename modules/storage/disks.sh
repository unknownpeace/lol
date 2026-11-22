#!/bin/sh
ensure_disk_tools() {
    ensure_alpine_community_repo
    NEED_APK="no"
    for cmd_chk in lsblk blkid cryptsetup mkfs.ext4 mkfs.btrfs mkfs.f2fs sfdisk; do
        command -v "$cmd_chk" >/dev/null 2>&1 || { NEED_APK="yes"; break; }
    done
    if [ "$NEED_APK" = "yes" ]; then
        echo "${C_CYN}[*] Установка пакетов управления дисками (cryptsetup LUKS2, e2fsprogs, btrfs-progs, f2fs-tools, lsblk)...${C_RES}"
        apk update >/dev/null 2>&1 || true
        apk add cryptsetup cryptsetup-openrc e2fsprogs e2fsprogs-extra btrfs-progs f2fs-tools util-linux lsblk blkid sfdisk parted lvm2-extra rsync >/dev/null 2>&1 || \
        apk add cryptsetup e2fsprogs btrfs-progs f2fs-tools util-linux lsblk blkid sfdisk >/dev/null 2>&1 || true
    fi
    for kmod_fs in dm_crypt dm_mod ext4 btrfs f2fs usb_storage uas nvme; do
        modprobe "$kmod_fs" 2>/dev/null || true
    done
    return 0
}

# Надежное определение корневого/системного диска (защита NVMe nvme0n1pX, SD/eMMC mmcblk0pX, VirtIO vda, SATA sda, dm-crypt/LVM)
get_root_base_disk() {
    ROOT_SRC=$(awk '$2 == "/" || $2 == "/boot" || $2 == "/boot/efi" || $2 == "/efi" || $2 == "/media/mmcblk0p1" || $2 == "/media/sda1" {print $1; exit}' /proc/mounts 2>/dev/null || true)
    [ -z "$ROOT_SRC" ] && ROOT_SRC=$(df / 2>/dev/null | awk 'NR==2 {print $1}' || true)
    _cur="$ROOT_SRC"
    _depth=0
    while [ -n "$_cur" ] && [ "$_depth" -lt 8 ]; do
        _pk=$(lsblk -no PKNAME "$_cur" 2>/dev/null | head -n 1 | tr -d ' \t\r\n' || true)
        [ -z "$_pk" ] && break
        case "$_pk" in
            /dev/*) _cur="$_pk" ;;
            *)      _cur="/dev/$_pk" ;;
        esac
        _depth=$((_depth + 1))
    done
    if [ -n "$_cur" ] && [ "$_cur" != "$ROOT_SRC" ]; then
        printf "%s" "$_cur"
        return 0
    fi
    case "$ROOT_SRC" in
        /dev/nvme*n*p[0-9]*|/dev/mmcblk*p[0-9]*|/dev/loop*p[0-9]*)
            printf "%s" "$ROOT_SRC" | sed -E 's/p[0-9]+$//'
            ;;
        /dev/*)
            printf "%s" "$ROOT_SRC" | sed -E 's/[0-9]+$//'
            ;;
        *)
            printf ""
            ;;
    esac
    return 0
}

# Проверка: принадлежит ли блочное устройство системному диску ОС (/ , /boot, /efi, /var, /home, /opt, swap)
is_system_protected_device() {
    CHK_DEV="${1:-}"
    [ -z "$CHK_DEV" ] && return 0
    CHK_REAL=$(readlink -f "$CHK_DEV" 2>/dev/null || printf "%s" "$CHK_DEV")
    ROOT_D=$(get_root_base_disk)
    if [ -n "$ROOT_D" ]; then
        ROOT_REAL=$(readlink -f "$ROOT_D" 2>/dev/null || printf "%s" "$ROOT_D")
        for _cand_d in "$CHK_DEV" "$CHK_REAL"; do
            for _cand_r in "$ROOT_D" "$ROOT_REAL"; do
                [ -z "$_cand_r" ] && continue
                case "$_cand_d" in
                    "$_cand_r"|"$_cand_r"[0-9]*|"$_cand_r"p[0-9]*)
                        return 0
                        ;;
                esac
            done
        done
        # Рекурсивная проверка родительского устройства (dm-crypt / LVM)
        _p_cur="$CHK_REAL"
        _p_depth=0
        while [ -n "$_p_cur" ] && [ "$_p_depth" -lt 8 ]; do
            _p_pk=$(lsblk -no PKNAME "$_p_cur" 2>/dev/null | head -n 1 | tr -d ' \t\r\n' || true)
            [ -z "$_p_pk" ] && break
            case "$_p_pk" in
                /dev/*) _p_cur="$_p_pk" ;;
                *)      _p_cur="/dev/$_p_pk" ;;
            esac
            if [ "$_p_cur" = "$ROOT_D" ] || [ "$_p_cur" = "$ROOT_REAL" ]; then
                return 0
            fi
            _p_depth=$((_p_depth + 1))
        done
    fi
    # Дополнительная проверка по точкам монтирования разделов выбранного диска
    if lsblk -rnpo MOUNTPOINT "$CHK_DEV" 2>/dev/null | grep -Eq '^(/|/boot(/.*)?|/efi|/etc|/home|/opt|/srv|/usr|/var|/media/.*|\[SWAP\])$'; then
        return 0
    fi
    return 1
}

# Сканирование доступных внешних разделов и дисков (исключая системный диск ОС)
list_available_external_disks() {
    ensure_disk_tools
    ensure_gateway_runtime_dir || return 1
    ROOT_DISK=$(get_root_base_disk)
    _disk_cache="${EXT_DISK_SCAN_CACHE:-${GATEWAY_RUNTIME_DIR:-/run/gateway}/disks.cache}"
    rm -f "$_disk_cache"
    : > "$_disk_cache"

    ui_box_top "🔌 ОБНАРУЖЕННЫЕ ВНЕШНИЕ НАКОПИТЕЛИ (Системный диск ${ROOT_DISK:-не определен} защищен)"
    lsblk -P -p -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null | awk \
        -v root_d="$ROOT_DISK" \
        -v cache_f="$_disk_cache" \
        -v c_cyn="$C_CYN" -v c_grn="$C_GRN" -v c_yel="$C_YEL" -v c_dim="$C_DIM" -v c_res="$C_RES" '
        function get_val(line, key,    s, res_str) {
            s = key "=\""
            if (index(line, s) > 0) {
                res_str = substr(line, index(line, s) + length(s))
                sub(/".*$/, "", res_str)
                return res_str
            }
            return ""
        }
        function is_root_dev(d, r,    sfx) {
            if (r == "") return 0
            if (d == r) return 1
            if (index(d, r) == 1) {
                sfx = substr(d, length(r) + 1)
                if (sfx ~ /^p?[0-9]+$/) return 1
            }
            return 0
        }
        {
            dev = get_val($0, "NAME")
            dtype = get_val($0, "TYPE")
            sz = get_val($0, "SIZE")
            fs = get_val($0, "FSTYPE")
            mp = get_val($0, "MOUNTPOINT")
            model = get_val($0, "MODEL")
            sub(/[[:space:]]+$/, "", model)

            if (dtype != "part" && dtype != "disk" && dtype != "crypt") next
            if (is_root_dev(dev, root_d)) next
            if (mp ~ /^(\/|\/boot(\/.*)?|\/efi|\/etc|\/home|\/opt|\/srv|\/usr|\/var|\/media\/.*|\[SWAP\])$/) next

            idx++
            tag = (fs == "crypto_LUKS") ? c_yel "[◆ LUKS2 Зашифрован]" c_res : (fs != "" ? c_grn "[● " fs "]" c_res : c_dim "[без ФС]" c_res)
            mp_str = (mp != "" ? mp : "не смонтирован")
            printf "%s│%s  %s[%d]%s %-18s │ %-5s │ %-7s │ %-22s │ Точка: %-15s %s\n", c_cyn, c_res, c_cyn, idx, c_res, dev, dtype, sz, tag, mp_str, model
            print dev > cache_f
        }
        END {
            if (idx == 0) {
                printf "%s│%s  %s(внешние USB / SATA / NVMe накопители не обнаружены — подключите диск и обновите список)%s\n", c_cyn, c_res, c_dim, c_res
            }
        }
    ' || true
    ui_box_bottom
    return 0
}

# Автоматический поиск первого внешнего накопителя для тихой установки (STORAGE_DISK="auto")
get_first_available_external_disk() {
    ensure_disk_tools
    ROOT_D=$(get_root_base_disk)
    lsblk -rnpo NAME,TYPE,MOUNTPOINT 2>/dev/null | awk \
        -v root_d="$ROOT_D" '
        function is_root_dev(d, r,    sfx) {
            if (r == "") return 0
            if (d == r) return 1
            if (index(d, r) == 1) {
                sfx = substr(d, length(r) + 1)
                if (sfx ~ /^p?[0-9]+$/) return 1
            }
            return 0
        }
        $2 == "disk" || $2 == "part" {
            dev = $1
            mp = $3
            if (is_root_dev(dev, root_d)) next
            if (mp ~ /^(\/|\/boot(\/.*)?|\/efi|\/etc|\/home|\/opt|\/srv|\/usr|\/var|\/media\/.*|\[SWAP\])$/) next
            print dev
            exit
        }'
}

# Выбор устройства из таблицы по номеру [1..N], ключевому слову 'auto' или прямому пути /dev/...
resolve_disk_selection() {
    RAW_SEL=$(printf "%s" "${1:-}" | tr -d ' \t\r\n')
    [ -z "$RAW_SEL" ] && return 1
    ensure_gateway_runtime_dir || return 1
    _disk_cache="${EXT_DISK_SCAN_CACHE:-${GATEWAY_RUNTIME_DIR:-/run/gateway}/disks.cache}"
    case "$RAW_SEL" in
        auto|AUTO)
            PICKED_DEV=$(get_first_available_external_disk)
            ;;
        /dev/*)
            PICKED_DEV="$RAW_SEL"
            ;;
        *[!0-9]*)
            return 1
            ;;
        *)
            PICKED_DEV=$(awk -v t="$RAW_SEL" 'NR == t {print $1; exit}' "$_disk_cache" 2>/dev/null || true)
            ;;
    esac
    [ -n "${PICKED_DEV:-}" ] && [ -b "$PICKED_DEV" ] || return 1
    if is_system_protected_device "$PICKED_DEV"; then
        ui_warn_box "ЗАЩИТА ДАННЫХ: Выбран системный диск ОС (${PICKED_DEV})!" \
                    "Выберите только внешний накопитель USB / SATA / NVMe из списка." >&2
        return 1
    fi
    printf "%s" "$PICKED_DEV"
    return 0
}

# Остановка и запуск всех сервисов и LXC-контейнеров, использующих /srv/storage
stop_storage_dependent_services() {
    _real_lxc=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
    if command -v lxc-stop >/dev/null 2>&1 && [ -d "$_real_lxc" ]; then
        for _ct_d in "${_real_lxc}/"*; do
            [ -d "$_ct_d" ] && [ -f "${_ct_d}/config" ] || continue
            _ct_n=$(basename "$_ct_d")
            if lxc-info -n "$_ct_n" 2>/dev/null | grep -q "State:.*RUNNING"; then
                lxc-stop -n "$_ct_n" -t 15 >/dev/null 2>&1 || lxc-stop -n "$_ct_n" -k >/dev/null 2>&1 || true
            fi
        done
    fi
    for svc_s in wsdd samba transmission-daemon metube forgejo code-server; do
        if [ -x "/etc/init.d/${svc_s}" ] && rc-service "$svc_s" status >/dev/null 2>&1; then
            rc-service "$svc_s" stop >/dev/null 2>&1 || true
        fi
    done
    return 0
}

start_storage_dependent_services() {
    if ! is_storage_mount_ready; then
        return 0
    fi
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*|caddy) continue ;; esac
            if [ "$M_EN" = "yes" ] && [ -x "/etc/init.d/${M_SVC}" ]; then
                rc-service "$M_SVC" start >/dev/null 2>&1 || true
            fi
        done < "$HOMELAB_STATE"
    fi
    if is_module_enabled "samba"; then
        [ -x /etc/init.d/wsdd ] && rc-service wsdd start >/dev/null 2>&1 || true
        [ -x /etc/init.d/avahi-daemon ] && rc-service avahi-daemon start >/dev/null 2>&1 || true
    fi
    return 0
}

# Определение типа накопителя (0 = SSD/NVMe/Flash, 1 = вращающийся HDD) для опций Btrfs
is_block_device_rotational() {
    _b_dev="${1:-}"
    [ -z "$_b_dev" ] && return 1
    _rota=$(lsblk -ndo ROTA "$_b_dev" 2>/dev/null | head -n 1 | tr -d ' \t\r\n' || true)
    if [ "$_rota" = "0" ] || [ "$_rota" = "1" ]; then
        printf "%s" "$_rota"
        return 0
    fi
    _b_cur="$_b_dev"
    _b_i=0
    while [ -n "$_b_cur" ] && [ "$_b_i" -lt 6 ]; do
        _b_pk=$(lsblk -no PKNAME "$_b_cur" 2>/dev/null | head -n 1 | tr -d ' \t\r\n' || true)
        [ -z "$_b_pk" ] && break
        case "$_b_pk" in
            /dev/*) _b_cur="$_b_pk" ;;
            *)      _b_cur="/dev/$_b_pk" ;;
        esac
        _b_i=$((_b_i + 1))
    done
    _b_base=$(basename "$_b_cur" 2>/dev/null || true)
    if [ -n "$_b_base" ] && [ -r "/sys/block/${_b_base}/queue/rotational" ]; then
        cat "/sys/block/${_b_base}/queue/rotational" 2>/dev/null | tr -d ' \t\r\n'
        return 0
    fi
    return 1
}

# Безопасные для внезапного отключения питания опции монтирования (ext4 / btrfs / f2fs)
# Убрана опасная опция commit=30 (риск потери 30 сек транзакций SQLite), включен стандартный 5-сек интервал + data=ordered
get_optimal_mount_opts() {
    FS_T="$1"
    OPT_DEV="${2:-}"
    case "$FS_T" in
        btrfs)
            _btrfs_ssd=""
            _dev_rota=$(is_block_device_rotational "$OPT_DEV" 2>/dev/null || true)
            if [ "$_dev_rota" = "0" ]; then
                _btrfs_ssd=",ssd"
            elif [ "$_dev_rota" = "1" ]; then
                _btrfs_ssd=",nossd"
            fi
            printf "defaults,noatime,compress=zstd:3%s,space_cache=v2,flushoncommit,nofail" "$_btrfs_ssd"
            ;;
        f2fs)  printf "defaults,noatime,gc_merge,background_gc=on,data_flush,nofail" ;;
        ext4)  printf "defaults,noatime,data=ordered,commit=5,errors=remount-ro,nofail" ;;
        *)     printf "defaults,noatime,nofail" ;;
    esac
    return 0
}

# Подключение существующего диска (обычного или зашифрованного LUKS2) в /srv/storage + безопасная автозагрузка
mount_external_drive_to_storage() {
    TARGET_DEV="$1"
    AUTO_UNLOCK_ANS="${2:-ask}"
    LUKS_PASS_OVERRIDE="${3:-}"
    ensure_disk_tools
    load_gateway_env

    if [ ! -b "$TARGET_DEV" ]; then
        ui_warn_box "Блочное устройство ${TARGET_DEV} не найдено в системе." \
                    "Проверьте подключение кабеля питания/данных и обновите список дисков."
        return 1
    fi
    if is_system_protected_device "$TARGET_DEV"; then
        ui_warn_box "Устройство ${TARGET_DEV} является системным диском ОС!" \
                    "Выберите внешний накопитель."
        return 1
    fi

    # Если выбран целый диск без разделов и на нем нет ФС/LUKS, но есть 1-й раздел — берем раздел
    DEV_TYPE=$(lsblk -no TYPE "$TARGET_DEV" 2>/dev/null | head -n 1 | tr -d ' \t\r\n')
    DEV_FS=$(blkid -s TYPE -o value "$TARGET_DEV" 2>/dev/null || true)
    if [ "$DEV_TYPE" = "disk" ] && [ -z "$DEV_FS" ]; then
        FIRST_PART=$(lsblk -rnpo NAME,TYPE "$TARGET_DEV" 2>/dev/null | awk '$2=="part" {print $1; exit}')
        if [ -n "$FIRST_PART" ]; then
            ui_info_msg "Выбран диск ${TARGET_DEV}, автоматически переключаемся на раздел: ${FIRST_PART}"
            TARGET_DEV="$FIRST_PART"
            DEV_FS=$(blkid -s TYPE -o value "$TARGET_DEV" 2>/dev/null || true)
        fi
    fi

    MOUNT_DEV="$TARGET_DEV"
    IS_LUKS="no"
    LUKS_UUID=""

    # 1. Проверяем, зашифрован ли раздел контейнером LUKS / LUKS2
    if cryptsetup isLuks "$TARGET_DEV" 2>/dev/null || [ "$DEV_FS" = "crypto_LUKS" ]; then
        IS_LUKS="yes"
        LUKS_UUID=$(cryptsetup luksUUID "$TARGET_DEV" 2>/dev/null || blkid -s UUID -o value "$TARGET_DEV" 2>/dev/null || true)
        ui_info_msg "Обнаружен зашифрованный контейнер LUKS2 на ${TARGET_DEV} (UUID: ${LUKS_UUID})"

        if [ ! -b "/dev/mapper/${LUKS_MAPPER_NAME}" ]; then
            if [ -s "$LUKS_KEYFILE" ] && cryptsetup open "$TARGET_DEV" "$LUKS_MAPPER_NAME" --key-file "$LUKS_KEYFILE" 2>/dev/null; then
                ui_ok_msg "Контейнер LUKS2 автоматически открыт с помощью сохраненного ключа ${LUKS_KEYFILE}!"
            else
                LUKS_PASS=""
                if [ -n "$LUKS_PASS_OVERRIDE" ]; then
                    LUKS_PASS="$LUKS_PASS_OVERRIDE"
                else
                    printf "Введите пароль (passphrase) для разблокировки LUKS2 диска %s: " "$TARGET_DEV"
                    [ -t 0 ] && stty -echo 2>/dev/null || true
                    read -r LUKS_PASS < /dev/tty || true
                    [ -t 0 ] && stty echo 2>/dev/null || true
                    printf "\n"
                    LUKS_PASS=$(printf "%s" "$LUKS_PASS" | tr -d '\r\n')
                fi
                if ! printf "%s" "$LUKS_PASS" | cryptsetup open --key-file=- "$TARGET_DEV" "$LUKS_MAPPER_NAME"; then
                    ui_warn_box "Неверный пароль или ошибка открытия контейнера LUKS2 (${TARGET_DEV})." \
                                "Повторите попытку через команду: gateway unlock"
                    return 1
                fi
                ui_ok_msg "Контейнер LUKS2 успешно открыт -> /dev/mapper/${LUKS_MAPPER_NAME}"

                if [ "$AUTO_UNLOCK_ANS" = "ask" ] && [ -t 0 ]; then
                    printf "Настроить авто-разблокировку этого LUKS-диска при загрузке сервера (ключ в %s, права 0400)? (y/n) [Enter = y]: " "$LUKS_KEYFILE"
                    read -r IN_KEYF < /dev/tty || true
                    IN_KEYF=$(printf "%s" "$IN_KEYF" | tr -d ' \t\r\n')
                    [ -z "$IN_KEYF" ] && IN_KEYF="y"
                else
                    IN_KEYF="$AUTO_UNLOCK_ANS"
                fi
                case "$IN_KEYF" in
                    [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа])
                        _had_key="no"
                        [ -s "$LUKS_KEYFILE" ] && _had_key="yes"
                        mkdir -p "$(dirname "$LUKS_KEYFILE")"
                        umask 077
                        if [ ! -s "$LUKS_KEYFILE" ]; then
                            dd if=/dev/urandom of="$LUKS_KEYFILE" bs=4096 count=1 >/dev/null 2>&1
                        fi
                        chmod 400 "$LUKS_KEYFILE"
                        umask 022
                        if printf "%s" "$LUKS_PASS" | cryptsetup luksAddKey --key-file=- "$TARGET_DEV" "$LUKS_KEYFILE"; then
                            ui_ok_msg "Ключ авто-разблокировки добавлен в слот LUKS2 и защищен (${LUKS_KEYFILE}, mode 0400)!"
                        else
                            [ "$_had_key" = "no" ] && rm -f "$LUKS_KEYFILE" 2>/dev/null || true
                            ui_warn_box "Не удалось добавить ключ авто-разблокировки в слот LUKS2!" \
                                        "Проверьте доступные ключевые слоты накопителя (${TARGET_DEV})."
                            return 1
                        fi
                        ;;
                esac
            fi
        fi
        MOUNT_DEV="/dev/mapper/${LUKS_MAPPER_NAME}"
    fi

    FS_TYPE=$(blkid -s TYPE -o value "$MOUNT_DEV" 2>/dev/null || true)
    FS_UUID=$(blkid -s UUID -o value "$MOUNT_DEV" 2>/dev/null || true)
    if [ -z "$FS_TYPE" ]; then
        ui_warn_box "На устройстве ${MOUNT_DEV} не обнаружена файловая система." \
                    "Выберите пункт 2 или 3 в меню дисков для форматирования в ext4 / btrfs / f2fs."
        return 1
    fi

    ui_step_progress 1 3 "Проверка целостности файловой системы ${FS_TYPE} (${MOUNT_DEV}) после размонтирования..."
    stop_storage_dependent_services
    auto_fsck_device "$MOUNT_DEV" "$FS_TYPE"

    MNT_OPTS=$(get_optimal_mount_opts "$FS_TYPE" "$MOUNT_DEV")

    # Если в локальной папке /srv/storage уже были файлы (на системном разделе), переносим напрямую на целевой диск без RAM /tmp
    _pre_mnt_bak=""
    if is_external_storage_mounted; then
        sync
        if ! umount "$STORAGE_ROOT" 2>/dev/null; then
            ui_warn_box "Не удалось размонтировать текущее хранилище ${STORAGE_ROOT} (устройство занято)." \
                        "Операция подключения отменена для предотвращения потери данных."
            start_storage_dependent_services
            return 1
        fi
    elif [ -d "$STORAGE_ROOT" ] && [ -n "$(ls -A "$STORAGE_ROOT" 2>/dev/null)" ]; then
        ui_step_progress 2 3 "Перенос существующих файлов из ${STORAGE_ROOT} напрямую на внешний накопитель..."
        ensure_gateway_runtime_dir || return 1
        _stage_mnt="${GATEWAY_RUNTIME_DIR:-/run/gateway}/mnt_migrate.$$"
        mkdir -p "$_stage_mnt"
        if ! mount -t "$FS_TYPE" -o "$MNT_OPTS" "$MOUNT_DEV" "$_stage_mnt" 2>/dev/null && ! mount "$MOUNT_DEV" "$_stage_mnt" 2>/dev/null; then
            rmdir "$_stage_mnt" 2>/dev/null || true
            ui_warn_box "Не удалось временно смонтировать ${MOUNT_DEV} для переноса данных!" \
                        "Существующие файлы в ${STORAGE_ROOT} не затронуты."
            start_storage_dependent_services
            return 1
        fi
        if ! cp -a "${STORAGE_ROOT}/." "${_stage_mnt}/"; then
            umount "$_stage_mnt" 2>/dev/null || true
            rmdir "$_stage_mnt" 2>/dev/null || true
            ui_warn_box "Ошибка копирования данных из ${STORAGE_ROOT} на ${MOUNT_DEV} (возможно, не хватает места)!" \
                        "Исходные файлы в ${STORAGE_ROOT} сохранены."
            start_storage_dependent_services
            return 1
        fi
        sync
        umount "$_stage_mnt" 2>/dev/null || {
            rmdir "$_stage_mnt" 2>/dev/null || true
            start_storage_dependent_services
            return 1
        }
        rmdir "$_stage_mnt" 2>/dev/null || true
        _pre_mnt_bak="${STORAGE_ROOT}.pre_mnt.$$"
        mv "$STORAGE_ROOT" "$_pre_mnt_bak"
    fi

    mkdir -p "$STORAGE_ROOT"
    ui_step_progress 3 3 "Монтирование ${MOUNT_DEV} (${FS_TYPE}) в ${STORAGE_ROOT} с защитой от сбоя питания..."
    if ! mount -t "$FS_TYPE" -o "$MNT_OPTS" "$MOUNT_DEV" "$STORAGE_ROOT" 2>/dev/null; then
        if ! mount "$MOUNT_DEV" "$STORAGE_ROOT"; then
            if [ -n "$_pre_mnt_bak" ] && [ -d "$_pre_mnt_bak" ]; then
                rmdir "$STORAGE_ROOT" 2>/dev/null || true
                mv "$_pre_mnt_bak" "$STORAGE_ROOT" 2>/dev/null || true
            fi
            ui_warn_box "Не удалось смонтировать ${MOUNT_DEV} в ${STORAGE_ROOT}!" \
                        "Выполните проверку диска через: gateway doctor"
            start_storage_dependent_services
            return 1
        fi
    fi

    if [ -n "$_pre_mnt_bak" ] && [ -d "$_pre_mnt_bak" ]; then
        rm -rf "$_pre_mnt_bak" 2>/dev/null || true
        ui_ok_msg "Существующие данные медиатеки перенесены на внешний накопитель!"
    fi

    # Безопасная настройка автомонтирования в /etc/fstab (с pass=0 и nofail, чтобы сервер НИКОГДА не зависал в Emergency Shell без SSH!)
    sed -i "\|[[:space:]]${STORAGE_ROOT}[[:space:]]|d" /etc/fstab 2>/dev/null || true
    EXT_STORAGE_EXPECTED="yes"
    EXT_STORAGE_FSTYPE="$FS_TYPE"
    if [ "$IS_LUKS" = "yes" ]; then
        touch /etc/modules 2>/dev/null || true
        for k_luks in dm_mod dm_crypt; do
            modprobe "$k_luks" 2>/dev/null || true
            grep -qxF "$k_luks" /etc/modules 2>/dev/null || echo "$k_luks" >> /etc/modules
        done
        rc-update add modules boot >/dev/null 2>&1 || true
        EXT_STORAGE_LUKS_UUID="$LUKS_UUID"
        EXT_STORAGE_UUID="$FS_UUID"
        mkdir -p /etc/conf.d
        touch /etc/conf.d/dmcrypt
        awk -v tgt="target='${LUKS_MAPPER_NAME}'" '
            $0 == tgt { skip=2; next }
            skip > 0 { skip--; next }
            { print }
        ' /etc/conf.d/dmcrypt > /etc/conf.d/dmcrypt.tmp.$$ 2>/dev/null && \
            mv -f /etc/conf.d/dmcrypt.tmp.$$ /etc/conf.d/dmcrypt || rm -f /etc/conf.d/dmcrypt.tmp.$$
        if [ -s "$LUKS_KEYFILE" ]; then
            cat << DMCRYPT_EOF >> /etc/conf.d/dmcrypt
target='${LUKS_MAPPER_NAME}'
source='UUID=${LUKS_UUID}'
key='${LUKS_KEYFILE}'
DMCRYPT_EOF
            rc-update add dmcrypt boot >/dev/null 2>&1 || rc-update add dmcrypt default >/dev/null 2>&1 || true
            printf "/dev/mapper/%s\t%s\t%s\t%s\t0 0\n" "$LUKS_MAPPER_NAME" "$STORAGE_ROOT" "$FS_TYPE" "$MNT_OPTS" >> /etc/fstab
        else
            # Если LUKS2 без авто-ключа (ручной ввод пароля), НЕ прописываем блокирующий fstab, чтобы система и SSH всегда загружались!
            ui_info_msg "Диск LUKS2 настроен на ручной ввод пароля после перезагрузки через команду: gateway unlock"
        fi
    else
        EXT_STORAGE_LUKS_UUID=""
        EXT_STORAGE_UUID="$FS_UUID"
        if [ -n "$FS_UUID" ]; then
            printf "UUID=%s\t%s\t%s\t%s\t0 0\n" "$FS_UUID" "$STORAGE_ROOT" "$FS_TYPE" "$MNT_OPTS" >> /etc/fstab
        else
            printf "%s\t%s\t%s\t%s\t0 0\n" "$MOUNT_DEV" "$STORAGE_ROOT" "$FS_TYPE" "$MNT_OPTS" >> /etc/fstab
        fi
    fi
    rc-update add localmount boot >/dev/null 2>&1 || true
    rm -f "$STORAGE_ALERT_CACHE" 2>/dev/null || true
    save_homelab_env
    sync

    init_homelab_storage
    sync_all_homelab_permissions
    start_storage_dependent_services

    ui_ok_msg "Внешний накопитель ${MOUNT_DEV} (${FS_TYPE}) успешно смонтирован в ${STORAGE_ROOT}!"
    df -hT "$STORAGE_ROOT" 2>/dev/null || true
    return 0
}

# Форматирование выбранного накопителя (ext4 / btrfs / f2fs) с опциональным шифрованием LUKS2
format_and_mount_external_drive() {
    RAW_DEV="$1"
    FS_CHOICE="${2:-ext4}"   # ext4 | btrfs | f2fs
    USE_LUKS="${3:-no}"     # yes | no
    CONFIRM_OVERRIDE="${4:-}"
    PASS_OVERRIDE="${5:-}"

    ensure_disk_tools
    TARGET_DEV=$(resolve_disk_selection "$RAW_DEV" || true)
    if [ -z "$TARGET_DEV" ]; then
        return 1
    fi

    echo ""
    echo "${C_RED}╔════════════════════════════════════════════════════════════════════════════${C_RES}"
    echo "${C_RED}║ ▲ ВНИМАНИЕ: ВСЕ ДАННЫЕ НА УСТРОЙСТВЕ ${TARGET_DEV} БУДУТ УНИЧТОЖЕНЫ!${C_RES}"
    echo "${C_RED}║${C_RES}   • Целевое устройство: ${C_YEL}${TARGET_DEV}${C_RES}"
    echo "${C_RED}║${C_RES}   • Файловая система:   ${C_CYN}${FS_CHOICE}${C_RES}"
    echo "${C_RED}║${C_RES}   • Шифрование LUKS2:   $([ "$USE_LUKS" = "yes" ] && echo "${C_GRN}ДА (AES-XTS-PLAIN64 512-bit + Argon2id)${C_RES}" || echo "НЕТ")"
    echo "${C_RED}╚════════════════════════════════════════════════════════════════════════════${C_RES}"

    if [ "$CONFIRM_OVERRIDE" = "YES" ]; then
        CONFIRM_FMT="YES"
        ui_info_msg "Форматирование подтверждено автоматически через параметр / файл ответов."
    else
        printf "Для подтверждения форматирования введите заглавными буквами YES: "
        read -r CONFIRM_FMT < /dev/tty || true
    fi
    if [ "$CONFIRM_FMT" != "YES" ]; then
        ui_info_msg "Форматирование отменено."
        return 0
    fi

    stop_storage_dependent_services
    sync
    if is_external_storage_mounted && ! umount "$STORAGE_ROOT" 2>/dev/null; then
        ui_warn_box "Не удалось размонтировать ${STORAGE_ROOT} перед форматированием!" \
                    "Закройте открытые файлы и повторите попытку."
        return 1
    fi
    if awk -v d="$TARGET_DEV" '$1 == d {found=1} END {exit !found}' /proc/mounts 2>/dev/null; then
        umount "$TARGET_DEV" 2>/dev/null || {
            ui_warn_box "Устройство ${TARGET_DEV} все еще смонтировано и занято!" "Размонтируйте вручную перед форматированием."
            return 1
        }
    fi
    for sub_p in "${TARGET_DEV}"*[0-9]; do
        if [ -b "$sub_p" ] && awk -v d="$sub_p" '$1 == d {found=1} END {exit !found}' /proc/mounts 2>/dev/null; then
            umount "$sub_p" 2>/dev/null || {
                ui_warn_box "Раздел ${sub_p} смонтирован и занят!" "Размонтируйте вручную перед форматированием."
                return 1
            }
        fi
    done
    if [ -b "/dev/mapper/${LUKS_MAPPER_NAME}" ]; then
        if ! cryptsetup close "$LUKS_MAPPER_NAME" 2>/dev/null; then
            ui_warn_box "Криптоконтейнер /dev/mapper/${LUKS_MAPPER_NAME} все еще открыт и занят!" \
                        "Закройте его через gateway eject перед форматированием."
            return 1
        fi
    fi

    # Если выбран целый диск (disk), создаем на нем чистую таблицу GPT и 1 раздел на 100% объема
    DEV_TYPE=$(lsblk -no TYPE "$TARGET_DEV" 2>/dev/null | head -n 1 | tr -d ' \t\r\n')
    if [ "$DEV_TYPE" = "disk" ]; then
        ui_step_progress 1 3 "Создание новой таблицы разделов GPT на диске ${TARGET_DEV}..."
        wipefs -a "$TARGET_DEV" >/dev/null 2>&1 || true
        if ! printf "label: gpt\n;\n" | sfdisk --force "$TARGET_DEV" >/dev/null 2>&1; then
            ui_warn_box "Ошибка создания таблицы разделов GPT на ${TARGET_DEV}!" "Проверьте исправность накопителя (dmesg)."
            return 1
        fi
        partprobe "$TARGET_DEV" 2>/dev/null || true
        blockdev --rereadpt "$TARGET_DEV" 2>/dev/null || true
        mdev -s 2>/dev/null || true
        PART_DEV=""
        _pw=0
        while [ "$_pw" -lt 10 ]; do
            PART_DEV=$(lsblk -rnpo NAME,TYPE "$TARGET_DEV" 2>/dev/null | awk '$2=="part" {print $1; exit}')
            if [ -n "$PART_DEV" ] && [ -b "$PART_DEV" ]; then
                break
            fi
            sleep 1
            mdev -s 2>/dev/null || true
            _pw=$((_pw + 1))
        done
        if [ -z "$PART_DEV" ] || [ ! -b "$PART_DEV" ]; then
            ui_warn_box "Ядро не обнаружило созданный раздел на ${TARGET_DEV} после sfdisk!" \
                        "Форматирование остановлено во избежание порчи таблицы разделов."
            return 1
        fi
        TARGET_DEV="$PART_DEV"
        wipefs -a "$TARGET_DEV" >/dev/null 2>&1 || true
    else
        wipefs -a "$TARGET_DEV" >/dev/null 2>&1 || true
    fi

    FMT_TARGET="$TARGET_DEV"
    if [ "$USE_LUKS" = "yes" ]; then
        if [ -n "$PASS_OVERRIDE" ]; then
            NEW_LUKS_PASS="$PASS_OVERRIDE"
        else
            printf "Задайте пароль (passphrase) для шифрования LUKS2 диска %s [Enter = использовать единый пароль шлюза]: " "$TARGET_DEV"
            [ -t 0 ] && stty -echo 2>/dev/null || true
            read -r NEW_LUKS_PASS < /dev/tty || true
            [ -t 0 ] && stty echo 2>/dev/null || true
            printf "\n"
            NEW_LUKS_PASS=$(printf "%s" "$NEW_LUKS_PASS" | tr -d '\r\n')
            load_gateway_env
            [ -z "$NEW_LUKS_PASS" ] && NEW_LUKS_PASS="${ADMIN_PASS:-admin}"
        fi

        MEM_KB_LUKS=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo "524288")
        case "$MEM_KB_LUKS" in ''|*[!0-9]*) MEM_KB_LUKS=524288 ;; esac
        if [ "$MEM_KB_LUKS" -le 1048576 ]; then
            PBKDF_MEM=65536
        else
            PBKDF_MEM=131072
        fi

        ui_step_progress 2 3 "Форматирование контейнера LUKS2 (cipher: aes-xts-plain64, key: 512 bit, pbkdf: argon2id, mem: ${PBKDF_MEM}K)..."
        if ! printf "%s" "$NEW_LUKS_PASS" | cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --pbkdf argon2id --pbkdf-memory "$PBKDF_MEM" --batch-mode --key-file=- "$TARGET_DEV"; then
            ui_warn_box "Ошибка создания контейнера LUKS2 на ${TARGET_DEV}!" "Проверьте исправность накопителя (dmesg)."
            return 1
        fi

        # Создаем и регистрируем ключ авто-разблокировки для старта сервера без ввода пароля с клавиатуры
        mkdir -p "$(dirname "$LUKS_KEYFILE")"
        umask 077
        dd if=/dev/urandom of="$LUKS_KEYFILE" bs=4096 count=1 >/dev/null 2>&1
        chmod 400 "$LUKS_KEYFILE"
        umask 022
        if ! printf "%s" "$NEW_LUKS_PASS" | cryptsetup luksAddKey --key-file=- "$TARGET_DEV" "$LUKS_KEYFILE" >/dev/null 2>&1; then
            rm -f "$LUKS_KEYFILE" 2>/dev/null || true
            ui_warn_box "Ошибка добавления ключа авто-разблокировки в слот LUKS2 на ${TARGET_DEV}!" \
                        "Форматирование остановлено."
            return 1
        fi

        if ! cryptsetup open "$TARGET_DEV" "$LUKS_MAPPER_NAME" --key-file "$LUKS_KEYFILE"; then
            printf "%s" "$NEW_LUKS_PASS" | cryptsetup open --key-file=- "$TARGET_DEV" "$LUKS_MAPPER_NAME" || return 1
        fi
        FMT_TARGET="/dev/mapper/${LUKS_MAPPER_NAME}"
        ui_ok_msg "Контейнер LUKS2 создан и открыт (${FMT_TARGET})!"
    fi

    ui_step_progress 3 3 "Создание файловой системы ${FS_CHOICE} на ${FMT_TARGET}..."
    case "$FS_CHOICE" in
        btrfs)
            mkfs.btrfs -f -L "HOMELAB_STORAGE" "$FMT_TARGET" || return 1
            ;;
        f2fs)
            mkfs.f2fs -f -l "HOMELAB_STORAGE" "$FMT_TARGET" || return 1
            ;;
        *)
            mkfs.ext4 -F -m 1 -L "HOMELAB_STORAGE" "$FMT_TARGET" || return 1
            ;;
    esac
    sync

    mount_external_drive_to_storage "$TARGET_DEV" "yes" "${NEW_LUKS_PASS:-}"
    return 0
}

# Умный перенос тяжелых данных сервисов Homelab (Git-репозитории Forgejo, проекты VS Code, бэкапы) на внешний диск
relocate_heavy_services_to_external_storage() {
    load_gateway_env
    if ! is_storage_mount_ready; then
        ui_warn_box "Внешний накопитель в ${STORAGE_ROOT} сейчас не смонтирован или заблокирован LUKS2!" \
                    "Сначала разблокируйте или смонтируйте диск (gateway unlock), затем запустите перенос."
        return 1
    fi
    init_homelab_storage
    ui_box_top "🚀 ПЕРЕНОС ТЯЖЕЛЫХ ДАННЫХ СЕРВИСОВ НА НАКОПИТЕЛЬ (${STORAGE_ROOT})"
    stop_storage_dependent_services

    # 1. Git-репозитории и LFS объекты Forgejo -> /srv/storage/Git-Repos
    mkdir -p "${STORAGE_REPOS}/repos" "${STORAGE_REPOS}/lfs"
    if [ -d /var/lib/forgejo/repos ] && [ ! -L /var/lib/forgejo/repos ]; then
        if cp -a /var/lib/forgejo/repos/. "${STORAGE_REPOS}/repos/"; then
            rm -rf /var/lib/forgejo/repos
            ln -s "${STORAGE_REPOS}/repos" /var/lib/forgejo/repos
        else
            ui_box_bottom
            ui_warn_box "Ошибка переноса /var/lib/forgejo/repos на ${STORAGE_REPOS}!" \
                        "Исходные репозитории сохранены; проверьте свободное место."
            start_storage_dependent_services
            return 1
        fi
    fi
    if id forgejo >/dev/null 2>&1; then
        FG_GRP=$(id -gn forgejo 2>/dev/null || echo "www-data")
        chown -R "forgejo:${FG_GRP}" "$STORAGE_REPOS" 2>/dev/null || true
        chmod -R 750 "$STORAGE_REPOS" 2>/dev/null || true
    fi
    ui_box_row "${C_GRN}[✔]${C_RES} Git-репозитории Forgejo привязаны к ${STORAGE_REPOS}/repos"

    # 2. Проекты и воркспейс VS Code (Server-Code) -> /srv/storage/Workspace
    mkdir -p "$STORAGE_CODE"
    if [ -d /var/lib/coder/workspace ] && [ ! -L /var/lib/coder/workspace ]; then
        if cp -a /var/lib/coder/workspace/. "$STORAGE_CODE/"; then
            rm -rf /var/lib/coder/workspace
            ln -s "$STORAGE_CODE" /var/lib/coder/workspace
        else
            ui_box_bottom
            ui_warn_box "Ошибка переноса /var/lib/coder/workspace в ${STORAGE_CODE}!" \
                        "Исходные проекты сохранены; проверьте свободное место."
            start_storage_dependent_services
            return 1
        fi
    elif [ -d /var/lib/coder ] && [ ! -e /var/lib/coder/workspace ]; then
        ln -s "$STORAGE_CODE" /var/lib/coder/workspace
    fi
    if id coder >/dev/null 2>&1; then
        chown -R "coder:${MEDIA_GROUP}" "$STORAGE_CODE" 2>/dev/null || true
        chmod 2775 "$STORAGE_CODE" 2>/dev/null || true
    fi
    ui_box_row "${C_GRN}[✔]${C_RES} Рабочая папка проектов VS Code (Server-Code) вынесена в ${STORAGE_CODE}"

    # 3. Синхронизация прав медиа-хранилища
    repair_storage_permissions

    # 5. Автоматическое зеркалирование архивов бэкапа в /srv/storage/Backups (строго root:root 0700/0600)
    mkdir -p "$STORAGE_BACKUPS"
    chown root:root "$STORAGE_BACKUPS" 2>/dev/null || true
    chmod 0700 "$STORAGE_BACKUPS" 2>/dev/null || true
    if [ -f "$BACKUP_ARCHIVE" ]; then
        cp -f "$BACKUP_ARCHIVE" "${STORAGE_BACKUPS}/gateway_backup_latest.tar.gz" 2>/dev/null || true
        chown root:root "${STORAGE_BACKUPS}/gateway_backup_latest.tar.gz" 2>/dev/null || true
        chmod 0600 "${STORAGE_BACKUPS}/gateway_backup_latest.tar.gz" 2>/dev/null || true
    fi
    ui_box_row "${C_GRN}[✔]${C_RES} Защищенное хранилище резервных копий готово: ${STORAGE_BACKUPS} (0700 root:root)"

    sync
    sync_all_homelab_permissions
    start_storage_dependent_services
    ui_box_bottom
    ui_ok_msg "Все тяжелые данные вынесены на накопитель ${STORAGE_ROOT}! Системный диск защищен от износа."
    return 0
}

# Безопасное отключение (размонтирование + закрытие LUKS2) внешнего накопителя (`gateway lock` / `gateway eject`)
unmount_external_storage_safe() {
    load_gateway_env
    if ! is_external_storage_mounted && [ ! -b "/dev/mapper/${LUKS_MAPPER_NAME}" ]; then
        ui_info_msg "В ${STORAGE_ROOT} сейчас не смонтирован внешний накопитель."
        return 0
    fi
    ui_box_top "⏏️ БЕЗОПАСНОЕ ИЗВЛЕЧЕНИЕ И БЛОКИРОВКА ДИСКА (GATEWAY EJECT / LOCK)"
    ui_step_progress 1 3 "Остановка зависимых медиа-сервисов, LXC-контейнеров и торрентов..."
    stop_storage_dependent_services

    ui_step_progress 2 3 "Сброс кэшей записи на диск (sync) и размонтирование ${STORAGE_ROOT}..."
    sync
    if is_external_storage_mounted; then
        if ! umount "$STORAGE_ROOT" 2>/dev/null; then
            sleep 1
            sync
            if ! umount "$STORAGE_ROOT" 2>/dev/null; then
                _busy_pids=$(fuser -m "$STORAGE_ROOT" 2>/dev/null || true)
                _busy_info=""
                [ -n "$_busy_pids" ] && _busy_info="Занято PID: ${_busy_pids}"
                [ -z "$_busy_info" ] && _busy_info=$(lsof +f -- "$STORAGE_ROOT" 2>/dev/null | head -n 8 || true)
                ui_box_bottom
                start_storage_dependent_services
                ui_warn_box "Не удалось размонтировать ${STORAGE_ROOT} (устройство занято процессом)." \
                            "${_busy_info:-Закройте открытые файлы в Samba/консоли и повторите: gateway eject}"
                return 1
            fi
        fi
    fi

    ui_step_progress 3 3 "Закрытие криптоконтейнера LUKS2..."
    if [ -b "/dev/mapper/${LUKS_MAPPER_NAME}" ]; then
        if ! cryptsetup close "$LUKS_MAPPER_NAME" 2>/dev/null; then
            _luks_pids=$(fuser -m "/dev/mapper/${LUKS_MAPPER_NAME}" 2>/dev/null || true)
            _luks_busy=""
            [ -n "$_luks_pids" ] && _luks_busy="Занято PID: ${_luks_pids}"
            [ -z "$_luks_busy" ] && _luks_busy=$(dmsetup info "$LUKS_MAPPER_NAME" 2>/dev/null || true)
            ui_box_bottom
            ui_warn_box "Файловая система отмонтирована, но не удалось закрыть контейнер LUKS2 (${LUKS_MAPPER_NAME})!" \
                        "${_luks_busy:-Устройство все еще используется ядром/процессом — НЕ извлекайте накопитель!}"
            return 1
        fi
        ui_box_row "${C_GRN}[✔] Контейнер LUKS2 (${LUKS_MAPPER_NAME}) безопасно заблокирован и закрыт.${C_RES}"
    fi

    sed -i "\|[[:space:]]${STORAGE_ROOT}[[:space:]]|d" /etc/fstab 2>/dev/null || true
    EXT_STORAGE_EXPECTED="no"
    save_homelab_env
    ui_box_row "${C_GRN}[✔] Внешний накопитель безопасно отключен! Теперь его можно физически извлечь.${C_RES}"
    ui_box_bottom
    return 0
}

# Интерактивное меню управления внешними дисками, LUKS2 и переносом данных
manage_external_disks_menu() {
    while true; do
        clear
        ui_banner "STORAGE MANAGER // ВНЕШНИЕ ДИСКИ, LUKS2 И ФАЙЛОВЫЕ СИСТЕМЫ"
        print_storage_stats
        list_available_external_disks
        ui_box_top "📦 ЧТО ХРАНИТСЯ И ВЫНОСИТСЯ НА ВНЕШНИЙ НАКОПИТЕЛЬ (${STORAGE_ROOT})"
        ui_box_row "• 🎵 ${C_CYN}Music${C_RES} & 🎬 ${C_CYN}Videos${C_RES}                 — аудиотека и видеоархив (MeTube)"
        ui_box_row "• ⬇️ ${C_CYN}Downloads & Incomplete${C_RES}          — загрузки Transmission и буфер MeTube (0 износа SD/eMMC!)"
        ui_box_row "• 💻 ${C_CYN}Git-Repos & Workspace${C_RES}           — Git-репозитории Forgejo и проекты VS Code (Server-Code)"
        ui_box_row "• 🗂️ ${C_CYN}Backups${C_RES}                         — архивы бэкапов шлюза"
        ui_box_sep "ДЕЙСТВИЯ С НАКОПИТЕЛЯМИ [0-7]"
        ui_box_row "${C_CYN}1)${C_RES} 🔌 Подключить существующий диск / раздел (обычный или зашифрованный ${C_YEL}LUKS2${C_RES}) в ${STORAGE_ROOT}"
        ui_box_row "${C_CYN}2)${C_RES} 💿 Форматировать накопитель в ${C_GRN}ext4 / btrfs / f2fs${C_RES} (без шифрования) и подключить"
        ui_box_row "${C_CYN}3)${C_RES} 🔐 Зашифровать накопитель в ${C_YEL}LUKS2 (AES-XTS 512-bit)${C_RES} + отформатировать (${C_GRN}ext4 / btrfs / f2fs${C_RES})"
        ui_box_row "${C_CYN}4)${C_RES} 🚀 Вынести все тяжелые данные сервисов (Git, VS Code, Бэкапы) на накопитель"
        ui_box_row "${C_CYN}5)${C_RES} 🔧 Синхронизировать права доступа (${MEDIA_GROUP} + setgid 2775 + POSIX ACL) и очистить буферы"
        ui_box_row "${C_CYN}6)${C_RES} ⏏️ Безопасно размонтировать внешний диск и закрыть контейнер LUKS2 (${C_YEL}gateway eject${C_RES})"
        ui_box_row "${C_CYN}7)${C_RES} 🔓 Быстро разблокировать LUKS2-накопитель после перезагрузки (${C_GRN}gateway unlock${C_RES})"
        ui_box_row "${C_CYN}0)${C_RES} Назад"
        ui_box_bottom
        printf "Выберите действие [0-7]: "
        read -r DSK_ACT < /dev/tty || break
        case "$DSK_ACT" in
            ""|0) break ;;
            1)
                printf "Введите номер устройства из таблицы выше (или путь, например /dev/sdb1): "
                read -r D_IN < /dev/tty || true
                PICK_D=$(resolve_disk_selection "$D_IN" || true)
                if [ -n "$PICK_D" ]; then
                    mount_external_drive_to_storage "$PICK_D" "ask" || true
                else
                    ui_warn_box "Устройство не найдено в списке или защищено от изменений (системный диск)." \
                                "Укажите корректный номер внешнего накопителя из таблицы."
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            2|3)
                USE_L="no"
                [ "$DSK_ACT" = "3" ] && USE_L="yes"
                printf "Введите номер устройства из таблицы для форматирования (или /dev/sdX): "
                read -r D_IN < /dev/tty || true
                ui_box_top "ВЫБОР ФАЙЛОВОЙ СИСТЕМЫ (ОПТИМИЗИРОВАНО ПОД ЗАЩИТУ ОТ ПОТЕРИ ПИТАНИЯ)"
                ui_box_row "1) ${C_GRN}ext4${C_RES}  — Универсальный стандарт (data=ordered, commit=5, максимальная живучесть)"
                ui_box_row "2) ${C_CYN}btrfs${C_RES} — CoW ФС со сжатием zstd:3 и flushoncommit (экономия места на бэкапах и коде)"
                ui_box_row "3) ${C_YEL}f2fs${C_RES}  — Специально для USB-флешек, SD-карт и SSD (минимальный износ NAND + data_flush)"
                ui_box_bottom
                printf "Ваш выбор ФС [1-3, Enter = 1 (ext4)]: "
                read -r FS_NUM < /dev/tty || true
                case "${FS_NUM:-1}" in
                    2|btrfs) FS_SEL="btrfs" ;;
                    3|f2fs)  FS_SEL="f2fs" ;;
                    *)       FS_SEL="ext4" ;;
                esac
                format_and_mount_external_drive "$D_IN" "$FS_SEL" "$USE_L" || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            4)
                relocate_heavy_services_to_external_storage || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            5)
                rm -rf "${STORAGE_INC_TORRENTS:?}/"* "${STORAGE_INC_YTDLP:?}/"* "${STORAGE_INCOMPLETE:?}/metube/"* 2>/dev/null || true
                sync_all_homelab_permissions
                ui_ok_msg "Права доступа синхронизированы, временные буферы загрузок очищены!"
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            6)
                unmount_external_storage_safe || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            7)
                unlock_external_storage_cli || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
        esac
    done
    return 0
}
