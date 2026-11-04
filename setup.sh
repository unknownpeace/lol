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
    echo "[*] Проверка системных пакетов (jq, curl, nftables, ca-certificates)..."
    apk add --no-cache jq curl nftables ca-certificates >/dev/null 2>&1 || true
fi

# 2. Выставление прав на исполнение
chmod +x "${GATEWAY_DIR}/gateway.sh"
[ -d "${GATEWAY_DIR}/scripts" ] && chmod +x "${GATEWAY_DIR}/scripts/"*.sh 2>/dev/null || true

# 3. Регистрация глобальной команды gateway через symlink
mkdir -p /usr/bin
ln -sf "${GATEWAY_DIR}/gateway.sh" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"

echo "[✓] Глобальная команда зарегистрирована: ${INSTALL_BIN} -> ${GATEWAY_DIR}/gateway.sh"
echo "[*] Теперь вы можете обновлять шлюз в любое время через 'cd ${GATEWAY_DIR} && git pull'."
echo "[*] Запуск шлюза..."
echo ""

# 4. Передача управления в CLI шлюза
exec "$INSTALL_BIN" "$@"
