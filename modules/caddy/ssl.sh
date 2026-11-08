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
    return 0
}

# Настройка автоматического продления сертификата в crond Alpine
ensure_acme_cron_job() {
    CRON_CMD='acme.sh --cron --reloadcmd "/usr/sbin/caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile" >/dev/null 2>&1'
    if [ -f "$CRON_FILE" ]; then
        grep -Fq "acme.sh --cron" "$CRON_FILE" 2>/dev/null || echo "0 3 * * * ${CRON_CMD}" >> "$CRON_FILE"
    else
        mkdir -p "$(dirname "$CRON_FILE")"
        echo "0 3 * * * ${CRON_CMD}" > "$CRON_FILE"
    fi
    chmod 600 "$CRON_FILE" 2>/dev/null || true
    service_ctl cron enable >/dev/null 2>&1 || true
    service_ctl cron start >/dev/null 2>&1 || true
    return 0
}

# Выпуск боевого wildcard-сертификата Let's Encrypt через DuckDNS DNS-01 API
issue_duckdns_cert() {
    TARGET_SUB="$1"
    TARGET_TOKEN="$2"
    TARGET_SUB="$(printf "%s" "$TARGET_SUB" | tr 'A-Z' 'a-z' | sed 's/\.duckdns\.org$//;s/^\*\.//;s/^[[:space:]]*//;s/[[:space:]]*$//')"

    if [ -z "$TARGET_SUB" ] || [ -z "$TARGET_TOKEN" ]; then
        echo "${C_RED}[X] Ошибка: Укажите субдомен и токен DuckDNS!${C_RES}"
        return 1
    fi

    install_acme_core || return 1
    FULL_DOMAIN="${TARGET_SUB}.duckdns.org"

    echo "${C_CYN}[*] Регистрация аккаунта в Let's Encrypt ACME...${C_RES}"
    acme.sh --register-account -m "admin@${FULL_DOMAIN}" --server letsencrypt >/dev/null 2>&1 || true

    echo "${C_CYN}[*] Запрос Let's Encrypt Wildcard (*.${FULL_DOMAIN}) через DuckDNS DNS-01...${C_RES}"
    echo "    (Добавление TXT-записи без открытия портов наружу, ожидание DNS 60 сек)..."

    if ! DuckDNS_Token="$TARGET_TOKEN" acme.sh --server letsencrypt --issue --dns dns_duckdns -d "*.${FULL_DOMAIN}" --dnssleep 60 --force; then
        echo "${C_RED}[X] Ошибка выпуска сертификата Let's Encrypt! Проверьте правильность токена DuckDNS.${C_RES}"
        return 1
    fi

    mkdir -p "$SSL_CERTS_DIR"
    chmod 755 /etc/ssl "$SSL_CERTS_DIR" 2>/dev/null || true
    acme.sh --install-cert -d "*.${FULL_DOMAIN}" \
        --cert-file "${SSL_CERTS_DIR}/cert.pem" \
        --key-file "${SSL_KEY_FILE}" \
        --fullchain-file "${SSL_FULLCHAIN_FILE}" >/dev/null 2>&1

    chown -R caddy:caddy "$SSL_CERTS_DIR" 2>/dev/null || true
    chmod 644 "$SSL_CERTS_DIR"/*.pem 2>/dev/null || true

    ensure_acme_cron_job

    SSL_TYPE="letsencrypt"
    SSL_PROVIDER="duckdns"
    SSL_DOMAIN="${FULL_DOMAIN}"
    DUCKDNS_TOKEN="${TARGET_TOKEN}"
    save_homelab_env

    # Привязка A-записи DuckDNS к локальному IP шлюза, чтобы все клиенты локальной сети попадали на шлюз
    CUR_LAN_IP=$(get_current_lan_ip)
    if [ -n "$CUR_LAN_IP" ]; then
        curl -s -m 10 "https://www.duckdns.org/update?domains=${TARGET_SUB}&token=${TARGET_TOKEN}&ip=${CUR_LAN_IP}" >/dev/null 2>&1 || true
    fi

    sync_caddy_main_config
    command -v sync_all_caddy_sites >/dev/null 2>&1 && sync_all_caddy_sites || true
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
    echo "${C_CYN}[*] Принудительное продление сертификата для *.${SSL_DOMAIN}...${C_RES}"
    if DuckDNS_Token="${DUCKDNS_TOKEN:-}" acme.sh --renew -d "*.${SSL_DOMAIN}" --force; then
        acme.sh --install-cert -d "*.${SSL_DOMAIN}" \
            --cert-file "${SSL_CERTS_DIR}/cert.pem" \
            --key-file "${SSL_KEY_FILE}" \
            --fullchain-file "${SSL_FULLCHAIN_FILE}" >/dev/null 2>&1
        chmod 644 "$SSL_CERTS_DIR"/*.pem 2>/dev/null || true
        reload_caddy_safe
        command -v sync_all_caddy_sites >/dev/null 2>&1 && sync_all_caddy_sites || true
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
    command -v sync_all_caddy_sites >/dev/null 2>&1 && sync_all_caddy_sites || true
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
        read -r SSL_CHOICE || break
        case "$SSL_CHOICE" in
            1)
                echo ""
                echo "${C_BLD}--- Настройка Let's Encrypt Wildcard через DuckDNS (DNS-01) ---${C_RES}"
                echo " Сертификат будет действовать на все сервисы (zashboard, adguard, vaultwarden и др.)"
                echo " Регистрация и получение токена: ${C_CYN}https://www.duckdns.org${C_RES}"
                echo ""
                printf " Введите субдомен DuckDNS (например, 'dmzzone' для dmzzone.duckdns.org) [${SSL_DOMAIN%%.*}]: "
                read -r IN_SUB
                [ -z "$IN_SUB" ] && IN_SUB="${SSL_DOMAIN%%.*}"
                printf " Введите токен DuckDNS (UUID) [${DUCKDNS_TOKEN:-}]: "
                read -r IN_TOKEN
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
                read -r _
                ;;
            2)
                switch_to_local_pki
                printf "\nНажмите Enter для продолжения..."
                read -r _
                ;;
            3)
                renew_duckdns_cert_force
                printf "\nНажмите Enter для продолжения..."
                read -r _
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
