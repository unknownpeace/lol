#!/bin/sh
is_autoupdate_enabled() {
    grep -q "/usr/bin/gateway autoupdate" "$CRON_FILE" 2>/dev/null
}

is_watchdog_enabled() {
    grep -q "/usr/bin/gateway watchdog" "$CRON_FILE" 2>/dev/null
}

_cron_set_entry() {
    _ce_pat="$1"
    _ce_line="$2"
    mkdir -p /etc/crontabs
    touch "$CRON_FILE"
    chown root:root "$CRON_FILE" 2>/dev/null || true
    chmod 600 "$CRON_FILE" 2>/dev/null || true
    sed -i "\\|${_ce_pat}|d" "$CRON_FILE" 2>/dev/null || true
    printf "%s\n" "$_ce_line" >> "$CRON_FILE"
    chmod 600 "$CRON_FILE" 2>/dev/null || true
    service_ctl cron enable
    service_ctl cron restart
    return 0
}

_cron_del_entry() {
    if [ -f "$CRON_FILE" ]; then
        sed -i "\\|${1}|d" "$CRON_FILE" 2>/dev/null || true
    fi
    service_ctl cron reload
    return 0
}

# Включение/отключение ночного автообновления (04:00 через crond) и Watchdog (каждые 5 мин)
enable_autoupdate()  { _cron_set_entry "/usr/bin/gateway autoupdate" "0 4 * * * /usr/bin/gateway autoupdate >${AUTOUPDATE_LOG} 2>&1"; }
disable_autoupdate() { _cron_del_entry "/usr/bin/gateway autoupdate"; }
enable_watchdog()    { _cron_set_entry "/usr/bin/gateway watchdog"   "*/5 * * * * /usr/bin/gateway watchdog >/dev/null 2>&1"; }
disable_watchdog()   { _cron_del_entry "/usr/bin/gateway watchdog"; }
