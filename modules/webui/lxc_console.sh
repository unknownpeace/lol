#!/bin/sh
# ==============================================================================
# Токенизированная точка входа ttyd для безопасного подключения к консоли LXC
# Принимает одноразовый 32-hex токен (аргумент из URL /console/?arg=<token>)
# ==============================================================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export TERM="${TERM:-xterm-256color}"

RAW_TOK="${1:-}"
case "$RAW_TOK" in
    *[!a-f0-9]*|"")
        printf "\r\n[!] Некорректный или отсутствующий токен консоли.\r\n"
        printf "Откройте терминал кнопкой «Консоль» в панели Gateway Dashboard.\r\n"
        sleep 2
        exit 1
        ;;
esac

if [ "${#RAW_TOK}" -ne 32 ]; then
    printf "\r\n[!] Недействительная длина токена консоли.\r\n"
    sleep 2
    exit 1
fi

TOK_FILE="/tmp/gw_console_tok_${RAW_TOK}"
if [ ! -f "$TOK_FILE" ]; then
    printf "\r\n[!] Токен консоли истёк или уже был использован.\r\n"
    printf "Нажмите «Переподключить» или откройте консоль заново из панели.\r\n"
    sleep 2
    exit 1
fi

META=$(cat "$TOK_FILE" 2>/dev/null || true)
rm -f "$TOK_FILE" 2>/dev/null || true

CT_NAME="${META%%|*}"
EXP_TS="${META##*|}"
NOW_TS=$(date +%s 2>/dev/null || echo 0)

case "$CT_NAME" in
    ""|*[!A-Za-z0-9_-]*)
        printf "\r\n[!] Поврежденные метаданные токена.\r\n"
        sleep 2
        exit 1
        ;;
esac

case "$EXP_TS" in
    ""|*[!0-9]*) EXP_TS=0 ;;
esac

if [ "$NOW_TS" -gt "$EXP_TS" ]; then
    printf "\r\n[!] Срок действия одноразового токена истёк (60 сек).\r\n"
    sleep 2
    exit 1
fi

if ! lxc-info -n "$CT_NAME" 2>/dev/null | grep -q "State:.*RUNNING"; then
    printf "\r\n[!] Контейнер '%s' не запущен.\r\n" "$CT_NAME"
    sleep 2
    exit 1
fi

printf "\033[1;36m[Gateway LXC Console]\033[0m Подключено к контейнеру \033[1;32m%s\033[0m (для выхода введите exit)\r\n\r\n" "$CT_NAME"
exec lxc-attach -n "$CT_NAME" -- env TERM=xterm-256color /bin/sh -c 'if [ -x /bin/bash ]; then exec /bin/bash -l; else exec /bin/sh -l; fi'
