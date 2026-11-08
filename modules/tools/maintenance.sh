rotate_gateway_logs() {
    for LOG_F in "$SB_LOG_FILE" "$AUTOUPDATE_LOG" /var/log/caddy.log /var/log/vaultwarden.log /var/log/metube.log /var/log/code-server.log /var/log/transmission/transmission.log; do
        if [ -f "$LOG_F" ]; then
            F_SIZE=$(wc -c < "$LOG_F" 2>/dev/null | tr -d ' \t\r\n' || echo "0")
            if [ "${F_SIZE:-0}" -gt 1048576 ]; then
                tail -n 500 "$LOG_F" > "${LOG_F}.tmp" 2>/dev/null && mv -f "${LOG_F}.tmp" "$LOG_F" 2>/dev/null || true
            fi
        fi
    done
    return 0
}

# ==============================================================================
# Движок проверки обновлений Git и самообновления всего комплекса Gateway
# ==============================================================================

# Проверка наличия обновлений в Git-репозитории шлюза (с кэшированием на 2 часа для нулевых задержек)
check_gateway_repo_updates() {
    FORCE_CHK="${1:-no}"
    CACHE_F="/tmp/gateway_update_check.cache"
    NOW_TS=$(date +%s 2>/dev/null || echo 0)

    if [ "$FORCE_CHK" != "force" ] && [ -f "$CACHE_F" ]; then
        IFS='|' read -r C_STAT C_BEHIND C_REM C_TIME < "$CACHE_F" 2>/dev/null || true
        AGE=$(( NOW_TS - ${C_TIME:-0} ))
        if [ "$AGE" -ge 0 ] && [ "$AGE" -lt 7200 ]; then
            [ "$C_STAT" = "UPDATE_AVAILABLE" ] && return 0 || return 1
        fi
    fi

    if [ ! -d "${GATEWAY_DIR}/.git" ] || ! command -v git >/dev/null 2>&1; then
        echo "NO_GIT|0||${NOW_TS}" > "$CACHE_F" 2>/dev/null || true
        return 1
    fi

    CUR_BRANCH=$(git -C "${GATEWAY_DIR}" branch --show-current 2>/dev/null || echo "main")
    [ -z "$CUR_BRANCH" ] && CUR_BRANCH="main"

    # Быстрый fetch с таймаутом без блокировки консоли
    if ! git -C "${GATEWAY_DIR}" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=4 fetch --quiet origin "$CUR_BRANCH" >/dev/null 2>&1; then
        return 1
    fi

    LOCAL_H=$(git -C "${GATEWAY_DIR}" rev-parse HEAD 2>/dev/null || true)
    REMOTE_H=$(git -C "${GATEWAY_DIR}" rev-parse "origin/${CUR_BRANCH}" 2>/dev/null || true)

    if [ -n "$LOCAL_H" ] && [ -n "$REMOTE_H" ] && [ "$LOCAL_H" != "$REMOTE_H" ]; then
        BEHIND_CNT=$(git -C "${GATEWAY_DIR}" rev-list --count "HEAD..origin/${CUR_BRANCH}" 2>/dev/null || echo 1)
        echo "UPDATE_AVAILABLE|${BEHIND_CNT}|${REMOTE_H}|${NOW_TS}" > "$CACHE_F" 2>/dev/null || true
        return 0
    else
        echo "UP_TO_DATE|0|${LOCAL_H}|${NOW_TS}" > "$CACHE_F" 2>/dev/null || true
        return 1
    fi
}

# Получение компактного статуса версии для баннера MOTD и шапки меню
get_gateway_update_badge() {
    if check_gateway_repo_updates "no"; then
        B_CNT=$(awk -F'|' '{print $2}' /tmp/gateway_update_check.cache 2>/dev/null || echo 1)
        printf "%b" "${C_YEL}🔔 Доступно обновление (${B_CNT} комм.) ➔ gw update${C_RES}"
    else
        if [ -d "${GATEWAY_DIR}/.git" ] && command -v git >/dev/null 2>&1; then
            CUR_SHORT=$(git -C "${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo "main")
            printf "%b" "${C_GRN}v2026.11 (${CUR_SHORT}) [актуальна ●]${C_RES}"
        else
            printf "%b" "${C_GRN}v2026.11 (Standalone) [актуальна ●]${C_RES}"
        fi
    fi
}

# Полное атомарное самообновление: Git-репозиторий + ядра + модули Homelab
self_update_gateway() {
    SU_MODE="${1:-}"

    if [ "$SU_MODE" = "check" ] || [ "$SU_MODE" = "status" ]; then
        ui_banner "GATEWAY UPDATE // ПРОВЕРКА ОБНОВЛЕНИЙ ИЗ GIT"
        ui_step_progress 1 1 "Связь с удаленным Git-репозиторием..."
        CUR_BRANCH=$(git -C "${GATEWAY_DIR}" branch --show-current 2>/dev/null || echo "main")
        [ -z "$CUR_BRANCH" ] && CUR_BRANCH="main"
        if check_gateway_repo_updates "force"; then
            B_CNT=$(awk -F'|' '{print $2}' /tmp/gateway_update_check.cache 2>/dev/null || echo 1)
            ui_box_top "🔔 ДОСТУПНА НОВАЯ ВЕРСИЯ ШЛЮЗА (новых коммитов: ${B_CNT})"
            git -C "${GATEWAY_DIR}" log --oneline -n 5 "HEAD..origin/${CUR_BRANCH}" 2>/dev/null | while read -r line; do
                ui_box_row "  • ${line}"
            done
            ui_box_bottom
            echo "Для установки обновления выполните: ${C_CYN}gw update${C_RES}"
        else
            CUR_H=$(git -C "${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo "HEAD")
            ui_ok_msg "У вас установлена последняя версия Gateway (${CUR_H}), обновлений нет."
        fi
        return 0
    fi

    ui_banner "GATEWAY UPDATE // ПОЛНОЕ ОБНОВЛЕНИЕ ШЛЮЗА, ЯДЕР И HOMELAB"

    # 1. Обновление кодовой базы из Git
    UPDATED_REPO="no"
    if [ -d "${GATEWAY_DIR}/.git" ] && command -v git >/dev/null 2>&1; then
        ui_step_progress 1 5 "Загрузка обновлений скриптов шлюза из Git-репозитория..."
        cd "${GATEWAY_DIR}"
        CUR_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
        [ -z "$CUR_BRANCH" ] && CUR_BRANCH="main"
        if git fetch --quiet origin "$CUR_BRANCH" 2>/dev/null; then
            LOC_H=$(git rev-parse HEAD 2>/dev/null || true)
            REM_H=$(git rev-parse "origin/${CUR_BRANCH}" 2>/dev/null || true)
            if [ -n "$LOC_H" ] && [ -n "$REM_H" ] && [ "$LOC_H" != "$REM_H" ]; then
                ui_info_msg "Обнаружены новые изменения. Применение (git pull)..."
                STASHED="no"
                if ! git diff-index --quiet HEAD -- 2>/dev/null; then
                    git stash save --include-untracked "gateway_auto_stash_$(date +%s)" >/dev/null 2>&1 && STASHED="yes" || true
                fi
                if git pull --ff-only origin "$CUR_BRANCH" 2>/dev/null || git pull origin "$CUR_BRANCH" 2>/dev/null; then
                    UPDATED_REPO="yes"
                    ui_ok_msg "Кодовая база шлюза успешно обновлена до $(git rev-parse --short HEAD 2>/dev/null)!"
                else
                    ui_warn_box "Не удалось автоматически слить изменения Git (возможен локальный конфликт)." \
                                "Проверьте git status в каталоге ${GATEWAY_DIR}."
                fi
                if [ "$STASHED" = "yes" ]; then
                    git stash pop >/dev/null 2>&1 || true
                fi
            else
                ui_ok_msg "Скрипты шлюза уже соответствуют последней версии в репозитории."
            fi
        else
            ui_warn_box "Не удалось подключиться к Git-репозиторию." "Продолжаем обновление локальных бинарников и ядер."
        fi
        chmod +x "${GATEWAY_DIR}/gateway.sh" "${GATEWAY_DIR}/setup.sh" 2>/dev/null || true
        [ -d "${GATEWAY_DIR}/scripts" ] && chmod +x "${GATEWAY_DIR}/scripts/"*.sh 2>/dev/null || true
        ln -sf "${GATEWAY_DIR}/gateway.sh" /usr/bin/gateway 2>/dev/null || true
        ln -sf "${GATEWAY_DIR}/gateway.sh" /usr/bin/gw 2>/dev/null || true
        rm -f /tmp/gateway_update_check.cache 2>/dev/null || true
    fi

    # 2. Обновление ядер Sing-Box Extended, AdGuard Home и панели Zashboard
    ui_step_progress 2 5 "Обновление ядер Sing-Box Extended, AdGuard Home и панели Zashboard..."
    update_cores_only "yes"

    # 3. Обновление активных модулей Homelab
    ui_step_progress 3 5 "Проверка обновлений для активных модулей Homelab..."
    if [ -f "$HOMELAB_STATE" ]; then
        while IFS='|' read -r M_ID M_EN _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            if [ "$M_EN" = "yes" ]; then
                homelab_module_dispatch "$M_ID" "update" 2>/dev/null || true
            fi
        done < "$HOMELAB_STATE"
    fi

    # 4. Пересборка конфига, сброс conntrack и перезапуск
    ui_step_progress 4 5 "Пересборка конфигурации Sing-Box и перезапуск служб..."
    backup_gateway_state
    load_gateway_env
    if apply_and_verify_singbox "Полное обновление шлюза и компонентов"; then
        conntrack -F >/dev/null 2>&1 || true
        service_ctl sing-box restart || true
        service_ctl adguardhome restart || true
    fi

    # 5. Итоговый отчет о готовности
    ui_step_progress 5 5 "Верификация состояния обновленной системы..."
    sleep 2
    echo ""
    ui_box_top "🎉 РЕЗУЛЬТАТ ПОЛНОГО ОБНОВЛЕНИЯ СЕРВЕРА"
    if pgrep sing-box >/dev/null 2>&1 && pgrep AdGuardHome >/dev/null 2>&1; then
        ui_box_row "${C_GRN}[✔] Все службы шлюза и модули Homelab активны и работают стабильно!${C_RES}"
    else
        ui_box_row "${C_YEL}[▲] Некоторые службы перезапускаются или требуют внимания (запустите: gw doctor)${C_RES}"
    fi
    ui_box_row "• Версия скриптов: $(git -C "${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo 'Standalone')"
    ui_box_row "• Ядро Sing-Box:   $(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || echo 'OK')"
    ui_box_row "• AdGuard Home:    $(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || echo 'OK')"
    ui_box_bottom
    echo ""

    if [ "$UPDATED_REPO" = "yes" ]; then
        ui_info_msg "Процесс шлюза будет перезапущен для применения обновленного кода..."
        sleep 1
        exec /usr/bin/gw motd
    fi
    return 0
}

# Активное сканирование всей /24 подсети LAN (прогрев ARP-таблицы за ~1.5 сек)
