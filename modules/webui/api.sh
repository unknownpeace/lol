#!/bin/sh
# ==============================================================================
# Единый POSIX sh JSON API бэкенд для Universal Sidecar Gateway & Homelab
# Используется как LuCI RPCD (OpenWrt), так и Alpine Web Dashboard (server.py)
# ==============================================================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[ "${1:-}" = "call" ] || exit 1
METHOD="${2:-}"
INPUT_JSON=$(cat 2>/dev/null || true)
[ -z "$INPUT_JSON" ] && INPUT_JSON="{}"

API_SCRIPT_DIR=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
GATEWAY_DIR=$(CDPATH='' cd -P "${API_SCRIPT_DIR}/../.." && pwd)
export GATEWAY_DIR

GATEWAY_NO_RUN=1
NO_COLOR=1
export GATEWAY_NO_RUN NO_COLOR

. "${GATEWAY_DIR}/gateway.sh" >/dev/null 2>&1 || {
    printf '{"ok":false,"error":"Не удалось загрузить модули %s"}\n' "${GATEWAY_DIR}"
    exit 0
}
set +e
detect_os >/dev/null 2>&1 || true
load_gateway_env >/dev/null 2>&1 || true

_strip_ansi() {
    awk '{ gsub(/\033\[[0-9;?]*[A-Za-z]/, ""); gsub(/\r/, ""); print }' 2>/dev/null || cat
}

_json_err() {
    jq -cn --arg e "$1" '{ok: false, error: $e}'
}

_jq_arg() {
    printf "%s" "$INPUT_JSON" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null || true
}

_is_safe_id() {
    case "${1:-}" in
        ""|*[!A-Za-z0-9_-]*) return 1 ;;
        *) return 0 ;;
    esac
}

_is_job_running() {
    _jid="$1"
    _pf="/tmp/gw_luci_job_${_jid}.pid"
    _rf="/tmp/gw_luci_job_${_jid}.rc"
    _sf="/tmp/gw_luci_job_${_jid}.starting"
    [ -f "$_rf" ] && return 1
    if [ -f "$_pf" ]; then
        _jpid=$(cat "$_pf" 2>/dev/null | tr -dc '0-9' || true)
        if [ -n "$_jpid" ] && kill -0 "$_jpid" 2>/dev/null; then
            return 0
        fi
    fi
    [ -f "$_sf" ] && return 0
    return 1
}

_mask_token() {
    _tok="${1:-}"
    _len=${#_tok}
    if [ "$_len" -eq 0 ]; then
        printf ""
    elif [ "$_len" -le 10 ]; then
        printf "****"
    else
        _head=$(printf "%s" "$_tok" | cut -c1-4)
        _tail=$(printf "%s" "$_tok" | cut -c$((_len - 3))-"$_len")
        printf "%s...%s" "$_head" "$_tail"
    fi
}

_read_sys_model() {
    _m=""
    if [ -r /tmp/sysinfo/model ]; then
        _m=$(tr -d '\r\n\0' < /tmp/sysinfo/model 2>/dev/null || true)
    elif [ -r /sys/devices/virtual/dmi/id/product_name ]; then
        _m=$(tr -d '\r\n\0' < /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)
    elif [ -r /proc/device-tree/model ]; then
        _m=$(tr -d '\r\n\0' < /proc/device-tree/model 2>/dev/null || true)
    fi
    [ -z "$_m" ] && _m=$(hostname -s 2>/dev/null || printf "%s" "${OS_NAME:-Linux}")
    printf "%s" "$_m"
}

_collect_alpine_ssl_json() {
    if is_openwrt 2>/dev/null; then
        printf 'null'
        return 0
    fi
    _cdy_en="false"
    is_module_enabled "caddy" && _cdy_en="true"
    _le_act="false"
    is_letsencrypt_ssl_active 2>/dev/null && _le_act="true"
    _exp=""
    _issuer=""
    _days=0
    if [ "$_le_act" = "true" ] && [ -s "${SSL_FULLCHAIN_FILE:-/etc/ssl/caddy/fullchain.pem}" ] && command -v openssl >/dev/null 2>&1; then
        _issuer=$(openssl x509 -in "$SSL_FULLCHAIN_FILE" -noout -issuer 2>/dev/null | sed 's/.*CN[[:space:]]*=[[:space:]]*//' | tr -d '\r\n' || true)
        _exp=$(openssl x509 -in "$SSL_FULLCHAIN_FILE" -noout -enddate 2>/dev/null | cut -d= -f2 | tr -d '\r\n' || true)
        if [ -n "$_exp" ]; then
            _clean_dt=$(printf "%s" "$_exp" | sed -E 's/  +/ 0/')
            _exp_s=$(date -D '%b %d %T %Y GMT' -d "$_clean_dt" +%s 2>/dev/null || date -d "$_exp" +%s 2>/dev/null || echo 0)
            _now_s=$(date +%s 2>/dev/null || echo 0)
            [ "${_exp_s:-0}" -gt "${_now_s:-0}" ] && _days=$(( (_exp_s - _now_s) / 86400 ))
        fi
    fi
    _duck_set="false"
    [ -n "${DUCKDNS_TOKEN:-}" ] && _duck_set="true"
    _duck_mask=$(_mask_token "${DUCKDNS_TOKEN:-}")
    jq -cn \
        --arg type "${SSL_TYPE:-local}" \
        --arg domain "${SSL_DOMAIN:-}" \
        --argjson le_active "$_le_act" \
        --argjson caddy_enabled "$_cdy_en" \
        --arg expiry "$_exp" \
        --arg issuer "$_issuer" \
        --argjson days_left "${_days:-0}" \
        --argjson duckdns_token_set "$_duck_set" \
        --arg duckdns_token_masked "$_duck_mask" \
        '{
            type: $type,
            domain: $domain,
            le_active: $le_active,
            caddy_enabled: $caddy_enabled,
            expiry: $expiry,
            issuer: $issuer,
            days_left: $days_left,
            duckdns_token_set: $duckdns_token_set,
            duckdns_token_masked: $duckdns_token_masked
        }'
}

_collect_alpine_homelab_json() {
    if is_openwrt 2>/dev/null; then
        printf '[]'
        return 0
    fi
    init_homelab_registry >/dev/null 2>&1 || true
    [ -f "$HOMELAB_STATE" ] || { printf '[]'; return 0; }
    _lip="$1"
    _cdy_on="no"
    is_module_enabled "caddy" && _cdy_on="yes"
    _le_on="no"
    is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ] && _le_on="yes"

    _hl_tmp="/tmp/gw_api_hl.$$"
    : > "$_hl_tmp"
    while IFS='|' read -r M_ID M_EN M_SVC M_PORT M_DOM M_USR M_TITLE <&3; do
        case "$M_ID" in ''|\#*) continue ;; esac
        _run="false"
        if [ -n "$M_SVC" ]; then
            if [ -d /run/openrc/started ]; then
                if [ -L "/run/openrc/started/${M_SVC}" ] && [ ! -e "/run/openrc/crashed/${M_SVC}" ]; then
                    _run="true"
                fi
            elif [ -x "/etc/init.d/${M_SVC}" ] && rc-service "$M_SVC" status </dev/null >/dev/null 2>&1; then
                _run="true"
            fi
        fi
        if [ "$_run" = "false" ] && [ "$M_ID" = "samba" ] && pgrep smbd >/dev/null 2>&1; then
            _run="true"
        elif [ "$_run" = "false" ] && [ "$M_ID" = "caddy" ] && pgrep caddy >/dev/null 2>&1; then
            _run="true"
        fi
        _url=""
        _smb=""
        if [ "$M_ID" = "caddy" ]; then
            if [ "$M_EN" = "yes" ]; then
                if [ "$_le_on" = "yes" ]; then
                    _url="https://ca.${SSL_DOMAIN}"
                else
                    _url="http://${DOM_CA:-ca.lan}"
                fi
            fi
        elif [ "$M_ID" = "samba" ]; then
            if [ "$M_EN" = "yes" ]; then
                _smb="\\\\${_lip}\\storage"
            fi
        elif [ "$M_EN" = "yes" ]; then
            _sub="${M_DOM%%.*}"
            if [ "$_cdy_on" = "yes" ]; then
                if [ "$_le_on" = "yes" ]; then
                    _url="https://${_sub}.${SSL_DOMAIN}"
                else
                    _url="https://${M_DOM}"
                fi
            else
                _url="http://${_lip}:${M_PORT}"
            fi
        fi
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$M_ID" "$M_EN" "$M_SVC" "$_run" "$M_PORT" "$M_DOM" "$_url" "$_smb" "$M_TITLE" >> "$_hl_tmp"
    done 3< "$HOMELAB_STATE"

    _hl_json=$(jq -Rn '
        [inputs | select(length > 0) | split("\t") | {
            id: .[0],
            enabled: (.[1] == "yes"),
            service: .[2],
            running: (.[3] == "true"),
            port: .[4],
            domain: .[5],
            url: .[6],
            smb_share: .[7],
            title: .[8]
        }]
    ' < "$_hl_tmp" 2>/dev/null || echo '[]')
    rm -f "$_hl_tmp" 2>/dev/null || true
    printf "%s" "$_hl_json"
}

_collect_alpine_storage_json() {
    if is_openwrt 2>/dev/null; then
        printf 'null'
        return 0
    fi
    _st_root="${STORAGE_ROOT:-/srv/storage}"
    mkdir -p "$_st_root" >/dev/null 2>&1 || true
    _st_exp="false"
    [ "${EXT_STORAGE_EXPECTED:-no}" = "yes" ] && _st_exp="true"
    _st_mnt="false"
    is_external_storage_mounted 2>/dev/null && _st_mnt="true"
    _st_luks="false"
    [ -b "/dev/mapper/${LUKS_MAPPER_NAME:-homelab_storage}" ] && _st_luks="true"
    _st_key="false"
    [ -s "${LUKS_KEYFILE:-/etc/sing-box/homelab/storage.luks.key}" ] && _st_key="true"
    _st_pct=$(get_disk_usage_pct "$_st_root")
    _df_line=$(df -Ph "$_st_root" 2>/dev/null | awk 'NR==2 {print $1 "\t" $2 "\t" $3 "\t" $6}' || true)
    _st_dev=$(printf "%s" "$_df_line" | awk -F'\t' '{print $1}')
    _st_tot=$(printf "%s" "$_df_line" | awk -F'\t' '{print $2}')
    _st_used=$(printf "%s" "$_df_line" | awk -F'\t' '{print $3}')
    _st_mp=$(printf "%s" "$_df_line" | awk -F'\t' '{print $4}')
    _st_fs=""
    if [ -n "$_st_mp" ]; then
        _st_fs=$(awk -v mp="$_st_mp" '$2 == mp {print $3; exit}' /proc/mounts 2>/dev/null || true)
    fi
    _st_badge=$(get_storage_disk_badge 2>/dev/null || true)
    _dirs_tmp="/tmp/gw_api_stdirs.$$"
    : > "$_dirs_tmp"
    for _dspec in \
        "Music|${STORAGE_MUSIC:-${_st_root}/Music}" \
        "Videos|${STORAGE_VIDEOS:-${_st_root}/Videos}" \
        "Downloads|${STORAGE_DOWNLOADS:-${_st_root}/Downloads}" \
        "Incomplete|${STORAGE_INCOMPLETE:-${_st_root}/Incomplete}" \
        "Backups|${STORAGE_BACKUPS:-${_st_root}/Backups}" \
        "LXC|${_st_root}/lxc" \
        "Git-Repos|${_st_root}/git-repos" \
        "Workspace|${_st_root}/workspace"; do
        _dn="${_dspec%%|*}"
        _dp="${_dspec#*|}"
        if [ -d "$_dp" ]; then
            _ds=$(timeout 2 du -sh "$_dp" 2>/dev/null | awk '{print $1}' || echo "0")
            [ -z "$_ds" ] && _ds="0"
            printf "%s\t%s\t%s\n" "$_dn" "$_dp" "$_ds" >> "$_dirs_tmp"
        fi
    done
    _dirs_json=$(jq -Rn '[inputs | select(length > 0) | split("\t") | {name: .[0], path: .[1], size: .[2]}]' < "$_dirs_tmp" 2>/dev/null || echo '[]')
    rm -f "$_dirs_tmp" 2>/dev/null || true
    jq -cn \
        --arg root "$_st_root" \
        --argjson ext_expected "$_st_exp" \
        --argjson ext_mounted "$_st_mnt" \
        --argjson luks_mapped "$_st_luks" \
        --argjson luks_key_exists "$_st_key" \
        --argjson disk_pct "${_st_pct:-0}" \
        --arg disk_used "${_st_used:-0}" \
        --arg disk_total "${_st_tot:-0}" \
        --arg fs_type "${_st_fs:-}" \
        --arg device "${_st_dev:-}" \
        --arg badge "${_st_badge:-}" \
        --argjson dirs "$_dirs_json" \
        '{
            root: $root,
            ext_expected: $ext_expected,
            ext_mounted: $ext_mounted,
            luks_mapped: $luks_mapped,
            luks_key_exists: $luks_key_exists,
            disk_pct: $disk_pct,
            disk_used: $disk_used,
            disk_total: $disk_total,
            fs_type: $fs_type,
            device: $device,
            badge: $badge,
            dirs: $dirs
        }'
}

_collect_alpine_lxc_json() {
    if is_openwrt 2>/dev/null; then
        printf 'null'
        return 0
    fi
    _lxc_inst="false"
    command -v lxc-create >/dev/null 2>&1 && _lxc_inst="true"
    _br_up="false"
    ip link show lxcbr0 >/dev/null 2>&1 && _br_up="true"
    _arch=$(get_lxc_system_arch 2>/dev/null || echo "amd64")
    _lxc_ver=$(lxc-create --version 2>/dev/null | head -n 1 | tr -d '\r\n' || echo "")
    _con_ready="false"
    if command -v ttyd >/dev/null 2>&1; then
        if [ -L /run/openrc/started/gateway-console ] || pgrep ttyd >/dev/null 2>&1; then
            _con_ready="true"
        fi
    fi
    _cts_json='[]'
    if [ "$_lxc_inst" = "true" ]; then
        _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
        _lxc_tmp="/tmp/gw_api_lxc.$$"
        : > "$_lxc_tmp"
        if [ -d "$_real_path" ]; then
            for _ct_dir in "${_real_path}/"*; do
                [ -d "$_ct_dir" ] || continue
                [ -f "${_ct_dir}/config" ] || continue
                _ct_name=$(basename "$_ct_dir")
                _ct_conf="${_ct_dir}/config"
                _st="STOPPED"
                _pid=""
                _ip=""
                _mem=""
                if command -v lxc-info >/dev/null 2>&1; then
                    _inf=$(lxc-info -n "$_ct_name" 2>/dev/null || true)
                    if printf "%s\n" "$_inf" | grep -q "State:.*RUNNING"; then
                        _st="RUNNING"
                        _pid=$(printf "%s\n" "$_inf" | awk '/PID:/ {print $2; exit}' || true)
                        _ip=$(printf "%s\n" "$_inf" | awk '/IP:/ && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $2}' | paste -sd "," - | sed 's/,/, /g' 2>/dev/null || true)
                        _mem=$(printf "%s\n" "$_inf" | awk '/Memory use:/ {print $3 " " $4; exit}' 2>/dev/null || true)
                    fi
                fi
                _auto="false"
                grep -q "^lxc\.start\.auto[[:space:]]*=[[:space:]]*1" "$_ct_conf" 2>/dev/null && _auto="true"
                _nest="false"
                grep -qE "GW_NESTING_BEGIN|nesting\.conf" "$_ct_conf" 2>/dev/null && _nest="true"
                _stor_mnt="false"
                grep -qE "GW_STORAGE_BEGIN|[[:space:]]mnt/storage[[:space:]]" "$_ct_conf" 2>/dev/null && _stor_mnt="true"
                _net_mode="nat"
                grep -q "^lxc\.net\.0\.type[[:space:]]*=[[:space:]]*macvlan" "$_ct_conf" 2>/dev/null && _net_mode="macvlan"
                _stat_ip=$(awk -F= '/^[[:space:]]*lxc\.net\.0\.ipv4\.address/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$_ct_conf" 2>/dev/null || true)
                _mem_lim=$(awk -F= '/^[[:space:]]*lxc\.cgroup2\.memory\.max/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$_ct_conf" 2>/dev/null || true)
                _cpu_lim=$(awk -F= '/^[[:space:]]*lxc\.cgroup2\.cpu\.max/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); split($2,a," "); if (a[1]>0) { q=(a[2]>0?a[2]:100000); v=a[1]/q; if (v == int(v)) printf "%d", v; else printf "%.1f", v } exit}' "$_ct_conf" 2>/dev/null || true)
                _os_pretty=""
                if [ -r "${_ct_dir}/rootfs/etc/os-release" ]; then
                    _os_pretty=$(awk -F= '/^PRETTY_NAME=/ {v=$2; gsub(/^["'\'']|["'\'']$/, "", v); print v; exit}' "${_ct_dir}/rootfs/etc/os-release" 2>/dev/null || true)
                fi
                [ -z "$_os_pretty" ] && [ -r "${_ct_dir}/.gw_os" ] && _os_pretty=$(tr -d '\r\n' < "${_ct_dir}/.gw_os" 2>/dev/null || true)
                _disk_use=""
                if [ -d "${_ct_dir}/rootfs" ]; then
                    _disk_use=$(timeout 2 du -sh "${_ct_dir}/rootfs" 2>/dev/null | awk '{print $1}' || true)
                fi
                _snaps_tmp="/tmp/gw_api_snaps.$$"
                : > "$_snaps_tmp"
                if [ -d "${_ct_dir}/snaps" ]; then
                    for _sd in "${_ct_dir}/snaps/"*; do
                        [ -d "$_sd" ] || continue
                        _sn=$(basename "$_sd")
                        _dt=""
                        if [ -f "${_sd}/ts" ]; then
                            _dt=$(tr -d '\r\n' < "${_sd}/ts" 2>/dev/null || true)
                        else
                            _dt=$(date -r "$_sd" '+%Y-%m-%d %H:%M' 2>/dev/null || true)
                        fi
                        _cmt=""
                        [ -f "${_sd}/comment" ] && _cmt=$(tr -d '\r\n\t' < "${_sd}/comment" 2>/dev/null | cut -c1-120 || true)
                        jq -cn --arg name "$_sn" --arg date "$_dt" --arg comment "$_cmt" '{name: $name, date: $date, comment: $comment}' >> "$_snaps_tmp"
                    done
                fi
                _snaps_json=$(jq -s '.' < "$_snaps_tmp" 2>/dev/null || echo '[]')
                rm -f "$_snaps_tmp" 2>/dev/null || true
                jq -cn \
                    --arg name "$_ct_name" \
                    --arg state "$_st" \
                    --arg pid "$_pid" \
                    --arg ipv4 "$_ip" \
                    --arg memory "$_mem" \
                    --arg mem_limit "$_mem_lim" \
                    --arg cpu_limit "$_cpu_lim" \
                    --arg disk_usage "$_disk_use" \
                    --arg os_pretty "$_os_pretty" \
                    --arg net_mode "$_net_mode" \
                    --arg static_ip "$_stat_ip" \
                    --argjson autostart "$_auto" \
                    --argjson nesting "$_nest" \
                    --argjson storage_mount "$_stor_mnt" \
                    --argjson snapshots "$_snaps_json" \
                    '{
                        name: $name,
                        state: $state,
                        pid: $pid,
                        ipv4: $ipv4,
                        memory: $memory,
                        mem_limit: $mem_limit,
                        cpu_limit: $cpu_limit,
                        disk_usage: $disk_usage,
                        os_pretty: $os_pretty,
                        net_mode: $net_mode,
                        static_ip: $static_ip,
                        autostart: $autostart,
                        nesting: $nesting,
                        storage_mount: $storage_mount,
                        snapshots: $snapshots
                    }' >> "$_lxc_tmp"
            done
        fi
        _cts_json=$(jq -s '.' < "$_lxc_tmp" 2>/dev/null || echo '[]')
        rm -f "$_lxc_tmp" 2>/dev/null || true
    fi
    jq -cn \
        --argjson installed "$_lxc_inst" \
        --argjson bridge_up "$_br_up" \
        --arg arch "$_arch" \
        --arg lxc_version "$_lxc_ver" \
        --argjson console_ready "$_con_ready" \
        --argjson containers "$_cts_json" \
        '{installed: $installed, bridge_up: $bridge_up, arch: $arch, lxc_version: $lxc_version, console_ready: $console_ready, containers: $containers}'
}

_collect_links_json() {
    _lip="$1"
    if is_openwrt 2>/dev/null; then
        jq -cn \
            --arg gw "http://${_lip}" \
            --arg ui "http://${_lip}:9090/ui/" \
            --arg agh "http://${_lip}:3000" \
            --arg ca "" \
            '{gateway_url: $gw, ui_url: $ui, agh_url: $agh, ca_url: $ca}'
        return 0
    fi
    if is_module_enabled "caddy"; then
        if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
            _gw="https://gateway.${SSL_DOMAIN}"
            _ui="https://zashboard.${SSL_DOMAIN}/ui/"
            _agh="https://adguard.${SSL_DOMAIN}"
            _ca="https://ca.${SSL_DOMAIN}"
        else
            _gw="https://${DOM_GATEWAY:-gateway.lan}"
            _ui="https://${DOM_ZASHBOARD:-zashboard.lan}/ui/"
            _agh="https://${DOM_ADGUARD:-adguard.lan}"
            _ca="http://${DOM_CA:-ca.lan}"
        fi
    else
        _gw="http://${_lip}:${PORT_WEBUI:-8095}"
        _ui="http://${_lip}:9090/ui/"
        _agh="http://${_lip}:3000"
        _ca=""
    fi
    jq -cn --arg gw "$_gw" --arg ui "$_ui" --arg agh "$_agh" --arg ca "$_ca" \
        '{gateway_url: $gw, ui_url: $ui, agh_url: $agh, ca_url: $ca}'
}

_cmd_status() {
    calc_hardware_limits >/dev/null 2>&1 || true
    SYS_MODEL=$(_read_sys_model)
    IS_OWRT="false"
    is_openwrt 2>/dev/null && IS_OWRT="true"
    KERNEL_VER=$(uname -r 2>/dev/null || echo "")
    UPTIME_SEC=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)
    LOAD_AVG=$(awk '{print $1 " " $2 " " $3}' /proc/loadavg 2>/dev/null || echo "")

    RAM_PCT=$(get_ram_usage_pct)
    RAM_USED=$(get_ram_used_mb)
    DISK_PCT=$(get_disk_usage_pct "/")
    DISK_USED=$(df -Ph / 2>/dev/null | awk 'NR==2 {print $3}' || echo "0")
    DISK_TOTAL=$(df -Ph / 2>/dev/null | awk 'NR==2 {print $2}' || echo "0")
    CT_USED=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)

    ACT_CORE=$(get_active_core)
    ACT_CORE_NAME=$(get_active_core_name)
    ACT_CORE_VER=$(get_active_core_version)
    CORE_RUN="false"
    CORE_PID=""
    CORE_RSS=""
    if is_core_running; then
        CORE_RUN="true"
        CORE_PID=$(get_core_pid)
        [ -n "$CORE_PID" ] && CORE_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${CORE_PID}/status" 2>/dev/null || true)
    fi

    TUN_UP="false"
    ip link show "$CORE_TUN_IF" >/dev/null 2>&1 && TUN_UP="true"

    ACT_UI=$(get_active_ui)
    ACT_UI_NAME=$(get_active_ui_name)
    ACT_UI_VER=""
    [ -f "$UI_VER_FILE" ] && ACT_UI_VER=$(tr -d ' \t\r\n' < "$UI_VER_FILE" 2>/dev/null || true)

    LAN_IP=$(get_current_lan_ip)
    LAN_IF=$(get_lan_ifname)

    AGH_RUN="false"
    AGH_PID=$(pgrep AdGuardHome 2>/dev/null | head -n 1 || true)
    AGH_RSS=""
    if [ -n "$AGH_PID" ]; then
        AGH_RUN="true"
        AGH_RSS=$(awk '/^VmRSS:/ {printf "%.1f МБ", $2/1024}' "/proc/${AGH_PID}/status" 2>/dev/null || true)
    fi
    AGH_VER=""
    [ -x /usr/bin/AdGuardHome ] && AGH_VER=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)

    DHCP_EN="false"
    is_dhcp_server_enabled && DHCP_EN="true"

    AGH_ST_JSON='{}'
    AGH_DHCP_JSON='{"enabled":false,"leases":[]}'
    if [ "$AGH_RUN" = "true" ] && [ -n "${AGH_USER:-}" ] && [ -n "${ADMIN_PASS:-}" ]; then
        _tmp_st=$(curl -fsS -m 2 -u "${AGH_USER}:${ADMIN_PASS}" "http://127.0.0.1:3000/control/status" 2>/dev/null || true)
        [ -n "$_tmp_st" ] && printf "%s" "$_tmp_st" | jq -e . >/dev/null 2>&1 && AGH_ST_JSON="$_tmp_st"
        _tmp_dh=$(curl -fsS -m 2 -u "${AGH_USER}:${ADMIN_PASS}" "http://127.0.0.1:3000/control/dhcp/status" 2>/dev/null || true)
        [ -n "$_tmp_dh" ] && printf "%s" "$_tmp_dh" | jq -e . >/dev/null 2>&1 && AGH_DHCP_JSON="$_tmp_dh"
    fi

    KS_EN="false"
    is_killswitch_enabled && KS_EN="true"
    WD_EN="false"
    is_watchdog_enabled && WD_EN="true"
    AU_EN="false"
    is_autoupdate_enabled && AU_EN="true"

    TG_CFG="false"
    is_telegram_configured && TG_CFG="true"
    TG_MASK=$(_mask_token "${TG_BOT_TOKEN:-}")

    BAK_EX="false"
    BAK_SIZE=""
    BAK_MTIME=""
    if [ -f "$BACKUP_ARCHIVE" ]; then
        BAK_EX="true"
        BAK_SIZE=$(du -sh "$BACKUP_ARCHIVE" 2>/dev/null | awk '{print $1}' || echo "")
        BAK_MTIME=$(date -r "$BACKUP_ARCHIVE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || true)
    fi

    GIT_REPO="false"
    GIT_SHA="Standalone"
    GIT_BR="main"
    if [ -d "${GATEWAY_DIR}/.git" ] && command -v git >/dev/null 2>&1; then
        GIT_REPO="true"
        GIT_SHA=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo "HEAD")
        GIT_BR=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" branch --show-current 2>/dev/null || echo "main")
        [ -z "$GIT_BR" ] && GIT_BR="main"
    fi
    UPD_STAT=""
    UPD_BEHIND=0
    if [ -f /tmp/gateway_update_check.cache ]; then
        IFS='|' read -r UPD_STAT UPD_BEHIND _ _ < /tmp/gateway_update_check.cache 2>/dev/null || true
    fi

    SUB_CNT=$(count_sub_urls)
    WARP_EN="false"
    is_warp_enabled && WARP_EN="true"
    WARP_LIC_SET="false"
    [ -n "${WARP_LICENSE:-}" ] && WARP_LIC_SET="true"

    MY_NODES_JSON='[]'
    if has_my_nodes; then
        MY_NODES_JSON=$(awk '
            NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {
                idx++
                line = $0
                proto = line
                sub(/:\/\/.*/, "", proto)
                tag = "(без названия)"
                if (index(line, "#") > 0) {
                    tag = substr(line, index(line, "#") + 1)
                    gsub(/%20/, " ", tag)
                }
                host = line
                sub(/^[a-zA-Z0-9+-]+:\/\/([^@]*@)?/, "", host)
                sub(/[\/?#].*/, "", host)
                printf "%d\t%s\t%s\t%s\t%s\n", idx, proto, host, tag, line
            }
        ' "$CUSTOM_NODES_FILE" 2>/dev/null | jq -Rn '
            [inputs | select(length > 0) | split("\t") | {
                index: (.[0] | tonumber),
                proto: .[1],
                host: .[2],
                tag: .[3],
                uri: .[4]
            }]
        ' 2>/dev/null || echo '[]')
    fi

    PROXY_DOMS_JSON='[]'
    if [ -s "$USER_PROXY_FILE" ]; then
        PROXY_DOMS_JSON=$(awk 'NF {print $0}' "$USER_PROXY_FILE" 2>/dev/null | jq -Rn '[inputs | select(length > 0)]' 2>/dev/null || echo '[]')
    fi
    DIRECT_DOMS_JSON='[]'
    if [ -s "$USER_DIRECT_FILE" ]; then
        DIRECT_DOMS_JSON=$(awk 'NF {print $0}' "$USER_DIRECT_FILE" 2>/dev/null | jq -Rn '[inputs | select(length > 0)]' 2>/dev/null || echo '[]')
    fi

    GROUPS_JSON='[]'
    if [ "$CORE_RUN" = "true" ] && [ -n "${ADMIN_PASS:-}" ]; then
        _px_raw=$(curl -fsS -m 2 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null || true)
        if [ -n "$_px_raw" ]; then
            GROUPS_JSON=$(printf "%s" "$_px_raw" | jq -c '
                def order: ["⚡ Авто (Самый быстрый)","🤖 Нейросети (ИИ)","🤖 Авто-ИИ","🇩🇪 Германия","🇩🇪 Авто-DE","🇺🇸 США","🇺🇸 Авто-US","▶️ YouTube & Медиа","💬 Мессенджеры","🎮 Гейминг","🎮 Авто-Гейминг","🧱 Roblox","🛑 Обход блокировок","🌐 Google & Android","🧲 Торренты","🌐 Остальной трафик"];
                .proxies as $p |
                [order[] | . as $k | select($p[$k] != null) | {
                    name: $k,
                    type: ($p[$k].type // ""),
                    now: (
                        ($p[$k].now // "") as $n |
                        if ($n != "" and (($p[$n].now // "") != "")) then "\($n) -> \($p[$n].now)"
                        else $n end
                    ),
                    count: (($p[$k].all // []) | length)
                }]
            ' 2>/dev/null || echo '[]')
        fi
    fi

    _leases_tmp="/tmp/gw_luci_leases.$$"
    printf "%s" "$AGH_DHCP_JSON" | jq -r '.leases[]? | [.ip, (.mac // ""), (.hostname // "")] | @tsv' > "$_leases_tmp" 2>/dev/null || : > "$_leases_tmp"

    DEVICES_JSON=$(awk -v self="$LAN_IP" -v gw="${GW_IP:-}" -v byp_f="$USER_BYPASS_IPS" -v vpn_f="$USER_FORCE_PROXY_IPS" '
        BEGIN {
            while ((getline line < byp_f) > 0) {
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
                if (line != "") byp[line] = 1
            }
            close(byp_f)
            while ((getline line < vpn_f) > 0) {
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
                if (line != "") vpn[line] = 1
            }
            close(vpn_f)
        }
        FILENAME != "/proc/net/arp" {
            ip = $1; mac = tolower($2); host = $3
            if (ip ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && ip != self) {
                ips[ip] = 1
                if (mac != "") macs[ip] = mac
                if (host != "" && host != "*") names[ip] = host
            }
            next
        }
        FILENAME == "/proc/net/arp" && FNR > 1 {
            ip = $1; flags = $3; mac = tolower($4)
            if (ip != self && flags != "0x0" && mac != "00:00:00:00:00:00") {
                ips[ip] = 1
                if (macs[ip] == "") macs[ip] = mac
            }
            next
        }
        END {
            for (ip in byp) ips[ip] = 1
            for (ip in vpn) ips[ip] = 1
            for (ip in ips) {
                m = (macs[ip] != "") ? macs[ip] : ""
                n = (names[ip] != "") ? names[ip] : ""
                if (ip == gw) {
                    n = (n != "") ? ("Роутер (" n ")") : "Основной роутер"
                }
                mode = "default"
                if (byp[ip]) mode = "bypass"
                if (vpn[ip]) mode = "force_proxy"
                printf "%s\t%s\t%s\t%s\n", ip, m, n, mode
            }
        }
    ' "$_leases_tmp" /proc/net/arp 2>/dev/null | jq -Rn '
        [inputs | select(length > 0) | split("\t") | {
            ip: .[0],
            mac: .[1],
            hostname: .[2],
            mode: .[3]
        }] | sort_by(.ip)
    ' 2>/dev/null || echo '[]')
    rm -f "$_leases_tmp" 2>/dev/null || true

    ACT_JOB=""
    if [ -f /tmp/gw_luci_current.id ]; then
        _cur_jid=$(cat /tmp/gw_luci_current.id 2>/dev/null | tr -dc 'A-Za-z0-9_-' || true)
        if [ -n "$_cur_jid" ] && _is_job_running "$_cur_jid"; then
            ACT_JOB="$_cur_jid"
        fi
    fi

    SSL_JSON=$(_collect_alpine_ssl_json)
    HOMELAB_JSON=$(_collect_alpine_homelab_json "$LAN_IP")
    STORAGE_JSON=$(_collect_alpine_storage_json)
    LXC_JSON=$(_collect_alpine_lxc_json)
    LINKS_JSON=$(_collect_links_json "$LAN_IP")

    jq -cn \
        --arg os_name "${OS_NAME:-OpenWrt}" \
        --argjson is_openwrt "$IS_OWRT" \
        --arg model "$SYS_MODEL" \
        --arg kernel "$KERNEL_VER" \
        --argjson uptime_sec "${UPTIME_SEC:-0}" \
        --arg load "$LOAD_AVG" \
        --argjson ram_pct "${RAM_PCT:-0}" \
        --argjson ram_used_mb "${RAM_USED:-0}" \
        --argjson ram_total_mb "${TOTAL_RAM_MB:-0}" \
        --argjson disk_pct "${DISK_PCT:-0}" \
        --arg disk_used "$DISK_USED" \
        --arg disk_total "$DISK_TOTAL" \
        --argjson ct_used "${CT_USED:-0}" \
        --argjson ct_max "${SYS_CONNTRACK_MAX:-0}" \
        --arg core "$ACT_CORE" \
        --arg core_name "$ACT_CORE_NAME" \
        --arg core_ver "$ACT_CORE_VER" \
        --argjson core_running "$CORE_RUN" \
        --arg core_pid "$CORE_PID" \
        --arg core_rss "$CORE_RSS" \
        --arg core_memlimit "${SB_GOMEMLIMIT:-off}" \
        --argjson tun_up "$TUN_UP" \
        --arg tun_if "${CORE_TUN_IF:-gateway-tun}" \
        --arg ui "$ACT_UI" \
        --arg ui_name "$ACT_UI_NAME" \
        --arg ui_ver "$ACT_UI_VER" \
        --arg lan_ip "$LAN_IP" \
        --arg lan_if "$LAN_IF" \
        --arg gw_ip "${GW_IP:-}" \
        --argjson agh_running "$AGH_RUN" \
        --arg agh_pid "$AGH_PID" \
        --arg agh_rss "$AGH_RSS" \
        --arg agh_ver "$AGH_VER" \
        --arg agh_user "${AGH_USER:-neko}" \
        --argjson agh_status "$AGH_ST_JSON" \
        --argjson dhcp_enabled "$DHCP_EN" \
        --argjson dhcp_status "$AGH_DHCP_JSON" \
        --argjson killswitch "$KS_EN" \
        --argjson watchdog "$WD_EN" \
        --argjson autoupdate "$AU_EN" \
        --argjson tg_configured "$TG_CFG" \
        --arg tg_chat_id "${TG_CHAT_ID:-}" \
        --arg tg_token_masked "$TG_MASK" \
        --argjson backup_exists "$BAK_EX" \
        --arg backup_size "$BAK_SIZE" \
        --arg backup_mtime "$BAK_MTIME" \
        --argjson git_is_repo "$GIT_REPO" \
        --arg git_sha "$GIT_SHA" \
        --arg git_branch "$GIT_BR" \
        --arg update_status "$UPD_STAT" \
        --argjson update_behind "${UPD_BEHIND:-0}" \
        --arg sub_urls "${SUB_URL:-}" \
        --argjson sub_count "${SUB_CNT:-0}" \
        --arg allow_ru "${ALLOW_RU_NODES:-no}" \
        --argjson warp_enabled "$WARP_EN" \
        --argjson warp_license_set "$WARP_LIC_SET" \
        --argjson my_nodes "$MY_NODES_JSON" \
        --argjson proxy_domains "$PROXY_DOMS_JSON" \
        --argjson direct_domains "$DIRECT_DOMS_JSON" \
        --argjson proxy_groups "$GROUPS_JSON" \
        --argjson lan_devices "$DEVICES_JSON" \
        --argjson ssl "$SSL_JSON" \
        --argjson homelab "$HOMELAB_JSON" \
        --argjson storage "$STORAGE_JSON" \
        --argjson lxc "$LXC_JSON" \
        --argjson links "$LINKS_JSON" \
        --arg active_job_id "$ACT_JOB" \
        '{
            ok: true,
            system: {
                os_name: $os_name,
                is_openwrt: $is_openwrt,
                model: $model,
                kernel: $kernel,
                uptime_sec: $uptime_sec,
                load: $load,
                ram_pct: $ram_pct,
                ram_used_mb: $ram_used_mb,
                ram_total_mb: $ram_total_mb,
                disk_pct: $disk_pct,
                disk_used: $disk_used,
                disk_total: $disk_total,
                conntrack_used: $ct_used,
                conntrack_max: $ct_max
            },
            core: {
                engine: $core,
                name: $core_name,
                version: $core_ver,
                running: $core_running,
                pid: $core_pid,
                rss: $core_rss,
                memlimit: $core_memlimit,
                tun_up: $tun_up,
                tun_if: $tun_if,
                ui: $ui,
                ui_name: $ui_name,
                ui_ver: $ui_ver
            },
            network: {
                lan_ip: $lan_ip,
                lan_if: $lan_if,
                gw_ip: $gw_ip,
                killswitch: $killswitch
            },
            adguard: {
                running: $agh_running,
                pid: $agh_pid,
                rss: $agh_rss,
                version: $agh_ver,
                user: $agh_user,
                protection_enabled: ($agh_status.protection_enabled // false),
                dhcp_enabled: $dhcp_enabled,
                dhcp_v4: ($dhcp_status.v4 // null),
                dhcp_leases: ($dhcp_status.leases // [])
            },
            cron: {
                watchdog: $watchdog,
                autoupdate: $autoupdate
            },
            telegram: {
                configured: $tg_configured,
                chat_id: $tg_chat_id,
                token_masked: $tg_token_masked
            },
            backup: {
                exists: $backup_exists,
                size: $backup_size,
                mtime: $backup_mtime
            },
            git: {
                is_repo: $git_is_repo,
                sha: $git_sha,
                branch: $git_branch,
                update_status: $update_status,
                update_behind: $update_behind
            },
            proxies: {
                sub_urls: $sub_urls,
                sub_count: $sub_count,
                allow_ru: ($allow_ru == "yes"),
                warp_enabled: $warp_enabled,
                warp_license_set: $warp_license_set,
                my_nodes: $my_nodes,
                proxy_domains: $proxy_domains,
                direct_domains: $direct_domains,
                groups: $proxy_groups
            },
            devices: $lan_devices,
            ssl: $ssl,
            homelab: $homelab,
            storage: $storage,
            lxc: $lxc,
            links: $links,
            active_job_id: $active_job_id
        }'
}

_cmd_trace() {
    DNS_AI=$(nslookup chatgpt.com 127.0.0.1 2>/dev/null | awk '/^Address/ && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 !~ /^127\./ {print $2; exit}')
    DNS_RU=$(nslookup ya.ru 127.0.0.1 2>/dev/null | awk '/^Address/ && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 !~ /^127\./ {print $2; exit}')
    DNS_DDR_A=$(nslookup -type=A _dns.resolver.arpa 127.0.0.1 2>/dev/null | awk '/^Address/ && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 !~ /^127\./ {print $2; exit}')
    DNS_DOH_A=$(nslookup -type=A use-application-dns.net 127.0.0.1 2>/dev/null | awk '/^Address/ && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $2 !~ /^127\./ {print $2; exit}')
    DDR_OK="false"
    if [ -z "$DNS_DDR_A" ] && [ -z "$DNS_DOH_A" ] && ! nslookup -type=A -port=1053 _dns.resolver.arpa 127.0.0.1 >/dev/null 2>&1; then
        DDR_OK="true"
    fi

    CF_RAW=$(curl -fsS --curves X25519:P-256 --connect-timeout 4 -m 6 -x http://127.0.0.1:7890 "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null || \
             curl -fsS --connect-timeout 4 -m 6 -x http://127.0.0.1:7890 "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null || true)
    CF_IP=$(printf "%s\n" "$CF_RAW" | awk -F= '$1=="ip"{print $2; exit}')
    CF_COLO=$(printf "%s\n" "$CF_RAW" | awk -F= '$1=="colo"{print $2; exit}')
    CF_LOC=$(printf "%s\n" "$CF_RAW" | awk -F= '$1=="loc"{print $2; exit}')
    CF_WARP=$(printf "%s\n" "$CF_RAW" | awk -F= '$1=="warp"{print $2; exit}')

    P_RU=$(curl -o /dev/null -fsS --connect-timeout 2 -m 3 -w '%{time_connect}' "http://ya.ru" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "-1"}' || echo "-1")
    P_CF=$(curl -o /dev/null -fsS --connect-timeout 3 -m 4 -x http://127.0.0.1:7890 -w '%{time_total}' "http://cp.cloudflare.com/generate_204" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "-1"}' || echo "-1")
    P_YT=$(curl -o /dev/null -fsS --connect-timeout 3 -m 5 -x http://127.0.0.1:7890 -w '%{time_total}' "https://www.youtube.com/generate_204" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "-1"}' || echo "-1")
    P_AI=$(curl -o /dev/null -sS --connect-timeout 3 -m 5 -x http://127.0.0.1:7890 -w '%{time_appconnect}' "https://api.openai.com" 2>/dev/null | awk '$1+0 > 0 {printf "%.0f", $1*1000; ok=1} END {if (!ok) print "-1"}' || echo "-1")

    jq -cn \
        --arg ip "$CF_IP" --arg colo "$CF_COLO" --arg loc "$CF_LOC" --arg warp "$CF_WARP" \
        --arg dns_ai "$DNS_AI" --arg dns_ru "$DNS_RU" --argjson ddr_block "$DDR_OK" \
        --argjson ping_ru "${P_RU:--1}" --argjson ping_cf "${P_CF:--1}" \
        --argjson ping_yt "${P_YT:--1}" --argjson ping_ai "${P_AI:--1}" \
        '{
            ok: true,
            trace: { ip: $ip, colo: $colo, loc: $loc, warp: $warp },
            dns: { chatgpt: $dns_ai, yaru: $dns_ru, ddr_block: $ddr_block },
            latency_ms: { ru: $ping_ru, cf: $ping_cf, yt: $ping_yt, ai: $ping_ai }
        }'
}

_cmd_domain_inspect() {
    RAW_D=$(_jq_arg "domain")
    CLEAN_SUF=$(sanitize_domain_entry "$RAW_D" 2>/dev/null || true)
    [ -z "$CLEAN_SUF" ] && { _json_err "Некорректное имя домена: ${RAW_D}"; return 0; }
    CLEAN_HOST="${CLEAN_SUF#+.}"

    LIST_SRC="rules"
    if grep -qxF "$CLEAN_SUF" "$USER_DIRECT_FILE" 2>/dev/null; then
        LIST_SRC="direct"
    elif grep -qxF "$CLEAN_SUF" "$USER_PROXY_FILE" 2>/dev/null; then
        LIST_SRC="proxy"
    fi

    RES_IP=$(nslookup "$CLEAN_HOST" 127.0.0.1 2>/dev/null | awk '
        /^Server:/ { next }
        /^Address.*127\.0\.0\.1/ { next }
        /^Name:|^Non-authoritative answer:/ { f=1; next }
        f && /Address/ {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit }
            }
        }
    ' || true)

    VERDICT="unknown"
    case "$RES_IP" in
        0.0.0.0|127.0.0.1) VERDICT="blocked" ;;
        198.18.*|198.19.*) VERDICT="proxy" ;;
        "$(get_current_lan_ip)") VERDICT="local" ;;
        "") VERDICT="nxdomain" ;;
        *) VERDICT="direct" ;;
    esac

    PRX_RES=$(curl -k -o /dev/null -sS --connect-timeout 3 -m 5 -x http://127.0.0.1:7890 -w '%{http_code} %{time_appconnect}' "https://${CLEAN_HOST}" 2>/dev/null || echo "000 0")
    PRX_CODE=$(printf "%s" "$PRX_RES" | awk '{print $1}')
    PRX_MS=$(printf "%s" "$PRX_RES" | awk '$2+0 > 0 {printf "%.0f", $2*1000; ok=1} END {if (!ok) print "-1"}')

    LAN_IF_T=$(get_lan_ifname)
    DIR_RES=$(curl -k -o /dev/null -sS --interface "$LAN_IF_T" --connect-timeout 2 -m 4 -w '%{http_code} %{time_appconnect}' "https://${CLEAN_HOST}" 2>/dev/null || echo "000 0")
    DIR_CODE=$(printf "%s" "$DIR_RES" | awk '{print $1}')
    DIR_MS=$(printf "%s" "$DIR_RES" | awk '$2+0 > 0 {printf "%.0f", $2*1000; ok=1} END {if (!ok) print "-1"}')

    jq -cn \
        --arg domain "$CLEAN_HOST" --arg suffix "$CLEAN_SUF" \
        --arg list_source "$LIST_SRC" --arg resolved_ip "$RES_IP" --arg verdict "$VERDICT" \
        --arg proxy_http "$PRX_CODE" --argjson proxy_ms "${PRX_MS:--1}" \
        --arg direct_http "$DIR_CODE" --argjson direct_ms "${DIR_MS:--1}" \
        '{
            ok: true,
            domain: $domain,
            suffix: $suffix,
            list_source: $list_source,
            resolved_ip: $resolved_ip,
            verdict: $verdict,
            proxy_http: $proxy_http,
            proxy_ms: $proxy_ms,
            direct_http: $direct_http,
            direct_ms: $direct_ms
        }'
}

_cmd_set_dhcp() {
    MODE=$(_jq_arg "mode")
    case "$MODE" in
        on|off) ;;
        *) _json_err "Недопустимый режим DHCP: ${MODE}"; return 0 ;;
    esac
    _out_f="/tmp/gw_luci_dhcp.$$"
    _rc=0
    configure_smart_dhcp "$MODE" >"$_out_f" 2>&1 || _rc=$?
    MSG=$(_strip_ansi < "$_out_f" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    rm -f "$_out_f" 2>/dev/null || true
    EN="false"
    is_dhcp_server_enabled && EN="true"
    if [ "$_rc" -eq 0 ]; then
        jq -cn --argjson en "$EN" --arg m "$MSG" '{ok: true, enabled: $en, message: $m}'
    else
        jq -cn --argjson en "$EN" --arg e "$MSG" '{ok: false, enabled: $en, error: $e}'
    fi
}

_cmd_set_killswitch() {
    MODE=$(_jq_arg "mode")
    case "$MODE" in
        on)  _ks_arg="yes" ;;
        off) _ks_arg="no" ;;
        *) _json_err "Недопустимый режим Kill-Switch"; return 0 ;;
    esac
    sync_dns_firewall "yes" "$_ks_arg" >/dev/null 2>&1 || {
        _json_err "Не удалось применить правила nftables Kill-Switch"
        return 0
    }
    EN="false"
    is_killswitch_enabled && EN="true"
    jq -cn --argjson en "$EN" '{ok: true, enabled: $en}'
}

_cmd_set_cron() {
    TGT=$(_jq_arg "target")
    EN_IN=$(_jq_arg "enabled")
    case "$TGT" in
        watchdog)
            if [ "$EN_IN" = "yes" ] || [ "$EN_IN" = "on" ] || [ "$EN_IN" = "true" ]; then
                enable_watchdog >/dev/null 2>&1
            else
                disable_watchdog >/dev/null 2>&1
            fi
            EN="false"; is_watchdog_enabled && EN="true"
            ;;
        autoupdate)
            if [ "$EN_IN" = "yes" ] || [ "$EN_IN" = "on" ] || [ "$EN_IN" = "true" ]; then
                enable_autoupdate >/dev/null 2>&1
            else
                disable_autoupdate >/dev/null 2>&1
            fi
            EN="false"; is_autoupdate_enabled && EN="true"
            ;;
        *)
            _json_err "Неизвестная задача cron: ${TGT}"
            return 0
            ;;
    esac
    jq -cn --arg target "$TGT" --argjson enabled "$EN" '{ok: true, target: $target, enabled: $enabled}'
}

_cmd_set_network() {
    IN_LAN=$(_jq_arg "lan_ip")
    IN_GW=$(_jq_arg "gw_ip")
    CUR_LAN=$(get_current_lan_ip)
    [ -z "$IN_LAN" ] && IN_LAN="$CUR_LAN"
    [ -z "$IN_GW" ] && IN_GW="${GW_IP:-}"

    is_valid_ipv4 "$IN_LAN" || { _json_err "Некорректный IP шлюза: ${IN_LAN}"; return 0; }
    is_valid_ipv4 "$IN_GW" || { _json_err "Некорректный IP роутера: ${IN_GW}"; return 0; }
    [ "$IN_LAN" = "$IN_GW" ] && { _json_err "IP шлюза и роутера не могут совпадать"; return 0; }
    [ "${IN_LAN%.*}" != "${IN_GW%.*}" ] && { _json_err "IP шлюза и роутера должны быть в одной подсети /24"; return 0; }

    if [ "$IN_LAN" != "$CUR_LAN" ]; then
        check_ip_conflict_on_lan "$IN_LAN" "$CUR_LAN" >/dev/null 2>&1 || {
            _json_err "IP ${IN_LAN} уже занят другим устройством в сети"
            return 0
        }
    fi

    _net_out="/tmp/gw_luci_net.$$"
    _rc=0
    apply_network_ips "$IN_LAN" "$IN_GW" </dev/null >"$_net_out" 2>&1 || _rc=$?
    MSG=$(_strip_ansi < "$_net_out" | tail -n 5 | tr '\n' ' ')
    rm -f "$_net_out" 2>/dev/null || true

    if [ "$_rc" -eq 0 ]; then
        CH="false"
        [ "$IN_LAN" != "$CUR_LAN" ] && CH="true"
        jq -cn --argjson ip_changed "$CH" --arg new_ip "$IN_LAN" --arg gw_ip "$IN_GW" \
            '{ok: true, ip_changed: $ip_changed, new_ip: $new_ip, gw_ip: $gw_ip}'
    else
        jq -cn --arg e "${MSG:-Ошибка применения сетевых настроек}" '{ok: false, error: $e}'
    fi
}

_cmd_set_subscription() {
    URLS_RAW=$(_jq_arg "urls")
    ARU_IN=$(_jq_arg "allow_ru")
    CLEAN_LIST=""
    if [ -n "$(printf "%s" "$URLS_RAW" | tr -d ' \t\r\n')" ]; then
        CLEAN_LIST=$(sanitize_sub_url_list "$URLS_RAW" 2>/dev/null || true)
        BAD="no"
        _valid_cnt=0
        for _u in $CLEAN_LIST; do
            case "$_u" in
                http://*|https://*)
                    case "$_u" in
                        *[\"\'\\\`\;\|\&\<\>\$\(\)]*) BAD="yes" ;;
                        *) _valid_cnt=$((_valid_cnt + 1)) ;;
                    esac
                    ;;
                *) BAD="yes" ;;
            esac
        done
        if [ "$BAD" = "yes" ] || [ "$_valid_cnt" -eq 0 ]; then
            _json_err "Некорректная ссылка подписки (разрешены http:// или https:// без спецсимволов)"
            return 0
        fi
        SUB_URL="$CLEAN_LIST"
    else
        SUB_URL=""
    fi

    case "$ARU_IN" in
        yes|true|1) ALLOW_RU_NODES="yes" ;;
        *) ALLOW_RU_NODES="no" ;;
    esac
    save_gateway_env >/dev/null 2>&1
    jq -cn --arg sub "$SUB_URL" --arg aru "$ALLOW_RU_NODES" '{ok: true, sub_urls: $sub, allow_ru: ($aru == "yes")}'
}

_cmd_node_add() {
    RAW_URI=$(_jq_arg "uri" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$RAW_URI" in
        vless://*|vmess://*|ss://*|ssr://*|trojan://*|hy2://*|hysteria2://*|hysteria://*|tuic://*|wg://*|wireguard://*|anytls://*|mieru://*|xhttp://*|splithttp://*|socks5://*|trusttunnel://*|sudoku://*|call://*|naive+https://*|naive+quic://*|naive://*|snell://*|openvpn://*|ssh://*)
            mkdir -p "$SB_PROVIDERS_DIR" 2>/dev/null || true
            [ -f "$CUSTOM_NODES_FILE" ] || : > "$CUSTOM_NODES_FILE"
            sed -i '/^proxies:[[:space:]]*\[\]/d' "$CUSTOM_NODES_FILE" 2>/dev/null || true
            format_uri_keys "$RAW_URI" >> "$CUSTOM_NODES_FILE"
            jq -cn '{ok: true}'
            ;;
        *)
            _json_err "Неподдерживаемая схема URI (нужен ключ vless://, hy2://, trojan://, ss://, ...)"
            ;;
    esac
}

_cmd_node_delete() {
    IDX=$(_jq_arg "index")
    case "$IDX" in
        ''|*[!0-9]*) _json_err "Некорректный индекс ключа"; return 0 ;;
    esac
    if delete_my_node_by_index "$IDX" >/dev/null 2>&1; then
        jq -cn '{ok: true}'
    else
        _json_err "Не удалось удалить ключ с номером ${IDX}"
    fi
}

_cmd_domain_rule() {
    ACT=$(_jq_arg "action")
    LST=$(_jq_arg "list")
    RAW_DOM=$(_jq_arg "domain")
    init_user_lists >/dev/null 2>&1 || true

    case "$LST" in
        proxy)  TGT_F="$USER_PROXY_FILE"; OTH_F="$USER_DIRECT_FILE" ;;
        direct) TGT_F="$USER_DIRECT_FILE"; OTH_F="$USER_PROXY_FILE" ;;
        *) _json_err "Неизвестный список доменов: ${LST}"; return 0 ;;
    esac

    CLEAN_SUF=$(sanitize_domain_entry "$RAW_DOM" 2>/dev/null || true)
    [ -z "$CLEAN_SUF" ] && { _json_err "Некорректный домен: ${RAW_DOM}"; return 0; }

    case "$ACT" in
        add)
            awk -v d="$CLEAN_SUF" 'NF && $0 != d {print}' "$OTH_F" > "${OTH_F}.tmp.$$" && mv -f "${OTH_F}.tmp.$$" "$OTH_F"
            grep -qxF "$CLEAN_SUF" "$TGT_F" 2>/dev/null || printf "%s\n" "$CLEAN_SUF" >> "$TGT_F"
            if [ ! -s "$USER_DIRECT_FILE" ]; then
                printf "+.localdomain\n+.lan\n" > "$USER_DIRECT_FILE"
            fi
            jq -cn --arg d "$CLEAN_SUF" '{ok: true, domain: $d}'
            ;;
        del)
            [ "$LST" = "direct" ] && { [ "$CLEAN_SUF" = "+.localdomain" ] || [ "$CLEAN_SUF" = "+.lan" ]; } && {
                _json_err "Системные суффиксы +.localdomain и +.lan удалять нельзя"
                return 0
            }
            awk -v d="$CLEAN_SUF" 'NF && $0 != d {print}' "$TGT_F" > "${TGT_F}.tmp.$$" && mv -f "${TGT_F}.tmp.$$" "$TGT_F"
            jq -cn --arg d "$CLEAN_SUF" '{ok: true, domain: $d}'
            ;;
        *)
            _json_err "Неизвестное действие с доменом: ${ACT}"
            ;;
    esac
}

_cmd_device_rule() {
    MODE=$(_jq_arg "mode")
    DEV_IP=$(_jq_arg "ip")
    is_valid_ipv4 "$DEV_IP" || { _json_err "Некорректный IPv4 устройства: ${DEV_IP}"; return 0; }
    mkdir -p "$SB_DIR" 2>/dev/null || true
    touch "$USER_BYPASS_IPS" "$USER_FORCE_PROXY_IPS" 2>/dev/null || true

    awk -v ip="$DEV_IP" 'NF && $0 != ip {print}' "$USER_BYPASS_IPS" > "${USER_BYPASS_IPS}.tmp.$$" && mv -f "${USER_BYPASS_IPS}.tmp.$$" "$USER_BYPASS_IPS"
    awk -v ip="$DEV_IP" 'NF && $0 != ip {print}' "$USER_FORCE_PROXY_IPS" > "${USER_FORCE_PROXY_IPS}.tmp.$$" && mv -f "${USER_FORCE_PROXY_IPS}.tmp.$$" "$USER_FORCE_PROXY_IPS"

    case "$MODE" in
        bypass)      printf "%s\n" "$DEV_IP" >> "$USER_BYPASS_IPS" ;;
        force_proxy) printf "%s\n" "$DEV_IP" >> "$USER_FORCE_PROXY_IPS" ;;
        default)     ;;
        *) _json_err "Некорректный режим устройства: ${MODE}"; return 0 ;;
    esac
    jq -cn --arg ip "$DEV_IP" --arg mode "$MODE" '{ok: true, ip: $ip, mode: $mode}'
}

_cmd_set_telegram() {
    ACT=$(_jq_arg "action")
    IN_TOK=$(_jq_arg "token" | tr -d ' \t\r\n')
    IN_CID=$(_jq_arg "chat_id" | tr -d ' \t\r\n')
    _src_lbl="из Web Dashboard"
    is_openwrt 2>/dev/null && _src_lbl="из LuCI"

    case "$ACT" in
        save)
            [ -z "$IN_CID" ] && { _json_err "Укажите Chat ID"; return 0; }
            if [ -n "$IN_TOK" ]; then
                TG_BOT_TOKEN="$IN_TOK"
            fi
            [ -z "${TG_BOT_TOKEN:-}" ] && { _json_err "Укажите API Token бота (@BotFather)"; return 0; }
            TG_CHAT_ID="$IN_CID"
            save_gateway_env >/dev/null 2>&1
            if send_telegram_msg "✅ Сервер (${OS_NAME} | $(get_current_lan_ip)) подключен к Telegram ${_src_lbl}!" >/dev/null 2>&1; then
                jq -cn '{ok: true, sent: true, message: "Настройки сохранены, тестовое сообщение доставлено!"}'
            else
                jq -cn --arg err "${TG_LAST_ERR:-проверьте /start у бота}" \
                    '{ok: true, sent: false, message: "Настройки сохранены, но тест не доставлен", error: $err}'
            fi
            ;;
        test)
            is_telegram_configured || { _json_err "Telegram-бот не настроен"; return 0; }
            if send_telegram_msg "🔔 Проверка связи с шлюзом (${OS_NAME} | $(get_current_lan_ip)) ${_src_lbl}." >/dev/null 2>&1; then
                jq -cn '{ok: true, message: "Тестовое сообщение успешно доставлено в Telegram!"}'
            else
                jq -cn --arg e "${TG_LAST_ERR:-нет ответа от API}" '{ok: false, error: $e}'
            fi
            ;;
        disable)
            TG_BOT_TOKEN=""
            TG_CHAT_ID=""
            save_gateway_env >/dev/null 2>&1
            jq -cn '{ok: true, message: "Telegram-уведомления отключены"}'
            ;;
        *)
            _json_err "Неизвестное действие Telegram: ${ACT}"
            ;;
    esac
}

_cmd_set_password() {
    NEW_P=$(_jq_arg "password" | tr -d '\r\n')
    [ "${#NEW_P}" -lt 4 ] && { _json_err "Пароль должен быть не короче 4 символов"; return 0; }
    _pw_out="/tmp/gw_luci_pw.$$"
    _rc=0
    change_unified_password "$NEW_P" "yes" </dev/null >"$_pw_out" 2>&1 || _rc=$?
    MSG=$(_strip_ansi < "$_pw_out" | tail -n 3 | tr '\n' ' ')
    rm -f "$_pw_out" 2>/dev/null || true
    if [ "$_rc" -eq 0 ]; then
        if is_openwrt 2>/dev/null; then
            jq -cn '{ok: true, message: "Единый мастер-пароль обновлён для AdGuard Home и Clash API"}'
        else
            jq -cn '{ok: true, message: "Единый мастер-пароль обновлён для всех сервисов и Web Dashboard"}'
        fi
    else
        jq -cn --arg e "${MSG:-Ошибка смены пароля}" '{ok: false, error: $e}'
    fi
}

_cmd_update_check() {
    if [ ! -d "${GATEWAY_DIR}/.git" ] || ! command -v git >/dev/null 2>&1; then
        jq -cn '{ok: true, status: "NO_GIT", behind: 0, current_sha: "Standalone", branch: "main", commits: []}'
        return 0
    fi
    CUR_BR=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" branch --show-current 2>/dev/null || echo "main")
    [ -z "$CUR_BR" ] && CUR_BR="main"
    CUR_SHA=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo "HEAD")

    check_gateway_repo_updates "force" >/dev/null 2>&1 || true
    STAT="UP_TO_DATE"
    BEHIND=0
    [ -f /tmp/gateway_update_check.cache ] && IFS='|' read -r STAT BEHIND _ _ < /tmp/gateway_update_check.cache 2>/dev/null || true
    COMMITS_JSON='[]'
    if [ "$STAT" = "UPDATE_AVAILABLE" ]; then
        COMMITS_JSON=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" log --oneline -n 10 "HEAD..origin/${CUR_BR}" 2>/dev/null | jq -Rn '[inputs | select(length > 0)]' 2>/dev/null || echo '[]')
    fi
    jq -cn \
        --arg status "$STAT" --argjson behind "${BEHIND:-0}" \
        --arg sha "$CUR_SHA" --arg branch "$CUR_BR" \
        --argjson commits "$COMMITS_JSON" \
        '{ok: true, status: $status, behind: $behind, current_sha: $sha, branch: $branch, commits: $commits}'
}

_cmd_get_logs() {
    TGT=$(_jq_arg "target")
    LINES=$(_jq_arg "lines")
    case "$LINES" in ''|*[!0-9]*) LINES=100 ;; esac
    [ "$LINES" -lt 20 ] && LINES=20
    [ "$LINES" -gt 400 ] && LINES=400

    TXT=""
    case "$TGT" in
        core|"")
            LOG_F=$(get_active_core_log)
            if [ -s "$LOG_F" ]; then
                TXT=$(tail -n "$LINES" "$LOG_F" 2>/dev/null | _strip_ansi || true)
            fi
            [ -z "$TXT" ] && TXT="(Лог ядра пока пуст)"
            ;;
        autoupdate)
            if [ -s "$AUTOUPDATE_LOG" ]; then
                TXT=$(tail -n "$LINES" "$AUTOUPDATE_LOG" 2>/dev/null | _strip_ansi || true)
            fi
            [ -z "$TXT" ] && TXT="(Лог автообновления пока пуст)"
            ;;
        check)
            TXT=$(run_gateway_quick_check </dev/null 2>&1 | _strip_ansi)
            ;;
        webui|console|caddy|vaultwarden|forgejo|code|metube|transmission)
            if is_openwrt 2>/dev/null; then
                _json_err "Источник лога ${TGT} доступен только в Alpine Linux"; return 0
            fi
            _lf=""
            case "$TGT" in
                webui)        _lf="/var/log/gateway-webui.log" ;;
                console)      _lf="/var/log/gateway-console.log" ;;
                caddy)        _lf="/var/log/caddy.log" ;;
                vaultwarden)  _lf="/var/log/vaultwarden.log" ;;
                code)         _lf="/var/log/code-server.log" ;;
                metube)       _lf="/var/log/metube.log" ;;
                transmission) _lf="/var/log/transmission/transmission.log"
                              [ -f "$_lf" ] || _lf="/var/log/transmission.log" ;;
                forgejo)      _lf="/var/log/forgejo/forgejo.log"
                              if [ ! -f "$_lf" ] && [ -d /var/log/forgejo ]; then
                                  _lf=$(ls -1t /var/log/forgejo/*.log 2>/dev/null | head -n 1 || true)
                              fi ;;
            esac
            if [ -n "$_lf" ] && [ -f "$_lf" ]; then
                TXT=$(tail -n "$LINES" "$_lf" 2>/dev/null | _strip_ansi)
                [ -z "$TXT" ] && TXT="(Файл лога пуст: ${_lf})"
            elif [ "$TGT" = "forgejo" ] && [ -f /var/log/messages ]; then
                TXT=$(grep -i forgejo /var/log/messages 2>/dev/null | tail -n "$LINES" | _strip_ansi || true)
                [ -z "$TXT" ] && TXT="(Лог Forgejo пока пуст)"
            else
                TXT="(Лог-файл ${_lf:-$TGT} не найден)"
            fi
            ;;
        *)
            _json_err "Неизвестный источник лога: ${TGT}"; return 0 ;;
    esac
    jq -cn --arg log "$TXT" '{ok: true, log: $log}'
}

_cmd_lxc_autostart() {
    is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
    CT_NAME=$(_jq_arg "name")
    EN_IN=$(_jq_arg "enabled")
    _is_safe_id "$CT_NAME" || { _json_err "Некорректное имя контейнера"; return 0; }
    _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
    [ -f "${_real_path}/${CT_NAME}/config" ] || { _json_err "Контейнер ${CT_NAME} не найден"; return 0; }
    _mode="off"
    case "$EN_IN" in
        on|yes|true|1) _mode="on" ;;
    esac
    if lxc_control "autostart" "$CT_NAME" "$_mode" >/dev/null 2>&1; then
        jq -cn --arg name "$CT_NAME" --argjson autostart "$([ "$_mode" = "on" ] && echo true || echo false)" \
            '{ok: true, name: $name, autostart: $autostart}'
    else
        _json_err "Не удалось изменить автозапуск для ${CT_NAME}"
    fi
}

_cmd_lxc_templates() {
    is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
    FORCE_T=$(_jq_arg "force")
    LXC_ARCH=$(get_lxc_system_arch 2>/dev/null || echo "amd64")
    CACHE_T="/tmp/lxc_web_catalog_${LXC_ARCH}.tsv"
    SRC_LBL="images.linuxcontainers.org"

    NEED_FETCH="no"
    if [ "$FORCE_T" = "yes" ] || [ "$FORCE_T" = "true" ] || [ ! -s "$CACHE_T" ]; then
        NEED_FETCH="yes"
    elif [ -n "$(find "$CACHE_T" -mmin +60 2>/dev/null || true)" ]; then
        NEED_FETCH="yes"
    fi

    if [ "$NEED_FETCH" = "yes" ]; then
        _tmp_idx="/tmp/lxc_idx_raw.$$"
        if curl -fsS --connect-timeout 8 -m 15 "https://images.linuxcontainers.org/meta/1.0/index-system" 2>/dev/null | \
            awk -F';' -v a="$LXC_ARCH" '($3 == a && NF >= 4 && $1 != "" && $2 != "") { v = ($4 != "" ? $4 : "default"); b = ($5 != "" ? $5 : ""); print $1 "\t" $2 "\t" v "\t" b }' | \
            sort -u > "$_tmp_idx" 2>/dev/null && [ -s "$_tmp_idx" ]; then
            mv -f "$_tmp_idx" "$CACHE_T"
        else
            rm -f "$_tmp_idx" 2>/dev/null || true
            SRC_LBL="fallback"
        fi
    fi

    if [ ! -s "$CACHE_T" ]; then
        SRC_LBL="fallback"
        cat << 'FB_CAT' > "$CACHE_T"
almalinux	9	default	offline
alpine	3.21	default	offline
alpine	3.22	default	offline
alpine	3.23	default	offline
alpine	3.24	default	offline
alpine	edge	default	offline
archlinux	current	default	offline
debian	bookworm	default	offline
debian	trixie	default	offline
fedora	43	default	offline
kali	current	default	offline
rockylinux	9	default	offline
ubuntu	jammy	default	offline
ubuntu	noble	default	offline
FB_CAT
    fi

    TMPLS_JSON=$(jq -Rn '
        [inputs | select(length > 0) | split("\t") | {
            distro: .[0],
            release: .[1],
            variant: .[2],
            build: (.[3] // "")
        }]
    ' < "$CACHE_T" 2>/dev/null || echo '[]')
    TOT=$(printf "%s" "$TMPLS_JSON" | jq 'length' 2>/dev/null || echo 0)
    UPD_AT=$(date -r "$CACHE_T" '+%Y-%m-%d %H:%M' 2>/dev/null || date '+%Y-%m-%d %H:%M')
    jq -cn \
        --arg arch "$LXC_ARCH" \
        --arg source "$SRC_LBL" \
        --arg updated_at "$UPD_AT" \
        --argjson total "$TOT" \
        --argjson templates "$TMPLS_JSON" \
        '{ok: true, arch: $arch, source: $source, updated_at: $updated_at, total: $total, templates: $templates}'
}

_cmd_lxc_console_token() {
    is_openwrt 2>/dev/null && { _json_err "Веб-консоль доступна только в Alpine Linux"; return 0; }
    CT_NAME=$(_jq_arg "name")
    _is_safe_id "$CT_NAME" || { _json_err "Некорректное имя контейнера"; return 0; }
    if ! lxc-info -n "$CT_NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
        _json_err "Контейнер ${CT_NAME} остановлен — сначала запустите его"; return 0
    fi
    if ! command -v ttyd >/dev/null 2>&1; then
        _json_err "Пакет ttyd не установлен (выполните: apk add ttyd && gw update)"; return 0
    fi
    if [ ! -L /run/openrc/started/gateway-console ] && ! pgrep ttyd >/dev/null 2>&1; then
        [ -x /etc/init.d/gateway-console ] && rc-service gateway-console start >/dev/null 2>&1 || true
        sleep 1
    fi
    if [ ! -L /run/openrc/started/gateway-console ] && ! pgrep ttyd >/dev/null 2>&1; then
        _json_err "Служба веб-консоли gateway-console не запущена"; return 0
    fi

    # Очистка просроченных токенов старше 120 сек
    find /tmp -maxdepth 1 -name 'gw_console_tok_*' -mmin +2 -delete 2>/dev/null || true

    TOK=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -dc '0-9a-f' | head -c 32 || true)
    [ "${#TOK}" -ne 32 ] && { _json_err "Не удалось сгенерировать токен консоли"; return 0; }
    EXP_TS=$(( $(date +%s 2>/dev/null || echo 0) + 60 ))
    (
        umask 077
        printf "%s|%s\n" "$CT_NAME" "$EXP_TS" > "/tmp/gw_console_tok_${TOK}"
    )
    jq -cn --arg token "$TOK" --arg url "/console/?arg=${TOK}" '{ok: true, token: $token, url: $url}'
}

_cmd_lxc_exec() {
    is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
    CT_NAME=$(_jq_arg "name")
    CMD_STR=$(_jq_arg "cmd")
    _is_safe_id "$CT_NAME" || { _json_err "Некорректное имя контейнера"; return 0; }
    [ -z "$(printf "%s" "$CMD_STR" | tr -d ' \t\r\n')" ] && { _json_err "Введите команду для выполнения"; return 0; }
    [ "${#CMD_STR}" -gt 2000 ] && { _json_err "Команда слишком длинная (макс. 2000 символов)"; return 0; }
    if ! lxc-info -n "$CT_NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
        _json_err "Контейнер ${CT_NAME} не запущен"; return 0
    fi
    _exec_f="/tmp/gw_lxc_exec.$$"
    _rc=0
    timeout 20 lxc-attach -n "$CT_NAME" -- /bin/sh -c "$CMD_STR" </dev/null >"$_exec_f" 2>&1 || _rc=$?
    _out=$(head -c 16000 "$_exec_f" 2>/dev/null | _strip_ansi || true)
    rm -f "$_exec_f" 2>/dev/null || true
    jq -cn --argjson exit_code "$_rc" --arg output "$_out" '{ok: true, exit_code: $exit_code, output: $output}'
}

_cmd_lxc_config() {
    is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
    CT_NAME=$(_jq_arg "name")
    _is_safe_id "$CT_NAME" || { _json_err "Некорректное имя контейнера"; return 0; }
    _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
    [ -f "${_real_path}/${CT_NAME}/config" ] || { _json_err "Контейнер ${CT_NAME} не найден"; return 0; }

    MEM_IN=$(_jq_arg "mem_limit" | tr -d ' \t\r\n')
    CPU_IN=$(_jq_arg "cpu_limit" | tr -d ' \t\r\n')
    AUTO_IN=$(_jq_arg "autostart")
    NEST_IN=$(_jq_arg "nesting")
    STOR_IN=$(_jq_arg "storage_mount")
    RPASS_IN=$(_jq_arg "root_pass" | tr -d '\r\n')
    RESTART_IN=$(_jq_arg "restart")

    case "$MEM_IN" in
        ""|none|0) MEM_VAL="none" ;;
        *[KkMmGg])
            case "$MEM_IN" in
                *[!0-9KkMmGg]*) _json_err "Некорректный лимит ОЗУ (пример: 512M, 2G)"; return 0 ;;
                *) MEM_VAL="$MEM_IN" ;;
            esac
            ;;
        *[!0-9]*) _json_err "Некорректный лимит ОЗУ (пример: 512M, 2G)"; return 0 ;;
        *) MEM_VAL="${MEM_IN}M" ;;
    esac

    case "$CPU_IN" in
        ""|none|0) CPU_VAL="none" ;;
        *)
            if printf "%s" "$CPU_IN" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
                CPU_VAL="$CPU_IN"
            else
                _json_err "Некорректный лимит CPU (пример: 1, 2, 0.5)"; return 0
            fi
            ;;
    esac

    AUTO_VAL="__KEEP__"
    [ -n "$AUTO_IN" ] && { case "$AUTO_IN" in on|yes|true|1) AUTO_VAL="yes" ;; *) AUTO_VAL="no" ;; esac; }
    NEST_VAL="__KEEP__"
    [ -n "$NEST_IN" ] && { case "$NEST_IN" in on|yes|true|1) NEST_VAL="yes" ;; *) NEST_VAL="no" ;; esac; }
    STOR_VAL="__KEEP__"
    [ -n "$STOR_IN" ] && { case "$STOR_IN" in on|yes|true|1) STOR_VAL="yes" ;; *) STOR_VAL="no" ;; esac; }

    if ! lxc_apply_config_updates "$CT_NAME" "$MEM_VAL" "$CPU_VAL" "$AUTO_VAL" "$NEST_VAL" "$STOR_VAL" >/dev/null 2>&1; then
        _json_err "Не удалось обновить конфигурацию ${CT_NAME}"; return 0
    fi

    if [ -n "$RPASS_IN" ]; then
        if lxc-info -n "$CT_NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
            printf "root:%s\n" "$RPASS_IN" | lxc-attach -n "$CT_NAME" -- chpasswd >/dev/null 2>&1 || true
        elif [ -d "${_real_path}/${CT_NAME}/rootfs" ]; then
            printf "root:%s\n" "$RPASS_IN" | chroot "${_real_path}/${CT_NAME}/rootfs" /usr/sbin/chpasswd >/dev/null 2>&1 || \
            printf "root:%s\n" "$RPASS_IN" | chroot "${_real_path}/${CT_NAME}/rootfs" /sbin/chpasswd >/dev/null 2>&1 || true
        fi
    fi

    if [ "$RESTART_IN" = "yes" ] || [ "$RESTART_IN" = "true" ]; then
        if lxc-info -n "$CT_NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
            lxc-stop -n "$CT_NAME" -t 5 >/dev/null 2>&1 || lxc-stop -n "$CT_NAME" -k >/dev/null 2>&1 || true
            sleep 1
            lxc-start -n "$CT_NAME" >/dev/null 2>&1 || true
        fi
    fi
    jq -cn --arg name "$CT_NAME" '{ok: true, name: $name, message: "Настройки контейнера обновлены"}'
}

_cmd_storage_clean_cache() {
    is_openwrt 2>/dev/null && { _json_err "Очистка кэша хранилища доступна только в Alpine Linux"; return 0; }
    rm -rf "${STORAGE_INC_TORRENTS:?}/"* "${STORAGE_INC_YTDLP:?}/"* "${STORAGE_INCOMPLETE:?}/metube/"* 2>/dev/null || true
    sync_all_homelab_permissions >/dev/null 2>&1 || true
    jq -cn '{ok: true, message: "Временные буферы загрузок очищены, права доступа синхронизированы"}'
}

_cmd_job_start() {
    ACT=$(_jq_arg "action")
    A1=$(_jq_arg "arg1")
    A2=$(_jq_arg "arg2")

    if [ -f /tmp/gw_luci_current.id ]; then
        OLD_ID=$(cat /tmp/gw_luci_current.id 2>/dev/null | tr -dc 'A-Za-z0-9_-' || true)
        if [ -n "$OLD_ID" ] && _is_job_running "$OLD_ID"; then
            jq -cn --arg id "$OLD_ID" '{ok: false, running_id: $id, error: "Уже выполняется фоновая операция"}'
            return 0
        fi
    fi

    # Валидация параметров строго по белому списку
    CMD_BODY=""
    case "$ACT" in
        restart)
            CMD_BODY='backup_gateway_state && load_gateway_env && if apply_and_verify_core "Перезапуск шлюза"; then conntrack -F >/dev/null 2>&1 || true; service_ctl adguardhome restart || true; fi'
            ;;
        doctor)
            CMD_BODY='run_gateway_doctor'
            ;;
        apply_core)
            CMD_BODY='backup_gateway_state && load_gateway_env && if apply_and_verify_core "Применение конфигурации"; then conntrack -F >/dev/null 2>&1 || true; fi'
            ;;
        set_core)
            case "$A1" in
                singbox|mihomo) CMD_BODY="switch_core_engine '${A1}'" ;;
                *) _json_err "Недопустимое ядро: ${A1}"; return 0 ;;
            esac
            ;;
        set_ui)
            case "$A1" in
                zashboard|metacubexd) CMD_BODY="switch_web_ui '${A1}'" ;;
                *) _json_err "Недопустимая панель: ${A1}"; return 0 ;;
            esac
            ;;
        warp_generate)
            case "$A1" in
                *[!A-Za-z0-9_-]*) _json_err "Недопустимые символы в ключе WARP+"; return 0 ;;
            esac
            CMD_BODY="generate_amnezia_warp '${A1}' && apply_and_verify_core 'Активация Amnezia WARP'"
            ;;
        warp_disable)
            CMD_BODY='echo '\''{"outbounds": []}'\'' > "$WARP_NODES_FILE" && apply_and_verify_core "Отключение WARP 2.0"'
            ;;
        backup_create)
            CMD_BODY='create_unified_backup "no"'
            ;;
        backup_telegram)
            CMD_BODY='create_unified_backup "no" && send_telegram_backup "$BACKUP_ARCHIVE"'
            ;;
        backup_restore)
            CMD_BODY='restore_unified_backup'
            ;;
        update)
            CMD_BODY='exec /usr/bin/gw update </dev/null'
            ;;
        homelab_action)
            is_openwrt 2>/dev/null && { _json_err "Модули Homelab доступны только в Alpine Linux"; return 0; }
            case "$A1" in
                caddy|samba|vaultwarden|forgejo|code|ytdlp|torrent) ;;
                *) _json_err "Неизвестный модуль Homelab: ${A1}"; return 0 ;;
            esac
            case "$A2" in
                start|stop|restart|remove|update)
                    if [ "$A1" = "caddy" ] && [ "$A2" = "remove" ]; then
                        CMD_BODY="homelab_module_dispatch '${A1}' '${A2}' && install_alpine_webui >/dev/null 2>&1 || true"
                    else
                        CMD_BODY="homelab_module_dispatch '${A1}' '${A2}'"
                    fi
                    ;;
                install)
                    if [ "$A1" = "samba" ]; then
                        CMD_BODY="install_module_samba 'auto'"
                    elif [ "$A1" = "caddy" ]; then
                        CMD_BODY="homelab_module_dispatch 'caddy' 'install' && install_alpine_webui"
                    else
                        CMD_BODY="homelab_module_dispatch '${A1}' 'install'"
                    fi
                    ;;
                *)
                    _json_err "Неизвестное действие Homelab: ${A2}"; return 0 ;;
            esac
            ;;
        lxc_action)
            is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
            _is_safe_id "$A1" || { _json_err "Некорректное имя контейнера: ${A1}"; return 0; }
            _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
            [ -f "${_real_path}/${A1}/config" ] || { _json_err "Контейнер ${A1} не найден"; return 0; }
            case "$A2" in
                start|restart|fix-net)
                    CMD_BODY="lxc_control '${A2}' '${A1}'; _rc=\$?; if [ \$_rc -eq 0 ] && lxc-info -n '${A1}' 2>/dev/null | grep -q 'State:.*RUNNING'; then for _w in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do lxc-info -n '${A1}' -iH 2>/dev/null | grep -q '[0-9][.][0-9]' && break; sleep 1; done; fi; (exit \$_rc)"
                    ;;
                stop)
                    CMD_BODY="lxc_control 'stop' '${A1}'"
                    ;;
                snap_create)
                    CMD_BODY="lxc_manage_snapshots '${A1}' 'create'"
                    ;;
                snap_restore:*)
                    _sn="${A2#snap_restore:}"
                    _is_safe_id "$_sn" || { _json_err "Некорректное имя снимка"; return 0; }
                    [ -d "${_real_path}/${A1}/snaps/${_sn}" ] || { _json_err "Снимок ${_sn} не найден"; return 0; }
                    CMD_BODY="echo '[*] Восстановление ${A1} из снимка ${_sn}...' && lxc-stop -n '${A1}' -k 2>/dev/null || true; sleep 1; if lxc-snapshot -n '${A1}' -r '${_sn}'; then lxc-start -n '${A1}' && for _w in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do lxc-info -n '${A1}' -iH 2>/dev/null | grep -q '[0-9][.][0-9]' && break; sleep 1; done && echo '[✓] Контейнер ${A1} восстановлен из ${_sn} и запущен.'; else echo '[X] Ошибка восстановления снимка ${_sn}' >&2; false; fi"
                    ;;
                snap_delete:*)
                    _sn="${A2#snap_delete:}"
                    _is_safe_id "$_sn" || { _json_err "Некорректное имя снимка"; return 0; }
                    [ -d "${_real_path}/${A1}/snaps/${_sn}" ] || { _json_err "Снимок ${_sn} не найден"; return 0; }
                    CMD_BODY="lxc-snapshot -n '${A1}' -d '${_sn}' && echo '[✓] Снимок ${_sn} удален.'"
                    ;;
                *)
                    _json_err "Неизвестное действие LXC: ${A2}"; return 0 ;;
            esac
            ;;
        lxc_create)
            is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
            if ! printf "%s" "$A1" | jq -e '.name != null and .distro != null and .release != null' >/dev/null 2>&1; then
                _json_err "Некорректная спецификация контейнера"; return 0
            fi
            _spec_name=$(printf "%s" "$A1" | jq -r '.name // empty' 2>/dev/null || true)
            _is_safe_id "$_spec_name" || { _json_err "Некорректное имя контейнера (латиница, цифры, - и _)"; return 0; }
            _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
            [ -e "${_real_path}/${_spec_name}" ] && { _json_err "Контейнер ${_spec_name} уже существует"; return 0; }
            ;;
        lxc_clone)
            is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
            _is_safe_id "$A1" || { _json_err "Некорректное имя исходного контейнера"; return 0; }
            _is_safe_id "$A2" || { _json_err "Некорректное имя клона (латиница, цифры, - и _)"; return 0; }
            _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
            [ -f "${_real_path}/${A1}/config" ] || { _json_err "Контейнер ${A1} не найден"; return 0; }
            [ -e "${_real_path}/${A2}" ] && { _json_err "Контейнер ${A2} уже существует"; return 0; }
            CMD_BODY="echo '[*] Клонирование контейнера ${A1} -> ${A2}...' && _was_run='no' && if lxc-info -n '${A1}' 2>/dev/null | grep -q 'State:.*RUNNING'; then _was_run='yes'; lxc-stop -n '${A1}' -t 10 || lxc-stop -n '${A1}' -k || true; fi && if lxc-copy -n '${A1}' -N '${A2}'; then _new_mac=\"10:66:6a:\$(hexdump -n 3 -e '/1 \":%02x\"' /dev/urandom 2>/dev/null | cut -c 2- || echo '22:33:44')\"; sed -i \"s|^lxc\\.net\\.0\\.hwaddr.*|lxc.net.0.hwaddr = \${_new_mac}|\" '${_real_path}/${A2}/config' 2>/dev/null || true; [ -f '${_real_path}/${A1}/.gw_os' ] && cp -f '${_real_path}/${A1}/.gw_os' '${_real_path}/${A2}/.gw_os' 2>/dev/null || true; [ \"\$_was_run\" = 'yes' ] && lxc-start -n '${A1}' 2>/dev/null || true; if lxc-start -n '${A2}' 2>/dev/null; then for _w in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do lxc-info -n '${A2}' -iH 2>/dev/null | grep -q '[0-9][.][0-9]' && break; sleep 1; done; fi; echo '[✓] Клон ${A2} успешно создан и запущен!'; else [ \"\$_was_run\" = 'yes' ] && lxc-start -n '${A1}' 2>/dev/null || true; echo '[X] Ошибка клонирования ${A1}' >&2; false; fi"
            ;;
        lxc_delete)
            is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
            _is_safe_id "$A1" || { _json_err "Некорректное имя контейнера"; return 0; }
            _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
            [ -f "${_real_path}/${A1}/config" ] || { _json_err "Контейнер ${A1} не найден"; return 0; }
            CMD_BODY="echo '[*] Удаление контейнера ${A1}...' && lxc-stop -n '${A1}' -k 2>/dev/null || true; sleep 1; if lxc-destroy -n '${A1}' -s -f; then echo '[✓] Контейнер ${A1} полностью удалён.'; else echo '[X] Ошибка удаления ${A1}' >&2; false; fi"
            ;;
        lxc_snap_create)
            is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
            _is_safe_id "$A1" || { _json_err "Некорректное имя контейнера"; return 0; }
            _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
            [ -f "${_real_path}/${A1}/config" ] || { _json_err "Контейнер ${A1} не найден"; return 0; }
            ;;
        lxc_doctor)
            is_openwrt 2>/dev/null && { _json_err "LXC доступен только в Alpine Linux"; return 0; }
            CMD_BODY='ensure_lxc_subsystem "no" && check_and_heal_lxc_doctor && echo "[✓] Подсистема LXC (пакеты, cgroups v2, мост lxcbr0, lxcfs) проверена и готова!"'
            ;;
        ssl_local)
            is_openwrt 2>/dev/null && { _json_err "SSL доступен только в Alpine Linux"; return 0; }
            CMD_BODY='switch_to_local_pki'
            ;;
        ssl_renew)
            is_openwrt 2>/dev/null && { _json_err "SSL доступен только в Alpine Linux"; return 0; }
            CMD_BODY='renew_duckdns_cert_force'
            ;;
        ssl_duckdns)
            is_openwrt 2>/dev/null && { _json_err "SSL доступен только в Alpine Linux"; return 0; }
            case "$A1" in
                ""|*[!A-Za-z0-9.-]*) _json_err "Некорректный субдомен DuckDNS"; return 0 ;;
            esac
            if [ -n "$A2" ]; then
                case "$A2" in
                    *[!A-Za-z0-9-]*) _json_err "Недопустимые символы в токене DuckDNS"; return 0 ;;
                esac
            else
                [ -z "${DUCKDNS_TOKEN:-}" ] && { _json_err "Укажите токен DuckDNS"; return 0; }
            fi
            # Не печатаем токен в аргументах/логах: берем переданный или сохраненный
            CMD_BODY="_tok='${A2}'; [ -z \"\$_tok\" ] && _tok=\"\${DUCKDNS_TOKEN:-}\"; issue_duckdns_cert '${A1}' \"\$_tok\""
            ;;
        storage_lock)
            is_openwrt 2>/dev/null && { _json_err "Хранилище доступно только в Alpine Linux"; return 0; }
            CMD_BODY='unmount_external_storage_safe'
            ;;
        storage_unlock)
            is_openwrt 2>/dev/null && { _json_err "Хранилище доступно только в Alpine Linux"; return 0; }
            CMD_BODY='if is_external_storage_mounted; then echo "[✓] Внешний накопитель уже разблокирован и смонтирован."; elif try_auto_unlock_and_mount_storage "yes" && is_external_storage_mounted; then echo "[✓] Накопитель LUKS2 разблокирован ключевым файлом и смонтирован; службы Homelab запущены."; else echo "[X] Требуется ручной ввод пароля LUKS2 — выполните по SSH: gw unlock" >&2; false; fi'
            ;;
        *)
            _json_err "Неизвестное задание: ${ACT}"; return 0 ;;
    esac

    ls -1t /tmp/gw_luci_job_*.rc 2>/dev/null | awk 'NR>3' | while IFS= read -r old_rc; do
        _b="${old_rc%.rc}"
        rm -f "${_b}.rc" "${_b}.log" "${_b}.pid" "${_b}.sh" "${_b}.starting" 2>/dev/null || true
    done

    JOB_ID="j_$(date +%s)_$$"
    JOB_BASE="/tmp/gw_luci_job_${JOB_ID}"
    printf "%s\n" "$JOB_ID" > /tmp/gw_luci_current.id

    if [ "$ACT" = "lxc_create" ]; then
        _spec_f="/tmp/gw_lxc_spec_${JOB_ID}.json"
        (
            umask 077
            printf "%s\n" "$A1" > "$_spec_f"
        )
        CMD_BODY="lxc_create_from_spec '${_spec_f}'; _cr_rc=\$?; rm -f '${_spec_f}' 2>/dev/null || true; (exit \$_cr_rc)"
    elif [ "$ACT" = "lxc_snap_create" ]; then
        _real_path=$(readlink -f "${LXC_VAR_LIB:-/var/lib/lxc}" 2>/dev/null || echo "${LXC_VAR_LIB:-/var/lib/lxc}")
        _scom_f="/tmp/gw_lxc_scom_${JOB_ID}.txt"
        printf "%s" "$A2" | tr -d '\r\n\t' | cut -c1-120 > "$_scom_f"
        CMD_BODY="_bef=''; [ -d '${_real_path}/${A1}/snaps' ] && _bef=\$(ls -1 '${_real_path}/${A1}/snaps' 2>/dev/null | tr '\n' ' '); lxc_manage_snapshots '${A1}' 'create'; _sn_rc=\$?; if [ \$_sn_rc -eq 0 ] && [ -s '${_scom_f}' ] && [ -d '${_real_path}/${A1}/snaps' ]; then _new_s=\$(ls -1t '${_real_path}/${A1}/snaps' 2>/dev/null | while IFS= read -r _s; do case \" \${_bef} \" in *\" \${_s} \"*) ;; *) printf '%s' \"\$_s\"; break ;; esac; done); [ -n \"\$_new_s\" ] && cp -f '${_scom_f}' \"${_real_path}/${A1}/snaps/\${_new_s}/comment\" 2>/dev/null || true; fi; if [ \$_sn_rc -eq 0 ] && lxc-info -n '${A1}' 2>/dev/null | grep -q 'State:.*RUNNING'; then for _w in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do lxc-info -n '${A1}' -iH 2>/dev/null | grep -q '[0-9][.][0-9]' && break; sleep 1; done; fi; rm -f '${_scom_f}' 2>/dev/null || true; (exit \$_sn_rc)"
    fi

    if [ "$ACT" = "update" ]; then
        cat << JOB_UPD > "${JOB_BASE}.sh"
#!/bin/sh
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export NO_COLOR=1
exec </dev/null >"${JOB_BASE}.log" 2>&1
echo "\$\$" > "${JOB_BASE}.pid"
rm -f "${JOB_BASE}.starting" 2>/dev/null || true
/usr/bin/gw update </dev/null
_rc=\$?
printf "%s\n" "\$_rc" > "${JOB_BASE}.rc"
rm -f "${JOB_BASE}.pid" "${JOB_BASE}.sh" "${JOB_BASE}.starting" 2>/dev/null || true
JOB_UPD
    else
        cat << JOB_EOF > "${JOB_BASE}.sh"
#!/bin/sh
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export GATEWAY_NO_RUN=1
export GATEWAY_DIR="${GATEWAY_DIR}"
export NO_COLOR=1
exec </dev/null >"${JOB_BASE}.log" 2>&1
echo "\$\$" > "${JOB_BASE}.pid"
rm -f "${JOB_BASE}.starting" 2>/dev/null || true
. "${GATEWAY_DIR}/gateway.sh"
set +e
detect_os >/dev/null 2>&1 || true
load_gateway_env >/dev/null 2>&1 || true
_rc=0
{ ${CMD_BODY}; } || _rc=\$?
printf "%s\n" "\$_rc" > "${JOB_BASE}.rc"
rm -f "${JOB_BASE}.pid" "${JOB_BASE}.sh" "${JOB_BASE}.starting" 2>/dev/null || true
JOB_EOF
    fi
    chmod 700 "${JOB_BASE}.sh"
    : > "${JOB_BASE}.log"
    : > "${JOB_BASE}.starting"
    if command -v setsid >/dev/null 2>&1; then
        setsid /bin/sh "${JOB_BASE}.sh" </dev/null >/dev/null 2>&1 &
    else
        ( /bin/sh "${JOB_BASE}.sh" ) </dev/null >/dev/null 2>&1 &
    fi
    jq -cn --arg id "$JOB_ID" '{ok: true, id: $id}'
}

_cmd_job_poll() {
    JOB_ID=$(_jq_arg "id")
    _is_safe_id "$JOB_ID" || { _json_err "Некорректный ID задания"; return 0; }
    JOB_BASE="/tmp/gw_luci_job_${JOB_ID}"
    if [ ! -f "${JOB_BASE}.log" ] && [ ! -f "${JOB_BASE}.pid" ] && [ ! -f "${JOB_BASE}.rc" ]; then
        _json_err "Задание не найдено"
        return 0
    fi
    RUN="false"
    RC=-1
    if [ -f "${JOB_BASE}.rc" ]; then
        RC=$(cat "${JOB_BASE}.rc" 2>/dev/null | tr -dc '0-9-' || echo 1)
        [ -z "$RC" ] && RC=1
    elif _is_job_running "$JOB_ID"; then
        RUN="true"
    else
        RC=1
    fi
    LOG_TXT=""
    [ -f "${JOB_BASE}.log" ] && LOG_TXT=$(tail -n 250 "${JOB_BASE}.log" 2>/dev/null | _strip_ansi)
    jq -cn --arg id "$JOB_ID" --argjson running "$RUN" --argjson exit_code "$RC" --arg log "$LOG_TXT" \
        '{ok: true, id: $id, running: $running, exit_code: $exit_code, log: $log}'
}

case "$METHOD" in
    status)              _cmd_status ;;
    trace)               _cmd_trace ;;
    domain_inspect)      _cmd_domain_inspect ;;
    set_dhcp)            _cmd_set_dhcp ;;
    set_killswitch)      _cmd_set_killswitch ;;
    set_cron)            _cmd_set_cron ;;
    set_network)         _cmd_set_network ;;
    set_subscription)    _cmd_set_subscription ;;
    node_add)            _cmd_node_add ;;
    node_delete)         _cmd_node_delete ;;
    domain_rule)         _cmd_domain_rule ;;
    device_rule)         _cmd_device_rule ;;
    set_telegram)        _cmd_set_telegram ;;
    set_password)        _cmd_set_password ;;
    update_check)        _cmd_update_check ;;
    get_logs)            _cmd_get_logs ;;
    lxc_autostart)       _cmd_lxc_autostart ;;
    lxc_templates)       _cmd_lxc_templates ;;
    lxc_console_token)   _cmd_lxc_console_token ;;
    lxc_exec)            _cmd_lxc_exec ;;
    lxc_config)          _cmd_lxc_config ;;
    storage_clean_cache) _cmd_storage_clean_cache ;;
    job_start)           _cmd_job_start ;;
    job_poll)            _cmd_job_poll ;;
    *)                   _json_err "Неизвестный метод: ${METHOD}" ;;
esac
