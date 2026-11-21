#!/bin/sh
# ==============================================================================
# Маршрутизация аргументов командной строки (CLI: `gateway <command>`)
# ==============================================================================
gateway_cli_dispatch() {
    detect_os >/dev/null 2>&1 || true
    load_gateway_env >/dev/null 2>&1 || true
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
    test|status|selftest)
        run_self_test
        ;;
    doctor|fix|heal|repair)
        run_gateway_doctor
        ;;
    unlock|luks-open)
        require_alpine_feature "LUKS2 (unlock)" || return 0
        unlock_external_storage_cli
        ;;
    lock|eject|unmount|luks-close)
        require_alpine_feature "LUKS2 (lock)" || return 0
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
        if apply_and_verify_core "CLI: Пересборка конфига и перезапуск шлюза"; then
            conntrack -F >/dev/null 2>&1 || true
            service_ctl adguardhome restart
            ui_ok_msg "Таблица conntrack сброшена, службы $(get_active_core_name) и AdGuard Home перезапущены."
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
        show_service_logs_cli "${2:-core}" "${3:-45}"
        ;;
    core|engine)
        case "${2:-}" in
            status)
                load_gateway_env
                echo "Активное ядро: $(get_active_core_name) ($(get_active_core_version)) | Интерфейс: ${CORE_TUN_IF}"
                ;;
            singbox|sing-box|sb|mihomo|clash|meta)
                switch_core_engine "$2" || return $?
                ;;
            *)
                prompt_core_and_ui_menu
                ;;
        esac
        ;;
    ui|panel|dashboard)
        case "${2:-}" in
            status)
                load_gateway_env
                echo "Активная веб-панель: $(get_active_ui_name) (http://$(get_current_lan_ip):9090/ui/)"
                ;;
            zashboard|zash|zb|metacubexd|metacube|xd)
                switch_web_ui "$2" || return $?
                ;;
            *)
                prompt_core_and_ui_menu
                ;;
        esac
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
                inspect_domain_route "${3:-}"
                ;;
            *)
                ui_warn_box "Укажите действие для домена: direct или proxy." \
                            "Пример: gateway domain direct https://kinopoisk.ru  ИЛИ  gateway domain proxy https://openai.com"
                ;;
        esac
        ;;
    ssl|cert|certs|tls)
        require_alpine_feature "Подсистема Caddy SSL/PKI" || return 0
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
                    issue_duckdns_cert "$3" "$4" || return $?
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
        require_alpine_feature "Управление внешними дисками (LUKS2)" || return 0
        manage_external_disks_menu
        ;;
    install|--answers*|-a|-f|--unattended)
        run_installer "$@"
        ;;
    homelab)
        require_alpine_feature "Модули Homelab" || return 0
        case "${2:-}" in
            status|test)        run_homelab_self_test ;;
            links|urls)         print_quick_access_card ;;
            disk|disks|storage) manage_external_disks_menu ;;
            unlock)             unlock_external_storage_cli ;;
            lock|eject)         unmount_external_storage_safe ;;
            install)            [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "install" || prompt_homelab_modules_wizard ;;
            remove)             [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "remove" ;;
            restart)            [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "restart" ;;
            update)             [ -n "${3:-}" ] && homelab_module_dispatch "$(resolve_homelab_module_id "$3" || printf "%s" "$3")" "update" ;;
            *)                  show_homelab_menu ;;
        esac
        ;;
    lxc|container|containers)
        require_alpine_feature "Виртуализация LXC" || return 0
        case "${2:-list}" in
            list|ls)
                lxc_list_containers
                ;;
            create|new)
                lxc_create_wizard
                ;;
            start)
                lxc_control "start" "${3:-}"
                ;;
            stop)
                lxc_control "stop" "${3:-}"
                ;;
            restart)
                lxc_control "restart" "${3:-}"
                ;;
            attach|shell|console|exec)
                lxc_control "attach" "${3:-}"
                ;;
            snap|snapshot|snapshots)
                lxc_manage_snapshots "${3:-}" "${4:-}" "${5:-}"
                ;;
            autostart)
                lxc_control "autostart" "${3:-}" "${4:-}"
                ;;
            rm|del|delete|destroy)
                lxc_control "delete" "${3:-}"
                ;;
            menu)
                lxc_interactive_menu
                ;;
            doctor|heal)
                check_and_heal_lxc_doctor
                ui_ok_msg "Диагностика и автоисцеление LXC завершены."
                ;;
            fix-net|net-fix)
                lxc_control "fix-net" "${3:-}"
                ;;
            *)
                echo "Использование: gw lxc [list|create|start|stop|restart|attach|snap|autostart|fix-net|rm|menu]"
                ;;
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
    killswitch|kill-switch|ks)
        case "${2:-status}" in
            on|enable|yes|1)
                sync_dns_firewall "yes" "yes"
                ui_ok_msg "Аппаратный Kill-Switch (nftables) ВКЛЮЧЕН."
                ;;
            off|disable|no|0)
                sync_dns_firewall "yes" "no"
                ui_ok_msg "Аппаратный Kill-Switch (nftables) ВЫКЛЮЧЕН."
                ;;
            status)
                if is_killswitch_enabled; then
                    echo "Kill-Switch: ВКЛЮЧЕН (строгая блокировка трафика мимо ${CORE_TUN_IF})"
                else
                    echo "Kill-Switch: ВЫКЛЮЧЕН"
                fi
                ;;
            *)
                echo "Использование: gw killswitch [on|off|status]"
                return 1
                ;;
        esac
        ;;
    help|--help|-h)
        print_gateway_cli_help
        ;;
    *)
        if [ ! -f "$SB_CONF" ] && [ ! -f "$MIHOMO_CONF" ]; then
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