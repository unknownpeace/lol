find_caddy_root_cert() {
    for c_cand in \
        "$CADDY_ROOT_CERT" \
        "/var/lib/caddy/caddy/pki/authorities/local/root.crt" \
        "/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt" \
        "/root/.local/share/caddy/pki/authorities/local/root.crt"; do
        if [ -f "$c_cand" ]; then
            CADDY_ROOT_CERT="$c_cand"
            return 0
        fi
    done
    return 1
}

# Генерация веб-портала http://ca.lan для удобной установки корневого сертификата на Windows 11, Linux и Android
build_pki_portal() {
    umask 022
    mkdir -p "$PKI_PORTAL_DIR" /usr/local/share/ca-certificates
    chmod 755 /srv /srv/homelab "$PKI_PORTAL_DIR" 2>/dev/null || true
    CUR_LIP=$(get_current_lan_ip)

    # Принудительная инициализация локального CA Caddy от имени пользователя caddy
    if ! find_caddy_root_cert && [ -x /usr/sbin/caddy ]; then
        chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
        su -s /bin/sh caddy -c 'XDG_DATA_HOME="/var/lib/caddy" XDG_CONFIG_HOME="/var/lib/caddy" HOME="/var/lib/caddy" /usr/sbin/caddy trust' >/dev/null 2>&1 || true
        chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
        chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    fi

    if find_caddy_root_cert; then
        cp -f "$CADDY_ROOT_CERT" "${PKI_PORTAL_DIR}/homelab-root-ca.crt" 2>/dev/null || true
        cp -f "$CADDY_ROOT_CERT" "${PKI_PORTAL_DIR}/homelab-root-ca.cer" 2>/dev/null || true
        chmod 644 "${PKI_PORTAL_DIR}/homelab-root-ca.crt" "${PKI_PORTAL_DIR}/homelab-root-ca.cer" 2>/dev/null || true
        cp -f "$CADDY_ROOT_CERT" /usr/local/share/ca-certificates/homelab-root-ca.crt 2>/dev/null || true
        chmod 644 /usr/local/share/ca-certificates/homelab-root-ca.crt 2>/dev/null || true
        update-ca-certificates >/dev/null 2>&1 || true
    fi

    cat << HTML_EOF > "${PKI_PORTAL_DIR}/index.html"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Alpine Homelab PKI — Установка сертификата HTTPS</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; background: #0f172a; color: #e2e8f0; max-width: 820px; margin: 2rem auto; padding: 0 1.2rem; line-height: 1.6; }
  .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 1.5rem; margin-bottom: 1.5rem; }
  h1, h2 { color: #38bdf8; margin-top: 0; }
  .btn { display: inline-block; background: #0284c7; color: #fff; text-decoration: none; padding: 0.75rem 1.4rem; border-radius: 8px; font-weight: 600; margin-right: 0.8rem; margin-bottom: 0.5rem; }
  .btn:hover { background: #0369a1; }
  pre { background: #090d16; color: #a7f3d0; padding: 1rem; border-radius: 8px; overflow-x: auto; font-size: 0.9rem; border: 1px solid #1e293b; }
  a { color: #38bdf8; }
</style>
</head>
<body>
  <div class="card">
    <h1>🔒 Локальный Центр Сертификации (Alpine Homelab PKI)</h1>
    <p>Сервер: <b>${CUR_LIP}</b> | Чтобы браузеры доверяли локальным доменам <code>https://*.lan</code> (включая WebCrypto API и WebAssembly SDK для Vaultwarden), установите корневой сертификат:</p>
    <p>
      <a class="btn" href="/homelab-root-ca.crt" download>📥 Скачать для Windows / Linux (.crt)</a>
      <a class="btn" href="/homelab-root-ca.cer" download>📱 Скачать для Android / iOS (.cer)</a>
    </p>
  </div>

  <div class="card">
    <h2>🪟 Windows 11 / 10 (Автоматически через PowerShell от Администратора)</h2>
    <pre>Invoke-WebRequest -Uri "http://ca.lan/homelab-root-ca.crt" -OutFile "\$env:TEMP\homelab-ca.crt"; Import-Certificate -FilePath "\$env:TEMP\homelab-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root</pre>
  </div>

  <div class="card">
    <h2>🐧 Linux (Debian / Ubuntu / Mint / Arch / Fedora)</h2>
    <pre>sudo curl -fsSL http://ca.lan/homelab-root-ca.crt -o /usr/local/share/ca-certificates/homelab-ca.crt &amp;&amp; sudo update-ca-certificates</pre>
  </div>

  <div class="card">
    <h2>🤖 Android (Установка вручную)</h2>
    <ol>
      <li>Нажмите кнопку <b>«Скачать для Android (.cer)»</b> выше.</li>
      <li>Откройте <b>Настройки &rarr; Безопасность и конфиденциальность &rarr; Другие настройки безопасности &rarr; Шифрование и учетные данные</b>.</li>
      <li>Выберите <b>Установка сертификата &rarr; Сертификат CA &rarr; Все равно установить</b> и укажите скачанный файл <code>homelab-root-ca.cer</code>.</li>
    </ol>
  </div>

  <div class="card">
    <h2>🏠 Все сервисы вашего домашнего сервера</h2>
    <ul>
      <li><a href="https://${DOM_ZASHBOARD}/ui/">https://${DOM_ZASHBOARD}</a> (или <a href="https://${DOM_SINGBOX}/ui/">https://${DOM_SINGBOX}</a>) — Панель Sing-Box (Zashboard)</li>
      <li><a href="https://${DOM_ADGUARD}">https://${DOM_ADGUARD}</a> — Панель AdGuard Home</li>
      <li><a href="https://${DOM_VAULTWARDEN}">https://${DOM_VAULTWARDEN}</a> — Vaultwarden (Пароли)</li>
      <li><a href="https://${DOM_JELLYFIN}">https://${DOM_JELLYFIN}</a> — Jellyfin (Единая медиаплатформа: Видео + Музыка)</li>
      <li><a href="https://${DOM_NAVIDROME}">https://${DOM_NAVIDROME}</a> — Navidrome (Специализированный музыкальный сервер Subsonic)</li>
      <li><a href="https://${DOM_YTDLP}">https://${DOM_YTDLP}</a> — yt-dlp Web UI (Загрузчик видео/аудио)</li>
      <li><a href="https://${DOM_TORRENT}">https://${DOM_TORRENT}</a> — qBittorrent (Торренты)</li>
      <li><a href="https://${DOM_FORGEJO}">https://${DOM_FORGEJO}</a> — Forgejo (Git-сервер)</li>
      <li><a href="https://${DOM_CODE}">https://${DOM_CODE}</a> — Server-Code (VS Code в браузере)</li>
    </ul>
  </div>
</body>
</html>
HTML_EOF
    chmod 644 "${PKI_PORTAL_DIR}/index.html" 2>/dev/null || true
    chown -R caddy:caddy "$PKI_PORTAL_DIR" 2>/dev/null || true
    return 0
}

# Генерация главного файла /etc/caddy/Caddyfile (включая сертификаты для AdGuard Home и Sing-Box Zashboard)
sync_caddy_main_config() {
    umask 022
    mkdir -p /etc/caddy "$CADDY_CONFD" "$PKI_PORTAL_DIR"
    chmod 755 /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    CUR_LIP_CDY=$(get_current_lan_ip)
    cat << CADDY_MAIN > "${CADDY_CONF}.tmp.$$"
{
    local_certs
    skip_install_trust
    auto_https disable_redirects
    servers {
        protocols h1 h2
    }
    pki {
        ca local {
            name "Alpine Homelab Root CA"
            root_cn "Alpine Homelab Root CA"
            intermediate_cn "Alpine Homelab Intermediate CA"
        }
    }
}

http://${DOM_CA}, http://${CUR_LIP_CDY}, http://*.lan {
    @pki_portal host ${DOM_CA} ${CUR_LIP_CDY}
    handle @pki_portal {
        root * ${PKI_PORTAL_DIR}
        header /homelab-root-ca.cer Content-Type "application/x-x509-ca-cert"
        header /homelab-root-ca.crt Content-Type "application/x-x509-ca-cert"
        file_server
    }
    handle {
        redir https://{host}{uri} permanent
    }
}

https://${DOM_CA} {
    tls internal
    root * ${PKI_PORTAL_DIR}
    header /homelab-root-ca.cer Content-Type "application/x-x509-ca-cert"
    header /homelab-root-ca.crt Content-Type "application/x-x509-ca-cert"
    file_server
}

https://${DOM_ADGUARD} {
    tls internal
    encode zstd gzip
    reverse_proxy 127.0.0.1:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}

https://${DOM_ZASHBOARD}, https://${DOM_SINGBOX} {
    tls internal
    encode zstd gzip
    @root_ui path /
    redir @root_ui /ui/ 302
    reverse_proxy 127.0.0.1:9090 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}

import ${CADDY_CONFD}/*.caddy
CADDY_MAIN
    chmod 644 "${CADDY_CONF}.tmp.$$" 2>/dev/null || true
    mv -f "${CADDY_CONF}.tmp.$$" "$CADDY_CONF"
    chown -R caddy:caddy /etc/caddy /var/lib/caddy 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    return 0
}

# Безопасная перезагрузка Caddy с проверкой синтаксиса и сохранением владельца caddy:caddy на PKI
reload_caddy_safe() {
    [ -x /usr/sbin/caddy ] || return 0
    sync_caddy_main_config
    chown -R caddy:caddy /var/lib/caddy /etc/caddy /var/log/caddy.log 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    if su -s /bin/sh caddy -c "XDG_DATA_HOME=/var/lib/caddy XDG_CONFIG_HOME=/var/lib/caddy HOME=/var/lib/caddy /usr/sbin/caddy validate --config '$CADDY_CONF' --adapter caddyfile" >/dev/null 2>&1 || \
       XDG_DATA_HOME="/var/lib/caddy" XDG_CONFIG_HOME="/var/lib/caddy" HOME="/var/lib/caddy" /usr/sbin/caddy validate --config "$CADDY_CONF" --adapter caddyfile >/dev/null 2>&1; then
        chown -R caddy:caddy /var/lib/caddy /etc/caddy 2>/dev/null || true
        chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
        service_ctl caddy enable
        if rc-service caddy status >/dev/null 2>&1; then
            if ! su -s /bin/sh caddy -c "XDG_DATA_HOME=/var/lib/caddy XDG_CONFIG_HOME=/var/lib/caddy HOME=/var/lib/caddy /usr/sbin/caddy reload --config '$CADDY_CONF' --adapter caddyfile" >/dev/null 2>&1 && \
               ! /usr/sbin/caddy reload --config "$CADDY_CONF" --adapter caddyfile >/dev/null 2>&1; then
                rc-service caddy restart >/dev/null 2>&1 || true
            fi
        else
            rc-service caddy start >/dev/null 2>&1 || true
        fi
        sleep 1
        # Триггер TLS handshake для гарантированной генерации локального Root CA Caddy
        curl -ksS --connect-timeout 2 -m 3 --resolve "${DOM_CA}:443:127.0.0.1" "https://${DOM_CA}/" >/dev/null 2>&1 || true
        chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
        build_pki_portal
        return 0
    else
        echo "${C_RED}[X] Ошибка валидации Caddyfile! Проверьте конфигурацию.${C_RES}" >&2
        return 1
    fi
}

# Подключение HTTPS-маршрута сервиса в /etc/caddy/conf.d/<module>.caddy
register_caddy_site() {
    SITE_MOD="$1"
    SITE_DOM="$2"
    SITE_PORT="$3"
    USE_BASIC_AUTH="${4:-no}"

    if ! is_module_enabled "caddy"; then
        install_module_caddy || return 1
    fi

    umask 022
    mkdir -p "$CADDY_CONFD"
    chmod 755 "$CADDY_CONFD" 2>/dev/null || true
    AUTH_BLOCK=""
    if [ "$USE_BASIC_AUTH" = "yes" ] && [ -x /usr/sbin/caddy ]; then
        load_gateway_env
        AUTH_USER="${SMB_USER:-${AGH_USER:-admin}}"
        C_HASH=$(/usr/sbin/caddy hash-password --plaintext "${ADMIN_PASS:-admin}" 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)
        [ -z "$C_HASH" ] && C_HASH=$(printf "%s\n" "${ADMIN_PASS:-admin}" | htpasswd -inBC 12 "$AUTH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        if [ -n "$C_HASH" ]; then
            if [ "$AUTH_USER" != "admin" ]; then
                AUTH_BLOCK="    basic_auth {
        ${AUTH_USER} ${C_HASH}
        admin ${C_HASH}
    }"
            else
                AUTH_BLOCK="    basic_auth {
        ${AUTH_USER} ${C_HASH}
    }"
            fi
        fi
    fi

    if [ "$SITE_MOD" = "vaultwarden" ]; then
        # Чистый эталонный профиль проксирования для Vaultwarden
        cat << VW_SITE_EOF > "${CADDY_CONFD}/${SITE_MOD}.caddy"
https://${SITE_DOM} {
    tls internal
    encode zstd gzip

    request_body {
        max_size 525MB
    }

    reverse_proxy 127.0.0.1:${SITE_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}
VW_SITE_EOF
    else
        cat << SITE_EOF > "${CADDY_CONFD}/${SITE_MOD}.caddy"
https://${SITE_DOM} {
    tls internal
    encode zstd gzip
${AUTH_BLOCK}
    reverse_proxy 127.0.0.1:${SITE_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}
SITE_EOF
    fi
    chmod 644 "${CADDY_CONFD}/${SITE_MOD}.caddy" 2>/dev/null || true
    reload_caddy_safe
    return 0
}

# Отключение HTTPS-маршрута сервиса из /etc/caddy/conf.d/
remove_caddy_site() {
    SITE_MOD="$1"
    rm -f "${CADDY_CONFD}/${SITE_MOD}.caddy" 2>/dev/null || true
    if is_module_enabled "caddy"; then
        reload_caddy_safe || true
    fi
    return 0
}

# Установка модуля Caddy (Центральный HTTPS Reverse Proxy & Local PKI)
install_module_caddy() {
    echo "${C_CYN}[*] Установка модуля Caddy (HTTPS Reverse Proxy & Local CA)...${C_RES}"
    umask 022
    ensure_alpine_community_repo
    apk update >/dev/null 2>&1 || true
    if ! apk add caddy caddy-openrc nss-tools ca-certificates; then
        echo "${C_RED}[X] Не удалось установить пакет caddy из репозитория Alpine!${C_RES}"
        return 1
    fi

    if ! id caddy >/dev/null 2>&1; then
        addgroup -S caddy 2>/dev/null || true
        adduser -S -D -H -h /var/lib/caddy -s /sbin/nologin -G caddy caddy 2>/dev/null || true
    fi

    # Разрешаем непривилегированному пользователю caddy занимать порты 80 и 443
    mkdir -p /etc/sysctl.d
    grep -q "ip_unprivileged_port_start" /etc/sysctl.d/99-gateway-forward.conf 2>/dev/null || \
        echo "net.ipv4.ip_unprivileged_port_start = 0" >> /etc/sysctl.d/99-gateway-forward.conf
    sysctl -w net.ipv4.ip_unprivileged_port_start=0 >/dev/null 2>&1 || true

    mkdir -p /etc/caddy "$CADDY_CONFD" "$PKI_PORTAL_DIR" /var/lib/caddy
    chmod 755 /srv /srv/homelab "$PKI_PORTAL_DIR" /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    chown -R caddy:caddy /var/lib/caddy "$PKI_PORTAL_DIR" /etc/caddy 2>/dev/null || true

    cat << 'CADDY_INIT' > /etc/init.d/caddy
#!/sbin/openrc-run
name="caddy"
description="Caddy HTTPS Reverse Proxy & Local PKI"
supervisor="supervise-daemon"
command="/usr/sbin/caddy"
command_args="run --config /etc/caddy/Caddyfile --adapter caddyfile"
command_user="caddy:caddy"
output_log="/var/log/caddy.log"
error_log="/var/log/caddy.log"
rc_ulimit="-n 65535"
export XDG_DATA_HOME="/var/lib/caddy"
export XDG_CONFIG_HOME="/var/lib/caddy"
export HOME="/var/lib/caddy"

depend() {
    need net
}

start_pre() {
    checkpath -f -m 0644 -o caddy:caddy /var/log/caddy.log
    checkpath -d -m 0755 -o caddy:caddy /var/lib/caddy
    chown -R caddy:caddy /var/lib/caddy /etc/caddy 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
}
CADDY_INIT
    chmod +x /etc/init.d/caddy

    sync_caddy_main_config
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
    sync_user_domain_rulesets
    sync_dns_firewall "yes" "keep"

    set_module_state "caddy" "yes"
    if ! reload_caddy_safe; then
        echo "${C_RED}[X] Не удалось запустить службу Caddy!${C_RES}"
        return 1
    fi

    # Ожидание генерации корневого сертификата локального CA Caddy (до 6 сек)
    W_CA=0
    while [ "$W_CA" -lt 6 ]; do
        find_caddy_root_cert && break
        curl -ksS --connect-timeout 1 -m 2 --resolve "${DOM_CA}:443:127.0.0.1" "https://${DOM_CA}/" >/dev/null 2>&1 || true
        sleep 1
        W_CA=$((W_CA + 1))
    done
    build_pki_portal

    echo "${C_GRN}[✓] Caddy и локальный Центр Сертификации успешно запущены!${C_RES}"
    echo "    • Портал установки сертификата: ${C_CYN}http://${DOM_CA}${C_RES} (или http://$(get_current_lan_ip))"
    echo "    • Панель Sing-Box (HTTPS):      ${C_CYN}https://${DOM_ZASHBOARD}${C_RES}"
    echo "    • Панель AdGuard Home (HTTPS):  ${C_CYN}https://${DOM_ADGUARD}${C_RES}"
    return 0
}

remove_module_caddy() {
    echo "Остановка и отключение модуля Caddy..."
    service_ctl caddy stop
    service_ctl caddy disable
    set_module_state "caddy" "no"
    echo "${C_GRN}[✓] Модуль Caddy отключен (сертификаты PKI сохранены в /var/lib/caddy).${C_RES}"
    return 0
}

# Вывод подробной памятки по установке корневого сертификата HTTPS на клиентские устройства
show_https_ca_instructions() {
    build_pki_portal
    CUR_LIP=$(get_current_lan_ip)
    echo ""
    ui_box_top "================================================================="
    echo "${C_BLD} 🔒 Установка доверенного корневого сертификата HTTPS (Windows/Linux/Android)${C_RES}"
    ui_box_top "================================================================="
    if find_caddy_root_cert; then
        echo " Статус Root CA: ${C_GRN}СГЕНЕРИРОВАН И РАЗДАЕТСЯ НА ПОРТАЛЕ${C_RES}"
    else
        echo " Статус Root CA: ${C_YEL}Ожидает первого запуска Caddy${C_RES}"
    fi
    echo " Веб-портал с кнопками скачивания: ${C_GRN}http://${DOM_CA}${C_RES} (или http://${CUR_LIP}/homelab-root-ca.crt)"
    ui_box_sep
    echo " ${C_BLD}1. Windows 11 / 10 (PowerShell от имени Администратора — в 1 клик):${C_RES}"
    echo "    ${C_CYN}Invoke-WebRequest -Uri \"http://ca.lan/homelab-root-ca.crt\" -OutFile \"\$env:TEMP\\homelab-ca.crt\"; Import-Certificate -FilePath \"\$env:TEMP\\homelab-ca.crt\" -CertStoreLocation Cert:\\LocalMachine\\Root${C_RES}"
    echo ""
    echo " ${C_BLD}2. Linux (Debian / Ubuntu / Mint / Arch):${C_RES}"
    echo "    ${C_CYN}sudo curl -fsSL http://ca.lan/homelab-root-ca.crt -o /usr/local/share/ca-certificates/homelab-ca.crt && sudo update-ca-certificates${C_RES}"
    echo ""
    echo " ${C_BLD}3. Android:${C_RES}"
    echo "    Откройте в браузере телефона ${C_GRN}http://ca.lan${C_RES}, скачайте файл ${C_BLD}.cer${C_RES},"
    echo "    затем: Настройки -> Безопасность -> Шифрование и учетные данные ->"
    echo "    Установка сертификата -> Сертификат CA -> выберите скачанный файл."
    ui_box_top "================================================================="
    return 0
}

# ==============================================================================
# Модуль Samba (SMB2/SMB3) + Сетевое обнаружение Windows 11 (wsdd) и Linux (avahi)
# ==============================================================================

# Настройка демонов сетевого обнаружения: wsdd (Windows 11 Explorer) и avahi (Linux File Managers)
