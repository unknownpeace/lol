'use strict';
'require view';
'require dom';
'require tools.gateway as gw';

return view.extend({
	load: function() {
		return gw.api.status();
	},

	renderInspectResult: function(res) {
		if (!res)
			return E('p', { 'style': 'opacity: 0.75;' }, 'Введите домен или URL (например, youtube.com, openai.com или ya.ru) и нажмите «Проверить».');
		if (!res.ok)
			return E('div', { 'class': 'alert-message warning' }, res.error || 'Ошибка проверки домена');

		var vBadge = gw.badge('off', res.verdict || '—');
		if (res.verdict === 'proxy') vBadge = gw.badge('ok', 'В ПРОКСИ (FakeIP)');
		else if (res.verdict === 'direct') vBadge = gw.badge('info', 'НАПРЯМУЮ (DIRECT)');
		else if (res.verdict === 'blocked') vBadge = gw.badge('err', 'ЗАБЛОКИРОВАН AdGuard');
		else if (res.verdict === 'nxdomain') vBadge = gw.badge('warn', 'NXDOMAIN / таймаут');

		var listText = 'Правила ядра (.mrs / .srs)';
		if (res.list_source === 'proxy') listText = 'Принудительно В ПРОКСИ (пользовательский список)';
		else if (res.list_source === 'direct') listText = 'Принудительно НАПРЯМУЮ (пользовательский список)';

		function fmtTls(code, ms) {
			var msTxt = (ms != null && Number(ms) >= 0) ? (ms + ' мс') : 'недоступен/таймаут';
			return 'HTTP ' + (code || '000') + ' │ TLS: ' + msTxt;
		}

		return E('div', { 'class': 'gw-card', 'style': 'margin-top: 10px;' }, [
			E('div', { 'class': 'gw-card-main' }, [
				res.domain + ' ', vBadge
			]),
			E('div', { 'class': 'gw-card-sub' }, [
				'DNS (:53): ', E('strong', res.resolved_ip || 'нет ответа'), ' │ Список: ', listText, E('br'),
				'Через туннель: ', E('strong', fmtTls(res.proxy_http, res.proxy_ms)), E('br'),
				'Напрямую (LAN): ', E('strong', fmtTls(res.direct_http, res.direct_ms))
			])
		]);
	},

	renderBody: function(host, st) {
		var self = this;
		var px = st.proxies || {};
		var devices = Array.isArray(st.devices) ? st.devices : [];
		var nodes = Array.isArray(px.my_nodes) ? px.my_nodes : [];
		var proxyDoms = Array.isArray(px.proxy_domains) ? px.proxy_domains : [];
		var directDoms = Array.isArray(px.direct_domains) ? px.direct_domains : [];

		function reload() {
			return gw.api.status().then(function(fresh) {
				if (fresh && fresh.ok)
					self.renderBody(host, fresh);
			});
		}

		var subIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': px.sub_urls || '', 'placeholder': 'https://...' });
		var ruChk = E('input', { 'type': 'checkbox' });
		ruChk.checked = !!px.allow_ru;
		var uriIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'vless://..., hy2://..., trojan://...' });
		var warpIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'Опциональный ключ WARP+ (или пусто)' });
		var domInspectIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'например: openai.com или https://youtube.com' });
		var inspectBox = E('div', {}, this.renderInspectResult(null));
		var domRuleIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'example.com' });
		var manualIpIn = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': '192.168.1.50' });
		var manualModeSel = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'bypass' }, 'В обход (DIRECT)'),
			E('option', { 'value': 'force_proxy' }, 'Full-VPN (всё в прокси)'),
			E('option', { 'value': 'default' }, 'Сбросить (по правилам)')
		]);

		var nodeRows = nodes.map(function(n) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, String(n.index)),
				E('td', { 'class': 'td' }, gw.badge('info', n.proto || '')),
				E('td', { 'class': 'td' }, n.host || '—'),
				E('td', { 'class': 'td' }, n.tag || '—'),
				E('td', { 'class': 'td' }, E('button', {
					'class': 'btn cbi-button cbi-button-negative',
					'click': function() {
						gw.api.nodeDelete(n.index).then(function(r) {
							if (r && r.ok) {
								gw.runJobModal('Пересборка конфигурации', 'apply_core', '', '', reload);
							} else {
								gw.notify('danger', (r && r.error) || 'Ошибка удаления ключа');
							}
						});
					}
				}, 'Удалить'))
			]);
		});

		var nodesView = nodes.length
			? E('table', { 'class': 'table', 'style': 'margin-top: 8px;' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, '#'),
					E('th', { 'class': 'th' }, 'Протокол'),
					E('th', { 'class': 'th' }, 'Хост'),
					E('th', { 'class': 'th' }, 'Название'),
					E('th', { 'class': 'th' }, '')
				])
			].concat(nodeRows))
			: E('p', { 'style': 'opacity: 0.75; margin-top: 6px;' }, 'Личных URI-ключей пока нет.');

		function makeChips(items, listName) {
			if (!items.length)
				return E('p', { 'style': 'opacity: 0.75;' }, 'Список пуст.');
			return E('div', { 'class': 'gw-chip-list' }, items.map(function(d) {
				var locked = (listName === 'direct' && (d === '+.localdomain' || d === '+.lan'));
				var chipChildren = [ d ];
				if (!locked) {
					chipChildren.push(E('button', {
						'title': 'Удалить',
						'click': function() {
							gw.api.domainRule('del', listName, d).then(function(r) {
								if (r && r.ok) {
									gw.notify('info', 'Удалено: ' + r.domain + ' (применяется)');
									gw.runJobModal('Обновление правил доменов', 'apply_core', '', '', reload);
								} else {
									gw.notify('danger', (r && r.error) || 'Ошибка удаления');
								}
							});
						}
					}, '×'));
				}
				return E('span', { 'class': 'gw-chip' }, chipChildren);
			}));
		}

		var devRows = devices.map(function(dev) {
			var modeBadge = gw.badge('off', 'По правилам');
			if (dev.mode === 'bypass') modeBadge = gw.badge('warn', 'DIRECT (в обход)');
			else if (dev.mode === 'force_proxy') modeBadge = gw.badge('ok', 'Full-VPN');

			function modeBtn(label, targetMode, cls) {
				return E('button', {
					'class': 'btn cbi-button ' + cls,
					'disabled': dev.mode === targetMode ? true : null,
					'click': function() {
						gw.api.deviceRule(targetMode, dev.ip).then(function(r) {
							if (r && r.ok) {
								gw.runJobModal('Применение режима для ' + dev.ip, 'apply_core', '', '', reload);
							} else {
								gw.notify('danger', (r && r.error) || 'Ошибка');
							}
						});
					}
				}, label);
			}

			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, E('strong', dev.ip || '')),
				E('td', { 'class': 'td' }, dev.mac || '—'),
				E('td', { 'class': 'td' }, dev.hostname || 'Устройство LAN'),
				E('td', { 'class': 'td' }, modeBadge),
				E('td', { 'class': 'td' }, E('div', { 'style': 'display:flex;gap:4px;flex-wrap:wrap;' }, [
					modeBtn('По правилам', 'default', ''),
					modeBtn('В обход', 'bypass', 'cbi-button-neutral'),
					modeBtn('Full-VPN', 'force_proxy', 'cbi-button-positive')
				]))
			]);
		});

		dom.content(host, [
			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Слот 1: HTTP-подписки'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field', 'style': 'min-width: 340px;' }, [
						E('label', 'Ссылки подписок (через пробел или пусто для отключения)'),
						subIn
					]),
					E('label', { 'style': 'display:flex;align-items:center;gap:6px;padding-bottom:6px;' }, [
						ruChk, ' Показывать РФ/БС каскады'
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() {
							gw.api.setSubscription(subIn.value.trim(), ruChk.checked ? 'yes' : 'no').then(function(r) {
								if (r && r.ok) {
									gw.runJobModal('Применение подписки', 'apply_core', '', '', reload);
								} else {
									gw.notify('danger', (r && r.error) || 'Ошибка сохранения подписки');
								}
							});
						}
					}, 'Сохранить и применить')
				])
			]),

			E('div', { 'class': 'gw-two-col' }, [
				E('div', { 'class': 'cbi-section' }, [
					E('h3', 'Слот 2: Личные ключи URI'),
					E('div', { 'class': 'gw-form-row' }, [
						E('div', { 'class': 'gw-field' }, [
							E('label', 'Добавить URI-ключ'),
							uriIn
						]),
						E('button', {
							'class': 'btn cbi-button cbi-button-positive',
							'click': function() {
								gw.api.nodeAdd(uriIn.value.trim()).then(function(r) {
									if (r && r.ok) {
										gw.runJobModal('Добавление ключа URI', 'apply_core', '', '', reload);
									} else {
										gw.notify('danger', (r && r.error) || 'Некорректный URI');
									}
								});
							}
						}, 'Добавить')
					]),
					nodesView
				]),

				E('div', { 'class': 'cbi-section' }, [
					E('h3', 'Слот 3: Бесплатный Amnezia WARP 2.0'),
					E('p', {}, [
						'Состояние: ',
						gw.badge(px.warp_enabled ? 'ok' : 'off', px.warp_enabled ? 'АКТИВЕН' : 'ВЫКЛЮЧЕН'),
						px.warp_license_set ? ' (ключ WARP+ указан)' : ''
					]),
					E('div', { 'class': 'gw-form-row' }, [
						E('div', { 'class': 'gw-field' }, [
							E('label', 'Ключ WARP+ (необязательно)'),
							warpIn
						])
					]),
					E('div', { 'class': 'gw-toolbar' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-apply',
							'click': function() {
								gw.runJobModal('Генерация пула Amnezia WARP', 'warp_generate', warpIn.value.trim(), '', reload);
							}
						}, px.warp_enabled ? 'Перегенерировать WARP' : 'Включить WARP 2.0'),
						px.warp_enabled ? E('button', {
							'class': 'btn cbi-button cbi-button-negative',
							'click': function() {
								gw.runJobModal('Отключение WARP 2.0', 'warp_disable', '', '', reload);
							}
						}, 'Отключить WARP') : ''
					].filter(Boolean))
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Рентген маршрута домена (DNS + TLS)'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Домен или URL'),
						domInspectIn
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function(ev) {
							var btn = ev.currentTarget;
							var dVal = domInspectIn.value.trim();
							if (!dVal) return;
							btn.disabled = true;
							dom.content(inspectBox, E('p', { 'class': 'spinning' }, 'Проверяю DNS и HTTPS...'));
							gw.api.domainInspect(dVal).then(function(r) {
								dom.content(inspectBox, self.renderInspectResult(r));
							}).finally(function() { btn.disabled = false; });
						}
					}, 'Проверить маршрут')
				]),
				inspectBox
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Пользовательские домены (В прокси / Напрямую)'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Домен для добавления в список'),
						domRuleIn
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-positive',
						'click': function() {
							gw.api.domainRule('add', 'proxy', domRuleIn.value.trim()).then(function(r) {
								if (r && r.ok) {
									gw.runJobModal('Перенос домена В ПРОКСИ', 'apply_core', '', '', reload);
								} else {
									gw.notify('danger', (r && r.error) || 'Ошибка');
								}
							});
						}
					}, 'В прокси'),
					E('button', {
						'class': 'btn cbi-button cbi-button-neutral',
						'click': function() {
							gw.api.domainRule('add', 'direct', domRuleIn.value.trim()).then(function(r) {
								if (r && r.ok) {
									gw.runJobModal('Перенос домена НАПРЯМУЮ', 'apply_core', '', '', reload);
								} else {
									gw.notify('danger', (r && r.error) || 'Ошибка');
								}
							});
						}
					}, 'Напрямую (DIRECT)')
				]),
				E('div', { 'class': 'gw-two-col' }, [
					E('div', { 'class': 'gw-card' }, [
						E('div', { 'class': 'gw-card-title' }, 'Всегда В ПРОКСИ (' + proxyDoms.length + ')'),
						makeChips(proxyDoms, 'proxy')
					]),
					E('div', { 'class': 'gw-card' }, [
						E('div', { 'class': 'gw-card-title' }, 'Всегда НАПРЯМУЮ (' + directDoms.length + ')'),
						makeChips(directDoms, 'direct')
					])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Устройства в сети LAN (обход или Full-VPN по IP)'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Задать правило вручную по IPv4'),
						manualIpIn
					]),
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Режим'),
						manualModeSel
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() {
							gw.api.deviceRule(manualModeSel.value, manualIpIn.value.trim()).then(function(r) {
								if (r && r.ok) {
									gw.runJobModal('Обновление правил устройств', 'apply_core', '', '', reload);
								} else {
									gw.notify('danger', (r && r.error) || 'Некорректный IPv4');
								}
							});
						}
					}, 'Применить')
				]),
				devices.length
					? E('table', { 'class': 'table' }, [
						E('tr', { 'class': 'tr table-titles' }, [
							E('th', { 'class': 'th' }, 'IP'),
							E('th', { 'class': 'th' }, 'MAC'),
							E('th', { 'class': 'th' }, 'Имя'),
							E('th', { 'class': 'th' }, 'Режим'),
							E('th', { 'class': 'th' }, 'Действие')
						])
					].concat(devRows))
					: E('p', { 'style': 'opacity: 0.75;' }, 'Активные устройства в ARP/DHCP пока не обнаружены.')
			])
		]);
	},

	render: function(st) {
		gw.injectStyles();
		var host = E('div');
		this.renderBody(host, st || {});
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', 'Прокси и маршруты'),
			E('div', { 'class': 'cbi-map-descr' }, 'Управление подписками, личными ключами URI, WARP 2.0, проверкой и списками доменов и устройствами LAN.'),
			host
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
