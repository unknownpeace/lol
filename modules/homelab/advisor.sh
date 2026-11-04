show_media_architecture_advisor() {
    load_gateway_env
    init_homelab_storage
    JF_ST=$(is_module_enabled "jellyfin" && echo "${C_GRN}УСТАНОВЛЕН${C_RES}" || echo "${C_DIM}НЕ АКТИВЕН${C_RES}")
    ND_ST=$(is_module_enabled "navidrome" && echo "${C_GRN}УСТАНОВЛЕН (доп. модуль)${C_RES}" || echo "${C_DIM}ОТКЛЮЧЕН${C_RES}")

    echo ""
    ui_box_top "================================================================="
    echo "${C_BLD} 🎬🎵 Архитектура медиасервера: Интеграция музыки и видео в Jellyfin${C_RES}"
    ui_box_top "================================================================="
    echo " • Статус Jellyfin:  ${JF_ST} | Режим единой медиаплатформы: ${C_GRN}${JELLYFIN_UNIFIED_MEDIA:-yes}${C_RES}"
    echo " • Статус Navidrome: ${ND_ST}"
    ui_box_sep
    echo " ${C_BLD}Рекомендуемая структура библиотек в Jellyfin (https://${DOM_JELLYFIN}):${C_RES}"
    echo "  1. Библиотека «Movies» (Фильмы)   -> каталог: ${C_CYN}${STORAGE_VIDEOS_MOVIES}${C_RES} (и ${STORAGE_VIDEOS})"
    echo "  2. Библиотека «Shows»  (Сериалы)  -> каталог: ${C_CYN}${STORAGE_VIDEOS_SERIES}${C_RES}"
    echo "  3. Библиотека «Music»  (Музыка)   -> каталог: ${C_CYN}${STORAGE_MUSIC}${C_RES}"
    ui_box_sep
    echo " ${C_BLD}Сравнение возможностей (на ноябрь 2026 г.):${C_RES}"
    echo "  • ${C_GRN}Jellyfin как единая платформа (Видео + Музыка):${C_RES}"
    echo "    [+] Один сервер и единый веб-интерфейс для фильмов, сериалов и музыки."
    echo "    [+] Отличное мобильное приложение для музыки: Finamp (Android/iOS, офлайн-кэш, gapless)"
    echo "        и Symfonium, плюс штатные клиенты Jellyfin на Smart TV / ПК."
    echo "    [+] Аппаратное/программное транскодирование через jellyfin-ffmpeg (FLAC/ALAC/Opus/MP3)."
    echo "    [-] Не поддерживает протокол Subsonic API из коробки."
    echo "  • ${C_CYN}Navidrome как дополнительный музыкальный модуль:${C_RES}"
    echo "    [+] Ультра-легкий (~40-50 МБ ОЗУ), мгновенная индексация больших аудиотек."
    echo "    [+] Полная поддержка Subsonic / OpenSubsonic API (DSub, Ultrasonic, Amperfy, Supersonic)."
    echo "    [+] Оба сервиса (Jellyfin и Navidrome) могут работать ОДНОВРЕМЕННО поверх"
    echo "        единого каталога ${STORAGE_MUSIC} без конфликтов!"
    ui_box_sep
    echo " Выберите режим работы медиастэка:"
    echo "  1) ${C_GRN}Единая платформа Jellyfin (Видео + Музыка)${C_RES} — установить/обновить Jellyfin и выдать права на ${STORAGE_MUSIC}"
    echo "  2) ${C_CYN}Гибридный режим (Jellyfin + Navidrome одновременно)${C_RES} — оба сервиса читают ${STORAGE_MUSIC}"
    echo "  3) Отключить Navidrome (оставить только Jellyfin для экономии ОЗУ, сохранив все файлы)"
    echo "  0) Назад"
    printf "Выбор [0-3]: "
    read -r MA_ACT < /dev/tty || true
    case "$MA_ACT" in
        1)
            JELLYFIN_UNIFIED_MEDIA="yes"
            save_homelab_env
            install_module_jellyfin || true
            repair_storage_permissions
            echo "${C_GRN}[✓] Jellyfin настроен как единая медиаплатформа с полным доступом к ${STORAGE_VIDEOS} и ${STORAGE_MUSIC}!${C_RES}"
            ;;
        2)
            JELLYFIN_UNIFIED_MEDIA="yes"
            save_homelab_env
            install_module_jellyfin || true
            install_module_navidrome || true
            repair_storage_permissions
            echo "${C_GRN}[✓] Активирован гибридный режим: Jellyfin и Navidrome работают параллельно над единой медиатекой!${C_RES}"
            ;;
        3)
            JELLYFIN_UNIFIED_MEDIA="yes"
            save_homelab_env
            is_module_enabled "navidrome" && remove_module_navidrome || true
            is_module_enabled "jellyfin" || install_module_jellyfin || true
            repair_storage_permissions
            echo "${C_GRN}[✓] Navidrome отключен, Jellyfin работает как единый сервер для музыки и видео.${C_RES}"
            ;;
    esac
    return 0
}

# 6. Модуль yt-dlp с веб-интерфейсом (Очередь, прогресс, форматы, авто-сортировка Music / Videos / Movies / Series)
