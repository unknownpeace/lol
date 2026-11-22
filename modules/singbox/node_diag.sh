#!/bin/sh
diagnose_failed_nodes() {
    if ! is_core_running || ! command -v jq >/dev/null 2>&1; then
        echo "${C_RED}[X] Служба $(get_active_core_name) не запущена или не найден jq.${C_RES}"
        return 1
    fi
    load_gateway_env
    API_JSON=$(clash_api_curl -fsS --connect-timeout 2 "http://127.0.0.1:9090/proxies" 2>/dev/null || true)
    if [ -z "$API_JSON" ]; then
        echo "${C_RED}[X] Не удалось подключиться к Clash API (127.0.0.1:9090).${C_RES}"
        return 1
    fi

    echo ""
    ui_box_top "🩺 Поштучная диагностика и оживление нод без пинга (⚡)"
    FAILED_LIST=$(printf "%s" "$API_JSON" | jq -r '
        .proxies | to_entries[]
        | select(.value.type != "Selector" and .value.type != "URLTest" and .value.type != "Direct" and .value.type != "Reject" and .value.type != "Pass" and .key != "⛔ Нет рабочих нод")
        | select(((.value.history // []) | if length > 0 then .[-1].delay else 0 end) == 0)
        | .key
    ' 2>/dev/null || true)

    if [ -z "$FAILED_LIST" ]; then
        echo "${C_GRN}[✓] Идеально! У всех 100% активных нод уже есть результат пинга!${C_RES}"
        ui_box_bottom
        return 0
    fi

    printf "%s\n" "$FAILED_LIST" | while IFS= read -r NODE_KEY; do
        [ -z "$NODE_KEY" ] && continue
        ENC_N=$(jq -rn --arg s "$NODE_KEY" '$s|@uri')
        RES1=$(clash_api_curl -fsS --connect-timeout 6 -m 7 \
            "http://127.0.0.1:9090/proxies/${ENC_N}/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000" 2>/dev/null || true)
        D1=$(printf "%s" "$RES1" | jq -r '.delay // 0' 2>/dev/null || echo "0")

        if [ "${D1:-0}" -gt 0 ]; then
            printf "  %s[✓ ОЖИВЛЕНА: %4s ms]%s %s\n" "$C_GRN" "$D1" "$C_RES" "$NODE_KEY"
        else
            RES2=$(clash_api_curl -fsS --connect-timeout 6 -m 7 \
                "http://127.0.0.1:9090/proxies/${ENC_N}/delay?url=http%3A%2F%2Fcp.cloudflare.com%2Fgenerate_204&timeout=5000" 2>/dev/null || true)
            D2=$(printf "%s" "$RES2" | jq -r '.delay // 0' 2>/dev/null || echo "0")
            if [ "${D2:-0}" -gt 0 ]; then
                printf "  %s[✓ ОЖИВЛЕНА: %4s ms]%s %s (через CF)\n" "$C_GRN" "$D2" "$C_RES" "$NODE_KEY"
            else
                printf "  %s[X МЕРТВА У ПРОВАЙДЕРА]%s %s\n" "$C_RED" "$C_RES" "$NODE_KEY"
            fi
        fi
    done
    ui_box_sep
    echo "${C_DIM}[i] Все оживленные ноды уже обновили свой пинг в панели $(get_active_ui_name)!${C_RES}"
    ui_box_bottom
    return 0
}

# Мини-пульт управления группами и нодами прямо из SSH-терминала (через Clash API)
manage_nodes_cli_menu() {
    if ! is_core_running || ! command -v jq >/dev/null 2>&1; then
        echo "${C_RED}[X] Служба $(get_active_core_name) не запущена или не найден jq.${C_RES}"
        return 1
    fi
    load_gateway_env

    while true; do
        API_JSON=$(clash_api_curl -fsS --connect-timeout 2 "http://127.0.0.1:9090/proxies" 2>/dev/null || true)
        if [ -z "$API_JSON" ]; then
            echo "${C_RED}[X] Не удалось получить список нод от Clash API (127.0.0.1:9090).${C_RES}"
            return 1
        fi

        clear
        ui_box_top "⚡ Мини-пульт управления группами и нодами (SSH)"
        for GRP_M in "⚡ Авто (Самый быстрый)" "🤖 Авто-ИИ" "🇩🇪 Авто-DE" "🇺🇸 Авто-US" "🎮 Авто-Гейминг"; do
            M_NOW=$(printf "%s" "$API_JSON" | jq -r --arg g "$GRP_M" '.proxies[$g].now // empty' 2>/dev/null)
            [ -n "$M_NOW" ] && printf " • %-24s -> %s%s%s\n" "$GRP_M" "$C_GRN" "$M_NOW" "$C_RES"
        done
        ui_box_sep
        echo "${C_BLD}Топ-8 самых быстрых нод по замеру пинга:${C_RES}"
        printf "%s" "$API_JSON" | jq -r '
            [.proxies | to_entries[]
             | select(.value.type != "Selector" and .value.type != "URLTest" and .value.type != "Direct" and .value.type != "Reject" and .value.type != "Pass" and .key != "⛔ Нет рабочих нод")
             | {name: .key, type: .value.type, delay: ((.value.history // []) | if length > 0 then .[-1].delay else 0 end)}
             | select(.delay > 0)]
            | sort_by(.delay) | .[:8] | to_entries[]
            | "  • [\(.value.delay) ms] \(.value.name) (\(.value.type))"
        ' 2>/dev/null || true
        ui_box_sep
        echo "${C_BLD}Активные селекторы маршрутизации (выберите для смены ноды):${C_RES}"

        ensure_gateway_runtime_dir >/dev/null 2>&1 || true
        GRP_LIST_FILE=$(mktemp "${GATEWAY_RUNTIME_DIR:-/run/gateway}/selectors.XXXXXX" 2>/dev/null || printf "%s" "${GATEWAY_RUNTIME_DIR:-/run/gateway}/selectors.$$")
        printf "%s" "$API_JSON" | jq -r '
            [.proxies | to_entries[] | select(.value.type == "Selector" and .key != "GLOBAL")]
            | map(.key) | .[]
        ' > "$GRP_LIST_FILE" 2>/dev/null || true

        G_IDX=0
        while IFS= read -r G_NAME; do
            [ -z "$G_NAME" ] && continue
            G_IDX=$((G_IDX + 1))
            G_CUR=$(printf "%s" "$API_JSON" | jq -r --arg g "$G_NAME" '.proxies[$g].now // "Авто"')
            printf "  %s[%d]%s %-28s -> Сейчас: %s%s%s\n" "$C_CYN" "$G_IDX" "$C_RES" "$G_NAME" "$C_GRN" "$G_CUR" "$C_RES"
        done < "$GRP_LIST_FILE"

        ui_box_sep
        echo "  ${C_CYN}[d]${C_RES} ${C_GRN}🩺 Поштучно проверить и оживить ноды с молнией (⚡)${C_RES}"
        echo "  ${C_CYN}[r]${C_RES} Запустить общий замер пинга всех нод"
        echo "  ${C_CYN}[0]${C_RES} Назад"
        printf "Выберите номер группы [1-%d / d / r / 0]: " "$G_IDX"
        read -r G_SEL < /dev/tty || break
        G_SEL=$(printf "%s" "$G_SEL" | tr -d ' \t\r\n')

        case "$G_SEL" in
            ""|0)
                rm -f "$GRP_LIST_FILE"
                break
                ;;
            d|D)
                diagnose_failed_nodes || true
                printf "\nНажмите Enter для продолжения..."
                read -r _ < /dev/tty || true
                ;;
            r|R)
                echo "Запуск тестирования задержки всех нод..."
                core_reload_api
                sleep 1
                ;;
            *[!0-9]*)
                ;;
            *)
                TARGET_GRP=$(awk -v t="$G_SEL" 'NR == t {print $0; exit}' "$GRP_LIST_FILE" 2>/dev/null)
                if [ -n "$TARGET_GRP" ]; then
                    NODES_LIST_FILE=$(mktemp "${GATEWAY_RUNTIME_DIR:-/run/gateway}/group_nodes.XXXXXX" 2>/dev/null || printf "%s" "${GATEWAY_RUNTIME_DIR:-/run/gateway}/group_nodes.$$")
                    printf "%s" "$API_JSON" | jq -r --arg g "$TARGET_GRP" '.proxies[$g].all[]?' > "$NODES_LIST_FILE" 2>/dev/null || true
                    echo ""
                    echo "${C_CYN}--- Доступные ноды для группы «${TARGET_GRP}» ---${C_RES}"
                    N_IDX=0
                    while IFS= read -r N_NAME; do
                        [ -z "$N_NAME" ] && continue
                        N_IDX=$((N_IDX + 1))
                        N_DELAY=$(printf "%s" "$API_JSON" | jq -r --arg n "$N_NAME" '(.proxies[$n].history // []) | if length > 0 then .[-1].delay else 0 end' 2>/dev/null || echo "0")
                        if [ "${N_DELAY:-0}" -gt 0 ]; then
                            printf "  %s[%d]%s %s %s(%s ms)%s\n" "$C_CYN" "$N_IDX" "$C_RES" "$N_NAME" "$C_GRN" "$N_DELAY" "$C_RES"
                        else
                            printf "  %s[%d]%s %s %s(⚡)%s\n" "$C_CYN" "$N_IDX" "$C_RES" "$N_NAME" "$C_DIM" "$C_RES"
                        fi
                    done < "$NODES_LIST_FILE"
                    printf "\nВыберите номер ноды для «%s» [Enter = отмена]: " "$TARGET_GRP"
                    read -r N_SEL < /dev/tty || true
                    N_SEL=$(printf "%s" "$N_SEL" | tr -d ' \t\r\n')
                    case "$N_SEL" in
                        ''|*[!0-9]*) ;;
                        *)
                            PICKED_NODE=$(awk -v t="$N_SEL" 'NR == t {print $0; exit}' "$NODES_LIST_FILE" 2>/dev/null)
                            if [ -n "$PICKED_NODE" ]; then
                                ENC_GRP=$(jq -rn --arg s "$TARGET_GRP" '$s|@uri')
                                PAYLOAD_JSON=$(jq -n --arg name "$PICKED_NODE" '{"name": $name}')
                                if clash_api_curl -fsS -X PUT -H "Content-Type: application/json" \
                                    -d "$PAYLOAD_JSON" "http://127.0.0.1:9090/proxies/${ENC_GRP}" >/dev/null 2>&1; then
                                    echo "${C_GRN}[✓] Группа «${TARGET_GRP}» переключена на: ${PICKED_NODE}${C_RES}"
                                    sleep 1
                                fi
                            fi
                            ;;
                    esac
                    rm -f "$NODES_LIST_FILE"
                fi
                ;;
        esac
        rm -f "$GRP_LIST_FILE"
    done
    rm -f "${GRP_LIST_FILE:-}" 2>/dev/null || true
    return 0
}
