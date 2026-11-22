#!/bin/sh
_tg_extract_error() {
    RESP_BODY="${1:-}"
    ERR_MSG=""
    if [ -n "$RESP_BODY" ]; then
        if command -v jq >/dev/null 2>&1; then
            ERR_MSG=$(printf "%s" "$RESP_BODY" | jq -r '.description // empty' 2>/dev/null || true)
        fi
        if [ -z "$ERR_MSG" ]; then
            ERR_MSG=$(printf "%s" "$RESP_BODY" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)
        fi
    fi
    printf "%s" "$ERR_MSG"
    return 0
}

_tg_resp_is_ok() {
    case "${1:-}" in
        *'"ok":true'*|*'"ok": true'*) return 0 ;;
        *) return 1 ;;
    esac
}

_tg_api_post() {
    EP="$1"
    shift
    TG_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}/${EP}"
    TG_URL_ESC=$(printf "%s" "$TG_URL" | sed 's/\\/\\\\/g; s/"/\\"/g')
    TG_LAST_ERR=""
    _M_SEC=10
    [ "$EP" = "sendDocument" ] && _M_SEC=60
    for CURL_P in "-x http://127.0.0.1:7890" ""; do
        # shellcheck disable=SC2086
        RESP=$(printf 'url = "%s"\n' "$TG_URL_ESC" | gw_curl -sS -K - --connect-timeout 5 -m "$_M_SEC" $CURL_P "$@" 2>/dev/null || true)
        if _tg_resp_is_ok "$RESP"; then
            TG_LAST_ERR=""
            return 0
        fi
        API_DESC=$(_tg_extract_error "$RESP")
        if [ -n "$API_DESC" ]; then
            TG_LAST_ERR="$API_DESC"
            return 1
        fi
    done
    TG_LAST_ERR="Ошибка сети или TLS при обращении к api.telegram.org"
    return 1
}

send_telegram_msg() {
    MSG_TEXT="${1:-}"
    TG_LAST_ERR=""
    load_gateway_env
    [ -n "$MSG_TEXT" ] || { TG_LAST_ERR="Пустой текст сообщения"; return 1; }
    if ! is_telegram_configured; then
        TG_LAST_ERR="Telegram не настроен"
        return 1
    fi

    _tg_api_post "sendMessage" \
        -X POST \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=${MSG_TEXT}"
}

# Отправка архива резервной копии шлюза и Homelab файлом в Telegram
send_telegram_backup() {
    BAK_FILE="${1:-$BACKUP_ARCHIVE}"
    TG_LAST_ERR=""
    detect_os >/dev/null 2>&1 || true
    load_gateway_env
    if ! is_telegram_configured; then
        echo "${C_YEL}[!] Telegram-бот не настроен (укажите Токен и Chat ID в меню).${C_RES}"
        return 1
    fi
    if [ ! -f "$BAK_FILE" ]; then
        echo "${C_RED}[X] Файл бэкапа ${BAK_FILE} не найден!${C_RES}"
        return 1
    fi

    BAK_BYTES=$(wc -c < "$BAK_FILE" 2>/dev/null | tr -dc '0-9' || echo 0)
    if [ "${BAK_BYTES:-0}" -gt 52428800 ]; then
        echo "${C_RED}[X] Размер архива ${BAK_FILE} превышает лимит Telegram Bot API (50 МБ).${C_RES}"
        return 1
    fi
    B_SIZE=$(du -sh "$BAK_FILE" 2>/dev/null | awk '{print $1}' || echo "н/д")

    if is_openwrt 2>/dev/null; then
        BAK_TITLE="📦 Бэкап шлюза (${OS_NAME})"
    else
        BAK_TITLE="📦 Бэкап шлюза и Homelab (${OS_NAME})"
    fi
    CAPTION_TXT="${BAK_TITLE}
🔌 Ядро: $(get_active_core_name) ($(get_active_core_version))
🌐 LAN IP: $(get_current_lan_ip)
📏 Размер: ${B_SIZE}
🕒 Дата: $(date '+%Y-%m-%d %H:%M:%S')"

    echo "Отправка архива ${BAK_FILE} (${B_SIZE}) в ваш Telegram..."
    if _tg_api_post "sendDocument" \
        -F "chat_id=${TG_CHAT_ID}" \
        -F "caption=${CAPTION_TXT}" \
        -F "document=@${BAK_FILE}"; then
        echo "${C_GRN}[✓] Архив бэкапа успешно доставлен в ваш Telegram!${C_RES}"
        return 0
    fi
    echo "${C_RED}[X] Не удалось отправить бэкап в Telegram (${TG_LAST_ERR:-проверьте Токен, Chat ID и соединение}).${C_RES}"
    return 1
}

# Интерактивная настройка Telegram-бота для облачных бэкапов и уведомлений
configure_telegram_menu() {
    detect_os >/dev/null 2>&1 || true
    load_gateway_env
    echo ""
    ui_box_top "Настройка Telegram (Облачный бэкап + Уведомления)"
    if is_telegram_configured; then
        ui_box_row "• Статус: ${C_GRN}ПОДКЛЮЧЕН${C_RES} (Chat ID: ${TG_CHAT_ID})"
    else
        ui_box_row "• Статус: ${C_DIM}НЕ НАСТРОЕН${C_RES}"
    fi
    ui_box_sep
    ui_box_row "1) Указать / изменить Токен бота (@BotFather) и ваш Chat ID"
    ui_box_row "2) Отправить тестовое сообщение в Telegram"
    ui_box_row "3) Отключить Telegram-уведомления и очистить токен"
    ui_box_row "0) Назад"
    ui_box_bottom
    printf "Выбор [0-3]: "
    read -r TG_ACT < /dev/tty || true
    case "$TG_ACT" in
        1)
            printf "Введите API Token бота (от @BotFather): "
            read -r IN_TOK < /dev/tty || true
            IN_TOK=$(printf "%s" "$IN_TOK" | tr -d ' \t\r\n')
            printf "Введите ваш Chat ID (узнать можно в @userinfobot): "
            read -r IN_CID < /dev/tty || true
            IN_CID=$(printf "%s" "$IN_CID" | tr -d ' \t\r\n')
            if [ -n "$IN_TOK" ] && [ -n "$IN_CID" ]; then
                TG_BOT_TOKEN="$IN_TOK"
                TG_CHAT_ID="$IN_CID"
                save_gateway_env
                if send_telegram_msg "✅ Сервер (${OS_NAME} | $(get_current_lan_ip)) успешно подключен к Telegram!"; then
                    echo "${C_GRN}[✓] Настройки сохранены, тестовое сообщение доставлено!${C_RES}"
                else
                    echo "${C_YEL}[!] Настройки сохранены, но тестовое сообщение не прошло (${TG_LAST_ERR:-проверьте, нажали ли вы /start у бота}).${C_RES}"
                fi
            else
                echo "${C_RED}[X] Отмена: Токен и Chat ID не могут быть пустыми.${C_RES}"
            fi
            ;;
        2)
            if ! is_telegram_configured; then
                echo "${C_YEL}[!] Telegram-бот не настроен (сначала выберите п. 1 и укажите Токен и Chat ID).${C_RES}"
            elif send_telegram_msg "🔔 Проверка связи с сервером (${OS_NAME} | $(get_current_lan_ip)). Все системы работают нормально."; then
                echo "${C_GRN}[✓] Тестовое уведомление успешно отправлено!${C_RES}"
            else
                echo "${C_RED}[X] Ошибка отправки сообщения (${TG_LAST_ERR:-нет ответа от API}).${C_RES}"
            fi
            ;;
        3)
            TG_BOT_TOKEN=""
            TG_CHAT_ID=""
            save_gateway_env
            echo "${C_GRN}[✓] Telegram-уведомления отключены.${C_RES}"
            ;;
    esac
    return 0
}
