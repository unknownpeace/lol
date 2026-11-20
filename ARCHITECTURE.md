# 🏛️ Архитектура проекта: Gateway & Homelab Suite (Alpine Linux)

> **Актуальность:** 20 ноября 2026 года (целевая платформа — исключительно **Alpine Linux** + OpenRC + `apk`; `opkg`, OpenWrt и Docker не используются).

Документ описывает внутреннее устройство, структуру каталогов, сетевую топологию, логику маршрутизации двойного ядра (**Sing-Box Extended v1.14.3** ⇄ **Mihomo v1.19.34**) и принципы модульности проекта.

---

## 📌 1. Концепция и сетевая топология

1. **Модульная архитектура (`gateway.sh`):**
   Все компоненты разбиты по независимым файлам в `lib/`, `modules/`, `ui/`. Проект клонируется в `/opt/gateway` и регистрируется глобальными командами `gw` и `gateway`.

2. **Схема Sidecar-шлюза (Z83II + Основной роутер `192.168.1.5`):**
   - Основной роутер (`192.168.1.5`) остаётся DHCP-сервером локальной сети и раздаёт клиентам в качестве Default Gateway и DNS-сервера локальный IP сервера на Alpine Linux (например, мини-ПК Z83II, подключённый по Ethernet).
   - Сама система Alpine Linux использует `192.168.1.5` как свой шлюз в интернет (`GW_IP`).
   - Для корректной однопортовой маршрутизации на физическом интерфейсе `${LAN_IF}` применяются `rp_filter=0`, `send_redirects=0`, `accept_redirects=0`, `secure_redirects=0`, `nf_conntrack_tcp_be_liberal=1`, `fq_codel` + `BBR`, а `nftables` настраивает `masquerade persistent` (с автоматическим откатом на `masquerade` при отсутствии поддержки в ядре), принудительный редирект LAN DNS `:53`, drop IPv6 и reject DoT/DoQ `:853`.

3. **Автономность и отсутствие Docker:**
   Все службы (Sing-Box Extended `v1.14.3-extended-2.7.3` или Mihomo `v1.19.34`, AdGuard Home `v1.0.0`, Zashboard `v3.30.0` / MetaCubeXD `v1.275.2`, Caddy, Samba, Vaultwarden, Forgejo, MeTube, Transmission, Server-Code) работают нативно через OpenRC. Оба ядра шлюза поднимают унифицированный интерфейс `gateway-tun` (`MTU 1400`, `stack: system`, `auto_redirect: true`) и слушают `:1053` (DNS), `:7890` (Mixed Proxy) и `:9090` (Clash API + Web UI).

---

## 🗂️ 2. Структура каталогов

```text
├── gateway.answers.example     # Шаблон для автоматической тихой установки (GW_IP="auto" / 192.168.1.5)
├── gateway.sh                  # Главная точка входа и загрузчик модулей (/usr/bin/gateway, /usr/bin/gw)
├── setup.sh                    # Регистрация команд, автодополнения и MOTD
├── ARCHITECTURE.md             # Данный архитектурный справочник
├── AGENTS.md                   # Памятка и инструкции для AI-ассистентов
├── config/
│   ├── gateway.env.example     # Пример конфигурации шлюза (GW_IP="192.168.1.5")
│   └── homelab.env.example     # Хранилище, пользователи, диски
├── lib/
│   ├── constants.sh            # Глобальные пути, CORE_TUN_IF="gateway-tun", фильтры подписок, DEFAULT_ROUTER_IP="192.168.1.5"
│   ├── core.sh                 # Атомарная запись, lock-файлы, service_ctl, get_lan_ifname, get_default_router_ip
│   ├── routing_rules.sh        # Единый источник правды списков доменов (ИИ, Game CDN, Bootstrap, DDR, Homelab .lan)
│   ├── env.sh                  # Валидация конфигов (sing-box check и mihomo -t) и проверки состояний
│   ├── env_store.sh            # Безопасное сохранение/чтение gateway.env (вкл. CORE_ENGINE, WEB_UI) и homelab.env
│   ├── metrics.sh              # Метрики ОЗУ/диска и восстановление после сбоя питания
│   └── ui.sh                   # Цвета ANSI, рамки, прогресс-бары и баннеры
├── modules/
│   ├── adguard/adguard.sh      # Синхронизация *.lan rewrites (поддержка flow/block YAML) и bootstrap_dns
│   ├── caddy/                  # Reverse Proxy, Local PKI (ca.lan) и Let's Encrypt DuckDNS
│   ├── core/engine.sh          # Диспетчер ядер (singbox ⇄ mihomo) и веб-панелей (zashboard ⇄ metacubexd)
│   ├── homelab/                # Реестр, диспетчер, self-test и 5 прикладных OpenRC-сервисов
│   ├── lxc/lxc.sh              # Контейнеры LXC (lxcbr0 10.0.3.x / macvlan со шлюзом на Z83II)
│   ├── mihomo/                 # Установка Mihomo (amd64-v1/v3, arm64) и генератор config.yaml (.mrs)
│   ├── network/
│   │   ├── dhcp.sh             # DHCP-сервер AdGuard Home с проверкой стороннего DHCP (без dnsmasq)
│   │   ├── firewall.sh         # nftables: Kill-Switch 2.0 (gateway-tun), DNS :53 redirect, DoT :853 reject, masquerade persistent
│   │   └── lan.sh              # Сканирование ARP + AdGuard leases.json
│   ├── samba/samba.sh          # SMB2/SMB3, WSDD (Windows 11) и Avahi mDNS
│   ├── singbox/                # Генератор config.json, rule-sets (.srs), WARP 2.0 + MASQUE H2, диагностика нод
│   ├── storage/                # Монтирование дисков (ext4/btrfs/f2fs) и LUKS2
│   └── tools/                  # Бэкапы, cron, doctor, maintenance, password, selftest, telegram
└── ui/                         # CLI диспетчер, TUI меню (16 разделов) и мастер установки
```

---

## 🌐 3. Архитектура ядер: Sing-Box Extended v1.14.3 и Mihomo v1.19.34 (20 ноября 2026)

Оба ядра используют общий контракт: интерфейс **`gateway-tun`** (`MTU 1400`, **`stack: system`**, `auto_redirect: true`, `strict_route: true`; `172.19.0.1/30` в Sing-Box, `198.18.0.1/30` в Mihomo FakeIP), DNS `:1053` за AdGuard Home `:53`, прокси `:7890` и Clash API + панель (`Zashboard` или `MetaCubeXD`) на `:9090/ui/`. Списки доменов берутся из единого источника `lib/routing_rules.sh`.
- **Sing-Box Extended (`config.json`, `.srs`):** поддерживает гибридный WARP 2.0 (4 UDP AmneziaWG + TCP `MASQUE H2`), `store_fakeip`/`store_warp_config`/`store_masque_config`.
- **Mihomo / Clash Meta (`config.yaml`, `.mrs`):** нативный Clash YAML, `fake-ip-filter-mode: rule`, `nameserver-policy`, `rcode://name_error` для DDR/DoH-канареек, guard `IP-CIDR,198.18.0.0/15,REJECT,no-resolve` для устаревших FakeIP, поддержка `AmneziaWG` в `wireguard` (без `MASQUE H2`).
- По умолчанию используется **`stack: "system"`**: по результатам A/B-тестирования на Alpine (Linux `6.18.62-0-lts`) отказ от `gVisor` для UDP снизил нагрузку на CPU (~7%), ОЗУ и вдвое уменьшил джиттер на UDP-нагрузке.

### DNS-пайплайн (`dns` в `/etc/sing-box/config.json`):
Используются исключительно типизированные серверы Sing-Box 1.14 (`cache_capacity: 8192`, **без** устаревших `independent_cache` и `legacy` полей):
1. **`dns_homelab` (`type: "hosts"`)** — мгновенный локальный резолв доменов `*.lan` сервисов в LAN IP сервера.
2. **`dns_local` (`type: "udp"`)** — запросы локальной сети (`.lan`, `.home.arpa`, `.local`, `private_domain`) уходят на основной роутер (`${GW_IP}:53`).
3. **`dns_ru` (`type: "https"`, `77.88.8.1`, `common.dot.dns.yandex.net`, `DIRECT`)** — реальные IP для РФ (`category-ru`), торрент-трекеров, `user_direct_domains`, `google_domain` (не-AI) и **всех игровых платформ и CDN** (`steam`, `epicgames`, `riot`, `ea`, `ubisoft`, `blizzard`, `playstation`, `xbox`, `nintendo`), чтобы не ломать античиты и NAT.
4. **`dns_bootstrap` (`type: "https"`, `9.9.9.9`, `dns.quad9.net`, `DIRECT`)** — надёжный высокопараллельный `default_domain_resolver` для загрузки подписок, узлов, rule-set'ов GitHub и пакетов `alpinelinux.org`.
5. **`dns_fakeip` (`type: "fakeip"`, `198.18.0.0/15`)** — выдаётся для `A`-запросов `user_proxy_domains`, всех ИИ-доменов, медиа/мессенджеров/расширенных прокси-списков и общего fallback (`query_type: ["A"]`).
6. **`dns_ai` (`type: "https"`, `1.1.1.1`, `detour: "🤖 Нейросети (ИИ)"`)** — обслуживает не-A запросы ИИ-доменов строго через ИИ-туннель (Zero-Leak).
7. **`dns_proxy` (`type: "https"`, `8.8.8.8`, `detour: "⚡ Авто (Самый быстрый)"`)** — финальный резолвер прокси-контура.
- В начале `dns.rules` жёстко блокируются DoH-canary/DDR/iCloud Private Relay (`NXDOMAIN`) и `HTTPS`/`SVCB`/`AAAA` (`NOERROR`).

### Исходящие группы (`outbounds`) и кэш:
- **`experimental.cache_file`**: включены `store_fakeip: true`, `store_warp_config: true`, `store_masque_config: true`. Кэширование подписок на диск отключено намеренно, так как синхронный прогрев сотен нод на старте блокирует запуск TUN/DNS/Clash API в Sing-Box Extended 1.14.3; фоновый `health_check` у провайдеров отключён во избежание дублирующей нагрузки на `urltest`.
- Все provider-зависимые `urltest` группы (`🤖 Авто-ИИ`, `🎮 Авто-Гейминг`, `🇺🇸 Авто-US`, `🇩🇪 Авто-DE`, `⚡ Авто (Самый быстрый)`) инициализируются fail-closed заглушкой `⛔ Нет рабочих нод` (`socks 127.0.0.1:1`), чтобы Sing-Box не подставлял `Compatible` (`Direct`) и не допускал утечку РФ IP при холодном старте или пустом фильтре; малые критичные `urltest` группы размещены перед `⚡ Авто`, а сама `⚡ Авто` дополнительно опирается на `🇩🇪 Авто-DE` и `🇺🇸 Авто-US` для мгновенного прогрева.
- **`⚡ Авто (Самый быстрый)`** (`urltest`, исключает TikTok-каскады и инфо-мусор)
- **`🤖 Нейросети (ИИ)`** (`selector`: `🤖 Авто-ИИ` -> `🇺🇸 США` -> `🇩🇪 Германия` -> `⚡ Авто`)
- **`🇩🇪 Германия`** (`selector` + `urltest` **`🇩🇪 Авто-DE`** с фильтром по Германии без TikTok)
- **`🇺🇸 США`** (`selector` + `urltest` **`🇺🇸 Авто-US`** с фильтром по США)
- **`🎮 Гейминг`** (`selector`: по умолчанию **`DIRECT`**, переключается в `🎮 Авто-Гейминг`, `🇩🇪 Германия`, `🇺🇸 США`, `⚡ Авто`)
- **`🧱 Roblox`** (`selector`: по умолчанию **`🇩🇪 Германия`**, переключается в `⚡ Авто`, `🇺🇸 США`, `🎮 Авто-Гейминг`, `DIRECT`)
- **`💬 Мессенджеры`** (`Telegram`, `WhatsApp`, `Discord` + voice IPs; без глобального перехвата STUN)
- **`▶️ YouTube & Медиа`** (`YouTube`, `Spotify`, `Twitch` + явные медиа-суффиксы)
- **Группа пользовательских/расширенных прокси-правил** (`user_proxy_domains` с высшим приоритетом, `refilter_ip`, `meta_domain`, `facebook_ip`, `tiktok_domain`, `cloudflare` и др. наборы правил)
- **`🌐 Google & Android`** (по умолчанию `DIRECT`, правило размещено **после** всех ИИ-правил)
- **`🧲 Торренты`** (`selector`: по умолчанию **`DIRECT`**, переключается на `🇩🇪 Германия`, `🇺🇸 США`, `⚡ Авто` или любую ноду подписки)
- **`📺 Устройства (Full-VPN)`** (создаётся динамически при наличии IP в `force_proxy_devices.conf`)
- **`🌐 Остальной трафик`** (по умолчанию `DIRECT`)
- В режимах `WARP-only` и `DIRECT-only` (когда нет подписок/ключей с гео-тегами) региональные/авто-группы (`🤖 Авто-ИИ`, `🇩🇪 Германия`, `🇩🇪 Авто-DE`, `🇺🇸 США`, `🇺🇸 Авто-US`, `🎮 Авто-Гейминг`) автоматически вычищаются.

### Ключевые правила маршрутизации (`route.rules`):
1. `dns-in` / `protocol: dns` -> `hijack-dns`, `sniff`, `clash_mode` (`direct`/`global`).
2. `ip_is_private`, `.lan`/`.home.arpa`/`.local`, системный bootstrap, `bypass_devices`, `private`/`user_direct_domains`/`ntp` -> `DIRECT`; порт `853` -> `reject`.
3. `bittorrent`, `torrent_domain` (и порты `6881-6889`, `51413` в Mihomo) -> **`🧲 Торренты`** (по умолчанию `DIRECT`, с возможностью выбора ноды/региона из подписки).
4. QUIC (`udp/443` `reject`) для `user_proxy_domains`, ИИ, YouTube, Meta, Discord, TikTok и расширенных списков маршрутизации (игры не затрагиваются!).
5. `user_proxy_domains` -> пользовательский прокси-пул (высший пользовательский приоритет).
6. `force_proxy_devices` -> `📺 Устройства (Full-VPN)`.
7. Явные ИИ-домены + наборы `ai_domain`, `google_gemini_domain`, `openai_domain`, `anthropic_domain`, `perplexity_domain`, `xai_domain`, `cursor_domain`, `copilot_domain` -> **`🤖 Нейросети (ИИ)`** (по умолчанию `🤖 Авто-ИИ`, строго **до** `google_domain`!).
8. `youtube_domain`/`spotify_domain`/`twitch_domain` + `SPOTIFY_EXTRA_DOMAINS`/`TWITCH_EXTRA_DOMAINS` -> `▶️ YouTube & Медиа`.
9. `telegram`/`whatsapp`/`discord` -> `💬 Мессенджеры`.
10. Игровые CDN (`steamcontent.com`, `epicgames-download1.akamaized.net` и др.) -> `DIRECT`; игровые платформы -> `🎮 Гейминг`; `roblox_domain` + `ROBLOX_EXTRA_DOMAINS` -> **`🧱 Roblox`** (по умолчанию `🇩🇪 Германия`, приоритетнее расширенных списков).
11. `google_domain` -> `🌐 Google & Android`; расширенные списки маршрутизации (Cloudflare/TikTok и др.) -> пользовательский прокси-пул; `ru_domain`/`ru_ip` -> `DIRECT`.

---

## 💾 4. Хранилище и локальные сервисы (AdGuard Home v1.0.0 + Caddy)

- **AdGuard Home `v1.0.0` (`schema_version: 35`):** слушает `0.0.0.0:53`, панель `:3000` (и `https://adguard.lan`), `upstream_dns: [127.0.0.1:1053]`, `ratelimit: 0`, автоматическая синхронизация `filtering.rewrites` для всех доменов `*.lan`.
- **Хранилище `/srv/storage`:** единые права `media:media` (GID 990, `2775` + POSIX ACL), разделение на `Music`, `Videos`, `Downloads` (`Incomplete`), `Backups`.
- **Веб-портал сертификатов:** `http://ca.lan` (или Let's Encrypt Wildcard через DuckDNS).
