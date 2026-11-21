'use strict';

(() => {
  const CAT_GROUPS = {
    popular: new Set(['alpine', 'debian', 'ubuntu', 'archlinux', 'fedora', 'almalinux', 'rockylinux']),
    light: new Set(['alpine', 'busybox', 'voidlinux', 'devuan']),
    server: new Set(['debian', 'ubuntu', 'centos', 'almalinux', 'rockylinux', 'oracle', 'amazonlinux', 'opensuse', 'alt']),
    sec: new Set(['kali', 'openwrt', 'nixos', 'gentoo', 'archlinux', 'cachyos']),
  };

  const DISTRO_ICONS = {
    alpine: '🏔️',
    debian: '🌀',
    ubuntu: '🟠',
    archlinux: '🏹',
    kali: '🐉',
    fedora: '🎩',
    almalinux: '💠',
    rockylinux: '🪨',
    centos: '💠',
    opensuse: '🦎',
    gentoo: '🧬',
    nixos: '❄️',
    voidlinux: '🟢',
    openwrt: '📡',
    busybox: '🧰',
    oracle: '🔴',
    devuan: '🟣',
    cachyos: '⚡',
    mint: '🌿',
  };

  const state = {
    status: null,
    activeTab: 'overview',
    pollTimer: null,
    refreshing: false,
    confirmResolve: null,
    catalog: null,
    catCategory: 'all',
    selectedDistro: 'alpine',
    expandedCts: {},
    ctSubTab: {},
    execOutputs: {},
    consoleCt: '',
    rawLogText: '',
  };

  function esc(val) {
    return String(val ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function qs(id) {
    return document.getElementById(id);
  }

  function badgeHtml(text, tone, extraClass = '') {
    return `<span class="badge badge-${tone || 'muted'} ${extraClass}">${esc(text)}</span>`;
  }

  function fmtUptime(sec) {
    const s = Math.max(0, Number(sec) || 0);
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (d > 0) return `${d}д ${h}ч ${m}м`;
    if (h > 0) return `${h}ч ${m}м`;
    return `${m}м`;
  }

  function toast(msg, type) {
    const stack = qs('toast-stack');
    const el = document.createElement('div');
    el.className = `toast ${type === 'err' ? 'toast-err' : 'toast-ok'}`;
    el.textContent = msg;
    stack.appendChild(el);
    setTimeout(() => {
      el.remove();
    }, 4200);
  }

  async function api(method, body = {}) {
    const res = await fetch(`/api/${encodeURIComponent(method)}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Gateway-Action': '1',
      },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_err) {
      throw new Error(`HTTP ${res.status}: некорректный ответ сервера`);
    }
    if (!res.ok) {
      throw new Error(data.error || `HTTP ${res.status}`);
    }
    return data;
  }

  async function copyText(str, okMsg = 'Скопировано в буфер') {
    try {
      await navigator.clipboard.writeText(str);
      toast(okMsg);
    } catch (_err) {
      toast(str);
    }
  }

  function confirmDialog(title, text) {
    return new Promise((resolve) => {
      state.confirmResolve = resolve;
      qs('confirm-title').textContent = title;
      qs('confirm-text').textContent = text;
      qs('confirm-modal').style.display = 'flex';
    });
  }

  function closeConfirm(answer) {
    qs('confirm-modal').style.display = 'none';
    if (state.confirmResolve) {
      const fn = state.confirmResolve;
      state.confirmResolve = null;
      fn(answer);
    }
  }

  function isModalOpen() {
    return (
      qs('job-modal').style.display === 'flex' ||
      qs('confirm-modal').style.display === 'flex' ||
      qs('lxc-create-modal').style.display === 'flex' ||
      qs('console-modal').style.display === 'flex'
    );
  }

  function isUserFocused() {
    const el = document.activeElement;
    if (el && ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)) return true;
    return Object.keys(state.expandedCts).some((k) => state.expandedCts[k] && state.ctSubTab[k] === 'config');
  }

  function setInputDefault(el, val) {
    if (!el) return;
    if (el.dataset.dirty === '1' || document.activeElement === el) return;
    el.value = val ?? '';
  }

  function trackDirty(el) {
    if (!el) return;
    el.addEventListener('input', () => {
      el.dataset.dirty = '1';
    });
  }

  async function runJob(title, action, arg1 = '', arg2 = '', onSuccessConsoleCt = '') {
    let startRes;
    try {
      startRes = await api('job_start', { action, arg1, arg2 });
    } catch (err) {
      toast(err.message, 'err');
      return;
    }

    if (!startRes.ok) {
      if (startRes.running_id) {
        toast('Уже выполняется другая фоновая операция — открываем её журнал', 'err');
        openJobPoller(title, startRes.running_id, '');
        return;
      }
      toast(startRes.error || 'Не удалось запустить задание', 'err');
      return;
    }

    openJobPoller(title, startRes.id, onSuccessConsoleCt);
  }

  function openJobPoller(title, jobId, onSuccessConsoleCt = '') {
    const modal = qs('job-modal');
    const titleEl = qs('job-title');
    const badgeEl = qs('job-badge');
    const logEl = qs('job-log');
    const closeBtn = qs('job-close');
    const conBtn = qs('job-open-console');

    titleEl.textContent = title;
    badgeEl.className = 'badge badge-warn';
    badgeEl.textContent = 'Выполняется...';
    logEl.textContent = 'Запуск фонового процесса...';
    closeBtn.disabled = true;
    conBtn.style.display = 'none';
    conBtn.onclick = null;
    modal.style.display = 'flex';

    let transientErrors = 0;

    const tick = async () => {
      try {
        const res = await api('job_poll', { id: jobId });
        transientErrors = 0;
        if (!res.ok) {
          badgeEl.className = 'badge badge-err';
          badgeEl.textContent = 'Ошибка';
          logEl.textContent = res.error || 'Задание недоступно';
          closeBtn.disabled = false;
          return;
        }
        if (res.log) {
          logEl.textContent = res.log;
          logEl.scrollTop = logEl.scrollHeight;
        }
        if (res.running) {
          setTimeout(tick, 900);
          return;
        }
        await refreshStatus(true);
        closeBtn.disabled = false;
        if (res.exit_code === 0) {
          badgeEl.className = 'badge badge-ok';
          badgeEl.textContent = 'Успешно';
          if (onSuccessConsoleCt) {
            conBtn.style.display = '';
            conBtn.onclick = () => {
              modal.style.display = 'none';
              openConsole(onSuccessConsoleCt);
            };
          }
        } else {
          badgeEl.className = 'badge badge-err';
          badgeEl.textContent = `Ошибка (${res.exit_code})`;
        }
      } catch (_err) {
        transientErrors += 1;
        if (transientErrors <= 12) {
          badgeEl.className = 'badge badge-warn';
          badgeEl.textContent = 'Переподключение...';
          setTimeout(tick, 1300);
        } else {
          badgeEl.className = 'badge badge-err';
          badgeEl.textContent = 'Потеряна связь';
          closeBtn.disabled = false;
        }
      }
    };

    tick();
  }

  async function openConsole(ctName) {
    try {
      const res = await api('lxc_console_token', { name: ctName });
      if (!res.ok) throw new Error(res.error || 'Не удалось получить токен консоли');
      state.consoleCt = ctName;
      qs('console-title').textContent = `💻 Консоль LXC: ${ctName}`;
      qs('console-sub').textContent = `Интерактивный shell (${location.host})`;
      qs('console-frame').src = res.url;
      qs('btn-con-newtab').href = res.url;
      qs('console-modal-box').classList.remove('fullscreen');
      qs('console-modal').style.display = 'flex';
    } catch (err) {
      toast(err.message, 'err');
    }
  }

  function closeConsoleModal() {
    const oldFrame = qs('console-frame');
    if (oldFrame && oldFrame.parentNode) {
      try {
        if (oldFrame.contentWindow) oldFrame.contentWindow.onbeforeunload = null;
      } catch (_e) {}
      const fresh = document.createElement('iframe');
      fresh.id = 'console-frame';
      fresh.className = oldFrame.className || 'console-frame';
      fresh.title = oldFrame.title || 'Веб-консоль LXC';
      oldFrame.replaceWith(fresh);
    }
    qs('console-modal').style.display = 'none';
  }

  function renderHeader(s) {
    const sys = s.system || {};
    const git = s.git || {};
    const links = s.links || {};
    const lxc = s.lxc || {};
    const cts = lxc.containers || [];
    const runCnt = cts.filter((c) => c.state === 'RUNNING').length;

    qs('hdr-sub').textContent = `${sys.os_name || 'Alpine Linux'} • ${sys.model || ''} • LAN ${s.network?.lan_ip || ''}`;

    const badges = [];
    badges.push(badgeHtml(
      s.core?.running ? `${s.core?.name || 'Core'} ●` : `${s.core?.name || 'Core'} ○`,
      s.core?.running ? 'ok' : 'err'
    ));
    badges.push(badgeHtml(
      s.adguard?.running ? 'AdGuard ●' : 'AdGuard ○',
      s.adguard?.running ? 'ok' : 'err'
    ));
    badges.push(`<span class="badge badge-${runCnt > 0 ? 'ok' : 'muted'} badge-clickable" id="hdr-lxc-jump">LXC ${runCnt}/${cts.length}</span>`);
    badges.push(badgeHtml(
      git.update_status === 'UPDATE_AVAILABLE'
        ? `Git ${git.sha} (↑${git.update_behind})`
        : `Git ${git.sha || 'Standalone'}`,
      git.update_status === 'UPDATE_AVAILABLE' ? 'warn' : 'muted'
    ));
    qs('hdr-badges').innerHTML = badges.join('');

    const lxcJump = qs('hdr-lxc-jump');
    if (lxcJump) {
      lxcJump.addEventListener('click', () => switchTab('lxc'));
    }

    const tabPill = qs('tab-lxc-count');
    if (cts.length > 0) {
      tabPill.style.display = '';
      tabPill.textContent = `${runCnt}/${cts.length}`;
    } else {
      tabPill.style.display = 'none';
    }

    const setLnk = (id, url) => {
      const el = qs(id);
      if (url) {
        el.href = url;
        el.style.display = '';
      } else {
        el.style.display = 'none';
      }
    };
    setLnk('lnk-core-ui', links.ui_url);
    setLnk('lnk-agh', links.agh_url);
    setLnk('lnk-ca', links.ca_url);
  }

  function renderOverview(s) {
    const sys = s.system || {};
    const core = s.core || {};
    const agh = s.adguard || {};

    const ramClass = sys.ram_pct >= 85 ? 'err' : sys.ram_pct >= 70 ? 'warn' : '';
    const dskClass = sys.disk_pct >= 90 ? 'err' : sys.disk_pct >= 75 ? 'warn' : '';

    qs('ov-kpis').innerHTML = `
      <div class="kpi-card">
        <div class="kpi-label">Ядро шлюза и TUN</div>
        <div class="kpi-val">${esc(core.name || '—')} ${esc(core.version || '')}</div>
        <div class="kpi-meta">
          ${core.running ? badgeHtml(`Активно (PID ${core.pid})`, 'ok') : badgeHtml('Остановлено', 'err')}
          ${core.tun_up ? badgeHtml(`TUN ${core.tun_if}`, 'ok') : badgeHtml('TUN вниз', 'err')}
          ${core.rss ? `<span class="muted"> • ${esc(core.rss)}</span>` : ''}
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-label">DNS &amp; DHCP (AdGuard Home)</div>
        <div class="kpi-val">${agh.running ? 'Работает' : 'Остановлен'} ${esc(agh.version || '')}</div>
        <div class="kpi-meta">
          ${agh.protection_enabled ? badgeHtml('Фильтр ON', 'ok') : badgeHtml('Фильтр OFF', 'warn')}
          ${agh.dhcp_enabled ? badgeHtml(`DHCP (${(agh.dhcp_leases || []).length} аренд)`, 'ok') : badgeHtml('DHCP Sidecar', 'muted')}
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-label">Оперативная память</div>
        <div class="kpi-val">${esc(sys.ram_pct)}% (${esc(sys.ram_used_mb)} / ${esc(sys.ram_total_mb)} МБ)</div>
        <div class="kpi-meta">Load: ${esc(sys.load || '—')} • Conntrack: ${esc(sys.conntrack_used)}/${esc(sys.conntrack_max)}</div>
        <div class="progress-bar"><div class="progress-fill ${ramClass}" style="width:${Math.min(100, sys.ram_pct || 0)}%"></div></div>
      </div>

      <div class="kpi-card">
        <div class="kpi-label">Корневой раздел /</div>
        <div class="kpi-val">${esc(sys.disk_used || '0')} / ${esc(sys.disk_total || '0')} (${esc(sys.disk_pct)}%)</div>
        <div class="kpi-meta">Ядро ОС: ${esc(sys.kernel || '—')}</div>
        <div class="progress-bar"><div class="progress-fill ${dskClass}" style="width:${Math.min(100, sys.disk_pct || 0)}%"></div></div>
      </div>
    `;

    qs('ov-uptime').textContent = `Аптайм: ${fmtUptime(sys.uptime_sec)}`;

    const modules = Array.isArray(s.homelab) ? s.homelab : [];
    if (!modules.length) {
      qs('ov-homelab-grid').innerHTML = '<div class="muted">Модули Homelab пока не зарегистрированы.</div>';
    } else {
      qs('ov-homelab-grid').innerHTML = modules.map((m) => {
        const statusBadge = !m.enabled
          ? badgeHtml('Не установлен', 'muted')
          : (m.running ? badgeHtml('Работает', 'ok') : badgeHtml('Остановлен', 'err'));

        let subLine = '';
        if (m.url) {
          subLine = `<a href="${esc(m.url)}" target="_blank" rel="noopener">${esc(m.url)} ↗</a>`;
        } else if (m.smb_share) {
          subLine = `<span class="mono">${esc(m.smb_share)}</span> <button class="btn btn-xs" data-copy="${esc(m.smb_share)}" type="button">Копир.</button>`;
        } else {
          subLine = `<span class="muted">Сервис: ${esc(m.service || m.id)} • Порт ${esc(m.port || '—')}</span>`;
        }

        let btns = '';
        if (m.enabled) {
          if (m.url) {
            btns += `<a class="btn btn-primary btn-xs" href="${esc(m.url)}" target="_blank" rel="noopener">Открыть ↗</a>`;
          }
          if (m.running) {
            btns += `<button class="btn btn-xs" data-hl-act="stop" data-hl-id="${esc(m.id)}" type="button">Стоп</button>`;
          } else {
            btns += `<button class="btn btn-primary btn-xs" data-hl-act="start" data-hl-id="${esc(m.id)}" type="button">Старт</button>`;
          }
          btns += `<button class="btn btn-xs" data-hl-act="restart" data-hl-id="${esc(m.id)}" type="button">Рестарт</button>`;
          btns += `<button class="btn btn-xs" data-hl-act="update" data-hl-id="${esc(m.id)}" type="button">Обновить</button>`;
          btns += `<button class="btn btn-danger btn-xs" data-hl-act="remove" data-hl-id="${esc(m.id)}" type="button">Удалить</button>`;
        } else {
          btns += `<button class="btn btn-primary btn-xs" data-hl-act="install" data-hl-id="${esc(m.id)}" type="button">+ Установить</button>`;
        }

        return `
          <div class="hl-card">
            <div class="hl-top">
              <div>
                <div class="hl-title">${esc(m.title)}</div>
                <div class="hl-sub">${subLine}</div>
              </div>
              ${statusBadge}
            </div>
            <div class="hl-actions">${btns}</div>
          </div>
        `;
      }).join('');
    }

    renderProxyGroups(s);
  }

  function renderProxyGroups(s) {
    const q = (qs('inp-groups-filter')?.value || '').trim().toLowerCase();
    const allGroups = s.proxies?.groups || [];
    const groups = q
      ? allGroups.filter((g) => g.name.toLowerCase().includes(q) || (g.now || '').toLowerCase().includes(q))
      : allGroups;
    qs('ov-groups-meta').textContent = q ? `${groups.length} из ${allGroups.length}` : `${allGroups.length} групп`;
    qs('ov-groups-body').innerHTML = groups.length
      ? groups.map((g) => `
          <tr>
            <td><strong>${esc(g.name)}</strong></td>
            <td class="muted">${esc(g.type)}</td>
            <td class="mono">${esc(g.now || '—')}</td>
            <td>${esc(g.count)}</td>
          </tr>
        `).join('')
      : '<tr><td colspan="4" class="muted">Совпадений нет или ядро остановлено.</td></tr>';
  }

  function renderNetwork(s) {
    const core = s.core || {};
    const net = s.network || {};
    const agh = s.adguard || {};

    qs('net-core-info').innerHTML = `
      <div><span class="muted">Движок:</span> <strong>${esc(core.name)}</strong></div>
      <div><span class="muted">Версия:</span> ${esc(core.version || '—')}</div>
      <div><span class="muted">Веб-панель:</span> <strong>${esc(core.ui_name)}</strong> (${esc(core.ui_ver || '—')})</div>
      <div><span class="muted">Память / PID:</span> ${esc(core.rss || '—')} / ${esc(core.pid || '—')}</div>
    `;

    qs('btn-core-mihomo').classList.toggle('active', core.engine === 'mihomo');
    qs('btn-core-singbox').classList.toggle('active', core.engine === 'singbox');
    qs('btn-ui-metacubexd').classList.toggle('active', core.ui === 'metacubexd');
    qs('btn-ui-zashboard').classList.toggle('active', core.ui === 'zashboard');

    const ksBtn = qs('btn-ks-toggle');
    ksBtn.textContent = net.killswitch ? 'Kill-Switch: ВКЛ (Отключить)' : 'Kill-Switch: ВЫКЛ (Включить)';
    ksBtn.className = `btn ${net.killswitch ? 'btn-danger' : 'btn-primary'}`;

    setInputDefault(qs('inp-lan-ip'), net.lan_ip || '');
    setInputDefault(qs('inp-gw-ip'), net.gw_ip || '');

    const dhcpBtn = qs('btn-dhcp-toggle');
    dhcpBtn.textContent = agh.dhcp_enabled ? 'DHCP: ВКЛ (Выключить)' : 'DHCP: ВЫКЛ (Включить)';
    dhcpBtn.className = `btn ${agh.dhcp_enabled ? 'btn-danger' : 'btn-primary'}`;

    const v4 = agh.dhcp_v4 || {};
    const leases = agh.dhcp_leases || [];
    qs('net-dhcp-info').innerHTML = `
      <span>Статус: ${agh.dhcp_enabled ? badgeHtml('Раздаёт адреса в LAN', 'ok') : badgeHtml('Выключен (Sidecar)', 'muted')}</span>
      <span>Диапазон: <span class="mono">${esc(v4.range_start || '—')} – ${esc(v4.range_end || '—')}</span></span>
      <span>Интерфейс: <span class="mono">${esc(net.lan_if || '—')}</span></span>
      <span>Активных аренд: <strong>${leases.length}</strong></span>
    `;

    qs('net-leases-body').innerHTML = leases.length
      ? leases.map((l) => `
          <tr>
            <td class="mono">${esc(l.ip)}</td>
            <td class="mono muted">${esc(l.mac || '—')}</td>
            <td>${esc(l.hostname || '—')}</td>
            <td class="muted">${esc(l.expires || '—')}</td>
          </tr>
        `).join('')
      : '<tr><td colspan="4" class="muted">Активных DHCP-аренд нет.</td></tr>';
  }

  function renderProxies(s) {
    const px = s.proxies || {};
    qs('px-sub-badge').textContent = `${px.sub_count || 0} ссылок`;
    qs('px-sub-badge').className = `badge ${px.sub_count > 0 ? 'badge-ok' : 'badge-muted'}`;
    setInputDefault(qs('inp-sub-urls'), (px.sub_urls || '').trim().split(/\s+/).filter(Boolean).join('\n'));
    const ruChk = qs('chk-allow-ru');
    if (ruChk.dataset.dirty !== '1') {
      ruChk.checked = Boolean(px.allow_ru);
    }

    const warpBadge = qs('px-warp-badge');
    warpBadge.textContent = px.warp_enabled ? 'Активен' : 'Выключен';
    warpBadge.className = `badge ${px.warp_enabled ? 'badge-ok' : 'badge-muted'}`;
    qs('inp-warp-lic').placeholder = px.warp_license_set
      ? 'Ключ WARP+ уже сохранён (введите новый при смене)'
      : 'Оставьте пустым для бесплатного WARP';

    const nodes = px.my_nodes || [];
    qs('px-nodes-body').innerHTML = nodes.length
      ? nodes.map((n) => `
          <tr>
            <td>${esc(n.index)}</td>
            <td>${badgeHtml(n.proto, 'ok')}</td>
            <td class="mono">${esc(n.host)}</td>
            <td>${esc(n.tag)}</td>
            <td><button class="btn btn-danger btn-xs" data-node-del="${esc(n.index)}" type="button">Удалить</button></td>
          </tr>
        `).join('')
      : '<tr><td colspan="5" class="muted">Пользовательские URI-ключи пока не добавлены.</td></tr>';

    const renderChips = (elId, items, listName) => {
      const container = qs(elId);
      if (!items || !items.length) {
        container.innerHTML = '<span class="muted small">Список пуст.</span>';
        return;
      }
      container.innerHTML = items.map((dom) => {
        const locked = listName === 'direct' && (dom === '+.lan' || dom === '+.localdomain');
        return `<span class="chip">${esc(dom)}${locked ? '' : `<button class="chip-del" data-dom-del="${esc(dom)}" data-dom-list="${esc(listName)}" type="button" title="Удалить">×</button>`}</span>`;
      }).join('');
    };

    renderChips('chips-proxy', px.proxy_domains, 'proxy');
    renderChips('chips-direct', px.direct_domains, 'direct');

    renderDevices(s);
  }

  function renderDevices(s) {
    const q = (qs('inp-dev-filter')?.value || '').trim().toLowerCase();
    const allDevs = s.devices || [];
    const devs = q
      ? allDevs.filter((d) =>
          (d.ip || '').toLowerCase().includes(q) ||
          (d.mac || '').toLowerCase().includes(q) ||
          (d.hostname || '').toLowerCase().includes(q)
        )
      : allDevs;
    qs('px-devices-body').innerHTML = devs.length
      ? devs.map((d) => `
          <tr>
            <td class="mono">${esc(d.ip)}</td>
            <td class="mono muted">${esc(d.mac || '—')}</td>
            <td>${esc(d.hostname || '—')}</td>
            <td>
              <div class="btn-row-compact">
                <button class="btn btn-xs ${d.mode === 'default' ? 'btn-primary' : ''}" data-dev-ip="${esc(d.ip)}" data-dev-mode="default" type="button">По умолчанию</button>
                <button class="btn btn-xs ${d.mode === 'bypass' ? 'btn-primary' : ''}" data-dev-ip="${esc(d.ip)}" data-dev-mode="bypass" type="button">Напрямую</button>
                <button class="btn btn-xs ${d.mode === 'force_proxy' ? 'btn-primary' : ''}" data-dev-ip="${esc(d.ip)}" data-dev-mode="force_proxy" type="button">Через прокси</button>
              </div>
            </td>
          </tr>
        `).join('')
      : '<tr><td colspan="4" class="muted">Устройства не найдены.</td></tr>';
  }

  function renderLxc(s) {
    const lxc = s.lxc || { installed: false, bridge_up: false, arch: 'amd64', lxc_version: '', console_ready: false, containers: [] };
    const ctsAll = lxc.containers || [];
    const runCnt = ctsAll.filter((c) => c.state === 'RUNNING').length;

    qs('lxc-status-badges').innerHTML = [
      badgeHtml(lxc.installed ? `LXC ${lxc.lxc_version || 'OK'}` : 'LXC не установлен', lxc.installed ? 'ok' : 'warn'),
      badgeHtml(lxc.bridge_up ? 'Мост lxcbr0 UP' : 'Мост lxcbr0 DOWN', lxc.bridge_up ? 'ok' : 'warn'),
      badgeHtml(`Архитектура: ${lxc.arch || 'amd64'}`, 'muted'),
      badgeHtml(lxc.console_ready ? 'Веб-консоль ttyd ●' : 'ttyd ○', lxc.console_ready ? 'ok' : 'warn'),
      badgeHtml(`Активных: ${runCnt}/${ctsAll.length}`, runCnt > 0 ? 'ok' : 'muted'),
    ].join(' ');

    const q = (qs('inp-lxc-filter')?.value || '').trim().toLowerCase();
    const cts = q
      ? ctsAll.filter((c) => c.name.toLowerCase().includes(q) || (c.os_pretty || '').toLowerCase().includes(q) || (c.ipv4 || '').toLowerCase().includes(q))
      : ctsAll;

    const wrap = qs('lxc-cards-container');
    if (!ctsAll.length) {
      wrap.innerHTML = `
        <div class="card lxc-empty">
          <h3>Контейнеров LXC пока нет</h3>
          <p class="muted">Разверните Debian, Ubuntu, Alpine, Arch, Kali или любую другую систему из полного каталога <span class="mono">images.linuxcontainers.org</span> в пару кликов.</p>
          <div class="btn-row" style="justify-content:center; margin-top:0.9rem">
            <button class="btn btn-primary" data-lxc-quick-os="alpine" type="button">🏔️ Alpine Linux</button>
            <button class="btn btn-primary" data-lxc-quick-os="debian" type="button">🌀 Debian</button>
            <button class="btn btn-primary" data-lxc-quick-os="ubuntu" type="button">🟠 Ubuntu</button>
            <button class="btn btn-secondary" data-lxc-quick-os="kali" type="button">🐉 Kali</button>
            <button class="btn btn-secondary" data-lxc-quick-os="" type="button">🌐 Весь каталог (24+ ОС)</button>
          </div>
        </div>
      `;
      return;
    }

    if (!cts.length) {
      wrap.innerHTML = '<div class="card"><div class="muted">По запросу контейнеры не найдены.</div></div>';
      return;
    }

    wrap.innerHTML = cts.map((c) => {
      const isRun = c.state === 'RUNNING';
      const isOpen = Boolean(state.expandedCts[c.name]);
      const sub = state.ctSubTab[c.name] || 'snaps';
      const snaps = c.snapshots || [];

      let drawerHtml = '';
      if (isOpen) {
        let panelHtml = '';
        if (sub === 'snaps') {
          const rows = snaps.length
            ? snaps.map((sn) => `
                <tr>
                  <td class="mono"><strong>${esc(sn.name)}</strong></td>
                  <td class="muted">${esc(sn.date || '—')}</td>
                  <td>${esc(sn.comment || '—')}</td>
                  <td>
                    <div class="btn-row-compact">
                      <button class="btn btn-xs" data-lxc-ct="${esc(c.name)}" data-lxc-act="snap_restore:${esc(sn.name)}" type="button">↩ Откатить</button>
                      <button class="btn btn-danger btn-xs" data-lxc-ct="${esc(c.name)}" data-lxc-act="snap_delete:${esc(sn.name)}" type="button">🗑 Удалить</button>
                    </div>
                  </td>
                </tr>
              `).join('')
            : '<tr><td colspan="4" class="muted">Снимков пока нет — создайте перед изменением системы!</td></tr>';

          panelHtml = `
            <p class="muted small" style="margin-top:0">Перед экспериментами или обновлением пакетов создайте снимок: откат вернёт контейнер в сохранённое состояние.</p>
            <form class="inline-form" data-snap-form="${esc(c.name)}">
              <input class="input" data-snap-comment="${esc(c.name)}" type="text" placeholder="Комментарий к снимку (например: До установки Docker)">
              <button class="btn btn-primary btn-sm" type="submit">📸 + Создать снимок</button>
            </form>
            <div class="table-wrap" style="margin-top:0.75rem">
              <table class="data-table">
                <thead><tr><th>Снимок</th><th>Дата</th><th>Описание</th><th>Действия</th></tr></thead>
                <tbody>${rows}</tbody>
              </table>
            </div>
          `;
        } else if (sub === 'exec') {
          const outTxt = state.execOutputs[c.name] || 'Вывод команды появится здесь (пример: apk update или systemctl status).';
          panelHtml = `
            <div class="btn-row-compact" style="margin-bottom:0.65rem">
              <span class="muted small">Быстрые проверки:</span>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="ip -4 -br addr && cat /etc/resolv.conf" type="button">🌐 Сеть и DNS</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="df -h" type="button">💾 Диски</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="free -m" type="button">🧠 Память</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="ps aux | head -n 25" type="button">⚙️ Процессы</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="cat /etc/os-release" type="button">🐧 ОС</button>
            </div>
            <form class="inline-form" data-exec-form="${esc(c.name)}">
              <input class="input mono" data-exec-input="${esc(c.name)}" type="text" placeholder="Введите команду внутри ${esc(c.name)} (например: uname -a && ls -la /mnt)" ${isRun ? '' : 'disabled'}>
              <button class="btn btn-primary btn-sm" type="submit" ${isRun ? '' : 'disabled'}>▶ Выполнить</button>
            </form>
            <pre class="exec-output" id="exec-out-${esc(c.name)}">${esc(outTxt)}</pre>
          `;
        } else if (sub === 'config') {
          panelHtml = `
            <form data-cfg-form="${esc(c.name)}" class="form-grid">
              <div class="two-col">
                <div>
                  <label class="field-label">Лимит ОЗУ (пусто = без лимита)</label>
                  <input class="input" name="mem_limit" type="text" value="${esc(c.mem_limit || '')}" placeholder="Например: 512M или 2G">
                </div>
                <div>
                  <label class="field-label">Лимит ядер CPU (пусто = без лимита)</label>
                  <input class="input" name="cpu_limit" type="text" value="${esc(c.cpu_limit || '')}" placeholder="Например: 1 или 2">
                </div>
                <div>
                  <label class="field-label">Сменить пароль root (необязательно)</label>
                  <input class="input" name="root_pass" type="password" placeholder="Оставьте пустым, чтобы не менять">
                </div>
                <div style="display:flex; flex-direction:column; justify-content:center; gap:0.4rem">
                  <label class="check-row" style="margin:0"><input name="autostart" type="checkbox" ${c.autostart ? 'checked' : ''}><span>⚡ Автозапуск при старте сервера</span></label>
                  <label class="check-row" style="margin:0"><input name="storage_mount" type="checkbox" ${c.storage_mount ? 'checked' : ''}><span>💾 Монтировать /srv/storage → /mnt/storage</span></label>
                  <label class="check-row" style="margin:0"><input name="nesting" type="checkbox" ${c.nesting ? 'checked' : ''}><span>🪆 Режим Nesting (Docker/контейнеры внутри)</span></label>
                </div>
              </div>
              <div class="btn-row">
                <button class="btn btn-secondary btn-sm" data-cfg-save="${esc(c.name)}" type="button">💾 Сохранить параметры</button>
                <button class="btn btn-primary btn-sm" data-cfg-restart="${esc(c.name)}" type="button">🔄 Сохранить и перезапустить</button>
              </div>
            </form>
          `;
        } else if (sub === 'manage') {
          panelHtml = `
            <div class="two-col">
              <div>
                <div class="field-label">🧬 Клонировать контейнер «${esc(c.name)}»</div>
                <form class="inline-form" data-clone-form="${esc(c.name)}">
                  <input class="input" data-clone-target="${esc(c.name)}" type="text" placeholder="${esc(c.name)}-copy" pattern="[A-Za-z0-9_-]+" required>
                  <button class="btn btn-primary btn-sm" type="submit">Клонировать</button>
                </form>
                <div class="muted small" style="margin-top:0.35rem">Создаст полную копию с уникальным MAC-адресом.</div>
              </div>
              <div>
                <div class="field-label">🔧 Диагностика и удаление</div>
                <div class="btn-row">
                  <button class="btn btn-secondary btn-sm" data-lxc-ct="${esc(c.name)}" data-lxc-act="fix-net" type="button">🔧 Починить сеть (DHCP/DNS)</button>
                  <button class="btn btn-danger btn-sm" data-lxc-delete="${esc(c.name)}" type="button">🗑 Удалить контейнер</button>
                </div>
              </div>
            </div>
          `;
        }

        drawerHtml = `
          <div class="lxc-drawer">
            <div class="sub-tabs">
              <button class="btn btn-xs seg-btn ${sub === 'snaps' ? 'active' : ''}" data-ct-sub="snaps" data-ct-name="${esc(c.name)}" type="button">📸 Снимки (${snaps.length})</button>
              <button class="btn btn-xs seg-btn ${sub === 'exec' ? 'active' : ''}" data-ct-sub="exec" data-ct-name="${esc(c.name)}" type="button">⚡ Быстрая команда</button>
              <button class="btn btn-xs seg-btn ${sub === 'config' ? 'active' : ''}" data-ct-sub="config" data-ct-name="${esc(c.name)}" type="button">⚙️ Ресурсы и опции</button>
              <button class="btn btn-xs seg-btn ${sub === 'manage' ? 'active' : ''}" data-ct-sub="manage" data-ct-name="${esc(c.name)}" type="button">🧬 Клон и удаление</button>
            </div>
            ${panelHtml}
          </div>
        `;
      }

      return `
        <article class="lxc-card">
          <div class="lxc-card-head">
            <div>
              <div class="lxc-title-row">
                <span class="lxc-name">${esc(c.name)}</span>
                ${isRun ? badgeHtml(`RUNNING${c.pid ? ` • PID ${c.pid}` : ''}`, 'ok') : badgeHtml('STOPPED', 'muted')}
                ${c.os_pretty ? badgeHtml(c.os_pretty, 'muted') : ''}
                ${badgeHtml(c.net_mode === 'macvlan' ? 'Macvlan LAN' : 'NAT lxcbr0', 'muted')}
                ${c.autostart ? badgeHtml('Автостарт', 'ok') : ''}
                ${c.nesting ? badgeHtml('Nesting', 'warn') : ''}
                ${c.storage_mount ? badgeHtml('/mnt/storage', 'ok') : ''}
              </div>
              <div class="lxc-meta-row">
                <span>IPv4: <strong class="mono">${esc(c.ipv4 || c.static_ip || '—')}</strong>${c.ipv4 ? ` <button class="btn btn-xs" data-copy="${esc(c.ipv4)}" type="button">Копир.</button>` : ''}</span>
                <span>ОЗУ: <strong>${esc(c.memory || '—')}</strong>${c.mem_limit ? ` / ${esc(c.mem_limit)}` : ''}</span>
                ${c.cpu_limit ? `<span>CPU: <strong>${esc(c.cpu_limit)} ядер</strong></span>` : ''}
                <span>Диск: <strong>${esc(c.disk_usage || '—')}</strong></span>
                <span>Снимки: <strong>${snaps.length}</strong></span>
              </div>
            </div>

            <div class="btn-row-compact">
              <button class="btn btn-primary btn-sm" data-lxc-console="${esc(c.name)}" type="button" ${isRun ? '' : 'disabled title="Запустите контейнер для подключения к консоли"'}>💻 Консоль</button>
              ${isRun
                ? `<button class="btn btn-sm" data-lxc-ct="${esc(c.name)}" data-lxc-act="stop" type="button">⏹ Стоп</button>`
                : `<button class="btn btn-primary btn-sm" data-lxc-ct="${esc(c.name)}" data-lxc-act="start" type="button">▶ Старт</button>`}
              <button class="btn btn-sm" data-lxc-ct="${esc(c.name)}" data-lxc-act="restart" type="button">🔄 Рестарт</button>
              <button class="btn btn-sm" data-lxc-quicksnap="${esc(c.name)}" type="button">📸 Снимок +</button>
              <button class="btn btn-sm ${isOpen ? 'btn-primary' : ''}" data-lxc-toggle="${esc(c.name)}" type="button">⚙ Управление ${isOpen ? '▴' : '▾'}</button>
            </div>
          </div>
          ${drawerHtml}
        </article>
      `;
    }).join('');
  }

  function renderStorageSsl(s) {
    const st = s.storage || {};
    const pct = Number(st.disk_pct) || 0;
    const fillCls = pct >= 90 ? 'err' : pct >= 75 ? 'warn' : '';
    qs('infra-storage-info').innerHTML = `
      <div class="info-list">
        <div><span class="muted">Путь:</span> <span class="mono">${esc(st.root || '/srv/storage')}</span></div>
        <div><span class="muted">Статус:</span> ${badgeHtml(st.badge || 'Системный раздел', st.ext_mounted ? 'ok' : (st.ext_expected ? 'warn' : 'muted'))}</div>
        <div><span class="muted">Устройство / ФС:</span> <span class="mono">${esc(st.device || '—')} (${esc(st.fs_type || '—')})</span></div>
        <div><span class="muted">LUKS2 ключ:</span> ${st.luks_key_exists ? badgeHtml('Ключ сохранён', 'ok') : badgeHtml('Нет ключевого файла', 'muted')}</div>
      </div>
      <div>Использование: <strong>${esc(st.disk_used || '0')} / ${esc(st.disk_total || '0')} (${pct}%)</strong></div>
      <div class="progress-bar"><div class="progress-fill ${fillCls}" style="width:${Math.min(100, pct)}%"></div></div>
    `;

    const dirs = st.dirs || [];
    qs('infra-storage-dirs').innerHTML = dirs.length
      ? dirs.map((d) => `
          <tr>
            <td><strong>${esc(d.name)}</strong></td>
            <td class="mono muted">${esc(d.path)}</td>
            <td class="mono">${esc(d.size)}</td>
          </tr>
        `).join('')
      : '<tr><td colspan="3" class="muted">Данные каталогов недоступны.</td></tr>';

    const ssl = s.ssl || {};
    const caBtn = qs('btn-ssl-ca-portal');
    if (s.links?.ca_url) {
      caBtn.href = s.links.ca_url;
      caBtn.style.display = '';
    } else {
      caBtn.style.display = 'none';
    }

    qs('infra-ssl-info').innerHTML = `
      <div class="info-list">
        <div><span class="muted">Режим HTTPS:</span> ${ssl.le_active ? badgeHtml('Let\'s Encrypt Wildcard', 'ok') : badgeHtml('Локальный PKI (*.lan)', 'muted')}</div>
        <div><span class="muted">Caddy Proxy:</span> ${ssl.caddy_enabled ? badgeHtml('Активен', 'ok') : badgeHtml('Отключен', 'warn')}</div>
        <div><span class="muted">Домен:</span> <span class="mono">${esc(ssl.domain ? `*.${ssl.domain}` : '*.lan')}</span></div>
        <div><span class="muted">Истекает:</span> ${esc(ssl.expiry || 'Локальный CA')}${ssl.days_left ? ` (${ssl.days_left} дн.)` : ''}</div>
      </div>
    `;
    setInputDefault(qs('inp-duck-sub'), (ssl.domain || '').replace(/\.duckdns\.org$/i, ''));
    qs('inp-duck-tok').placeholder = ssl.duckdns_token_set
      ? `Сохранён (${ssl.duckdns_token_masked || '****'}) — оставьте пустым для использования`
      : 'Введите токен DuckDNS (UUID)';
  }

  function renderSystem(s) {
    const tg = s.telegram || {};
    qs('sys-tg-badge').textContent = tg.configured ? 'Настроен' : 'Выключен';
    qs('sys-tg-badge').className = `badge ${tg.configured ? 'badge-ok' : 'badge-muted'}`;
    qs('sys-tg-mask').textContent = tg.token_masked ? `Текущий токен: ${tg.token_masked}` : 'Токен еще не задан';
    setInputDefault(qs('inp-tg-chat'), tg.chat_id || '');

    const bak = s.backup || {};
    qs('sys-backup-info').innerHTML = bak.exists
      ? `<div>Архив: <span class="mono">/root/gateway_backup.tar.gz</span> • <strong>${esc(bak.size)}</strong> • <span class="muted">${esc(bak.mtime)}</span></div>`
      : '<div class="muted">Единый архив бэкапа еще не создан.</div>';

    const cron = s.cron || {};
    const wdBtn = qs('btn-cron-wd');
    wdBtn.textContent = cron.watchdog ? 'ВКЛ (Выключить)' : 'ВЫКЛ (Включить)';
    wdBtn.className = `btn btn-sm ${cron.watchdog ? 'btn-primary' : 'btn-secondary'}`;

    const auBtn = qs('btn-cron-au');
    auBtn.textContent = cron.autoupdate ? 'ВКЛ (Выключить)' : 'ВЫКЛ (Включить)';
    auBtn.className = `btn btn-sm ${cron.autoupdate ? 'btn-primary' : 'btn-secondary'}`;

    const git = s.git || {};
    const updTone = git.update_status === 'UPDATE_AVAILABLE' ? 'warn' : 'ok';
    const updText = git.update_status === 'UPDATE_AVAILABLE'
      ? `Доступно обновлений: ${git.update_behind}`
      : (git.update_status === 'UP_TO_DATE' ? 'Актуальная версия' : (git.is_repo ? 'Не проверялось' : 'Standalone'));
    qs('sys-git-info').innerHTML = `
      <div class="info-list">
        <div><span class="muted">Ветка:</span> <span class="mono">${esc(git.branch || 'main')}</span></div>
        <div><span class="muted">Текущий коммит:</span> <span class="mono">${esc(git.sha || '—')}</span></div>
        <div><span class="muted">Статус:</span> ${badgeHtml(updText, updTone)}</div>
      </div>
    `;
  }

  function renderAll(s) {
    renderHeader(s);
    renderOverview(s);
    renderNetwork(s);
    renderProxies(s);
    renderLxc(s);
    renderStorageSsl(s);
    renderSystem(s);
  }

  // LXC Creation Wizard catalog functions
  async function loadCatalog(force = false) {
    qs('lxc-cat-status').textContent = 'Загрузка официального списка образов с images.linuxcontainers.org...';
    try {
      const cat = await api('lxc_templates', { force: force ? 'yes' : 'no' });
      if (!cat.ok) throw new Error(cat.error || 'Не удалось загрузить каталог');
      state.catalog = cat;
      qs('lxc-cat-arch-badge').textContent = `Архитектура: ${cat.arch}`;
      qs('lxc-cat-status').textContent = `Загружено ${cat.total} образов (${cat.source}, кэш ${cat.updated_at})`;
      renderCatalogGrid();
    } catch (err) {
      qs('lxc-cat-status').textContent = `Ошибка загрузки каталога: ${err.message}`;
    }
  }

  function renderCatalogGrid() {
    const cat = state.catalog;
    const grid = qs('lxc-distro-grid');
    if (!cat || !Array.isArray(cat.templates)) {
      grid.innerHTML = '<div class="muted small" style="padding:0.5rem">Загрузка каталога...</div>';
      return;
    }

    const q = (qs('inp-cat-search').value || '').trim().toLowerCase();
    const vFilt = qs('sel-cat-variant').value;
    const gFilt = state.catCategory;

    const byDistro = new Map();
    for (const item of cat.templates) {
      if (vFilt !== 'all' && item.variant !== vFilt) continue;
      if (gFilt !== 'all' && CAT_GROUPS[gFilt] && !CAT_GROUPS[gFilt].has(item.distro)) continue;
      if (q && !item.distro.toLowerCase().includes(q) && !item.release.toLowerCase().includes(q)) continue;
      if (!byDistro.has(item.distro)) byDistro.set(item.distro, []);
      byDistro.get(item.distro).push(item);
    }

    const distros = Array.from(byDistro.keys()).sort();
    if (!distros.length) {
      grid.innerHTML = '<div class="muted small" style="padding:0.5rem">Образы по фильтру не найдены — попробуйте «Все ОС» или ручной ввод.</div>';
      return;
    }

    if (!byDistro.has(state.selectedDistro)) {
      state.selectedDistro = distros[0];
    }

    grid.innerHTML = distros.map((d) => {
      const items = byDistro.get(d);
      const relSet = new Set(items.map((x) => x.release));
      const icon = DISTRO_ICONS[d] || '🐧';
      const selCls = d === state.selectedDistro ? 'selected' : '';
      return `
        <button class="distro-tile ${selCls}" data-pick-distro="${esc(d)}" type="button">
          <span class="distro-title">${icon} ${esc(d)}</span>
          <span class="distro-meta">${relSet.size} релизов</span>
        </button>
      `;
    }).join('');

    syncDistroReleases(state.selectedDistro);
  }

  function syncDistroReleases(distro) {
    state.selectedDistro = distro;
    qs('sel-lxc-distro').value = distro;
    const templates = (state.catalog?.templates || []).filter((t) => t.distro === distro);
    const relMap = new Map();
    for (const t of templates) {
      if (!relMap.has(t.release)) relMap.set(t.release, []);
      relMap.get(t.release).push(t);
    }
    const rels = Array.from(relMap.keys());
    const relSel = qs('sel-lxc-release');
    relSel.innerHTML = rels.length
      ? rels.map((r) => `<option value="${esc(r)}">${esc(r)}</option>`).join('')
      : '<option value="default">manual</option>';

    // Prefer popular/latest release cleanly
    const preferred = ['3.24', 'bookworm', 'trixie', 'noble', 'jammy', 'current', '43', '9'];
    for (const p of preferred) {
      if (rels.includes(p)) {
        relSel.value = p;
        break;
      }
    }
    syncReleaseVariants();
  }

  function syncReleaseVariants() {
    const distro = qs('sel-lxc-distro').value.trim();
    const rel = qs('sel-lxc-release').value;
    const vFilt = qs('sel-cat-variant').value;
    let items = (state.catalog?.templates || []).filter((t) => t.distro === distro && t.release === rel);
    if (vFilt !== 'all') {
      const filtered = items.filter((t) => t.variant === vFilt);
      if (filtered.length) items = filtered;
    }
    const varSel = qs('sel-lxc-variant');
    if (items.length) {
      varSel.innerHTML = items.map((t) => `<option value="${esc(t.variant)}">${esc(t.variant)}${t.build ? ` (${esc(t.build.split('_')[0])})` : ''}</option>`).join('');
      const defOpt = items.find((t) => t.variant === 'default');
      if (defOpt) varSel.value = 'default';
    } else {
      varSel.innerHTML = '<option value="default">default</option>';
    }
  }

  async function openLxcWizard(preselectDistro = '') {
    qs('lxc-create-modal').style.display = 'flex';
    qs('inp-cat-search').value = '';
    if (preselectDistro) {
      state.selectedDistro = preselectDistro;
      state.catCategory = 'all';
      document.querySelectorAll('#cat-group-btns [data-cat]').forEach((b) => {
        b.classList.toggle('active', b.dataset.cat === 'all');
      });
    }
    if (!state.catalog) {
      await loadCatalog(false);
    } else {
      renderCatalogGrid();
    }
    if (preselectDistro && (state.catalog?.templates || []).some((t) => t.distro === preselectDistro)) {
      syncDistroReleases(preselectDistro);
      renderCatalogGrid();
    }
  }

  function renderFilteredLogs() {
    const view = qs('sys-log-view');
    const raw = state.rawLogText || '';
    if (!raw) return;
    const q = (qs('inp-log-filter')?.value || '').trim().toLowerCase();
    if (!q) {
      view.textContent = raw;
      return;
    }
    const matched = raw.split('\n').filter((line) => line.toLowerCase().includes(q));
    view.textContent = matched.length ? matched.join('\n') : '(Строк по фильтру не найдено)';
  }

  async function refreshStatus(force = false) {
    if (!force && (isModalOpen() || isUserFocused())) return;
    if (state.refreshing) return;
    state.refreshing = true;
    try {
      const s = await api('status', {});
      if (!s.ok) throw new Error(s.error || 'Ошибка получения статуса');
      state.status = s;
      renderAll(s);
    } catch (err) {
      toast(`Не удалось обновить статус: ${err.message}`, 'err');
    } finally {
      state.refreshing = false;
    }
  }

  function switchTab(tabName) {
    state.activeTab = tabName;
    document.querySelectorAll('.tab-btn').forEach((b) => {
      b.classList.toggle('active', b.dataset.tab === tabName);
    });
    document.querySelectorAll('.tab-panel').forEach((p) => {
      p.classList.toggle('active', p.id === `tab-${tabName}`);
    });
  }

  function initTheme() {
    const saved = localStorage.getItem('gw_theme') || 'dark';
    document.documentElement.setAttribute('data-theme', saved);
    qs('btn-theme').addEventListener('click', () => {
      const cur = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
      document.documentElement.setAttribute('data-theme', cur);
      localStorage.setItem('gw_theme', cur);
    });
  }

  function bindEvents() {
    document.querySelectorAll('.tab-btn').forEach((btn) => {
      btn.addEventListener('click', () => switchTab(btn.dataset.tab));
    });

    ['inp-lan-ip', 'inp-gw-ip', 'inp-sub-urls', 'inp-tg-chat', 'inp-duck-sub'].forEach((id) => {
      trackDirty(qs(id));
    });
    qs('chk-allow-ru').addEventListener('change', () => {
      qs('chk-allow-ru').dataset.dirty = '1';
    });

    qs('btn-refresh').addEventListener('click', () => refreshStatus(true));
    qs('confirm-cancel').addEventListener('click', () => closeConfirm(false));
    qs('confirm-ok').addEventListener('click', () => closeConfirm(true));
    qs('job-close').addEventListener('click', () => {
      qs('job-modal').style.display = 'none';
      refreshStatus(true);
    });

    document.addEventListener('keydown', (e) => {
      if (e.key !== 'Escape') return;
      if (qs('confirm-modal').style.display === 'flex') {
        closeConfirm(false);
      } else if (qs('console-modal').style.display === 'flex') {
        closeConsoleModal();
      } else if (qs('lxc-create-modal').style.display === 'flex') {
        qs('lxc-create-modal').style.display = 'none';
      }
    });

    // Overview quick actions & Homelab cards
    qs('btn-ov-go-lxc').addEventListener('click', () => switchTab('lxc'));
    qs('inp-groups-filter').addEventListener('input', () => {
      if (state.status) renderProxyGroups(state.status);
    });

    qs('btn-trace').addEventListener('click', async () => {
      const box = qs('trace-box');
      box.style.display = 'block';
      box.textContent = 'Проверка DNS, IP выхода и задержек...';
      try {
        const res = await api('trace', {});
        const t = res.trace || {};
        const d = res.dns || {};
        const l = res.latency_ms || {};
        const ms = (v) => (Number(v) > 0 ? `${v} мс` : 'таймаут');
        box.innerHTML = `
          <div><strong>Выходной IP:</strong> <span class="mono">${esc(t.ip || '—')}</span> (${esc(t.loc || '?')} / ${esc(t.colo || '?')}, WARP: ${esc(t.warp || 'off')})</div>
          <div style="margin-top:0.35rem"><strong>DNS Fake-IP (chatgpt.com):</strong> <span class="mono">${esc(d.chatgpt || '—')}</span> • <strong>ya.ru:</strong> <span class="mono">${esc(d.yaru || '—')}</span> • <strong>DDR Block:</strong> ${d.ddr_block ? 'OK' : 'WARN'}</div>
          <div style="margin-top:0.35rem"><strong>Задержка:</strong> RU Direct ${esc(ms(l.ru))} • Cloudflare ${esc(ms(l.cf))} • YouTube ${esc(ms(l.yt))} • OpenAI ${esc(ms(l.ai))}</div>
        `;
      } catch (err) {
        box.textContent = `Ошибка: ${err.message}`;
      }
    });

    qs('btn-restart-gw').addEventListener('click', () => runJob('Перезапуск шлюза и AdGuard Home', 'restart'));
    qs('btn-doctor').addEventListener('click', () => runJob('Комплексная диагностика Doctor', 'doctor'));
    qs('btn-ov-apply').addEventListener('click', () => runJob('Применение конфигурации ядра', 'apply_core'));
    qs('btn-net-apply').addEventListener('click', () => runJob('Применение конфигурации ядра', 'apply_core'));
    qs('btn-px-apply').addEventListener('click', () => runJob('Применение конфигурации ядра', 'apply_core'));

    qs('ov-homelab-grid').addEventListener('click', async (e) => {
      const copyBtn = e.target.closest('[data-copy]');
      if (copyBtn) {
        copyText(copyBtn.dataset.copy, 'Сетевой путь скопирован');
        return;
      }
      const btn = e.target.closest('[data-hl-act]');
      if (!btn) return;
      const modId = btn.dataset.hlId;
      const act = btn.dataset.hlAct;
      if (act === 'remove') {
        const extra = modId === 'caddy' ? ' (также переведёт Web Dashboard на встроенный порт :8095)' : '';
        const ok = await confirmDialog('Отключить модуль?', `Отключить модуль "${modId}"${extra}? Данные сохранятся на диске.`);
        if (!ok) return;
      }
      const titles = {
        start: `Запуск модуля ${modId}`,
        stop: `Остановка модуля ${modId}`,
        restart: `Перезапуск модуля ${modId}`,
        install: `Установка модуля ${modId}`,
        update: `Обновление модуля ${modId}`,
        remove: `Отключение модуля ${modId}`,
      };
      runJob(titles[act] || `Homelab ${modId}`, 'homelab_action', modId, act);
    });

    // Network & Core
    qs('btn-core-mihomo').addEventListener('click', async () => {
      if (await confirmDialog('Сменить ядро?', 'Переключиться на Mihomo и пересобрать конфигурацию?')) {
        runJob('Переключение на Mihomo', 'set_core', 'mihomo');
      }
    });
    qs('btn-core-singbox').addEventListener('click', async () => {
      if (await confirmDialog('Сменить ядро?', 'Переключиться на Sing-Box Extended и пересобрать конфигурацию?')) {
        runJob('Переключение на Sing-Box Extended', 'set_core', 'singbox');
      }
    });
    qs('btn-ui-metacubexd').addEventListener('click', () => runJob('Переключение UI на MetaCubeXD', 'set_ui', 'metacubexd'));
    qs('btn-ui-zashboard').addEventListener('click', () => runJob('Переключение UI на Zashboard', 'set_ui', 'zashboard'));

    qs('btn-ks-toggle').addEventListener('click', async () => {
      const next = state.status?.network?.killswitch ? 'off' : 'on';
      try {
        const res = await api('set_killswitch', { mode: next });
        if (!res.ok) throw new Error(res.error || 'Ошибка Kill-Switch');
        if (state.status?.network) {
          state.status.network.killswitch = Boolean(res.enabled);
          renderNetwork(state.status);
        }
        toast(res.enabled ? 'Kill-Switch включён' : 'Kill-Switch выключен');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('btn-dhcp-toggle').addEventListener('click', async () => {
      const next = state.status?.adguard?.dhcp_enabled ? 'off' : 'on';
      const label = next === 'on' ? 'включить встроенный DHCP AdGuard Home' : 'выключить DHCP AdGuard Home';
      if (!(await confirmDialog('Изменить DHCP?', `Вы действительно хотите ${label}?`))) return;
      try {
        const res = await api('set_dhcp', { mode: next });
        if (!res.ok) throw new Error(res.error || 'Ошибка DHCP');
        toast(res.enabled ? 'DHCP AdGuard Home включён' : 'DHCP AdGuard Home выключен');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('frm-network').addEventListener('submit', async (e) => {
      e.preventDefault();
      const lan_ip = qs('inp-lan-ip').value.trim();
      const gw_ip = qs('inp-gw-ip').value.trim();
      if (!(await confirmDialog('Применить IP-адреса?', `Назначить LAN IP ${lan_ip} и шлюз ${gw_ip}? При смене LAN IP откройте панель по новому адресу.`))) return;
      try {
        const res = await api('set_network', { lan_ip, gw_ip });
        if (!res.ok) throw new Error(res.error || 'Ошибка настройки сети');
        qs('inp-lan-ip').dataset.dirty = '';
        qs('inp-gw-ip').dataset.dirty = '';
        toast(res.ip_changed ? `IP изменён на ${res.new_ip}` : 'Сетевые настройки обновлены');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    // Proxies & Routes
    document.querySelectorAll('[data-inspect-preset]').forEach((btn) => {
      btn.addEventListener('click', () => {
        qs('inp-inspect-domain').value = btn.dataset.inspectPreset;
        qs('frm-inspect').requestSubmit();
      });
    });

    qs('frm-inspect').addEventListener('submit', async (e) => {
      e.preventDefault();
      const domain = qs('inp-inspect-domain').value.trim();
      if (!domain) return;
      const box = qs('inspect-result');
      box.style.display = 'block';
      box.textContent = 'Проверка маршрута домена...';
      try {
        const r = await api('domain_inspect', { domain });
        if (!r.ok) throw new Error(r.error || 'Ошибка проверки');
        box.innerHTML = `
          <div><strong>Домен:</strong> <span class="mono">${esc(r.domain)}</span> (${esc(r.suffix)}) • <strong>Вердикт:</strong> ${badgeHtml(r.verdict.toUpperCase(), r.verdict === 'proxy' ? 'ok' : (r.verdict === 'blocked' ? 'err' : 'warn'))}</div>
          <div style="margin-top:0.35rem"><strong>Список:</strong> ${esc(r.list_source)} • <strong>DNS Ответ:</strong> <span class="mono">${esc(r.resolved_ip || '—')}</span></div>
          <div style="margin-top:0.35rem"><strong>Через прокси:</strong> HTTP ${esc(r.proxy_http)} (${esc(r.proxy_ms)} мс) • <strong>Напрямую:</strong> HTTP ${esc(r.direct_http)} (${esc(r.direct_ms)} мс)</div>
        `;
      } catch (err) {
        box.textContent = `Ошибка: ${err.message}`;
      }
    });

    qs('frm-sub').addEventListener('submit', async (e) => {
      e.preventDefault();
      try {
        const urls = qs('inp-sub-urls').value.trim();
        const allow_ru = qs('chk-allow-ru').checked ? 'yes' : 'no';
        const res = await api('set_subscription', { urls, allow_ru });
        if (!res.ok) throw new Error(res.error || 'Ошибка сохранения подписок');
        qs('inp-sub-urls').dataset.dirty = '';
        qs('chk-allow-ru').dataset.dirty = '';
        toast('Подписки сохранены. Нажмите «Применить конфиг ядра».');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('btn-warp-gen').addEventListener('click', () => {
      const lic = qs('inp-warp-lic').value.trim();
      runJob('Генерация и активация Amnezia WARP 2.0', 'warp_generate', lic);
    });
    qs('btn-warp-off').addEventListener('click', () => runJob('Отключение WARP 2.0', 'warp_disable'));

    qs('frm-node-add').addEventListener('submit', async (e) => {
      e.preventDefault();
      const uri = qs('inp-node-uri').value.trim();
      if (!uri) return;
      try {
        const res = await api('node_add', { uri });
        if (!res.ok) throw new Error(res.error || 'Ошибка добавления ключа');
        qs('inp-node-uri').value = '';
        toast('Ключ добавлен');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('px-nodes-body').addEventListener('click', async (e) => {
      const btn = e.target.closest('[data-node-del]');
      if (!btn) return;
      try {
        const res = await api('node_delete', { index: Number(btn.dataset.nodeDel) });
        if (!res.ok) throw new Error(res.error || 'Ошибка удаления');
        toast('Ключ удалён');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    const addDomainForm = (formId, inputId, listName) => {
      qs(formId).addEventListener('submit', async (e) => {
        e.preventDefault();
        const domain = qs(inputId).value.trim();
        if (!domain) return;
        try {
          const res = await api('domain_rule', { action: 'add', list: listName, domain });
          if (!res.ok) throw new Error(res.error || 'Ошибка добавления домена');
          qs(inputId).value = '';
          toast(`Домен ${res.domain} добавлен`);
          refreshStatus(true);
        } catch (err) {
          toast(err.message, 'err');
        }
      });
    };
    addDomainForm('frm-dom-proxy', 'inp-dom-proxy', 'proxy');
    addDomainForm('frm-dom-direct', 'inp-dom-direct', 'direct');

    ['chips-proxy', 'chips-direct'].forEach((cid) => {
      qs(cid).addEventListener('click', async (e) => {
        const btn = e.target.closest('[data-dom-del]');
        if (!btn) return;
        try {
          const res = await api('domain_rule', {
            action: 'del',
            list: btn.dataset.domList,
            domain: btn.dataset.domDel,
          });
          if (!res.ok) throw new Error(res.error || 'Ошибка удаления');
          toast(`Удалён ${btn.dataset.domDel}`);
          refreshStatus(true);
        } catch (err) {
          toast(err.message, 'err');
        }
      });
    });

    qs('inp-dev-filter').addEventListener('input', () => {
      if (state.status) renderDevices(state.status);
    });

    qs('frm-dev-add').addEventListener('submit', async (e) => {
      e.preventDefault();
      try {
        const res = await api('device_rule', {
          ip: qs('inp-dev-ip').value.trim(),
          mode: qs('inp-dev-mode').value,
        });
        if (!res.ok) throw new Error(res.error || 'Ошибка правила устройства');
        qs('inp-dev-ip').value = '';
        toast(`Правило для ${res.ip} сохранено`);
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('px-devices-body').addEventListener('click', async (e) => {
      const btn = e.target.closest('[data-dev-ip]');
      if (!btn) return;
      try {
        const res = await api('device_rule', { ip: btn.dataset.devIp, mode: btn.dataset.devMode });
        if (!res.ok) throw new Error(res.error || 'Ошибка правила');
        toast(`Режим ${res.ip}: ${res.mode}`);
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    // LXC Studio Events
    qs('btn-lxc-open-create').addEventListener('click', () => openLxcWizard(''));
    qs('btn-lxc-doctor').addEventListener('click', () => runJob('Проверка и самоисцеление подсистемы LXC', 'lxc_doctor'));
    qs('btn-lxc-refresh-cat').addEventListener('click', async () => {
      await loadCatalog(true);
      toast('Официальный каталог LXC обновлён');
    });
    qs('inp-lxc-filter').addEventListener('input', () => {
      if (state.status) renderLxc(state.status);
    });

    qs('lxc-cards-container').addEventListener('click', async (e) => {
      const qOs = e.target.closest('[data-lxc-quick-os]');
      if (qOs) {
        openLxcWizard(qOs.dataset.lxcQuickOs);
        return;
      }

      const cp = e.target.closest('[data-copy]');
      if (cp) {
        copyText(cp.dataset.copy, 'IP-адрес скопирован');
        return;
      }

      const conBtn = e.target.closest('[data-lxc-console]');
      if (conBtn) {
        openConsole(conBtn.dataset.lxcConsole);
        return;
      }

      const qSnap = e.target.closest('[data-lxc-quicksnap]');
      if (qSnap) {
        const ct = qSnap.dataset.lxcQuicksnap;
        state.expandedCts[ct] = true;
        state.ctSubTab[ct] = 'snaps';
        if (state.status) renderLxc(state.status);
        runJob(`Создание снимка ${ct}`, 'lxc_snap_create', ct, 'Быстрый снимок из панели');
        return;
      }

      const togBtn = e.target.closest('[data-lxc-toggle]');
      if (togBtn) {
        const ct = togBtn.dataset.lxcToggle;
        state.expandedCts[ct] = !state.expandedCts[ct];
        if (state.status) renderLxc(state.status);
        return;
      }

      const subBtn = e.target.closest('[data-ct-sub]');
      if (subBtn) {
        state.ctSubTab[subBtn.dataset.ctName] = subBtn.dataset.ctSub;
        if (state.status) renderLxc(state.status);
        return;
      }

      const presetBtn = e.target.closest('[data-exec-preset]');
      if (presetBtn) {
        const ct = presetBtn.dataset.execPreset;
        const cmd = presetBtn.dataset.execCmd;
        const inp = document.querySelector(`[data-exec-input="${ct}"]`);
        if (inp) inp.value = cmd;
        await executeLxcCommand(ct, cmd);
        return;
      }

      const cfgSave = e.target.closest('[data-cfg-save], [data-cfg-restart]');
      if (cfgSave) {
        const ct = cfgSave.dataset.cfgSave || cfgSave.dataset.cfgRestart;
        const doRestart = Boolean(cfgSave.dataset.cfgRestart);
        const form = document.querySelector(`[data-cfg-form="${ct}"]`);
        if (!form) return;
        try {
          const payload = {
            name: ct,
            mem_limit: form.querySelector('[name="mem_limit"]').value.trim(),
            cpu_limit: form.querySelector('[name="cpu_limit"]').value.trim(),
            root_pass: form.querySelector('[name="root_pass"]').value,
            autostart: form.querySelector('[name="autostart"]').checked ? 'on' : 'off',
            storage_mount: form.querySelector('[name="storage_mount"]').checked ? 'yes' : 'no',
            nesting: form.querySelector('[name="nesting"]').checked ? 'yes' : 'no',
            restart: doRestart ? 'yes' : 'no',
          };
          const res = await api('lxc_config', payload);
          if (!res.ok) throw new Error(res.error || 'Ошибка сохранения настроек');
          form.querySelector('[name="root_pass"]').value = '';
          toast(doRestart ? `Настройки ${ct} применены и контейнер перезапущен` : `Настройки ${ct} сохранены`);
          refreshStatus(true);
        } catch (err) {
          toast(err.message, 'err');
        }
        return;
      }

      const delBtn = e.target.closest('[data-lxc-delete]');
      if (delBtn) {
        const ct = delBtn.dataset.lxcDelete;
        if (await confirmDialog('Удалить контейнер?', `Контейнер «${ct}», его диски и все снимки будут безвозвратно удалены! Продолжить?`)) {
          delete state.expandedCts[ct];
          runJob(`Удаление контейнера ${ct}`, 'lxc_delete', ct);
        }
        return;
      }

      const actBtn = e.target.closest('[data-lxc-act]');
      if (actBtn) {
        const ct = actBtn.dataset.lxcCt;
        const act = actBtn.dataset.lxcAct;
        if (act.startsWith('snap_restore:')) {
          const sn = act.slice('snap_restore:'.length);
          if (!(await confirmDialog('Откатить контейнер?', `Откатить «${ct}» к снимку ${sn}? Несохранённые изменения после снимка будут потеряны.`))) return;
        } else if (act.startsWith('snap_delete:')) {
          const sn = act.slice('snap_delete:'.length);
          if (!(await confirmDialog('Удалить снимок?', `Удалить снимок ${sn} контейнера «${ct}»?`))) return;
        }
        runJob(`LXC ${ct}: ${act}`, 'lxc_action', ct, act);
      }
    });

    qs('lxc-cards-container').addEventListener('submit', async (e) => {
      const snapForm = e.target.closest('[data-snap-form]');
      if (snapForm) {
        e.preventDefault();
        const ct = snapForm.dataset.snapForm;
        const cmtInp = snapForm.querySelector(`[data-snap-comment="${ct}"]`);
        const comment = (cmtInp?.value || '').trim();
        if (cmtInp) cmtInp.value = '';
        runJob(`Создание снимка ${ct}`, 'lxc_snap_create', ct, comment);
        return;
      }

      const execForm = e.target.closest('[data-exec-form]');
      if (execForm) {
        e.preventDefault();
        const ct = execForm.dataset.execForm;
        const inp = execForm.querySelector(`[data-exec-input="${ct}"]`);
        const cmd = (inp?.value || '').trim();
        if (cmd) await executeLxcCommand(ct, cmd);
        return;
      }

      const cloneForm = e.target.closest('[data-clone-form]');
      if (cloneForm) {
        e.preventDefault();
        const src = cloneForm.dataset.cloneForm;
        const dstInp = cloneForm.querySelector(`[data-clone-target="${src}"]`);
        const dst = (dstInp?.value || '').trim();
        if (!dst) return;
        if (await confirmDialog('Клонировать контейнер?', `Создать клон «${dst}» из «${src}»? (Исходный контейнер на время копирования будет остановлен и вновь запущен.)`)) {
          runJob(`Клонирование ${src} -> ${dst}`, 'lxc_clone', src, dst);
        }
      }
    });

    async function executeLxcCommand(ctName, cmd) {
      const outEl = qs(`exec-out-${ctName}`);
      state.execOutputs[ctName] = `Выполнение: ${cmd}...`;
      if (outEl) outEl.textContent = state.execOutputs[ctName];
      try {
        const res = await api('lxc_exec', { name: ctName, cmd });
        if (!res.ok) throw new Error(res.error || 'Ошибка выполнения');
        const txt = `[exit ${res.exit_code}]\n${res.output || '(пустой вывод)'}`;
        state.execOutputs[ctName] = txt;
        if (outEl) outEl.textContent = txt;
      } catch (err) {
        state.execOutputs[ctName] = `Ошибка: ${err.message}`;
        if (outEl) outEl.textContent = state.execOutputs[ctName];
      }
    }

    // LXC Creation Wizard Modal Events
    const closeCreate = () => { qs('lxc-create-modal').style.display = 'none'; };
    qs('btn-lxc-create-x').addEventListener('click', closeCreate);
    qs('btn-lxc-create-cancel').addEventListener('click', closeCreate);
    qs('btn-lxc-cat-reload').addEventListener('click', () => loadCatalog(true));

    qs('inp-cat-search').addEventListener('input', renderCatalogGrid);
    qs('sel-cat-variant').addEventListener('change', renderCatalogGrid);
    document.querySelectorAll('#cat-group-btns [data-cat]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.catCategory = btn.dataset.cat;
        document.querySelectorAll('#cat-group-btns [data-cat]').forEach((b) => {
          b.classList.toggle('active', b === btn);
        });
        renderCatalogGrid();
      });
    });

    qs('lxc-distro-grid').addEventListener('click', (e) => {
      const tile = e.target.closest('[data-pick-distro]');
      if (!tile) return;
      syncDistroReleases(tile.dataset.pickDistro);
      document.querySelectorAll('#lxc-distro-grid .distro-tile').forEach((t) => {
        t.classList.toggle('selected', t.dataset.pickDistro === state.selectedDistro);
      });
    });

    qs('sel-lxc-release').addEventListener('change', syncReleaseVariants);
    qs('chk-lxc-manual-os').addEventListener('change', (e) => {
      const manual = e.target.checked;
      qs('sel-lxc-release').style.display = manual ? 'none' : '';
      qs('inp-lxc-release-manual').style.display = manual ? '' : 'none';
    });

    document.querySelectorAll('input[name="lxc_net_mode"]').forEach((r) => {
      r.addEventListener('change', () => {
        const isMac = r.value === 'macvlan' && r.checked;
        qs('rcard-nat').classList.toggle('selected', !isMac);
        qs('rcard-macvlan').classList.toggle('selected', isMac);
        if (isMac) {
          qs('inp-lxc-ip').placeholder = '192.168.1.150/24';
          qs('inp-lxc-gw').placeholder = state.status?.network?.gw_ip || '192.168.1.1';
          qs('inp-lxc-dns').placeholder = state.status?.network?.lan_ip || '192.168.1.82';
        } else {
          qs('inp-lxc-ip').placeholder = '10.0.3.50/24';
          qs('inp-lxc-gw').placeholder = '10.0.3.1';
          qs('inp-lxc-dns').placeholder = '10.0.3.1';
        }
      });
    });

    qs('chk-lxc-static-ip').addEventListener('change', (e) => {
      qs('lxc-static-ip-fields').style.display = e.target.checked ? '' : 'none';
    });

    document.querySelectorAll('[data-mem-preset]').forEach((b) => {
      b.addEventListener('click', () => { qs('inp-lxc-mem').value = b.dataset.memPreset; });
    });
    document.querySelectorAll('[data-cpu-preset]').forEach((b) => {
      b.addEventListener('click', () => { qs('inp-lxc-cpu').value = b.dataset.cpuPreset; });
    });

    qs('frm-lxc-create').addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = qs('inp-lxc-name').value.trim();
      if (!/^[A-Za-z0-9_-]+$/.test(name)) {
        toast('Имя контейнера может содержать только латиницу, цифры, - и _', 'err');
        return;
      }
      const manual = qs('chk-lxc-manual-os').checked;
      const distro = qs('sel-lxc-distro').value.trim();
      const release = manual ? qs('inp-lxc-release-manual').value.trim() : qs('sel-lxc-release').value;
      const variant = qs('sel-lxc-variant').value || 'default';
      if (!distro || !release) {
        toast('Укажите дистрибутив и релиз ОС', 'err');
        return;
      }
      const netMode = document.querySelector('input[name="lxc_net_mode"]:checked')?.value || 'nat';
      const useStatic = qs('chk-lxc-static-ip').checked;
      const startNow = qs('chk-lxc-startnow').checked;

      const spec = {
        name,
        distro,
        release,
        variant,
        net_mode: netMode,
        static_ip: useStatic ? qs('inp-lxc-ip').value.trim() : '',
        static_gw: useStatic ? qs('inp-lxc-gw').value.trim() : '',
        static_dns: useStatic ? qs('inp-lxc-dns').value.trim() : '',
        mem_limit: qs('inp-lxc-mem').value.trim(),
        cpu_limit: qs('inp-lxc-cpu').value.trim(),
        autostart: qs('chk-lxc-autostart').checked,
        storage_mount: qs('chk-lxc-storage').checked,
        nesting: qs('chk-lxc-nesting').checked,
        start_now: startNow,
        root_pass: qs('inp-lxc-rootpass').value,
      };
      qs('inp-lxc-rootpass').value = '';
      closeCreate();
      runJob(
        `Создание контейнера ${name} (${distro} ${release})`,
        'lxc_create',
        JSON.stringify(spec),
        '',
        startNow ? name : ''
      );
    });

    // Console Modal Events
    qs('btn-con-close').addEventListener('click', () => {
      closeConsoleModal();
    });
    qs('btn-con-fullscreen').addEventListener('click', () => {
      qs('console-modal-box').classList.toggle('fullscreen');
    });
    qs('btn-con-reconnect').addEventListener('click', () => {
      if (state.consoleCt) openConsole(state.consoleCt);
    });
    qs('btn-con-newtab').addEventListener('click', async (e) => {
      if (!state.consoleCt) return;
      e.preventDefault();
      const win = window.open('about:blank', '_blank');
      try {
        const res = await api('lxc_console_token', { name: state.consoleCt });
        if (!res.ok) throw new Error(res.error || 'Не удалось получить токен консоли');
        if (win && !win.closed) {
          win.location.href = res.url;
        } else {
          window.open(res.url, '_blank', 'noopener');
        }
      } catch (err) {
        if (win && !win.closed) win.close();
        toast(err.message, 'err');
      }
    });

    // Storage & SSL
    qs('btn-st-clean').addEventListener('click', async () => {
      try {
        const res = await api('storage_clean_cache', {});
        if (!res.ok) throw new Error(res.error || 'Ошибка очистки');
        toast(res.message || 'Буферы очищены');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });
    qs('btn-st-unlock').addEventListener('click', () => runJob('Разблокировка накопителя LUKS2', 'storage_unlock'));
    qs('btn-st-lock').addEventListener('click', async () => {
      if (await confirmDialog('Извлечь внешний диск?', 'Остановить зависимые сервисы, размонтировать /srv/storage и закрыть LUKS2?')) {
        runJob('Безопасное извлечение накопителя', 'storage_lock');
      }
    });

    qs('btn-ssl-local').addEventListener('click', async () => {
      if (await confirmDialog('Переключить на Local PKI?', 'Перевести HTTPS на локальный центр сертификации (*.lan) и перезагрузить Caddy?')) {
        runJob('Переключение HTTPS на Local PKI (*.lan)', 'ssl_local');
      }
    });
    qs('btn-ssl-renew').addEventListener('click', () => runJob('Продление Let\'s Encrypt сертификата', 'ssl_renew'));
    qs('frm-ssl-duckdns').addEventListener('submit', async (e) => {
      e.preventDefault();
      const sub = qs('inp-duck-sub').value.trim();
      const tok = qs('inp-duck-tok').value.trim();
      if (!sub) {
        toast('Укажите субдомен DuckDNS', 'err');
        return;
      }
      if (await confirmDialog('Выпустить Wildcard Let\'s Encrypt?', `Запросить сертификат для *.${sub}.duckdns.org через DuckDNS DNS-01 (может занять ~60 сек)?`)) {
        qs('inp-duck-sub').dataset.dirty = '';
        runJob(`Let's Encrypt Wildcard (*.${sub}.duckdns.org)`, 'ssl_duckdns', sub, tok);
      }
    });

    // System, Telegram, Backup, Password, Git Update, Logs
    qs('frm-telegram').addEventListener('submit', async (e) => {
      e.preventDefault();
      try {
        const res = await api('set_telegram', {
          action: 'save',
          token: qs('inp-tg-token').value.trim(),
          chat_id: qs('inp-tg-chat').value.trim(),
        });
        if (!res.ok) throw new Error(res.error || 'Ошибка Telegram');
        qs('inp-tg-token').value = '';
        qs('inp-tg-chat').dataset.dirty = '';
        toast(res.message || 'Сохранено', res.sent === false ? 'err' : 'ok');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('btn-tg-test').addEventListener('click', async () => {
      try {
        const res = await api('set_telegram', { action: 'test' });
        if (!res.ok) throw new Error(res.error || 'Тест не прошёл');
        toast(res.message || 'Сообщение отправлено');
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('btn-tg-disable').addEventListener('click', async () => {
      if (!(await confirmDialog('Отключить Telegram?', 'Удалить токен бота и Chat ID из настроек?'))) return;
      try {
        const res = await api('set_telegram', { action: 'disable' });
        toast(res.message || 'Отключено');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('btn-bak-create').addEventListener('click', () => runJob('Создание единого бэкапа', 'backup_create'));
    qs('btn-bak-tg').addEventListener('click', () => runJob('Бэкап и отправка в Telegram', 'backup_telegram'));
    qs('btn-bak-restore').addEventListener('click', async () => {
      if (await confirmDialog('Восстановить из бэкапа?', 'Восстановить конфигурацию из /root/gateway_backup.tar.gz?')) {
        runJob('Восстановление из единого бэкапа', 'backup_restore');
      }
    });

    const bindCron = (btnId, target) => {
      qs(btnId).addEventListener('click', async () => {
        const cur = Boolean(state.status?.cron?.[target]);
        try {
          const res = await api('set_cron', { target, enabled: cur ? 'no' : 'yes' });
          if (!res.ok) throw new Error(res.error || 'Ошибка cron');
          if (state.status?.cron) {
            state.status.cron[target] = Boolean(res.enabled);
            renderSystem(state.status);
          }
          toast(`${target}: ${res.enabled ? 'включён' : 'выключен'}`);
          refreshStatus(true);
        } catch (err) {
          toast(err.message, 'err');
        }
      });
    };
    bindCron('btn-cron-wd', 'watchdog');
    bindCron('btn-cron-au', 'autoupdate');

    qs('frm-passwd').addEventListener('submit', async (e) => {
      e.preventDefault();
      const p1 = qs('inp-pw1').value;
      const p2 = qs('inp-pw2').value;
      if (p1.length < 4) {
        toast('Пароль должен быть не короче 4 символов', 'err');
        return;
      }
      if (p1 !== p2) {
        toast('Пароли не совпадают', 'err');
        return;
      }
      if (!(await confirmDialog('Сменить мастер-пароль?', 'Обновить пароль на всех сервисах (потребуется повторный вход в панель)?'))) return;
      try {
        const res = await api('set_password', { password: p1 });
        if (!res.ok) throw new Error(res.error || 'Ошибка смены пароля');
        qs('inp-pw1').value = '';
        qs('inp-pw2').value = '';
        toast(res.message || 'Пароль обновлён');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('btn-upd-check').addEventListener('click', async () => {
      try {
        const r = await api('update_check', {});
        if (!r.ok) throw new Error(r.error || 'Ошибка проверки Git');
        const box = qs('sys-git-commits');
        if (r.status === 'UPDATE_AVAILABLE' && Array.isArray(r.commits) && r.commits.length) {
          box.style.display = 'block';
          box.textContent = r.commits.join('\n');
        } else {
          box.style.display = 'none';
        }
        toast(r.status === 'UPDATE_AVAILABLE' ? `Найдено новых коммитов: ${r.behind}` : 'Обновлений пока нет');
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    qs('btn-upd-run').addEventListener('click', async () => {
      if (await confirmDialog('Обновить шлюз (gw update)?', 'Выполнить обновление кода из GitHub, ядер и модулей Homelab?')) {
        runJob('Полное обновление (gw update)', 'update');
      }
    });

    qs('btn-log-load').addEventListener('click', async () => {
      const target = qs('sel-log-target').value;
      const lines = Number(qs('sel-log-lines').value || 150);
      const view = qs('sys-log-view');
      view.textContent = 'Загрузка лога...';
      try {
        const res = await api('get_logs', { target, lines });
        if (!res.ok) throw new Error(res.error || 'Ошибка чтения лога');
        state.rawLogText = res.log || '(Лог пуст)';
        renderFilteredLogs();
      } catch (err) {
        state.rawLogText = '';
        view.textContent = `Ошибка: ${err.message}`;
      }
    });

    qs('inp-log-filter').addEventListener('input', renderFilteredLogs);
    qs('btn-log-copy').addEventListener('click', () => {
      copyText(qs('sys-log-view').textContent || '', 'Текст лога скопирован');
    });
  }

  initTheme();
  bindEvents();
  refreshStatus(true);
  state.pollTimer = setInterval(() => refreshStatus(false), 15000);
})();
