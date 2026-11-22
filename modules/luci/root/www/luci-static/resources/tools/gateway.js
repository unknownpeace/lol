'use strict';
'require baseclass';
'require rpc';
'require ui';
'require dom';

var callStatus = rpc.declare({ object: 'gateway', method: 'status', expect: {} });
var callTrace = rpc.declare({ object: 'gateway', method: 'trace', expect: {} });
var callDomainInspect = rpc.declare({ object: 'gateway', method: 'domain_inspect', params: ['domain'], expect: {} });
var callSetDhcp = rpc.declare({ object: 'gateway', method: 'set_dhcp', params: ['mode'], expect: {} });
var callSetKillswitch = rpc.declare({ object: 'gateway', method: 'set_killswitch', params: ['mode'], expect: {} });
var callSetCron = rpc.declare({ object: 'gateway', method: 'set_cron', params: ['target', 'enabled'], expect: {} });
var callSetNetwork = rpc.declare({ object: 'gateway', method: 'set_network', params: ['lan_ip', 'gw_ip'], expect: {} });
var callSetSubscription = rpc.declare({ object: 'gateway', method: 'set_subscription', params: ['urls', 'allow_ru'], expect: {} });
var callNodeAdd = rpc.declare({ object: 'gateway', method: 'node_add', params: ['uri'], expect: {} });
var callNodeDelete = rpc.declare({ object: 'gateway', method: 'node_delete', params: ['index'], expect: {} });
var callDomainRule = rpc.declare({ object: 'gateway', method: 'domain_rule', params: ['action', 'list', 'domain'], expect: {} });
var callDeviceRule = rpc.declare({ object: 'gateway', method: 'device_rule', params: ['mode', 'ip'], expect: {} });
var callSetTelegram = rpc.declare({ object: 'gateway', method: 'set_telegram', params: ['action', 'token', 'chat_id'], expect: {} });
var callSetPassword = rpc.declare({ object: 'gateway', method: 'set_password', params: ['password'], expect: {} });
var callUpdateCheck = rpc.declare({ object: 'gateway', method: 'update_check', expect: {} });
var callGetLogs = rpc.declare({ object: 'gateway', method: 'get_logs', params: ['target', 'lines'], expect: {} });
var callJobStart = rpc.declare({ object: 'gateway', method: 'job_start', params: ['action', 'arg1', 'arg2'], expect: {} });
var callJobPoll = rpc.declare({ object: 'gateway', method: 'job_poll', params: ['id'], expect: {} });

function injectStyles() {
	if (document.getElementById('gw-luci-styles'))
		return;
	var css = [
		'.gw-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 12px; margin: 12px 0 16px; }',
		'.gw-card { border: 1px solid var(--border-color-medium, #d9d9d9); border-radius: 6px; padding: 12px 14px; background: var(--background-color-high, #fff); }',
		'.gw-card-title { font-size: 12px; text-transform: uppercase; letter-spacing: 0.4px; opacity: 0.72; margin-bottom: 6px; }',
		'.gw-card-main { font-size: 16px; font-weight: 600; margin-bottom: 4px; }',
		'.gw-card-sub { font-size: 12px; opacity: 0.8; line-height: 1.45; }',
		'.gw-badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600; line-height: 1.4; }',
		'.gw-badge-ok { background: #1e8e3e; color: #fff; }',
		'.gw-badge-err { background: #c5221f; color: #fff; }',
		'.gw-badge-warn { background: #b06000; color: #fff; }',
		'.gw-badge-info { background: #1a73e8; color: #fff; }',
		'.gw-badge-off { background: var(--background-color-low, #e0e0e0); color: var(--text-color-high, #333); }',
		'.gw-toolbar { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin: 8px 0 14px; }',
		'.gw-form-row { display: flex; flex-wrap: wrap; gap: 10px; align-items: flex-end; margin-bottom: 10px; }',
		'.gw-field { display: flex; flex-direction: column; gap: 4px; min-width: 240px; flex: 1; }',
		'.gw-field label { font-size: 12px; font-weight: 600; opacity: 0.85; }',
		'.gw-field input[type="text"], .gw-field input[type="password"], .gw-field select, .gw-field textarea, .gw-field .cbi-input-text, .gw-field .cbi-input-select, .gw-field .cbi-input-textarea { width: 100% !important; max-width: 100% !important; box-sizing: border-box; }',
		'.gw-pre { background: #161b22; color: #e6edf3; padding: 12px; border-radius: 6px; font-family: monospace; font-size: 12px; line-height: 1.45; max-height: 360px; overflow: auto; white-space: pre-wrap; word-break: break-word; }',
		'.gw-two-col { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(320px, 100%), 1fr)); gap: 16px; }',
		'.gw-chip-list { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }',
		'.gw-chip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 8px; border-radius: 4px; border: 1px solid var(--border-color-medium, #d9d9d9); background: var(--background-color-low, #f6f6f6); font-size: 12px; }',
		'.gw-chip button { border: none; background: transparent; cursor: pointer; font-weight: 700; padding: 0 2px; color: #c5221f; }'
	].join('\n');
	var st = document.createElement('style');
	st.id = 'gw-luci-styles';
	st.textContent = css;
	document.head.appendChild(st);
}

function badge(kind, text) {
	return E('span', { 'class': 'gw-badge gw-badge-' + (kind || 'off') }, String(text || ''));
}

function notify(kind, msg) {
	ui.addTimeLimitedNotification(null, E('p', String(msg || '')), 5000, kind || 'info');
}

function formatUptime(sec) {
	sec = Number(sec || 0);
	var d = Math.floor(sec / 86400);
	var h = Math.floor((sec % 86400) / 3600);
	var m = Math.floor((sec % 3600) / 60);
	var parts = [];
	if (d > 0) parts.push(d + 'д');
	if (h > 0 || d > 0) parts.push(h + 'ч');
	parts.push(m + 'м');
	return parts.join(' ');
}

function hostUrl(port, path) {
	var proto = 'http:';
	var host = window.location.hostname || '192.168.1.1';
	return proto + '//' + host + ':' + String(port) + (path || '');
}

var activeJobStop = null;

function stopActiveJobStream() {
	if (typeof activeJobStop === 'function') {
		var fn = activeJobStop;
		activeJobStop = null;
		fn();
	}
}

function attachJobStream(jobId, preEl, statusEl, closeBtn, onDone) {
	var timer = null;
	var stopped = false;

	function cleanup() {
		stopped = true;
		if (timer !== null) {
			window.clearTimeout(timer);
			timer = null;
		}
		window.removeEventListener('hashchange', cleanup);
		window.removeEventListener('popstate', cleanup);
		window.removeEventListener('pagehide', cleanup);
	}

	window.addEventListener('hashchange', cleanup);
	window.addEventListener('popstate', cleanup);
	window.addEventListener('pagehide', cleanup);

	function step() {
		if (stopped || !statusEl.isConnected) {
			cleanup();
			return;
		}
		callJobPoll(jobId).then(function(res) {
			if (stopped || !statusEl.isConnected) {
				cleanup();
				return;
			}
			if (!res || !res.ok) {
				statusEl.textContent = (res && res.error) ? ('Ошибка: ' + res.error) : 'Не удалось получить статус задания';
				closeBtn.disabled = false;
				cleanup();
				return;
			}
			if (res.log != null) {
				preEl.textContent = res.log || 'Ожидание вывода...';
				preEl.scrollTop = preEl.scrollHeight;
			}
			if (res.running) {
				timer = window.setTimeout(step, 1000);
			} else {
				var ok = (Number(res.exit_code) === 0);
				dom.content(statusEl, [
					badge(ok ? 'ok' : 'err', ok ? 'Завершено успешно (код 0)' : ('Ошибка выполнения (код ' + res.exit_code + ')'))
				]);
				closeBtn.disabled = false;
				cleanup();
				if (typeof onDone === 'function')
					onDone(res);
			}
		}).catch(function(err) {
			if (stopped || !statusEl.isConnected) {
				cleanup();
				return;
			}
			statusEl.textContent = 'Ошибка опроса: ' + (err && err.message ? err.message : String(err));
			closeBtn.disabled = false;
			cleanup();
		});
	}
	step();
	return cleanup;
}

function openJobModal(title, jobId, onDone) {
	stopActiveJobStream();
	var statusEl = E('div', { 'style': 'margin-bottom: 10px;' }, [ badge('info', 'Выполняется в фоне...') ]);
	var preEl = E('pre', { 'class': 'gw-pre' }, 'Запуск операции...');
	var closeBtn = E('button', {
		'class': 'btn cbi-button',
		'disabled': true,
		'click': function() {
			stopActiveJobStream();
			ui.hideModal();
		}
	}, 'Закрыть');

	ui.showModal(title, [
		statusEl,
		preEl,
		E('div', { 'class': 'right', 'style': 'margin-top: 12px;' }, [ closeBtn ])
	]);

	activeJobStop = attachJobStream(jobId, preEl, statusEl, closeBtn, onDone);
}

function runJobModal(title, action, arg1, arg2, onDone) {
	ui.showModal(title, [
		E('p', { 'class': 'spinning' }, 'Запуск задания...')
	]);
	return callJobStart(action, arg1 || '', arg2 || '').then(function(res) {
		if (!res || !res.ok) {
			if (res && res.running_id) {
				openJobModal(title + ' (текущее задание)', res.running_id, onDone);
				return;
			}
			ui.hideModal();
			notify('danger', (res && res.error) ? res.error : 'Не удалось запустить задание');
			return;
		}
		openJobModal(title, res.id, onDone);
	}).catch(function(err) {
		ui.hideModal();
		notify('danger', err && err.message ? err.message : String(err));
	});
}

return baseclass.extend({
	injectStyles: injectStyles,
	badge: badge,
	notify: notify,
	formatUptime: formatUptime,
	hostUrl: hostUrl,
	openJobModal: openJobModal,
	runJobModal: runJobModal,
	api: {
		status: callStatus,
		trace: callTrace,
		domainInspect: callDomainInspect,
		setDhcp: callSetDhcp,
		setKillswitch: callSetKillswitch,
		setCron: callSetCron,
		setNetwork: callSetNetwork,
		setSubscription: callSetSubscription,
		nodeAdd: callNodeAdd,
		nodeDelete: callNodeDelete,
		domainRule: callDomainRule,
		deviceRule: callDeviceRule,
		setTelegram: callSetTelegram,
		setPassword: callSetPassword,
		updateCheck: callUpdateCheck,
		getLogs: callGetLogs,
		jobStart: callJobStart,
		jobPoll: callJobPoll
	}
});
