# 🤖 Памятка для AI-Ассистентов и Разработчиков (AGENTS.md)

> **Актуализировано:** 20 ноября 2026 года.

Документ содержит критические инварианты репозитория для LLM и разработчиков.

## ⚡ Инварианты платформы и сети

1. **Только Alpine Linux + OpenRC + `apk`:**
   - Целевая ОС — **исключительно Alpine Linux** (musl libc, busybox `sh`, OpenRC `/etc/init.d/<name>`).
   - **OpenWrt, `opkg`, `uci`, `procd`, `fw4` и fallback-и на `dnsmasq` не поддерживаются и запрещены.**
   - Docker **не используется**. Все скрипты обязаны иметь переводы строк **LF (`\n`)** и проходить `sh -n`.

2. **Типовая топология домашней сети (Z83II Sidecar):**
   - Основной роутер с DHCP: по умолчанию `DEFAULT_ROUTER_IP="192.168.1.5"` (`get_default_router_ip`).
   - Сервер Alpine Linux (Z83II) подключён к роутеру по Ethernet, выступает как **шлюз (Default Gateway) и DNS-сервер** для клиентов LAN.
   - DHCP на AdGuard Home выключен по умолчанию (Sidecar); включение блокируется при обнаружении DHCP роутера (`detect_external_dhcp_server`).
   - Обязателен per-interface sysctl тюнинг в `/etc/sysctl.d/99-gateway-forward.conf`: `rp_filter=0`, `send_redirects=0`, `accept_redirects=0`, `secure_redirects=0` на `${LAN_IF_INIT}` + `nf_conntrack_tcp_be_liberal=1`.

3. **Версии ядер, панелей и схемы (на 20.11.2026):**
   - `shtorm-7/sing-box-extended`: `v1.14.3-extended-2.7.3`.
   - `MetaCubeX/mihomo`: `v1.19.34` (`amd64-v1`/`amd64-v3`/`arm64`).
   - `AdguardTeam/AdGuardHome`: `v1.0.0` (`schema_version: 35`, `ratelimit: 0`).
   - Веб-панели (:9090/ui): `Zephyruso/zashboard` (`v3.30.0`) или `MetaCubeX/metacubexd` (`v1.275.2`).
   - Единый источник доменов: `lib/routing_rules.sh`; при правке ИИ/игровых CDN/bootstrap/DDR списков править только там.
   - Общий TUN-интерфейс обоих ядер: `CORE_TUN_IF="gateway-tun"` (`MTU 1400`, `stack: system`, `auto_redirect: true`; в Sing-Box адрес `172.19.0.1/30`, в Mihomo 1.19 при активном FakeIP адрес `198.18.0.1/30` берётся из `fake-ip-range: 198.18.0.1/16` с автоисключением `.0.1/.0.2` + guard `IP-CIDR,198.18.0.0/15,REJECT,no-resolve`).
   - В `gateway_cli_dispatch` (`ui/cli.sh`) и генераторах конфигов сохраняется выбранный `CORE_ENGINE`/`WEB_UI` до `load_gateway_env`.
   - Запрещены устаревшие настройки Sing-Box 1.14: `independent_cache`, legacy DNS поля и переменные окружения `ENABLE_DEPRECATED_WIREGUARD_OUTBOUND` / `ENABLE_DEPRECATED_SPECIAL_OUTBOUNDS`.

## 🌐 Критические правила маршрутизации (`modules/singbox/config.sh`)

1. **Единое определение `service_ctl`:** каноническая функция находится в `lib/core.sh`; не дублировать в модулях.
2. **Подписки:** remote-провайдеры используют `"user_agent": "clash.meta"` (возвращает полный набор нод, включая `XHTTP` и `Hysteria2`) и строгую фильтрацию инфо-мусора из `lib/constants.sh`.
3. **Группы и селекторы:**
   - `⚡ Авто (Самый быстрый)` (`urltest`, исключает TikTok-каскады),
   - `🤖 Нейросети (ИИ)` (`selector` -> `🤖 Авто-ИИ` / `🇺🇸 США` / `🇩🇪 Германия` / `⚡ Авто`),
   - `🇩🇪 Германия` (`🇩🇪 Авто-DE`), `🇺🇸 США` (`🇺🇸 Авто-US`),
   - `🎮 Гейминг` (по умолчанию **`DIRECT`**, переключается в `🎮 Авто-Гейминг` / `🇩🇪 Германия` / `🇺🇸 США`),
   - `💬 Мессенджеры`, `▶️ YouTube & Медиа`, пользовательская/расширенная прокси-группа, `🌐 Google & Android` (`DIRECT`), `🌐 Остальной трафик` (`DIRECT`).
   - В режимах без подписок/ключей (`WARP-only` и `DIRECT-only`) региональные/авто-группы удаляются из `config.json`.
   - Во все provider-зависимые `urltest` группы добавляется fail-closed заглушка `⛔ Нет рабочих нод` (`socks 127.0.0.1:1`), исключающая автоподстановку `Compatible` (`Direct`). Малые критичные `urltest` группы (`🤖 Авто-ИИ`, `🎮 Авто-Гейминг`, `🇺🇸 Авто-US`, `🇩🇪 Авто-DE`) идут до `⚡ Авто (Самый быстрый)`, а у `⚡ Авто` дополнительно указаны fallback-группы `🇩🇪 Авто-DE` и `🇺🇸 Авто-US`. В `cache_file` сохраняются FakeIP и WARP/MASQUE (без дискового кэша подписок, блокирующего Stage 1), а дублирующий `health_check` у провайдеров выключен.
   - При изменении структуры `outbounds` в `jq`-ветках `config.sh` запрещено использовать хрупкую позиционную индексацию `.outbounds[0]` / `.outbounds[1:-1]` (сборка идёт по тегам).
4. **Zero-Leak для нейросетей:**
   - ИИ-домены (`proactivebackend-pa.googleapis.com`, `geller-pa.googleapis.com`, `robinfrontend-pa.googleapis.com`, `alkalimakersuite-pa.clients6.google.com`, `aistudio.google.com`, `antigravity.google`, `copilot.github.com`, `copilot-proxy.githubusercontent.com`, `openai`, `anthropic`, `perplexity`, `xai`, `cursor` и др.) должны резолвиться в FakeIP (`A`) и `dns_ai` (прочие типы) и маршрутизироваться в `🤖 Нейросети (ИИ)` **строго ДО** `google_domain` и `DIRECT`.
   - Обязателен блок `use-application-dns.net`, `_dns.resolver.arpa`, `mask.icloud.com`, `mask-h2.icloud.com` (`NXDOMAIN`) и `HTTPS`/`SVCB`/`AAAA` (`NOERROR`).
   - Запрещено смешивать разные типы матчеров (`domain_suffix` и `rule_set`) в одном объекте правила Sing-Box без явного намерения `AND`.
5. **Гейминг и торренты:**
   - Игровые домены и CDN резолвятся реальным IP (`dns_ru`, без FakeIP); игровые CDN (`steamcontent.com`, `epicgames-download1.akamaized.net` и др.) всегда `DIRECT`.
   - Запрещён слепой перехват UDP-портов `3478`, `5349`, `19302`, `50000:50100` и `stun_domain`.
   - `tun` MTU = `1400`, `stack = system` (`CORE_TUN_IF="gateway-tun"`); в `nftables` используется `masquerade persistent` (с fallback на `masquerade`).
   - При проверке подавления DDR/DoH (NXDOMAIN) на Mihomo домены `DDR_BLOCK_DOMAINS` обязаны стоять как `real-ip` в начале `fake-ip-filter`, чтобы запрос дошёл до `nameserver-policy` (`rcode://name_error`).
   - `🧱 Roblox` идёт с более высоким приоритетом до расширенных списков и по умолчанию использует `🇩🇪 Германия`; `🧲 Торренты` по умолчанию идут `DIRECT`, с возможностью переключения в панели/CLI на группы или ноды подписки.

## 🧩 Модульное тестирование Homelab

- Для тестирования конкретного сервиса можно запускать скрипт напрямую:
  ```sh
  sh modules/homelab/services/torrent.sh [install|remove|restart|status]
  sh modules/homelab/services/ytdlp.sh [install|remove|restart|status]
  sh modules/samba/samba.sh [install|remove|status]
  ```
- Единая группа хранилища `/srv/storage`: `media` (GID `990`).
