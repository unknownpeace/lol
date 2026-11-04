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

# Надежное определение корневого/системного диска (защита NVMe nvme0n1pX, SD/eMMC mmcblk0pX, VirtIO vda, SATA sda)
get_root_base_disk() {
    ROOT_SRC=$(awk '$2 == "/" || $2 == "/boot" || $2 == "/media/mmcblk0p1" || $2 == "/media/sda1" {print $1; exit}' /proc/mounts 2>/dev/null || true)
    [ -z "$ROOT_SRC" ] && ROOT_SRC=$(df / 2>/dev/null | awk 'NR==2 {print $1}' || true)
    ROOT_PK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n 1 | tr -d ' \t\r\n' || true)
    if [ -n "$ROOT_PK" ]; then
        printf "/dev/%s" "$ROOT_PK"
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
            printf "/dev/sda"
            ;;
    esac
    return 0
}

# Проверка: принадлежит ли блочное устройство системному диску ОС (/ , /boot, /var, swap)
is_system_protected_device() {
    CHK_DEV="${1:-}"
    [ -z "$CHK_DEV" ] && return 0
    ROOT_D=$(get_root_base_disk)
    case "$CHK_DEV" in
        "$ROOT_D"|"$ROOT_D"[0-9]*|"$ROOT_D"p[0-9]*)
            return 0
            ;;
    esac
    # Дополнительная проверка по точкам монтирования разделов выбранного диска
    if lsblk -rnpo MOUNTPOINT "$CHK_DEV" 2>/dev/null | grep -Eq '^(/|/boot|/etc|/var|/usr|/media/.*|\[SWAP\])$'; then
        return 0
    fi
    return 1
}

# Сканирование доступных внешних разделов и дисков (исключая системный диск ОС)
list_available_external_disks() {
    ensure_disk_tools
    ROOT_DISK=$(get_root_base_disk)
    rm -f "$EXT_DISK_SCAN_CACHE"
    touch "$EXT_DISK_SCAN_CACHE"

    ui_box_top "🔌 ОБНАРУЖЕННЫЕ ВНЕШНИЕ НАКОПИТЕЛИ (Системный диск ${ROOT_DISK} защищен)"
    lsblk -rnpo NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null | awk \
        -v root_d="$ROOT_DISK" \
        -v cache_f="$EXT_DISK_SCAN_CACHE" \
        -v c_cyn="$C_CYN" -v c_grn="$C_GRN" -v c_yel="$C_YEL" -v c_dim="$C_DIM" -v c_res="$C_RES" '
        $2 == "part" || $2 == "disk" || $2 == "crypt" {
            dev = $1; dtype = $2; sz = $3; fs = ($4 != "" ? $4 : "без ФС"); mp = ($5 != "" ? $5 : "не смонтирован")
            model = ""
            for (i=6; i<=NF; i++) model = model (i>6 ? " " : "") $i
            gsub(/\\x20/, " ", model)
            if (dev == root_d || index(dev, root_d "p") == 1 || index(dev, root_d "1") == 1 || index(dev, root_d "2") == 1 || index(dev, root_d "3") == 1 || index(dev, root_d "4") == 1) next
            if (mp == "/" || mp == "/boot" || mp == "/var" || mp == "[SWAP]") next
            idx++
            tag = (fs == "crypto_LUKS") ? c_yel "[◆ LUKS2 Зашифрован]" c_res : c_grn "[● " fs "]" c_res
            printf "%s│%s  %s[%d]%s %-18s │ %-5s │ %-7s │ %-22s │ Точка: %-15s %s\n", c_cyn, c_res, c_cyn, idx, c_res, dev, dtype, sz, tag, mp, model
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

# Выбор устройства из таблицы по номеру [1..N] или прямому пути /dev/...
resolve_disk_selection() {
    RAW_SEL=$(printf "%s" "${1:-}" | tr -d ' \t\r\n')
    [ -z "$RAW_SEL" ] && return 1
    case "$RAW_SEL" in
        /dev/*)
            PICKED_DEV="$RAW_SEL"
            ;;
        *[!0-9]*)
            return 1
            ;;
        *)
            PICKED_DEV=$(awk -v t="$RAW_SEL" 'NR == t {print $1; exit}' "$EXT_DISK_SCAN_CACHE" 2>/dev/null || true)
            ;;
    esac
    [ -b "${PICKED_DEV:-}" ] || return 1
    if is_system_protected_device "$PICKED_DEV"; then
        ui_warn_box "ЗАЩИТА ДАННЫХ: Выбран системный диск ОС (${PICKED_DEV})!" \
                    "Выберите только внешний накопитель USB / SATA / NVMe из списка." >&2
        return 1
    fi
    printf "%s" "$PICKED_DEV"
    return 0
}

# Остановка и запуск всех сервисов, использующих /srv/storage (перед монтированием или миграцией)
stop_storage_dependent_services() {
    for svc_s in samba qbittorrent-nox ytdlp-webui jellyfin navidrome forgejo code-server; do
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
    return 0
}

# Безопасные для внезапного отключения питания опции монтирования (ext4 / btrfs / f2fs)
# Убрана опасная опция commit=30 (риск потери 30 сек транзакций SQLite), включен стандартный 5-сек интервал + data=ordered
get_optimal_mount_opts() {
    FS_T="$1"
    case "$FS_T" in
        btrfs) printf "defaults,noatime,compress=zstd:3,ssd,space_cache=v2,flushoncommit,nofail" ;;
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
                printf "Введите пароль (passphrase) для разблокировки LUKS2 диска %s: " "$TARGET_DEV"
                read -r LUKS_PASS < /dev/tty || true
                LUKS_PASS=$(printf "%s" "$LUKS_PASS" | tr -d '\r\n')
                if ! printf "%s" "$LUKS_PASS" | cryptsetup open "$TARGET_DEV" "$LUKS_MAPPER_NAME" -; then
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
                        mkdir -p "$(dirname "$LUKS_KEYFILE")"
                        umask 077
                        if [ ! -s "$LUKS_KEYFILE" ]; then
                            dd if=/dev/urandom of="$LUKS_KEYFILE" bs=4096 count=1 >/dev/null 2>&1
                        fi
                        chmod 400 "$LUKS_KEYFILE"
                        umask 022
                        if printf "%s" "$LUKS_PASS" | cryptsetup luksAddKey "$TARGET_DEV" "$LUKS_KEYFILE" -; then
                            ui_ok_msg "Ключ авто-разблокировки добавлен в слот LUKS2 и защищен (${LUKS_KEYFILE}, mode 0400)!"
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

    # Если в локальной папке /srv/storage уже были файлы (на системном разделе), сохраняем их во временный буфер для переноса
    MIGRATE_TMP="/tmp/homelab_storage_migrate_$$"
    rm -rf "$MIGRATE_TMP"
    if ! is_external_storage_mounted; then
        if [ -d "$STORAGE_ROOT" ] && [ -n "$(ls -A "$STORAGE_ROOT" 2>/dev/null)" ]; then
            ui_step_progress 2 3 "Сохранение существующих файлов из локальной папки ${STORAGE_ROOT} для переноса..."
            mkdir -p "$MIGRATE_TMP"
            cp -a "${STORAGE_ROOT}/." "$MIGRATE_TMP/" 2>/dev/null || true
        fi
    else
        umount "$STORAGE_ROOT" 2>/dev/null || umount -l "$STORAGE_ROOT" 2>/dev/null || true
    fi

    mkdir -p "$STORAGE_ROOT"
    MNT_OPTS=$(get_optimal_mount_opts "$FS_TYPE")
    ui_step_progress 3 3 "Монтирование ${MOUNT_DEV} (${FS_TYPE}) в ${STORAGE_ROOT} с защитой от сбоя питания..."
    if ! mount -t "$FS_TYPE" -o "$MNT_OPTS" "$MOUNT_DEV" "$STORAGE_ROOT" 2>/dev/null; then
        if ! mount "$MOUNT_DEV" "$STORAGE_ROOT"; then
            ui_warn_box "Не удалось смонтировать ${MOUNT_DEV} в ${STORAGE_ROOT}!" \
                        "Выполните проверку диска через: gateway doctor"
            start_storage_dependent_services
            return 1
        fi
    fi

    # Перенос сохраненных файлов на новый смонтированный диск
    if [ -d "$MIGRATE_TMP" ]; then
        cp -a "$MIGRATE_TMP/." "$STORAGE_ROOT/" 2>/dev/null || true
        rm -rf "$MIGRATE_TMP"
        ui_ok_msg "Существующие данные медиатеки перенесены на внешний накопитель!"
    fi

    # Безопасная настройка автомонтирования в /etc/fstab (с pass=0 и nofail, чтобы сервер НИКОГДА не зависал в Emergency Shell без SSH!)
    sed -i "\|[[:space:]]${STORAGE_ROOT}[[:space:]]|d" /etc/fstab 2>/dev/null || true
    EXT_STORAGE_EXPECTED="yes"
    EXT_STORAGE_FSTYPE="$FS_TYPE"
    if [ "$IS_LUKS" = "yes" ]; then
        EXT_STORAGE_LUKS_UUID="$LUKS_UUID"
        EXT_STORAGE_UUID="$FS_UUID"
        mkdir -p /etc/conf.d
        touch /etc/conf.d/dmcrypt
        sed -i "/^target='${LUKS_MAPPER_NAME}'/,+2d" /etc/conf.d/dmcrypt 2>/dev/null || true
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
    FS_CHOICE="$2"   # ext4 | btrfs | f2fs
    USE_LUKS="$3"    # yes | no

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
    printf "Для подтверждения форматирования введите заглавными буквами YES: "
    read -r CONFIRM_FMT < /dev/tty || true
    if [ "$CONFIRM_FMT" != "YES" ]; then
        ui_info_msg "Форматирование отменено."
        return 0
    fi

    stop_storage_dependent_services
    umount "$STORAGE_ROOT" 2>/dev/null || true
    umount "$TARGET_DEV" 2>/dev/null || true
    for sub_p in "${TARGET_DEV}"*[0-9]; do
        [ -b "$sub_p" ] && umount "$sub_p" 2>/dev/null || true
    done
    [ -b "/dev/mapper/${LUKS_MAPPER_NAME}" ] && cryptsetup close "$LUKS_MAPPER_NAME" 2>/dev/null || true

    # Если выбран целый диск (disk), создаем на нем чистую таблицу GPT и 1 раздел на 100% объема
    DEV_TYPE=$(lsblk -no TYPE "$TARGET_DEV" 2>/dev/null | head -n 1 | tr -d ' \t\r\n')
    if [ "$DEV_TYPE" = "disk" ]; then
        ui_step_progress 1 3 "Создание новой таблицы разделов GPT на диске ${TARGET_DEV}..."
        wipefs -a "$TARGET_DEV" >/dev/null 2>&1 || true
        printf "label: gpt\n;\n" | sfdisk --force "$TARGET_DEV" >/dev/null 2>&1 || true
        mdev -s 2>/dev/null || partprobe "$TARGET_DEV" 2>/dev/null || true
        sleep 2
        PART_DEV=$(lsblk -rnpo NAME,TYPE "$TARGET_DEV" 2>/dev/null | awk '$2=="part" {print $1; exit}')
        [ -n "$PART_DEV" ] && TARGET_DEV="$PART_DEV"
    else
        wipefs -a "$TARGET_DEV" >/dev/null 2>&1 || true
    fi

    FMT_TARGET="$TARGET_DEV"
    if [ "$USE_LUKS" = "yes" ]; then
        printf "Задайте пароль (passphrase) для шифрования LUKS2 диска %s [Enter = использовать единый пароль шлюза]: " "$TARGET_DEV"
        read -r NEW_LUKS_PASS < /dev/tty || true
        NEW_LUKS_PASS=$(printf "%s" "$NEW_LUKS_PASS" | tr -d '\r\n')
        load_gateway_env
        [ -z "$NEW_LUKS_PASS" ] && NEW_LUKS_PASS="${ADMIN_PASS:-admin}"

        ui_step_progress 2 3 "Форматирование контейнера LUKS2 (cipher: aes-xts-plain64, key: 512 bit, pbkdf: argon2id)..."
        if ! printf "%s" "$NEW_LUKS_PASS" | cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --pbkdf argon2id --batch-mode "$TARGET_DEV" -; then
            ui_warn_box "Ошибка создания контейнера LUKS2 на ${TARGET_DEV}!" "Проверьте исправность накопителя (dmesg)."
            return 1
        fi

        # Создаем и регистрируем ключ авто-разблокировки для старта сервера без ввода пароля с клавиатуры
        mkdir -p "$(dirname "$LUKS_KEYFILE")"
        umask 077
        dd if=/dev/urandom of="$LUKS_KEYFILE" bs=4096 count=1 >/dev/null 2>&1
        chmod 400 "$LUKS_KEYFILE"
        umask 022
        printf "%s" "$NEW_LUKS_PASS" | cryptsetup luksAddKey "$TARGET_DEV" "$LUKS_KEYFILE" - >/dev/null 2>&1 || true

        if ! cryptsetup open "$TARGET_DEV" "$LUKS_MAPPER_NAME" --key-file "$LUKS_KEYFILE"; then
            printf "%s" "$NEW_LUKS_PASS" | cryptsetup open "$TARGET_DEV" "$LUKS_MAPPER_NAME" - || return 1
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

    mount_external_drive_to_storage "$TARGET_DEV" "yes"
    return 0
}

# Умный перенос тяжелых данных сервисов Homelab (Git-репозитории Forgejo, проекты VS Code, кэш Jellyfin, бэкапы) на внешний диск
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
        cp -a /var/lib/forgejo/repos/. "${STORAGE_REPOS}/repos/" 2>/dev/null || true
        rm -rf /var/lib/forgejo/repos
        ln -s "${STORAGE_REPOS}/repos" /var/lib/forgejo/repos
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
        cp -a /var/lib/coder/workspace/. "$STORAGE_CODE/" 2>/dev/null || true
        rm -rf /var/lib/coder/workspace
        ln -s "$STORAGE_CODE" /var/lib/coder/workspace
    elif [ -d /var/lib/coder ] && [ ! -e /var/lib/coder/workspace ]; then
        ln -s "$STORAGE_CODE" /var/lib/coder/workspace
    fi
    if id coder >/dev/null 2>&1; then
        chown -R "coder:${MEDIA_GROUP}" "$STORAGE_CODE" 2>/dev/null || true
        chmod 2775 "$STORAGE_CODE" 2>/dev/null || true
    fi
    ui_box_row "${C_GRN}[✔]${C_RES} Рабочая папка проектов VS Code (Server-Code) вынесена в ${STORAGE_CODE}"

    # 3. Тяжелый кэш транскодирования и метаданные обложек Jellyfin -> /srv/storage/.jellyfin-data
    JF_EXT_DIR="${STORAGE_ROOT}/.jellyfin-data"
    mkdir -p "${JF_EXT_DIR}/cache" "${JF_EXT_DIR}/metadata"
    if [ -d /var/cache/jellyfin ] && [ ! -L /var/cache/jellyfin ]; then
        cp -a /var/cache/jellyfin/. "${JF_EXT_DIR}/cache/" 2>/dev/null || true
        rm -rf /var/cache/jellyfin
        ln -s "${JF_EXT_DIR}/cache" /var/cache/jellyfin
    fi
    if [ -d /var/lib/jellyfin/metadata ] && [ ! -L /var/lib/jellyfin/metadata ]; then
        cp -a /var/lib/jellyfin/metadata/. "${JF_EXT_DIR}/metadata/" 2>/dev/null || true
        rm -rf /var/lib/jellyfin/metadata
        ln -s "${JF_EXT_DIR}/metadata" /var/lib/jellyfin/metadata
    fi
    if id jellyfin >/dev/null 2>&1; then
        chown -R "jellyfin:${MEDIA_GROUP}" "$JF_EXT_DIR" 2>/dev/null || true
        chmod -R 750 "$JF_EXT_DIR" 2>/dev/null || true
    fi
    ui_box_row "${C_GRN}[✔]${C_RES} Кэш транскодирования и обложки Jellyfin вынесены в ${JF_EXT_DIR}"

    # 4. Кэш транскодирования аудио Navidrome -> /srv/storage/.navidrome-cache
    ND_EXT_DIR="${STORAGE_ROOT}/.navidrome-cache"
    mkdir -p "$ND_EXT_DIR"
    if [ -d /var/lib/navidrome/cache ] && [ ! -L /var/lib/navidrome/cache ]; then
        cp -a /var/lib/navidrome/cache/. "$ND_EXT_DIR/" 2>/dev/null || true
        rm -rf /var/lib/navidrome/cache
        ln -s "$ND_EXT_DIR" /var/lib/navidrome/cache
    fi
    if id navidrome >/dev/null 2>&1; then
        chown -R "navidrome:${MEDIA_GROUP}" "$ND_EXT_DIR" 2>/dev/null || true
    fi
    ui_box_row "${C_GRN}[✔]${C_RES} Кэш аудио-транскодирования Navidrome вынесен в ${ND_EXT_DIR}"

    # 5. Автоматическое зеркалирование архивов бэкапа в /srv/storage/Backups
    mkdir -p "$STORAGE_BACKUPS"
    [ -f "$BACKUP_ARCHIVE" ] && cp -f "$BACKUP_ARCHIVE" "${STORAGE_BACKUPS}/gateway_backup_latest.tar.gz" 2>/dev/null || true
    chmod 750 "$STORAGE_BACKUPS" 2>/dev/null || true
    ui_box_row "${C_GRN}[✔]${C_RES} Хранилище резервных копий и личное облако Samba готовы: ${STORAGE_BACKUPS}"

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
    ui_step_progress 1 3 "Остановка зависимых медиа-сервисов и торрентов..."
    stop_storage_dependent_services

    ui_step_progress 2 3 "Сброс кэшей записи на диск (sync) и размонтирование ${STORAGE_ROOT}..."
    sync
    if ! is_external_storage_mounted || umount "$STORAGE_ROOT" 2>/dev/null || umount -l "$STORAGE_ROOT" 2>/dev/null; then
        sed -i "\|[[:space:]]${STORAGE_ROOT}[[:space:]]|d" /etc/fstab 2>/dev/null || true
        EXT_STORAGE_EXPECTED="no"
        save_homelab_env
        ui_step_progress 3 3 "Закрытие криптоконтейнера LUKS2..."
        if [ -b "/dev/mapper/${LUKS_MAPPER_NAME}" ]; then
            cryptsetup close "$LUKS_MAPPER_NAME" 2>/dev/null || true
            ui_box_row "${C_GRN}[✔] Контейнер LUKS2 (${LUKS_MAPPER_NAME}) безопасно заблокирован и закрыт.${C_RES}"
        fi
        ui_box_row "${C_GRN}[✔] Внешний накопитель безопасно отключен! Теперь его можно физически извлечь.${C_RES}"
        ui_box_bottom
    else
        ui_box_bottom
        start_storage_dependent_services
        ui_warn_box "Не удалось размонтировать ${STORAGE_ROOT} (устройство занято процессом)." \
                    "Закройте открытые файлы в шаре Samba и повторите: gateway eject"
        return 1
    fi
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
        ui_box_row "• 🎵 ${C_CYN}Music${C_RES} & 🎬 ${C_CYN}Videos (Movies/Series)${C_RES} — вся медиатека Jellyfin и Navidrome"
        ui_box_row "• ⬇️ ${C_CYN}Downloads & Incomplete${C_RES}          — тяжелые раздачи qBittorrent и буфер yt-dlp (0 износа SD/eMMC!)"
        ui_box_row "• 💻 ${C_CYN}Git-Repos & Workspace${C_RES}           — Git-репозитории/LFS Forgejo и проекты VS Code (Server-Code)"
        ui_box_row "• 🗂️ ${C_CYN}Personal & Backups${C_RES}              — личный сетевой диск Samba для ПК/телефона + архивы бэкапов"
        ui_box_row "• ⚡ ${C_CYN}.jellyfin-data & .navidrome${C_RES}     — тяжелый кэш транскодирования видео/аудио и постеры"
        ui_box_sep "ДЕЙСТВИЯ С НАКОПИТЕЛЯМИ [0-7]"
        ui_box_row "${C_CYN}1)${C_RES} 🔌 Подключить существующий диск / раздел (обычный или зашифрованный ${C_YEL}LUKS2${C_RES}) в ${STORAGE_ROOT}"
        ui_box_row "${C_CYN}2)${C_RES} 💿 Форматировать накопитель в ${C_GRN}ext4 / btrfs / f2fs${C_RES} (без шифрования) и подключить"
        ui_box_row "${C_CYN}3)${C_RES} 🔐 Зашифровать накопитель в ${C_YEL}LUKS2 (AES-XTS 512-bit)${C_RES} + отформатировать (${C_GRN}ext4 / btrfs / f2fs${C_RES})"
        ui_box_row "${C_CYN}4)${C_RES} 🚀 Вынести все тяжелые данные сервисов (Git, VS Code, кэш Jellyfin, Бэкапы) на накопитель"
        ui_box_row "${C_CYN}5)${C_RES} 🔧 Синхронизировать права доступа (${MEDIA_GROUP} + setgid 2775 + POSIX ACL) и очистить буферы"
        ui_box_row "${C_CYN}6)${C_RES} ⏏️ Безопасно размонтировать внешний диск и закрыть контейнер LUKS2 (${C_YEL}gateway eject${C_RES})"
        ui_box_row "${C_CYN}7)${C_RES} 🔓 Быстро разблокировать LUKS2-накопитель после перезагрузки (${C_GRN}gateway unlock${C_RES})"
        ui_box_row "${C_CYN}0)${C_RES} Назад"
        ui_box_bottom
        printf "Выберите действие [0-7]: "
        read -r DSK_ACT < /dev/tty || true
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
                rm -rf "${STORAGE_INC_TORRENTS:?}/"* "${STORAGE_INC_YTDLP:?}/"* 2>/dev/null || true
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

# ==============================================================================
# Центральная система HTTPS, локальный PKI и домены *.lan (Caddy + AdGuard Home)
# ==============================================================================

# Поиск актуального пути корневого сертификата Caddy Root CA
