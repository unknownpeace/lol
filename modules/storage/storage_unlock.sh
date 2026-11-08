is_external_storage_mounted() {
    awk -v mp="${STORAGE_ROOT:-/srv/storage}" '$2 == mp {found=1} END {exit !found}' /proc/mounts 2>/dev/null
}

# Mount Guard: проверка готовности /srv/storage перед стартом тяжелых сервисов Homelab
# Предотвращает запись торрентов/медиа на системную SD-карту/флешку, если внешний диск отпал или ждет LUKS-пароль
is_storage_mount_ready() {
    load_gateway_env
    if [ "${EXT_STORAGE_EXPECTED:-no}" = "yes" ]; then
        if is_external_storage_mounted; then
            return 0
        fi
        return 1
    fi
    return 0
}

# Ожидание инициализации USB/SATA/NVMe блочного устройства по UUID при холодном старте (до N секунд)
wait_for_block_device_uuid() {
    W_UUID="$1"
    W_MAX="${2:-10}"
    [ -z "$W_UUID" ] && return 1
    W_ELAPSED=0
    while [ "$W_ELAPSED" -lt "$W_MAX" ]; do
        FOUND_DEV=$(blkid -U "$W_UUID" 2>/dev/null || findfs "UUID=${W_UUID}" 2>/dev/null || true)
        if [ -n "$FOUND_DEV" ] && [ -b "$FOUND_DEV" ]; then
            printf "%s" "$FOUND_DEV"
            return 0
        fi
        mdev -s 2>/dev/null || true
        sleep 1
        W_ELAPSED=$((W_ELAPSED + 1))
    done
    return 1
}

# Автоматическая неинтерактивная проверка и лечение ФС (fsck -y / btrfs check / fsck.f2fs) после сбоя питания
auto_fsck_device() {
    FSCK_DEV="$1"
    FSCK_FSTYPE="${2:-}"
    [ -b "$FSCK_DEV" ] || return 0
    # Не запускаем fsck на уже смонтированном устройстве
    if awk -v d="$FSCK_DEV" '$1 == d {found=1} END {exit !found}' /proc/mounts 2>/dev/null; then
        return 0
    fi
    [ -z "$FSCK_FSTYPE" ] && FSCK_FSTYPE=$(blkid -s TYPE -o value "$FSCK_DEV" 2>/dev/null || true)
    case "$FSCK_FSTYPE" in
        ext4|ext3|ext2)
            command -v e2fsck >/dev/null 2>&1 && e2fsck -p -f "$FSCK_DEV" >/dev/null 2>&1 || fsck.ext4 -y "$FSCK_DEV" >/dev/null 2>&1 || true
            ;;
        f2fs)
            command -v fsck.f2fs >/dev/null 2>&1 && fsck.f2fs -a "$FSCK_DEV" >/dev/null 2>&1 || true
            ;;
        btrfs)
            command -v btrfs >/dev/null 2>&1 && btrfs check --readonly "$FSCK_DEV" >/dev/null 2>&1 || true
            ;;
        *)
            fsck -p "$FSCK_DEV" >/dev/null 2>&1 || fsck -y "$FSCK_DEV" >/dev/null 2>&1 || true
            ;;
    esac
    return 0
}

# Автоматическая попытка разблокировать (по ключу) и смонтировать внешний накопитель после подачи питания
try_auto_unlock_and_mount_storage() {
    load_gateway_env
    is_external_storage_mounted && return 0
    [ "${EXT_STORAGE_EXPECTED:-no}" = "yes" ] || return 0

    ensure_disk_tools >/dev/null 2>&1 || true
    TARGET_MNT_DEV=""

    if [ -n "${EXT_STORAGE_LUKS_UUID:-}" ]; then
        RAW_LUKS_DEV=$(wait_for_block_device_uuid "$EXT_STORAGE_LUKS_UUID" 8 || true)
        if [ -n "$RAW_LUKS_DEV" ] && [ -b "$RAW_LUKS_DEV" ]; then
            if [ ! -b "/dev/mapper/${LUKS_MAPPER_NAME}" ]; then
                if [ -s "$LUKS_KEYFILE" ]; then
                    cryptsetup open "$RAW_LUKS_DEV" "$LUKS_MAPPER_NAME" --key-file "$LUKS_KEYFILE" >/dev/null 2>&1 || return 1
                else
                    return 1
                fi
            fi
            TARGET_MNT_DEV="/dev/mapper/${LUKS_MAPPER_NAME}"
        else
            return 1
        fi
    elif [ -n "${EXT_STORAGE_UUID:-}" ]; then
        TARGET_MNT_DEV=$(wait_for_block_device_uuid "$EXT_STORAGE_UUID" 8 || true)
        [ -n "$TARGET_MNT_DEV" ] && [ -b "$TARGET_MNT_DEV" ] || return 1
    else
        return 1
    fi

    [ -b "$TARGET_MNT_DEV" ] || return 1
    DET_FS=$(blkid -s TYPE -o value "$TARGET_MNT_DEV" 2>/dev/null || printf "%s" "${EXT_STORAGE_FSTYPE:-ext4}")
    auto_fsck_device "$TARGET_MNT_DEV" "$DET_FS"

    mkdir -p "$STORAGE_ROOT"
    M_OPTS=$(get_optimal_mount_opts "$DET_FS")
    if mount -t "$DET_FS" -o "$M_OPTS" "$TARGET_MNT_DEV" "$STORAGE_ROOT" 2>/dev/null || mount "$TARGET_MNT_DEV" "$STORAGE_ROOT" 2>/dev/null; then
        rm -f "$STORAGE_ALERT_CACHE" 2>/dev/null || true
        init_homelab_storage >/dev/null 2>&1 || true
        start_storage_dependent_services >/dev/null 2>&1 || true
        return 0
    fi
    return 1
}

# Интерактивная команда `gateway unlock`: быстрая разблокировка LUKS2 после перезагрузки + старт Homelab
unlock_external_storage_cli() {
    load_gateway_env
    ensure_disk_tools
    ui_box_top "🔐 РАЗБЛОКИРОВКА ВНЕШНЕГО НАКОПИТЕЛЯ LUKS2 (GATEWAY UNLOCK)"
    if is_external_storage_mounted; then
        ui_box_row "${C_GRN}[✔] Внешний накопитель уже разблокирован и смонтирован в ${STORAGE_ROOT}!${C_RES}"
        ui_box_bottom
        start_storage_dependent_services
        return 0
    fi

    if try_auto_unlock_and_mount_storage; then
        ui_box_row "${C_GRN}[✔] Контейнер LUKS2 автоматически открыт ключом ${LUKS_KEYFILE} и смонтирован!${C_RES}"
        ui_box_row "${C_GRN}[✔] Все зависимые сервисы Homelab запущены.${C_RES}"
        ui_box_bottom
        return 0
    fi

    LUKS_DEV_CAND=""
    if [ -n "${EXT_STORAGE_LUKS_UUID:-}" ]; then
        LUKS_DEV_CAND=$(wait_for_block_device_uuid "$EXT_STORAGE_LUKS_UUID" 5 || true)
    fi
    if [ -z "$LUKS_DEV_CAND" ]; then
        LUKS_DEV_CAND=$(blkid -t TYPE="crypto_LUKS" -o device 2>/dev/null | head -n 1 || true)
    fi

    if [ -z "$LUKS_DEV_CAND" ] || [ ! -b "$LUKS_DEV_CAND" ]; then
        ui_box_bottom
        ui_warn_box "Зашифрованный LUKS2-раздел не обнаружен на шине USB/SATA/NVMe." \
                    "Проверьте кабель/питание внешнего диска и выполните: gateway disk"
        return 1
    fi

    ui_box_row "Найден зашифрованный раздел: ${C_YEL}${LUKS_DEV_CAND}${C_RES}"
    ui_box_bottom
    mount_external_drive_to_storage "$LUKS_DEV_CAND" "ask"
    return $?
}

# Команда `gateway safe-reboot` / `gateway safe-poweroff`: безопасное выключение/перезагрузка
safe_power_action() {
    PWR_MODE="${1:-reboot}"
    load_gateway_env
    ui_box_top "⚡ БЕЗОПАСНОЕ ЗАВЕРШЕНИЕ РАБОТЫ СЕРВЕРА (${PWR_MODE})"
    ui_step_progress 1 4 "Остановка медиа-сервисов, торрентов и баз данных Homelab..."
    stop_storage_dependent_services
    service_ctl vaultwarden stop >/dev/null 2>&1 || true
    service_ctl caddy stop >/dev/null 2>&1 || true

    ui_step_progress 2 4 "Фиксация WAL-журналов SQLite и сохранение состояния шлюза..."
    check_and_recover_power_loss_state
    backup_gateway_state

    ui_step_progress 3 4 "Сброс дисковых кэшей (sync) и безопасная парковка LUKS2..."
    sync
    if is_external_storage_mounted; then
        umount "$STORAGE_ROOT" 2>/dev/null || umount -l "$STORAGE_ROOT" 2>/dev/null || true
    fi
    if [ -b "/dev/mapper/${LUKS_MAPPER_NAME}" ]; then
        cryptsetup close "$LUKS_MAPPER_NAME" 2>/dev/null || true
    fi
    sync

    ui_step_progress 4 4 "Выполнение системной команды ${PWR_MODE}..."
    ui_box_bottom
    if [ "$PWR_MODE" = "poweroff" ] || [ "$PWR_MODE" = "shutdown" ]; then
        poweroff || halt
    else
        reboot
    fi
    return 0
}

# Команда `gateway doctor` / `gateway fix`: умная комплексная авто-починка сервера одной командой
