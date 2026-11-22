#!/bin/sh
# ==============================================================================
# Единый источник правды (Single Source of Truth) для списков доменов маршрутизации
# Используется одновременно генераторами Sing-Box Extended и Mihomo (Clash Meta)
# ==============================================================================

# Explicit AI / Neural Network domain suffixes (Zero-Leak AI -> 🤖 Нейросети (ИИ) / dns_ai)
AI_EXPLICIT_DOMAINS="proactivebackend-pa.googleapis.com geller-pa.googleapis.com robinfrontend-pa.googleapis.com alkalimakersuite-pa.clients6.google.com alkalimakersuite-pa.googleapis.com waa-pa.clients6.google.com jnn-pa.googleapis.com generativelanguage.googleapis.com aisandbox-pa.googleapis.com ai.google.dev ai.studio aistudio.google.com makersuite.google.com gemini.google.com gemini.google gemini.gstatic.com bard.google.com deepmind.google deepmind.com notebooklm.google.com notebooklm.google jules.google.com antigravity.google labs.google opal.google openai.com chatgpt.com oaistatic.com oaiusercontent.com sora.com anthropic.com claude.ai claude.com perplexity.ai pplx.ai x.ai grok.com cursor.sh cursor.com cursor-cdn.com codeium.com windsurf.com copilot.github.com githubcopilot.com copilot-proxy.githubusercontent.com v0.dev v0.app lovable.dev manus.im midjourney.com elevenlabs.io suno.com suno.ai runwayml.com lumalabs.ai mistral.ai groq.com openrouter.ai huggingface.co hf.co poe.com cohere.com cohere.ai replicate.com ideogram.ai character.ai civitai.com"

# Game download CDNs routed DIRECT (even when 🎮 Гейминг selector uses proxy)
GAME_CDN_DIRECT_DOMAINS="steamcontent.com dl.steam.clngaa.com epicgames-download1.akamaized.net blzddist1-a.akamaihd.net origin-a.akamaihd.net"

# GitHub & Alpine bootstrap domains routed directly via Quad9 bootstrap resolver (DIRECT)
BOOTSTRAP_DIRECT_DOMAINS="cp.cloudflare.com github.com api.github.com raw.githubusercontent.com objects.githubusercontent.com release-assets.githubusercontent.com"

# Canary DoH / DDR domains blocked with NXDOMAIN to prevent browsers from bypassing DNS :53
DDR_BLOCK_DOMAINS="use-application-dns.net _dns.resolver.arpa mask.icloud.com mask-h2.icloud.com"

# Explicit Roblox domain suffixes (-> 🧱 Roblox selector, default 🇩🇪 Германия)
ROBLOX_EXTRA_DOMAINS="roblox.com rbxcdn.com rbxinfra.net robloxlabs.com rbx.com"

# Explicit Spotify & Twitch media suffixes (-> ▶️ YouTube & Медиа selector)
SPOTIFY_EXTRA_DOMAINS="spotify.com scdn.co spotifycdn.com"
TWITCH_EXTRA_DOMAINS="twitch.tv ttvnw.net jtvnw.net ext-twitch.tv twitchcdn.net"

# Homelab & Gateway local hostnames mapped directly to gateway LAN IP
HOMELAB_SUBDOMAINS="gateway ca adguard zashboard singbox mihomo panel vaultwarden forgejo downloads ytdlp torrents torrent code"
HOMELAB_LAN_DOMAINS="gateway.lan ca.lan adguard.lan zashboard.lan singbox.lan mihomo.lan panel.lan vaultwarden.lan forgejo.lan downloads.lan ytdlp.lan torrents.lan torrent.lan code.lan"

# Возвращает все субдомены Homelab для заданного базового домена (включая корневой домен)
emit_homelab_le_domains() {
    _le_base="$1"
    [ -z "$_le_base" ] && return 0
    _out="$_le_base"
    for _sub in $HOMELAB_SUBDOMAINS; do
        _out="${_out} ${_sub}.${_le_base}"
    done
    printf "%s" "$_out"
}

# Преобразует список доменов через пробел в JSON-массив строк (для Sing-Box)
emit_json_string_array() {
    printf "["
    _first=1
    for _item in $1; do
        [ -z "$_item" ] && continue
        if [ "$_first" -eq 1 ]; then
            printf "\n          \"%s\"" "$_item"
            _first=0
        else
            printf ",\n          \"%s\"" "$_item"
        fi
    done
    printf "\n        ]"
}

# Эмитит YAML nameserver-policy записи `'<prefix><domain>': <upstream>`
emit_yaml_ns_policy() {
    _indent="$1"
    _items="$2"
    _prefix="$3"
    _upstream="$4"
    for _item in $_items; do
        [ -z "$_item" ] && continue
        printf "%s'%s%s': %s\n" "$_indent" "$_prefix" "$_item" "$_upstream"
    done
}

# Эмитит Mihomo правила вида `<indent>- "<RULE_TYPE>,<item>,<TARGET>"`
emit_yaml_typed_rules() {
    _indent="$1"
    _rtype="$2"
    _items="$3"
    _target="$4"
    for _item in $_items; do
        [ -z "$_item" ] && continue
        printf "%s- \"%s,%s,%s\"\n" "$_indent" "$_rtype" "$_item" "$_target"
    done
}

# Эмитит Mihomo QUIC block (AND UDP:443 -> REJECT) для списка DOMAIN-SUFFIX или RULE-SET
emit_yaml_quic_reject_rules() {
    _indent="$1"
    _rtype="$2"
    _items="$3"
    for _item in $_items; do
        [ -z "$_item" ] && continue
        printf "%s- \"AND,((%s,%s),(NETWORK,UDP),(DST-PORT,443)),REJECT\"\n" "$_indent" "$_rtype" "$_item"
    done
}
