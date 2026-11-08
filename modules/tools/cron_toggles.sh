is_autoupdate_enabled() {
    grep -q "/usr/bin/gateway autoupdate" "$CRON_FILE" 2>/dev/null
}

is_watchdog_enabled() {
    grep -q "/usr/bin/gateway watchdog" "$CRON_FILE" 2>/dev/null
}

# Включение автообновления (ежедневно в 04:00 через crond)
enable_autoupdate() {
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    echo "0 4 * * * /usr/bin/gateway autoupdate >${AUTOUPDATE_LOG} 2>&1" >> "$CRON_FILE"
    service_ctl cron enable
    service_ctl cron restart
    return 0
}

# Отключение автообновления
disable_autoupdate() {
    if [ -f "$CRON_FILE" ]; then
        sed -i '\|/usr/bin/gateway autoupdate|d' "$CRON_FILE" 2>/dev/null || true
    fi
    service_ctl cron reload
    return 0
}

# Управление встроенным Watchdog (самоисцеление служб каждые 5 минут)
enable_watchdog() {
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    sed -i '\|/usr/bin/gateway watchdog|d' "$CRON_FILE" 2>/dev/null || true
    echo "*/5 * * * * /usr/bin/gateway watchdog >/dev/null 2>&1" >> "$CRON_FILE"
    service_ctl cron enable
    service_ctl cron restart
    return 0
}

disable_watchdog() {
    if [ -f "$CRON_FILE" ]; then
        sed -i '\|/usr/bin/gateway watchdog|d' "$CRON_FILE" 2>/dev/null || true
    fi
    service_ctl cron reload
    return 0
}

# Проверка: смонтирован ли сейчас внешний диск в /srv/storage
