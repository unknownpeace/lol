#!/bin/sh
# ==============================================================================
# Модуль Caddy Reverse Proxy & HTTPS PKI CA
# ==============================================================================

if [ -z "${GATEWAY_DIR:-}" ]; then
    GATEWAY_DIR="$(cd -P "$(dirname "$0")/../.." && pwd)"
    . "${GATEWAY_DIR}/lib/constants.sh"
    . "${GATEWAY_DIR}/lib/ui.sh"
    . "${GATEWAY_DIR}/lib/core.sh"
    . "${GATEWAY_DIR}/lib/env.sh"
    . "${GATEWAY_DIR}/lib/env_store.sh"
    . "${GATEWAY_DIR}/modules/homelab/registry.sh"
    . "${GATEWAY_DIR}/modules/caddy/ssl.sh"
fi

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

# Генерация веб-портала http://ca.lan (Obsidian Glass UI) для установки Root CA на клиенты
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

    load_gateway_env >/dev/null 2>&1 || true
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        PORTAL_GW_URL="https://gateway.${SSL_DOMAIN}"
        PORTAL_UI_URL="https://zashboard.${SSL_DOMAIN}/ui/"
        PORTAL_UI_LBL="https://zashboard.${SSL_DOMAIN}"
        PORTAL_PANEL_LBL="https://panel.${SSL_DOMAIN}"
        PORTAL_AGH_URL="https://adguard.${SSL_DOMAIN}"
        PORTAL_VW_URL="https://vaultwarden.${SSL_DOMAIN}"
        PORTAL_YT_URL="https://downloads.${SSL_DOMAIN}"
        PORTAL_TR_URL="https://torrents.${SSL_DOMAIN}"
        PORTAL_FG_URL="https://forgejo.${SSL_DOMAIN}"
        PORTAL_CD_URL="https://code.${SSL_DOMAIN}"
    else
        PORTAL_GW_URL="https://${DOM_GATEWAY:-gateway.lan}"
        PORTAL_UI_URL="https://${DOM_ZASHBOARD}/ui/"
        PORTAL_UI_LBL="https://${DOM_ZASHBOARD}"
        PORTAL_PANEL_LBL="https://${DOM_PANEL}"
        PORTAL_AGH_URL="https://${DOM_ADGUARD}"
        PORTAL_VW_URL="https://${DOM_VAULTWARDEN}"
        PORTAL_YT_URL="https://${DOM_YTDLP}"
        PORTAL_TR_URL="https://${DOM_TORRENT}"
        PORTAL_FG_URL="https://${DOM_FORGEJO}"
        PORTAL_CD_URL="https://${DOM_CODE}"
    fi

    cat << HTML_EOF > "${PKI_PORTAL_DIR}/index.html"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Alpine Homelab PKI — Центр Сертификации HTTPS</title>
<style>
  :root {
    --bg: #07090e;
    --surface-1: #0f1420;
    --surface-2: #151c2c;
    --border: rgba(148, 163, 184, 0.14);
    --border-strong: rgba(148, 163, 184, 0.28);
    --edge: inset 0 1px 0 rgba(255, 255, 255, 0.06);
    --text: #f1f5f9;
    --text-2: #cbd5e1;
    --muted: #8b9bb4;
    --accent: #38bdf8;
    --accent-strong: #0ea5e9;
    --ok: #10b981;
    --font-sans: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    --font-mono: ui-monospace, "Cascadia Code", "SFMono-Regular", Menlo, Consolas, monospace;
  }
  *, *::before, *::after { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; background: var(--bg); color: var(--text); font-family: var(--font-sans); line-height: 1.55; }
  body {
    background-image: radial-gradient(ellipse 80% 50% at 50% -15%, rgba(56, 189, 248, 0.12), transparent);
    min-height: 100vh;
    padding: 2rem 1rem 3rem;
  }
  .wrap { max-width: 880px; margin: 0 auto; display: grid; gap: 1rem; }
  .card {
    background: var(--surface-1);
    border: 1px solid var(--border);
    border-radius: 14px;
    padding: 1.35rem 1.45rem;
    box-shadow: var(--edge), 0 18px 40px -22px rgba(0, 0, 0, 0.7);
    min-width: 0;
  }
  .hero { display: flex; flex-wrap: wrap; gap: 1rem; align-items: flex-start; justify-content: space-between; }
  .brand { display: flex; gap: 0.85rem; align-items: center; }
  .brand-ic {
    width: 42px; height: 42px; border-radius: 11px; flex-shrink: 0;
    background: rgba(56, 189, 248, 0.12); border: 1px solid rgba(56, 189, 248, 0.28);
    display: grid; place-items: center; color: var(--accent);
  }
  h1 { margin: 0; font-size: 1.15rem; font-weight: 650; letter-spacing: -0.02em; }
  .sub { margin: 0.25rem 0 0; font-size: 0.85rem; color: var(--muted); font-variant-numeric: tabular-nums; }
  .pill {
    display: inline-flex; align-items: center; gap: 0.4rem;
    padding: 0.28rem 0.65rem; border-radius: 999px; font-size: 0.78rem; font-weight: 600;
    background: rgba(16, 185, 129, 0.14); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.28);
    font-variant-numeric: tabular-nums;
  }
  .lead { margin: 0.9rem 0 1.1rem; color: var(--text-2); font-size: 0.9rem; }
  .actions { display: flex; flex-wrap: wrap; gap: 0.65rem; }
  .btn {
    display: inline-flex; align-items: center; gap: 0.5rem;
    background: var(--accent-strong); color: #fff; text-decoration: none;
    padding: 0.65rem 1.1rem; border-radius: 10px; font-size: 0.875rem; font-weight: 600;
    border: 1px solid rgba(255, 255, 255, 0.12); transition: transform 120ms ease, background 150ms ease;
    cursor: pointer;
  }
  .btn:hover { background: #0284c7; }
  .btn:active { transform: scale(0.98); }
  .btn-sec { background: var(--surface-2); color: var(--text); border-color: var(--border-strong); }
  .btn-sec:hover { background: #1c2538; }
  h2 {
    margin: 0 0 0.75rem; font-size: 0.96rem; font-weight: 650; letter-spacing: -0.01em;
    display: flex; align-items: center; gap: 0.5rem; color: var(--text);
  }
  h2 svg { color: var(--accent); flex-shrink: 0; }
  .cmd-wrap { position: relative; }
  pre {
    margin: 0; background: #090d16; color: #a7f3d0; font-family: var(--font-mono);
    padding: 0.85rem 4.8rem 0.85rem 0.95rem; border-radius: 10px; overflow-x: auto;
    font-size: 0.82rem; border: 1px solid var(--border);
  }
  .copy-btn {
    position: absolute; top: 0.5rem; right: 0.5rem;
    background: var(--surface-2); color: var(--text-2); border: 1px solid var(--border-strong);
    border-radius: 7px; padding: 0.3rem 0.6rem; font-size: 0.75rem; font-weight: 600; cursor: pointer;
  }
  .copy-btn:hover { color: #fff; border-color: var(--accent); }
  code { font-family: var(--font-mono); font-size: 0.84em; background: var(--surface-2); padding: 0.1rem 0.38rem; border-radius: 5px; color: var(--accent); }
  ol { margin: 0; padding-left: 1.25rem; color: var(--text-2); font-size: 0.88rem; display: grid; gap: 0.35rem; }
  .svc-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(240px, 100%), 1fr)); gap: 0.65rem; }
  .svc {
    display: flex; flex-direction: column; gap: 0.2rem; padding: 0.75rem 0.9rem;
    background: var(--surface-2); border: 1px solid var(--border); border-radius: 10px;
    text-decoration: none; transition: border-color 140ms ease, transform 140ms ease;
  }
  .svc:hover { border-color: var(--accent); transform: translateY(-1px); }
  .svc-t { color: var(--text); font-weight: 600; font-size: 0.88rem; }
  .svc-u { color: var(--accent); font-family: var(--font-mono); font-size: 0.78rem; word-break: break-all; }
  .svc-d { color: var(--muted); font-size: 0.78rem; }
</style>
</head>
<body>
<div class="wrap">
  <section class="card">
    <div class="hero">
      <div class="brand">
        <div class="brand-ic">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="M9 12l2 2 4-4"/></svg>
        </div>
        <div>
          <h1>Локальный Центр Сертификации (Homelab PKI)</h1>
          <p class="sub">Шлюз: ${CUR_LIP} &bull; Портал: http://${DOM_CA:-ca.lan}</p>
        </div>
      </div>
      <span class="pill">Root CA активен</span>
    </div>
    <p class="lead">Чтобы браузеры доверяли локальным доменам <code>https://*.lan</code> (включая WebCrypto API и WebAssembly SDK в Vaultwarden), установите корневой сертификат один раз на устройство:</p>
    <div class="actions">
      <a class="btn" href="/homelab-root-ca.crt" download>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
        Windows / Linux (.crt)
      </a>
      <a class="btn btn-sec" href="/homelab-root-ca.cer" download>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg>
        Android / iOS (.cer)
      </a>
    </div>
  </section>

  <section class="card">
    <h2>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="8" height="8" rx="1"/><rect x="13" y="3" width="8" height="8" rx="1"/><rect x="3" y="13" width="8" height="8" rx="1"/><rect x="13" y="13" width="8" height="8" rx="1"/></svg>
      Windows 11 / 10 (PowerShell от Администратора)
    </h2>
    <div class="cmd-wrap">
      <pre id="cmd-win">Invoke-WebRequest -Uri "http://${DOM_CA:-ca.lan}/homelab-root-ca.crt" -OutFile "\$env:TEMP\homelab-ca.crt"; Import-Certificate -FilePath "\$env:TEMP\homelab-ca.crt" -CertStoreLocation Cert:\LocalMachine\Root</pre>
      <button class="copy-btn" type="button" onclick="copyPre('cmd-win', this)">Копировать</button>
    </div>
  </section>

  <section class="card">
    <h2>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
      Linux (Debian / Ubuntu / Mint / Arch / Fedora)
    </h2>
    <div class="cmd-wrap">
      <pre id="cmd-lin">sudo curl -fsSL http://${DOM_CA:-ca.lan}/homelab-root-ca.crt -o /usr/local/share/ca-certificates/homelab-ca.crt &amp;&amp; sudo update-ca-certificates</pre>
      <button class="copy-btn" type="button" onclick="copyPre('cmd-lin', this)">Копировать</button>
    </div>
  </section>

  <section class="card">
    <h2>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2" width="14" height="20" rx="2"/><line x1="12" y1="18" x2="12.01" y2="18"/></svg>
      Android / iOS (Установка вручную)
    </h2>
    <ol>
      <li>Нажмите кнопку <b>«Android / iOS (.cer)»</b> выше для загрузки профиля.</li>
      <li>Android: откройте <b>Настройки &rarr; Безопасность &rarr; Шифрование и учетные данные &rarr; Установка сертификата &rarr; Сертификат CA</b> и выберите файл <code>homelab-root-ca.cer</code>.</li>
      <li>iOS: установите профиль в <b>Настройках</b> и включите полное доверие в разделе <b>Об этом устройстве &rarr; Доверие сертификатам</b>.</li>
    </ol>
  </section>

  <section class="card">
    <h2>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="9" y1="21" x2="9" y2="9"/></svg>
      Сервисы вашего домашнего сервера
    </h2>
    <div class="svc-grid">
      <a class="svc" href="${PORTAL_GW_URL}"><span class="svc-t">Gateway Dashboard</span><span class="svc-u">${PORTAL_GW_URL}</span><span class="svc-d">Панель управления шлюзом и LXC</span></a>
      <a class="svc" href="${PORTAL_UI_URL}"><span class="svc-t">Панель прокси-ядра</span><span class="svc-u">${PORTAL_UI_LBL}</span><span class="svc-d">Zashboard / MetaCubeXD (${PORTAL_PANEL_LBL})</span></a>
      <a class="svc" href="${PORTAL_AGH_URL}"><span class="svc-t">AdGuard Home</span><span class="svc-u">${PORTAL_AGH_URL}</span><span class="svc-d">DNS-фильтрация и локальные записи</span></a>
      <a class="svc" href="${PORTAL_VW_URL}"><span class="svc-t">Vaultwarden</span><span class="svc-u">${PORTAL_VW_URL}</span><span class="svc-d">Менеджер паролей Bitwarden</span></a>
      <a class="svc" href="${PORTAL_YT_URL}"><span class="svc-t">MeTube</span><span class="svc-u">${PORTAL_YT_URL}</span><span class="svc-d">Загрузка видео и аудио (yt-dlp)</span></a>
      <a class="svc" href="${PORTAL_TR_URL}"><span class="svc-t">Transmission</span><span class="svc-u">${PORTAL_TR_URL}</span><span class="svc-d">BitTorrent клиент</span></a>
      <a class="svc" href="${PORTAL_FG_URL}"><span class="svc-t">Forgejo</span><span class="svc-u">${PORTAL_FG_URL}</span><span class="svc-d">Приватный Git-сервер</span></a>
      <a class="svc" href="${PORTAL_CD_URL}"><span class="svc-t">Server-Code</span><span class="svc-u">${PORTAL_CD_URL}</span><span class="svc-d">VS Code Web IDE в браузере</span></a>
    </div>
  </section>
</div>
<script>
function copyPre(id, btn) {
  var el = document.getElementById(id);
  if (!el) return;
  var txt = el.textContent || "";
  var done = function() {
    var orig = btn.textContent;
    btn.textContent = "Скопировано ✓";
    setTimeout(function() { btn.textContent = orig; }, 1600);
  };
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(txt).then(done).catch(function() { fallbackCopy(txt, done); });
  } else {
    fallbackCopy(txt, done);
  }
}
function fallbackCopy(txt, cb) {
  var ta = document.createElement("textarea");
  ta.value = txt;
  ta.style.position = "fixed";
  ta.style.opacity = "0";
  document.body.appendChild(ta);
  ta.focus();
  ta.select();
  try { document.execCommand("copy"); cb(); } catch (e) {}
  document.body.removeChild(ta);
}
</script>
</body>
</html>
HTML_EOF
    chmod 644 "${PKI_PORTAL_DIR}/index.html" 2>/dev/null || true
    chown -R root:caddy "$PKI_PORTAL_DIR" 2>/dev/null || true
    return 0
}

# Генерация главного файла /etc/caddy/Caddyfile с предварительной валидацией перед заменой рабочего файла
_render_caddy_core_sites() {
    _cs_tls="$1"
    _cs_ca="$2"
    _cs_agh="$3"
    _cs_ui="$4"
    cat << CORE_SITES_EOF
${_cs_ca} {
    tls ${_cs_tls}
    root * ${PKI_PORTAL_DIR}
    header /homelab-root-ca.cer Content-Type "application/x-x509-ca-cert"
    header /homelab-root-ca.crt Content-Type "application/x-x509-ca-cert"
    file_server
}

${_cs_agh} {
    tls ${_cs_tls}
    encode zstd gzip
    reverse_proxy 127.0.0.1:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}

${_cs_ui} {
    tls ${_cs_tls}
    encode zstd gzip
    @root_ui path /
    redir @root_ui /ui/ 302
    reverse_proxy 127.0.0.1:9090 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
}
CORE_SITES_EOF
}

sync_caddy_main_config() {
    umask 022
    mkdir -p /etc/caddy "$CADDY_CONFD" "$PKI_PORTAL_DIR"
    chown root:caddy /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    chmod 750 /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    CUR_LIP_CDY=$(get_current_lan_ip)
    HTTP_REDIRECT_DOMS="http://${DOM_CA}, http://${CUR_LIP_CDY}, http://*.lan"
    LAN_MAIN_BLOCKS=$(_render_caddy_core_sites \
        "internal" \
        "https://${DOM_CA}" \
        "https://${DOM_ADGUARD}" \
        "https://${DOM_ZASHBOARD}, https://${DOM_SINGBOX}, https://${DOM_MIHOMO}, https://${DOM_PANEL}")
    LE_MAIN_BLOCKS=""
    if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
        HTTP_REDIRECT_DOMS="${HTTP_REDIRECT_DOMS}, http://${SSL_DOMAIN}, http://*.${SSL_DOMAIN}"
        LE_MAIN_BLOCKS=$(_render_caddy_core_sites \
            "${SSL_FULLCHAIN_FILE} ${SSL_KEY_FILE}" \
            "https://ca.${SSL_DOMAIN}, https://${SSL_DOMAIN}" \
            "https://adguard.${SSL_DOMAIN}" \
            "https://zashboard.${SSL_DOMAIN}, https://singbox.${SSL_DOMAIN}, https://mihomo.${SSL_DOMAIN}, https://panel.${SSL_DOMAIN}")
    fi
    _caddy_tmp="${CADDY_CONF}.tmp.$$"
    cat << CADDY_MAIN > "$_caddy_tmp"
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

${HTTP_REDIRECT_DOMS} {
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

${LAN_MAIN_BLOCKS}

${LE_MAIN_BLOCKS}

import ${CADDY_CONFD}/*.caddy
CADDY_MAIN
    chown root:caddy "$_caddy_tmp" 2>/dev/null || true
    chmod 640 "$_caddy_tmp" 2>/dev/null || true
    if [ -x /usr/sbin/caddy ]; then
        if ! XDG_DATA_HOME="/var/lib/caddy" XDG_CONFIG_HOME="/var/lib/caddy" HOME="/var/lib/caddy" /usr/sbin/caddy validate --config "$_caddy_tmp" --adapter caddyfile >/dev/null 2>&1; then
            rm -f "$_caddy_tmp" 2>/dev/null || true
            echo "${C_RED}[X] Ошибка валидации нового Caddyfile — рабочая конфигурация не изменена!${C_RES}" >&2
            return 1
        fi
    fi
    mv -f "$_caddy_tmp" "$CADDY_CONF"
    chown -R root:caddy /etc/caddy 2>/dev/null || true
    chmod 750 /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    chmod 640 "$CADDY_CONF" 2>/dev/null || true
    chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    return 0
}

# Безопасная перезагрузка Caddy с проверкой синтаксиса и прав (без записи конфига от caddy)
reload_caddy_safe() {
    [ -x /usr/sbin/caddy ] || return 1
    sync_caddy_main_config || return 1
    chown -R root:caddy /etc/caddy 2>/dev/null || true
    chmod 750 /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    chmod 640 "$CADDY_CONF" 2>/dev/null || true
    find "$CADDY_CONFD" -maxdepth 1 -type f -name '*.caddy' -exec chmod 640 {} + 2>/dev/null || true
    chown -R caddy:caddy /var/lib/caddy /var/log/caddy.log 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
    if su -s /bin/sh caddy -c "XDG_DATA_HOME=/var/lib/caddy XDG_CONFIG_HOME=/var/lib/caddy HOME=/var/lib/caddy /usr/sbin/caddy validate --config '$CADDY_CONF' --adapter caddyfile" >/dev/null 2>&1 || \
       XDG_DATA_HOME="/var/lib/caddy" XDG_CONFIG_HOME="/var/lib/caddy" HOME="/var/lib/caddy" /usr/sbin/caddy validate --config "$CADDY_CONF" --adapter caddyfile >/dev/null 2>&1; then
        service_ctl caddy enable
        if rc-service caddy status >/dev/null 2>&1; then
            if ! su -s /bin/sh caddy -c "XDG_DATA_HOME=/var/lib/caddy XDG_CONFIG_HOME=/var/lib/caddy HOME=/var/lib/caddy /usr/sbin/caddy reload --config '$CADDY_CONF' --adapter caddyfile" >/dev/null 2>&1 && \
               ! /usr/sbin/caddy reload --config "$CADDY_CONF" --adapter caddyfile >/dev/null 2>&1; then
                if ! rc-service caddy restart >/dev/null 2>&1; then
                    echo "${C_RED}[X] Не удалось перезапустить службу Caddy!${C_RES}" >&2
                    return 1
                fi
            fi
        else
            if ! rc-service caddy start >/dev/null 2>&1; then
                echo "${C_RED}[X] Не удалось запустить службу Caddy!${C_RES}" >&2
                return 1
            fi
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

# Подключение HTTPS-маршрута сервиса в /etc/caddy/conf.d/<module>.caddy (fail-closed basic_auth + валидация до подмены)
register_caddy_site() {
    SITE_MOD="$1"
    SITE_DOM="$2"
    SITE_PORT="$3"
    USE_BASIC_AUTH="${4:-no}"
    SKIP_RELOAD="${5:-no}"

    if ! is_module_enabled "caddy"; then
        install_module_caddy || return 1
    fi

    umask 022
    mkdir -p "$CADDY_CONFD"
    chown root:caddy "$CADDY_CONFD" 2>/dev/null || true
    chmod 750 "$CADDY_CONFD" 2>/dev/null || true

    AUTH_BLOCK=""
    AUTH_STRIP_LINE=""
    if [ "$USE_BASIC_AUTH" = "yes" ]; then
        load_gateway_env
        AUTH_USER="${SMB_USER:-${AGH_USER:-admin}}"
        C_HASH=""
        if [ -x /usr/sbin/caddy ]; then
            C_HASH=$(/usr/sbin/caddy hash-password --plaintext "${ADMIN_PASS:-admin}" 2>/dev/null | tail -n 1 | tr -d '\r\n' || true)
        fi
        if [ -z "$C_HASH" ] && command -v htpasswd >/dev/null 2>&1; then
            C_HASH=$(printf "%s\n" "${ADMIN_PASS:-admin}" | htpasswd -inBC 12 "$AUTH_USER" 2>/dev/null | cut -d: -f2 | tr -d ' \t\r\n' || true)
        fi
        if [ -z "$C_HASH" ]; then
            echo "${C_RED}[X] Ошибка: Не удалось сгенерировать bcrypt-хэш для basic_auth (${SITE_MOD}) — публикация отменена!${C_RES}" >&2
            return 1
        fi
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
        AUTH_STRIP_LINE="        header_up -Authorization"
    fi

    GW_PROXY_HEADER_LINE=""
    if [ "$SITE_MOD" = "gateway" ]; then
        GW_PROXY_TOK=$(ensure_webui_proxy_token) || {
            echo "${C_RED}[X] Ошибка: Не удалось получить / создать токен прокси WebUI (${HOMELAB_DIR:-/etc/sing-box/homelab}/webui_proxy.token)!${C_RES}" >&2
            return 1
        }
        GW_PROXY_HEADER_LINE="            header_up X-Gateway-Proxy-Token ${GW_PROXY_TOK}"
    fi

    SITE_SUB="${SITE_DOM%%.*}"
    if [ -n "$SITE_SUB" ] && [ "$SITE_SUB" != "$SITE_MOD" ]; then
        LE_DOM_HEADER="https://${SITE_SUB}.${SSL_DOMAIN}, https://${SITE_MOD}.${SSL_DOMAIN}"
        LAN_DOM_HEADER="https://${SITE_DOM}, https://${SITE_MOD}.lan"
    else
        LE_DOM_HEADER="https://${SITE_SUB:-$SITE_MOD}.${SSL_DOMAIN}"
        LAN_DOM_HEADER="https://${SITE_DOM}"
    fi

    _render_site_block() {
        _sb_hdr="$1"
        _sb_tls="$2"
        if [ "$SITE_MOD" = "gateway" ]; then
            CON_PORT="${PORT_WEBUI_CONSOLE:-8096}"
            cat << GW_SITE_EOF
${_sb_hdr} {
    tls ${_sb_tls}
    encode zstd gzip
${AUTH_BLOCK}
    handle /console* {
        reverse_proxy 127.0.0.1:${CON_PORT} {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up -Authorization
        }
    }
    handle {
        reverse_proxy 127.0.0.1:${SITE_PORT} {
            header_up Host {host}
            header_up X-Real-IP {remote_host}
            header_up -Authorization
${GW_PROXY_HEADER_LINE}
        }
    }
}
GW_SITE_EOF
        elif [ "$SITE_MOD" = "vaultwarden" ]; then
            # Эталонный профиль Vaultwarden: WebSockets проксируются Caddy нативно
            cat << VW_SITE_EOF
${_sb_hdr} {
    tls ${_sb_tls}
    encode zstd gzip

    request_body {
        max_size 525MB
    }

    reverse_proxy 127.0.0.1:${SITE_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto https
    }
}
VW_SITE_EOF
        else
            cat << SITE_EOF
${_sb_hdr} {
    tls ${_sb_tls}
    encode zstd gzip
${AUTH_BLOCK}
    reverse_proxy 127.0.0.1:${SITE_PORT} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
${AUTH_STRIP_LINE}
    }
}
SITE_EOF
        fi
    }

    ensure_gateway_runtime_dir || return 1
    _val_dir=$(umask 077 && mktemp -d "${GATEWAY_RUNTIME_DIR:-/run/gateway}/caddy_val.XXXXXX") || return 1
    mkdir -p "${_val_dir}/conf.d"
    if [ -d "$CADDY_CONFD" ]; then
        cp -f "${CADDY_CONFD}"/*.caddy "${_val_dir}/conf.d/" 2>/dev/null || true
    fi
    _staged_site="${_val_dir}/conf.d/${SITE_MOD}.caddy"

    {
        _render_site_block "$LAN_DOM_HEADER" "internal"
        if is_letsencrypt_ssl_active 2>/dev/null && [ -n "${SSL_DOMAIN:-}" ]; then
            printf "\n"
            _render_site_block "$LE_DOM_HEADER" "${SSL_FULLCHAIN_FILE} ${SSL_KEY_FILE}"
        fi
    } > "$_staged_site"

    if [ -x /usr/sbin/caddy ] && [ -s "$CADDY_CONF" ]; then
        sed "s|import ${CADDY_CONFD}/\*\.caddy|import ${_val_dir}/conf.d/*.caddy|g" "$CADDY_CONF" > "${_val_dir}/Caddyfile"
        if ! XDG_DATA_HOME="/var/lib/caddy" XDG_CONFIG_HOME="/var/lib/caddy" HOME="/var/lib/caddy" /usr/sbin/caddy validate --config "${_val_dir}/Caddyfile" --adapter caddyfile >/dev/null 2>&1; then
            rm -rf "$_val_dir" 2>/dev/null || true
            echo "${C_RED}[X] Ошибка валидации конфигурации сайта Caddy (${SITE_MOD}) — старая конфигурация сохранена!${C_RES}" >&2
            return 1
        fi
    fi

    chown root:caddy "$_staged_site" 2>/dev/null || true
    chmod 640 "$_staged_site" 2>/dev/null || true
    mv -f "$_staged_site" "${CADDY_CONFD}/${SITE_MOD}.caddy"
    chown root:caddy "${CADDY_CONFD}/${SITE_MOD}.caddy" 2>/dev/null || true
    chmod 640 "${CADDY_CONFD}/${SITE_MOD}.caddy" 2>/dev/null || true
    rm -rf "$_val_dir" 2>/dev/null || true

    if [ "$SKIP_RELOAD" != "yes" ]; then
        reload_caddy_safe || return 1
    fi
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

# Синхронизация HTTPS-конфигураций Caddy для всех установленных модулей Homelab (одним финальным reload)
sync_all_caddy_sites() {
    load_gateway_env
    is_module_enabled "vaultwarden" && register_caddy_site "vaultwarden" "${DOM_VAULTWARDEN:-vaultwarden.lan}" "${PORT_VAULTWARDEN:-8222}" "no" "yes" || true
    is_module_enabled "forgejo"     && register_caddy_site "forgejo" "${DOM_FORGEJO:-forgejo.lan}" "${PORT_FORGEJO:-3001}" "no" "yes" || true
    is_module_enabled "code"        && register_caddy_site "code" "${DOM_CODE:-code.lan}" "${PORT_CODE:-8443}" "yes" "yes" || true
    is_module_enabled "ytdlp"       && register_caddy_site "ytdlp" "${DOM_YTDLP:-downloads.lan}" "${PORT_METUBE:-8081}" "yes" "yes" || true
    is_module_enabled "torrent"     && register_caddy_site "torrent" "${DOM_TORRENT:-torrents.lan}" "${PORT_TRANSMISSION_WEB:-9091}" "yes" "yes" || true
    [ -x /etc/init.d/gateway-webui ] && register_caddy_site "gateway" "${DOM_GATEWAY:-gateway.lan}" "${PORT_WEBUI:-8095}" "yes" "yes" || true
    reload_caddy_safe
    return $?
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
    chmod 755 /srv /srv/homelab "$PKI_PORTAL_DIR" 2>/dev/null || true
    chown -R root:caddy /etc/caddy "$PKI_PORTAL_DIR" 2>/dev/null || true
    chmod 750 /etc/caddy "$CADDY_CONFD" 2>/dev/null || true
    chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true

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
    chown -R caddy:caddy /var/lib/caddy 2>/dev/null || true
    chmod -R u+rwX /var/lib/caddy 2>/dev/null || true
}
CADDY_INIT
    chmod +x /etc/init.d/caddy

    sync_caddy_main_config || return 1
    sync_agh_homelab_rewrites "$(get_current_lan_ip)"
    sync_user_domain_rulesets
    sync_dns_firewall "yes" "keep"

    if ! reload_caddy_safe; then
        set_module_state "caddy" "no"
        echo "${C_RED}[X] Не удалось запустить службу Caddy!${C_RES}"
        return 1
    fi
    set_module_state "caddy" "yes"

    # Ожидание генерации корневого сертификата локального CA Caddy (до 6 сек)
    W_CA=0
    while [ "$W_CA" -lt 6 ]; do
        find_caddy_root_cert && break
        curl -ksS --connect-timeout 1 -m 2 --resolve "${DOM_CA}:443:127.0.0.1" "https://${DOM_CA}/" >/dev/null 2>&1 || true
        sleep 1
        W_CA=$((W_CA + 1))
    done
    build_pki_portal
    if [ -x /etc/init.d/gateway-webui ] && command -v install_alpine_webui >/dev/null 2>&1; then
        install_alpine_webui >/dev/null 2>&1 || true
    fi

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
    if [ -x /etc/init.d/gateway-webui ] && command -v install_alpine_webui >/dev/null 2>&1; then
        install_alpine_webui >/dev/null 2>&1 || true
    fi
    echo "${C_GRN}[✓] Модуль Caddy отключен (сертификаты PKI сохранены в /var/lib/caddy).${C_RES}"
    return 0
}

# Вывод подробной памятки по установке корневого сертификата HTTPS на клиентские устройства
show_https_ca_instructions() {
    build_pki_portal
    CUR_LIP=$(get_current_lan_ip)
    echo ""
    ui_box_top "🔒 Установка доверенного корневого сертификата HTTPS (Windows/Linux/Android)"
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
    ui_box_bottom
    return 0
}

# Standalone CLI execution
if [ "$(basename "$0")" = "caddy.sh" ]; then
    case "$1" in
        install)
            install_module_caddy
            ;;
        remove|uninstall)
            remove_module_caddy
            ;;
        restart)
            service_ctl caddy restart
            ;;
        status)
            rc-service caddy status 2>/dev/null || rc-status
            ;;
        portal)
            build_pki_portal
            show_https_ca_instructions
            ;;
        *)
            ;;
    esac
fi
