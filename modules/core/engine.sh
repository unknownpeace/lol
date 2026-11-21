#!/bin/sh
# ==============================================================================
# Единый диспетчер ядер (Sing-Box Extended <-> Mihomo) и веб-панелей (Zashboard <-> MetaCubeXD)
# ==============================================================================

get_active_core() {
    case "${CORE_ENGINE:-singbox}" in
        mihomo|clash|meta) printf "mihomo" ;;
        *) printf "singbox" ;;
    esac
}

get_active_core_name() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        printf "Mihomo (Clash Meta)"
    else
        printf "Sing-Box Extended"
    fi
}

get_active_core_service() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        printf "mihomo"
    else
        printf "sing-box"
    fi
}

get_active_core_bin() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        printf "/usr/bin/mihomo"
    else
        printf "/usr/bin/sing-box"
    fi
}

get_active_core_conf() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        printf "%s" "$MIHOMO_CONF"
    else
        printf "%s" "$SB_CONF"
    fi
}

get_active_core_log() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        printf "%s" "$MIHOMO_LOG_FILE"
    else
        printf "%s" "$SB_LOG_FILE"
    fi
}

get_active_core_version() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        if [ -x /usr/bin/mihomo ]; then
            _v=$(/usr/bin/mihomo -v 2>/dev/null | sed -n 's/.*\(v[0-9][0-9.a-zA-Z_-]*\).*/\1/p' | head -n 1 || true)
            printf "%s" "${_v:-установлен}"
        else
            printf "не установлен"
        fi
    else
        if [ -x /usr/bin/sing-box ]; then
            _v=$(/usr/bin/sing-box version 2>/dev/null | head -n 1 | awk '{print $3}' || true)
            [ -n "$_v" ] && printf "v%s" "${_v#v}" || printf "установлен"
        else
            printf "не установлен"
        fi
    fi
}

get_active_ui() {
    _u="${WEB_UI:-}"
    if [ -z "$_u" ] && [ -f "$UI_TYPE_FILE" ]; then
        _u=$(cat "$UI_TYPE_FILE" 2>/dev/null | tr -d ' \t\r\n' || true)
    fi
    case "${_u:-zashboard}" in
        metacubexd|metacube|xd) printf "metacubexd" ;;
        *) printf "zashboard" ;;
    esac
}

get_active_ui_name() {
    if [ "$(get_active_ui)" = "metacubexd" ]; then
        printf "MetaCubeXD"
    else
        printf "Zashboard"
    fi
}

is_core_running() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        pidof mihomo >/dev/null 2>&1 || pgrep mihomo >/dev/null 2>&1
    else
        pidof sing-box >/dev/null 2>&1 || pgrep sing-box >/dev/null 2>&1
    fi
}

get_core_pid() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        pidof mihomo 2>/dev/null | awk '{print $1}' | head -n 1 || pgrep mihomo 2>/dev/null | head -n 1 || true
    else
        pidof sing-box 2>/dev/null | awk '{print $1}' | head -n 1 || pgrep sing-box 2>/dev/null | head -n 1 || true
    fi
}

show_core_logs() {
    LINES_CNT="${1:-40}"
    CUR_LOG=$(get_active_core_log)
    CUR_CNAME=$(get_active_core_name)
    if [ -s "$CUR_LOG" ]; then
        tail -n "$LINES_CNT" "$CUR_LOG" 2>/dev/null || true
    elif [ -f /var/log/messages ]; then
        grep -iE "sing-box|mihomo" /var/log/messages 2>/dev/null | tail -n "$LINES_CNT" || true
    else
        echo "  ${C_DIM}(лог-файл ${CUR_CNAME} ${CUR_LOG} пока пуст)${C_RES}"
    fi
    return 0
}

core_generate_config() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        generate_mihomo_config
    else
        generate_singbox_config
    fi
}

core_check_config() {
    if [ "$(get_active_core)" = "mihomo" ]; then
        check_mihomo_config
    else
        check_singbox_config
    fi
}

core_restart_and_wait() {
    _SVC="${1:-$(get_active_core_service)}"
    [ -z "${ADMIN_PASS:-}" ] && load_gateway_env >/dev/null 2>&1 || true
    service_ctl "$_SVC" stop
    _STOP_W=0
    while [ "$_STOP_W" -lt 8 ]; do
        is_core_running || break
        sleep 1
        _STOP_W=$((_STOP_W + 1))
    done
    service_ctl "$_SVC" start
    _START_W=0
    while [ "$_START_W" -lt 15 ]; do
        if is_core_running && ip link show "$CORE_TUN_IF" >/dev/null 2>&1 && \
           curl -fsS --connect-timeout 1 -m 2 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/version" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        _START_W=$((_START_W + 1))
    done
    is_core_running && ip link show "$CORE_TUN_IF" >/dev/null 2>&1 && return 0
    return 1
}

_core_delay_group() {
    _grp_tag="$1"
    _tmo_ms="${2:-5000}"
    _curl_max="${3:-20}"
    _enc_g=$(jq -rn --arg s "$_grp_tag" '$s|@uri')
    curl -g -fsS --connect-timeout 2 -m "$_curl_max" -H "Authorization: Bearer ${ADMIN_PASS}" \
        "http://127.0.0.1:9090/group/${_enc_g}/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=${_tmo_ms}" >/dev/null 2>&1 || true
}

core_reload_api() {
    is_core_running || return 0
    load_gateway_env
    command -v jq >/dev/null 2>&1 || return 0

    _API_WAIT=0
    while [ "$_API_WAIT" -lt 12 ]; do
        if curl -fsS --connect-timeout 1 -m 2 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/version" >/dev/null 2>&1; then
            break
        fi
        sleep 1
        _API_WAIT=$((_API_WAIT + 1))
    done

    API_PROX_JSON=$(curl -fsS --connect-timeout 2 -m 5 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/providers/proxies" 2>/dev/null || true)
    HAS_REAL_PROV=0
    if [ -n "$API_PROX_JSON" ]; then
        PROV_TAGS=$(printf "%s" "$API_PROX_JSON" | jq -r '.providers | to_entries[]? | select(.value.vehicleType=="HTTP" or .value.vehicleType=="File" or .value.vehicleType=="Remote" or .value.vehicleType=="Local") | .key' 2>/dev/null || true)
        if [ -n "$PROV_TAGS" ]; then
            HAS_REAL_PROV=1
            printf "%s\n" "$PROV_TAGS" | while IFS= read -r P_TAG; do
                [ -z "$P_TAG" ] && continue
                ENC_P=$(jq -rn --arg s "$P_TAG" '$s|@uri')
                _PUT_CODE=$(curl -g -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 -m 15 -X PUT -H "Authorization: Bearer ${ADMIN_PASS}" \
                    "http://127.0.0.1:9090/providers/proxies/${ENC_P}" 2>/dev/null || echo "000")
                case "$_PUT_CODE" in
                    200|204|503) ;;
                    *)
                        sleep 2
                        curl -g -fsS --connect-timeout 2 -m 15 -X PUT -H "Authorization: Bearer ${ADMIN_PASS}" \
                            "http://127.0.0.1:9090/providers/proxies/${ENC_P}" >/dev/null 2>&1 || true
                        ;;
                esac
            done
        fi
    fi

    # Wait adaptively for async remote provider hydration (Sing-Box Extended 503 updating)
    PROX_JSON=""
    _WAIT_I=0
    _PREV_UNHYDRATED=-1
    _STABLE_CNT=0
    while [ "$_WAIT_I" -lt 25 ]; do
        PROX_JSON=$(curl -fsS --connect-timeout 2 -m 5 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null || true)
        [ "$HAS_REAL_PROV" -eq 0 ] && break
        [ -z "$PROX_JSON" ] && break
        _UNHYDRATED=$(printf "%s" "$PROX_JSON" | jq -r '[.proxies | to_entries[] | select(.value.type=="URLTest" and ((.value.all|length) <= 1))] | length' 2>/dev/null || echo "0")
        [ "$_UNHYDRATED" -eq 0 ] && break
        _AUTO_LEN=$(printf "%s" "$PROX_JSON" | jq -r '(.proxies["⚡ Авто (Самый быстрый)"].all | length) // 0' 2>/dev/null || echo "0")
        if [ "$_AUTO_LEN" -gt 3 ] && [ "$_UNHYDRATED" -eq "$_PREV_UNHYDRATED" ]; then
            _STABLE_CNT=$((_STABLE_CNT + 1))
            [ "$_STABLE_CNT" -ge 3 ] && break
        else
            _STABLE_CNT=0
        fi
        _PREV_UNHYDRATED="$_UNHYDRATED"
        sleep 1
        _WAIT_I=$((_WAIT_I + 1))
    done

    if [ -n "$PROX_JSON" ]; then
        printf "%s" "$PROX_JSON" | jq -r '.proxies | to_entries[] | select(.value.type=="URLTest" and .key!="⚡ Авто (Самый быстрый)") | .key' 2>/dev/null | {
            while IFS= read -r G_TAG; do
                [ -z "$G_TAG" ] && continue
                _core_delay_group "$G_TAG" 5000 20 &
            done
            wait
        }

        # Retry any populated URLTest group still stuck on dummy fallback after concurrent burst
        PROX_JSON=$(curl -fsS --connect-timeout 2 -m 5 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null || true)
        if [ -n "$PROX_JSON" ]; then
            printf "%s" "$PROX_JSON" | jq -r '.proxies | to_entries[] | select(.value.type=="URLTest" and .key!="⚡ Авто (Самый быстрый)" and ((.value.all|length) > 1) and .value.now=="⛔ Нет рабочих нод") | .key' 2>/dev/null | while IFS= read -r STUCK_G; do
                [ -z "$STUCK_G" ] && continue
                _core_delay_group "$STUCK_G" 5500 20
            done

            HAS_MAIN_AUTO=$(printf "%s" "$PROX_JSON" | jq -r 'if .proxies["⚡ Авто (Самый быстрый)"].type=="URLTest" then "1" else "0" end' 2>/dev/null || echo "0")
            if [ "$HAS_MAIN_AUTO" = "1" ]; then
                _core_delay_group "⚡ Авто (Самый быстрый)" 5000 20
                MAIN_NOW=$(curl -fsS --connect-timeout 2 -m 5 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/proxies" 2>/dev/null | \
                    jq -r 'if .proxies["⚡ Авто (Самый быстрый)"].now=="⛔ Нет рабочих нод" and ((.proxies["⚡ Авто (Самый быстрый)"].all|length) > 1) then "1" else "0" end' 2>/dev/null || echo "0")
                if [ "$MAIN_NOW" = "1" ]; then
                    sleep 1
                    _core_delay_group "⚡ Авто (Самый быстрый)" 5500 20
                fi
            fi
        fi
        sleep 1
    fi
    return 0
}

# Загрузка и установка веб-панели (Zashboard или MetaCubeXD) в общий каталог ${UI_DIR}
install_web_ui() {
    case "${1:-$WEB_UI}" in
        metacubexd|metacube|xd) TARGET_UI="metacubexd" ;;
        *) TARGET_UI="zashboard" ;;
    esac
    TARGET_UI_VER="${2:-}"
    check_github_mirror

    if [ "$TARGET_UI" = "metacubexd" ]; then
        UI_REPO_T="$METACUBEXD_REPO"
        UI_NAME_T="MetaCubeXD"
        DEF_VER_T="v1.275.2"
        URL_1="$METACUBEXD_TAR_URL"
        URL_2="$METACUBEXD_FALLBACK_TAR_URL"
    else
        UI_REPO_T="$ZASHBOARD_REPO"
        UI_NAME_T="Zashboard"
        DEF_VER_T="v3.30.0"
        URL_1="$ZASHBOARD_TAR_URL"
        URL_2=""
    fi

    [ -z "$TARGET_UI_VER" ] && TARGET_UI_VER=$(fetch_latest_github_tag "$UI_REPO_T") || true
    case "$TARGET_UI_VER" in v*) ;; *) TARGET_UI_VER="$DEF_VER_T" ;; esac

    echo "Загрузка и установка веб-панели ${UI_NAME_T} ${TARGET_UI_VER}..."
    rm -rf /tmp/gw_ui.tgz /tmp/gw_ui_extract
    mkdir -p /tmp/gw_ui_extract

    DL_OK="no"
    if download_file "$URL_1" "/tmp/gw_ui.tgz" && tar -xzf /tmp/gw_ui.tgz -C /tmp/gw_ui_extract 2>/dev/null; then
        DL_OK="yes"
    elif [ -n "$URL_2" ] && download_file "$URL_2" "/tmp/gw_ui.tgz" && tar -xzf /tmp/gw_ui.tgz -C /tmp/gw_ui_extract 2>/dev/null; then
        DL_OK="yes"
    fi

    if [ "$DL_OK" = "yes" ]; then
        INDEX_PATH=$(find /tmp/gw_ui_extract -type f -name "index.html" 2>/dev/null | head -n 1 || true)
        if [ -n "$INDEX_PATH" ] && [ -s "$INDEX_PATH" ]; then
            SRC_UI_DIR=$(dirname "$INDEX_PATH")
            mkdir -p "${UI_DIR}.new.$$"
            cp -rf "${SRC_UI_DIR}/." "${UI_DIR}.new.$$/"
            rm -rf "${UI_DIR}"
            mv -f "${UI_DIR}.new.$$" "${UI_DIR}"
            chmod -R a+rX "${UI_DIR}" 2>/dev/null || true
            echo "$TARGET_UI_VER" > "$UI_VER_FILE"
            echo "$TARGET_UI" > "$UI_TYPE_FILE"
            LATEST_UI_TAG="$TARGET_UI_VER"
            rm -rf /tmp/gw_ui.tgz /tmp/gw_ui_extract
            echo "${C_GRN}[✓] Веб-панель ${UI_NAME_T} ${TARGET_UI_VER} успешно установлена в ${UI_DIR}.${C_RES}"
            return 0
        fi
    fi

    rm -rf /tmp/gw_ui.tgz /tmp/gw_ui_extract "${UI_DIR}.new.$$"
    echo "${C_RED}[X] Ошибка загрузки или распаковки веб-панели ${UI_NAME_T}!${C_RES}"
    return 1
}

switch_web_ui() {
    case "${1:-}" in
        zashboard|zash|zb)      REQ_UI="zashboard" ;;
        metacubexd|metacube|xd) REQ_UI="metacubexd" ;;
        *)
            echo "${C_RED}[X] Неизвестная веб-панель: ${1:-}. Доступно: zashboard | metacubexd${C_RES}"
            return 1
            ;;
    esac
    load_gateway_env
    if install_web_ui "$REQ_UI"; then
        WEB_UI="$REQ_UI"
        save_gateway_env
        rm -f "$VER_CACHE_FILE"
        echo "${C_GRN}[✓] Активная веб-панель переключена на $(get_active_ui_name). Откройте http://$(get_current_lan_ip):9090/ui/${C_RES}"
        return 0
    fi
    return 1
}

apply_and_verify_core() {
    ACTION_TITLE="${1:-Обновление конфигурации}"
    ensure_alpine_modules
    load_gateway_env
    ACT_CORE=$(get_active_core)
    ACT_NAME=$(get_active_core_name)
    ACT_SVC=$(get_active_core_service)
    ACT_CONF=$(get_active_core_conf)

    core_generate_config

    if ! core_check_config; then
        echo "${C_RED}[X] Ошибка синтаксиса ${ACT_NAME} при действии: ${ACTION_TITLE}!${C_RES}"
        if [ "$ACT_CORE" = "mihomo" ]; then
            SAFE_PATHS="${SB_DIR}:${MIHOMO_DIR}" /usr/bin/mihomo -t -d "$MIHOMO_DIR" -f "$MIHOMO_CONF" || true
        else
            /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" || true
        fi
        echo "${C_YEL}[!] Выполняется авто-откат к предыдущей рабочей конфигурации...${C_RES}"
        restore_gateway_state
        return 1
    fi

    if core_restart_and_wait "$ACT_SVC"; then
        WAIT_OK="yes"
    else
        WAIT_OK="no"
    fi

    if [ "$WAIT_OK" = "yes" ]; then
        sync_dns_firewall "yes" "keep" >/dev/null 2>&1 || true
        core_reload_api
        ui_box_top "✔ ${ACTION_TITLE}: УСПЕШНО (${ACT_NAME} & ${CORE_TUN_IF} АКТИВНЫ)"
        print_proxy_slots_report
        ui_box_bottom
        return 0
    else
        ui_box_sep
        echo "${C_RED}[X] Служба ${ACT_NAME} (${ACT_SVC}) не смогла запуститься (${ACTION_TITLE})!${C_RES}"
        echo "--- Причина из системного журнала ---"
        show_core_logs 12
        ui_box_sep
        echo "${C_YEL}[!] Выполняется авто-откат к предыдущей рабочей конфигурации...${C_RES}"
        restore_gateway_state
        return 1
    fi
}

switch_core_engine() {
    case "${1:-}" in
        singbox|sing-box|sb) TARGET_CORE="singbox" ;;
        mihomo|clash|meta)   TARGET_CORE="mihomo" ;;
        *)
            echo "${C_RED}[X] Неизвестное ядро: ${1:-}. Доступно: singbox | mihomo${C_RES}"
            return 1
            ;;
    esac

    load_gateway_env
    PREV_CORE=$(get_active_core)
    if [ "$TARGET_CORE" = "mihomo" ]; then
        TARGET_NAME="Mihomo (Clash Meta)"
        TARGET_SVC="mihomo"
        OTHER_SVC="sing-box"
    else
        TARGET_NAME="Sing-Box Extended"
        TARGET_SVC="sing-box"
        OTHER_SVC="mihomo"
    fi

    echo "${C_CYN}[*] Переключение активного ядра шлюза на ${TARGET_NAME}...${C_RES}"
    backup_gateway_state
    ensure_alpine_modules

    # 1. Гарантируем наличие бинарника целевого ядра перед остановкой текущего
    if [ "$TARGET_CORE" = "mihomo" ] && [ ! -x /usr/bin/mihomo ]; then
        install_mihomo_binary || return 1
    elif [ "$TARGET_CORE" = "singbox" ] && [ ! -x /usr/bin/sing-box ]; then
        install_singbox_binary || return 1
    fi

    # 2. Генерируем и проверяем новый конфиг ДО остановки старого ядра
    CORE_ENGINE="$TARGET_CORE"
    if [ "$TARGET_CORE" = "mihomo" ]; then
        generate_mihomo_config
    else
        generate_singbox_config
    fi
    CORE_ENGINE="$TARGET_CORE"
    if ! core_check_config; then
        echo "${C_RED}[X] Конфигурация ${TARGET_NAME} не прошла проверку! Оставлено ядро ${PREV_CORE}.${C_RES}"
        if [ "$TARGET_CORE" = "mihomo" ]; then
            SAFE_PATHS="${SB_DIR}:${MIHOMO_DIR}" /usr/bin/mihomo -t -d "$MIHOMO_DIR" -f "$MIHOMO_CONF" || true
        else
            /usr/bin/sing-box check -c "$SB_CONF" -D "$SB_DIR" || true
        fi
        CORE_ENGINE="$PREV_CORE"
        save_gateway_env
        return 1
    fi

    # 3. Сохраняем выбор ядра и выполняем безопасное переключение демонов
    CORE_ENGINE="$TARGET_CORE"
    save_gateway_env
    service_ctl "$OTHER_SVC" stop
    service_ctl "$OTHER_SVC" disable
    nft delete table inet sing-box >/dev/null 2>&1 || true
    nft delete table inet mihomo >/dev/null 2>&1 || true
    conntrack -F >/dev/null 2>&1 || true

    setup_init_scripts

    WAIT_OK="no"
    W_IDX=0
    while [ "$W_IDX" -lt 15 ]; do
        if (pgrep -x "$TARGET_SVC" >/dev/null 2>&1 || is_core_running) && ip link show "$CORE_TUN_IF" >/dev/null 2>&1 && \
           curl -fsS -m 1 -H "Authorization: Bearer ${ADMIN_PASS}" "http://127.0.0.1:9090/configs" >/dev/null 2>&1; then
            WAIT_OK="yes"
            break
        fi
        sleep 1
        W_IDX=$((W_IDX + 1))
    done

    if [ "$WAIT_OK" = "yes" ]; then
        sync_dns_firewall "yes" "keep" >/dev/null 2>&1 || true
        sync_agh_homelab_rewrites "$(get_current_lan_ip)" >/dev/null 2>&1 || true
        if is_module_enabled "caddy"; then
            reload_caddy_safe >/dev/null 2>&1 || true
        fi
        core_reload_api
        rm -f "$VER_CACHE_FILE"
        echo "${C_GRN}[✓] Ядро успешно переключено на ${TARGET_NAME} ($(get_active_core_version))! TUN: ${CORE_TUN_IF}${C_RES}"
        if [ "$TARGET_CORE" = "mihomo" ] && is_warp_enabled; then
            echo "${C_DIM}[i] Примечание: в Mihomo слот WARP работает через 4 узла AmneziaWG UDP; MASQUE H2 доступен в Sing-Box Extended.${C_RES}"
        fi
        return 0
    else
        echo "${C_RED}[X] Не удалось запустить ${TARGET_NAME} или поднять ${CORE_TUN_IF}! Журнал:${C_RES}"
        show_core_logs 15
        echo "${C_YEL}[!] Выполняется авто-откат на предыдущее ядро (${PREV_CORE})...${C_RES}"
        restore_gateway_state
        setup_init_scripts >/dev/null 2>&1 || true
        return 1
    fi
}

prompt_core_and_ui_menu() {
    while true; do
        load_gateway_env
        clear
        ui_banner "CORE & WEB-UI MANAGER // ПЕРЕКЛЮЧЕНИЕ ЯДРА И ВЕБ-ПАНЕЛИ"
        ui_box_top "⚙️ ТЕКУЩАЯ КОНФИГУРАЦИЯ ШЛЮЗА"
        ui_box_row "• Активное ядро:    ${C_GRN}$(get_active_core_name)${C_RES} ($(get_active_core_version))"
        ui_box_row "• TUN-интерфейс:    ${C_CYN}${CORE_TUN_IF}${C_RES} (MTU 1400, system stack)"
        ui_box_row "• Активная панель:  ${C_GRN}$(get_active_ui_name)${C_RES} (https://${DOM_ZASHBOARD} / https://${DOM_PANEL})"
        ui_box_sep "ДЕЙСТВИЯ [0-4]"
        ui_box_row "1) Переключить ядро на ${C_CYN}Sing-Box Extended${C_RES} (вкл. WARP MASQUE H2 + JSON)"
        ui_box_row "2) Переключить ядро на ${C_CYN}Mihomo (Clash Meta)${C_RES} (нативный Clash YAML + .mrs)"
        ui_box_row "3) Переключить веб-панель на ${C_GRN}Zashboard${C_RES}"
        ui_box_row "4) Переключить веб-панель на ${C_GRN}MetaCubeXD${C_RES}"
        ui_box_row "0) Назад"
        ui_box_bottom
        printf "Выбор [0-4]: "
        read -r CE_ACT < /dev/tty || break
        CE_ACT=$(printf "%s" "$CE_ACT" | tr -d ' \t\r\n')
        case "$CE_ACT" in
            ""|0) break ;;
            1) switch_core_engine "singbox" || true; printf "\nНажмите Enter..."; read -r _ < /dev/tty || break ;;
            2) switch_core_engine "mihomo" || true; printf "\nНажмите Enter..."; read -r _ < /dev/tty || break ;;
            3) switch_web_ui "zashboard" || true; printf "\nНажмите Enter..."; read -r _ < /dev/tty || break ;;
            4) switch_web_ui "metacubexd" || true; printf "\nНажмите Enter..."; read -r _ < /dev/tty || break ;;
        esac
    done
    return 0
}
