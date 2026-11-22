#!/bin/sh
change_unified_password() {
    NEW_PASS=$(printf "%s" "$1" | tr -d '\r\n')
    SYNC_SMB_ANS="${2:-ask}"
    if [ -z "$NEW_PASS" ]; then
        echo "${C_RED}[X] Ошибка: Пароль не может быть пустым!${C_RES}"
        return 1
    fi
    load_gateway_env
    OLD_ADMIN_PASS="${ADMIN_PASS:-}"
    OLD_SMB_PASS="${SMB_PASS:-}"

    ADMIN_PASS="$NEW_PASS"
    if [ "$SYNC_SMB_ANS" = "yes" ] || [ -z "$OLD_SMB_PASS" ] || [ "$OLD_SMB_PASS" = "$OLD_ADMIN_PASS" ]; then
        SMB_PASS="$NEW_PASS"
    elif [ "$SYNC_SMB_ANS" = "ask" ] && [ -t 0 ]; then
        printf "Обновить также пароль сетевой папки Samba для пользователя '%s'? (y/n) [Enter = y]: " "${SMB_USER:-homelab}"
        read -r IN_SYNC_SMB < /dev/tty || true
        IN_SYNC_SMB=$(printf "%s" "$IN_SYNC_SMB" | tr -d ' \t\r\n')
        [ -z "$IN_SYNC_SMB" ] && IN_SYNC_SMB="y"
        case "$IN_SYNC_SMB" in
            [Yy]|[Yy][Ee][Ss]|[Дд]|[Дд][Аа]) SMB_PASS="$NEW_PASS" ;;
        esac
    fi

    detect_os >/dev/null 2>&1 || true

    CUR_AGH_USER=""
    NEW_HASH=""
    if [ -f "$AGH_CONF" ]; then
        if ! command -v htpasswd >/dev/null 2>&1 && [ ! -x /usr/sbin/caddy ]; then
            if is_openwrt; then
                apk add apache-utils >/dev/null 2>&1 || true
            else
                apk add --no-cache apache2-utils >/dev/null 2>&1 || true
            fi
            disable_apache_daemon
        fi
        CUR_AGH_USER=$(get_agh_admin_user)
        [ -z "$CUR_AGH_USER" ] && CUR_AGH_USER="${AGH_USER:-admin}" || true
        if command -v htpasswd >/dev/null 2>&1; then
            NEW_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$CUR_AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        elif [ -x /usr/sbin/caddy ]; then
            NEW_HASH=$(/usr/sbin/caddy hash-password --plaintext "$ADMIN_PASS" 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)
        fi
        if [ -z "$NEW_HASH" ]; then
            echo "${C_RED}[X] Ошибка: Не удалось вычислить bcrypt-хэш для AdGuard Home — пароль не изменен!${C_RES}"
            return 1
        fi
    fi

    save_gateway_env
    if ! is_openwrt; then
        save_homelab_env
    fi
    core_generate_config

    service_ctl adguardhome stop
    if [ -f "$AGH_CONF" ] && [ -n "$NEW_HASH" ]; then
        CUR_AGH_USER="$CUR_AGH_USER" NEW_HASH="$NEW_HASH" awk '
            BEGIN {
                u = ENVIRON["CUR_AGH_USER"];
                h = ENVIRON["NEW_HASH"];
            }
            /^users:/ {
                print "users:"
                print "  - name: " u
                print "    password: " h
                in_users=1; next
            }
            in_users && /^[^[:space:]]/ { in_users=0 }
            in_users { next }
            { print }
        ' "$AGH_CONF" > "${AGH_CONF}.tmp.$$" 2>/dev/null || true
        atomic_commit_tmp "${AGH_CONF}.tmp.$$" "$AGH_CONF" 0600 "root:root" || {
            echo "${C_RED}[X] Ошибка записи ${AGH_CONF}!${C_RES}"
            service_ctl adguardhome start >/dev/null 2>&1 || true
            return 1
        }
    fi

    if ! is_openwrt; then
        # Синхронизация и верификация пароля Samba
        if command -v smbpasswd >/dev/null 2>&1; then
            if ! apply_and_verify_samba_password "${SMB_USER:-homelab}" "${SMB_PASS:-$ADMIN_PASS}"; then
                echo "${C_YEL}[!] Предупреждение: Не удалось подтвердить обновление записи Samba passdb для ${SMB_USER:-homelab}.${C_RES}"
            fi
        fi

        # Синхронизация ADMIN_TOKEN в Vaultwarden (если модуль установлен)
        if [ -f /etc/conf.d/vaultwarden ] || is_module_enabled "vaultwarden"; then
            sync_vaultwarden_config >/dev/null 2>&1 || true
            is_module_enabled "vaultwarden" && service_ctl vaultwarden restart || true
        fi

        # Синхронизация RPC-пароля в Transmission (если модуль установлен)
        TR_SETTINGS_FILE="/var/lib/transmission/config/settings.json"
        if [ -f "$TR_SETTINGS_FILE" ] || is_module_enabled "torrent"; then
            TR_USER="${SMB_USER:-${AGH_USER:-admin}}"
            TR_PASS="${ADMIN_PASS:-admin}"
            service_ctl transmission-daemon stop >/dev/null 2>&1 || true
            if [ -f "$TR_SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
                if jq --arg u "$TR_USER" --arg p "$TR_PASS" '.["rpc-username"] = $u | .["rpc-password"] = $p' "$TR_SETTINGS_FILE" > "${TR_SETTINGS_FILE}.tmp.$$" 2>/dev/null; then
                    mv -f "${TR_SETTINGS_FILE}.tmp.$$" "$TR_SETTINGS_FILE"
                    chmod 600 "$TR_SETTINGS_FILE" 2>/dev/null || true
                    chown "transmission:${MEDIA_GROUP:-media}" "$TR_SETTINGS_FILE" 2>/dev/null || true
                else
                    rm -f "${TR_SETTINGS_FILE}.tmp.$$" 2>/dev/null || true
                fi
            fi
            if is_module_enabled "torrent"; then
                service_ctl transmission-daemon start >/dev/null 2>&1 || true
            fi
        fi

        # Синхронизация BasicAuth в Caddy для защищенных модулей
        if [ -x /usr/sbin/caddy ] && [ -d "$CADDY_CONFD" ] && is_module_enabled "caddy"; then
            is_module_enabled "ytdlp" && register_caddy_site "ytdlp" "$DOM_YTDLP" "$PORT_YTDLP" "yes" >/dev/null 2>&1 || true
            is_module_enabled "torrent" && register_caddy_site "torrent" "$DOM_TORRENT" "$PORT_TORRENT_WEB" "yes" >/dev/null 2>&1 || true
            is_module_enabled "code" && register_caddy_site "code" "$DOM_CODE" "$PORT_CODE" "yes" >/dev/null 2>&1 || true
            [ -x /etc/init.d/gateway-webui ] && register_caddy_site "gateway" "${DOM_GATEWAY:-gateway.lan}" "${PORT_WEBUI:-8095}" "yes" >/dev/null 2>&1 || true
        fi
    fi

    service_ctl "$(get_active_core_service)" restart || true
    service_ctl adguardhome start || true

    PW_IDX=0
    CORE_READY=0
    AGH_READY=0
    while [ "$PW_IDX" -lt 10 ]; do
        CORE_READY=0
        AGH_READY=0
        if clash_api_curl -fsS -m 1 "http://127.0.0.1:9090/configs" >/dev/null 2>&1; then
            CORE_READY=1
        fi
        if pgrep AdGuardHome >/dev/null 2>&1; then
            _agh_u_esc=$(printf "%s" "${CUR_AGH_USER:-${AGH_USER:-admin}}" | sed 's/\\/\\\\/g; s/"/\\"/g')
            _agh_p_esc=$(printf "%s" "${ADMIN_PASS}" | sed 's/\\/\\\\/g; s/"/\\"/g')
            if printf 'user = "%s:%s"\n' "$_agh_u_esc" "$_agh_p_esc" | curl -K - -fsS -m 1 "http://127.0.0.1:3000/control/status" >/dev/null 2>&1; then
                AGH_READY=1
            fi
        fi
        [ "$CORE_READY" -eq 1 ] && [ "$AGH_READY" -eq 1 ] && break
        sleep 1
        PW_IDX=$((PW_IDX + 1))
    done

    if is_sub_enabled && command -v jq >/dev/null 2>&1; then
        _PROV_J=$(clash_api_curl -fsS -m 2 "http://127.0.0.1:9090/providers/proxies" 2>/dev/null || true)
        _EMPTY_SUB=$(printf "%s" "$_PROV_J" | jq -r '[.providers // {} | to_entries[] | select((.value.vehicleType == "Remote" or .value.vehicleType == "HTTP") and ((.value.proxies // []) | length == 0))] | length' 2>/dev/null || echo "0")
        [ "${_EMPTY_SUB:-0}" -gt 0 ] && core_reload_api >/dev/null 2>&1 || true
    fi

    if [ "$CORE_READY" -eq 1 ] && core_check_config; then
        backup_gateway_state >/dev/null 2>&1 || true
    fi
    if is_openwrt; then
        echo "${C_GRN}[✓] Единый пароль успешно синхронизирован (Шлюз + AdGuard Home)!${C_RES}"
    else
        echo "${C_GRN}[✓] Единый пароль успешно синхронизирован (Шлюз, AdGuard Home, Samba, Vaultwarden, Transmission, Caddy, Web Dashboard)!${C_RES}"
    fi
    return 0
}
