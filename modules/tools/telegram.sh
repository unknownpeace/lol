send_telegram_msg() {
    MSG_TEXT="$1"
    load_gateway_env
    is_telegram_configured || return 0

    TG_API_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage"
    for CURL_P in "-x http://127.0.0.1:7890" ""; do
        # shellcheck disable=SC2086
        if curl -fsSL --curves X25519:P-256 --connect-timeout 4 -m 8 $CURL_P \
            -X POST "$TG_API_URL" \
            --data-urlencode "chat_id=${TG_CHAT_ID}" \
            --data-urlencode "text=${MSG_TEXT}" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Отправка архива резервной копии шлюза и Homelab файлом в Telegram
send_telegram_backup() {
    BAK_FILE="${1:-$BACKUP_ARCHIVE}"
    load_gateway_env
    if ! is_telegram_configured; then
        echo "${C_YEL}[!] Telegram-бот не настроен (укажите Токен и Chat ID в меню).${C_RES}"
        return 1
    fi
    if [ ! -f "$BAK_FILE" ]; then
        echo "${C_RED}[X] Файл бэкапа ${BAK_FILE} не найден!${C_RES}"
        return 1
    fi

    CAPTION_TXT="📦 Бэкап шлюза и Homelab (${OS_NAME})
🌐 LAN IP: $(get_current_lan_ip)
🕒 Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    TG_DOC_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument"

    echo "Отправка архива ${BAK_FILE} в ваш Telegram..."
    for CURL_P in "-x http://127.0.0.1:7890" ""; do
        # shellcheck disable=SC2086
        if curl -fsSL --curves X25519:P-256 --connect-timeout 5 -m 30 $CURL_P \
            -F "chat_id=${TG_CHAT_ID}" \
            -F "caption=${CAPTION_TXT}" \
            -F "document=@${BAK_FILE}" \
            "$TG_DOC_URL" >/dev/null 2>&1; then
            echo "${C_GRN}[✓] Архив бэкапа успешно доставлен в ваш Telegram!${C_RES}"
            return 0
        fi
    done
    echo "${C_RED}[X] Не удалось отправить бэкап в Telegram (проверьте Токен, Chat ID и соединение).${C_RES}"
    return 1
}

# Интерактивная настройка Telegram-бота для облачных бэкапов и уведомлений
configure_telegram_menu() {
    load_gateway_env
    echo ""
    ui_box_top "Настройка Telegram (Облачный бэкап + Уведомления)"
    if is_telegram_configured; then
        echo " • Статус: ${C_GRN}ПОДКЛЮЧЕН${C_RES} (Chat ID: ${TG_CHAT_ID})"
    else
        echo " • Статус: ${C_DIM}НЕ НАСТРОЕН${C_RES}"
    fi
    ui_box_sep
    echo " 1) Указать / изменить Токен бота (@BotFather) и ваш Chat ID"
    echo " 2) Отправить тестовое сообщение в Telegram"
    echo " 3) Отключить Telegram-уведомления и очистить токен"
    echo " 0) Назад"
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
                    echo "${C_YEL}[!] Настройки сохранены, но тестовое сообщение не прошло (проверьте нажали ли вы /start у бота).${C_RES}"
                fi
            else
                echo "${C_RED}[X] Отмена: Токен и Chat ID не могут быть пустыми.${C_RES}"
            fi
            ;;
        2)
            if send_telegram_msg "🔔 Проверка связи с сервером (${OS_NAME} | $(get_current_lan_ip)). Все системы работают нормально."; then
                echo "${C_GRN}[✓] Тестовое уведомление успешно отправлено!${C_RES}"
            else
                echo "${C_RED}[X] Ошибка отправки сообщения.${C_RES}"
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

# Авто-ротация логов шлюза и сервисов Homelab (защита от переполнения диска)
