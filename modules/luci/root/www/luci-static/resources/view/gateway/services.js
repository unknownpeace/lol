'use strict';
'require view';
'require dom';
'require tools.gateway as gw';

return view.extend({
	load: function() {
		return gw.api.status();
	},

	renderBody: function(host, st) {
		var self = this;
		var tg = st.telegram || {};
		var bak = st.backup || {};
		var cron = st.cron || {};

		function reload() {
			return gw.api.status().then(function(fresh) {
				if (fresh && fresh.ok)
					self.renderBody(host, fresh);
			});
		}

		var tokIn = E('input', {
			'type': 'password',
			'class': 'cbi-input-text',
			'placeholder': tg.configured ? ('Сохранён: ' + (tg.token_masked || '****') + ' (оставьте пустым, чтобы не менять)') : '123456:ABC...'
		});
		var cidIn = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'value': tg.chat_id || '',
			'placeholder': 'Ваш Chat ID (из @userinfobot)'
		});

		var pass1In = E('input', { 'type': 'password', 'class': 'cbi-input-text', 'placeholder': 'Новый пароль (от 4 символов)' });
		var pass2In = E('input', { 'type': 'password', 'class': 'cbi-input-text', 'placeholder': 'Повторите пароль' });

		dom.content(host, [
			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Telegram-бот (уведомления и облачные бэкапы)'),
				E('p', {}, [
					'Статус: ',
					gw.badge(tg.configured ? 'ok' : 'off', tg.configured ? ('ПОДКЛЮЧЁН (Chat ID: ' + tg.chat_id + ')') : 'НЕ НАСТРОЕН')
				]),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'API Token бота (@BotFather)'),
						tokIn
					]),
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Chat ID'),
						cidIn
					])
				]),
				E('div', { 'class': 'gw-toolbar' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function(ev) {
							var btn = ev.currentTarget;
							btn.disabled = true;
							gw.api.setTelegram('save', tokIn.value.trim(), cidIn.value.trim()).then(function(r) {
								if (r && r.ok) {
									gw.notify(r.sent ? 'info' : 'warning', r.sent ? r.message : (r.message + ': ' + (r.error || '')));
									reload();
								} else {
									gw.notify('danger', (r && r.error) || 'Ошибка сохранения Telegram');
								}
							}).finally(function() { btn.disabled = false; });
						}
					}, 'Сохранить и проверить'),
					tg.configured ? E('button', {
						'class': 'btn cbi-button',
						'click': function(ev) {
							var btn = ev.currentTarget;
							btn.disabled = true;
							gw.api.setTelegram('test', '', '').then(function(r) {
								if (r && r.ok) gw.notify('info', r.message || 'Тест доставлен');
								else gw.notify('danger', (r && r.error) || 'Ошибка доставки');
							}).finally(function() { btn.disabled = false; });
						}
					}, 'Отправить тест') : '',
					tg.configured ? E('button', {
						'class': 'btn cbi-button cbi-button-negative',
						'click': function() {
							gw.api.setTelegram('disable', '', '').then(function(r) {
								if (r && r.ok) {
									gw.notify('info', r.message || 'Отключено');
									reload();
								}
							});
						}
					}, 'Отключить бота') : ''
				].filter(Boolean))
			]),

			E('div', { 'class': 'gw-two-col' }, [
				E('div', { 'class': 'cbi-section' }, [
					E('h3', 'Резервное копирование'),
					E('p', {}, [
						'Архив /root/gateway_backup.tar.gz: ',
						gw.badge(bak.exists ? 'ok' : 'off', bak.exists ? ('Есть (' + (bak.size || '?') + ')') : 'Не создан'),
						bak.mtime ? (' от ' + bak.mtime) : ''
					]),
					E('div', { 'class': 'gw-toolbar' }, [
						E('button', {
							'class': 'btn cbi-button cbi-button-apply',
							'click': function() {
								gw.runJobModal('Создание резервной копии', 'backup_create', '', '', reload);
							}
						}, 'Создать бэкап'),
						E('button', {
							'class': 'btn cbi-button cbi-button-positive',
							'disabled': tg.configured ? null : true,
							'click': function() {
								gw.runJobModal('Создание и отправка бэкапа в Telegram', 'backup_telegram', '', '', reload);
							}
						}, 'Создать и отправить в Telegram'),
						bak.exists ? E('button', {
							'class': 'btn cbi-button cbi-button-negative',
							'click': function() {
								if (!window.confirm('Восстановить конфигурацию шлюза, AdGuard Home и OpenWrt из /root/gateway_backup.tar.gz?'))
									return;
								gw.runJobModal('Восстановление из резервной копии', 'backup_restore', '', '', reload);
							}
						}, 'Восстановить из архива') : ''
					].filter(Boolean))
				]),

				E('div', { 'class': 'cbi-section' }, [
					E('h3', 'Автономность (Cron)'),
					E('div', { 'class': 'gw-card', 'style': 'margin-bottom: 10px;' }, [
						E('div', { 'class': 'gw-card-main' }, [
							'Watchdog (каждые 5 мин) ',
							gw.badge(cron.watchdog ? 'ok' : 'off', cron.watchdog ? 'ВКЛ' : 'ВЫКЛ')
						]),
						E('div', { 'class': 'gw-card-sub' }, 'Контролирует здоровье служб, Conntrack и маршрут по умолчанию.'),
						E('div', { 'class': 'gw-toolbar', 'style': 'margin-top: 8px; margin-bottom: 0;' }, [
							E('button', {
								'class': 'btn cbi-button ' + (cron.watchdog ? 'cbi-button-neutral' : 'cbi-button-positive'),
								'click': function() {
									gw.api.setCron('watchdog', cron.watchdog ? 'no' : 'yes').then(function(r) {
										if (r && r.ok) reload();
									});
								}
							}, cron.watchdog ? 'Выключить Watchdog' : 'Включить Watchdog')
						])
					]),
					E('div', { 'class': 'gw-card' }, [
						E('div', { 'class': 'gw-card-main' }, [
							'Автообновление ядер в 04:00 ',
							gw.badge(cron.autoupdate ? 'ok' : 'off', cron.autoupdate ? 'ВКЛ' : 'ВЫКЛ')
						]),
						E('div', { 'class': 'gw-card-sub' }, 'Ежедневно проверяет свежие релизы ядра, AdGuard Home и панели UI.'),
						E('div', { 'class': 'gw-toolbar', 'style': 'margin-top: 8px; margin-bottom: 0;' }, [
							E('button', {
								'class': 'btn cbi-button ' + (cron.autoupdate ? 'cbi-button-neutral' : 'cbi-button-positive'),
								'click': function() {
									gw.api.setCron('autoupdate', cron.autoupdate ? 'no' : 'yes').then(function(r) {
										if (r && r.ok) reload();
									});
								}
							}, cron.autoupdate ? 'Выключить автообновление' : 'Включить автообновление')
						])
					])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Смена единого мастер-пароля (AdGuard Home и Clash API :9090)'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Новый пароль'),
						pass1In
					]),
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Подтверждение'),
						pass2In
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-negative',
						'click': function(ev) {
							var p1 = pass1In.value;
							var p2 = pass2In.value;
							if (!p1 || p1.length < 4) {
								gw.notify('warning', 'Пароль должен быть не короче 4 символов');
								return;
							}
							if (p1 !== p2) {
								gw.notify('warning', 'Пароли не совпадают');
								return;
							}
							var btn = ev.currentTarget;
							btn.disabled = true;
							gw.api.setPassword(p1).then(function(r) {
								if (r && r.ok) {
									pass1In.value = '';
									pass2In.value = '';
									gw.notify('info', r.message || 'Пароль обновлён');
								} else {
									gw.notify('danger', (r && r.error) || 'Ошибка смены пароля');
								}
							}).finally(function() { btn.disabled = false; });
						}
					}, 'Сменить пароль')
				])
			])
		]);
	},

	render: function(st) {
		gw.injectStyles();
		var host = E('div');
		this.renderBody(host, st || {});
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', 'Telegram, бэкапы и автономность'),
			E('div', { 'class': 'cbi-map-descr' }, 'Управление ботом Telegram, резервным копированием, фоновыми задачами Cron и единым паролем.'),
			host
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
