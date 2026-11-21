'use strict';
'require view';
'require ui';
'require dom';
'require poll';
'require tools.gateway as gw';

return view.extend({
	load: function() {
		return gw.api.status();
	},

	renderCards: function(st) {
		var sys = st.system || {};
		var core = st.core || {};
		var net = st.network || {};
		var agh = st.adguard || {};
		var cron = st.cron || {};
		var tg = st.telegram || {};
		var git = st.git || {};
		var px = st.proxies || {};

		var leasesCount = Array.isArray(agh.dhcp_leases) ? agh.dhcp_leases.length : 0;
		var subLabel = (px.sub_count > 0) ? ('Слот 1: ' + px.sub_count + ' подп.') : 'Слот 1: выкл';
		var nodeCount = Array.isArray(px.my_nodes) ? px.my_nodes.length : 0;

		return [
			E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-title' }, 'Ядро маршрутизации'),
				E('div', { 'class': 'gw-card-main' }, [
					core.name || core.engine || '—',
					' ',
					gw.badge(core.running ? 'ok' : 'err', core.running ? 'АКТИВНО' : 'СТОП')
				]),
				E('div', { 'class': 'gw-card-sub' }, [
					'Версия: ' + (core.version || '—') + ' │ PID ' + (core.pid || '—') + ' │ ОЗУ: ' + (core.rss || '—'),
					E('br'),
					'Интерфейс TUN: ',
					gw.badge(core.tun_up ? 'ok' : 'err', (core.tun_if || 'gateway-tun') + (core.tun_up ? ' UP' : ' DOWN'))
				])
			]),

			E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-title' }, 'AdGuard Home и DHCP'),
				E('div', { 'class': 'gw-card-main' }, [
					'DNS :53 ',
					gw.badge(agh.running ? 'ok' : 'err', agh.running ? 'АКТИВЕН' : 'СТОП'),
					' ',
					gw.badge(agh.dhcp_enabled ? 'ok' : 'off', agh.dhcp_enabled ? 'DHCP ВКЛ' : 'Sidecar')
				]),
				E('div', { 'class': 'gw-card-sub' }, [
					'Версия: ' + (agh.version || '—') + ' │ ОЗУ: ' + (agh.rss || '—') + ' │ Фильтр: ' + (agh.protection_enabled ? 'вкл' : 'выкл'),
					E('br'),
					'Аренд DHCP: ' + leasesCount + (agh.dhcp_v4 && agh.dhcp_v4.range_start ? (' (' + agh.dhcp_v4.range_start + '–' + agh.dhcp_v4.range_end.split('.').pop() + ')') : '')
				])
			]),

			E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-title' }, 'Веб-панель и прокси'),
				E('div', { 'class': 'gw-card-main' }, [
					core.ui_name || core.ui || '—',
					' ',
					gw.badge('info', core.ui_ver || 'UI')
				]),
				E('div', { 'class': 'gw-card-sub' }, [
					subLabel + ' │ Ключи: ' + nodeCount + ' │ WARP: ' + (px.warp_enabled ? 'вкл' : 'выкл'),
					E('br'),
					'LAN: ' + (net.lan_ip || '—') + ' (' + (net.lan_if || 'br-lan') + ') → Роутер: ' + (net.gw_ip || '—')
				])
			]),

			E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-title' }, 'Система и защита'),
				E('div', { 'class': 'gw-card-main' }, [
					sys.model || sys.os_name || 'OpenWrt',
					' ',
					gw.badge(net.killswitch ? 'warn' : 'ok', net.killswitch ? 'Kill-Switch ВКЛ' : 'Firewall Guard')
				]),
				E('div', { 'class': 'gw-card-sub' }, [
					'ОЗУ: ' + (sys.ram_used_mb || 0) + '/' + (sys.ram_total_mb || 0) + ' МБ (' + (sys.ram_pct || 0) + '%) │ Conntrack: ' + (sys.conntrack_used || 0) + '/' + (sys.conntrack_max || 0),
					E('br'),
					'Uptime: ' + gw.formatUptime(sys.uptime_sec) + ' │ Watchdog: ' + (cron.watchdog ? 'вкл' : 'выкл') + ' │ TG: ' + (tg.configured ? 'вкл' : 'выкл') + ' │ Git: ' + (git.sha || '—')
				])
			])
		];
	},

	renderGroupsTable: function(st) {
		var groups = (st.proxies && Array.isArray(st.proxies.groups)) ? st.proxies.groups : [];
		if (!groups.length) {
			return E('p', { 'style': 'opacity: 0.75;' }, 'Прокси-группы пока не загружены или Clash API :9090 не отвечает.');
		}
		var rows = groups.map(function(g) {
			var isBad = (g.now || '').indexOf('Нет рабочих нод') !== -1;
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, E('strong', g.name || '')),
				E('td', { 'class': 'td' }, gw.badge(g.type === 'URLTest' ? 'info' : 'off', g.type || '—')),
				E('td', { 'class': 'td' }, gw.badge(isBad ? 'err' : (g.now === 'DIRECT' ? 'off' : 'ok'), g.now || '—')),
				E('td', { 'class': 'td' }, String(g.count || 0))
			]);
		});
		return E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, 'Группа'),
				E('th', { 'class': 'th' }, 'Тип'),
				E('th', { 'class': 'th' }, 'Активный маршрут / нода'),
				E('th', { 'class': 'th' }, 'Узлов')
			])
		].concat(rows));
	},

	renderTraceBox: function(tr) {
		if (!tr) {
			return E('p', { 'style': 'opacity: 0.75;' }, 'Нажмите «Проверить Trace и Ping» для живого замера DNS, внешнего IP и задержек.');
		}
		var t = tr.trace || {};
		var d = tr.dns || {};
		var l = tr.latency_ms || {};
		function fmtMs(v) { return (v != null && Number(v) >= 0) ? (String(v) + ' мс') : 'таймаут'; }
		return E('div', { 'class': 'gw-grid' }, [
			E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-title' }, 'Внешний выход (Cloudflare Trace)'),
				E('div', { 'class': 'gw-card-main' }, t.ip ? (t.ip + ' (' + (t.loc || '?') + ' / ' + (t.colo || '?') + ')') : gw.badge('err', 'Нет ответа')),
				E('div', { 'class': 'gw-card-sub' }, 'WARP: ' + (t.warp || 'off'))
			]),
			E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-title' }, 'Anti-Leak DNS (:53)'),
				E('div', { 'class': 'gw-card-sub' }, [
					'chatgpt.com: ', E('strong', d.chatgpt || 'n/a'), E('br'),
					'ya.ru: ', E('strong', d.yaru || 'n/a'), E('br'),
					'DDR / DoH Block: ', gw.badge(d.ddr_block ? 'ok' : 'err', d.ddr_block ? 'OK' : 'FAIL')
				])
			]),
			E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-title' }, 'Задержка до сервисов'),
				E('div', { 'class': 'gw-card-sub' }, [
					'Напрямую РФ (ya.ru): ', E('strong', fmtMs(l.ru)), E('br'),
					'Cloudflare Anycast: ', E('strong', fmtMs(l.cf)), E('br'),
					'YouTube: ', E('strong', fmtMs(l.yt)), ' │ OpenAI TLS: ', E('strong', fmtMs(l.ai))
				])
			])
		]);
	},

	refreshAll: function(cardsHost, groupsHost, onComplete) {
		return gw.api.status().then(L.bind(function(st) {
			if (st && st.ok) {
				dom.content(cardsHost, this.renderCards(st));
				dom.content(groupsHost, this.renderGroupsTable(st));
			}
			if (typeof onComplete === 'function')
				onComplete(st);
		}, this)).catch(function() {});
	},

	render: function(st) {
		gw.injectStyles();
		var cardsHost = E('div', { 'class': 'gw-grid' }, this.renderCards(st || {}));
		var traceHost = E('div', {}, this.renderTraceBox(null));
		var groupsHost = E('div', {}, this.renderGroupsTable(st || {}));
		var self = this;

		if (st && st.active_job_id) {
			gw.openJobModal('Активная фоновая операция', st.active_job_id, function() {
				self.refreshAll(cardsHost, groupsHost);
			});
		}

		var traceBtn = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': function(ev) {
				var btn = ev.currentTarget;
				btn.disabled = true;
				dom.content(traceHost, E('p', { 'class': 'spinning' }, 'Выполняется замер DNS, Trace и задержек...'));
				gw.api.trace().then(function(res) {
					dom.content(traceHost, self.renderTraceBox(res));
				}).catch(function(err) {
					gw.notify('danger', err && err.message ? err.message : String(err));
				}).finally(function() {
					btn.disabled = false;
				});
			}
		}, 'Проверить Trace и Ping');

		var toolbar = E('div', { 'class': 'gw-toolbar' }, [
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': function() {
					gw.runJobModal('Перезапуск шлюза', 'restart', '', '', function() {
						self.refreshAll(cardsHost, groupsHost);
					});
				}
			}, 'Применить и перезапустить'),
			E('button', {
				'class': 'btn cbi-button',
				'click': function() {
					gw.runJobModal('Авто-доктор шлюза (Doctor 2.0)', 'doctor', '', '', function() {
						self.refreshAll(cardsHost, groupsHost);
					});
				}
			}, 'Авто-доктор (Doctor)'),
			traceBtn,
			E('a', {
				'class': 'btn cbi-button',
				'href': gw.hostUrl(9090, '/ui/'),
				'target': '_blank',
				'rel': 'noopener'
			}, 'Открыть ' + ((st && st.core && st.core.ui_name) || 'Панель UI') + ' (:9090)'),
			E('a', {
				'class': 'btn cbi-button',
				'href': gw.hostUrl(3000, '/'),
				'target': '_blank',
				'rel': 'noopener'
			}, 'Открыть AdGuard Home (:3000)')
		]);

		poll.add(function() {
			return self.refreshAll(cardsHost, groupsHost);
		}, 5);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', 'Universal Sidecar Gateway'),
			E('div', { 'class': 'cbi-map-descr' }, 'Сводное состояние ядра маршрутизации, AdGuard Home DHCP, прокси-групп и защиты от утечек.'),
			toolbar,
			cardsHost,
			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Диагностика канала и Anti-Leak DNS'),
				traceHost
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Активные маршруты прокси-групп'),
				groupsHost
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
