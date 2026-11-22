'use strict';

(() => {
  const CAT_GROUPS = {
    popular: new Set(['alpine', 'debian', 'ubuntu', 'archlinux', 'fedora', 'almalinux', 'rockylinux']),
    light: new Set(['alpine', 'busybox', 'voidlinux', 'devuan']),
    server: new Set(['debian', 'ubuntu', 'centos', 'almalinux', 'rockylinux', 'oracle', 'amazonlinux', 'opensuse', 'alt']),
    sec: new Set(['kali', 'openwrt', 'nixos', 'gentoo', 'archlinux', 'cachyos']),
  };

  const HOMELAB_META = {
    caddy: {
      desc: 'Локальный PKI, HTTPS и обратный прокси',
      svg: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#10b981" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2 20 6v6c0 5.5-3.5 9.8-8 11-4.5-1.2-8-5.5-8-11V6l8-4Z"/><rect x="9" y="10.5" width="6" height="5" rx="1"/><path d="M10 10.5V9a2 2 0 1 1 4 0v1.5"/></svg>',
    },
    samba: {
      desc: 'Сетевые диски SMB для Windows, macOS и ТВ',
      svg: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#38bdf8" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6Z"/><path d="M8 13h8M12 10v6"/></svg>',
    },
    vaultwarden: {
      desc: 'Менеджер паролей (совместим с Bitwarden)',
      svg: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#818cf8" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2 20 5.5v6.5c0 5.2-3.4 9.5-8 10.8C7.4 21.5 4 17.2 4 12V5.5L12 2Z"/><circle cx="12" cy="11" r="2.2"/><path d="M12 13.2V16"/></svg>',
    },
    forgejo: {
      desc: 'Локальный Git-сервер и репозитории кода',
      svg: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fbbf24" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="2.5"/><circle cx="18" cy="8" r="2.5"/><circle cx="6" cy="18" r="2.5"/><path d="M6 8.5v7M8.5 6h5a4.5 4.5 0 0 1 4.5 4.5"/></svg>',
    },
    code: {
      desc: 'VS Code IDE прямо в окне браузера',
      svg: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#38bdf8" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="m17 3 4 2.5v13L17 21l-9-8-4 3-2-1.5v-5L4 8l4 3 9-8Z"/><path d="M17 7.5v9L11.5 12 17 7.5Z"/></svg>',
    },
    ytdlp: {
      desc: 'Загрузчик видео и аудио (YouTube / yt-dlp)',
      svg: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#fb7185" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="4"/><polygon points="10 9 16 12 10 15 10 9" fill="#fb7185"/></svg>',
    },
    torrent: {
      desc: 'Клиент торрентов в общем хранилище',
      svg: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#f87171" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11m0 0-4-4m4 4 4-4"/><path d="M5 18h14"/><circle cx="12" cy="5" r="2"/></svg>',
    },
  };

  const DISTRO_THEME = {
    alpine: ['#0d597f', 'A'],
    debian: ['#d70a53', 'D'],
    ubuntu: ['#e95420', 'U'],
    archlinux: ['#1793d1', 'Ar'],
    kali: ['#367bf0', 'K'],
    fedora: ['#51a2da', 'F'],
    almalinux: ['#10b981', 'Al'],
    rockylinux: ['#10b981', 'R'],
    centos: ['#932279', 'C'],
    opensuse: ['#73ba25', 'S'],
    gentoo: ['#8b5cf6', 'G'],
    nixos: ['#5277c3', 'Nx'],
    voidlinux: ['#478061', 'V'],
    openwrt: ['#00b5e2', 'Ow'],
    busybox: ['#f59e0b', 'Bb'],
    oracle: ['#ef4444', 'Or'],
    devuan: ['#a855f7', 'Dv'],
    cachyos: ['#06b6d4', 'Ca'],
    mint: ['#69b53f', 'M'],
  };

  const STORAGE_COLORS = ['#38bdf8', '#818cf8', '#10b981', '#f59e0b', '#f43f5e', '#06b6d4', '#a855f7', '#64748b'];

  const state = {
    status: null,
    activeTab: 'overview',
    pollTimer: null,
    refreshing: false,
    pendingForceRefresh: false,
    confirmResolve: null,
    catalog: null,
    catCategory: 'all',
    selectedDistro: 'alpine',
    wizardStep: 1,
    expandedCts: {},
    ctSubTab: {},
    lxcDrafts: {},
    execOutputs: {},
    consoleCt: '',
    rawLogText: '',
    logLoaded: false,
    logSeverity: 'all',
    lastTrace: null,
    proxiesDirty: false,
    subRevealed: false,
    history: loadSparkHistory(),
    focusReturnMap: {},
    cmdItems: [],
    cmdIndex: 0,
    reconTimer: null,
  };

  function loadSparkHistory() {
    try {
      const raw = sessionStorage.getItem('gw_spark_hist');
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed && Array.isArray(parsed.ram) && Array.isArray(parsed.ct)) {
          return { ram: parsed.ram.slice(-24), ct: parsed.ct.slice(-24) };
        }
      }
    } catch (_e) {}
    return { ram: [], ct: [] };
  }

  function saveSparkHistory() {
    try {
      sessionStorage.setItem('gw_spark_hist', JSON.stringify(state.history));
    } catch (_e) {}
  }

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

  function svgIcon(id, cls = 'ic') {
    return `<svg class="${cls}" aria-hidden="true"><use href="#${id}"/></svg>`;
  }

  function pluralRu(n, forms) {
    const abs = Math.abs(Number(n) || 0) % 100;
    const n1 = abs % 10;
    if (abs > 10 && abs < 20) return `${n} ${forms[2]}`;
    if (n1 > 1 && n1 < 5) return `${n} ${forms[1]}`;
    if (n1 === 1) return `${n} ${forms[0]}`;
    return `${n} ${forms[2]}`;
  }

  function badgeHtml(text, tone, extraClass = '') {
    return `<span class="badge badge-${tone || 'muted'} ${extraClass}">${esc(text)}</span>`;
  }

  function hintDotHtml(text, ariaLabel = 'Пояснение') {
    return `<button class="hint-dot" type="button" data-hint="${esc(text)}" aria-label="${esc(ariaLabel)}">?</button>`;
  }

  function homelabIconSvg(id) {
    return HOMELAB_META[id]?.svg || svgIcon('i-lxc');
  }

  function distroIconSvg(distro) {
    const key = String(distro || '').toLowerCase();
    const entry = DISTRO_THEME[key];
    const color = entry ? entry[0] : '#38bdf8';
    const label = entry ? entry[1] : (key.slice(0, 2).toUpperCase() || 'LX');
    if (key === 'alpine') {
      return `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M3 17 9.5 7l4 6 2.5-3.5L21 17H3Z" stroke="${color}" stroke-width="2" stroke-linejoin="round" fill="${color}" fill-opacity="0.2"/></svg>`;
    }
    if (key === 'debian') {
      return `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 20a8 8 0 1 1 6.5-12.6 4.8 4.8 0 1 1-6.9 6.6 2.5 2.5 0 0 1 2.2-3.9" stroke="${color}" stroke-width="2" stroke-linecap="round"/></svg>`;
    }
    if (key === 'ubuntu') {
      return `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true"><circle cx="12" cy="12" r="5.5" stroke="${color}" stroke-width="2"/><circle cx="12" cy="4" r="2" fill="${color}"/><circle cx="5.2" cy="16" r="2" fill="${color}"/><circle cx="18.8" cy="16" r="2" fill="${color}"/></svg>`;
    }
    if (key === 'archlinux') {
      return `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3 4 20l4.8-2 3.2-5 3.2 5L20 20 12 3Z" stroke="${color}" stroke-width="1.9" stroke-linejoin="round" fill="${color}" fill-opacity="0.18"/></svg>`;
    }
    return `<svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><rect x="2" y="2" width="20" height="20" rx="6" fill="${color}" fill-opacity="0.18" stroke="${color}" stroke-width="1.6"/><text x="12" y="15.5" text-anchor="middle" font-size="9.5" font-weight="700" fill="${color}" font-family="system-ui,sans-serif">${esc(label)}</text></svg>`;
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

  function isValidIpv4(ip) {
    const m = String(ip || '').trim().match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
    if (!m) return false;
    return [m[1], m[2], m[3], m[4]].every((oct) => {
      const n = Number(oct);
      return Number.isInteger(n) && n >= 0 && n <= 255 && String(n) === oct;
    });
  }

  function isValidIpv4Cidr(val) {
    const parts = String(val || '').trim().split('/');
    if (parts.length !== 2) return false;
    if (!isValidIpv4(parts[0])) return false;
    const mask = Number(parts[1]);
    return Number.isInteger(mask) && mask >= 1 && mask <= 32 && /^\d+$/.test(parts[1]);
  }

  function extractHostCandidate(raw) {
    let s = String(raw || '').trim();
    s = s.replace(/^[a-zA-Z][a-zA-Z0-9+\-.]*:\/\//, '');
    s = s.split('/')[0].split('?')[0].split('#')[0];
    if (s.includes('@')) s = s.split('@').pop();
    if (s.startsWith('[')) {
      const end = s.indexOf(']');
      return end > 0 ? s.slice(0, end + 1) : s;
    }
    const colonIdx = s.indexOf(':');
    const lastColon = s.lastIndexOf(':');
    if (colonIdx > -1 && colonIdx === lastColon) {
      s = s.slice(0, colonIdx);
    }
    return s;
  }

  function isIpLiteral(rawHost) {
    const h = extractHostCandidate(rawHost);
    if (!h) return false;
    if (isValidIpv4(h)) return true;
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(h)) return true;
    if (h.includes(':') || /^\[.*\]$/.test(h)) return true;
    if (/^(0x[0-9a-f]+|\d+)$/i.test(h)) return true;
    return false;
  }

  function parseSizeToMb(str) {
    const m = String(str || '').trim().match(/^([0-9]+(?:[.,][0-9]+)?)\s*([KkMmGgTt])?(?:i?[Bb])?$/);
    if (!m) return 0;
    const num = parseFloat(m[1].replace(',', '.'));
    if (!Number.isFinite(num)) return 0;
    const u = (m[2] || 'M').toUpperCase();
    if (u === 'K') return num / 1024;
    if (u === 'G') return num * 1024;
    if (u === 'T') return num * 1024 * 1024;
    return num;
  }

  function parseDiskBytes(str) {
    const m = String(str || '').trim().match(/^([0-9]+(?:[.,][0-9]+)?)\s*([BbKkMmGgTt])?/);
    if (!m) return 0;
    const num = parseFloat(m[1].replace(',', '.'));
    if (!Number.isFinite(num)) return 0;
    const u = (m[2] || 'B').toUpperCase();
    if (u === 'K') return num * 1024;
    if (u === 'M') return num * 1024 * 1024;
    if (u === 'G') return num * 1024 * 1024 * 1024;
    if (u === 'T') return num * 1024 * 1024 * 1024 * 1024;
    return num;
  }

  function formatLeaseExpiry(val) {
    if (!val) return '—';
    const ts = Date.parse(val);
    if (!Number.isFinite(ts)) return esc(val);
    const diff = ts - Date.now();
    if (diff <= 0) return `<span title="${esc(val)}">Истекла</span>`;
    const mins = Math.floor(diff / 60000);
    const hrs = Math.floor(mins / 60);
    const remM = mins % 60;
    const lbl = hrs >= 24 ? `${Math.floor(hrs / 24)}д ${hrs % 24}ч` : (hrs > 0 ? `${hrs}ч ${remM}м` : `${mins}м`);
    return `<span title="${esc(val)}">Через ${esc(lbl)}</span>`;
  }

  function maskSubUrl(u) {
    try {
      const url = new URL(u);
      const path = url.pathname || '';
      const tail = path.length > 6 ? path.slice(-4) : '';
      return `${url.protocol}//${url.host}/••••${tail}`;
    } catch (_e) {
      if (u.length <= 18) return '••••';
      return `${u.slice(0, 14)}••••${u.slice(-4)}`;
    }
  }

  function isValidLxcMem(v) {
    return /^[1-9][0-9]*[KkMmGg]?$/.test(v);
  }

  function isValidLxcCpu(v) {
    return /^([1-9][0-9]*(\.[0-9]+)?|0\.[1-9][0-9]*)$/.test(v);
  }

  function radialGaugeHtml(pct, forceTone = '', labelOverride = '') {
    const val = Math.max(0, Math.min(100, Math.round(Number(pct) || 0)));
    const arcLen = 117.29;
    const offset = (arcLen * (1 - val / 100)).toFixed(2);
    const cls = forceTone || (val >= 90 ? 'err' : val >= 75 ? 'warn' : '');
    const text = labelOverride || `${val}%`;
    return `
      <div class="gauge-wrap" aria-hidden="true">
        <svg class="gauge-svg" viewBox="0 0 80 68">
          <circle class="gauge-track" cx="40" cy="38" r="28" stroke-dasharray="117.29 175.93" transform="rotate(150 40 38)"/>
          <circle class="gauge-arc ${cls}" cx="40" cy="38" r="28" stroke-dasharray="117.29 175.93" stroke-dashoffset="${offset}" transform="rotate(150 40 38)"/>
        </svg>
        <div class="gauge-text">${text}</div>
      </div>
    `;
  }

  function sparklineSvgHtml(values, gradId, strokeColor = '#38bdf8') {
    const arr = Array.isArray(values) && values.length ? values : [0, 0];
    const ptsArr = arr.length === 1 ? [arr[0], arr[0]] : arr;
    const w = 180;
    const h = 26;
    const pad = 2;
    const min = Math.min(...ptsArr, 0);
    const max = Math.max(...ptsArr, 100);
    const span = Math.max(1, max - min);
    const coords = ptsArr.map((v, i) => {
      const x = (i / (ptsArr.length - 1)) * w;
      const y = h - pad - ((v - min) / span) * (h - pad * 2);
      return [Number(x.toFixed(1)), Number(y.toFixed(1))];
    });
    let d = `M ${coords[0][0]} ${coords[0][1]}`;
    for (let i = 1; i < coords.length; i += 1) {
      const prev = coords[i - 1];
      const cur = coords[i];
      const mx = ((prev[0] + cur[0]) / 2).toFixed(1);
      d += ` Q ${prev[0]} ${prev[1]}, ${mx} ${((prev[1] + cur[1]) / 2).toFixed(1)}`;
    }
    const last = coords[coords.length - 1];
    d += ` L ${last[0]} ${last[1]}`;
    const areaD = `${d} L ${w} ${h} L 0 ${h} Z`;
    return `
      <div class="spark-wrap" aria-hidden="true">
        <svg class="spark-svg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
          <defs>
            <linearGradient id="${gradId}" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color="${strokeColor}" stop-opacity="0.32"/>
              <stop offset="100%" stop-color="${strokeColor}" stop-opacity="0"/>
            </linearGradient>
          </defs>
          <path d="${areaD}" fill="url(#${gradId})"/>
          <path d="${d}" fill="none" stroke="${strokeColor}" stroke-width="1.6" stroke-linecap="round"/>
        </svg>
      </div>
    `;
  }

  function toast(msg, type = 'ok') {
    const stack = qs('toast-stack');
    const el = document.createElement('div');
    const cls = type === 'err' ? 'toast-err' : (type === 'info' ? 'toast-info' : 'toast-ok');
    el.className = `toast ${cls}`;
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
    if (res.status === 401) {
      const err = new Error('Требуется повторная авторизация с новым паролем');
      err.status = 401;
      throw err;
    }
    const text = await res.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_err) {
      const err = new Error(`HTTP ${res.status}: некорректный ответ сервера`);
      err.status = res.status;
      throw err;
    }
    if (!res.ok) {
      const err = new Error(data.error || `HTTP ${res.status}`);
      err.status = res.status;
      throw err;
    }
    return data;
  }

  async function copyText(str, okMsg = 'Скопировано в буфер') {
    const val = String(str ?? '');
    if (!val) {
      toast('Нечего копировать', 'err');
      return false;
    }
    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
      try {
        await navigator.clipboard.writeText(val);
        toast(okMsg);
        return true;
      } catch (_err) {
        // Fallback below for HTTP LAN contexts
      }
    }
    try {
      const ta = document.createElement('textarea');
      ta.value = val;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      ta.style.top = '0';
      document.body.appendChild(ta);
      ta.select();
      ta.setSelectionRange(0, val.length);
      const ok = document.execCommand('copy');
      ta.remove();
      if (ok) {
        toast(okMsg);
        return true;
      }
    } catch (_e) {}
    toast('Не удалось скопировать в буфер — выделите текст вручную', 'err');
    return false;
  }

  function getFocusableElements(container) {
    if (!container) return [];
    return Array.from(
      container.querySelectorAll('a[href], button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])')
    ).filter((el) => el.offsetParent !== null || getComputedStyle(el).position === 'fixed');
  }

  function openModal(id, focusEl = null) {
    const modal = qs(id);
    if (!modal) return;
    if (modal.style.display !== 'flex') {
      state.focusReturnMap[id] = document.activeElement;
    }
    modal.style.display = 'flex';
    requestAnimationFrame(() => {
      const target = focusEl && !focusEl.disabled ? focusEl : getFocusableElements(modal)[0];
      if (target && typeof target.focus === 'function') target.focus();
    });
  }

  function closeModal(id) {
    const modal = qs(id);
    if (!modal) return;
    modal.style.display = 'none';
    const ret = state.focusReturnMap[id];
    delete state.focusReturnMap[id];
    if (ret && typeof ret.focus === 'function' && document.contains(ret)) {
      ret.focus();
    }
  }

  function confirmDialog(title, text) {
    return new Promise((resolve) => {
      state.confirmResolve = resolve;
      qs('confirm-title').textContent = title;
      qs('confirm-text').textContent = text;
      openModal('confirm-modal', qs('confirm-cancel'));
    });
  }

  function closeConfirm(answer) {
    closeModal('confirm-modal');
    if (state.confirmResolve) {
      const fn = state.confirmResolve;
      state.confirmResolve = null;
      fn(answer);
    }
  }

  function showReconnectModal(opts) {
    if (state.reconTimer) {
      clearInterval(state.reconTimer);
      state.reconTimer = null;
    }
    const { title, bodyHtml, url, autoCountdownSec = 0 } = opts;
    qs('recon-title').textContent = title;
    const bodyEl = qs('recon-body');
    const goEl = qs('recon-go');
    goEl.href = url || location.href;
    if (url) {
      goEl.textContent = 'Открыть панель';
      goEl.onclick = null;
    } else {
      goEl.textContent = 'Обновить страницу';
      goEl.onclick = (e) => {
        e.preventDefault();
        location.reload();
      };
    }

    if (autoCountdownSec > 0 && url) {
      let left = autoCountdownSec;
      bodyEl.innerHTML = `${bodyHtml}<div class="muted small tabular-nums" id="recon-cd" style="margin-top:0.6rem">Автопереход через ${left} сек...</div>`;
      state.reconTimer = setInterval(() => {
        left -= 1;
        const cdEl = qs('recon-cd');
        if (left <= 0) {
          clearInterval(state.reconTimer);
          state.reconTimer = null;
          location.href = url;
        } else if (cdEl) {
          cdEl.textContent = `Автопереход через ${left} сек...`;
        }
      }, 1000);
    } else {
      bodyEl.innerHTML = bodyHtml;
    }
    openModal('reconnect-modal', goEl);
  }

  function isModalOpen() {
    const ids = ['job-modal', 'confirm-modal', 'lxc-create-modal', 'console-modal', 'cmd-modal', 'mobile-more-sheet', 'reconnect-modal'];
    return ids.some((id) => qs(id)?.style.display === 'flex');
  }

  function hasOpenLxcDrawer() {
    return Object.keys(state.expandedCts).some((k) => Boolean(state.expandedCts[k]));
  }

  function hasActiveLxcDrafts() {
    if (state.activeTab === 'lxc' && hasOpenLxcDrawer()) {
      const lxcRoot = qs('lxc-cards-container');
      if (lxcRoot && lxcRoot.contains(document.activeElement)) return true;
      for (const ct of Object.keys(state.expandedCts)) {
        if (!state.expandedCts[ct]) continue;
        const sub = state.ctSubTab[ct] || 'snaps';
        if (sub === 'config') return true;
        const d = state.lxcDrafts[ct];
        if (d && (d.comment || d.execCmd || d.cloneTarget || d.cfgDirty)) return true;
      }
    }
    return false;
  }

  function isUserFocused() {
    const el = document.activeElement;
    if (el && ['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)) return true;
    return hasActiveLxcDrafts();
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

  function setSwitchState(btn, labelEl, checked, onTxt = 'Вкл', offTxt = 'Выкл') {
    if (!btn) return;
    btn.setAttribute('aria-checked', checked ? 'true' : 'false');
    if (labelEl) labelEl.textContent = checked ? onTxt : offTxt;
  }

  function updateApplyBar() {
    const bar = qs('px-apply-bar');
    const txt = qs('px-apply-text');
    const btn = qs('btn-px-apply');
    if (!bar || !txt || !btn) return;
    if (state.proxiesDirty) {
      bar.classList.add('is-dirty');
      txt.textContent = 'Есть неприменённые изменения — пересоберите конфигурацию ядра.';
      btn.className = 'btn btn-primary btn-sm';
    } else {
      bar.classList.remove('is-dirty');
      txt.textContent = 'Конфигурация ядра актуальна — изменения сразу можно применять здесь.';
      btn.className = 'btn btn-secondary btn-sm';
    }
  }

  function markProxiesDirty(dirty = true) {
    state.proxiesDirty = dirty;
    updateApplyBar();
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

    openJobPoller(title, startRes.id, onSuccessConsoleCt, action);
  }

  function openJobPoller(title, jobId, onSuccessConsoleCt = '', actionName = '') {
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
    openModal('job-modal', closeBtn);

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
          closeBtn.focus();
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
          if (['apply_core', 'restart', 'warp_generate', 'warp_disable', 'set_core'].includes(actionName)) {
            markProxiesDirty(false);
          }
          if (onSuccessConsoleCt) {
            conBtn.style.display = '';
            conBtn.onclick = () => {
              closeModal('job-modal');
              openConsole(onSuccessConsoleCt);
            };
          }
        } else {
          badgeEl.className = 'badge badge-err';
          badgeEl.textContent = `Ошибка (${res.exit_code})`;
        }
        closeBtn.focus();
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

  function resetConsoleFrame() {
    const oldFrame = qs('console-frame');
    if (!oldFrame || !oldFrame.parentNode) return null;
    try {
      if (oldFrame.contentWindow) {
        oldFrame.contentWindow.onbeforeunload = null;
      }
    } catch (_e) {}
    const fresh = document.createElement('iframe');
    fresh.id = 'console-frame';
    fresh.className = oldFrame.className || 'console-frame';
    fresh.title = oldFrame.title || 'LXC Web Console';
    oldFrame.replaceWith(fresh);
    return fresh;
  }

  async function openConsole(ctName) {
    // Clear onbeforeunload and swap iframe BEFORE requesting a new token
    const freshFrame = resetConsoleFrame();
    const statusBadge = qs('console-status-badge');
    const liveDot = qs('console-live-dot');
    if (statusBadge) {
      statusBadge.className = 'badge badge-warn';
      statusBadge.textContent = 'Подключение...';
    }
    if (liveDot) liveDot.className = 'dot-off';

    try {
      const res = await api('lxc_console_token', { name: ctName });
      if (!res.ok) throw new Error(res.error || 'Не удалось получить токен консоли');
      state.consoleCt = ctName;
      qs('console-title').textContent = `Консоль LXC: ${ctName}`;
      qs('console-sub').textContent = `Интерактивный shell (${location.host})`;
      const targetFrame = qs('console-frame') || freshFrame;
      if (targetFrame) targetFrame.src = res.url;
      if (statusBadge) {
        statusBadge.className = 'badge badge-ok';
        statusBadge.textContent = 'Сессия активна';
      }
      if (liveDot) liveDot.className = 'dot-live';
      qs('console-modal-box').classList.remove('fullscreen');
      if (qs('console-modal').style.display !== 'flex') {
        openModal('console-modal', qs('btn-con-close'));
      }
    } catch (err) {
      if (statusBadge) {
        statusBadge.className = 'badge badge-err';
        statusBadge.textContent = 'Отключено';
      }
      toast(err.message, 'err');
    }
  }

  function closeConsoleModal() {
    resetConsoleFrame();
    state.consoleCt = '';
    closeModal('console-modal');
  }

  function renderHeader(s) {
    const sys = s.system || {};
    const git = s.git || {};
    const links = s.links || {};
    const lxc = s.lxc || {};
    const cts = lxc.containers || [];
    const runCnt = cts.filter((c) => c.state === 'RUNNING').length;

    qs('hdr-sub').textContent = `${sys.os_name || 'Alpine Linux'} • ${sys.model || ''} • LAN ${s.network?.lan_ip || ''}`;

    const coreOk = Boolean(s.core?.running);
    const aghOk = Boolean(s.adguard?.running);

    const mobDot = qs('mob-live-pill');
    if (mobDot) {
      mobDot.innerHTML = `<span class="${coreOk && aghOk ? 'dot-live' : 'dot-off'}"></span>`;
    }

    const badges = [];
    badges.push(
      `<span class="badge badge-${coreOk ? 'ok' : 'err'}"><span class="${coreOk ? 'dot-live' : 'dot-off'}"></span>${esc(s.core?.name || 'Core')}</span>`
    );
    badges.push(
      `<span class="badge badge-${aghOk ? 'ok' : 'err'}"><span class="${aghOk ? 'dot-live' : 'dot-off'}"></span>AdGuard</span>`
    );
    badges.push(
      `<button class="badge badge-${runCnt > 0 ? 'ok' : 'muted'} badge-clickable" id="hdr-lxc-jump" type="button">LXC ${runCnt}/${cts.length}</button>`
    );
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
    const mobPill = qs('mob-lxc-count');
    if (cts.length > 0) {
      tabPill.style.display = '';
      tabPill.textContent = `${runCnt}/${cts.length}`;
      if (mobPill) {
        mobPill.style.display = '';
        mobPill.textContent = `${runCnt}/${cts.length}`;
      }
    } else {
      tabPill.style.display = 'none';
      if (mobPill) mobPill.style.display = 'none';
    }

    const setLnk = (id, mobId, url) => {
      const el = qs(id);
      const mel = qs(mobId);
      if (url) {
        if (el) { el.href = url; el.style.display = ''; }
        if (mel) { mel.href = url; mel.style.display = ''; }
      } else {
        if (el) el.style.display = 'none';
        if (mel) mel.style.display = 'none';
      }
    };
    setLnk('lnk-core-ui', 'mob-lnk-core-ui', links.ui_url);
    setLnk('lnk-agh', 'mob-lnk-agh', links.agh_url);
    setLnk('lnk-ca', 'mob-lnk-ca', links.ca_url);
  }

  function renderOnboarding(s) {
    const box = qs('ov-onboarding');
    if (!box) return;
    if (localStorage.getItem('gw_onboarding_dismissed') === '1') {
      box.style.display = 'none';
      return;
    }

    const px = s.proxies || {};
    const ssl = s.ssl || {};
    const tg = s.telegram || {};
    const bak = s.backup || {};

    const step1 = Boolean((px.sub_count || 0) > 0 || (px.my_nodes || []).length > 0 || px.warp_enabled);
    const step2 = Boolean(ssl.caddy_enabled || ssl.le_active);
    const step3 = Boolean(state.lastTrace || localStorage.getItem('gw_trace_ran') === '1');
    const step4 = Boolean(tg.configured || bak.exists);
    const doneCnt = [step1, step2, step3, step4].filter(Boolean).length;

    box.style.display = 'block';
    const steps = [
      {
        done: step1,
        title: '1. Источник прокси',
        desc: step1 ? 'Подписка, URI-ключи или WARP настроены' : 'Добавьте подписку, ключ или включите WARP',
        cta: 'Настроить',
        act: 'tab:proxies',
      },
      {
        done: step2,
        title: '2. HTTPS и доверие PKI',
        desc: step2 ? 'Caddy HTTPS активен для сервисов' : 'Включите Caddy или Wildcard Let\'s Encrypt',
        cta: s.links?.ca_url ? 'Портал CA' : 'SSL и PKI',
        act: s.links?.ca_url ? `url:${s.links.ca_url}` : 'tab:storage',
      },
      {
        done: step3,
        title: '3. Проверка Trace & Ping',
        desc: step3 ? 'Диагностика канала и Anti-Leak выполнена' : 'Убедитесь, что Fake-IP и прокси работают',
        cta: 'Проверить',
        act: 'run:trace',
      },
      {
        done: step4,
        title: '4. Бэкап и Telegram',
        desc: step4 ? 'Резервная копия или уведомления готовы' : 'Создайте единый бэкап или привяжите бота',
        cta: 'Открыть',
        act: 'tab:system',
      },
    ];

    box.innerHTML = `
      <div class="ob-head">
        <div class="card-title-group">
          <h2>Быстрый старт шлюза</h2>
          ${badgeHtml(`${doneCnt}/4 готово`, doneCnt === 4 ? 'ok' : 'info')}
        </div>
        <button class="btn btn-xs" id="btn-ob-dismiss" type="button">Скрыть подсказку</button>
      </div>
      <div class="ob-steps">
        ${steps.map((st) => `
          <div class="ob-step ${st.done ? 'done' : ''}">
            <div class="ob-step-top">
              <span class="ob-check">${st.done ? svgIcon('i-check', 'ic-xs') : ''}</span>
              <div>
                <div class="ob-title">${esc(st.title)}</div>
                <div class="ob-desc">${esc(st.desc)}</div>
              </div>
            </div>
            <div>
              <button class="btn btn-xs ${st.done ? 'btn-secondary' : 'btn-primary'}" data-ob-act="${esc(st.act)}" type="button">${esc(st.cta)}</button>
            </div>
          </div>
        `).join('')}
      </div>
    `;
  }

  function renderPipeline(s) {
    const el = qs('ov-pipeline');
    if (!el) return;
    const devs = s.devices || [];
    const leases = s.adguard?.dhcp_leases || [];
    const clientCnt = Math.max(devs.length, leases.length);
    const agh = s.adguard || {};
    const core = s.core || {};
    const tr = state.lastTrace?.trace;
    const grpCnt = (s.proxies?.groups || []).length;

    const exitTitle = tr?.ip ? `${tr.ip}${tr.loc ? ` (${tr.loc})` : ''}` : (core.running ? `${pluralRu(grpCnt, ['группа', 'группы', 'групп'])} активны` : 'Ожидание');

    el.innerHTML = `
      <div class="pipeline-head">
        <span class="pipeline-title">${svgIcon('i-activity', 'ic-xs')} Живая топология трафика (нажмите на узел)</span>
        <span class="muted small tabular-nums">${s.network?.lan_if ? esc(s.network.lan_if) : 'LAN'} &rarr; ${esc(core.tun_if || 'gateway-tun')}</span>
      </div>
      <div class="pipeline-flow">
        <button class="pipeline-node" data-pipe-act="tab:proxies" type="button">
          <span class="pipeline-ico ok">${svgIcon('i-lan')}</span>
          <span class="pipeline-node-meta">
            <span class="pipeline-node-lbl">Клиенты LAN</span>
            <span class="pipeline-node-val tabular-nums">${pluralRu(clientCnt, ['устройство', 'устройства', 'устройств'])}</span>
          </span>
        </button>

        <svg class="pipeline-conn ${agh.running ? '' : 'off'}" viewBox="0 0 32 16" aria-hidden="true">
          <path d="M2 8h26m-5-5 5 5-5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>

        <button class="pipeline-node" data-pipe-act="tab:network" type="button">
          <span class="pipeline-ico ${agh.running ? 'ok' : 'err'}">${svgIcon('i-shield')}</span>
          <span class="pipeline-node-meta">
            <span class="pipeline-node-lbl">AdGuard DNS :53</span>
            <span class="pipeline-node-val"><span class="${agh.running ? 'dot-live' : 'dot-off'}"></span>${agh.running ? (agh.protection_enabled ? 'Фильтр ON' : 'Фильтр OFF') : 'Остановлен'}</span>
          </span>
        </button>

        <svg class="pipeline-conn ${core.running && core.tun_up ? '' : 'off'}" viewBox="0 0 32 16" aria-hidden="true">
          <path d="M2 8h26m-5-5 5 5-5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>

        <button class="pipeline-node" data-pipe-act="tab:network" type="button">
          <span class="pipeline-ico ${core.running && core.tun_up ? 'ok' : 'err'}">${svgIcon('i-zap')}</span>
          <span class="pipeline-node-meta">
            <span class="pipeline-node-lbl">${esc(core.name || 'Core')} TUN</span>
            <span class="pipeline-node-val"><span class="${core.running && core.tun_up ? 'dot-live' : 'dot-off'}"></span>${core.tun_up ? 'TUN активен' : 'TUN отключён'}</span>
          </span>
        </button>

        <svg class="pipeline-conn ${core.running ? '' : 'off'}" viewBox="0 0 32 16" aria-hidden="true">
          <path d="M2 8h26m-5-5 5 5-5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>

        <button class="pipeline-node" data-pipe-act="run:trace" type="button">
          <span class="pipeline-ico ${tr?.ip ? 'ok' : ''}">${svgIcon('i-proxies')}</span>
          <span class="pipeline-node-meta">
            <span class="pipeline-node-lbl">Выход (Trace)</span>
            <span class="pipeline-node-val tabular-nums">${esc(exitTitle)}</span>
          </span>
        </button>
      </div>
    `;
  }

  function renderOverview(s) {
    const sys = s.system || {};
    const core = s.core || {};
    const agh = s.adguard || {};
    const st = s.storage || null;

    renderOnboarding(s);
    renderPipeline(s);

    const ramSpark = sparklineSvgHtml(state.history.ram, 'sg-ram', sys.ram_pct >= 85 ? '#f87171' : '#38bdf8');
    const ctSpark = sparklineSvgHtml(state.history.ct, 'sg-ct', '#818cf8');

    qs('ov-kpis').innerHTML = `
      <div class="kpi-card">
        <div class="kpi-top">
          <span class="kpi-label">Ядро и TUN ${hintDotHtml('Виртуальный сетевой интерфейс TUN перехватывает весь трафик LAN для маршрутизации без настройки клиентов.')}</span>
          <span class="${core.running ? 'dot-live' : 'dot-off'}"></span>
        </div>
        <div class="kpi-main">
          <div>
            <div class="kpi-val">${esc(core.name || '—')}</div>
            <div class="muted small tabular-nums">${esc(core.version || '—')}${core.rss ? ` • ${esc(core.rss)}` : ''}</div>
          </div>
          ${s.links?.ui_url ? `<a class="btn btn-xs" href="${esc(s.links.ui_url)}" target="_blank" rel="noopener" title="Открыть панель ядра">${svgIcon('i-ext', 'ic-xs')}</a>` : ''}
        </div>
        <div class="kpi-meta">
          ${core.running ? badgeHtml(`Активно (PID ${core.pid})`, 'ok') : badgeHtml('Остановлено', 'err')}
          ${core.tun_up ? badgeHtml(`TUN ${core.tun_if}`, 'ok') : badgeHtml('TUN отключён', 'err')}
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-top">
          <span class="kpi-label">DNS &amp; Защита ${hintDotHtml('AdGuard Home фильтрует рекламу и передаёт домены в ядро, а DDR Block запрещает браузерам обходить ваш DNS.')}</span>
          <span class="${agh.running ? 'dot-live' : 'dot-off'}"></span>
        </div>
        <div class="kpi-main">
          <div>
            <div class="kpi-val">${agh.running ? 'AdGuard ON' : 'Остановлен'}</div>
            <div class="muted small tabular-nums">${esc(agh.version || '—')}${agh.rss ? ` • ${esc(agh.rss)}` : ''}</div>
          </div>
          ${s.links?.agh_url ? `<a class="btn btn-xs" href="${esc(s.links.agh_url)}" target="_blank" rel="noopener" title="Открыть AdGuard Home">${svgIcon('i-ext', 'ic-xs')}</a>` : ''}
        </div>
        <div class="kpi-meta">
          ${agh.protection_enabled ? badgeHtml('Фильтр ON', 'ok') : badgeHtml('Фильтр OFF', 'warn')}
          ${agh.dhcp_enabled ? badgeHtml(`DHCP • ${pluralRu((agh.dhcp_leases || []).length, ['аренда', 'аренды', 'аренд'])}`, 'ok') : badgeHtml('DHCP Sidecar', 'muted')}
          ${state.lastTrace?.dns ? badgeHtml(state.lastTrace.dns.ddr_block ? 'DDR Block OK' : 'DDR WARN', state.lastTrace.dns.ddr_block ? 'ok' : 'warn') : ''}
        </div>
      </div>

      <div class="kpi-card">
        <div class="kpi-top">
          <span class="kpi-label">ОЗУ и Conntrack ${hintDotHtml('Conntrack — таблица активных сетевых соединений ядра Linux. Спарклайн показывает динамику за последние 24 замера.')}</span>
        </div>
        <div class="kpi-main">
          <div>
            <div class="kpi-val tabular-nums">${esc(sys.ram_used_mb)} / ${esc(sys.ram_total_mb)} МБ</div>
            <div class="muted small tabular-nums">Load: ${esc(sys.load || '—')}</div>
            <div class="muted small tabular-nums">Conntrack: ${esc(sys.conntrack_used)}/${esc(sys.conntrack_max)}</div>
          </div>
          ${radialGaugeHtml(sys.ram_pct)}
        </div>
        ${ramSpark}
      </div>

      <div class="kpi-card">
        <div class="kpi-top">
          <span class="kpi-label">Диск / и система</span>
        </div>
        <div class="kpi-main">
          <div>
            <div class="kpi-val tabular-nums">${esc(sys.disk_used || '0')} / ${esc(sys.disk_total || '0')}</div>
            <div class="muted small">Ядро: ${esc(sys.kernel || '—')}</div>
            ${st ? `<div class="muted small tabular-nums">Storage: ${esc(st.disk_used)} / ${esc(st.disk_total)} (${esc(st.disk_pct)}%)</div>` : ''}
          </div>
          ${radialGaugeHtml(sys.disk_pct)}
        </div>
        ${ctSpark}
      </div>
    `;

    qs('ov-uptime').textContent = `Аптайм: ${fmtUptime(sys.uptime_sec)}`;

    const modules = Array.isArray(s.homelab) ? s.homelab : [];
    const dockEl = qs('ov-homelab-grid');
    if (!modules.length) {
      dockEl.innerHTML = '<div class="muted">Модули Homelab пока не зарегистрированы.</div>';
    } else {
      const installed = modules.filter((m) => m.enabled);
      const available = modules.filter((m) => !m.enabled);

      const renderInstalledCard = (m) => {
        const meta = HOMELAB_META[m.id] || { desc: `Сервис ${m.service || m.id}` };
        const statusBadge = m.running
          ? `<span class="badge badge-ok"><span class="dot-live"></span>Работает</span>`
          : `<span class="badge badge-err"><span class="dot-off"></span>Остановлен</span>`;

        let subLine = '';
        if (m.url) {
          subLine = `<a href="${esc(m.url)}" target="_blank" rel="noopener">${esc(m.url)}</a>`;
        } else if (m.smb_share) {
          subLine = `<span class="mono">${esc(m.smb_share)}</span>`;
        } else {
          subLine = `<span class="muted">Порт ${esc(m.port || '—')}</span>`;
        }

        let primaryBtn = '';
        if (m.url && m.running) {
          primaryBtn = `<a class="btn btn-primary btn-xs" href="${esc(m.url)}" target="_blank" rel="noopener">Открыть ${svgIcon('i-ext', 'ic-xs')}</a>`;
        } else if (m.smb_share && m.running) {
          primaryBtn = `<button class="btn btn-primary btn-xs" data-copy="${esc(m.smb_share)}" type="button">${svgIcon('i-copy', 'ic-xs')} Копировать путь</button>`;
        } else if (!m.running) {
          primaryBtn = `<button class="btn btn-primary btn-xs" data-hl-act="start" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-play', 'ic-xs')} Старт</button>`;
        } else {
          primaryBtn = `<button class="btn btn-secondary btn-xs" data-hl-act="restart" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-refresh', 'ic-xs')} Рестарт</button>`;
        }

        const startStopItem = m.running
          ? `<button class="menu-item" data-hl-act="stop" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-stop', 'ic-xs')} Остановить</button>`
          : `<button class="menu-item" data-hl-act="start" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-play', 'ic-xs')} Запустить</button>`;

        return `
          <div class="hl-card">
            <div class="hl-top">
              <div class="hl-head-left">
                <div class="hl-icon">${homelabIconSvg(m.id)}</div>
                <div>
                  <div class="hl-title">${esc(m.title)}</div>
                  <div class="hl-desc">${esc(meta.desc)}</div>
                  <div class="hl-sub">${subLine}</div>
                </div>
              </div>
              ${statusBadge}
            </div>
            <div class="hl-actions">
              ${primaryBtn}
              <div class="menu-wrap">
                <button class="btn btn-xs" data-menu-toggle="hl-${esc(m.id)}" type="button" aria-label="Дополнительные действия для ${esc(m.title)}" aria-expanded="false">
                  ${svgIcon('i-more', 'ic-xs')}
                </button>
                <div class="menu-pop" id="menu-hl-${esc(m.id)}" role="menu">
                  ${startStopItem}
                  <button class="menu-item" data-hl-act="restart" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-refresh', 'ic-xs')} Рестарт</button>
                  <button class="menu-item" data-hl-act="update" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-download', 'ic-xs')} Обновить</button>
                  <button class="menu-item danger" data-hl-act="remove" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-trash', 'ic-xs')} Отключить</button>
                </div>
              </div>
            </div>
          </div>
        `;
      };

      const renderAvailCard = (m) => {
        const meta = HOMELAB_META[m.id] || { desc: `Модуль ${m.id}` };
        return `
          <div class="hl-card is-available">
            <div class="hl-top">
              <div class="hl-head-left">
                <div class="hl-icon">${homelabIconSvg(m.id)}</div>
                <div>
                  <div class="hl-title">${esc(m.title)}</div>
                  <div class="hl-desc">${esc(meta.desc)}</div>
                </div>
              </div>
              ${badgeHtml('Не установлен', 'muted')}
            </div>
            <div class="hl-actions">
              <button class="btn btn-secondary btn-xs" data-hl-act="install" data-hl-id="${esc(m.id)}" type="button">${svgIcon('i-plus', 'ic-xs')} Установить</button>
            </div>
          </div>
        `;
      };

      let html = '';
      if (installed.length) {
        html += `
          <div>
            <div class="hl-section-head"><span>Установленные сервисы (${installed.length})</span></div>
            <div class="homelab-grid">${installed.map(renderInstalledCard).join('')}</div>
          </div>
        `;
      }
      if (available.length) {
        html += `
          <div>
            <div class="hl-section-head"><span>Доступные к установке (${available.length})</span></div>
            <div class="homelab-grid">${available.map(renderAvailCard).join('')}</div>
          </div>
        `;
      }
      dockEl.innerHTML = html;
    }

    renderProxyGroups(s);
  }

  function renderProxyGroups(s) {
    const q = (qs('inp-groups-filter')?.value || '').trim().toLowerCase();
    const allGroups = s.proxies?.groups || [];
    const groups = q
      ? allGroups.filter((g) => g.name.toLowerCase().includes(q) || (g.now || '').toLowerCase().includes(q))
      : allGroups;
    qs('ov-groups-meta').textContent = q
      ? `${groups.length} из ${allGroups.length}`
      : pluralRu(allGroups.length, ['группа', 'группы', 'групп']);
    qs('ov-groups-body').innerHTML = groups.length
      ? groups.map((g) => {
          const niceNow = (g.now || '—').replace(/\s*->\s*/g, ' \u2192 ');
          return `
            <tr>
              <td><strong>${esc(g.name)}</strong></td>
              <td>${badgeHtml(g.type || '—', 'muted')}</td>
              <td class="mono">${esc(niceNow)}</td>
              <td class="tabular-nums">${esc(g.count)}</td>
            </tr>
          `;
        }).join('')
      : '<tr><td colspan="4" class="muted">Совпадений нет или ядро остановлено.</td></tr>';
  }

  function renderNetwork(s) {
    const core = s.core || {};
    const net = s.network || {};
    const agh = s.adguard || {};

    qs('net-core-info').innerHTML = `
      <div><span class="muted">Движок:</span> <strong>${esc(core.name)}</strong></div>
      <div><span class="muted">Версия:</span> <span class="tabular-nums">${esc(core.version || '—')}</span></div>
      <div><span class="muted">Веб-панель:</span> <strong>${esc(core.ui_name)}</strong> (${esc(core.ui_ver || '—')})</div>
      <div><span class="muted">Память / PID:</span> <span class="tabular-nums">${esc(core.rss || '—')} / ${esc(core.pid || '—')}</span></div>
    `;

    qs('btn-core-mihomo').classList.toggle('active', core.engine === 'mihomo');
    qs('btn-core-singbox').classList.toggle('active', core.engine === 'singbox');
    qs('btn-ui-metacubexd').classList.toggle('active', core.ui === 'metacubexd');
    qs('btn-ui-zashboard').classList.toggle('active', core.ui === 'zashboard');

    setSwitchState(qs('btn-ks-toggle'), qs('ks-state-label'), Boolean(net.killswitch), 'Вкл', 'Выкл');

    setInputDefault(qs('inp-lan-ip'), net.lan_ip || '');
    setInputDefault(qs('inp-gw-ip'), net.gw_ip || '');

    setSwitchState(qs('btn-dhcp-toggle'), qs('dhcp-state-label'), Boolean(agh.dhcp_enabled), 'Вкл', 'Выкл');

    const v4 = agh.dhcp_v4 || {};
    const leases = agh.dhcp_leases || [];
    qs('net-dhcp-info').innerHTML = `
      <span>Статус: ${agh.dhcp_enabled ? badgeHtml('Раздаёт адреса в LAN', 'ok') : badgeHtml('Выключен (Sidecar)', 'muted')}</span>
      <span>Диапазон: <span class="mono">${esc(v4.range_start || '—')} – ${esc(v4.range_end || '—')}</span></span>
      <span>Интерфейс: <span class="mono">${esc(net.lan_if || '—')}</span></span>
      <span>${agh.dhcp_enabled ? 'Активных аренд:' : 'Кэш аренд (Sidecar):'} <strong class="tabular-nums">${leases.length}</strong></span>
    `;

    qs('net-leases-body').innerHTML = leases.length
      ? leases.map((l) => `
          <tr>
            <td class="mono">${esc(l.ip)}</td>
            <td class="mono muted">${esc(l.mac || '—')}</td>
            <td>${esc(l.hostname || '—')}</td>
            <td class="muted">${formatLeaseExpiry(l.expires)}</td>
          </tr>
        `).join('')
      : '<tr><td colspan="4" class="muted">Активных DHCP-аренд нет.</td></tr>';
  }

  function renderProxies(s) {
    const px = s.proxies || {};
    const subCnt = Number(px.sub_count) || 0;
    const subUrlsList = (px.sub_urls || '').trim().split(/\s+/).filter(Boolean);

    qs('px-sub-badge').textContent = pluralRu(subCnt, ['ссылка', 'ссылки', 'ссылок']);
    qs('px-sub-badge').className = `badge ${subCnt > 0 ? 'badge-ok' : 'badge-muted'}`;
    setInputDefault(qs('inp-sub-urls'), subUrlsList.join('\n'));

    const maskedEl = qs('px-sub-masked');
    if (maskedEl) {
      if (subUrlsList.length) {
        maskedEl.innerHTML = subUrlsList.map((u) => `<span class="chip">${esc(maskSubUrl(u))}</span>`).join('');
      } else {
        maskedEl.innerHTML = '<span class="muted small">Подписки пока не заданы. Нажмите «Показать / редактировать» чтобы вставить URL.</span>';
      }
      maskedEl.style.display = state.subRevealed ? 'none' : 'flex';
    }
    const edEl = qs('px-sub-editor');
    if (edEl) edEl.style.display = state.subRevealed ? 'block' : 'none';

    const ruChk = qs('chk-allow-ru');
    if (ruChk.dataset.dirty !== '1') {
      ruChk.checked = Boolean(px.allow_ru);
    }

    const nodes = px.my_nodes || [];
    qs('px-nodes-badge').textContent = pluralRu(nodes.length, ['ключ', 'ключа', 'ключей']);
    qs('px-nodes-badge').className = `badge ${nodes.length > 0 ? 'badge-ok' : 'badge-muted'}`;
    qs('px-nodes-body').innerHTML = nodes.length
      ? nodes.map((n) => `
          <tr>
            <td class="tabular-nums">${esc(n.index)}</td>
            <td>${badgeHtml(n.proto, 'ok')}</td>
            <td class="mono">${esc(n.host)}</td>
            <td>${esc(n.tag)}</td>
            <td><button class="btn btn-danger btn-xs" data-node-del="${esc(n.index)}" type="button">Удалить</button></td>
          </tr>
        `).join('')
      : '<tr><td colspan="5" class="muted">Пользовательские URI-ключи пока не добавлены.</td></tr>';

    const warpBadge = qs('px-warp-badge');
    warpBadge.textContent = px.warp_enabled ? 'Активен' : 'Выключен';
    warpBadge.className = `badge ${px.warp_enabled ? 'badge-ok' : 'badge-muted'}`;
    qs('inp-warp-lic').placeholder = px.warp_license_set
      ? 'Ключ WARP+ уже сохранён (введите новый при смене)'
      : 'Оставьте пустым для бесплатного WARP';

    const renderChips = (elId, items, listName) => {
      const container = qs(elId);
      if (!items || !items.length) {
        container.innerHTML = '<span class="muted small">Список пуст.</span>';
        return;
      }
      container.innerHTML = items.map((dom) => {
        const locked = listName === 'direct' && (dom === '+.lan' || dom === '+.localdomain');
        return `<span class="chip">${locked ? `${svgIcon('i-lock', 'ic-xs')} ` : ''}${esc(dom)}${locked ? '' : `<button class="chip-del" data-dom-del="${esc(dom)}" data-dom-list="${esc(listName)}" type="button" title="Удалить" aria-label="Удалить ${esc(dom)}">&times;</button>`}</span>`;
      }).join('');
    };

    renderChips('chips-proxy', px.proxy_domains, 'proxy');
    renderChips('chips-direct', px.direct_domains, 'direct');

    renderDevices(s);
    updateApplyBar();
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
      badgeHtml(lxc.console_ready ? 'Консоль ttyd ON' : 'ttyd OFF', lxc.console_ready ? 'ok' : 'warn'),
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
          <p class="muted">Разверните Debian, Ubuntu, Alpine, Arch, Kali или любую другую систему из полного каталога <span class="mono">images.linuxcontainers.org</span> в три простых шага.</p>
          <div class="btn-row" style="justify-content:center; margin-top:0.9rem">
            <button class="btn btn-primary" data-lxc-quick-os="alpine" type="button">${distroIconSvg('alpine')} Alpine Linux</button>
            <button class="btn btn-primary" data-lxc-quick-os="debian" type="button">${distroIconSvg('debian')} Debian</button>
            <button class="btn btn-primary" data-lxc-quick-os="ubuntu" type="button">${distroIconSvg('ubuntu')} Ubuntu</button>
            <button class="btn btn-secondary" data-lxc-quick-os="kali" type="button">${distroIconSvg('kali')} Kali</button>
            <button class="btn btn-secondary" data-lxc-quick-os="" type="button">Весь каталог</button>
          </div>
        </div>
      `;
      return;
    }

    if (!cts.length) {
      wrap.innerHTML = '<div class="card"><div class="muted">По запросу контейнеры не найдены.</div></div>';
      return;
    }

    // Preserve active focus and exec output scroll across renders
    const execScrolls = {};
    wrap.querySelectorAll('.exec-output').forEach((el) => {
      execScrolls[el.id] = el.scrollTop;
    });
    let focusMeta = null;
    const actEl = document.activeElement;
    if (actEl && wrap.contains(actEl)) {
      const attrs = ['data-snap-comment', 'data-exec-input', 'data-clone-target'];
      for (const a of attrs) {
        if (actEl.hasAttribute(a)) {
          focusMeta = { sel: `[${a}="${actEl.getAttribute(a)}"]`, ss: actEl.selectionStart, se: actEl.selectionEnd };
          break;
        }
      }
      if (!focusMeta && actEl.name) {
        const frm = actEl.closest('[data-cfg-form]');
        if (frm) {
          focusMeta = { sel: `[data-cfg-form="${frm.dataset.cfgForm}"] [name="${actEl.name}"]`, ss: actEl.selectionStart, se: actEl.selectionEnd };
        }
      }
    }

    wrap.innerHTML = cts.map((c) => {
      const isRun = c.state === 'RUNNING';
      const isOpen = Boolean(state.expandedCts[c.name]);
      const sub = state.ctSubTab[c.name] || 'snaps';
      const snaps = c.snapshots || [];
      const draft = state.lxcDrafts[c.name] || {};
      const distroGuess = (c.os_pretty || '').split(/\s+/)[0].toLowerCase();

      const memUsedMb = parseSizeToMb(c.memory);
      const memLimMb = parseSizeToMb(c.mem_limit);
      const ramPct = memLimMb > 0 ? Math.min(100, Math.round((memUsedMb / memLimMb) * 100)) : 0;

      const ipShown = c.ipv4 || c.static_ip || '';
      const netLabel = c.net_mode === 'macvlan' ? 'Macvlan' : 'NAT';
      const ipPill = ipShown ? `${netLabel} ${ipShown}` : (c.net_mode === 'macvlan' ? 'Macvlan LAN' : 'NAT lxcbr0');

      let drawerHtml = '';
      if (isOpen) {
        let panelHtml = '';
        if (sub === 'snaps') {
          const rows = snaps.length
            ? snaps.map((sn) => `
                <tr>
                  <td class="mono"><strong>${esc(sn.name)}</strong></td>
                  <td class="muted tabular-nums">${esc(sn.date || '—')}</td>
                  <td>${esc(sn.comment || '—')}</td>
                  <td>
                    <div class="btn-row-compact">
                      <button class="btn btn-xs" data-lxc-ct="${esc(c.name)}" data-lxc-act="snap_restore:${esc(sn.name)}" type="button">${svgIcon('i-rollback', 'ic-xs')} Откатить</button>
                      <button class="btn btn-danger btn-xs" data-lxc-ct="${esc(c.name)}" data-lxc-act="snap_delete:${esc(sn.name)}" type="button">${svgIcon('i-trash', 'ic-xs')} Удалить</button>
                    </div>
                  </td>
                </tr>
              `).join('')
            : '<tr><td colspan="4" class="muted">Снимков пока нет — создайте перед изменением системы!</td></tr>';

          panelHtml = `
            <p class="muted small" style="margin-top:0">Перед экспериментами или обновлением пакетов создайте снимок: откат вернёт контейнер в сохранённое состояние.</p>
            <form class="inline-form" data-snap-form="${esc(c.name)}">
              <input class="input" data-snap-comment="${esc(c.name)}" type="text" value="${esc(draft.comment || '')}" placeholder="Комментарий к снимку (например: До установки Docker)" aria-label="Комментарий к снимку">
              <button class="btn btn-primary btn-sm" type="submit">${svgIcon('i-camera', 'ic-xs')} Создать снимок</button>
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
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="ip -4 -br addr && cat /etc/resolv.conf" type="button">Сеть и DNS</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="df -h" type="button">Диски</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="free -m" type="button">Память</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="ps -o pid,user,rss,args | head -n 25" type="button">Процессы</button>
              <button class="btn btn-xs" data-exec-preset="${esc(c.name)}" data-exec-cmd="cat /etc/os-release" type="button">ОС</button>
            </div>
            <form class="inline-form" data-exec-form="${esc(c.name)}">
              <input class="input mono" data-exec-input="${esc(c.name)}" type="text" value="${esc(draft.execCmd || '')}" placeholder="Введите команду внутри ${esc(c.name)} (например: uname -a && ls -la /mnt)" aria-label="Команда внутри ${esc(c.name)}" ${isRun ? '' : 'disabled'}>
              <button class="btn btn-primary btn-sm" type="submit" ${isRun ? '' : 'disabled'}>${svgIcon('i-play', 'ic-xs')} Выполнить</button>
            </form>
            <pre class="exec-output" id="exec-out-${esc(c.name)}">${esc(outTxt)}</pre>
          `;
        } else if (sub === 'config') {
          const cfgMem = draft.cfgDirty && draft.mem_limit !== undefined ? draft.mem_limit : (c.mem_limit || '');
          const cfgCpu = draft.cfgDirty && draft.cpu_limit !== undefined ? draft.cpu_limit : (c.cpu_limit || '');
          const cfgAuto = draft.cfgDirty && draft.autostart !== undefined ? draft.autostart : Boolean(c.autostart);
          const cfgStor = draft.cfgDirty && draft.storage_mount !== undefined ? draft.storage_mount : Boolean(c.storage_mount);
          const cfgNest = draft.cfgDirty && draft.nesting !== undefined ? draft.nesting : Boolean(c.nesting);
          panelHtml = `
            <form data-cfg-form="${esc(c.name)}" class="form-grid">
              <div class="two-col">
                <div>
                  <label class="field-label">Лимит ОЗУ (пусто = без лимита)</label>
                  <div class="btn-row-compact" style="margin-bottom:0.35rem">
                    <button class="btn btn-xs" data-cfg-mem="" data-cfg-ct="${esc(c.name)}" type="button">Без лимита</button>
                    <button class="btn btn-xs" data-cfg-mem="256M" data-cfg-ct="${esc(c.name)}" type="button">256M</button>
                    <button class="btn btn-xs" data-cfg-mem="512M" data-cfg-ct="${esc(c.name)}" type="button">512M</button>
                    <button class="btn btn-xs" data-cfg-mem="1G" data-cfg-ct="${esc(c.name)}" type="button">1G</button>
                    <button class="btn btn-xs" data-cfg-mem="2G" data-cfg-ct="${esc(c.name)}" type="button">2G</button>
                  </div>
                  <input class="input" name="mem_limit" type="text" value="${esc(cfgMem)}" placeholder="Например: 512M или 2G">
                </div>
                <div>
                  <label class="field-label">Лимит ядер CPU (пусто = без лимита)</label>
                  <div class="btn-row-compact" style="margin-bottom:0.35rem">
                    <button class="btn btn-xs" data-cfg-cpu="" data-cfg-ct="${esc(c.name)}" type="button">Без лимита</button>
                    <button class="btn btn-xs" data-cfg-cpu="0.5" data-cfg-ct="${esc(c.name)}" type="button">0.5</button>
                    <button class="btn btn-xs" data-cfg-cpu="1" data-cfg-ct="${esc(c.name)}" type="button">1</button>
                    <button class="btn btn-xs" data-cfg-cpu="2" data-cfg-ct="${esc(c.name)}" type="button">2</button>
                    <button class="btn btn-xs" data-cfg-cpu="4" data-cfg-ct="${esc(c.name)}" type="button">4</button>
                  </div>
                  <input class="input" name="cpu_limit" type="text" value="${esc(cfgCpu)}" placeholder="Например: 1 или 2">
                </div>
                <div>
                  <label class="field-label">Сменить пароль root (необязательно)</label>
                  <input class="input" name="root_pass" type="password" value="${esc(draft.root_pass || '')}" placeholder="Оставьте пустым, чтобы не менять">
                </div>
                <div style="display:flex; flex-direction:column; justify-content:center; gap:0.42rem">
                  <label class="check-row" style="margin:0"><input name="autostart" type="checkbox" ${cfgAuto ? 'checked' : ''}><span>Автозапуск при старте сервера</span></label>
                  <label class="check-row" style="margin:0"><input name="storage_mount" type="checkbox" ${cfgStor ? 'checked' : ''}><span>Монтировать общее хранилище &rarr; /mnt/storage</span></label>
                  <label class="check-row" style="margin:0"><input name="nesting" type="checkbox" ${cfgNest ? 'checked' : ''}><span>Режим Nesting (Docker/контейнеры внутри)</span></label>
                </div>
              </div>
              <div class="btn-row">
                <button class="btn btn-secondary btn-sm" data-cfg-save="${esc(c.name)}" type="button">${svgIcon('i-save', 'ic-xs')} Сохранить параметры</button>
                <button class="btn btn-primary btn-sm" data-cfg-restart="${esc(c.name)}" type="button">${svgIcon('i-refresh', 'ic-xs')} Сохранить и перезапустить</button>
              </div>
            </form>
          `;
        } else if (sub === 'manage') {
          panelHtml = `
            <div class="two-col">
              <div>
                <div class="field-label">Клонировать контейнер «${esc(c.name)}»</div>
                <form class="inline-form" data-clone-form="${esc(c.name)}" novalidate>
                  <input class="input" data-clone-target="${esc(c.name)}" type="text" value="${esc(draft.cloneTarget || '')}" placeholder="${esc(c.name)}-copy" pattern="[A-Za-z0-9_\\-]+" required aria-label="Имя клона">
                  <button class="btn btn-primary btn-sm" type="submit">${svgIcon('i-clone', 'ic-xs')} Клонировать</button>
                </form>
                <div class="muted small" style="margin-top:0.35rem">Создаст полную копию с уникальным MAC-адресом.</div>
              </div>
              <div>
                <div class="field-label">Диагностика и удаление</div>
                <div class="btn-row">
                  <button class="btn btn-secondary btn-sm" data-lxc-ct="${esc(c.name)}" data-lxc-act="fix-net" type="button">${svgIcon('i-wrench', 'ic-xs')} Починить сеть (DHCP/DNS)</button>
                  <button class="btn btn-danger btn-sm" data-lxc-delete="${esc(c.name)}" type="button">${svgIcon('i-trash', 'ic-xs')} Удалить контейнер</button>
                </div>
              </div>
            </div>
          `;
        }

        drawerHtml = `
          <div class="lxc-drawer">
            <div class="sub-tabs">
              <button class="btn btn-xs seg-btn ${sub === 'snaps' ? 'active' : ''}" data-ct-sub="snaps" data-ct-name="${esc(c.name)}" type="button">Снимки (${snaps.length})</button>
              <button class="btn btn-xs seg-btn ${sub === 'exec' ? 'active' : ''}" data-ct-sub="exec" data-ct-name="${esc(c.name)}" type="button">Быстрая команда</button>
              <button class="btn btn-xs seg-btn ${sub === 'config' ? 'active' : ''}" data-ct-sub="config" data-ct-name="${esc(c.name)}" type="button">Ресурсы и опции</button>
              <button class="btn btn-xs seg-btn ${sub === 'manage' ? 'active' : ''}" data-ct-sub="manage" data-ct-name="${esc(c.name)}" type="button">Клон и удаление</button>
            </div>
            ${panelHtml}
          </div>
        `;
      }

      const flags = [];
      if (c.autostart) flags.push('Автостарт');
      if (c.nesting) flags.push('Nesting');
      if (c.storage_mount) flags.push('/mnt/storage');

      return `
        <article class="lxc-card" data-ct-card="${esc(c.name)}">
          <div class="lxc-card-head">
            <div class="lxc-id-wrap">
              <div class="lxc-distro-ico">${distroIconSvg(distroGuess)}</div>
              <div style="min-width:0">
                <div class="lxc-title-row">
                  <span class="lxc-name">${esc(c.name)}</span>
                  ${isRun ? `<span class="badge badge-ok"><span class="dot-live"></span>RUNNING${c.pid ? ` • ${esc(c.pid)}` : ''}</span>` : badgeHtml('STOPPED', 'muted')}
                  ${c.os_pretty ? badgeHtml(c.os_pretty, 'muted') : ''}
                  ${badgeHtml(ipPill, 'info')}
                  ${c.ipv4 ? `<button class="btn-copy-inline" data-copy="${esc(c.ipv4)}" type="button" title="Копировать IPv4" aria-label="Копировать IP ${esc(c.ipv4)}">${svgIcon('i-copy', 'ic-xs')}</button>` : ''}
                </div>
                <div class="lxc-meta-row">
                  <span class="lxc-ram-wrap">
                    <span>ОЗУ: <strong class="tabular-nums">${esc(c.memory || '—')}</strong>${c.mem_limit ? ` / ${esc(c.mem_limit)}` : ''}</span>
                    ${memLimMb > 0 && isRun ? `<span class="lxc-ram-track" title="${ramPct}%"><span class="lxc-ram-fill" style="width:${ramPct}%"></span></span>` : ''}
                  </span>
                  ${c.cpu_limit ? `<span>CPU: <strong class="tabular-nums">${esc(c.cpu_limit)}</strong></span>` : ''}
                  <span>Диск: <strong class="tabular-nums">${esc(c.disk_usage || '—')}</strong></span>
                  <span>Снимки: <strong class="tabular-nums">${snaps.length}</strong></span>
                  ${flags.length ? `<span class="muted">${esc(flags.join(' • '))}</span>` : ''}
                </div>
              </div>
            </div>

            <div class="btn-row-compact">
              <button class="btn btn-primary btn-sm" data-lxc-console="${esc(c.name)}" type="button" ${isRun ? '' : 'disabled title="Запустите контейнер для подключения к консоли"'}>${svgIcon('i-terminal', 'ic-xs')} Консоль</button>
              ${isRun
                ? `<button class="btn btn-sm" data-lxc-ct="${esc(c.name)}" data-lxc-act="stop" type="button">${svgIcon('i-stop', 'ic-xs')} Стоп</button>`
                : `<button class="btn btn-primary btn-sm" data-lxc-ct="${esc(c.name)}" data-lxc-act="start" type="button">${svgIcon('i-play', 'ic-xs')} Старт</button>`}
              <button class="btn btn-sm ${isOpen ? 'btn-primary' : ''}" data-lxc-toggle="${esc(c.name)}" type="button">${svgIcon('i-sliders', 'ic-xs')} Управление ${isOpen ? '▴' : '▾'}</button>
              <div class="menu-wrap">
                <button class="btn btn-sm" data-menu-toggle="lxc-${esc(c.name)}" type="button" aria-label="Действия для ${esc(c.name)}" aria-expanded="false">${svgIcon('i-more', 'ic-xs')}</button>
                <div class="menu-pop" id="menu-lxc-${esc(c.name)}" role="menu">
                  <button class="menu-item" data-lxc-ct="${esc(c.name)}" data-lxc-act="restart" type="button">${svgIcon('i-refresh', 'ic-xs')} Рестарт</button>
                  <button class="menu-item" data-lxc-quicksnap="${esc(c.name)}" type="button">${svgIcon('i-camera', 'ic-xs')} Быстрый снимок</button>
                  <button class="menu-item" data-lxc-open-sub="manage" data-lxc-ct-open="${esc(c.name)}" type="button">${svgIcon('i-clone', 'ic-xs')} Клонировать</button>
                  <button class="menu-item danger" data-lxc-delete="${esc(c.name)}" type="button">${svgIcon('i-trash', 'ic-xs')} Удалить</button>
                </div>
              </div>
            </div>
          </div>
          ${drawerHtml}
        </article>
      `;
    }).join('');

    for (const [id, top] of Object.entries(execScrolls)) {
      const box = qs(id);
      if (box) box.scrollTop = top;
    }
    if (focusMeta) {
      const target = wrap.querySelector(focusMeta.sel);
      if (target) {
        target.focus();
        if (typeof focusMeta.ss === 'number' && typeof target.setSelectionRange === 'function') {
          try { target.setSelectionRange(focusMeta.ss, focusMeta.se); } catch (_e) {}
        }
      }
    }
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
      <div class="tabular-nums">Использование: <strong>${esc(st.disk_used || '0')} / ${esc(st.disk_total || '0')} (${pct}%)</strong></div>
      <div class="progress-bar"><div class="progress-fill ${fillCls}" style="width:${Math.min(100, pct)}%"></div></div>
    `;

    // Context-aware LUKS2 button states
    const hasExtLuks = Boolean(st.ext_expected || st.ext_mounted || st.luks_mapped || st.luks_key_exists);
    const unlockBtn = qs('btn-st-unlock');
    const lockBtn = qs('btn-st-lock');
    const luksHint = qs('st-luks-hint');
    if (!hasExtLuks) {
      unlockBtn.disabled = true;
      lockBtn.disabled = true;
      unlockBtn.className = 'btn btn-secondary';
      if (luksHint) luksHint.textContent = 'Внешний накопитель LUKS2 не подключён — хранилище работает на системном разделе.';
    } else if (st.ext_mounted) {
      unlockBtn.disabled = true;
      unlockBtn.className = 'btn btn-secondary';
      lockBtn.disabled = false;
      if (luksHint) luksHint.textContent = 'Внешний диск смонтирован. Перед отключением USB-кабеля выполните безопасное извлечение.';
    } else {
      unlockBtn.disabled = false;
      unlockBtn.className = 'btn btn-primary';
      lockBtn.disabled = true;
      if (luksHint) luksHint.textContent = 'Ожидается разблокировка внешнего LUKS2-накопителя.';
    }

    const dirs = st.dirs || [];
    const segBar = qs('st-seg-bar');
    if (segBar) {
      const parsedDirs = dirs.map((d, i) => ({
        name: d.name,
        size: d.size,
        bytes: parseDiskBytes(d.size),
        color: STORAGE_COLORS[i % STORAGE_COLORS.length],
      })).filter((x) => x.bytes > 0);
      const totalB = parsedDirs.reduce((acc, x) => acc + x.bytes, 0);
      if (totalB > 0) {
        segBar.innerHTML = `
          <div class="st-seg-bar" title="Распределение по каталогам">
            ${parsedDirs.map((x) => `<div class="st-seg-slice" style="width:${Math.max(1, (x.bytes / totalB) * 100).toFixed(1)}%; background:${x.color}" title="${esc(x.name)}: ${esc(x.size)}"></div>`).join('')}
          </div>
          <div class="st-seg-legend">
            ${parsedDirs.map((x) => `<span class="st-leg-item"><span class="st-leg-dot" style="background:${x.color}"></span>${esc(x.name)} (${esc(x.size)})</span>`).join('')}
          </div>
        `;
      } else {
        segBar.innerHTML = '';
      }
    }

    qs('infra-storage-dirs').innerHTML = dirs.length
      ? dirs.map((d) => `
          <tr>
            <td><strong>${esc(d.name)}</strong></td>
            <td class="mono muted">${esc(d.path)}</td>
            <td class="mono tabular-nums">${esc(d.size)}</td>
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

    const daysLeft = Number(ssl.days_left) || 0;
    const sslRingPct = ssl.le_active ? Math.min(100, Math.round((daysLeft / 90) * 100)) : 100;
    const sslRingTone = ssl.le_active ? (daysLeft <= 14 ? 'err' : daysLeft <= 30 ? 'warn' : 'ok') : 'ok';

    qs('infra-ssl-info').innerHTML = `
      <div class="ssl-hero">
        ${radialGaugeHtml(sslRingPct, sslRingTone, ssl.le_active ? `${daysLeft}д` : 'PKI')}
        <div class="info-list" style="margin-bottom:0; flex:1">
          <div><span class="muted">Режим HTTPS:</span> ${ssl.le_active ? badgeHtml('Let\'s Encrypt Wildcard', 'ok') : badgeHtml('Локальный PKI (*.lan)', 'muted')}</div>
          <div><span class="muted">Caddy Proxy:</span> ${ssl.caddy_enabled ? badgeHtml('Активен', 'ok') : badgeHtml('Отключен', 'warn')}</div>
          <div><span class="muted">Домен:</span> <span class="mono">${esc(ssl.domain ? `*.${ssl.domain}` : '*.lan')}</span></div>
          <div><span class="muted">Срок:</span> <span class="tabular-nums">${esc(ssl.expiry || 'Локальный CA')}${daysLeft ? ` (${pluralRu(daysLeft, ['день', 'дня', 'дней'])})` : ''}</span></div>
        </div>
      </div>
    `;

    const snEl = qs('ssl-pki-snippets');
    if (snEl) {
      if (!ssl.le_active && s.links?.ca_url) {
        const caOrigin = s.links.ca_url.replace(/\/+$/, '');
        const psCmd = `Invoke-WebRequest -Uri "${caOrigin}/homelab-root-ca.crt" -OutFile "$env:TEMP\\homelab-ca.crt"; Import-Certificate -FilePath "$env:TEMP\\homelab-ca.crt" -CertStoreLocation Cert:\\LocalMachine\\Root`;
        const shCmd = `sudo curl -fsSL ${caOrigin}/homelab-root-ca.crt -o /usr/local/share/ca-certificates/homelab-ca.crt && sudo update-ca-certificates`;
        snEl.style.display = 'flex';
        snEl.innerHTML = `
          <div class="snippet-box">
            <div class="snippet-head"><span>Быстрая установка CA (Windows PowerShell)</span><button class="btn btn-xs" data-copy-snippet="${esc(psCmd)}" type="button">${svgIcon('i-copy', 'ic-xs')} Копировать</button></div>
            <div class="snippet-code">${esc(psCmd)}</div>
          </div>
          <div class="snippet-box">
            <div class="snippet-head"><span>Быстрая установка CA (Linux)</span><button class="btn btn-xs" data-copy-snippet="${esc(shCmd)}" type="button">${svgIcon('i-copy', 'ic-xs')} Копировать</button></div>
            <div class="snippet-code">${esc(shCmd)}</div>
          </div>
        `;
      } else {
        snEl.style.display = 'none';
      }
    }

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
      ? `<div class="small">Архив: <span class="mono">/root/gateway_backup.tar.gz</span> • <strong class="tabular-nums">${esc(bak.size)}</strong> • <span class="muted tabular-nums">${esc(bak.mtime)}</span></div>`
      : '<div class="muted small">Единый архив бэкапа еще не создан.</div>';

    const cron = s.cron || {};
    setSwitchState(qs('btn-cron-wd'), qs('cron-wd-label'), Boolean(cron.watchdog), 'Вкл', 'Выкл');
    setSwitchState(qs('btn-cron-au'), qs('cron-au-label'), Boolean(cron.autoupdate), 'Вкл', 'Выкл');

    const git = s.git || {};
    const isUpd = git.update_status === 'UPDATE_AVAILABLE';
    const updTone = isUpd ? 'warn' : 'ok';
    const updText = isUpd
      ? `Доступно обновлений: ${pluralRu(git.update_behind, ['коммит', 'коммита', 'коммитов'])}`
      : (git.update_status === 'UP_TO_DATE' ? 'Актуальная версия' : (git.is_repo ? 'Не проверялось' : 'Standalone'));
    qs('sys-git-info').innerHTML = `
      <div class="info-list" style="margin-bottom:0">
        <div><span class="muted">Ветка:</span> <span class="mono">${esc(git.branch || 'main')}</span></div>
        <div><span class="muted">Текущий коммит:</span> <span class="mono">${esc(git.sha || '—')}</span></div>
        <div><span class="muted">Статус:</span> ${badgeHtml(updText, updTone)}</div>
      </div>
    `;

    const updRunBtn = qs('btn-upd-run');
    const updHint = qs('sys-git-hint');
    if (updRunBtn) {
      updRunBtn.className = `btn ${isUpd ? 'btn-primary' : 'btn-secondary'}`;
    }
    if (updHint) {
      updHint.textContent = !git.is_repo
        ? 'Режим Standalone (без .git): при обновлении перезагрузит пакеты и ядра без git pull.'
        : (isUpd ? 'Найдены новые коммиты на GitHub — можно безопасно обновиться.' : '');
    }
  }

  function renderAll(s, opts = {}) {
    renderHeader(s);
    renderOverview(s);
    renderNetwork(s);
    renderProxies(s);
    if (!opts.skipLxc) {
      renderLxc(s);
    }
    renderStorageSsl(s);
    renderSystem(s);
  }

  // LXC Creation Wizard catalog & stepper functions
  function setWizardStep(step) {
    state.wizardStep = Math.max(1, Math.min(3, Number(step) || 1));
    document.querySelectorAll('[data-wizard-step]').forEach((b) => {
      const n = Number(b.dataset.wizardStep);
      b.classList.toggle('active', n === state.wizardStep);
      b.classList.toggle('done', n < state.wizardStep);
    });
    document.querySelectorAll('[data-wizard-pane]').forEach((p) => {
      const act = Number(p.dataset.wizardPane) === state.wizardStep;
      p.classList.toggle('active', act);
      p.hidden = !act;
    });
    qs('btn-lxc-prev').style.display = state.wizardStep > 1 ? '' : 'none';
    qs('btn-lxc-next').style.display = state.wizardStep < 3 ? '' : 'none';
    qs('btn-lxc-create-submit').style.display = state.wizardStep === 3 ? '' : 'none';
    if (state.wizardStep === 3) renderWizardSummary();
  }

  function renderWizardSummary() {
    const sumEl = qs('lxc-wizard-summary');
    if (!sumEl) return;
    const manual = qs('chk-lxc-manual-os').checked;
    const distro = qs('sel-lxc-distro').value.trim() || '—';
    const release = (manual ? qs('inp-lxc-release-manual').value.trim() : qs('sel-lxc-release').value) || '—';
    const variant = qs('sel-lxc-variant').value || 'default';
    const name = qs('inp-lxc-name').value.trim() || '—';
    const netMode = document.querySelector('input[name="lxc_net_mode"]:checked')?.value || 'nat';
    const useStatic = qs('chk-lxc-static-ip').checked;
    const ipLbl = useStatic ? (qs('inp-lxc-ip').value.trim() || 'статический') : 'DHCP автоматически';
    const mem = qs('inp-lxc-mem').value.trim() || 'Без лимита';
    const cpu = qs('inp-lxc-cpu').value.trim() || 'Без лимита';
    const flags = [];
    if (qs('chk-lxc-startnow').checked) flags.push('Запустить сразу');
    if (qs('chk-lxc-autostart').checked) flags.push('Автостарт');
    if (qs('chk-lxc-storage').checked) flags.push('/mnt/storage');
    if (qs('chk-lxc-nesting').checked) flags.push('Nesting');

    sumEl.innerHTML = `
      <div style="font-weight:650; margin-bottom:0.45rem">Сводка перед созданием</div>
      <div class="info-list" style="margin-bottom:0">
        <div><span class="muted">ОС:</span> <strong>${esc(distro)} ${esc(release)}</strong> (${esc(variant)})</div>
        <div><span class="muted">Имя:</span> <span class="mono"><strong>${esc(name)}</strong></span></div>
        <div><span class="muted">Сеть:</span> ${esc(netMode === 'macvlan' ? 'Macvlan LAN' : 'NAT lxcbr0')} (${esc(ipLbl)})</div>
        <div><span class="muted">Ресурсы:</span> ОЗУ ${esc(mem)} • CPU ${esc(cpu)}</div>
      </div>
      ${flags.length ? `<div class="muted small" style="margin-top:0.35rem">Опции: ${esc(flags.join(' • '))}</div>` : ''}
    `;
  }

  async function loadCatalog(force = false) {
    qs('lxc-cat-status').textContent = 'Загрузка официального списка образов с images.linuxcontainers.org...';
    try {
      const cat = await api('lxc_templates', { force: force ? 'yes' : 'no' });
      if (!cat.ok) throw new Error(cat.error || 'Не удалось загрузить каталог');
      state.catalog = cat;
      qs('lxc-cat-arch-badge').textContent = `Архитектура: ${cat.arch}`;
      qs('lxc-cat-status').textContent = `Загружено ${pluralRu(cat.total, ['образ', 'образа', 'образов'])} (${cat.source}, кэш ${cat.updated_at})`;
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
      const selCls = d === state.selectedDistro ? 'selected' : '';
      return `
        <button class="distro-tile ${selCls}" data-pick-distro="${esc(d)}" type="button">
          ${distroIconSvg(d)}
          <span>
            <span class="distro-title">${esc(d)}</span>
            <span class="distro-meta tabular-nums">${esc(pluralRu(relSet.size, ['релиз', 'релиза', 'релизов']))}</span>
          </span>
        </button>
      `;
    }).join('');

    syncDistroReleases(state.selectedDistro);
  }

  function syncDistroReleases(distro, skipDistroInput = false) {
    state.selectedDistro = distro;
    if (!skipDistroInput) qs('sel-lxc-distro').value = distro;
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
    const distro = qs('sel-lxc-distro').value.trim().toLowerCase();
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

  function validateWizardStep(step) {
    if (step === 1) {
      const manual = qs('chk-lxc-manual-os').checked;
      const distro = qs('sel-lxc-distro').value.trim();
      const release = manual ? qs('inp-lxc-release-manual').value.trim() : qs('sel-lxc-release').value;
      if (!distro || !release) {
        toast('Укажите дистрибутив и релиз ОС', 'err');
        return false;
      }
      return true;
    }
    if (step === 2) {
      const name = qs('inp-lxc-name').value.trim();
      if (!/^[A-Za-z0-9_-]+$/.test(name)) {
        toast('Имя контейнера может содержать только латиницу, цифры, - и _', 'err');
        qs('inp-lxc-name').focus();
        return false;
      }
      if (qs('chk-lxc-static-ip').checked) {
        const sip = qs('inp-lxc-ip').value.trim();
        const sgw = qs('inp-lxc-gw').value.trim();
        const sdns = qs('inp-lxc-dns').value.trim();
        if (!isValidIpv4Cidr(sip)) {
          toast('Укажите корректный статический IPv4 с маской (например 10.0.3.50/24)', 'err');
          qs('inp-lxc-ip').focus();
          return false;
        }
        if (!isValidIpv4(sgw)) {
          toast('Укажите корректный IPv4 шлюза (например 10.0.3.1)', 'err');
          qs('inp-lxc-gw').focus();
          return false;
        }
        if (!isValidIpv4(sdns)) {
          toast('Укажите корректный IPv4 DNS-сервера (например 10.0.3.1)', 'err');
          qs('inp-lxc-dns').focus();
          return false;
        }
      }
      return true;
    }
    if (step === 3) {
      const mem = qs('inp-lxc-mem').value.trim();
      const cpu = qs('inp-lxc-cpu').value.trim();
      if (mem && !isValidLxcMem(mem)) {
        toast('Некорректный лимит ОЗУ (пример: 512M или 2G)', 'err');
        qs('inp-lxc-mem').focus();
        return false;
      }
      if (cpu && !isValidLxcCpu(cpu)) {
        toast('Некорректный лимит CPU (пример: 0.5, 1, 2)', 'err');
        qs('inp-lxc-cpu').focus();
        return false;
      }
      return true;
    }
    return true;
  }

  async function openLxcWizard(preselectDistro = '') {
    setWizardStep(1);
    openModal('lxc-create-modal', qs('inp-cat-search'));
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

  function classifyLogLine(line) {
    if (/(\[X\]|\b(ERROR|FATAL|PANIC|CRITICAL)\b|"level"\s*:\s*"error")/i.test(line)) return 'log-line-err';
    if (/(\[!\]|\b(WARN|WARNING)\b|"level"\s*:\s*"warn")/i.test(line)) return 'log-line-warn';
    if (/(\[✓\]|\[OK\]|\bSUCCESS\b)/i.test(line)) return 'log-line-ok';
    return '';
  }

  function getFilteredLogLines() {
    const raw = state.rawLogText || '';
    if (!raw) return [];
    const q = (qs('inp-log-filter')?.value || '').trim().toLowerCase();
    const sev = state.logSeverity || 'all';
    const lines = raw.split('\n');
    return lines.filter((line) => {
      if (sev === 'err' && classifyLogLine(line) !== 'log-line-err') return false;
      if (sev === 'warn' && !['log-line-warn', 'log-line-err'].includes(classifyLogLine(line))) return false;
      if (q && !line.toLowerCase().includes(q)) return false;
      return true;
    });
  }

  function renderFilteredLogs() {
    const view = qs('sys-log-view');
    const meta = qs('log-match-meta');
    if (!state.logLoaded || !state.rawLogText) {
      view.textContent = 'Выберите источник лога и нажмите «Показать лог».';
      if (meta) meta.textContent = '';
      return;
    }
    const total = state.rawLogText.split('\n').length;
    const matched = getFilteredLogLines();
    view.innerHTML = '';
    if (!matched.length) {
      view.textContent = '(Строк по фильтру не найдено)';
      if (meta) meta.textContent = `0 из ${total}`;
      return;
    }
    const frag = document.createDocumentFragment();
    for (const line of matched) {
      const span = document.createElement('span');
      const cls = classifyLogLine(line);
      span.className = cls ? `log-line ${cls}` : 'log-line';
      span.textContent = line;
      frag.appendChild(span);
    }
    view.appendChild(frag);
    if (meta) meta.textContent = matched.length === total ? pluralRu(total, ['строка', 'строки', 'строк']) : `${matched.length} из ${total}`;
    if (qs('chk-log-autoscroll')?.checked) {
      view.scrollTop = view.scrollHeight;
    }
  }

  async function refreshStatus(force = false) {
    if (!force && (isModalOpen() || isUserFocused())) return;
    if (state.refreshing) {
      if (force) state.pendingForceRefresh = true;
      return;
    }
    state.refreshing = true;
    const spinEl = qs('refresh-icon');
    if (spinEl) spinEl.classList.add('is-spinning');
    try {
      const s = await api('status', {});
      if (!s.ok) throw new Error(s.error || 'Ошибка получения статуса');
      if (state.pendingForceRefresh && !force) return;
      state.status = s;

      const ramPct = Number(s.system?.ram_pct);
      const ctUsed = Number(s.system?.conntrack_used) || 0;
      const ctMax = Math.max(1, Number(s.system?.conntrack_max) || 1);
      if (Number.isFinite(ramPct)) state.history.ram = [...state.history.ram, ramPct].slice(-24);
      state.history.ct = [...state.history.ct, Math.min(100, Math.round((ctUsed / ctMax) * 100))].slice(-24);
      saveSparkHistory();

      const skipLxc = !force && hasOpenLxcDrawer();
      renderAll(s, { skipLxc });
    } catch (err) {
      if (err.status === 401) {
        showReconnectModal({
          title: 'Требуется повторный вход',
          bodyHtml: '<p>Сессия авторизации устарела или мастер-пароль был изменён. Обновите страницу и введите актуальный пароль.</p>',
          url: '',
        });
      } else {
        toast(`Не удалось обновить статус: ${err.message}`, 'err');
      }
    } finally {
      state.refreshing = false;
      if (spinEl) spinEl.classList.remove('is-spinning');
      if (state.pendingForceRefresh) {
        state.pendingForceRefresh = false;
        refreshStatus(true);
      }
    }
  }

  function switchTab(tabName) {
    state.activeTab = tabName;
    document.querySelectorAll('.tab-btn').forEach((b) => {
      const act = b.dataset.tab === tabName;
      b.classList.toggle('active', act);
      b.setAttribute('aria-selected', act ? 'true' : 'false');
      b.setAttribute('tabindex', act ? '0' : '-1');
    });
    document.querySelectorAll('.mob-nav-btn[data-mob-tab]').forEach((b) => {
      b.classList.toggle('active', b.dataset.mobTab === tabName);
    });
    document.querySelectorAll('.tab-panel').forEach((p) => {
      const act = p.id === `tab-${tabName}`;
      p.classList.toggle('active', act);
      p.hidden = !act;
    });
  }

  function applyThemeIcon(theme) {
    const ico = qs('theme-icon');
    const metaTheme = document.querySelector('meta[name="theme-color"]');
    if (ico) {
      ico.innerHTML = `<use href="#${theme === 'light' ? 'i-moon' : 'i-sun'}"/>`;
    }
    if (metaTheme) {
      metaTheme.setAttribute('content', theme === 'light' ? '#f4f6fa' : '#07090e');
    }
  }

  function toggleTheme() {
    const cur = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', cur);
    localStorage.setItem('gw_theme', cur);
    applyThemeIcon(cur);
  }

  function initTheme() {
    const saved = localStorage.getItem('gw_theme') || 'dark';
    document.documentElement.setAttribute('data-theme', saved);
    applyThemeIcon(saved);
    qs('btn-theme').addEventListener('click', toggleTheme);
    qs('mob-btn-theme')?.addEventListener('click', () => {
      toggleTheme();
      closeModal('mobile-more-sheet');
    });
  }

  // Hint Popover Manager
  function closeHintPopover() {
    document.querySelectorAll('.hint-popover').forEach((el) => el.remove());
  }

  function showHintPopover(btn) {
    const text = btn.dataset.hint;
    if (!text) return;
    const existing = document.querySelector('.hint-popover');
    if (existing && existing.dataset.forBtn === text) {
      closeHintPopover();
      return;
    }
    closeHintPopover();
    const pop = document.createElement('div');
    pop.className = 'hint-popover';
    pop.dataset.forBtn = text;
    pop.setAttribute('role', 'tooltip');
    pop.textContent = text;
    document.body.appendChild(pop);

    const rect = btn.getBoundingClientRect();
    const pr = pop.getBoundingClientRect();
    let left = rect.left + rect.width / 2 - pr.width / 2;
    left = Math.max(8, Math.min(window.innerWidth - pr.width - 8, left));
    let top = rect.bottom + 6;
    if (top + pr.height > window.innerHeight - 8) {
      top = Math.max(8, rect.top - pr.height - 6);
    }
    pop.style.left = `${Math.round(left)}px`;
    pop.style.top = `${Math.round(top)}px`;
  }

  // Command Palette (Ctrl+K)
  function buildCommandItems(query) {
    const q = query.trim().toLowerCase();
    const items = [
      { title: 'Обзор и Homelab', sub: 'Вкладка', icon: 'i-overview', run: () => switchTab('overview') },
      { title: 'Ядро и сеть', sub: 'Вкладка', icon: 'i-network', run: () => switchTab('network') },
      { title: 'Прокси и маршруты', sub: 'Вкладка', icon: 'i-proxies', run: () => switchTab('proxies') },
      { title: 'Контейнеры LXC', sub: 'Вкладка', icon: 'i-lxc', run: () => switchTab('lxc') },
      { title: 'Диск и SSL', sub: 'Вкладка', icon: 'i-storage', run: () => switchTab('storage') },
      { title: 'Система и логи', sub: 'Вкладка', icon: 'i-system', run: () => switchTab('system') },
      { title: 'Trace & Ping', sub: 'Быстрая диагностика канала', icon: 'i-activity', run: () => { switchTab('overview'); qs('btn-trace').click(); } },
      { title: 'Doctor (автолечение)', sub: 'Диагностика и исправление', icon: 'i-stethoscope', run: () => qs('btn-doctor').click() },
      { title: 'Применить конфиг ядра', sub: 'Пересобрать и применить правила', icon: 'i-zap', run: () => qs('btn-ov-apply').click() },
      { title: 'Создать контейнер LXC', sub: 'Открыть мастер создания', icon: 'i-plus', run: () => { switchTab('lxc'); openLxcWizard(''); } },
      { title: 'Сменить тему оформления', sub: 'Dark / Light', icon: 'i-sun', run: () => toggleTheme() },
      { title: 'Обновить статус сейчас', sub: 'Запрос /api/status', icon: 'i-refresh', run: () => refreshStatus(true) },
    ];

    for (const m of state.status?.homelab || []) {
      if (m.enabled && m.url) {
        items.push({
          title: `Открыть ${m.title}`,
          sub: m.url,
          icon: 'i-ext',
          run: () => window.open(m.url, '_blank', 'noopener'),
        });
      }
      items.push({
        title: m.enabled ? `Перезапустить ${m.title}` : `Установить ${m.title}`,
        sub: 'Homelab OpenRC',
        icon: m.enabled ? 'i-refresh' : 'i-plus',
        run: () => runJob(`${m.enabled ? 'Перезапуск' : 'Установка'} ${m.id}`, 'homelab_action', m.id, m.enabled ? 'restart' : 'install'),
      });
    }

    for (const c of state.status?.lxc?.containers || []) {
      if (c.state === 'RUNNING') {
        items.push({
          title: `Консоль LXC: ${c.name}`,
          sub: `${c.os_pretty || 'LXC'} • ${c.ipv4 || 'NAT'}`,
          icon: 'i-terminal',
          run: () => { switchTab('lxc'); openConsole(c.name); },
        });
      }
      items.push({
        title: `Перейти к контейнеру ${c.name}`,
        sub: c.state,
        icon: 'i-lxc',
        run: () => { switchTab('lxc'); state.expandedCts[c.name] = true; renderLxc(state.status); },
      });
    }

    const filtered = q
      ? items.filter((it) => it.title.toLowerCase().includes(q) || it.sub.toLowerCase().includes(q))
      : items;

    if (q && q.includes('.') && !isIpLiteral(q) && !q.includes(' ')) {
      filtered.unshift({
        title: `Domain X-Ray: проверить «${query.trim()}»`,
        sub: 'Проверить маршрут домена через DNS и прокси',
        icon: 'i-search',
        run: () => {
          switchTab('proxies');
          qs('inp-inspect-domain').value = query.trim();
          qs('frm-inspect').requestSubmit();
        },
      });
    }
    return filtered.slice(0, 14);
  }

  function renderCommandList() {
    const input = qs('cmd-input');
    const list = qs('cmd-list');
    state.cmdItems = buildCommandItems(input.value);
    if (state.cmdIndex >= state.cmdItems.length) state.cmdIndex = 0;

    if (!state.cmdItems.length) {
      list.innerHTML = '<div class="muted small" style="padding:0.75rem">Ничего не найдено</div>';
      return;
    }

    list.innerHTML = state.cmdItems.map((it, i) => `
      <button class="cmd-item ${i === state.cmdIndex ? 'active' : ''}" data-cmd-idx="${i}" type="button" role="option" aria-selected="${i === state.cmdIndex ? 'true' : 'false'}">
        <span class="cmd-item-left">
          ${svgIcon(it.icon)}
          <span>
            <span class="cmd-item-title">${esc(it.title)}</span>
            <span class="cmd-item-sub" style="display:block">${esc(it.sub)}</span>
          </span>
        </span>
      </button>
    `).join('');
  }

  function openCommandPalette() {
    const inp = qs('cmd-input');
    inp.value = '';
    state.cmdIndex = 0;
    renderCommandList();
    openModal('cmd-modal', inp);
  }

  function runCommandIndex(idx) {
    const item = state.cmdItems[idx];
    if (!item) return;
    closeModal('cmd-modal');
    item.run();
  }

  function renderTraceResult(res) {
    const box = qs('trace-box');
    const t = res.trace || {};
    const d = res.dns || {};
    const l = res.latency_ms || {};
    const latRow = (lbl, val) => {
      const n = Number(val);
      const ok = Number.isFinite(n) && n > 0;
      const cls = !ok ? 'dead' : (n < 120 ? '' : n < 260 ? 'mid' : 'slow');
      const pct = !ok ? 100 : Math.min(100, Math.max(8, Math.round((n / 600) * 100)));
      return `
        <div class="lat-row">
          <span class="muted">${esc(lbl)}</span>
          <span class="lat-track"><span class="lat-fill ${cls}" style="width:${pct}%"></span></span>
          <span class="lat-ms">${ok ? `${n} мс` : 'таймаут'}</span>
        </div>
      `;
    };
    box.innerHTML = `
      <div class="trace-grid">
        <div class="trace-card">
          <div class="trace-card-title">${svgIcon('i-proxies', 'ic-xs')} Выходной IP</div>
          <div class="mono"><strong>${esc(t.ip || '—')}</strong></div>
          <div class="muted small" style="margin-top:0.35rem">Локация: ${esc(t.loc || '?')} / ${esc(t.colo || '?')}</div>
          <div style="margin-top:0.35rem">${badgeHtml(`WARP: ${t.warp || 'off'}`, t.warp && t.warp !== 'off' ? 'ok' : 'muted')}</div>
        </div>
        <div class="trace-card">
          <div class="trace-card-title">${svgIcon('i-shield', 'ic-xs')} DNS &amp; Anti-Leak</div>
          <div class="small">Fake-IP (chatgpt.com): <span class="mono">${esc(d.chatgpt || '—')}</span></div>
          <div class="small" style="margin-top:0.25rem">Direct (ya.ru): <span class="mono">${esc(d.yaru || '—')}</span></div>
          <div style="margin-top:0.35rem">${badgeHtml(d.ddr_block ? 'DDR Block: OK' : 'DDR Block: WARN', d.ddr_block ? 'ok' : 'warn')}</div>
        </div>
        <div class="trace-card">
          <div class="trace-card-title">${svgIcon('i-activity', 'ic-xs')} Задержка каналов</div>
          ${latRow('RU Direct', l.ru)}
          ${latRow('Cloudflare', l.cf)}
          ${latRow('YouTube', l.yt)}
          ${latRow('OpenAI', l.ai)}
        </div>
      </div>
    `;
  }

  async function runTraceCheck() {
    const box = qs('trace-box');
    box.style.display = 'block';
    box.textContent = 'Проверка DNS, IP выхода и задержек...';
    try {
      const res = await api('trace', {});
      state.lastTrace = res;
      localStorage.setItem('gw_trace_ran', '1');
      renderTraceResult(res);
      if (state.status) renderOverview(state.status);
    } catch (err) {
      box.textContent = `Ошибка: ${err.message}`;
    }
  }

  function closeAllOverflowMenus() {
    document.querySelectorAll('.menu-pop.open').forEach((m) => {
      m.classList.remove('open');
      const wrap = m.closest('.menu-wrap');
      const btn = wrap?.querySelector('[data-menu-toggle]');
      if (btn) btn.setAttribute('aria-expanded', 'false');
    });
  }

  function bindEvents() {
    // Tab Switching & Keyboard Arrow Navigation
    const tabBtns = Array.from(document.querySelectorAll('.tab-btn'));
    tabBtns.forEach((btn, idx) => {
      btn.addEventListener('click', () => switchTab(btn.dataset.tab));
      btn.addEventListener('keydown', (e) => {
        if (!['ArrowRight', 'ArrowLeft', 'Home', 'End'].includes(e.key)) return;
        e.preventDefault();
        let next = idx;
        if (e.key === 'ArrowRight') next = (idx + 1) % tabBtns.length;
        else if (e.key === 'ArrowLeft') next = (idx - 1 + tabBtns.length) % tabBtns.length;
        else if (e.key === 'Home') next = 0;
        else if (e.key === 'End') next = tabBtns.length - 1;
        tabBtns[next].focus();
        switchTab(tabBtns[next].dataset.tab);
      });
    });

    // Mobile Bottom Nav & More Sheet
    document.querySelectorAll('.mob-nav-btn[data-mob-tab]').forEach((btn) => {
      btn.addEventListener('click', () => switchTab(btn.dataset.mobTab));
    });
    qs('btn-mobile-more')?.addEventListener('click', () => openModal('mobile-more-sheet', qs('btn-mob-sheet-x')));
    qs('btn-mob-sheet-x')?.addEventListener('click', () => closeModal('mobile-more-sheet'));
    qs('mobile-more-sheet')?.addEventListener('click', (e) => {
      if (e.target === qs('mobile-more-sheet')) closeModal('mobile-more-sheet');
    });
    document.querySelectorAll('[data-sheet-tab]').forEach((btn) => {
      btn.addEventListener('click', () => {
        closeModal('mobile-more-sheet');
        switchTab(btn.dataset.sheetTab);
      });
    });
    qs('mob-btn-cmd')?.addEventListener('click', () => {
      closeModal('mobile-more-sheet');
      openCommandPalette();
    });

    // Global Popover / Overflow Menu Dismissal
    document.addEventListener('click', (e) => {
      const hintBtn = e.target.closest('.hint-dot');
      if (hintBtn) {
        e.stopPropagation();
        showHintPopover(hintBtn);
        return;
      }
      if (!e.target.closest('.hint-popover')) closeHintPopover();

      const menuTog = e.target.closest('[data-menu-toggle]');
      if (menuTog) {
        e.stopPropagation();
        const menuId = `menu-${menuTog.dataset.menuToggle}`;
        const targetMenu = qs(menuId);
        const wasOpen = targetMenu?.classList.contains('open');
        closeAllOverflowMenus();
        if (targetMenu && !wasOpen) {
          targetMenu.classList.add('open');
          menuTog.setAttribute('aria-expanded', 'true');
        }
        return;
      }
      if (!e.target.closest('.menu-pop')) closeAllOverflowMenus();
    });

    // Command Palette Events
    qs('btn-cmd-palette').addEventListener('click', openCommandPalette);
    qs('btn-cmd-close').addEventListener('click', () => closeModal('cmd-modal'));
    qs('cmd-modal').addEventListener('click', (e) => {
      if (e.target === qs('cmd-modal')) closeModal('cmd-modal');
    });
    qs('cmd-input').addEventListener('input', () => {
      state.cmdIndex = 0;
      renderCommandList();
    });
    qs('cmd-input').addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (state.cmdItems.length) {
          state.cmdIndex = (state.cmdIndex + 1) % state.cmdItems.length;
          renderCommandList();
        }
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (state.cmdItems.length) {
          state.cmdIndex = (state.cmdIndex - 1 + state.cmdItems.length) % state.cmdItems.length;
          renderCommandList();
        }
      } else if (e.key === 'Enter') {
        e.preventDefault();
        runCommandIndex(state.cmdIndex);
      }
    });
    qs('cmd-list').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-cmd-idx]');
      if (btn) runCommandIndex(Number(btn.dataset.cmdIdx));
    });

    // Dirty tracking on settings inputs
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
      closeModal('job-modal');
      refreshStatus(true);
    });
    qs('recon-dismiss').addEventListener('click', () => {
      if (state.reconTimer) { clearInterval(state.reconTimer); state.reconTimer = null; }
      closeModal('reconnect-modal');
    });

    // Global Keyboard Shortcuts (Ctrl+K, Escape, Modal Focus Trap)
    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        if (qs('cmd-modal').style.display === 'flex') closeModal('cmd-modal');
        else openCommandPalette();
        return;
      }

      if (e.key === '/' && !isModalOpen() && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName)) {
        e.preventDefault();
        openCommandPalette();
        return;
      }

      if (e.key === 'Escape') {
        closeHintPopover();
        closeAllOverflowMenus();
        if (qs('confirm-modal').style.display === 'flex') {
          closeConfirm(false);
        } else if (qs('cmd-modal').style.display === 'flex') {
          closeModal('cmd-modal');
        } else if (qs('reconnect-modal').style.display === 'flex') {
          if (state.reconTimer) { clearInterval(state.reconTimer); state.reconTimer = null; }
          closeModal('reconnect-modal');
        } else if (qs('mobile-more-sheet').style.display === 'flex') {
          closeModal('mobile-more-sheet');
        } else if (qs('console-modal').style.display === 'flex') {
          closeConsoleModal();
        } else if (qs('lxc-create-modal').style.display === 'flex') {
          closeModal('lxc-create-modal');
        } else if (qs('job-modal').style.display === 'flex' && !qs('job-close').disabled) {
          closeModal('job-modal');
          refreshStatus(true);
        }
        return;
      }

      if (e.key === 'Tab') {
        const order = ['confirm-modal', 'reconnect-modal', 'cmd-modal', 'console-modal', 'lxc-create-modal', 'job-modal', 'mobile-more-sheet'];
        const openId = order.find((id) => qs(id)?.style.display === 'flex');
        if (openId) {
          const focusables = getFocusableElements(qs(openId));
          if (focusables.length) {
            const first = focusables[0];
            const last = focusables[focusables.length - 1];
            if (e.shiftKey && document.activeElement === first) {
              e.preventDefault();
              last.focus();
            } else if (!e.shiftKey && document.activeElement === last) {
              e.preventDefault();
              first.focus();
            }
          }
        }
      }
    });

    // Onboarding & Pipeline Clicks
    qs('ov-onboarding')?.addEventListener('click', (e) => {
      if (e.target.closest('#btn-ob-dismiss')) {
        localStorage.setItem('gw_onboarding_dismissed', '1');
        qs('ov-onboarding').style.display = 'none';
        return;
      }
      const btn = e.target.closest('[data-ob-act]');
      if (!btn) return;
      const act = btn.dataset.obAct;
      if (act.startsWith('tab:')) switchTab(act.slice(4));
      else if (act.startsWith('url:')) window.open(act.slice(4), '_blank', 'noopener');
      else if (act === 'run:trace') runTraceCheck();
    });

    qs('ov-pipeline')?.addEventListener('click', (e) => {
      const node = e.target.closest('[data-pipe-act]');
      if (!node) return;
      const act = node.dataset.pipeAct;
      if (act.startsWith('tab:')) switchTab(act.slice(4));
      else if (act === 'run:trace') runTraceCheck();
    });

    // Overview quick actions & Homelab cards
    qs('btn-ov-go-lxc').addEventListener('click', () => switchTab('lxc'));
    qs('inp-groups-filter').addEventListener('input', () => {
      if (state.status) renderProxyGroups(state.status);
    });
    qs('btn-trace').addEventListener('click', runTraceCheck);
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
      closeAllOverflowMenus();
      const modId = btn.dataset.hlId;
      const act = btn.dataset.hlAct;
      if (act === 'remove') {
        const extra = modId === 'caddy' ? ' (также переведёт Web Dashboard на встроенный порт :8095)' : '';
        const ok = await confirmDialog('Отключить модуль?', `Отключить модуль «${modId}»${extra}? Данные сохранятся на диске.`);
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
      if (!isValidIpv4(lan_ip)) {
        toast('Укажите корректный LAN IP сервера (например 192.168.1.82)', 'err');
        qs('inp-lan-ip').focus();
        return;
      }
      if (!isValidIpv4(gw_ip)) {
        toast('Укажите корректный IP основного роутера (например 192.168.1.1)', 'err');
        qs('inp-gw-ip').focus();
        return;
      }
      if (lan_ip === gw_ip) {
        toast('IP сервера и роутера не могут совпадать', 'err');
        return;
      }
      if (lan_ip.split('.').slice(0, 3).join('.') !== gw_ip.split('.').slice(0, 3).join('.')) {
        toast('IP сервера и роутера должны находиться в одной подсети /24', 'err');
        return;
      }
      if (!(await confirmDialog('Применить IP-адреса?', `Назначить LAN IP ${lan_ip} и шлюз ${gw_ip}? При смене LAN IP откройте панель по новому адресу.`))) return;
      try {
        const res = await api('set_network', { lan_ip, gw_ip });
        if (!res.ok) throw new Error(res.error || 'Ошибка настройки сети');
        qs('inp-lan-ip').dataset.dirty = '';
        qs('inp-gw-ip').dataset.dirty = '';
        if (res.ip_changed && res.new_ip) {
          const port = location.port ? `:${location.port}` : '';
          const newUrl = `${location.protocol}//${res.new_ip}${port}/`;
          showReconnectModal({
            title: 'LAN IP сервера изменён',
            bodyHtml: `<p>Новый адрес панели: <a class="mono" href="${esc(newUrl)}">${esc(newUrl)}</a></p>`,
            url: newUrl,
            autoCountdownSec: 10,
          });
        } else {
          toast('Сетевые настройки обновлены');
          refreshStatus(true);
        }
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    // Proxies & Routes
    qs('btn-sub-reveal')?.addEventListener('click', () => {
      state.subRevealed = !state.subRevealed;
      qs('btn-sub-reveal').setAttribute('aria-expanded', state.subRevealed ? 'true' : 'false');
      if (state.status) renderProxies(state.status);
      if (state.subRevealed) qs('inp-sub-urls')?.focus();
    });

    document.querySelectorAll('[data-inspect-preset]').forEach((btn) => {
      btn.addEventListener('click', () => {
        qs('inp-inspect-domain').value = btn.dataset.inspectPreset;
        qs('frm-inspect').requestSubmit();
      });
    });

    qs('frm-inspect').addEventListener('submit', async (e) => {
      e.preventDefault();
      const raw = qs('inp-inspect-domain').value.trim();
      const box = qs('inspect-result');
      if (!raw) {
        toast('Введите имя домена (например chatgpt.com)', 'err');
        qs('inp-inspect-domain').focus();
        return;
      }
      if (isIpLiteral(raw)) {
        box.style.display = 'block';
        box.innerHTML = '<span class="badge badge-err">IP-адрес отклонён</span> <span class="muted">Domain X-Ray проверяет доменные имена (например <span class="mono">chatgpt.com</span>), а не IP-адреса.</span>';
        toast('Domain X-Ray принимает доменные имена, а не IP-адреса', 'err');
        return;
      }
      const cleanHost = extractHostCandidate(raw);
      if (!cleanHost || /\s/.test(cleanHost) || !cleanHost.includes('.')) {
        toast('Укажите корректное доменное имя (например chatgpt.com)', 'err');
        return;
      }

      box.style.display = 'block';
      box.textContent = 'Проверка маршрута домена...';
      try {
        const r = await api('domain_inspect', { domain: cleanHost });
        if (!r.ok) throw new Error(r.error || 'Ошибка проверки');
        const vTone = r.verdict === 'proxy' ? 'ok' : (r.verdict === 'blocked' ? 'err' : 'warn');
        const barRow = (lbl, code, ms) => {
          const n = Number(ms);
          const ok = Number.isFinite(n) && n > 0;
          const pct = !ok ? 100 : Math.min(100, Math.max(8, Math.round((n / 800) * 100)));
          const cls = !ok ? 'dead' : (n < 150 ? '' : n < 350 ? 'mid' : 'slow');
          return `
            <div class="lat-row" style="grid-template-columns: 110px 1fr 110px">
              <span class="muted">${esc(lbl)}</span>
              <span class="lat-track"><span class="lat-fill ${cls}" style="width:${pct}%"></span></span>
              <span class="lat-ms">HTTP ${esc(code)} • ${ok ? `${n} мс` : '—'}</span>
            </div>
          `;
        };
        box.innerHTML = `
          <div class="xray-flow">
            <span class="xray-hop">DNS :53 &rarr; <span class="mono">${esc(r.resolved_ip || '—')}</span></span>
            <span class="xray-hop">Список: <strong>${esc(r.list_source)}</strong> (${esc(r.suffix)})</span>
            ${badgeHtml(r.verdict.toUpperCase(), vTone)}
          </div>
          ${barRow('Через прокси', r.proxy_http, r.proxy_ms)}
          ${barRow('Напрямую', r.direct_http, r.direct_ms)}
          <div class="btn-row-compact" style="margin-top:0.65rem">
            <button class="btn btn-xs" data-xray-add="proxy" data-xray-dom="${esc(r.domain)}" type="button">+ В прокси</button>
            <button class="btn btn-xs" data-xray-add="direct" data-xray-dom="${esc(r.domain)}" type="button">+ Напрямую</button>
          </div>
        `;
      } catch (err) {
        box.textContent = `Ошибка: ${err.message}`;
      }
    });

    qs('inspect-result').addEventListener('click', async (e) => {
      const btn = e.target.closest('[data-xray-add]');
      if (!btn) return;
      try {
        const res = await api('domain_rule', { action: 'add', list: btn.dataset.xrayAdd, domain: btn.dataset.xrayDom });
        if (!res.ok) throw new Error(res.error || 'Ошибка добавления правила');
        markProxiesDirty(true);
        toast(`Домен ${res.domain} добавлен (${btn.dataset.xrayAdd}). Нажмите «Применить конфиг ядра».`);
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
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
        markProxiesDirty(true);
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
        markProxiesDirty(true);
        toast('Ключ добавлен. Нажмите «Применить конфиг ядра».');
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
        markProxiesDirty(true);
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
          markProxiesDirty(true);
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
          markProxiesDirty(true);
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
      const ip = qs('inp-dev-ip').value.trim();
      if (!isValidIpv4(ip)) {
        toast('Укажите корректный IPv4 устройства (например 192.168.1.50)', 'err');
        qs('inp-dev-ip').focus();
        return;
      }
      try {
        const res = await api('device_rule', {
          ip,
          mode: qs('inp-dev-mode').value,
        });
        if (!res.ok) throw new Error(res.error || 'Ошибка правила устройства');
        qs('inp-dev-ip').value = '';
        markProxiesDirty(true);
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
        markProxiesDirty(true);
        toast(`Режим ${res.ip}: ${res.mode}`);
        refreshStatus(true);
      } catch (err) {
        toast(err.message, 'err');
      }
    });

    // LXC Studio Events & Draft Tracking
    qs('btn-lxc-open-create').addEventListener('click', () => openLxcWizard(''));
    qs('btn-lxc-doctor').addEventListener('click', () => runJob('Проверка и самоисцеление подсистемы LXC', 'lxc_doctor'));
    qs('btn-lxc-refresh-cat').addEventListener('click', async () => {
      await loadCatalog(true);
      toast('Официальный каталог LXC обновлён');
    });
    qs('inp-lxc-filter').addEventListener('input', () => {
      if (state.status) renderLxc(state.status);
    });

    const recordLxcDraft = (e) => {
      const el = e.target;
      if (el.hasAttribute('data-snap-comment')) {
        const ct = el.getAttribute('data-snap-comment');
        state.lxcDrafts[ct] = { ...(state.lxcDrafts[ct] || {}), comment: el.value };
      } else if (el.hasAttribute('data-exec-input')) {
        const ct = el.getAttribute('data-exec-input');
        state.lxcDrafts[ct] = { ...(state.lxcDrafts[ct] || {}), execCmd: el.value };
      } else if (el.hasAttribute('data-clone-target')) {
        const ct = el.getAttribute('data-clone-target');
        state.lxcDrafts[ct] = { ...(state.lxcDrafts[ct] || {}), cloneTarget: el.value };
      } else {
        const cfgForm = el.closest('[data-cfg-form]');
        if (cfgForm) {
          const ct = cfgForm.dataset.cfgForm;
          state.lxcDrafts[ct] = {
            ...(state.lxcDrafts[ct] || {}),
            cfgDirty: true,
            mem_limit: cfgForm.querySelector('[name="mem_limit"]')?.value ?? '',
            cpu_limit: cfgForm.querySelector('[name="cpu_limit"]')?.value ?? '',
            root_pass: cfgForm.querySelector('[name="root_pass"]')?.value ?? '',
            autostart: Boolean(cfgForm.querySelector('[name="autostart"]')?.checked),
            storage_mount: Boolean(cfgForm.querySelector('[name="storage_mount"]')?.checked),
            nesting: Boolean(cfgForm.querySelector('[name="nesting"]')?.checked),
          };
        }
      }
    };
    qs('lxc-cards-container').addEventListener('input', recordLxcDraft);
    qs('lxc-cards-container').addEventListener('change', recordLxcDraft);

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
        closeAllOverflowMenus();
        const ct = qSnap.dataset.lxcQuicksnap;
        state.expandedCts[ct] = true;
        state.ctSubTab[ct] = 'snaps';
        if (state.status) renderLxc(state.status);
        runJob(`Создание снимка ${ct}`, 'lxc_snap_create', ct, 'Быстрый снимок из панели');
        return;
      }

      const openSubBtn = e.target.closest('[data-lxc-open-sub]');
      if (openSubBtn) {
        closeAllOverflowMenus();
        const ct = openSubBtn.dataset.lxcCtOpen;
        state.expandedCts[ct] = true;
        state.ctSubTab[ct] = openSubBtn.dataset.lxcOpenSub;
        if (state.status) renderLxc(state.status);
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

      const cfgMemBtn = e.target.closest('[data-cfg-mem]');
      if (cfgMemBtn) {
        const ct = cfgMemBtn.dataset.cfgCt;
        const form = document.querySelector(`[data-cfg-form="${ct}"]`);
        const inp = form?.querySelector('[name="mem_limit"]');
        if (inp) {
          inp.value = cfgMemBtn.dataset.cfgMem;
          inp.dispatchEvent(new Event('input', { bubbles: true }));
        }
        return;
      }

      const cfgCpuBtn = e.target.closest('[data-cfg-cpu]');
      if (cfgCpuBtn) {
        const ct = cfgCpuBtn.dataset.cfgCt;
        const form = document.querySelector(`[data-cfg-form="${ct}"]`);
        const inp = form?.querySelector('[name="cpu_limit"]');
        if (inp) {
          inp.value = cfgCpuBtn.dataset.cfgCpu;
          inp.dispatchEvent(new Event('input', { bubbles: true }));
        }
        return;
      }

      const presetBtn = e.target.closest('[data-exec-preset]');
      if (presetBtn) {
        const ct = presetBtn.dataset.execPreset;
        const cmd = presetBtn.dataset.execCmd;
        const inp = document.querySelector(`[data-exec-input="${ct}"]`);
        if (inp) inp.value = cmd;
        state.lxcDrafts[ct] = { ...(state.lxcDrafts[ct] || {}), execCmd: cmd };
        await executeLxcCommand(ct, cmd);
        return;
      }

      const cfgSave = e.target.closest('[data-cfg-save], [data-cfg-restart]');
      if (cfgSave) {
        const ct = cfgSave.dataset.cfgSave || cfgSave.dataset.cfgRestart;
        const doRestart = Boolean(cfgSave.dataset.cfgRestart);
        const form = document.querySelector(`[data-cfg-form="${ct}"]`);
        if (!form) return;
        const memVal = form.querySelector('[name="mem_limit"]').value.trim();
        const cpuVal = form.querySelector('[name="cpu_limit"]').value.trim();
        if (memVal && !isValidLxcMem(memVal)) {
          toast('Некорректный лимит ОЗУ (пример: 512M или 2G)', 'err');
          return;
        }
        if (cpuVal && !isValidLxcCpu(cpuVal)) {
          toast('Некорректный лимит CPU (пример: 0.5, 1, 2)', 'err');
          return;
        }
        try {
          const payload = {
            name: ct,
            mem_limit: memVal,
            cpu_limit: cpuVal,
            root_pass: form.querySelector('[name="root_pass"]').value,
            autostart: form.querySelector('[name="autostart"]').checked ? 'on' : 'off',
            storage_mount: form.querySelector('[name="storage_mount"]').checked ? 'yes' : 'no',
            nesting: form.querySelector('[name="nesting"]').checked ? 'yes' : 'no',
            restart: doRestart ? 'yes' : 'no',
          };
          const res = await api('lxc_config', payload);
          if (!res.ok) throw new Error(res.error || 'Ошибка сохранения настроек');
          form.querySelector('[name="root_pass"]').value = '';
          if (state.lxcDrafts[ct]) {
            state.lxcDrafts[ct].cfgDirty = false;
            state.lxcDrafts[ct].root_pass = '';
          }
          toast(doRestart ? `Настройки ${ct} применены и контейнер перезапущен` : `Настройки ${ct} сохранены`);
          refreshStatus(true);
        } catch (err) {
          toast(err.message, 'err');
        }
        return;
      }

      const delBtn = e.target.closest('[data-lxc-delete]');
      if (delBtn) {
        closeAllOverflowMenus();
        const ct = delBtn.dataset.lxcDelete;
        if (await confirmDialog('Удалить контейнер?', `Контейнер «${ct}», его диски и все снимки будут безвозвратно удалены! Продолжить?`)) {
          delete state.expandedCts[ct];
          delete state.lxcDrafts[ct];
          runJob(`Удаление контейнера ${ct}`, 'lxc_delete', ct);
        }
        return;
      }

      const actBtn = e.target.closest('[data-lxc-act]');
      if (actBtn) {
        closeAllOverflowMenus();
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
        if (state.lxcDrafts[ct]) state.lxcDrafts[ct].comment = '';
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
        if (!/^[A-Za-z0-9_-]+$/.test(dst)) {
          toast('Имя клона может содержать только латиницу, цифры, - и _', 'err');
          dstInp?.focus();
          return;
        }
        if (dst === src) {
          toast('Имя клона должно отличаться от исходного контейнера', 'err');
          dstInp?.focus();
          return;
        }
        if (await confirmDialog('Клонировать контейнер?', `Создать клон «${dst}» из «${src}»? (Исходный контейнер на время копирования будет остановлен и вновь запущен.)`)) {
          if (state.lxcDrafts[src]) state.lxcDrafts[src].cloneTarget = '';
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

    // LXC 3-Step Creation Wizard Modal Events
    const closeCreate = () => closeModal('lxc-create-modal');
    qs('btn-lxc-create-x').addEventListener('click', closeCreate);
    qs('btn-lxc-create-cancel').addEventListener('click', closeCreate);
    qs('btn-lxc-cat-reload').addEventListener('click', () => loadCatalog(true));

    document.querySelectorAll('[data-wizard-step]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const target = Number(btn.dataset.wizardStep);
        if (target > state.wizardStep) {
          for (let s = state.wizardStep; s < target; s += 1) {
            if (!validateWizardStep(s)) return;
          }
        }
        setWizardStep(target);
      });
    });

    qs('btn-lxc-prev').addEventListener('click', () => setWizardStep(state.wizardStep - 1));
    qs('btn-lxc-next').addEventListener('click', () => {
      if (!validateWizardStep(state.wizardStep)) return;
      setWizardStep(state.wizardStep + 1);
    });

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

    // Keep distro text input synced when typed manually
    const onDistroTyped = () => {
      const val = qs('sel-lxc-distro').value.trim().toLowerCase();
      if (!val) return;
      syncDistroReleases(val, true);
      document.querySelectorAll('#lxc-distro-grid .distro-tile').forEach((t) => {
        t.classList.toggle('selected', t.dataset.pickDistro === val);
      });
    };
    qs('sel-lxc-distro').addEventListener('input', onDistroTyped);
    qs('sel-lxc-distro').addEventListener('change', onDistroTyped);

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
      const show = e.target.checked;
      qs('lxc-static-ip-fields').style.display = show ? '' : 'none';
      if (show) {
        const isMac = document.querySelector('input[name="lxc_net_mode"]:checked')?.value === 'macvlan';
        if (!qs('inp-lxc-gw').value.trim()) {
          qs('inp-lxc-gw').value = isMac ? (state.status?.network?.gw_ip || '192.168.1.1') : '10.0.3.1';
        }
        if (!qs('inp-lxc-dns').value.trim()) {
          qs('inp-lxc-dns').value = isMac ? (state.status?.network?.lan_ip || '192.168.1.82') : '10.0.3.1';
        }
      }
    });

    document.querySelectorAll('[data-mem-preset]').forEach((b) => {
      b.addEventListener('click', () => {
        qs('inp-lxc-mem').value = b.dataset.memPreset;
        renderWizardSummary();
      });
    });
    document.querySelectorAll('[data-cpu-preset]').forEach((b) => {
      b.addEventListener('click', () => {
        qs('inp-lxc-cpu').value = b.dataset.cpuPreset;
        renderWizardSummary();
      });
    });
    ['inp-lxc-mem', 'inp-lxc-cpu', 'chk-lxc-startnow', 'chk-lxc-autostart', 'chk-lxc-storage', 'chk-lxc-nesting'].forEach((id) => {
      qs(id)?.addEventListener('input', renderWizardSummary);
      qs(id)?.addEventListener('change', renderWizardSummary);
    });

    qs('frm-lxc-create').addEventListener('submit', async (e) => {
      e.preventDefault();
      for (const s of [1, 2, 3]) {
        if (!validateWizardStep(s)) {
          setWizardStep(s);
          return;
        }
      }
      const name = qs('inp-lxc-name').value.trim();
      const manual = qs('chk-lxc-manual-os').checked;
      const distro = qs('sel-lxc-distro').value.trim();
      const release = manual ? qs('inp-lxc-release-manual').value.trim() : qs('sel-lxc-release').value;
      const variant = qs('sel-lxc-variant').value || 'default';
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
    qs('btn-con-close').addEventListener('click', closeConsoleModal);
    qs('btn-con-fullscreen').addEventListener('click', () => {
      qs('console-modal-box').classList.toggle('fullscreen');
    });
    qs('btn-con-reconnect').addEventListener('click', () => {
      if (state.consoleCt) openConsole(state.consoleCt);
    });
    qs('btn-con-newtab').addEventListener('click', async () => {
      if (!state.consoleCt) return;
      const win = window.open('about:blank', '_blank');
      try {
        const res = await api('lxc_console_token', { name: state.consoleCt });
        if (!res.ok) throw new Error(res.error || 'Не удалось получить токен консоли');
        if (win && !win.closed) {
          win.opener = null;
          win.location.href = res.url;
        } else {
          window.open(res.url, '_blank', 'noopener');
        }
      } catch (err) {
        if (win && !win.closed) win.close();
        toast(err.message, 'err');
      }
    });
    document.querySelectorAll('[data-con-snippet]').forEach((b) => {
      b.addEventListener('click', () => {
        copyText(b.dataset.conSnippet, 'Команда скопирована — вставьте в терминал (Ctrl+Shift+V)');
      });
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

    qs('ssl-pki-snippets')?.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-copy-snippet]');
      if (btn) copyText(btn.dataset.copySnippet, 'Команда установки CA скопирована');
    });

    qs('btn-ssl-local').addEventListener('click', async () => {
      if (await confirmDialog('Переключить на Local PKI?', 'Перевести HTTPS на локальный центр сертификации (*.lan) и перезагрузить Caddy?')) {
        runJob('Переключение HTTPS на Local PKI (*.lan)', 'ssl_local');
      }
    });
    qs('btn-ssl-renew').addEventListener('click', () => runJob('Продление Let\'s Encrypt сертификата', 'ssl_renew'));
    qs('frm-ssl-duckdns').addEventListener('submit', async (e) => {
      e.preventDefault();
      let sub = qs('inp-duck-sub').value.trim().replace(/\.duckdns\.org$/i, '');
      const tok = qs('inp-duck-tok').value.trim();
      if (!sub || !/^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9-]+)*$/.test(sub) || sub.includes('..')) {
        toast('Укажите корректный субдомен DuckDNS (только латиница, цифры и -)', 'err');
        qs('inp-duck-sub').focus();
        return;
      }
      qs('inp-duck-sub').value = sub;
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

    qs('inp-pw1')?.addEventListener('input', () => {
      const p = qs('inp-pw1').value;
      const el = qs('pw-strength');
      if (!el) return;
      if (!p) { el.textContent = ''; return; }
      if (p.length < 4) { el.textContent = 'Слишком короткий (минимум 4 символа)'; el.style.color = 'var(--err-fg)'; }
      else if (p.length < 8) { el.textContent = 'Базовый уровень надёжности'; el.style.color = 'var(--warn-fg)'; }
      else if (/[A-Z]/.test(p) && /[0-9]/.test(p) && p.length >= 10) { el.textContent = 'Надёжный мастер-пароль'; el.style.color = 'var(--ok-fg)'; }
      else { el.textContent = 'Хороший пароль (рекомендуем цифры и заглавные)'; el.style.color = 'var(--accent)'; }
    });

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
        if (qs('pw-strength')) qs('pw-strength').textContent = '';
        toast(res.message || 'Пароль обновлён. Потребуется повторный вход.', 'info');
        showReconnectModal({
          title: 'Мастер-пароль обновлён',
          bodyHtml: '<p>Для продолжения работы обновите страницу и введите новый пароль в окне авторизации браузера.</p>',
          url: '',
        });
      } catch (err) {
        if (err.status === 401) {
          toast('Пароль обновлён — обновите страницу для повторного входа', 'info');
          showReconnectModal({
            title: 'Требуется повторный вход',
            bodyHtml: '<p>Сессия была сброшена после смены пароля. Нажмите «Обновить страницу» для входа с новым паролем.</p>',
            url: '',
          });
        } else {
          toast(err.message, 'err');
        }
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
        toast(r.status === 'UPDATE_AVAILABLE' ? `Найдено новых коммитов: ${pluralRu(r.behind, ['коммит', 'коммита', 'коммитов'])}` : 'Обновлений пока нет');
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
      state.logLoaded = false;
      state.rawLogText = '';
      view.textContent = 'Загрузка лога...';
      try {
        const res = await api('get_logs', { target, lines });
        if (!res.ok) throw new Error(res.error || 'Ошибка чтения лога');
        state.rawLogText = res.log || '(Лог пуст)';
        state.logLoaded = true;
        renderFilteredLogs();
      } catch (err) {
        state.rawLogText = '';
        state.logLoaded = false;
        view.textContent = `Ошибка: ${err.message}`;
      }
    });

    document.querySelectorAll('[data-log-sev]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.logSeverity = btn.dataset.logSev;
        document.querySelectorAll('[data-log-sev]').forEach((b) => b.classList.toggle('active', b === btn));
        renderFilteredLogs();
      });
    });

    qs('inp-log-filter').addEventListener('input', renderFilteredLogs);

    qs('btn-log-copy').addEventListener('click', () => {
      if (!state.logLoaded || !state.rawLogText) {
        toast('Сначала загрузите лог кнопкой «Показать лог»', 'err');
        return;
      }
      const matched = getFilteredLogLines();
      if (!matched.length) {
        toast('Нет строк для копирования по текущему фильтру', 'err');
        return;
      }
      copyText(matched.join('\n'), 'Текст лога скопирован');
    });

    qs('btn-log-download').addEventListener('click', () => {
      if (!state.logLoaded || !state.rawLogText) {
        toast('Сначала загрузите лог кнопкой «Показать лог»', 'err');
        return;
      }
      const matched = getFilteredLogLines();
      const txt = matched.length ? matched.join('\n') : state.rawLogText;
      const tgt = qs('sel-log-target').value || 'gateway';
      const blob = new Blob([txt + '\n'], { type: 'text/plain;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `gateway-${tgt}.log`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast(`Лог gateway-${tgt}.log сохранён`);
    });
  }

  initTheme();
  bindEvents();
  refreshStatus(true);
  state.pollTimer = setInterval(() => refreshStatus(false), 15000);
})();
