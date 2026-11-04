create_unified_backup() {
    INCLUDE_MEDIA="${1:-no}"
    STAGE_DIR="/var/lib/gateway_backup_stage"
    rm -rf "$STAGE_DIR"
    mkdir -p "${STAGE_DIR}/sqlite_dumps"
    chmod 700 "$STAGE_DIR" 2>/dev/null || true

    echo "${C_CYN}[*] Подготовка консистентной резервной копии (Шлюз + Homelab)...${C_RES}"

    # 1. Горячее безопасное резервное копирование всех баз SQLite через sqlite3 .backup
    if command -v sqlite3 >/dev/null 2>&1; then
        [ -f /var/lib/vaultwarden/db.sqlite3 ] && \
            sqlite3 /var/lib/vaultwarden/db.sqlite3 ".backup '${STAGE_DIR}/sqlite_dumps/vaultwarden.sqlite3'" 2>/dev/null || true
        [ -f /var/lib/forgejo/data/forgejo.db ] && \
            sqlite3 /var/lib/forgejo/data/forgejo.db ".backup '${STAGE_DIR}/sqlite_dumps/forgejo.sqlite3'" 2>/dev/null || true
        [ -f /var/lib/navidrome/navidrome.db ] && \
            sqlite3 /var/lib/navidrome/navidrome.db ".backup '${STAGE_DIR}/sqlite_dumps/navidrome.sqlite3'" 2>/dev/null || true
        [ -f /var/lib/jellyfin/data/jellyfin.db ] && \
            sqlite3 /var/lib/jellyfin/data/jellyfin.db ".backup '${STAGE_DIR}/sqlite_dumps/jellyfin.sqlite3'" 2>/dev/null || true
    fi

    # 2. Сбор всех конфигурационных директорий, секретов и локального CA Caddy
    BACKUP_PATHS="/etc/sing-box"
    [ -f "$AGH_CONF" ] && BACKUP_PATHS="$BACKUP_PATHS $AGH_CONF"
    [ -f "$ALPINE_NFT_CONF" ] && BACKUP_PATHS="$BACKUP_PATHS $ALPINE_NFT_CONF"
    [ -d /etc/caddy ] && BACKUP_PATHS="$BACKUP_PATHS /etc/caddy"
    [ -d /var/lib/caddy ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/caddy"
    [ -d /etc/samba ] && BACKUP_PATHS="$BACKUP_PATHS /etc/samba"
    [ -d /var/lib/samba/private ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/samba/private"
    [ -f /etc/conf.d/vaultwarden ] && BACKUP_PATHS="$BACKUP_PATHS /etc/conf.d/vaultwarden"
    [ -d /var/lib/vaultwarden ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/vaultwarden"
    [ -d /etc/forgejo ] && BACKUP_PATHS="$BACKUP_PATHS /etc/forgejo"
    [ -d /etc/navidrome ] && BACKUP_PATHS="$BACKUP_PATHS /etc/navidrome"
    [ -d /etc/jellyfin ] && BACKUP_PATHS="$BACKUP_PATHS /etc/jellyfin"
    [ -d /var/lib/qbittorrent/.config ] && BACKUP_PATHS="$BACKUP_PATHS /var/lib/qbittorrent/.config"
    [ "$INCLUDE_MEDIA" = "yes" ] && [ -d "$STORAGE_ROOT" ] && BACKUP_PATHS="$BACKUP_PATHS $STORAGE_ROOT"

    umask 077
    # shellcheck disable=SC2086
    if ! tar --exclude='*cache.db*' -czf "${BACKUP_ARCHIVE}.tmp.$$" $BACKUP_PATHS "$STAGE_DIR" 2>/dev/null; then
        rm -rf "$STAGE_DIR" "${BACKUP_ARCHIVE}.tmp.$$"
        umask 022
        echo "${C_RED}[X] Ошибка создания архива резервной копии!${C_RES}"
        return 1
    fi
    rm -rf "$STAGE_DIR"
    chmod 600 "${BACKUP_ARCHIVE}.tmp.$$" 2>/dev/null || true
    mv -f "${BACKUP_ARCHIVE}.tmp.$$" "$BACKUP_ARCHIVE"
    chmod 600 "$BACKUP_ARCHIVE" 2>/dev/null || true
    umask 022

    if [ -d "${STORAGE_BACKUPS:-/srv/storage/Backups}" ]; then
        cp -f "$BACKUP_ARCHIVE" "${STORAGE_BACKUPS}/gateway_backup_$(date '+%Y%m%d_%H%M').tar.gz" 2>/dev/null || true
        cp -f "$BACKUP_ARCHIVE" "${STORAGE_BACKUPS}/gateway_backup_latest.tar.gz" 2>/dev/null || true
        ls -1t "${STORAGE_BACKUPS}"/gateway_backup_2*.tar.gz 2>/dev/null | awk 'NR>5' | xargs rm -f 2>/dev/null || true
    fi
    B_SIZE=$(du -sh "$BACKUP_ARCHIVE" 2>/dev/null | awk '{print $1}' || echo "н/д")
    echo "${C_GRN}[✓] Единый архив бэкапа успешно создан: ${BACKUP_ARCHIVE} (размер: ${B_SIZE})${C_RES}"
    return 0
}

restore_unified_backup() {
    if [ ! -f "$BACKUP_ARCHIVE" ]; then
        echo "${C_RED}[X] Файл бэкапа ${BACKUP_ARCHIVE} не найден!${C_RES}"
        return 1
    fi
    if ! tar -tzf "$BACKUP_ARCHIVE" >/dev/null 2>&1; then
        echo "${C_RED}[X] Ошибка: Архив ${BACKUP_ARCHIVE} поврежден!${C_RES}"
        return 1
    fi

    echo "${C_CYN}[*] Восстановление конфигурации шлюза и сервисов Homelab из ${BACKUP_ARCHIVE}...${C_RES}"
    service_ctl sing-box stop
    service_ctl adguardhome stop
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            [ "$M_EN" = "yes" ] && [ -n "$M_SVC" ] && service_ctl "$M_SVC" stop || true
        done < "$HOMELAB_STATE"
    fi
    rm -f /etc/sing-box/cache.db 2>/dev/null || true

    tar -xzf "$BACKUP_ARCHIVE" -C / 2>/dev/null || true

    # Восстановление консистентных SQLite-дампов поверх распакованных баз
    STAGE_RESTORE="/var/lib/gateway_backup_stage/sqlite_dumps"
    if [ -d "$STAGE_RESTORE" ]; then
        if [ -f "${STAGE_RESTORE}/vaultwarden.sqlite3" ]; then
            rm -f /var/lib/vaultwarden/db.sqlite3-wal /var/lib/vaultwarden/db.sqlite3-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/vaultwarden.sqlite3" /var/lib/vaultwarden/db.sqlite3 2>/dev/null || true
        fi
        if [ -f "${STAGE_RESTORE}/forgejo.sqlite3" ]; then
            rm -f /var/lib/forgejo/data/forgejo.db-wal /var/lib/forgejo/data/forgejo.db-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/forgejo.sqlite3" /var/lib/forgejo/data/forgejo.db 2>/dev/null || true
        fi
        if [ -f "${STAGE_RESTORE}/navidrome.sqlite3" ]; then
            rm -f /var/lib/navidrome/navidrome.db-wal /var/lib/navidrome/navidrome.db-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/navidrome.sqlite3" /var/lib/navidrome/navidrome.db 2>/dev/null || true
        fi
        if [ -f "${STAGE_RESTORE}/jellyfin.sqlite3" ]; then
            rm -f /var/lib/jellyfin/data/jellyfin.db-wal /var/lib/jellyfin/data/jellyfin.db-shm 2>/dev/null || true
            cp -f "${STAGE_RESTORE}/jellyfin.sqlite3" /var/lib/jellyfin/data/jellyfin.db 2>/dev/null || true
        fi
        rm -rf "/var/lib/gateway_backup_stage" 2>/dev/null || true
    fi

    chmod 600 "$SB_CONF" "$SB_ENV" "$HOMELAB_ENV" "$AGH_CONF" 2>/dev/null || true
    umask 022

    load_gateway_env
    sync_all_homelab_permissions >/dev/null 2>&1 || true
    sync_user_domain_rulesets
    sync_dns_firewall "yes" "keep"
    service_ctl sing-box start || true
    service_ctl adguardhome start || true

    # Перезапуск активных модулей Homelab после восстановления
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN M_SVC _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            if [ "$M_EN" = "yes" ] && [ -x "/etc/init.d/${M_SVC}" ]; then
                service_ctl "$M_SVC" enable
                service_ctl "$M_SVC" restart || true
            fi
        done < "$HOMELAB_STATE"
    fi
    build_pki_portal
    echo "${C_GRN}[✓] Система (Шлюз + Homelab + БД SQLite + локальный CA Caddy) успешно восстановлена!${C_RES}"
    return 0
}


# ==============================================================================
# Диагностика Homelab, Мастер установки, Меню Homelab (Пункт 13) и Главное меню
# ==============================================================================

# Сводная таблица всех модулей Homelab (реальный статус демона OpenRC, порт и домен)
