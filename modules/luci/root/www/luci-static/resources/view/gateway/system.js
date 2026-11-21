'use strict';
'require view';
'require dom';
'require tools.gateway as gw';

return view.extend({
	load: function() {
		return Promise.all([
			gw.api.status(),
			gw.api.getLogs('core', 100)
		]);
	},

	renderUpdateBox: function(upd) {
		if (!upd)
			return E('p', { 'style': 'opacity: 0.75;' }, 'Нажмите «Проверить обновления в Git», чтобы сравнить установленный код с origin/main.');
		if (upd.status === 'NO_GIT')
			return E('div', { 'class': 'alert-message warning' }, 'Режим Standalone: в /opt/gateway нет каталога .git.');
		if (upd.status === 'FETCH_ERROR')
			return E('div', { 'class': 'alert-message warning' }, 'Не удалось связаться с удалённым Git-репозиторием (' + (upd.branch || 'main') + ').');
		if (upd.status === 'UPDATE_AVAILABLE') {
			var list = Array.isArray(upd.commits) ? upd.commits.map(function(c) { return E('li', c); }) : [];
			return E('div', { 'class': 'gw-card' }, [
				E('div', { 'class': 'gw-card-main' }, [
					gw.badge('warn', 'Доступно коммитов: ' + (upd.behind || 1)),
					' (текущий: ' + (upd.current_sha || '—') + ')'
				]),
				list.length ? E('ul', { 'style': 'margin: 6px 0 0 18px;' }, list) : ''
			].filter(Boolean));
		}
		return E('div', { 'class': 'alert-message notice' }, 'Установлена последняя версия Gateway (' + (upd.current_sha || 'HEAD') + '), обновлений нет.');
	},

	render: function(results) {
		gw.injectStyles();
		var st = (results && results[0]) ? results[0] : {};
		var initialLog = (results && results[1] && results[1].log) ? results[1].log : '';
		var git = st.git || {};
		var self = this;

		var verBadge = E('span', {}, [
			'Ветка: ', E('strong', git.branch || 'main'),
			' │ Ревизия: ', gw.badge(git.is_repo ? 'ok' : 'off', git.sha || 'Standalone')
		]);
		var updBox = E('div', { 'style': 'margin-top: 8px;' }, this.renderUpdateBox(null));

		var srcSel = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'core' }, 'Лог активного ядра (' + ((st.core && st.core.name) || 'core') + ')'),
			E('option', { 'value': 'check' }, 'Неинвазивный аудит (gw check)'),
			E('option', { 'value': 'autoupdate' }, 'Лог ночного автообновления (04:00)')
		]);
		var linesSel = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': '100' }, '100 строк'),
			E('option', { 'value': '250' }, '250 строк')
		]);
		var logPre = E('pre', { 'class': 'gw-pre' }, initialLog || '(пусто)');

		function loadLogNow() {
			logPre.textContent = 'Загрузка...';
			return gw.api.getLogs(srcSel.value, Number(linesSel.value || 100)).then(function(r) {
				logPre.textContent = (r && r.ok) ? (r.log || '(пусто)') : ((r && r.error) || 'Ошибка чтения лога');
			});
		}

		srcSel.addEventListener('change', loadLogNow);
		linesSel.addEventListener('change', loadLogNow);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', 'Обновление и логи'),
			E('div', { 'class': 'cbi-map-descr' }, 'Проверка обновлений проекта на GitHub, запуск gw update с живым выводом и просмотр журналов.'),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Обновление системы (gw update)'),
				E('p', {}, verBadge),
				E('div', { 'class': 'gw-toolbar' }, [
					E('button', {
						'class': 'btn cbi-button',
						'click': function(ev) {
							var btn = ev.currentTarget;
							btn.disabled = true;
							dom.content(updBox, E('p', { 'class': 'spinning' }, 'Связь с GitHub...'));
							gw.api.updateCheck().then(function(r) {
								dom.content(updBox, self.renderUpdateBox(r));
							}).finally(function() { btn.disabled = false; });
						}
					}, 'Проверить обновления в Git'),
					E('button', {
						'class': 'btn cbi-button cbi-button-apply',
						'click': function() {
							gw.runJobModal('Полное обновление шлюза (gw update)', 'update', '', '', function() {
								gw.api.status().then(function(fresh) {
									if (fresh && fresh.git) {
										dom.content(verBadge, [
											'Ветка: ', E('strong', fresh.git.branch || 'main'),
											' │ Ревизия: ', gw.badge(fresh.git.is_repo ? 'ok' : 'off', fresh.git.sha || 'Standalone')
										]);
									}
									gw.api.updateCheck().then(function(u) {
										dom.content(updBox, self.renderUpdateBox(u));
									});
								});
							});
						}
					}, 'Обновить сейчас (gw update)')
				]),
				updBox
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', 'Журнал работы и диагностика'),
				E('div', { 'class': 'gw-form-row' }, [
					E('div', { 'class': 'gw-field' }, [
						E('label', 'Источник'),
						srcSel
					]),
					E('div', { 'class': 'gw-field', 'style': 'max-width: 150px;' }, [
						E('label', 'Глубина'),
						linesSel
					]),
					E('button', {
						'class': 'btn cbi-button',
						'click': loadLogNow
					}, 'Обновить лог')
				]),
				logPre
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
