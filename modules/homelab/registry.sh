ensure_alpine_community_repo() {
    if [ -f /etc/apk/repositories ]; then
        sed -i 's|^#[[:space:]]*\(https\?://.*/v[0-9.]*/community\)|\1|' /etc/apk/repositories 2>/dev/null || true
        sed -i 's|^#[[:space:]]*\(https\?://.*/edge/community\)|\1|' /etc/apk/repositories 2>/dev/null || true
        if ! grep -q '^https\?://.*/community' /etc/apk/repositories 2>/dev/null; then
            MAIN_REPO_LINE=$(grep -E '^https?://.*/main' /etc/apk/repositories 2>/dev/null | head -n 1 || true)
            if [ -n "$MAIN_REPO_LINE" ]; then
                COMM_REPO_LINE=$(printf "%s" "$MAIN_REPO_LINE" | sed 's|/main$|/community|')
                echo "$COMM_REPO_LINE" >> /etc/apk/repositories
            fi
        fi
    fi
    return 0
}

# Инициализация реестра модулей Homelab (/etc/sing-box/homelab/modules.state)
# Формат: ID|ENABLED|OPENRC_SVC|PORT|DOMAIN|SYS_USER|TITLE
init_homelab_registry() {
    umask 022
    mkdir -p "$HOMELAB_DIR" "$HOMELAB_LIB_DIR"
    chmod 755 "$HOMELAB_LIB_DIR" 2>/dev/null || true
    if [ ! -s "$HOMELAB_STATE" ]; then
        cat << 'REG_EOF' > "$HOMELAB_STATE"
# MODULE_ID|ENABLED|OPENRC_SVC|PORT|DOMAIN|SYS_USER|TITLE
caddy|no|caddy|443|ca.lan|caddy|Caddy HTTPS & Local PKI
samba|no|samba|445|_|homelab|Samba SMB2/3 + WSDD + Avahi
vaultwarden|no|vaultwarden|8222|vaultwarden.lan|vaultwarden|Vaultwarden (Bitwarden Server)
forgejo|no|forgejo|3001|forgejo.lan|forgejo|Forgejo (Git Service)
code|no|code-server|8443|code.lan|coder|Server-Code (VS Code Web IDE)
navidrome|no|navidrome|4533|music.lan|navidrome|Navidrome (Music Streaming)
jellyfin|no|jellyfin|8096|jellyfin.lan|jellyfin|Jellyfin (Media Server)
ytdlp|no|ytdlp-webui|8081|downloads.lan|ytdlp|yt-dlp Web UI (Video/Audio Downloader)
torrent|no|qbittorrent-nox|8080|torrents.lan|qbittorrent|qBittorrent-nox (Torrent Web UI)
REG_EOF
    fi
    return 0
}

# Проверка, включен ли модуль в реестре Homelab
is_module_enabled() {
    MOD_QUERY="$1"
    [ -f "$HOMELAB_STATE" ] || return 1
    awk -F'|' -v m="$MOD_QUERY" '$1 == m && $2 == "yes" {found=1} END {exit !found}' "$HOMELAB_STATE" 2>/dev/null
}

# Получение поля модуля из реестра (2=ENABLED, 3=SVC, 4=PORT, 5=DOMAIN, 6=USER, 7=TITLE)
get_module_field() {
    MOD_QUERY="$1"
    FIELD_IDX="$2"
    init_homelab_registry
    awk -F'|' -v m="$MOD_QUERY" -v f="$FIELD_IDX" '$1 == m {print $f; exit}' "$HOMELAB_STATE" 2>/dev/null
    return 0
}

# Обновление статуса ENABLED (yes/no) для модуля в реестре
set_module_state() {
    MOD_TARGET="$1"
    NEW_STATE="$2"
    init_homelab_registry
    awk -F'|' -v OFS='|' -v m="$MOD_TARGET" -v st="$NEW_STATE" '
        $1 == m { $2 = st }
        { print }
    ' "$HOMELAB_STATE" > "${HOMELAB_STATE}.tmp.$$" && mv -f "${HOMELAB_STATE}.tmp.$$" "$HOMELAB_STATE"
    return 0
}

# Подсчет количества активных модулей Homelab
count_enabled_homelab_modules() {
    [ -f "$HOMELAB_STATE" ] || { echo "0"; return 0; }
    awk -F'|' '$1 !~ /^#/ && $2 == "yes" {c++} END {print c+0}' "$HOMELAB_STATE" 2>/dev/null
    return 0
}

# Создание единой группы media (GID 990) и системных пользователей для Samba и сервисов общего хранилища
ensure_media_group_and_users() {
    if [ -z "${SMB_USER:-}" ] || [ -z "${ADMIN_PASS:-}" ]; then
        load_gateway_env
    fi
    [ -z "${SMB_USER:-}" ] && SMB_USER="${AGH_USER:-homelab}"

    if ! grep -q "^${MEDIA_GROUP}:" /etc/group 2>/dev/null; then
        addgroup -g "$MEDIA_GID" "$MEDIA_GROUP" 2>/dev/null || addgroup "$MEDIA_GROUP" 2>/dev/null || true
    fi

    if ! id "$SMB_USER" >/dev/null 2>&1; then
        adduser -D -H -s /sbin/nologin -G "$MEDIA_GROUP" "$SMB_USER" 2>/dev/null || \
        adduser -D -H -s /sbin/nologin "$SMB_USER" 2>/dev/null || true
    fi
    addgroup "$SMB_USER" "$MEDIA_GROUP" 2>/dev/null || true

    # Разблокировка сервисных и пользовательских аккаунтов ('!' -> '*' в /etc/shadow) для smbd, OpenRC и su
    for UNLOCK_U in "$SMB_USER" caddy vaultwarden forgejo navidrome jellyfin ytdlp qbittorrent coder homelab; do
        if [ -f /etc/shadow ] && grep -q "^${UNLOCK_U}:!" /etc/shadow 2>/dev/null; then
            sed -i "s/^${UNLOCK_U}:!/${UNLOCK_U}:*/" /etc/shadow 2>/dev/null || passwd -u "$UNLOCK_U" >/dev/null 2>&1 || true
        fi
    done

    # Добавление установленных сервисных пользователей медиаконвейера в единую группу media
    for SVC_U in jellyfin navidrome ytdlp qbittorrent coder; do
        if id "$SVC_U" >/dev/null 2>&1; then
            addgroup "$SVC_U" "$MEDIA_GROUP" 2>/dev/null || true
        fi
    done
    return 0
}

# Инициализация структуры единого хранилища /srv/storage и настройка прав (setgid 2775 + POSIX ACL)
init_homelab_storage() {
    umask 002
    ensure_media_group_and_users
    mkdir -p \
        "$STORAGE_MUSIC" \
        "$STORAGE_VIDEOS" \
        "$STORAGE_VIDEOS_MOVIES" \
        "$STORAGE_VIDEOS_SERIES" \
        "$STORAGE_DOWNLOADS" \
        "$STORAGE_DL_MUSIC" \
        "$STORAGE_DL_VIDEOS" \
        "$STORAGE_DL_OTHER" \
        "$STORAGE_INCOMPLETE" \
        "$STORAGE_INC_TORRENTS" \
        "$STORAGE_INC_YTDLP" \
        "$STORAGE_BACKUPS" \
        "$STORAGE_REPOS" \
        "$STORAGE_CODE" \
        "$STORAGE_PERSONAL"

    repair_storage_permissions
    umask 022
    return 0
}

# Выставление эталонных прав доступа на /srv/storage (группа media, setgid 2775, POSIX ACL)
repair_storage_permissions() {
    ensure_media_group_and_users
    [ -d "$STORAGE_ROOT" ] || return 0

    chmod 755 /srv 2>/dev/null || true
    chown "${SMB_USER}:${MEDIA_GROUP}" "$STORAGE_ROOT" 2>/dev/null || chown root:"$MEDIA_GROUP" "$STORAGE_ROOT" 2>/dev/null || true
    chmod 2775 "$STORAGE_ROOT" 2>/dev/null || true

    for SUB_D in \
        "$STORAGE_MUSIC" \
        "$STORAGE_VIDEOS" \
        "$STORAGE_VIDEOS_MOVIES" \
        "$STORAGE_VIDEOS_SERIES" \
        "$STORAGE_DOWNLOADS" \
        "$STORAGE_DL_MUSIC" \
        "$STORAGE_DL_VIDEOS" \
        "$STORAGE_DL_OTHER" \
        "$STORAGE_INCOMPLETE" \
        "$STORAGE_INC_TORRENTS" \
        "$STORAGE_INC_YTDLP" \
        "$STORAGE_BACKUPS" \
        "$STORAGE_REPOS" \
        "$STORAGE_CODE" \
        "$STORAGE_PERSONAL"; do
        [ -d "$SUB_D" ] || mkdir -p "$SUB_D" 2>/dev/null || continue
    done

    for TOP_D in "$STORAGE_MUSIC" "$STORAGE_VIDEOS" "$STORAGE_DOWNLOADS" "$STORAGE_CODE" "$STORAGE_PERSONAL" "$STORAGE_BACKUPS"; do
        [ -d "$TOP_D" ] || continue
        chown -R "${SMB_USER}:${MEDIA_GROUP}" "$TOP_D" 2>/dev/null || chgrp -R "$MEDIA_GROUP" "$TOP_D" 2>/dev/null || true
        find "$TOP_D" -type d -exec chmod 2775 {} + 2>/dev/null || true
        find "$TOP_D" -type f -exec chmod 0664 {} + 2>/dev/null || true
    done

    # Выделение прав владельца на временные буферы соответствующим демонам при сохранении группы media (2775)
    if id qbittorrent >/dev/null 2>&1 && [ -d "$STORAGE_INC_TORRENTS" ]; then
        chown -R "qbittorrent:${MEDIA_GROUP}" "$STORAGE_INC_TORRENTS" 2>/dev/null || true
        chmod 2775 "$STORAGE_INC_TORRENTS" 2>/dev/null || true
    fi
    if id ytdlp >/dev/null 2>&1 && [ -d "$STORAGE_INC_YTDLP" ]; then
        chown -R "ytdlp:${MEDIA_GROUP}" "$STORAGE_INC_YTDLP" 2>/dev/null || true
        chmod 2775 "$STORAGE_INC_YTDLP" 2>/dev/null || true
    fi

    # Применение наследуемых POSIX ACL (если установлен пакет acl и ФС поддерживает ACL)
    if command -v setfacl >/dev/null 2>&1; then
        setfacl -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" -d -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" "$STORAGE_ROOT" 2>/dev/null || true
        setfacl -R -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" -d -m "u:${SMB_USER}:rwx,g:${MEDIA_GROUP}:rwx,o::rx" \
            "$STORAGE_MUSIC" "$STORAGE_VIDEOS" "$STORAGE_DOWNLOADS" 2>/dev/null || true
        for ACL_U in jellyfin navidrome ytdlp qbittorrent coder; do
            if id "$ACL_U" >/dev/null 2>&1; then
                setfacl -R -m "u:${ACL_U}:rwx" -d -m "u:${ACL_U}:rwx" \
                    "$STORAGE_MUSIC" "$STORAGE_VIDEOS" "$STORAGE_DOWNLOADS" 2>/dev/null || true
            fi
        done
    fi
    return 0
}

# Проверка: смонтирован ли внешний накопитель (и зашифрован ли он LUKS2) в /srv/storage
get_storage_disk_badge() {
    load_gateway_env
    MNT_SRC=$(awk -v mp="${STORAGE_ROOT:-/srv/storage}" '$2 == mp {print $1; exit}' /proc/mounts 2>/dev/null || true)
    MNT_FSTYPE=$(awk -v mp="${STORAGE_ROOT:-/srv/storage}" '$2 == mp {print $3; exit}' /proc/mounts 2>/dev/null || true)
    if [ -n "$MNT_SRC" ]; then
        case "$MNT_SRC" in
            /dev/mapper/*|*luks*|*crypt*)
                printf "● LUKS2 UNLOCKED [%s]" "${MNT_FSTYPE:-FS}"
                return 0
                ;;
            *)
                printf "● Внешний [%s: %s]" "$(basename "$MNT_SRC")" "${MNT_FSTYPE:-FS}"
                return 0
                ;;
        esac
    fi
    if [ "${EXT_STORAGE_EXPECTED:-no}" = "yes" ]; then
        if [ -n "${EXT_STORAGE_LUKS_UUID:-}" ]; then
            printf "▲ Ждет разблокировки LUKS2 (выполните: gateway unlock)"
        else
            printf "▲ Внешний диск отключен (выполните: gateway disk)"
        fi
        return 0
    fi
    printf "○ Системный раздел"
    return 0
}

# Вывод статистики использования единого хранилища /srv/storage с прогресс-барами
print_storage_stats() {
    load_gateway_env
    if is_storage_mount_ready; then
        init_homelab_storage
    fi
    DISK_MODE_TXT=$(get_storage_disk_badge)
    DISK_PCT=$(get_disk_usage_pct "$STORAGE_ROOT")
    DISK_BAR=$(ui_progress_bar "$DISK_PCT" 14)

    ui_box_top "💽 ЕДИНОЕ ФАЙЛОВОЕ ХРАНИЛИЩЕ: ${STORAGE_ROOT} (${DISK_MODE_TXT})"
    DF_LINE=$(df -hT "$STORAGE_ROOT" 2>/dev/null | awk 'NR==2 {printf "Устройство: %-18s | ФС: %-6s | Занято: %s из %s (Свободно: %s)", $1, $2, $4, $3, $5}' || true)
    ui_box_row "Заполнение: ${DISK_BAR}  ${C_DIM}${DF_LINE}${C_RES}"
    if ! is_storage_mount_ready; then
        ui_box_row "${C_YEL}[▲] ВНИМАНИЕ: Внешний накопитель ожидает разблокировки LUKS2 (gateway unlock) или подключения!${C_RES}"
        ui_box_row "${C_DIM}    Зависимые медиа-сервисы удерживаются в безопасной паузе для защиты системного диска.${C_RES}"
    fi
    ui_box_sep "КАТАЛОГИ МЕДИАТЕКИ И ОБЛАКА"
    for D_ITEM in \
        "$STORAGE_MUSIC" \
        "$STORAGE_VIDEOS" \
        "$STORAGE_VIDEOS_MOVIES" \
        "$STORAGE_VIDEOS_SERIES" \
        "$STORAGE_DOWNLOADS" \
        "$STORAGE_DL_MUSIC" \
        "$STORAGE_DL_VIDEOS" \
        "$STORAGE_DL_OTHER" \
        "$STORAGE_REPOS" \
        "$STORAGE_CODE" \
        "$STORAGE_PERSONAL" \
        "$STORAGE_BACKUPS" \
        "$STORAGE_INCOMPLETE"; do
        if [ -d "$D_ITEM" ]; then
            D_SZ=$(du -sh "$D_ITEM" 2>/dev/null | awk '{print $1}' || echo "0")
            D_PM=$(stat -c "%a %U:%G" "$D_ITEM" 2>/dev/null || echo "н/д")
            printf "%s│%s  ▸ %-40s : %s%-8s%s (%s)\n" "$C_CYN" "$C_RES" "$D_ITEM" "$C_BLD" "$D_SZ" "$C_RES" "$D_PM"
        fi
    done
    ui_box_bottom
    return 0
}

# ==============================================================================
# Подсистема внешних накопителей (USB / SATA / NVMe):
# Поддержка LUKS2 шифрования, форматирования (ext4 / btrfs / f2fs),
# авто-разблокировки при загрузке и переноса тяжелых данных сервисов Homelab
# ==============================================================================

# Установка утилит для работы с дисками, LUKS2 и файловыми системами ext4, btrfs, f2fs
