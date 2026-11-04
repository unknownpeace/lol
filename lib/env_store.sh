clean_clipboard_line() {
    printf "%s" "${1:-}" | tr -d '\r\n\000\007\010\013\014\033' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    return 0
}

escape_single_quotes() {
    printf "%s" "$1" | tr -d '\r\n\000' | sed "s/'/'\\\\''/g"
    return 0
}

# Чтение и сохранение параметров сетевого шлюза (gateway.env) и Homelab (homelab.env — единый источник истины)
load_gateway_env() {
    if [ -f "$SB_ENV" ]; then
        sed -i 's/\r$//' "$SB_ENV" 2>/dev/null || true
        # shellcheck disable=SC1090
        . "$SB_ENV" 2>/dev/null || true
    fi
    # Миграция устаревшего дубля /etc/sing-box/homelab/homelab.env в единый канонический /etc/sing-box/homelab.env
    if [ ! -f "$HOMELAB_ENV" ] && [ -f "${HOMELAB_DIR}/homelab.env" ] && [ ! -L "${HOMELAB_DIR}/homelab.env" ]; then
        mv -f "${HOMELAB_DIR}/homelab.env" "$HOMELAB_ENV" 2>/dev/null || cp -f "${HOMELAB_DIR}/homelab.env" "$HOMELAB_ENV" 2>/dev/null || true
        ln -sf "$HOMELAB_ENV" "${HOMELAB_DIR}/homelab.env" 2>/dev/null || true
    fi
    if [ -f "$HOMELAB_ENV" ]; then
        sed -i 's/\r$//' "$HOMELAB_ENV" 2>/dev/null || true
        # shellcheck disable=SC1090
        . "$HOMELAB_ENV" 2>/dev/null || true
    fi

    if [ -z "${GW_IP:-}" ] && [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        GW_IP=$(jq -r '.dns.servers[]? | select(.tag=="dns_local") | .server // empty' "$SB_CONF" 2>/dev/null | head -n 1)
    fi
    if [ -z "${ADMIN_PASS:-}" ] && [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        ADMIN_PASS=$(jq -r '.experimental.clash_api.secret // empty' "$SB_CONF" 2>/dev/null | head -n 1)
    fi
    if [ -z "${SUB_URL:-}" ] && [ -f "$SB_CONF" ] && command -v jq >/dev/null 2>&1; then
        SUB_URL=$(jq -r '[.providers[]? | select(.type=="remote") | .url] | join(" ")' "$SB_CONF" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    case "${SUB_URL:-}" in
        *http://* | *https://*) ;;
        *) SUB_URL="" ;;
    esac

    [ -z "${ALLOW_RU_NODES:-}" ] && ALLOW_RU_NODES="no"
    if [ -z "${GW_IP:-}" ]; then
        GW_IP=$(ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via") {print $(i+1); exit}}')
    fi
    [ -z "${GW_IP:-}" ] && GW_IP="192.168.1.1"
    if [ -z "${AGH_USER:-}" ]; then
        AGH_USER=$(get_agh_admin_user)
    fi
    [ -z "${SMB_USER:-}" ] && SMB_USER="${AGH_USER:-homelab}"
    [ -z "${SMB_PASS:-}" ] && SMB_PASS="${ADMIN_PASS:-}"
    [ -z "${STORAGE_ROOT:-}" ] && STORAGE_ROOT="/srv/storage"
    [ -z "${JELLYFIN_UNIFIED_MEDIA:-}" ] && JELLYFIN_UNIFIED_MEDIA="yes"
    [ -z "${EXT_STORAGE_EXPECTED:-}" ] && EXT_STORAGE_EXPECTED="no"
    [ -z "${EXT_STORAGE_UUID:-}" ] && EXT_STORAGE_UUID=""
    [ -z "${EXT_STORAGE_LUKS_UUID:-}" ] && EXT_STORAGE_LUKS_UUID=""
    [ -z "${EXT_STORAGE_FSTYPE:-}" ] && EXT_STORAGE_FSTYPE="ext4"
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
    return 0
}

save_gateway_env() {
    mkdir -p "$SB_DIR"
    chown root:root "$SB_DIR" 2>/dev/null || true
    chmod 700 "$SB_DIR" 2>/dev/null || true
    umask 077
    ESC_GW=$(escape_single_quotes "${GW_IP:-}")
    ESC_AGHU=$(escape_single_quotes "${AGH_USER:-admin}")
    ESC_PASS=$(escape_single_quotes "${ADMIN_PASS:-}")
    ESC_SUB=$(escape_single_quotes "${SUB_URL:-}")
    ESC_WLIC=$(escape_single_quotes "${WARP_LICENSE:-}")
    ESC_ARU=$(escape_single_quotes "${ALLOW_RU_NODES:-no}")
    ESC_TGB=$(escape_single_quotes "${TG_BOT_TOKEN:-}")
    ESC_TGC=$(escape_single_quotes "${TG_CHAT_ID:-}")
    atomic_write_file "$SB_ENV" 0600 "root:root" << ENV_EOF
GW_IP='${ESC_GW}'
AGH_USER='${ESC_AGHU}'
ADMIN_PASS='${ESC_PASS}'
SUB_URL='${ESC_SUB}'
WARP_LICENSE='${ESC_WLIC}'
ALLOW_RU_NODES='${ESC_ARU}'
TG_BOT_TOKEN='${ESC_TGB}'
TG_CHAT_ID='${ESC_TGC}'
ENV_EOF
    umask 022
    return 0
}

save_homelab_env() {
    mkdir -p "$SB_DIR" "$HOMELAB_DIR"
    chown root:root "$SB_DIR" "$HOMELAB_DIR" 2>/dev/null || true
    chmod 700 "$SB_DIR" 2>/dev/null || true
    chmod 750 "$HOMELAB_DIR" 2>/dev/null || true
    umask 077
    ESC_SMBU=$(escape_single_quotes "${SMB_USER:-${AGH_USER:-homelab}}")
    ESC_SMBP=$(escape_single_quotes "${SMB_PASS:-${ADMIN_PASS:-}}")
    ESC_SROOT=$(escape_single_quotes "${STORAGE_ROOT:-/srv/storage}")
    ESC_JFUNI=$(escape_single_quotes "${JELLYFIN_UNIFIED_MEDIA:-yes}")
    ESC_EXP=$(escape_single_quotes "${EXT_STORAGE_EXPECTED:-no}")
    ESC_EUUID=$(escape_single_quotes "${EXT_STORAGE_UUID:-}")
    ESC_LUUID=$(escape_single_quotes "${EXT_STORAGE_LUKS_UUID:-}")
    ESC_EFST=$(escape_single_quotes "${EXT_STORAGE_FSTYPE:-ext4}")
    atomic_write_file "$HOMELAB_ENV" 0600 "root:root" << HL_ENV_EOF
SMB_USER='${ESC_SMBU}'
SMB_PASS='${ESC_SMBP}'
STORAGE_ROOT='${ESC_SROOT}'
JELLYFIN_UNIFIED_MEDIA='${ESC_JFUNI}'
EXT_STORAGE_EXPECTED='${ESC_EXP}'
EXT_STORAGE_UUID='${ESC_EUUID}'
EXT_STORAGE_LUKS_UUID='${ESC_LUUID}'
EXT_STORAGE_FSTYPE='${ESC_EFST}'
HL_ENV_EOF
    # Единый источник истины: симлинк для обратной совместимости в ${HOMELAB_DIR}/homelab.env
    if [ "${HOMELAB_DIR}/homelab.env" != "$HOMELAB_ENV" ]; then
        rm -f "${HOMELAB_DIR}/homelab.env" 2>/dev/null || true
        ln -sf "$HOMELAB_ENV" "${HOMELAB_DIR}/homelab.env" 2>/dev/null || true
    fi
    umask 022
    return 0
}

# Умная очистка и нормализация домена (URL, @telegram, *.site.com, IDN кириллица -> punycode, защита от IP)
