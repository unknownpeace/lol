init_colors() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        C_RES=$(printf '\033[0m')
        C_BLD=$(printf '\033[1m')
        C_DIM=$(printf '\033[2m')
        TERM_VAL="${TERM:-}"
        case "$TERM_VAL" in
            *256color*|*truecolor*|*xterm*|*kitty*|*alacritty*|*tmux*|*screen*)
                C_GRN=$(printf '\033[1;38;5;48m')
                C_RED=$(printf '\033[1;38;5;197m')
                C_YEL=$(printf '\033[1;38;5;220m')
                C_CYN=$(printf '\033[1;38;5;51m')
                C_BLU=$(printf '\033[1;38;5;39m')
                C_MAG=$(printf '\033[1;38;5;135m')
                C_WHT=$(printf '\033[1;38;5;255m')
                C_G1=$(printf '\033[1;38;5;51m')
                C_G2=$(printf '\033[1;38;5;45m')
                C_G3=$(printf '\033[1;38;5;39m')
                C_G4=$(printf '\033[1;38;5;99m')
                C_G5=$(printf '\033[1;38;5;135m')
                C_G6=$(printf '\033[1;38;5;48m')
                ;;
            *)
                C_GRN=$(printf '\033[1;32m')
                C_RED=$(printf '\033[1;31m')
                C_YEL=$(printf '\033[1;33m')
                C_CYN=$(printf '\033[1;36m')
                C_BLU=$(printf '\033[1;34m')
                C_MAG=$(printf '\033[1;35m')
                C_WHT=$(printf '\033[1;37m')
                C_G1="$C_CYN"; C_G2="$C_CYN"; C_G3="$C_BLU"
                C_G4="$C_MAG"; C_G5="$C_MAG"; C_G6="$C_GRN"
                ;;
        esac
    else
        C_RES=""; C_BLD=""; C_DIM=""; C_GRN=""; C_RED=""; C_YEL=""; C_CYN=""
        C_BLU=""; C_MAG=""; C_WHT=""
        C_G1=""; C_G2=""; C_G3=""; C_G4=""; C_G5=""; C_G6=""
    fi
    return 0
}
init_colors

# ==============================================================================
# Универсальный движок TUI / ASCII-графики (Unicode Box-Drawing, Открытые рамки,
# Неоновый градиент, Прогресс-бары, Матрица пинга и Неблокирующий спиннер)
# ==============================================================================
ui_banner() {
    TITLE_SUB="${1:-UNIVERSAL SIDECAR GATEWAY & HOMELAB | ALPINE LINUX EDITION}"
    echo "${C_G1}  ╭──────────────────────────────────────────────────────────────────────────╮${C_RES}"
    echo "${C_G1}  │  ██████╗  █████╗ ████████╗███████╗██╗    ██╗ █████╗ ██╗   ██╗            │${C_RES}"
    echo "${C_G2}  │ ██╔════╝ ██╔══██╗╚══██╔══╝██╔════╝██║    ██║██╔══██╗╚██╗ ██╔╝            │${C_RES}"
    echo "${C_G3}  │ ██║  ███╗███████║   ██║   █████╗  ██║ █╗ ██║███████║ ╚████╔╝   ${C_G6}v2026.11${C_G3}  │${C_RES}"
    echo "${C_G4}  │ ██║   ██║██╔══██║   ██║   ██╔══╝  ██║███╗██║██╔══██║  ╚██╔╝    ${C_WHT}HOMELAB${C_G4}   │${C_RES}"
    echo "${C_G5}  │ ╚██████╔╝██║  ██║   ██║   ███████╗╚███╔███╔╝██║  ██║   ██║     ${C_CYN}ALPINE${C_G5}    │${C_RES}"
    echo "${C_G5}  │  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚══╝╚══╝ ╚═╝  ╚═╝   ╚═╝               │${C_RES}"
    echo "${C_G6}  ├──────────────────────────────────────────────────────────────────────────┴─${C_RES}"
    echo "${C_G6}  │${C_RES} ${C_BLD}◆ ${TITLE_SUB}${C_RES}"
    echo "${C_G6}  ╰────────────────────────────────────────────────────────────────────────────${C_RES}"
    return 0
}

ui_box_top() {
    BOX_TITLE="${1:-}"
    if [ -n "$BOX_TITLE" ]; then
        echo "${C_CYN}╭──[ ${C_BLD}${C_WHT}${BOX_TITLE}${C_RES}${C_CYN} ]──────────────────────────────────────────────────────────${C_RES}"
    else
        echo "${C_CYN}╭────────────────────────────────────────────────────────────────────────────${C_RES}"
    fi
    return 0
}

ui_box_row() {
    echo "${C_CYN}│${C_RES} $*"
    return 0
}

ui_box_sep() {
    SEP_TITLE="${1:-}"
    if [ -n "$SEP_TITLE" ]; then
        echo "${C_CYN}├──[ ${C_BLD}${SEP_TITLE}${C_RES}${C_CYN} ]──────────────────────────────────────────────────────────${C_RES}"
    else
        echo "${C_CYN}├────────────────────────────────────────────────────────────────────────────${C_RES}"
    fi
    return 0
}

ui_box_bottom() {
    echo "${C_CYN}╰────────────────────────────────────────────────────────────────────────────${C_RES}"
    return 0
}

ui_warn_box() {
    W_WHAT="${1:-Обнаружена проблема}"
    W_FIX="${2:-Проверьте конфигурацию или запустите: gateway doctor}"
    echo "${C_RED}╔════════════════════════════════════════════════════════════════════════════${C_RES}"
    echo "${C_RED}║ ▲ ЧТО ПРОИЗОШЛО:${C_RES} ${C_BLD}${W_WHAT}${C_RES}"
    echo "${C_RED}║ ▸ КАК ИСПРАВИТЬ:${C_RES} ${C_YEL}${W_FIX}${C_RES}"
    echo "${C_RED}╚════════════════════════════════════════════════════════════════════════════${C_RES}"
    return 0
}

ui_ok_msg() {
    echo "${C_GRN}  [✔]${C_RES} $*"
    return 0
}

ui_info_msg() {
    echo "${C_CYN}  [◆]${C_RES} $*"
    return 0
}

ui_warn_msg() {
    echo "${C_YEL}  [▲]${C_RES} $*"
    return 0
}

ui_err_msg() {
    echo "${C_RED}  [✖]${C_RES} $*"
    return 0
}

ui_badge() {
    B_STATE="${1:-off}"
    B_LABEL="${2:-STATUS}"
    case "$B_STATE" in
        on|ok|up|active|yes)
            printf "%s[ ● %s ]%s" "$C_GRN" "$B_LABEL" "$C_RES"
            ;;
        warn|wait|locked|pause)
            printf "%s[ ▲ %s ]%s" "$C_YEL" "$B_LABEL" "$C_RES"
            ;;
        err|down|fail|no)
            printf "%s[ ✖ %s ]%s" "$C_RED" "$B_LABEL" "$C_RES"
            ;;
        info|cyan)
            printf "%s[ ◆ %s ]%s" "$C_CYN" "$B_LABEL" "$C_RES"
            ;;
        *)
            printf "%s[ ○ %s ]%s" "$C_DIM" "$B_LABEL" "$C_RES"
            ;;
    esac
    return 0
}

# Визуальный прогресс-бар [████████░░] 78% с авто-сменой цвета (<70% зел, 70-89% желт, >=90% красн)
ui_progress_bar() {
    PCT_VAL="${1:-0}"
    BAR_WIDTH="${2:-10}"
    case "$PCT_VAL" in ''|*[!0-9]*) PCT_VAL=0 ;; esac
    [ "$PCT_VAL" -gt 100 ] && PCT_VAL=100
    [ "$PCT_VAL" -lt 0 ] && PCT_VAL=0

    FILLED=$(( (PCT_VAL * BAR_WIDTH + 50) / 100 ))
    [ "$FILLED" -gt "$BAR_WIDTH" ] && FILLED="$BAR_WIDTH"
    EMPTY=$(( BAR_WIDTH - FILLED ))

    if [ "$PCT_VAL" -ge 90 ]; then
        B_COL="$C_RED"
    elif [ "$PCT_VAL" -ge 70 ]; then
        B_COL="$C_YEL"
    else
        B_COL="$C_GRN"
    fi

    BAR_STR=""
    I_B=0
    while [ "$I_B" -lt "$FILLED" ]; do
        BAR_STR="${BAR_STR}█"
        I_B=$((I_B + 1))
    done
    PAD_STR=""
    I_E=0
    while [ "$I_E" -lt "$EMPTY" ]; do
        PAD_STR="${PAD_STR}░"
        I_E=$((I_E + 1))
    done
    printf "[%s%s%s%s%s] %3d%%" "$B_COL" "$BAR_STR" "$C_DIM" "$PAD_STR" "$C_RES" "$PCT_VAL"
    return 0
}

# Визуальная шкала задержки (Ping Matrix) [■■■░░] 42 ms
ui_ping_bar() {
    RAW_PING="${1:-timeout}"
    MS_NUM=$(printf "%s" "$RAW_PING" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
    if [ -z "$MS_NUM" ] || [ "$MS_NUM" -le 0 ]; then
        printf "[%s░░░░░%s] %s✖ недоступен%s" "$C_RED" "$C_RES" "$C_RED" "$C_RES"
        return 0
    fi
    if [ "$MS_NUM" -le 60 ]; then
        P_COL="$C_GRN"; P_BAR="■■■■■"
    elif [ "$MS_NUM" -le 130 ]; then
        P_COL="$C_GRN"; P_BAR="■■■■░"
    elif [ "$MS_NUM" -le 220 ]; then
        P_COL="$C_YEL"; P_BAR="■■■░░"
    elif [ "$MS_NUM" -le 380 ]; then
        P_COL="$C_YEL"; P_BAR="■■░░░"
    else
        P_COL="$C_RED"; P_BAR="■░░░░"
    fi
    printf "[%s%s%s] %s%4d ms%s" "$P_COL" "$P_BAR" "$C_RES" "$P_COL" "$MS_NUM" "$C_RES"
    return 0
}

# Пошаговый прогресс-индикатор с анимацией для длительных задач
ui_step_progress() {
    STEP_CUR="${1:-1}"
    STEP_TOT="${2:-4}"
    STEP_MSG="${3:-Выполнение операции...}"
    if [ -t 1 ]; then
        for SP_FRAME in "⠋" "⠙" "⠹" "⠸" "⠼" "⠴"; do
            printf "\r  %s[ %s/%s ] %s%s %s%s" "$C_CYN" "$STEP_CUR" "$STEP_TOT" "$C_G1" "$SP_FRAME" "$C_BLD$STEP_MSG" "$C_RES"
            usleep 45000 2>/dev/null || sleep 0.05 2>/dev/null || true
        done
        printf "\r  %s[ %s/%s ] %s▸%s %s\n" "$C_CYN" "$STEP_CUR" "$STEP_TOT" "$C_GRN" "$C_RES" "$STEP_MSG"
    else
        echo "  [ ${STEP_CUR}/${STEP_TOT} ] ▸ ${STEP_MSG}"
    fi
    return 0
}

# ==============================================================================
# Атомарная запись конфигурационных файлов (защита от 0-байтных файлов при сбое питания)
# Запись во временный файл в той же ФС -> принудительный fsync/sync -> chmod -> mv -f
# ==============================================================================
