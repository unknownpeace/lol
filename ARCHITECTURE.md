# 🏛️ Архитектура проекта: Gateway & Homelab Suite (Alpine Linux)

Документ описывает внутреннее устройство, структуру каталогов, логику маршрутизации трафика и принципы модульности проекта. Предназначен как для разработчиков-людей, так и для AI-ассистентов (LLM/Agents), поддерживающих кодовую базу.

---

## 📌 1. Концепция и ключевые принципы

1. **Модульная архитектура (`gateway.sh`):**
   Все компоненты разбиты по независимым файлам в `lib/`, `modules/`, `ui/`. Удобно разрабатывать, тестировать и отлаживать каждый сервис в изоляции. Проект устанавливается и клонируется напрямую в `/opt/gateway`.

2. **Полная автономность каждого модуля:**
   Каждый скрипт в `modules/homelab/services/` и других подпапках может запускаться независимо:
   ```sh
   sh modules/homelab/services/torrent.sh install   # Установит и запустит только Transmission
   sh modules/homelab/services/ytdlp.sh restart     # Перезапустит только MeTube
   sh modules/samba/samba.sh status                 # Проверит статус Samba
   ```
   В начале каждого модуля находится блок самоопределения корня проекта (`GATEWAY_DIR`) и загрузка только необходимых библиотек, если скрипт запущен напрямую.

3. **Легковесность и отсутствие Docker:**
   Все службы разворачиваются **нативно** под Alpine Linux (musl libc) с управлением через **OpenRC** и изоляцией системных пользователей под общей группой `media` (GID 990). Это гарантирует минимальное потребление RAM (работает стабильно даже на 512–1024 МБ памяти).

---

## 🗂️ 2. Структура каталогов и назначение файлов

```
├── gateway.sh                 # Главная точка входа модульного запуска и CLI (/usr/bin/gateway)
├── setup.sh                   # Быстрый скрипт инициализации окружения
├── ARCHITECTURE.md            # Данный архитектурный справочник
├── AGENTS.md                  # Памятка и инструкции для AI-ассистентов
├── lib/                       # Базовые библиотеки
│   ├── constants.sh           # Глобальные пути, порты, домены, пользователи, шаблоны
│   ├── core.sh                # Системные функции (проверка сети, архитектуры, утилиты)
│   ├── env.sh                 # Чтение и валидация переменных конфигурации
│   ├── env_store.sh           # Атомарное сохранение переменных в gateway.env / homelab.env
│   ├── metrics.sh             # Сбор метрик ОЗУ, диска, аптайма
│   └── ui.sh                  # Цвета ANSI, отрисовка рамок, баннеров и спиннеров
├── modules/
│   ├── adguard/
│   │   └── adguard.sh         # Синхронизация DNS Rewrites (*.lan), парсинг AdGuardHome.yaml
│   ├── caddy/
│   │   ├── caddy.sh           # Reverse Proxy, локальный Root CA PKI, веб-портал ca.lan
│   │   └── ssl.sh             # Поддержка Let's Encrypt / DuckDNS / пользовательских сертификатов
│   ├── homelab/
│   │   ├── dispatch.sh        # Диспетчеризация управления службами (install, remove, status)
│   │   ├── registry.sh        # Реестр модулей (/etc/sing-box/homelab/modules.state), umask, права media
│   │   ├── selftest.sh        # Проверка работоспособности сервисов homelab
│   │   └── services/          # Нативные службы (OpenRC)
│   │       ├── code.sh        # VS Code Web Server (нативный Alpine musl бинарник)
│   │       ├── forgejo.sh     # Легковесный Git-сервер Forgejo
│   │       ├── torrent.sh     # Transmission Daemon + Web UI (порт 9091, /srv/storage/Downloads)
│   │       ├── vaultwarden.sh # Менеджер паролей Vaultwarden (порт 8222)
│   │       └── ytdlp.sh       # MeTube Web UI (порт 8081, разделение видео/музыки)
│   ├── lxc/
│   │   └── lxc.sh             # Управление и мониторинг контейнеров LXC
│   ├── network/
│   │   ├── dhcp.sh            # Настройка встроенного DHCP-сервера (dnsmasq)
│   │   ├── firewall.sh        # nftables: Kill-Switch 2.0, перехват DNS (:53), защита портов
│   │   └── lan.sh             # Определение интерфейсов LAN/WAN, смена локального IP
│   ├── samba/
│   │   └── samba.sh           # SMB2/SMB3 шары, WSDD (Windows 11) и Avahi (Linux/macOS)
│   ├── singbox/
│   │   ├── apply.sh           # Применение настроек ядра Sing-Box
│   │   ├── config.sh          # Генерация /etc/sing-box/config.json (DNS, Inbounds, Outbounds, Rules)
│   │   ├── node_diag.sh       # Диагностика и пинг прокси-узлов
│   │   ├── providers.sh       # Парсинг подписок, конвертация VLESS/Trojan/Shadowsocks/Hysteria2
│   │   ├── route_inspect.sh   # Трассировка маршрута домена/IP через правила
│   │   ├── rulesets.sh        # Синхронизация бинарных правил .srs (meta-rules-dat)
│   │   ├── service.sh         # Управление демоном sing-box, резервное копирование .last_good_state
│   │   ├── setup.sh           # Первичная установка бинарника sing-box
│   │   └── warp.sh            # Бесплатный Cloudflare WARP 2.0 + MASQUE H2
│   ├── storage/
│   │   ├── disks.sh           # Монтирование внешних накопителей, авто-fstab
│   │   └── storage_unlock.sh  # Разблокировка LUKS зашифрованных дисков
│   └── tools/                 # Вспомогательные системные инструменты
│       ├── backup.sh          # Создание и восстановление полных бэкапов конфигурации
│       ├── cron_toggles.sh    # Управление фоновыми cron-задачами (автообновления, очистка)
│       ├── doctor.sh          # Комплексный аудит системы (Sing-Box, AdGuard, диски, утечки DNS)
│       ├── maintenance.sh     # Автоматическое обновление компонентов шлюза
│       ├── password.sh        # Ротация единого пароля (Sing-Box + AdGuard + Samba + Homelab)
│       ├── selftest.sh        # Экспресс-тест ядра шлюза и сетевых портов
│       └── telegram.sh        # Оповещения в Telegram бот
└── ui/
    ├── cli.sh                 # Обработка аргументов командной строки `gw <команда>`
    ├── cli_utils.sh           # Хелперы вывода форматированного текста и карточек
    ├── menu.sh                # Интерактивное TUI главное меню
    └── wizard.sh              # Пошаговый мастер первоначальной настройки шлюза
```

---

## 🌐 3. Маршрутизация трафика в Sing-Box (Россия / 2026)

Маршрутизация построена по строгой приоритетной цепочке правил (`route.rules`):

### Исходящие группы (Outbounds):
1. **`⚡ Авто (Самый быстрый)`** — `urltest` по пулу проверенных прокси-нод.
2. **`🤖 ИИ`** — Выделенная группа для ChatGPT, Claude, Gemini, Copilot.
3. **`🌐 Google & Android`** — Сервисы Google (Play Маркет, YouTube Music API, Android OS).
4. **`💬 Мессенджеры`** — Discord, Telegram, WhatsApp (направлены в прокси из-за блокировок/замедлений ТСПУ РКН).
5. **`▶️ YouTube & Музыка`** — YouTube, Spotify, Twitch.
6. **`🎮 Гейминг`** — Steam Community, Roblox, Discord Voice, PSN, Xbox Live.
7. **`🛑 Заблокированные сайты (РКН / Meta)`** — Реестр блокировок, Instagram, Facebook, Twitter/X, запрещенные СМИ.
8. **`🧲 Торренты & P2P`** — **По умолчанию `DIRECT`** (гарантирует максимальную скорость и защиту прокси-серверов от блокировок хостером за торрент-трафик).
9. **`🌐 Остальной трафик`** — По умолчанию `DIRECT`.
10. **`DIRECT`** — Прямой выход через шлюз провайдера.

### 🧠 Критически важное решение: Gemini Spark / Tasks vs Google Group
В официальном приложении Google Gemini кнопка «Задачи» (Spark / Proactive suggestions) обращается к эндпоинтам:
- `proactivebackend-pa.googleapis.com`
- `geller-pa.googleapis.com`
- `robinfrontend-pa.googleapis.com`
- `alkalimakersuite-pa.clients6.google.com`
- `alkalimakersuite-pa.googleapis.com`

**Проблема:** В наборах правил сообщества (`meta-rules-dat`) эти домены входят в категорию `google.srs`, а не `category-ai.srs`. Если вынести Google в отдельную группу или пустить напрямую, мобильный Gemini Spark перестает работать в РФ.
**Решение:** В `modules/singbox/config.sh` эти конкретные FQDN принудительно направляются в группу `🤖 ИИ` **ДО** общего правила `google_domain -> 🌐 Google & Android`.

---

## 💾 4. Файловая структура хранилища и Samba

Все медиа-сервисы обращаются к единому каталогу `/srv/storage` с групповыми правами `media:media` (`umask 002`, `chmod 2775`):

```
/srv/storage/
├── Music/               # Музыкальная библиотека (MeTube скачивает аудио сюда)
├── Videos/              # Видеоархив и фильмы (MeTube скачивает видео сюда)
├── Downloads/           # Загрузки Transmission и временные файлы
│   └── Incomplete/      # Недокачанные торрент-файлы Transmission
└── Backups/             # Автоматические резервные копии шлюза
```

### Сетевые папки Samba (`/etc/samba/smb.conf`):
- `\\<IP>\storage` — Полный доступ ко всему хранилищу.
- `\\<IP>\Music` — Музыка (прямой доступ к `/srv/storage/Music`).
- `\\<IP>\Videos` — Видео (прямой доступ к `/srv/storage/Videos`).
- `\\<IP>\Downloads` — Торренты и скачанные файлы (`/srv/storage/Downloads`).

---

## 🔒 5. Сетевые порты и домены `.lan`

Все веб-панели доступны по локальным HTTPS доменам через Caddy с автоматически выпущенным сертификатом локального CA (`http://ca.lan` для установки корневого сертификата):

| Сервис | Порт | Внутренний домен HTTPS | Логин / Пароль по умолчанию |
|---|---|---|---|
| **Caddy Root CA Portal** | `80` / `443` | `http://ca.lan` | Без пароля |
| **Sing-Box (Zashboard)** | `9090` | `https://zashboard.lan` | Секретный токен шлюза |
| **AdGuard Home** | `3000` (:53 DNS) | `https://adguard.lan` | Единый логин / пароль |
| **Transmission (Торренты)** | `9091` (51413 P2P) | `https://torrents.lan` | Единый логин / пароль |
| **MeTube (Скачивание видео)**| `8081` | `https://downloads.lan`| Единый логин / пароль |
| **Vaultwarden (Пароли)** | `8222` | `https://vaultwarden.lan`| Регистрация по почте |
| **Forgejo (Git)** | `3001` (2222 SSH) | `https://forgejo.lan` | Регистрация первого юзера |
| **VS Code Web Server** | `8443` | `https://code.lan` | Единый логин / пароль |
