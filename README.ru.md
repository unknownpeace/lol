# 🚀 Universal Sidecar Gateway & Homelab (2026 Edition)

<p align="center">
  <a href="README.md"><b>🇬🇧 Read in English (README.md)</b></a>
</p>

[![GitHub Repo](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/unknownpeace/lol)
[![Sing-Box Extended](https://img.shields.io/badge/Sing--Box_Extended-v1.14.3-purple)](https://github.com/shtorm-7/sing-box-extended)
[![AdGuard Home](https://img.shields.io/badge/AdGuard_Home-v0.107.56-green)](https://github.com/AdguardTeam/AdGuardHome)
[![Zashboard](https://img.shields.io/badge/Zashboard-Dashboard-orange)](https://github.com/Zephyruso/zashboard)
[![Vaultwarden](https://img.shields.io/badge/Vaultwarden-Bitwarden-blue)](https://github.com/dani-garcia/vaultwarden)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Полностью автоматизированный программно-аппаратный комплекс для развёртывания **Sidecar-шлюза, модульного домашнего сервера (Homelab & Media Stack) и легковесной виртуализации LXC** для одноплатных компьютеров (Raspberry Pi, Orange Pi, NanoPi), энергоэффективных мини-ПК (Intel N100/N95), контейнеров Proxmox VE LXC/VM или роутеров на базе **Alpine Linux 3.21–3.24+** (и OpenWrt 25.12+).

---

## ⚡ Ключевые возможности комплекса

* **Нативная производительность без оверхеда Docker:** все прикладные службы работают через нативные демоны OpenRC и cgroups v2. Потребление памяти комплексом в режиме покоя — **менее 100 МБ ОЗУ**.
* **Умная селективная маршрутизация:** ядро `sing-box-extended` с автоматическим тестированием задержек (`urltest`), разделением потоков трафика по правилам и резервными цепочками.
* **Двухконтурная система DNS с защитой от подмены:** **AdGuard Home** (порт `:53`) вырезает рекламу, трекеры и отдаёт локальные адреса зоны `*.lan`, а внешние запросы направляются в зашифрованный **DoH** (DNS over HTTPS с валидацией TLS SNI) и **FakeIP (`198.18.0.0/15`)** ядра Sing-Box.
* **Автономная экосистема домашних сервисов:**
  * **Caddy Reverse Proxy & Local PKI:** автоматический центр сертификации и веб-портал установки доверенного сертификата (`http://ca.lan`).
  * **Samba SMB3 + WSDD:** сетевой файловый доступ с мгновенным обнаружением в Windows 11 (24H2) и Linux.
  * **Vaultwarden:** локальный менеджер паролей с поддержкой WebCrypto API и WebAssembly.
  * **MeTube:** загрузчик мультимедиа-контента на базе `yt-dlp`.
  * **Transmission:** лёгкий BitTorrent-клиент с веб-интерфейсом.
  * **Forgejo & Server-Code:** персональный Git-сервер и VS Code Web IDE прямо в браузере.
* **Шифрование накопителей (LUKS2):** поддержка внешних дисков (USB/SATA/NVMe) с разметкой `ext4`, `btrfs` (сжатие `zstd:3`) или `f2fs`, защищённых **LUKS2 (Argon2id + AES-XTS 512-bit)**, с безопасным извлечением (`gw eject`) и автоматической разблокировкой при перезагрузке.
* **Чистая виртуализация LXC:** контейнеры без фонового демона Docker. Загрузка официальных образов (Alpine, Debian, Ubuntu), снимки состояния (снапшоты), мгновенный откат и интеграция в локальную сеть сервера.

---

## 🚀 Быстрая установка

Подключитесь к вашему устройству по SSH под пользователем `root`:

### Вариант 1: Установка через Git (Рекомендуемый)
```sh
apk add --no-cache git
git clone https://github.com/unknownpeace/lol.git /opt/gateway
cd /opt/gateway
./setup.sh
```

### Вариант 2: Автоматическая тихая установка (Zero-Touch)
```sh
# Генерация шаблона: gw answers template /root/answers.env
gw install --answers /root/answers.env
```

После завершения инсталляции панель управления доступна командой:
```sh
gw        # или 'gateway'
```

---

## 🧩 Модульная архитектура

```text
/opt/gateway/
├── gateway.sh                  # Главная точка входа и диспетчер модулей
├── setup.sh                    # Быстрая регистрация команд gw/gateway, автодополнение, баннер MOTD
├── config/                     # Шаблоны конфигураций
│   ├── gateway.env.example     # Сеть, маршрутизация и внешние провайдеры
│   ├── homelab.env.example     # Пути хранилища, доступы Samba, диски
│   └── gateway_answers.env     # Шаблон для автоматической тихой установки
├── lib/                        # Базовые библиотеки ядра
│   ├── constants.sh            # Глобальные пути и переменные окружения
│   ├── ui.sh                   # Рендеринг TUI-интерфейса, цвета, индикаторы
│   ├── core.sh                 # Атомарные транзакции файлов, блокировки, детекция ОС
│   ├── env.sh                  # Проверка параметров окружения
│   ├── env_store.sh            # Безопасное сохранение .env файлов
│   └── metrics.sh              # Телеметрия, контроль памяти и защита при сбое питания
├── modules/                    # Изолированные сервисные модули
│   ├── network/                # nftables, TProxy, Smart DHCP (dnsmasq), сканер сети
│   ├── singbox/                # Генератор config.json, группы селекторов, диагностика
│   ├── adguard/                # AdGuard Home rewrites (*.lan) и интеграция DNS
│   ├── storage/                # LUKS2 шифрование, оптимизация ФС, безопасный монтирование
│   ├── caddy/                  # HTTPS шлюз, локальный PKI CA, портал ca.lan
│   ├── samba/                  # Демон SMB3, wsdd (Windows 11), Avahi mDNS
│   ├── homelab/                # Прикладные модули (Vaultwarden, Transmission, MeTube и др.)
│   ├── lxc/                    # Менеджер контейнеров LXC, сетевые мосты, снапшоты
│   └── tools/                  # Резервные копии, Telegram-бот, Watchdog, авто-доктор
└── ui/                         # Пользовательский интерфейс
    ├── wizard.sh               # Первоначальный мастер настройки и Zero-Touch движок
    ├── menu.sh                 # Интерактивное главное TUI-меню из 16 разделов
    ├── cli.sh                  # Неинтерактивный CLI маршрутизатор
    └── cli_utils.sh            # Горячие команды консоли и вспомогательные экраны
```

---

## 🏠 Каталог модулей домашнего сервера

Все сервисы слушают локальный адрес `127.0.0.1` и публикуются в сеть через Caddy HTTPS:

| Модуль | Служба | Локальный адрес | Порт |
| :--- | :--- | :--- | :--- |
| **`1` (`caddy`)** | **Caddy HTTPS & Local PKI** | `http://ca.lan` (`https://ca.lan`) | `:80` / `:443` |
| **`2` (`samba`)** | **Samba SMB3 + WSDD** | `\\HOMELAB\storage` | `:445` |
| **`3` (`vaultwarden`)** | **Vaultwarden (Bitwarden Server)** | `https://vaultwarden.lan` | `127.0.0.1:8222` |
| **`4` (`forgejo`)** | **Forgejo Git Service** | `https://forgejo.lan` | `127.0.0.1:3001` |
| **`5` (`code`)** | **Server-Code (VS Code Web IDE)** | `https://code.lan` | `127.0.0.1:8443` |
| **`6` (`metube`)** | **MeTube Downloader** | `https://downloads.lan` | `127.0.0.1:8081` |
| **`7` (`torrent`)** | **Transmission Web UI** | `https://torrents.lan` | `127.0.0.1:9091` |

---

## 🛠️ Основные команды CLI

```sh
# Общее состояние и здоровье
gw                           # Открыть главное интерактивное TUI-меню
gw status                    # Полный рентген служб (Self-Test) и пинг-матрица
gw doctor                    # Автоматическое восстановление БД, прав и сети в 1 клик
gw update                    # Бесшовное 5-стадийное обновление из Git
gw links                     # Вывести карточку всех адресов *.lan и доступов

# Маршрутизация и сетевые правила
gw proxy add <url|key|warp>  # Подключить подписку или узел
gw domain direct <домен>     # Направить домен напрямую через WAN
gw domain proxy <домен>      # Направить домен через группу умного проксирования

# Хранилище и криптоконтейнеры
gw unlock                    # Разблокировать и смонтировать диск LUKS2
gw lock                      # Безопасно остановить службы, сбросить буферы и закрыть LUKS2
gw safe-reboot               # Корректная перезагрузка с парковкой баз SQLite
gw safe-poweroff             # Безопасное выключение питания с закрытием диска

# Легковесная виртуализация LXC
gw lxc list                  # Список запущенных контейнеров, IP и ОЗУ
gw lxc create                # Интерактивный мастер создания контейнера
gw lxc snap <имя> create     # Создать снимок состояния (снапшот)
gw lxc snap <имя> restore    # Откатить контейнер к выбранному снимку
```

---

## 📄 Лицензия
Проект распространяется под открытой лицензией [MIT License](LICENSE).
