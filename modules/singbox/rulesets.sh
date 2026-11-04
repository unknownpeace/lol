sanitize_domain_entry() {
    RAW_IN_DOM=$(clean_clipboard_line "$1")
    [ -z "$RAW_IN_DOM" ] && return 1
    case "$RAW_IN_DOM" in
        @*)
            TG_HANDLE=$(printf "%s" "${RAW_IN_DOM#@}" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9_].*//')
            [ -n "$TG_HANDLE" ] && { printf "+.t.me"; return 0; }
            return 1
            ;;
    esac
    RAW_DOM=$(printf "%s" "$RAW_IN_DOM" | tr 'A-Z' 'a-z' | sed -E 's|^["'\''`]+||; s|["'\''`]+$||; s|^[a-z0-9+.-]+://||; s|^//||; s|[/?#].*$||; s|^[^@]*@||; s|:.*$||; s|^\*\.\.?||; s|^\+\.||; s|^\.||; s|^www\.||; s|\.$||')
    [ -z "$RAW_DOM" ] && return 1

    # Защита: если пользователь ввел IPv4 вместо домена, отклоняем с подсказкой
    if is_valid_ipv4 "$RAW_DOM"; then
        return 1
    fi

    # Авто-конвертация кириллических IDN-доменов (например, кинопоиск.рф -> xn--...p1ai) через python3
    if printf "%s" "$RAW_DOM" | grep -q '[^[:ascii:]]' 2>/dev/null; then
        if command -v python3 >/dev/null 2>&1; then
            IDN_DOM=$(python3 -c 'import sys; print(sys.argv[1].strip().encode("idna").decode("ascii").lower())' "$RAW_DOM" 2>/dev/null || true)
            [ -n "$IDN_DOM" ] && RAW_DOM="$IDN_DOM"
        fi
    fi

    case "$RAW_DOM" in
        ""|*[![:alnum:]._-]*|*..*|.*|*.)
            return 1
            ;;
        *.*)
            printf "+.%s" "$RAW_DOM"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Вывод пронумерованного списка строк из файла (для доменов и IP устройств)
list_entries_numbered() {
    TARGET_FILE="$1"
    if [ ! -s "$TARGET_FILE" ] || ! awk 'NF {found=1} END {exit !found}' "$TARGET_FILE" 2>/dev/null; then
        echo "  ${C_DIM}(список пуст)${C_RES}"
        return 0
    fi
    awk -v c="${C_CYN}" -v r="${C_RES}" 'NF {idx++; printf "  %s[%d]%s %s\n", c, idx, r, $0}' "$TARGET_FILE" 2>/dev/null || true
    return 0
}

count_file_entries() {
    TARGET_FILE="$1"
    if [ -s "$TARGET_FILE" ]; then
        awk 'NF {c++} END {print c+0}' "$TARGET_FILE" 2>/dev/null
    else
        echo "0"
    fi
    return 0
}

get_entry_by_index() {
    TARGET_FILE="$1"
    TARGET_IDX="$2"
    awk -v target="$TARGET_IDX" 'NF {idx++; if (idx == target) {print $0; exit}}' "$TARGET_FILE" 2>/dev/null
    return 0
}

# Точечное удаление строки (домена или IP) по порядковому номеру
delete_entry_by_index() {
    TARGET_FILE="$1"
    DEL_IDX="$2"
    FALLBACK_VAL="${3:-}"
    case "$DEL_IDX" in
        ''|*[!0-9]*)
            echo "${C_RED}[X] Некорректный номер.${C_RES}"
            return 1
            ;;
    esac
    TOTAL_E=$(count_file_entries "$TARGET_FILE")
    if [ "$DEL_IDX" -lt 1 ] || [ "$DEL_IDX" -gt "$TOTAL_E" ]; then
        echo "${C_RED}[X] Запись с номером ${DEL_IDX} не существует (доступно: 1..${TOTAL_E}).${C_RES}"
        return 1
    fi
    awk -v target="$DEL_IDX" -v fb="$FALLBACK_VAL" '
        NF {
            idx++
            if (idx == target) next
            print $0
            kept++
        }
        END {
            if (kept == 0 && fb != "") print fb
        }
    ' "$TARGET_FILE" > "${TARGET_FILE}.tmp" && mv -f "${TARGET_FILE}.tmp" "$TARGET_FILE"
    return 0
}

# Компиляция текстовых пользовательских списков доменов (.list) в JSON rule-set (version 3)
# Включает автоматическую защиту локальной зоны +.lan от попадания в FakeIP
sync_user_domain_rulesets() {
    mkdir -p "$SB_RULES_DIR"
    [ -f "$USER_DIRECT_FILE" ] || printf "+.localdomain\n+.lan\n" > "$USER_DIRECT_FILE"
    grep -qxF "+.lan" "$USER_DIRECT_FILE" 2>/dev/null || echo "+.lan" >> "$USER_DIRECT_FILE"
    [ -f "$USER_PROXY_FILE" ] || echo "+.chatgpt.com" > "$USER_PROXY_FILE"
    sed -i 's/\r$//' "$USER_DIRECT_FILE" "$USER_PROXY_FILE" "$CUSTOM_NODES_FILE" 2>/dev/null || true

    if command -v jq >/dev/null 2>&1; then
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^+\.//;s/^\.//' "$USER_DIRECT_FILE" 2>/dev/null | grep -v '^$' | \
            jq -R . | jq -s '{version: 3, rules: [{domain_suffix: (if length > 0 then . else ["localdomain", "lan"] end)}]}' > "${USER_DIRECT_JSON}.tmp" && \
            mv "${USER_DIRECT_JSON}.tmp" "$USER_DIRECT_JSON"

        sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^+\.//;s/^\.//' "$USER_PROXY_FILE" 2>/dev/null | grep -v '^$' | \
            jq -R . | jq -s '{version: 3, rules: [{domain_suffix: (if length > 0 then . else ["chatgpt.com"] end)}]}' > "${USER_PROXY_JSON}.tmp" && \
            mv "${USER_PROXY_JSON}.tmp" "$USER_PROXY_JSON"
    else
        cat << 'J_DIR' > "$USER_DIRECT_JSON"
{"version":3,"rules":[{"domain_suffix":["localdomain","lan"]}]}
J_DIR
        cat << 'J_PRX' > "$USER_PROXY_JSON"
{"version":3,"rules":[{"domain_suffix":["chatgpt.com"]}]}
J_PRX
    fi
    return 0
}

# Сборка JSON-массивов IP-адресов устройств (DIRECT и Full-VPN)
get_ip_cidr_json_array() {
    SRC_FILE="$1"
    if [ ! -s "$SRC_FILE" ] || ! command -v jq >/dev/null 2>&1; then
        printf "[]"
        return 0
    fi
    sed -i 's/\r$//' "$SRC_FILE" 2>/dev/null || true
    awk '{
        gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", $0);
        if ($0 != "") {
            if (index($0, "/") == 0) print $0 "/32";
            else print $0;
        }
    }' "$SRC_FILE" | jq -R . | jq -s .
    return 0
}

# Генерация эталонного /etc/sing-box/config.json (оптимизировано под 200+ нод, AI-сервера и зону .lan)
