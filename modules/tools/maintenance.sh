#!/bin/sh
rotate_gateway_logs() {
    ensure_gateway_runtime_dir >/dev/null 2>&1 || true
    for LOG_F in "$SB_LOG_FILE" "$MIHOMO_LOG_FILE" "$AUTOUPDATE_LOG" /var/log/gateway-webui.log /var/log/gateway-console.log /var/log/caddy.log /var/log/vaultwarden.log /var/log/metube.log /var/log/code-server.log /var/log/transmission/transmission.log; do
        if [ -f "$LOG_F" ]; then
            F_SIZE=$(wc -c < "$LOG_F" 2>/dev/null | tr -d ' \t\r\n' || echo "0")
            if [ "${F_SIZE:-0}" -gt 1048576 ]; then
                _log_tmp=$(mktemp "${GATEWAY_RUNTIME_DIR:-/run/gateway}/logrot.XXXXXX" 2>/dev/null || printf "%s" "${GATEWAY_RUNTIME_DIR:-/run/gateway}/logrot.$$")
                if tail -n 500 "$LOG_F" > "$_log_tmp" 2>/dev/null; then
                    cat "$_log_tmp" > "$LOG_F" 2>/dev/null || true
                fi
                rm -f "$_log_tmp" 2>/dev/null || true
            fi
        fi
    done
    return 0
}

# ==============================================================================
# Движок проверки обновлений Git и самообновления всего комплекса Gateway
# ==============================================================================

# Проверка наличия обновлений в Git-репозитории шлюза (с кэшированием в /run/gateway на 2 часа)
check_gateway_repo_updates() {
    FORCE_CHK="${1:-no}"
    ensure_gateway_runtime_dir >/dev/null 2>&1 || true
    CACHE_F="${GATEWAY_UPDATE_CACHE:-/run/gateway/update_check.cache}"
    NOW_TS=$(date +%s 2>/dev/null || echo 0)

    if [ "$FORCE_CHK" != "force" ] && [ -f "$CACHE_F" ]; then
        IFS='|' read -r C_STAT _C_BEHIND _C_REM C_TIME < "$CACHE_F" 2>/dev/null || true
        AGE=$(( NOW_TS - ${C_TIME:-0} ))
        if [ "$C_STAT" != "FETCH_ERROR" ] && [ "$AGE" -ge 0 ] && [ "$AGE" -lt 7200 ]; then
            [ "$C_STAT" = "UPDATE_AVAILABLE" ] && return 0 || return 1
        fi
    fi

    if [ ! -d "${GATEWAY_DIR}/.git" ] || ! command -v git >/dev/null 2>&1; then
        printf "NO_GIT|0||%s\n" "$NOW_TS" > "$CACHE_F" 2>/dev/null || true
        chmod 600 "$CACHE_F" 2>/dev/null || true
        return 1
    fi

    CUR_BRANCH=$(GIT_TERMINAL_PROMPT=0 git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" branch --show-current 2>/dev/null || echo "main")
    [ -z "$CUR_BRANCH" ] && CUR_BRANCH="main"

    # Быстрый fetch без блокировки на запросе пароля
    if ! GIT_TERMINAL_PROMPT=0 git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=4 fetch --quiet origin "$CUR_BRANCH" >/dev/null 2>&1; then
        printf "FETCH_ERROR|0||%s\n" "$NOW_TS" > "$CACHE_F" 2>/dev/null || true
        chmod 600 "$CACHE_F" 2>/dev/null || true
        return 1
    fi

    LOCAL_H=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse HEAD 2>/dev/null || true)
    REMOTE_H=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse "origin/${CUR_BRANCH}" 2>/dev/null || true)
    BEHIND_CNT=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-list --count "HEAD..origin/${CUR_BRANCH}" 2>/dev/null | tr -dc '0-9' || true)
    [ -z "$BEHIND_CNT" ] && BEHIND_CNT=0

    if [ -n "$LOCAL_H" ] && [ -n "$REMOTE_H" ] && [ "$BEHIND_CNT" -gt 0 ]; then
        printf "UPDATE_AVAILABLE|%s|%s|%s\n" "$BEHIND_CNT" "$REMOTE_H" "$NOW_TS" > "$CACHE_F" 2>/dev/null || true
        chmod 600 "$CACHE_F" 2>/dev/null || true
        return 0
    else
        printf "UP_TO_DATE|0|%s|%s\n" "$LOCAL_H" "$NOW_TS" > "$CACHE_F" 2>/dev/null || true
        chmod 600 "$CACHE_F" 2>/dev/null || true
        return 1
    fi
}

# Получение компактного статуса версии для баннера MOTD и шапки меню
get_gateway_update_badge() {
    _badge_mode="${1:-}"
    CACHE_F="${GATEWAY_UPDATE_CACHE:-/run/gateway/update_check.cache}"
    _has_upd=1
    if [ "$_badge_mode" = "cache-only" ]; then
        if [ -f "$CACHE_F" ]; then
            IFS='|' read -r _c_stat _c_cnt _rest < "$CACHE_F" 2>/dev/null || true
            [ "$_c_stat" = "UPDATE_AVAILABLE" ] && _has_upd=0
        fi
    else
        check_gateway_repo_updates "no" && _has_upd=0
    fi

    if [ "$_has_upd" -eq 0 ]; then
        B_CNT=$(awk -F'|' '{print $2}' "$CACHE_F" 2>/dev/null || echo 1)
        printf "%b" "${C_YEL}🔔 Доступно обновление (${B_CNT} комм.) ➔ gw update${C_RES}"
    else
        if [ -d "${GATEWAY_DIR}/.git" ] && command -v git >/dev/null 2>&1; then
            CUR_SHORT=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo "main")
            printf "%b" "${C_GRN}v2026.11 (${CUR_SHORT}) [актуальна ●]${C_RES}"
        else
            printf "%b" "${C_GRN}v2026.11 (Standalone) [актуальна ●]${C_RES}"
        fi
    fi
}

# Полное атомарное самообновление: Git-репозиторий + ядра + модули Homelab
self_update_gateway() {
    SU_MODE="${1:-}"
    CACHE_F="${GATEWAY_UPDATE_CACHE:-/run/gateway/update_check.cache}"

    if [ "$SU_MODE" = "check" ] || [ "$SU_MODE" = "status" ]; then
        ui_banner "GATEWAY UPDATE // ПРОВЕРКА ОБНОВЛЕНИЙ ИЗ GIT"
        ui_step_progress 1 1 "Связь с удаленным Git-репозиторием..."
        CUR_BRANCH=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" branch --show-current 2>/dev/null || echo "main")
        [ -z "$CUR_BRANCH" ] && CUR_BRANCH="main"
        if check_gateway_repo_updates "force"; then
            B_CNT=$(awk -F'|' '{print $2}' "$CACHE_F" 2>/dev/null || echo 1)
            ui_box_top "🔔 ДОСТУПНА НОВАЯ ВЕРСИЯ ШЛЮЗА (новых коммитов: ${B_CNT})"
            git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" log --oneline -n 5 "HEAD..origin/${CUR_BRANCH}" 2>/dev/null | while IFS= read -r line; do
                ui_box_row "  • ${line}"
            done
            ui_box_bottom
            echo "Для установки обновления выполните: ${C_CYN}gw update${C_RES}"
        else
            C_STAT=""
            [ -f "$CACHE_F" ] && IFS='|' read -r C_STAT _REST < "$CACHE_F" 2>/dev/null || true
            case "$C_STAT" in
                NO_GIT)
                    ui_warn_box "Режим Standalone (без Git-репозитория)." \
                                "В каталоге ${GATEWAY_DIR} отсутствует .git — проверка обновлений скриптов недоступна."
                    ;;
                FETCH_ERROR)
                    ui_warn_box "Не удалось связаться с удаленным репозиторием origin/${CUR_BRANCH}." \
                                "Проверьте доступ к Git и повторите: gw update check"
                    ;;
                *)
                    CUR_H=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo "HEAD")
                    ui_ok_msg "У вас установлена последняя версия Gateway (${CUR_H}), обновлений нет."
                    ;;
            esac
        fi
        return 0
    fi

    _upd_wait=0
    while ! acquire_gateway_lock "update"; do
        sleep 1
        _upd_wait=$((_upd_wait + 1))
        if [ "$_upd_wait" -ge 15 ]; then
            ui_warn_box "Обновление уже выполняется другим процессом (${GATEWAY_LOCK_DIR})." "Повторите через несколько секунд."
            return 1
        fi
    done
    trap 'release_gateway_lock' EXIT INT TERM HUP

    if is_openwrt 2>/dev/null; then
        ui_banner "GATEWAY UPDATE // ПОЛНОЕ ОБНОВЛЕНИЕ ШЛЮЗА И ЯДЕР"
    else
        ui_banner "GATEWAY UPDATE // ПОЛНОЕ ОБНОВЛЕНИЕ ШЛЮЗА, ЯДЕР И HOMELAB"
    fi

    # 1. Обновление кодовой базы из Git (строго --ff-only и без конфликтов перед re-exec)
    UPDATED_REPO="no"
    REPO_CONFLICT="no"
    if [ -d "${GATEWAY_DIR}/.git" ] && command -v git >/dev/null 2>&1; then
        ui_step_progress 1 5 "Загрузка обновлений скриптов шлюза из Git-репозитория..."
        CUR_BRANCH=$(GIT_TERMINAL_PROMPT=0 git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" branch --show-current 2>/dev/null || echo "main")
        [ -z "$CUR_BRANCH" ] && CUR_BRANCH="main"
        if GIT_TERMINAL_PROMPT=0 git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=8 fetch --quiet origin "$CUR_BRANCH" 2>/dev/null; then
            BEHIND_CNT=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-list --count "HEAD..origin/${CUR_BRANCH}" 2>/dev/null | tr -dc '0-9' || true)
            [ -z "$BEHIND_CNT" ] && BEHIND_CNT=0
            if [ "$BEHIND_CNT" -gt 0 ]; then
                ui_info_msg "Обнаружены новые изменения (коммитов: ${BEHIND_CNT}). Применение (git pull --ff-only)..."
                STASHED="no"
                DIRTY_OUT=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" status --porcelain 2>/dev/null || true)
                if [ -n "$DIRTY_OUT" ]; then
                    if git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" -c user.name="Gateway AutoUpdate" -c user.email="gateway@localhost" stash push --include-untracked -m "gateway_auto_stash_$(date +%s)" >/dev/null 2>&1; then
                        STASHED="yes"
                    fi
                fi
                if GIT_TERMINAL_PROMPT=0 git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" -c user.name="Gateway AutoUpdate" -c user.email="gateway@localhost" pull --ff-only origin "$CUR_BRANCH" 2>/dev/null; then
                    UPDATED_REPO="yes"
                    NEW_H=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo "HEAD")
                    ui_ok_msg "Кодовая база шлюза успешно обновлена до ${NEW_H}!"
                else
                    REPO_CONFLICT="yes"
                    ui_warn_box "Не удалось обновить код через --ff-only (история Git разошлась с origin/${CUR_BRANCH})." \
                                "Проверьте 'git status' и 'git log' в каталоге ${GATEWAY_DIR}."
                fi
                if [ "$STASHED" = "yes" ]; then
                    if ! git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" stash pop >/dev/null 2>&1; then
                        REPO_CONFLICT="yes"
                        git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" checkout -- . >/dev/null 2>&1 || true
                        ui_warn_box "Локальные изменения сохранены в git stash (конфликт при возврате откачен)." \
                                    "Проверьте 'git stash list' в каталоге ${GATEWAY_DIR}."
                    fi
                fi
            else
                ui_ok_msg "Скрипты шлюза уже соответствуют последней версии в репозитории."
            fi
        else
            ui_warn_box "Не удалось подключиться к Git-репозиторию." "Продолжаем обновление локальных бинарников и ядер."
        fi
        chmod +x "${GATEWAY_DIR}/gateway.sh" "${GATEWAY_DIR}/setup.sh" 2>/dev/null || true
        if [ -f "${GATEWAY_DIR}/gateway.sh" ]; then
            ln -sf "${GATEWAY_DIR}/gateway.sh" /usr/bin/gateway 2>/dev/null || true
            ln -sf "${GATEWAY_DIR}/gateway.sh" /usr/bin/gw 2>/dev/null || true
        fi
        rm -f "$CACHE_F" 2>/dev/null || true
        if [ "$REPO_CONFLICT" = "yes" ]; then
            release_gateway_lock
            trap - EXIT INT TERM HUP
            return 1
        fi
        if [ "$UPDATED_REPO" = "yes" ] && [ -z "${GATEWAY_SELF_UPDATE_REEXEC:-}" ]; then
            ui_info_msg "Перезапуск процесса обновления для применения нового кода скриптов..."
            release_gateway_lock
            trap - EXIT INT TERM HUP
            GATEWAY_SELF_UPDATE_REEXEC=1 exec /usr/bin/gw update
        fi
    else
        ui_step_progress 1 5 "Установка без Git (Standalone) — пропуск обновления скриптов..."
    fi

    # 2. Обновление активного ядра, AdGuard Home и выбранной веб-панели
    ui_step_progress 2 5 "Обновление ядер $(get_active_core_name), AdGuard Home и панели $(get_active_ui_name)..."
    update_cores_only "yes"

    # 3. Обновление активных модулей Homelab (только Alpine Linux)
    if ! is_openwrt && [ -f "$HOMELAB_STATE" ]; then
        ui_step_progress 3 5 "Проверка обновлений для активных модулей Homelab..."
        while IFS='|' read -r M_ID M_EN _REST; do
            case "$M_ID" in ''|\#*) continue ;; esac
            if [ "$M_EN" = "yes" ]; then
                homelab_module_dispatch "$M_ID" "update" 2>/dev/null || true
            fi
        done < "$HOMELAB_STATE"
    else
        ui_step_progress 3 5 "Модули Homelab не используются в режиме ${OS_NAME} (пропуск)..."
    fi

    # 4. Пересборка конфига, сброс conntrack и синхронный перезапуск служб
    ui_step_progress 4 5 "Пересборка конфигурации $(get_active_core_name) и перезапуск служб..."
    backup_gateway_state
    load_gateway_env
    if apply_and_verify_core "Полное обновление шлюза и компонентов"; then
        conntrack -F >/dev/null 2>&1 || true
        service_ctl adguardhome restart || true
    else
        pgrep AdGuardHome >/dev/null 2>&1 || service_ctl adguardhome start || true
    fi
    is_openwrt && install_openwrt_luci_app >/dev/null 2>&1 || true
    if ! is_openwrt 2>/dev/null; then
        install_alpine_webui >/dev/null 2>&1 || true
    fi

    # 5. Итоговый отчет о готовности
    ui_step_progress 5 5 "Верификация состояния обновленной системы..."
    W_SVC=0
    while [ "$W_SVC" -lt 5 ]; do
        if is_core_running && pgrep AdGuardHome >/dev/null 2>&1; then
            break
        fi
        sleep 1
        W_SVC=$((W_SVC + 1))
    done
    echo ""
    ui_box_top "🎉 РЕЗУЛЬТАТ ПОЛНОГО ОБНОВЛЕНИЯ СЕРВЕРА"
    if is_core_running && pgrep AdGuardHome >/dev/null 2>&1; then
        if is_openwrt 2>/dev/null; then
            ui_box_row "${C_GRN}[✔] Все службы шлюза активны и работают стабильно!${C_RES}"
        else
            ui_box_row "${C_GRN}[✔] Все службы шлюза и модули Homelab активны и работают стабильно!${C_RES}"
        fi
    else
        ui_box_row "${C_YEL}[▲] Некоторые службы перезапускаются или требуют внимания (запустите: gw doctor)${C_RES}"
    fi
    if [ -d "${GATEWAY_DIR}/.git" ] && command -v git >/dev/null 2>&1; then
        CUR_REV=$(git -C "${GATEWAY_DIR}" -c safe.directory="${GATEWAY_DIR}" rev-parse --short HEAD 2>/dev/null || echo 'Standalone')
    else
        CUR_REV='Standalone'
    fi
    AGH_VER_STR=$(/usr/bin/AdGuardHome --version 2>&1 | sed -n 's/.*version \(v[0-9.a-zA-Z_.-]*\).*/\1/p' | head -n 1 || true)
    [ -z "$AGH_VER_STR" ] && AGH_VER_STR="OK"
    ui_box_row "• Версия скриптов: ${CUR_REV}"
    ui_box_row "• Ядро шлюза:     $(get_active_core_name) ($(get_active_core_version)) │ Панель: $(get_active_ui_name)"
    ui_box_row "• AdGuard Home:    ${AGH_VER_STR}"
    ui_box_bottom
    echo ""
    release_gateway_lock
    trap - EXIT INT TERM HUP
    return 0
}
