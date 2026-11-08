# 🤖 Памятка для AI-Ассистентов и Разработчиков (AGENTS.md)

Файл предназначен для быстрого входа в контекст любой LLM (Gemini, Claude, GPT, Cursor, Windsurf и др.).

## ⚡ Экспресс-правила работы с репозиторием

1. **Модульная структура:**
   - Монолит `Install.sh` упразднен! Репозиторий является полностью модульным.
   - Все изменения вносятся строго по месту в `modules/`, `lib/` или `ui/`.

2. **Модульное тестирование (не запускать весь визард целиком):**
   - Для тестирования конкретного сервиса запускайте скрипт этого сервиса напрямую:
     ```sh
     sh modules/homelab/services/torrent.sh [install|remove|restart|status]
     sh modules/homelab/services/ytdlp.sh [install|remove|restart|status]
     sh modules/samba/samba.sh [install|remove|status]
     ```
   - Каждый сервис умеет подтягивать зависимости самостоятельно, если запущен в изолированном режиме.

3. **Специфика окружения Alpine Linux & Musl:**
   - Дистрибутив: **Alpine Linux** (OpenRC вместо systemd, musl libc вместо glibc, busybox).
   - Docker **не используется**. Все службы работают нативно через OpenRC (`/etc/init.d/<name>`).
   - Системный пользователь для медиа-сервисов — общая группа `media` (GID 990).
   - Репозиторий `community` в `/etc/apk/repositories` должен быть раскомментирован функцией `ensure_alpine_community_repo`.

4. **MeTube (yt-dlp Web UI):**
   - Развернут в `/opt/metube/app`.
   - Запускается через `python3 -m app.main` с `PYTHONPATH="/opt/metube/app/app"`.
   - Переменные путей:
     - `DOWNLOAD_DIR="/srv/storage/Videos"` (все видеофайлы).
     - `AUDIO_DOWNLOAD_DIR="/srv/storage/Music"` (аудио/музыка).

5. **Transmission:**
   - Заменяет qBittorrent. Настройки в `/var/lib/transmission/config/settings.json`.
   - Пользователь: `transmission:media`.
   - Порт Web RPC: `9091`, порт пиров: `51413`.
   - Папка загрузок: `/srv/storage/Downloads` (Incomplete: `/srv/storage/Downloads/Incomplete`).

6. **Маршрутизация Sing-Box (Тонкости правил):**
   - Группа `🧲 Торренты & P2P` всегда должна оставаться `DIRECT` по умолчанию, чтобы не забивать и не компрометировать VPS/прокси торрент-трафиком.
   - Мессенджеры (`Discord`, `Telegram`, `WhatsApp`) объединены в группу `💬 Мессенджеры` и направлены в прокси (ТСПУ РФ блокирует/замедляет их).
   - **Gemini Spark/Tasks:** Домены `proactivebackend-pa.googleapis.com`, `geller-pa.googleapis.com`, `robinfrontend-pa.googleapis.com`, `alkalimakersuite-pa.clients6.google.com` ОБЯЗАТЕЛЬНО должны маршрутизироваться в группу `🤖 ИИ` **раньше**, чем общее правило для `google_domain`.
