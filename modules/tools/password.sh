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

    save_gateway_env
    save_homelab_env
    generate_singbox_config

    service_ctl adguardhome stop
    if [ -f "$AGH_CONF" ] && command -v htpasswd >/dev/null 2>&1; then
        CUR_AGH_USER=$(sed -n '/^users:/,/^auth_attempts:/ s/^[[:space:]]*-[[:space:]]*name:[[:space:]]*\(.*\)/\1/p' "$AGH_CONF" | head -n 1 | tr -d ' \t\r\n"')
        [ -z "$CUR_AGH_USER" ] && CUR_AGH_USER="admin" || true
        NEW_HASH=$(printf "%s\n" "$ADMIN_PASS" | htpasswd -inBC 10 "$CUR_AGH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        [ -z "$NEW_HASH" ] && NEW_HASH=$(htpasswd -nbBC 10 "$CUR_AGH_USER" "$ADMIN_PASS" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true) || true
        if [ -n "$NEW_HASH" ]; then
            awk -v u="$CUR_AGH_USER" -v h="$NEW_HASH" '
                /^users:/ {
                    print "users:"
                    print "  - name: " u
                    print "    password: " h
                    in_users=1; next
                }
                in_users && /^[^[:space:]]/ { in_users=0 }
                in_users { next }
                { print }
            ' "$AGH_CONF" > "${AGH_CONF}.tmp" && mv "${AGH_CONF}.tmp" "$AGH_CONF"
            chmod 600 "$AGH_CONF" 2>/dev/null || true
        fi
    fi

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

    # Синхронизация BasicAuth в Caddy для защищенных модулей
    if [ -x /usr/sbin/caddy ] && [ -d "$CADDY_CONFD" ]; then
        is_module_enabled "ytdlp" && register_caddy_site "ytdlp" "$DOM_YTDLP" "$PORT_YTDLP" "yes" >/dev/null 2>&1 || true
        is_module_enabled "torrent" && register_caddy_site "torrent" "$DOM_TORRENT" "$PORT_TORRENT_WEB" "yes" >/dev/null 2>&1 || true
        is_module_enabled "code" && register_caddy_site "code" "$DOM_CODE" "$PORT_CODE" "yes" >/dev/null 2>&1 || true
    fi

    service_ctl sing-box restart || true
    service_ctl adguardhome start || true
    echo "${C_GRN}[✓] Единый пароль успешно синхронизирован (Sing-Box, AdGuard Home, Samba, Vaultwarden, Caddy)!${C_RES}"
    return 0
}

# Управление Умным DHCP-сервером на Alpine Linux (dnsmasq на порту 5353)
