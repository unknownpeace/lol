install_module_torrent() {
    echo "${C_CYN}[*] Установка модуля qBittorrent-nox + Hardlink Media Pipeline...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add qbittorrent-nox qbittorrent-nox-openrc; then
        if ! apk add qbittorrent-nox; then
            echo "${C_RED}[X] Не удалось установить пакет qbittorrent-nox!${C_RES}"
            return 1
        fi
    fi

    if ! id qbittorrent >/dev/null 2>&1; then
        addgroup -S qbittorrent 2>/dev/null || true
        adduser -S -D -H -h /var/lib/qbittorrent -s /sbin/nologin -G qbittorrent qbittorrent 2>/dev/null || true
    fi

    init_homelab_storage
    addgroup qbittorrent "$MEDIA_GROUP" 2>/dev/null || true

    # Генерация хука безопасного импорта завершенных торрентов через жесткие ссылки (hardlinks cp -al)
    mkdir -p "$HOMELAB_LIB_DIR"
    chmod 755 "$HOMELAB_LIB_DIR" 2>/dev/null || true
    cat << HOOK_EOF > "$TORRENT_HOOK"
#!/bin/sh
# Авто-импорт завершенных раздач в медиатеку Jellyfin / Navidrome без остановки сидинга
umask 0002
CAT_NAME="\$(printf "%s" "\${1:-}" | tr 'A-Z' 'a-z')"
CONTENT_PATH="\${2:-}"
[ -z "\$CONTENT_PATH" ] || [ ! -e "\$CONTENT_PATH" ] && exit 0

case "\$CAT_NAME" in
    music|audio|музыка)
        DEST_DIR="${STORAGE_MUSIC}"
        ;;
    movies|movie|films|фильмы)
        DEST_DIR="${STORAGE_VIDEOS_MOVIES}"
        ;;
    series|tv|shows|сериалы)
        DEST_DIR="${STORAGE_VIDEOS_SERIES}"
        ;;
    video|videos|видео)
        DEST_DIR="${STORAGE_VIDEOS}"
        ;;
    *)
        exit 0
        ;;
esac

mkdir -p "\$DEST_DIR"
BASE_NAME="\$(basename "\$CONTENT_PATH")"
TARGET_PATH="\${DEST_DIR}/\${BASE_NAME}"

# Мгновенное создание жестких ссылок (0 лишних байт на одной ФС, раздача продолжается!)
cp -al "\$CONTENT_PATH" "\$DEST_DIR/" 2>/dev/null || cp -rf "\$CONTENT_PATH" "\$DEST_DIR/" 2>/dev/null || true
if [ -e "\$TARGET_PATH" ]; then
    chgrp -R "${MEDIA_GROUP}" "\$TARGET_PATH" 2>/dev/null || true
    find "\$TARGET_PATH" -type d -exec chmod 2775 {} + 2>/dev/null || true
    find "\$TARGET_PATH" -type f -exec chmod 0664 {} + 2>/dev/null || true
fi
exit 0
HOOK_EOF
    chmod 755 "$TORRENT_HOOK"

    QB_HOME="/var/lib/qbittorrent"
    QB_CONF_DIR="${QB_HOME}/.config/qBittorrent"
    mkdir -p "$QB_CONF_DIR"

    cat << QB_CATS > "${QB_CONF_DIR}/categories.json"
{
    "music": {
        "save_path": "${STORAGE_DL_MUSIC}"
    },
    "videos": {
        "save_path": "${STORAGE_DL_VIDEOS}"
    },
    "movies": {
        "save_path": "${STORAGE_DL_VIDEOS}"
    },
    "series": {
        "save_path": "${STORAGE_DL_VIDEOS}"
    }
}
QB_CATS

    load_gateway_env
    QB_USER="${SMB_USER:-${AGH_USER:-admin}}"
    QB_PBKDF2=""
    if command -v python3 >/dev/null 2>&1; then
        QB_PBKDF2=$(python3 - "${ADMIN_PASS:-admin}" << 'PY_QB_HASH' 2>/dev/null || true
import hashlib, base64, os, sys
pw = sys.argv[1].encode("utf-8")
salt = os.urandom(16)
dk = hashlib.pbkdf2_hmac("sha512", pw, salt, 100000, 64)
print(f"@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(dk).decode()})")
PY_QB_HASH
)
    fi

    cat << QB_CONF > "${QB_CONF_DIR}/qBittorrent.conf"
[AutoRun]
enabled=true
program="${TORRENT_HOOK} \"%L\" \"%F\" \"%N\""

[BitTorrent]
Session\DefaultSavePath=${STORAGE_DL_OTHER}
Session\Port=${PORT_TORRENT_PEER}
Session\TempPath=${STORAGE_INC_TORRENTS}
Session\TempPathEnabled=true

[LegalNotice]
Accepted=true

[Preferences]
Downloads\SavePath=${STORAGE_DL_OTHER}
Downloads\TempPath=${STORAGE_INC_TORRENTS}
Downloads\TempPathEnabled=true
WebUI\Address=127.0.0.1
WebUI\Port=${PORT_TORRENT_WEB}
WebUI\Username=${QB_USER}
WebUI\Password_PBKDF2="${QB_PBKDF2}"
WebUI\AuthSubnetWhitelist=127.0.0.1/32, ::1/128
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\CSRFProtection=false
WebUI\HostHeaderValidation=false
WebUI\LocalHostAuth=false
QB_CONF

    chown -R qbittorrent:"$MEDIA_GROUP" "$QB_HOME" 2>/dev/null || true
    chmod 750 "$QB_HOME" 2>/dev/null || true

    cat << QB_CONF_D > /etc/conf.d/qbittorrent-nox
WEBUI_PORT=${PORT_TORRENT_WEB}
command_user="qbittorrent:${MEDIA_GROUP}"
directory="/var/lib/qbittorrent"
umask="0002"
rc_nice="10"
rc_oom_score_adj="500"
QB_CONF_D

    cat << QB_INIT > /etc/init.d/qbittorrent-nox
#!/sbin/openrc-run
name="qbittorrent-nox"
description="qBittorrent-nox headless BitTorrent client"
supervisor="supervise-daemon"
command="/usr/bin/qbittorrent-nox"
command_args="--webui-port=\${WEBUI_PORT:-${PORT_TORRENT_WEB}}"
command_user="\${command_user:-qbittorrent:${MEDIA_GROUP}}"
directory="/var/lib/qbittorrent"
umask="0002"
output_log="/var/log/qbittorrent-nox.log"
error_log="/var/log/qbittorrent-nox.log"
rc_ulimit="-n 50000"
rc_nice="10"
rc_oom_score_adj="500"
export HOME="/var/lib/qbittorrent"
export XDG_CONFIG_HOME="/var/lib/qbittorrent/.config"
export XDG_DATA_HOME="/var/lib/qbittorrent/.local/share"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath -d -m 0750 -o qbittorrent:${MEDIA_GROUP} /var/lib/qbittorrent
    checkpath -f -m 0640 -o qbittorrent:${MEDIA_GROUP} /var/log/qbittorrent-nox.log
}
QB_INIT
    chmod +x /etc/init.d/qbittorrent-nox

    repair_storage_permissions
    service_ctl qbittorrent-nox enable
    if ! service_ctl qbittorrent-nox restart; then
        echo "${C_RED}[X] Служба qbittorrent-nox не смогла запуститься!${C_RES}"
        return 1
    fi
    sync_dns_firewall "yes" "keep"
    register_caddy_site "torrent" "$DOM_TORRENT" "$PORT_TORRENT_WEB" "yes"
    set_module_state "torrent" "yes"

    echo "${C_GRN}[✓] qBittorrent-nox запущен: https://${DOM_TORRENT} (защищен BasicAuth паролем шлюза)${C_RES}"
    echo "    Категории 'music', 'videos', 'movies', 'series' автоматически линкуются в медиатеку без потери раздачи!"
    return 0
}

remove_module_torrent() {
    service_ctl qbittorrent-nox stop
    service_ctl qbittorrent-nox disable
    remove_caddy_site "torrent"
    set_module_state "torrent" "no"
    echo "${C_GRN}[✓] Модуль qBittorrent-nox отключен (файлы в ${STORAGE_DOWNLOADS} сохранены).${C_RES}"
    return 0
}

# Синхронизация прав доступа сервисов Homelab и единого хранилища /srv/storage
