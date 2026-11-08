print_proxy_slots_report() {
    load_gateway_env
    if [ "${ALLOW_RU_NODES:-no}" = "yes" ]; then
        RU_FLT_TAG="${C_YEL}Каскады РФ/БС: ПОКАЗАНЫ${C_RES}"
    else
        RU_FLT_TAG="Каскады РФ/БС: СКРЫТЫ"
    fi

    SUB_CNT=$(count_sub_urls)
    if [ "$SUB_CNT" -gt 1 ]; then
        SLOT1_INFO="${C_GRN}АКТИВНЫ${C_RES} (${SUB_CNT} подписки | ${RU_FLT_TAG})"
    elif [ "$SUB_CNT" -eq 1 ]; then
        SLOT1_INFO="${C_GRN}АКТИВНА${C_RES} (${SUB_URL} | ${RU_FLT_TAG})"
    else
        SLOT1_INFO="${C_DIM}ОТКЛЮЧЕНА${C_RES} (${RU_FLT_TAG})"
    fi

    MY_CNT=$(count_my_nodes)
    if [ "$MY_CNT" -gt 0 ]; then
        SLOT2_INFO="${C_GRN}АКТИВЕН${C_RES} (${MY_CNT} шт. в my_nodes.yaml)"
    else
        SLOT2_INFO="${C_DIM}ПУСТО (0 ключей)${C_RES}"
    fi

    if is_warp_enabled; then
        if [ -n "${WARP_LICENSE:-}" ]; then
            SLOT3_INFO="${C_GRN}АКТИВЕН${C_RES} (4 ноды UDP AWG WARP+ + 1 нода TCP MASQUE H2 -> '☁️ Amnezia WARP')"
        else
            SLOT3_INFO="${C_GRN}АКТИВЕН${C_RES} (4 ноды UDP AWG 2.0 + 1 нода TCP MASQUE H2 -> '☁️ Amnezia WARP')"
        fi
    else
        SLOT3_INFO="${C_DIM}ОТКЛЮЧЕН${C_RES}"
    fi

    ui_box_row "▸ Слот 1 [Подписки HTTP]:    ${SLOT1_INFO}"
    ui_box_row "▸ Слот 2 [Личные ключи URI]: ${SLOT2_INFO}"
    ui_box_row "▸ Слот 3 [Amnezia WARP+H2]:  ${SLOT3_INFO}"
    return 0
}

# Вывод пронумерованного списка личных ключей в my_nodes.yaml
list_my_nodes() {
    if ! has_my_nodes; then
        echo " ${C_DIM}[i] Список личных ключей (my_nodes.yaml) пуст.${C_RES}"
        return 0
    fi
    echo " ${C_CYN}--- Список ваших ключей в ${CUSTOM_NODES_FILE} ---${C_RES}"
    awk -v c="${C_CYN}" -v r="${C_RES}" '
        NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {
            idx++
            line = $0
            proto = line
            sub(/:\/\/.*/, "", proto)
            tag = "(без названия)"
            if (index(line, "#") > 0) {
                tag = substr(line, index(line, "#") + 1)
                gsub(/%20/, " ", tag)
            }
            host = line
            sub(/^[a-zA-Z0-9+-]+:\/\/([^@]*@)?/, "", host)
            sub(/[\/?#].*/, "", host)
            if (length(host) > 34) host = substr(host, 1, 31) "..."
            printf "  %s[%d]%s %-10s | %-34s | #%s\n", c, idx, r, proto "://", host, tag
        }
    ' "$CUSTOM_NODES_FILE" 2>/dev/null || true
    return 0
}

# Точечное удаление личного ключа по его порядковому номеру
delete_my_node_by_index() {
    DEL_IDX="$1"
    case "$DEL_IDX" in
        ''|*[!0-9]*)
            echo "${C_RED}[X] Некорректный номер ключа.${C_RES}"
            return 1
            ;;
    esac
    TOTAL_K=$(count_my_nodes)
    if [ "$DEL_IDX" -lt 1 ] || [ "$DEL_IDX" -gt "$TOTAL_K" ]; then
        echo "${C_RED}[X] Ключ с номером ${DEL_IDX} не существует (доступно: 1..${TOTAL_K}).${C_RES}"
        return 1
    fi
    awk -v target="$DEL_IDX" '
        NF && $0 !~ /^[[:space:]]*#/ && $0 !~ /^proxies:/ {
            idx++
            if (idx == target) next
            print $0
            kept++
        }
        END {
            if (kept == 0) print "proxies: []"
        }
    ' "$CUSTOM_NODES_FILE" > "${CUSTOM_NODES_FILE}.tmp" && mv "${CUSTOM_NODES_FILE}.tmp" "$CUSTOM_NODES_FILE"
    return 0
}

# Безопасное применение изменений с проверкой старта процесса и интерфейса singbox-tun
