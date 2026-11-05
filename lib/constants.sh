#!/bin/sh
set -e

# ==============================================================================
# Глобальные пути и переменные (Alpine Linux Homelab Edition)
# Сетевой шлюз (Sing-Box Extended + AdGuard Home) + Модульный Homelab стек
# ==============================================================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# Автоматическое определение GATEWAY_DIR и самораспаковка автономного Install.sh
if [ -z "${GATEWAY_DIR:-}" ]; then
    TARGET_EXEC="${BASH_SOURCE:-$0}"
    case "$TARGET_EXEC" in
        */*) ;;
        *)
            CMD_LOC=$(command -v "$TARGET_EXEC" 2>/dev/null || true)
            [ -n "$CMD_LOC" ] && TARGET_EXEC="$CMD_LOC"
            ;;
    esac
    REAL_EXEC=$(readlink -f "$TARGET_EXEC" 2>/dev/null || true)
    [ -z "$REAL_EXEC" ] && REAL_EXEC="$TARGET_EXEC"
    if [ -f "$REAL_EXEC" ]; then
        GATEWAY_DIR="$(cd -P "$(dirname "$REAL_EXEC")" && pwd)"
    else
        GATEWAY_DIR="/opt/gateway"
    fi
    export GATEWAY_DIR
fi

if [ -d "/usr/bin" ] && [ -w "/usr/bin" ]; then
    mkdir -p "/opt/gateway" 2>/dev/null || true
    CUR_RUNNING="${BASH_SOURCE:-$0}"
    if [ -f "$CUR_RUNNING" ] && [ "$(readlink -f "$CUR_RUNNING" 2>/dev/null)" != "/opt/gateway/Install.sh" ] && \
       [ "$(readlink -f "$CUR_RUNNING" 2>/dev/null)" != "/opt/gateway/gateway.sh" ] && \
       [ "$CUR_RUNNING" != "/usr/bin/gateway" ] && [ "$CUR_RUNNING" != "/usr/bin/gw" ]; then
        case "$CUR_RUNNING" in
            *Install.sh)
                cp -f "$CUR_RUNNING" /opt/gateway/Install.sh 2>/dev/null || true
                chmod +x /opt/gateway/Install.sh 2>/dev/null || true
                ;;
        esac
    fi
    if [ -f "/opt/gateway/Install.sh" ] && [ ! -f "/opt/gateway/gateway.sh" ]; then
        ln -sf /opt/gateway/Install.sh /usr/bin/gateway 2>/dev/null || true
        ln -sf /opt/gateway/Install.sh /usr/bin/gw 2>/dev/null || true
    fi
    if [ -d "/etc/profile.d" ] && [ ! -f "/etc/profile.d/00-gateway-motd.sh" ]; then
        cat << 'MOTD_EOF' > /etc/profile.d/00-gateway-motd.sh
if [ -t 1 ] && [ -x /usr/bin/gateway ]; then
    /usr/bin/gateway motd
fi
MOTD_EOF
        chmod 644 /etc/profile.d/00-gateway-motd.sh 2>/dev/null || true
    fi
fi

SB_DIR="/etc/sing-box"
SB_CONF="${SB_DIR}/config.json"
SB_ENV="${SB_DIR}/gateway.env"
SB_RULES_DIR="${SB_DIR}/rule_sets"
SB_PROVIDERS_DIR="${SB_DIR}/providers"
CUSTOM_NODES_FILE="${SB_PROVIDERS_DIR}/my_nodes.yaml"
WARP_NODES_FILE="${SB_PROVIDERS_DIR}/warp_nodes.json"
USER_DIRECT_FILE="${SB_RULES_DIR}/user_direct_domains.list"
USER_PROXY_FILE="${SB_RULES_DIR}/user_proxy_domains.list"
USER_DIRECT_JSON="${SB_RULES_DIR}/user_direct_domains.json"
USER_PROXY_JSON="${SB_RULES_DIR}/user_proxy_domains.json"
USER_BYPASS_IPS="${SB_DIR}/bypass_devices.conf"
USER_FORCE_PROXY_IPS="${SB_DIR}/force_proxy_devices.conf"
BACKUP_ARCHIVE="/root/gateway_backup.tar.gz"
STATE_BAK_DIR="${SB_DIR}/.last_good_state"
POWER_LOSS_FLAG="${SB_DIR}/.power_loss_recovered"
STORAGE_ALERT_CACHE="/tmp/gateway_storage_alert.ts"
CRON_FILE="/etc/crontabs/root"
AUTOUPDATE_LOG="/var/log/gateway_autoupdate.log"
SB_LOG_FILE="/var/log/sing-box.log"
VER_CACHE_FILE="/tmp/gateway_ver.cache"
LAN_SCAN_CACHE="/tmp/gateway_lan_scan.cache"
GATEWAY_LOCK_DIR="/tmp/gateway_op.lock"
UI_VER_FILE="${SB_DIR}/ui/.ui_version"
UI_REPO="Zephyruso/zashboard"
UI_ZIP_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.zip"
UI_TAR_URL="https://github.com/Zephyruso/zashboard/archive/refs/heads/gh-pages.tar.gz"
AGH_CONF="/etc/AdGuardHome/AdGuardHome.yaml"
ALPINE_NFT_CONF="/etc/nftables.nft"
ALPINE_DHCP_CONF="/etc/dnsmasq.d/gateway-dhcp.conf"

# Глобальные пути и переменные подсистемы Homelab
HOMELAB_DIR="${SB_DIR}/homelab"
HOMELAB_ENV="${SB_DIR}/homelab.env"
HOMELAB_STATE="${HOMELAB_DIR}/modules.state"
HOMELAB_LIB_DIR="/usr/lib/gateway"
TORRENT_HOOK="${HOMELAB_LIB_DIR}/torrent-import-hook.sh"
YTDLP_WEB_SCRIPT="${HOMELAB_LIB_DIR}/ytdlp-webui.py"
STORAGE_ROOT="/srv/storage"
STORAGE_MUSIC="${STORAGE_ROOT}/Music"
STORAGE_VIDEOS="${STORAGE_ROOT}/Videos"
STORAGE_VIDEOS_MOVIES="${STORAGE_VIDEOS}/Movies"
STORAGE_VIDEOS_SERIES="${STORAGE_VIDEOS}/Series"
STORAGE_DOWNLOADS="${STORAGE_ROOT}/Downloads"
STORAGE_DL_MUSIC="${STORAGE_DOWNLOADS}/Music"
STORAGE_DL_VIDEOS="${STORAGE_DOWNLOADS}/Videos"
STORAGE_DL_OTHER="${STORAGE_DOWNLOADS}/Other"
STORAGE_INCOMPLETE="${STORAGE_DOWNLOADS}/Incomplete"
STORAGE_INC_TORRENTS="${STORAGE_INCOMPLETE}/torrents"
STORAGE_INC_YTDLP="${STORAGE_INCOMPLETE}/ytdlp"
STORAGE_BACKUPS="${STORAGE_ROOT}/Backups"
STORAGE_REPOS="${STORAGE_ROOT}/Git-Repos"
STORAGE_CODE="${STORAGE_ROOT}/Workspace"
STORAGE_PERSONAL="${STORAGE_ROOT}/Personal"
LUKS_KEYFILE="/etc/sing-box/homelab/storage.luks.key"
LUKS_MAPPER_NAME="homelab_storage"
EXT_DISK_SCAN_CACHE="/tmp/gateway_disks.cache"
PKI_PORTAL_DIR="/srv/homelab/pki-portal"
CADDY_CONF="/etc/caddy/Caddyfile"
CADDY_CONFD="/etc/caddy/conf.d"
CADDY_ROOT_CERT="/var/lib/caddy/caddy/pki/authorities/local/root.crt"
SSL_CERTS_DIR="/etc/ssl/caddy"
SSL_FULLCHAIN_FILE="${SSL_CERTS_DIR}/fullchain.pem"
SSL_KEY_FILE="${SSL_CERTS_DIR}/key.pem"
MEDIA_GROUP="media"
MEDIA_GID="990"
SMB_USER="homelab"
SMB_PASS=""
JELLYFIN_UNIFIED_MEDIA="yes"
HOMELAB_DOMAIN_SUFFIX="lan"
EXT_STORAGE_EXPECTED="no"
EXT_STORAGE_UUID=""
EXT_STORAGE_LUKS_UUID=""
EXT_STORAGE_FSTYPE="ext4"

# Порты локальных бэкендов Homelab (слушают строго 127.0.0.1)
PORT_VAULTWARDEN="8222"
PORT_FORGEJO="3001"
PORT_CODE="8443"
PORT_NAVIDROME="4533"
PORT_JELLYFIN="8096"
PORT_YTDLP="8081"
PORT_TORRENT_WEB="8080"
PORT_TORRENT_PEER="51413"

# Домены Homelab и панелей шлюза (Caddy HTTPS + AdGuard Home DNS Rewrites)
DOM_VAULTWARDEN="vaultwarden.lan"
DOM_FORGEJO="forgejo.lan"
DOM_CODE="code.lan"
DOM_NAVIDROME="music.lan"
DOM_JELLYFIN="jellyfin.lan"
DOM_YTDLP="downloads.lan"
DOM_TORRENT="torrents.lan"
DOM_CA="ca.lan"
DOM_ADGUARD="adguard.lan"
DOM_ZASHBOARD="zashboard.lan"
DOM_SINGBOX="singbox.lan"

SUB_FILTER_STRICT="(?i)(剩余|过期|到期|官网|流量|套餐|重置|expire|traffic|website|official|срок|осталось|трафик|истекает|подписк|тариф|торрент|запрещ|лимит|инфо|новост|поддержк|канал|бот|t[.]me/|ℹ️|⛔|🚫|⚠️|📅|🇷🇺|Россия|Russia|Москва|Moscow|СПб|Белые списки|WhiteList)"
SUB_FILTER_WHITELIST="(?i)(剩余|过期|到期|官网|流量|套餐|重置|expire|traffic|website|official|срок|осталось|трафик|истекает|подписк|тариф|торрент|запрещ|лимит|инфо|новост|поддержк|канал|бот|t[.]me/|ℹ️|⛔|🚫|⚠️|📅)"
ALLOW_RU_NODES="no"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
GH_PROXY=""
LATEST_SB_TAG=""
LATEST_AGH_TAG=""
LATEST_UI_TAG=""
OS_TYPE="alpine"
OS_NAME="Alpine Linux"
SB_ARCH="amd64"
AGH_ARCH="amd64"
ARCH_RAW="x86_64"
SB_GOMEMLIMIT="200MiB"
AGH_GOMEMLIMIT="100MiB"
SYS_CONNTRACK_MAX="65536"
SYS_BUF_MAX="16777216"
TOTAL_RAM_MB="512"

# Инициализация цветовой палитры терминала (ANSI 256-color Neon с fallback на 16 цветов и отключением в cron)
