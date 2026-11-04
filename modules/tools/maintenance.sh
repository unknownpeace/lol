rotate_gateway_logs() {
    for LOG_F in "$SB_LOG_FILE" "$AUTOUPDATE_LOG" /var/log/caddy.log /var/log/vaultwarden.log /var/log/ytdlp-webui.log /var/log/code-server.log /var/log/navidrome.log /var/log/jellyfin.log /var/log/qbittorrent-nox.log; do
        if [ -f "$LOG_F" ]; then
            F_SIZE=$(wc -c < "$LOG_F" 2>/dev/null | tr -d ' \t\r\n' || echo "0")
            if [ "${F_SIZE:-0}" -gt 1048576 ]; then
                tail -n 500 "$LOG_F" > "${LOG_F}.tmp" 2>/dev/null && mv -f "${LOG_F}.tmp" "$LOG_F" 2>/dev/null || true
            fi
        fi
    done
    return 0
}

# Активное сканирование всей /24 подсети LAN (прогрев ARP-таблицы за ~1.5 сек)
