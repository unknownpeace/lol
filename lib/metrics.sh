get_ram_usage_pct() {
    awk '
        /^MemTotal:/ { t=$2 }
        /^MemAvailable:/ { a=$2 }
        /^MemFree:/ { f=$2 }
        /^Buffers:/ { b=$2 }
        /^Cached:/ { c=$2 }
        END {
            if (t <= 0) { print 0; exit }
            avail = (a > 0) ? a : (f + b + c)
            used = t - avail
            if (used < 0) used = 0
            printf "%d", (used * 100) / t
        }
    ' /proc/meminfo 2>/dev/null || echo "0"
    return 0
}

get_ram_used_mb() {
    awk '
        /^MemTotal:/ { t=$2 }
        /^MemAvailable:/ { a=$2 }
        /^MemFree:/ { f=$2 }
        /^Buffers:/ { b=$2 }
        /^Cached:/ { c=$2 }
        END {
            avail = (a > 0) ? a : (f + b + c)
            used = t - avail
            if (used < 0) used = 0
            printf "%d", used / 1024
        }
    ' /proc/meminfo 2>/dev/null || echo "0"
    return 0
}

get_disk_usage_pct() {
    TARGET_MP="${1:-${STORAGE_ROOT:-/srv/storage}}"
    [ -d "$TARGET_MP" ] || TARGET_MP="/"
    df -P "$TARGET_MP" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}' || echo "0"
    return 0
}

# Проверка: был ли зафиксирован аварийный сброс питания или пустой/оборванный конфиг
check_and_recover_power_loss_state() {
    mkdir -p "$SB_DIR" "$HOMELAB_DIR" 2>/dev/null || true

    # 1. Очистка протухших блокировок, сокетов и PID-файлов после жесткого ребута
    if [ -f "${GATEWAY_LOCK_DIR}/pid" ]; then
        LCK_P=$(awk '{print $1}' "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true)
        if [ -n "$LCK_P" ] && ! kill -0 "$LCK_P" 2>/dev/null; then
            rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
        fi
    fi

    # 2. Восстановление оборванных/нулевых конфигов из персистентного снапшота STATE_BAK_DIR (/etc/sing-box/.last_good_state)
    RECOVERED_ANY="no"
    if [ -d "$STATE_BAK_DIR" ]; then
        for CRIT_F in \
            "${SB_CONF}:config.json" \
            "${SB_ENV}:gateway.env" \
            "${HOMELAB_ENV}:homelab.env" \
            "${CUSTOM_NODES_FILE}:my_nodes.yaml" \
            "${WARP_NODES_FILE}:warp_nodes.json" \
            "${USER_DIRECT_FILE}:user_direct_domains.list" \
            "${USER_PROXY_FILE}:user_proxy_domains.list"; do
            DEST_P="${CRIT_F%:*}"
            BAK_N="${CRIT_F#*:}"
            if [ ! -s "$DEST_P" ] && [ -s "${STATE_BAK_DIR}/${BAK_N}" ]; then
                cp -f "${STATE_BAK_DIR}/${BAK_N}" "$DEST_P" 2>/dev/null || true
                RECOVERED_ANY="yes"
            fi
        done
        if [ -f "$SB_CONF" ] && [ -x /usr/bin/sing-box ] && ! check_singbox_config; then
            if [ -s "${STATE_BAK_DIR}/config.json" ]; then
                cp -f "${STATE_BAK_DIR}/config.json" "$SB_CONF" 2>/dev/null || true
                RECOVERED_ANY="yes"
            fi
        fi
    fi

    if [ "$RECOVERED_ANY" = "yes" ]; then
        date '+%Y-%m-%d %H:%M:%S' > "$POWER_LOSS_FLAG" 2>/dev/null || true
        sync
    fi

    # 3. Автоматическая проверка целостности и WAL-checkpoint баз SQLite после грязного выключения
    if command -v sqlite3 >/dev/null 2>&1; then
        for DB_FILE in \
            /var/lib/vaultwarden/db.sqlite3 \
            /var/lib/forgejo/data/forgejo.db \
            /var/lib/navidrome/navidrome.db \
            /var/lib/jellyfin/data/jellyfin.db; do
            if [ -f "${DB_FILE}-wal" ] && [ -f "$DB_FILE" ]; then
                sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
            fi
        done
    fi
    return 0
}

# Универсальный парсер AdGuardHome.yaml (извлечение логина или атомарное обновление секций)
