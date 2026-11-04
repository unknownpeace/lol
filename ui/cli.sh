# ==============================================================================
# Маршрутизация аргументов командной строки (CLI: `gateway <command>`)
# ==============================================================================
gateway_cli_dispatch() {
    case "${1:-}" in
    autoupdate)
        run_autoupdate
        ;;
    watchdog)
        run_watchdog
        ;;
    check|verify|lint)
        run_gateway_quick_check
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
        case "${2:-}" in
            check|status)
                self_update_gateway "check"
                ;;
            *)
                self_update_gateway
                ;;
        esac
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
    ssl|cert|certs|tls)
        case "${2:-}" in
            status)
                show_ssl_status
                ;;
            renew)
                renew_duckdns_cert_force
                ;;
            local|lan)
                switch_to_local_pki
                ;;
            duckdns|setup)
                if [ -n "${3:-}" ] && [ -n "${4:-}" ]; then
                    if issue_duckdns_cert "$3" "$4"; then
                        sync_caddy_main_config
                        reload_caddy_safe
                        sync_agh_homelab_rewrites
                    fi
                else
                    prompt_ssl_management_menu
                fi
                ;;
            *)
                prompt_ssl_management_menu
                ;;
        esac
        ;;
    links|urls|info)
        print_quick_access_card
        ;;
    motd)
        print_gateway_motd
        ;;
    passwd|password)
        if [ -n "${2:-}" ]; then
            change_unified_password "$2" "yes"
        else
            printf "Введите новый единый мастер-пароль: "
            read -r IN_P < /dev/tty || true
            IN_P=$(printf "%s" "$IN_P" | tr -d '\r\n')
            change_unified_password "$IN_P"
        fi
        ;;
    answers)
        case "${2:-}" in
            template|generate|example)
                generate_answers_template "${3:-}"
                ;;
            verify|check|test)
                verify_answers_file "${3:-}"
                ;;
            *)
                echo "Использование: gw answers template [файл]  ИЛИ  gw answers verify [файл]"
                ;;
        esac
        ;;
    disk|disks|storage)
        manage_external_disks_menu
        ;;
    install|--answers*|-a|-f|--unattended)
        run_installer "$@"
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
}

if [ -z "${GATEWAY_NO_RUN:-}" ]; then
    gateway_cli_dispatch "$@"
fi