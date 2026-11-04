# ==============================================================================
# Маршрутизация аргументов командной строки (CLI: `gateway <command>`)
# ==============================================================================
case "${1:-}" in
    autoupdate)
        run_autoupdate
        ;;
    watchdog)
        run_watchdog
        ;;
    test|status)
        run_self_test
        ;;
    doctor|fix|heal|repair)
        run_gateway_doctor
        ;;
    unlock|luks-open)
        unlock_external_storage_cli
        ;;
    lock|eject|unmount|luks-close)
        unmount_external_storage_safe
        ;;
    safe-reboot|reboot-safe)
        safe_power_action "reboot"
        ;;
    safe-poweroff|safe-shutdown|poweroff-safe)
        safe_power_action "poweroff"
        ;;
    restart|reload)
        backup_gateway_state
        load_gateway_env
        if apply_and_verify_singbox "CLI: Пересборка конфига и перезапуск шлюза"; then
            conntrack -F >/dev/null 2>&1 || true
            service_ctl adguardhome restart
            ui_ok_msg "Таблица conntrack сброшена, службы Sing-Box и AdGuard Home перезапущены."
        fi
        ;;
    update|upgrade)
        ui_banner "GATEWAY UPDATE // ОБНОВЛЕНИЕ ЯДЕР И МОДУЛЕЙ HOMELAB"
        update_cores_only "yes"
        service_ctl sing-box restart
        service_ctl adguardhome restart
        if [ -f "$HOMELAB_STATE" ]; then
            while IFS='|' read -r M_ID M_EN _REST; do
                case "$M_ID" in ''|\#*) continue ;; esac
                [ "$M_EN" = "yes" ] && homelab_module_dispatch "$M_ID" "update"
            done < "$HOMELAB_STATE"
        fi
        ;;
    logs|log)
        show_service_logs_cli "${2:-sing-box}" "${3:-45}"
        ;;
    proxy)
        case "${2:-}" in
            add)
                shift 2
                cli_proxy_add "$*"
                ;;
            list|status)
                print_proxy_slots_report
                list_my_nodes
                ;;
            *)
                manage_nodes_cli_menu
                ;;
        esac
        ;;
    domain|domains)
        case "${2:-}" in
            direct)
                cli_domain_rule_add "direct" "${3:-}"
                ;;
            proxy)
                cli_domain_rule_add "proxy" "${3:-}"
                ;;
            test|check|inspect)
                inspect_domain_route
                ;;
            *)
                ui_warn_box "Укажите действие для домена: direct или proxy." \
                            "Пример: gateway domain direct https://kinopoisk.ru  ИЛИ  gateway domain proxy https://openai.com"
                ;;
        esac
        ;;
    links|urls|info)
        print_quick_access_card
        ;;
    disk|disks|storage)
        manage_external_disks_menu
        ;;
    install)
        run_installer
        ;;
    homelab)
        case "${2:-}" in
            status|test)        run_homelab_self_test ;;
            links|urls)         print_quick_access_card ;;
            disk|disks|storage) manage_external_disks_menu ;;
            unlock)             unlock_external_storage_cli ;;
            lock|eject)         unmount_external_storage_safe ;;
            media)              show_media_architecture_advisor ;;
            install)            [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "install" || prompt_homelab_modules_wizard ;;
            remove)             [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "remove" ;;
            restart)            [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "restart" ;;
            update)             [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "update" ;;
            *)                  show_homelab_menu ;;
        esac
        ;;
    backup)
        case "${2:-create}" in
            create)   create_unified_backup "no" ;;
            full)     create_unified_backup "yes" ;;
            restore)  restore_unified_backup ;;
            telegram) [ -f "$BACKUP_ARCHIVE" ] || create_unified_backup "no"; send_telegram_backup "$BACKUP_ARCHIVE" ;;
        esac
        ;;
    help|--help|-h)
        print_gateway_cli_help
        ;;
    *)
        if [ ! -f "$SB_CONF" ]; then
            run_installer
        else
            show_menu
        fi
        ;;
esac