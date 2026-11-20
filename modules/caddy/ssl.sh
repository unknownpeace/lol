#!/bin/sh
set -e

# ==============================================================================
# 🔒 Управление SSL/TLS сертификатами (Local PKI vs Let's Encrypt Wildcard)
# Поддержка DNS-01 через DuckDNS API без открытия портов наружу
# ==============================================================================

is_letsencrypt_ssl_active() {
    [ "${SSL_TYPE:-local}" = "letsencrypt" ] && \
    [ -n "${SSL_DOMAIN:-}" ] && \
    [ -s "${SSL_FULLCHAIN_FILE:-/etc/ssl/caddy/fullchain.pem}" ] && \
    [ -s "${SSL_KEY_FILE:-/etc/ssl/caddy/key.pem}" ]
}

ACME_HOME_DIR="/root/.acme.sh"

# Гарантированная установка acme.sh и необходимых утилит в Alpine Linux
install_acme_core() {
    if ! command -v acme.sh >/dev/null 2>&1; then
        echo "${C_CYN}[*] Установка acme.sh и криптографических утилит...${C_RES}"
        ensure_alpine_community_repo
        if command -v apk >/dev/null 2>&1; then
            apk add --no-cache acme.sh socat curl openssl >/dev/null 2>&1 || apk add acme.sh socat curl openssl >/dev/null 2>&1 || true
        fi
    fi
    if ! command -v acme.sh >/dev/null 2>&1; then
        echo "${C_RED}[X] Ошибка: Не удалось установить acme.sh!${C_RES}"
        return 1
    fi
    mkdir -p "$ACME_HOME_DIR"
    return 0
}

# Настройка автоматического продления сертификата в crond Alpine
ensure_acme_cron_job() {
    ACME_BIN=$(command -v acme.sh 2>/dev/null || echo "/usr/bin/acme.sh")
    CRON_LINE="0 3 * * * ${ACME_BIN} --cron --home ${ACME_HOME_DIR} >/dev/null 2>&1"
    mkdir -p "$(dirname "$CRON_FILE")"
    if [ -f "$CRON_FILE" ]; then
        awk '!/acme\.sh --cron/' "$CRON_FILE" > "${CRON_FILE}.tmp.$$" && mv -f "${CRON_FILE}.tmp.$$" "$CRON_FILE"
    else
        : > "$CRON_FILE"
    fi
    echo "$CRON_LINE" >> "$CRON_FILE"
    chmod 600 "$CRON_FILE" 2>/dev/null || true
    service_ctl cron enable >/dev/null 2>&1 || true
    service_ctl cron start >/dev/null 2>&1 || true
    return 0
}

# Выпуск боевого wildcard-сертификата Let's Encrypt через DuckDNS DNS-01 API
issue_duckdns_cert() {
    TARGET_SUB=$(clean_clipboard_line "${1:-}")
    TARGET_TOKEN=$(clean_clipboard_line "${2:-}")
    TARGET_SUB=$(printf "%s" "$TARGET_SUB" | tr 'A-Z' 'a-z' | sed -E 's|^https?://||; s|^\*\.||; s|/.*$||; s|\.duckdns\.org$||; s/^[[:space:]]+//; s/[[:space:]]+$//')
    TARGET_TOKEN=$(printf "%s" "$TARGET_TOKEN" | tr -d ' \t\r\n')

    if [ -z "$TARGET_SUB" ] || [ -z "$TARGET_TOKEN" ]; then
        echo "${C_RED}[X] Ошибка: Укажите субдомен и токен DuckDNS!${C_RES}"
        return 1
    fi

    install_acme_core || return 1
    FULL_DOMAIN="${TARGET_SUB}.duckdns.org"

    # Предварительная проверка токена и субдомена в DuckDNS API (и привязка A-записи к LAN IP шлюза)
    CUR_LAN_IP=$(get_current_lan_ip)
    DUCK_RES=$(curl -fsS --connect-timeout 5 -m 10 "https://www.duckdns.org/update?domains=${TARGET_SUB}&token=${TARGET_TOKEN}&ip=${CUR_LAN_IP:-127.0.0.1}" 2>/dev/null | tr -d ' \t\r\n' || true)
    if [ "$DUCK_RES" != "OK" ]; then
        echo "${C_RED}[X] Ошибка DuckDNS API (ответ: ${DUCK_RES:-таймаут})! Проверьте правильность субдомена '${TARGET_SUB}' и токена.${C_RES}"
        return 1
    fi

    FORCE_ISSUE="${3:-no}"
    EXISTING_CERT=""
    for _c_cand in "${ACME_HOME_DIR}/*.${FULL_DOMAIN}_ecc/fullchain.cer" "${ACME_HOME_DIR}/*.${FULL_DOMAIN}/fullchain.cer"; do
        if [ -s "$_c_cand" ]; then
            EXISTING_CERT="$_c_cand"
            break
        fi
    done

    REUSED_CERT="no"
    if [ "$FORCE_ISSUE" != "--force" ] && [ -n "$EXISTING_CERT" ] && command -v openssl >/dev/null 2>&1; then
        if openssl x509 -checkend 1209600 -noout -in "$EXISTING_CERT" >/dev/null 2>&1; then
            REUSED_CERT="yes"
            echo "${C_GRN}[✓] Найден действующий Let's Encrypt Wildcard (*.${FULL_DOMAIN}, запас > 14 дн.) — переиспользуем без повторного запроса к ACME!${C_RES}"
        fi
    fi

    if [ "$REUSED_CERT" != "yes" ]; then
        echo "${C_CYN}[*] Регистрация аккаунта в Let's Encrypt ACME...${C_RES}"
        acme.sh --home "$ACME_HOME_DIR" --register-account -m "admin@${FULL_DOMAIN}" --server letsencrypt >/dev/null 2>&1 || true

        echo "${C_CYN}[*] Запрос Let's Encrypt Wildcard (*.${FULL_DOMAIN}) через DuckDNS DNS-01...${C_RES}"
        echo "    (Добавление TXT-записи без открытия портов наружу, ожидание DNS 60 сек)..."

        if ! DuckDNS_Token="$TARGET_TOKEN" acme.sh --home "$ACME_HOME_DIR" --server letsencrypt --issue --dns dns_duckdns -d "*.${FULL_DOMAIN}" --dnssleep 60 --force; then
            echo "${C_RED}[X] Ошибка выпуска сертификата Let's Encrypt! Проверьте токен DuckDNS и доступ к ACME API.${C_RES}"
            return 1
        fi
    fi

    mkdir -p "$SSL_CERTS_DIR"
    chmod 755 /etc/ssl 2>/dev/null || true
    chmod 750 "$SSL_CERTS_DIR" 2>/dev/null || true
    if ! acme.sh --home "$ACME_HOME_DIR" --install-cert -d "*.${FULL_DOMAIN}" \
        --cert-file "${SSL_CERTS_DIR}/cert.pem" \
        --key-file "${SSL_KEY_FILE}" \
        --fullchain-file "${SSL_FULLCHAIN_FILE}" \
        --reloadcmd "chown -R caddy:caddy '${SSL_CERTS_DIR}' && chmod 750 '${SSL_CERTS_DIR}' && chmod 644 '${SSL_CERTS_DIR}/cert.pem' '${SSL_FULLCHAIN_FILE}' && chmod 600 '${SSL_KEY_FILE}' && rc-service caddy restart"; then
        echo "${C_RED}[X] Ошибка установки файлов сертификата в ${SSL_CERTS_DIR}!${C_RES}"
        return 1
    fi

    chown -R caddy:caddy "$SSL_CERTS_DIR" 2>/dev/null || true
    chmod 750 "$SSL_CERTS_DIR" 2>/dev/null || true
    chmod 644 "${SSL_CERTS_DIR}/cert.pem" "$SSL_FULLCHAIN_FILE" 2>/dev/null || true
    chmod 600 "$SSL_KEY_FILE" 2>/dev/null || true

    ensure_acme_cron_job

    SSL_TYPE="letsencrypt"
    SSL_PROVIDER="duckdns"
    SSL_DOMAIN="${FULL_DOMAIN}"
    DUCKDNS_TOKEN="${TARGET_TOKEN}"
    save_homelab_env

    sync_caddy_main_config
    if command -v sync_all_caddy_sites >/dev/null 2>&1; then
        sync_all_caddy_sites
    elif command -v reload_caddy_safe >/dev/null 2>&1; then
        reload_caddy_safe
    fi
    sync_agh_homelab_rewrites

    echo "${C_GRN}[✓] Wildcard-сертификат Let's Encrypt (*.${FULL_DOMAIN}) успешно получен и установлен!${C_RES}"
    return 0
}

# Принудительное ручное продление сертификата
renew_duckdns_cert_force() {
    load_gateway_env
    if [ -z "${SSL_DOMAIN:-}" ]; then
        echo "${C_RED}[X] Ошибка: Домен Let's Encrypt не настроен!${C_RES}"
        return 1
    fi
    ACME_CERT_ID="*.${SSL_DOMAIN}"
    if [ ! -d "${ACME_HOME_DIR}/*.${SSL_DOMAIN}" ] && [ ! -d "${ACME_HOME_DIR}/*.${SSL_DOMAIN}_ecc" ]; then
        ACME_CERT_ID="${SSL_DOMAIN}"
    fi
    echo "${C_CYN}[*] Принудительное продление сертификата для *.${SSL_DOMAIN}...${C_RES}"
    if DuckDNS_Token="${DUCKDNS_TOKEN:-}" acme.sh --home "$ACME_HOME_DIR" --renew -d "${ACME_CERT_ID}" --force; then
        if ! acme.sh --home "$ACME_HOME_DIR" --install-cert -d "${ACME_CERT_ID}" \
            --cert-file "${SSL_CERTS_DIR}/cert.pem" \
            --key-file "${SSL_KEY_FILE}" \
            --fullchain-file "${SSL_FULLCHAIN_FILE}" \
            --reloadcmd "chown -R caddy:caddy '${SSL_CERTS_DIR}' && chmod 750 '${SSL_CERTS_DIR}' && chmod 644 '${SSL_CERTS_DIR}/cert.pem' '${SSL_FULLCHAIN_FILE}' && chmod 600 '${SSL_KEY_FILE}' && rc-service caddy restart"; then
            echo "${C_RED}[X] Ошибка установки обновленного сертификата в ${SSL_CERTS_DIR}!${C_RES}"
            return 1
        fi
        chown -R caddy:caddy "$SSL_CERTS_DIR" 2>/dev/null || true
        chmod 750 "$SSL_CERTS_DIR" 2>/dev/null || true
        chmod 644 "${SSL_CERTS_DIR}/cert.pem" "$SSL_FULLCHAIN_FILE" 2>/dev/null || true
        chmod 600 "$SSL_KEY_FILE" 2>/dev/null || true
        if command -v sync_all_caddy_sites >/dev/null 2>&1; then
            sync_all_caddy_sites
        elif command -v reload_caddy_safe >/dev/null 2>&1; then
            reload_caddy_safe
        fi
        echo "${C_GRN}[✓] Сертификат успешно обновлен, Caddy перезагружен.${C_RES}"
        return 0
    else
        echo "${C_RED}[X] Ошибка продления сертификата!${C_RES}"
        return 1
    fi
}

# Переключение обратно на локальный самоподписной PKI (*.lan)
switch_to_local_pki() {
    load_gateway_env
    SSL_TYPE="local"
    save_homelab_env
    echo "${C_CYN}[*] Переключение HTTPS на локальный PKI (*.lan)...${C_RES}"
    sync_caddy_main_config
    if command -v sync_all_caddy_sites >/dev/null 2>&1; then
        sync_all_caddy_sites
    elif command -v reload_caddy_safe >/dev/null 2>&1; then
        reload_caddy_safe
    fi
    sync_agh_homelab_rewrites
    echo "${C_GRN}[✓] Шлюз переведен в оффлайн-режим Local PKI (*.lan).${C_RES}"
    return 0
}

# Наглядный отчет о текущем статусе SSL/TLS
show_ssl_status() {
    load_gateway_env
    ui_box_top "🔒 СТАТУС SSL/TLS СЕРТИФИКАТА ШЛЮЗА"

    if is_letsencrypt_ssl_active; then
        ui_box_row "Режим HTTPS:       ${C_GRN}● Валидный Let's Encrypt Wildcard${C_RES} (Глобально доверенный)"
        ui_box_row "Рабочий домен:     ${C_CYN}*.${SSL_DOMAIN}${C_RES} (Провайдер: ${SSL_PROVIDER})"
        ui_box_row "Файлы ключей:      ${SSL_FULLCHAIN_FILE}"

        if [ -s "$SSL_FULLCHAIN_FILE" ] && command -v openssl >/dev/null 2>&1; then
            ISSUER_NAME=$(openssl x509 -in "$SSL_FULLCHAIN_FILE" -noout -issuer 2>/dev/null | sed 's/.*CN[[:space:]]*=[[:space:]]*//' || echo "Let's Encrypt")
            NOT_AFTER=$(openssl x509 -in "$SSL_FULLCHAIN_FILE" -noout -enddate 2>/dev/null | cut -d= -f2 || true)
            CLEAN_DATE=$(printf "%s" "$NOT_AFTER" | sed -E 's/  +/ 0/')
            EXP_SEC=$(date -D '%b %d %T %Y GMT' -d "$CLEAN_DATE" +%s 2>/dev/null || date -d "$NOT_AFTER" +%s 2>/dev/null || echo 0)
            NOW_SEC=$(date +%s 2>/dev/null || echo 0)
            if [ "$EXP_SEC" -gt "$NOW_SEC" ]; then
                DAYS_LEFT=$(( (EXP_SEC - NOW_SEC) / 86400 ))
                ui_box_row "Действителен до:   ${NOT_AFTER} (${C_GRN}${DAYS_LEFT} дн. осталось${C_RES}, эмитент: ${ISSUER_NAME})"
            else
                ui_box_row "Действителен до:   ${NOT_AFTER} (эмитент: ${ISSUER_NAME})"
            fi
        fi
        ui_box_row "Авто-продление:    ${C_GRN}● АКТИВНО${C_RES} (crond проверяет продление раз в сутки в 03:00)"
    else
        ui_box_row "Режим HTTPS:       ${C_CYN}● Локальный CA (Local PKI / *.lan)${C_RES}"
        ui_box_row "Корневой CA:       http://${DOM_CA:-ca.lan} (установка сертификата на устройства)"
        ui_box_row "Статус доверия:    Требует однократной установки homelab-root-ca.crt на клиентах"
        ui_box_row "Альтернатива:      Возможно переключение на бесплатный Let's Encrypt (DuckDNS)"
    fi

    ui_box_bottom
    return 0
}

# Интерактивное TUI-меню управления SSL/TLS сертификатами
prompt_ssl_management_menu() {
    load_gateway_env
    while true; do
        show_ssl_status
        echo ""
        echo " ${C_BLD}Выберите действие:${C_RES}"
        echo "   ${C_CYN}1${C_RES}) Подключить / перевыпустить Let's Encrypt Wildcard (DuckDNS)"
        echo "   ${C_CYN}2${C_RES}) Переключиться на локальный самоподписной PKI (*.lan)"
        echo "   ${C_CYN}3${C_RES}) Принудительно продлить сертификат (Force Renew)"
        echo "   ${C_CYN}0${C_RES}) Назад в главное меню"
        echo ""
        printf " Ваш выбор [0-3]: "
        read -r SSL_CHOICE < /dev/tty || break
        SSL_CHOICE=$(clean_clipboard_line "$SSL_CHOICE")
        case "$SSL_CHOICE" in
            1)
                echo ""
                echo "${C_BLD}--- Настройка Let's Encrypt Wildcard через DuckDNS (DNS-01) ---${C_RES}"
                echo " Сертификат будет действовать на все сервисы (zashboard, adguard, vaultwarden и др.)"
                echo " Регистрация и получение токена: ${C_CYN}https://www.duckdns.org${C_RES}"
                echo ""
                printf " Введите субдомен DuckDNS (например, 'dmzzone' для dmzzone.duckdns.org) [%s]: " "${SSL_DOMAIN%%.*}"
                read -r IN_SUB < /dev/tty || true
                IN_SUB=$(clean_clipboard_line "$IN_SUB")
                [ -z "$IN_SUB" ] && IN_SUB="${SSL_DOMAIN%%.*}"
                printf " Введите токен DuckDNS (UUID) [%s]: " "${DUCKDNS_TOKEN:-}"
                read -r IN_TOKEN < /dev/tty || true
                IN_TOKEN=$(clean_clipboard_line "$IN_TOKEN")
                [ -z "$IN_TOKEN" ] && IN_TOKEN="${DUCKDNS_TOKEN:-}"

                if [ -n "$IN_SUB" ] && [ -n "$IN_TOKEN" ]; then
                    if issue_duckdns_cert "$IN_SUB" "$IN_TOKEN"; then
                        ui_ok_msg "Все сервисы переведены на официальный Let's Encrypt Wildcard!"
                        echo "   Панель Sing-Box: https://zashboard.${IN_SUB}.duckdns.org"
                        echo "   Панель AdGuard:  https://adguard.${IN_SUB}.duckdns.org"
                    fi
                else
                    echo "${C_RED}[X] Отменено: субдомен или токен не указаны.${C_RES}"
                fi
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            2)
                switch_to_local_pki
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            3)
                renew_duckdns_cert_force
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            0|q|exit)
                break
                ;;
            *)
                ;;
        esac
    done
    return 0
}
