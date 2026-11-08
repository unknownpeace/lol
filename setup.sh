#!/bin/sh
set -e

# ==============================================================================
# 🚀 Sidecar Gateway & Homelab: Установщик модульного репозитория
# Регистрирует команду /usr/bin/gateway и запускает шлюз
# ==============================================================================

GATEWAY_DIR="$(cd -P "$(dirname "$0")" && pwd)"
INSTALL_BIN="/usr/bin/gateway"

echo "=================================================================="
echo " 🚀 Установка Universal Sidecar Gateway & Homelab (Modular Git Edition)"
echo "=================================================================="

# 1. Проверка прав суперпользователя
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Ошибка: Для установки шлюза требуются права суперпользователя (root)."
    echo "    Запустите скрипт через sudo: sudo ./setup.sh"
    exit 1
fi

# 1.5. Проверка и установка базовых зависимостей
if command -v apk >/dev/null 2>&1; then
    echo "[*] Проверка системных пакетов (jq, curl, nftables, ca-certificates, git)..."
    apk add --no-cache jq curl nftables ca-certificates git >/dev/null 2>&1 || true
fi

# 2. Выставление прав на исполнение
chmod +x "${GATEWAY_DIR}/gateway.sh"

# 3. Регистрация глобальных команд gateway и gw через прямые symlinks
mkdir -p /usr/bin
ln -sf "${GATEWAY_DIR}/gateway.sh" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"
ln -sf "${GATEWAY_DIR}/gateway.sh" /usr/bin/gw 2>/dev/null || true
chmod +x /usr/bin/gw 2>/dev/null || true

# 3.5. Установка динамического MOTD и автодополнения в /etc/profile.d
mkdir -p /etc/profile.d
cat << 'MOTD_EOF' > /etc/profile.d/00-gateway-motd.sh
# Динамический баннер состояния шлюза при входе через SSH/консоль
if [ -t 1 ] && [ -x /usr/bin/gateway ]; then
    /usr/bin/gateway motd
fi
MOTD_EOF
chmod 644 /etc/profile.d/00-gateway-motd.sh 2>/dev/null || true

cat << 'COMP_EOF' > /etc/profile.d/gateway-completion.sh
# Автодополнение для команд gateway и gw (только в Bash)
if [ -n "$BASH_VERSION" ]; then
    eval '
    _gateway_completions() {
        local cur prev
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        local commands="status test doctor restart reload update autoupdate watchdog check unlock lock eject safe-reboot safe-poweroff logs proxy domain ssl links storage disk homelab lxc backup passwd answers motd help"
        case "$prev" in
            gateway|gw)
                COMPREPLY=($(compgen -W "$commands" -- "$cur"))
                return 0
                ;;
            lxc|container|containers)
                COMPREPLY=($(compgen -W "list create start stop restart attach snap autostart rm menu doctor" -- "$cur"))
                return 0
                ;;
            proxy)
                COMPREPLY=($(compgen -W "add list status" -- "$cur"))
                return 0
                ;;
            domain|domains)
                COMPREPLY=($(compgen -W "direct proxy test check" -- "$cur"))
                return 0
                ;;
            ssl|cert)
                COMPREPLY=($(compgen -W "status renew duckdns local" -- "$cur"))
                return 0
                ;;
            homelab)
                COMPREPLY=($(compgen -W "status links disk unlock lock media install remove restart update" -- "$cur"))
                return 0
                ;;
            backup)
                COMPREPLY=($(compgen -W "create full restore telegram" -- "$cur"))
                return 0
                ;;
            update)
                COMPREPLY=($(compgen -W "check status" -- "$cur"))
                return 0
                ;;
            answers)
                COMPREPLY=($(compgen -W "template show verify" -- "$cur"))
                return 0
                ;;
        esac
    }
    complete -F _gateway_completions gateway gw 2>/dev/null || true
    '
fi
COMP_EOF
chmod 644 /etc/profile.d/gateway-completion.sh 2>/dev/null || true

echo "[✓] Глобальные команды зарегистрированы: ${INSTALL_BIN} и /usr/bin/gw"
echo "[✓] Системный баннер и Tab-автодополнение установлены в /etc/profile.d"
echo "[*] Теперь вы можете обновлять шлюз в любое время через 'gw update' или 'cd ${GATEWAY_DIR} && git pull'."
echo "[*] Запуск шлюза..."
echo ""

# 4. Передача управления в CLI шлюза
exec "$INSTALL_BIN" "$@"
