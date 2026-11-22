#!/bin/sh
_read_ram_metric() {
    awk -v mode="$1" '
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
            if (mode == "pct") printf "%d", (used * 100) / t
            else printf "%d", used / 1024
        }
    ' /proc/meminfo 2>/dev/null || echo "0"
    return 0
}

get_ram_usage_pct() { _read_ram_metric pct; }

get_ram_used_mb() { _read_ram_metric mb; }

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
    if [ -d "$GATEWAY_LOCK_DIR" ]; then
        if [ -f "${GATEWAY_LOCK_DIR}/pid" ]; then
            LCK_P=$(awk '{print $1}' "${GATEWAY_LOCK_DIR}/pid" 2>/dev/null || true)
            case "$LCK_P" in ''|*[!0-9]*) LCK_P="" ;; esac
            if [ -n "$LCK_P" ] && ! kill -0 "$LCK_P" 2>/dev/null; then
                rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
            fi
        elif [ -n "$(find "$GATEWAY_LOCK_DIR" -maxdepth 0 -mmin +1 2>/dev/null || true)" ]; then
            rm -rf "$GATEWAY_LOCK_DIR" 2>/dev/null || true
        fi
    fi

    # 2. Восстановление оборванных/нулевых обязательных конфигов из STATE_BAK_DIR (только для активного ядра)
    RECOVERED_ANY="no"
    if [ -d "$STATE_BAK_DIR" ]; then
        _act_core_m="singbox"
        if [ -f "$SB_ENV" ]; then
            _act_core_m=$(awk -F= '/^[[:space:]]*CORE_ENGINE=/{gsub(/["'\'' \r]/,"",$2); print $2; exit}' "$SB_ENV" 2>/dev/null || echo "singbox")
        fi
        case "$_act_core_m" in
            mihomo|clash|meta) _act_core_m="mihomo" ;;
            *) _act_core_m="singbox" ;;
        esac

        if [ "$_act_core_m" = "mihomo" ]; then
            _crit_list="${MIHOMO_CONF}:config.yaml"
        else
            _crit_list="${SB_CONF}:config.json"
        fi
        _crit_list="${_crit_list} ${SB_ENV}:gateway.env"
        is_openwrt 2>/dev/null || _crit_list="${_crit_list} ${HOMELAB_ENV}:homelab.env"
        _crit_list="${_crit_list} ${CUSTOM_NODES_FILE}:my_nodes.yaml ${WARP_NODES_FILE}:warp_nodes.json ${USER_DIRECT_FILE}:user_direct_domains.list"

        for CRIT_F in $_crit_list; do
            DEST_P="${CRIT_F%:*}"
            BAK_N="${CRIT_F#*:}"
            if [ ! -s "$DEST_P" ] && [ -s "${STATE_BAK_DIR}/${BAK_N}" ]; then
                mkdir -p "$(dirname "$DEST_P")" 2>/dev/null || true
                cp -f "${STATE_BAK_DIR}/${BAK_N}" "$DEST_P" 2>/dev/null || true
                RECOVERED_ANY="yes"
            fi
        done
        if [ ! -e "$USER_PROXY_FILE" ] && [ -s "${STATE_BAK_DIR}/user_proxy_domains.list" ]; then
            mkdir -p "$(dirname "$USER_PROXY_FILE")" 2>/dev/null || true
            cp -f "${STATE_BAK_DIR}/user_proxy_domains.list" "$USER_PROXY_FILE" 2>/dev/null || true
            RECOVERED_ANY="yes"
        fi
        if [ "$_act_core_m" = "singbox" ]; then
            if [ -f "$SB_CONF" ] && [ -x /usr/bin/sing-box ] && ! check_singbox_config; then
                if [ -s "${STATE_BAK_DIR}/config.json" ]; then
                    cp -f "${STATE_BAK_DIR}/config.json" "$SB_CONF" 2>/dev/null || true
                    RECOVERED_ANY="yes"
                fi
            fi
        else
            if [ -f "$MIHOMO_CONF" ] && [ -x /usr/bin/mihomo ] && ! check_mihomo_config; then
                if [ -s "${STATE_BAK_DIR}/config.yaml" ]; then
                    cp -f "${STATE_BAK_DIR}/config.yaml" "$MIHOMO_CONF" 2>/dev/null || true
                    RECOVERED_ANY="yes"
                fi
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
            /var/lib/forgejo/data/forgejo.db; do
            if [ -f "${DB_FILE}-wal" ] && [ -f "$DB_FILE" ]; then
                sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
            fi
        done
    fi
    return 0
}
