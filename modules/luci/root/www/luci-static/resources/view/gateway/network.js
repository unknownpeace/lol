'use strict';
'require view';
'require ui';
'require dom';
'require tools.gateway as gw';

return view.extend({
	load: function() {
		return gw.api.status();
	},

	renderBody: function(host, st) {
		var self = this;
		var core = st.core || {};
		var net = st.network || {};
		var agh = st.adguard || {};
		var leases = Array.isArray(agh.dhcp_leases) ? agh.dhcp_leases : [];

		function reload() {
			return gw.api.status().then(function(fresh) {
				if (fresh && fresh.ok)
					self.renderBody(host, fresh);
			});
		}

		var coreSel = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'mihomo' }, 'Mihomo (Clash Meta — YAML + .mrs)'),
			E('option', { 'value': 'singbox' }, 'Sing-Box Extended (JSON + WARP MASQUE H2)')
		]);
		coreSel.value = (core.engine === 'mihomo') ? 'mihomo' : 'singbox';

		var uiSel = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'metacubexd' }, 'MetaCubeXD'),
			E('option', { 'value': 'zashboard' }, 'Zashboard')
		]);
		uiSel.value = (core.ui === 'metacubexd') ? 'metacubexd' : 'zashboard';

		var lanIpIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': net.lan_ip || '' });
		var gwIpIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': net.gw_ip || '' });

		var leaseRows = leases.map(function(l) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, E('strong', l.ip || '')),
				E('td', { 'class': 'td' }, l.mac || '—'),
				E('td', { 'class': 'td' }, l.hostname || '—'),
				E('td', { 'class': 'td' }, l.expires || '—')
			]);
		});

		var leasesTable = leases.length
			? E('table', { 'class': 'table', 'style': 'margin-top: 10px;' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, 'IP'),
					E('th', { 'class': 'th' }, 'MAC'),
					E('th', { 'class': 'th' }, 'Устройство'),
					E('th', { 'class': 'th' }, 'Истекает')
				])
			].concat(leaseRows))
			: E('p', { 'style': 'opacity: 0.75; margin-top: 8px;' }, 'Активных DHCP-аренд в AdGuard Home пока нет.');

		dom.content(host, [
			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Ядро маршрутизации и веб-панель (:9090/ui)'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Активное ядро: ' + (core.name || core.engine || '—') + ' (' + (core.version || '—') + ')'),
						coreSel
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() {
							gw.runJobModal('Переключение ядра: ' + coreSel.value, 'set_core', coreSel.value, '', reload);
						}
					}, 'Применить ядро')
				]),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Активная панель управления: ' + (core.ui_name || core.ui || '—') + ' (' + (core.ui_ver || '—') + ')'),
						uiSel
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() {
							gw.runJobModal('Переключение панели UI: ' + uiSel.value, 'set_ui', uiSel.value, '', reload);
						}
					}, 'Применить панель')
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'DHCP-сервер AdGuard Home и Kill-Switch'),
				E('div', { 'class': 'gw-two-col' }, [
					E('div', { 'class': 'gw-card' }, [
						E('div', { 'class': 'gw-card-title' }, 'DHCP-сервер в локальной сети (' + (net.lan_if || 'br-lan') + ')'),
						E('div', { 'class': 'gw-card-main' }, [
							gw.badge(agh.dhcp_enabled ? 'ok' : 'off', agh.dhcp_enabled ? 'ВКЛЮЧЁН (пул ' + ((agh.dhcp_v4 && agh.dhcp_v4.range_start) || '.100') + '–.239)' : 'ВЫКЛЮЧЕН (режим Sidecar)')
						]),
						E('div', { 'class': 'gw-card-sub' }, 'Перед включением выполняется автоматическая проверка сети на конфликт со сторонним DHCP-сервером.'),
						E('div', { 'class': 'gw-toolbar', 'style': 'margin-top: 10px;' }, [
							E('button', {
								'class': 'btn cbi-button ' + (agh.dhcp_enabled ? 'cbi-button-negative' : 'cbi-button-positive'),
								'click': function(ev) {
									var nextMode = agh.dhcp_enabled ? 'off' : 'on';
									var btn = ev.currentTarget;
									btn.disabled = true;
									gw.api.setDhcp(nextMode).then(function(r) {
										if (r && r.ok) {
											gw.notify('info', r.message || ('DHCP ' + nextMode));
											reload();
										} else {
											gw.notify('danger', (r && r.error) || 'Ошибка переключения DHCP');
										}
									}).catch(function(e) {
										gw.notify('danger', e.message || String(e));
									}).finally(function() { btn.disabled = false; });
								}
							}, agh.dhcp_enabled ? 'Выключить AdGuard DHCP' : 'Включить AdGuard DHCP')
						])
					]),

					E('div', { 'class': 'gw-card' }, [
						E('div', { 'class': 'gw-card-title' }, 'Аппаратный Kill-Switch (nftables)'),
						E('div', { 'class': 'gw-card-main' }, [
							gw.badge(net.killswitch ? 'warn' : 'ok', net.killswitch ? 'KILL-SWITCH ВКЛЮЧЁН' : 'Штатная защита Firewall')
						]),
						E('div', { 'class': 'gw-card-sub' }, 'При активном Kill-Switch блокируется весь транзитный трафик мимо ' + (core.tun_if || 'gateway-tun') + ' (кроме списка обхода IP).'),
						E('div', { 'class': 'gw-toolbar', 'style': 'margin-top: 10px;' }, [
							E('button', {
								'class': 'btn cbi-button ' + (net.killswitch ? 'cbi-button-neutral' : 'cbi-button-negative'),
								'click': function(ev) {
									var nextKs = net.killswitch ? 'off' : 'on';
									var btn = ev.currentTarget;
									btn.disabled = true;
									gw.api.setKillswitch(nextKs).then(function(r) {
										if (r && r.ok) {
											gw.notify('info', r.enabled ? 'Kill-Switch ВКЛЮЧЁН' : 'Kill-Switch ВЫКЛЮЧЕН');
											reload();
										} else {
											gw.notify('danger', (r && r.error) || 'Ошибка nftables');
										}
									}).catch(function(e) {
										gw.notify('danger', e.message || String(e));
									}).finally(function() { btn.disabled = false; });
								}
							}, net.killswitch ? 'Выключить Kill-Switch' : 'Включить Kill-Switch')
						])
					])
				]),
				E('h4', { 'style': 'margin-top: 14px;' }, 'Активные аренды AdGuard Home DHCP'),
				leasesTable
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Сетевые адреса (LAN IP и шлюз)'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'LAN IP адрес этого роутера OpenWrt'),
						lanIpIn
					]),
					E('div', { 'class': 'gw-field' }, [
						E('label', 'IP основного роутера (Gateway Uplink)'),
						gwIpIn
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function(ev) {
							var newLan = lanIpIn.value.trim();
							var newGw = gwIpIn.value.trim();
							if (!newLan || !newGw) {
								gw.notify('warning', 'Укажите оба IP-адреса');
								return;
							}
							var btn = ev.currentTarget;
							btn.disabled = true;
							gw.api.setNetwork(newLan, newGw).then(function(r) {
								if (r && r.ok) {
									if (r.ip_changed) {
										ui.awaitReconnect(r.new_ip);
									} else {
										gw.notify('info', 'Сетевые настройки применены');
										reload();
									}
								} else {
									gw.notify('danger', (r && r.error) || 'Ошибка изменения сети');
								}
							}).catch(function(e) {
								gw.notify('danger', e.message || String(e));
							}).finally(function() { btn.disabled = false; });
						}
					}, 'Применить IP')
				])
			])
		]);
	},

	render: function(st) {
		gw.injectStyles();
		var host = E('div');
		this.renderBody(host, st || {});
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', 'Ядро и сеть'),
			E('div', { 'class': 'cbi-map-descr' }, 'Управление движком маршрутизации, веб-панелью, DHCP-сервером AdGuard Home, Kill-Switch и сетевыми адресами.'),
			host
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
