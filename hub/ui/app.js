// Dev-Toolbox Hub 前端（ui-kit 3.0）。只與 Hub 後端（同 origin）通訊；工具畫面由 iframe 承載。
'use strict';

const $ = (id) => document.getElementById(id);
const els = {
  nav: $('toolNav'), navSettings: $('navSettings'), hubVersion: $('hubVersion'), hubInfo: $('hubInfo'),
  pageTool: $('pageTool'), pageSettings: $('pageSettings'),
  toolName: $('toolName'), toolBadge: $('toolBadge'), toolStatus: $('toolStatus'),
  btnStart: $('btnStart'), btnStop: $('btnStop'), btnReload: $('btnReload'), btnPopout: $('btnPopout'),
  frameBox: $('frameBox'), frame: $('toolFrame'), placeholder: $('placeholder'),
  phIcon: $('phIcon'), phTitle: $('phTitle'), phDesc: $('phDesc'), phMeta: $('phMeta'),
  phCallout: $('phCallout'), phHint: $('phHint'), phStart: $('phStart'),
  swatches: $('swatches'), pySources: $('pySources'), pyManual: $('pyManual'), pyPath: $('pyPath'),
  pyCheck: $('pyCheck'), pyResult: $('pyResult'), pySaved: $('pySaved'), pySave: $('pySave'),
  toastArea: $('toastArea'), confirmBackdrop: $('confirmBackdrop'), confirmIcon: $('confirmIcon'),
  confirmTitle: $('confirmTitle'), confirmText: $('confirmText'), confirmOk: $('confirmOk'), confirmCancel: $('confirmCancel'),
};

const TOOL_ICONS = { 'git-ref-manager': 'git-branch', 'opencode-cfg-manager': 'package', 'key-manager': 'key' };
const ACCENT_NAMES = { blue: '藍', green: '綠', violet: '紫', orange: '橘', rose: '玫瑰' };

const params = new URLSearchParams(location.search);
const state = {
  tools: [],
  page: params.get('page') === 'settings' ? 'settings' : 'tool',
  selected: params.get('tool') || load('hub.selected') || null,
  busy: {},          // id -> 'start' | 'stop'
  frameKey: '',      // 避免每次 poll 重設 iframe.src
  frameOrigin: '',
  lastError: {},     // id -> message
  failCount: 0,      // 連續連線失敗次數；偶發一次不顯示錯誤
  pollTimer: null,
  settings: { pythonPath: '' },
};

function load(k) { try { return localStorage.getItem(k); } catch (_) { return null; } }
function save(k, v) { try { localStorage.setItem(k, v); } catch (_) { /* 只影響記憶 */ } }
function icon(name, opts) { return window.TbIcons ? TbIcons.svg(name, opts || {}) : ''; }
function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

// ---------- 基礎 API ----------
async function apiPost(path, body) {
  const resp = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Toolbox-Request': '1' },
    body: JSON.stringify(body || {}),
  });
  let data = null;
  try { data = await resp.json(); } catch (_) { /* 非 JSON 回應 */ }
  if (!data || data.ok !== true) {
    const msg = (data && data.error && data.error.message) || `HTTP ${resp.status}`;
    const err = new Error(msg);
    err.code = data && data.error ? data.error.code : 'HTTP_ERROR';
    throw err;
  }
  return data;
}

async function apiGet(path) {
  const resp = await fetch(path);
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.json();
}

// ---------- 通知與確認 ----------
const TOAST_ICONS = { ok: 'circle-check', danger: 'triangle-alert', warn: 'triangle-alert', info: 'info' };
function toast(kind, text, ms = 4200) {
  const t = el('div', `tb-toast tb-toast--${kind}`);
  t.innerHTML = icon(TOAST_ICONS[kind] || 'info');
  t.appendChild(el('span', '', text));
  els.toastArea.appendChild(t);
  setTimeout(() => t.remove(), ms);
}

function confirmDialog(title, text) {
  return new Promise((resolve) => {
    const opener = document.activeElement; // 關閉後把焦點還回去
    els.confirmIcon.innerHTML = icon('triangle-alert', { size: 22 });
    els.confirmTitle.textContent = title;
    els.confirmText.textContent = text;
    els.confirmBackdrop.classList.remove('tb-hidden');
    els.confirmCancel.focus();
    const done = (val) => {
      els.confirmBackdrop.classList.add('tb-hidden');
      if (opener && typeof opener.focus === 'function' && document.contains(opener)) opener.focus();
      els.confirmOk.removeEventListener('click', okFn);
      els.confirmCancel.removeEventListener('click', cancelFn);
      els.confirmBackdrop.removeEventListener('click', backFn);
      document.removeEventListener('keydown', keyFn, true);
      resolve(val);
    };
    const okFn = () => done(true);
    const cancelFn = () => done(false);
    const backFn = (ev) => { if (ev.target === els.confirmBackdrop) done(false); };
    const keyFn = (ev) => {
      if (ev.key === 'Escape') { done(false); return; }
      if (ev.key === 'Tab') { // 對話框只有兩個按鈕，Tab 在兩者間循環
        ev.preventDefault();
        (document.activeElement === els.confirmOk ? els.confirmCancel : els.confirmOk).focus();
      }
    };
    els.confirmOk.addEventListener('click', okFn);
    els.confirmCancel.addEventListener('click', cancelFn);
    els.confirmBackdrop.addEventListener('click', backFn);
    document.addEventListener('keydown', keyFn, true);
  });
}

// ---------- 狀態判定 ----------
function toolById(id) { return state.tools.find((t) => t.id === id) || null; }
function toolState(t) {
  if (state.busy[t.id]) return 'busy';
  if (!t.installed) return 'missing';
  if (t.running) return 'running';
  return 'stopped';
}
const DOT = { busy: 'tb-dot tb-dot--busy', running: 'tb-dot tb-dot--ok', missing: 'tb-dot tb-dot--danger', stopped: 'tb-dot' };
const BADGE = {
  busy: ['tb-badge tb-badge--accent', '處理中'], running: ['tb-badge tb-badge--ok', '執行中'],
  missing: ['tb-badge tb-badge--danger', '未安裝'], stopped: ['tb-badge', '未啟動'],
};
function stateLabel(t) {
  const s = toolState(t);
  if (s === 'busy') return state.busy[t.id] === 'start' ? '啟動中…' : '停止中…';
  if (s === 'missing') return t.error || '未安裝';
  if (s === 'running') {
    const r = t.running;
    return `v${t.version} · 127.0.0.1:${r.port} · pid ${r.pid}${r.managed ? '' : '（非 Hub 啟動）'}`;
  }
  return t.web ? `v${t.version}` : `v${t.version} · 只有 CLI`;
}

// ---------- 主題同步到 iframe ----------
function postThemeToFrame() {
  if (!state.frameOrigin || !els.frame.contentWindow) return;
  const t = TbTheme.get();
  try { els.frame.contentWindow.postMessage({ type: 'tb-theme', mode: t.mode, accent: t.accent }, state.frameOrigin); } catch (_) { /* 尚未載入 */ }
}
els.frame.addEventListener('load', postThemeToFrame);

function setFrame(t) {
  if (!t || !t.running) {
    if (els.frame.getAttribute('src')) els.frame.removeAttribute('src');
    state.frameKey = ''; state.frameOrigin = '';
    return;
  }
  const key = t.running.url;
  if (key === state.frameKey) return;
  state.frameKey = key;
  state.frameOrigin = new URL(t.running.url).origin;
  els.frame.src = `${t.running.url}/?${TbTheme.query()}&embedded=1`;
}

// ---------- 畫面 ----------
function renderNav() {
  els.nav.innerHTML = '';
  for (const t of state.tools) {
    const s = toolState(t);
    const a = el('a', 'tb-nav__item hub-nav__tool');
    a.href = `?tool=${encodeURIComponent(t.id)}`;
    if (state.page === 'tool' && t.id === state.selected) a.setAttribute('aria-current', 'page');
    a.title = `${t.name}｜${stateLabel(t)}`;
    a.innerHTML = icon(TOOL_ICONS[t.id] || 'square', { anim: 'pop' });
    a.appendChild(el('span', 'tb-nav__label', t.name));
    const dot = el('span', `${DOT[s]} hub-nav__dot`);
    dot.setAttribute('aria-hidden', 'true');
    a.appendChild(dot);
    a.addEventListener('click', (ev) => { ev.preventDefault(); select(t.id); });
    els.nav.appendChild(a);
  }
  if (state.page === 'settings') els.navSettings.setAttribute('aria-current', 'page');
  else els.navSettings.removeAttribute('aria-current');
}

function kv(rows) {
  els.phMeta.innerHTML = '';
  for (const [k, v] of rows) {
    const dd = el('dd');
    dd.appendChild(el('code', '', v));
    els.phMeta.append(el('dt', '', k), dd);
  }
}

function renderPlaceholder(title, desc, iconName, hint) {
  els.frameBox.classList.add('tb-hidden');
  els.placeholder.classList.remove('tb-hidden');
  els.phIcon.innerHTML = icon(iconName, { size: 20 });
  els.phTitle.textContent = title;
  els.phDesc.textContent = desc || '';
  els.phHint.textContent = hint || '';
  els.phCallout.classList.toggle('tb-hidden', !hint);
}

function renderTool() {
  const t = state.selected ? toolById(state.selected) : null;
  if (!t) {
    els.toolName.textContent = 'Dev-Toolbox';
    els.toolBadge.className = 'tb-hidden';
    els.toolStatus.textContent = '';
    [els.btnStart, els.btnStop, els.btnReload, els.btnPopout].forEach((b) => { b.disabled = true; });
    els.phMeta.innerHTML = '';
    els.phStart.classList.add('tb-hidden');
    renderPlaceholder(state.tools.length ? '請選擇工具' : '尚未安裝任何工具',
      state.tools.length ? '從左側選一個工具開始。' : 'tools\\ 目錄下沒有工具。', 'layout-dashboard',
      state.tools.length ? '' : '請先執行 Setup.bat 初始化 submodule。');
    setFrame(null);
    return;
  }
  const s = toolState(t);
  els.toolName.textContent = t.name;
  els.toolBadge.className = BADGE[s][0];
  els.toolBadge.textContent = BADGE[s][1];
  els.toolStatus.textContent = stateLabel(t);

  const canStart = s === 'stopped' && t.web;
  els.btnStart.disabled = !canStart;
  els.btnStop.disabled = s !== 'running' || !t.running.managed;
  els.btnReload.disabled = s !== 'running';
  els.btnPopout.disabled = s !== 'running';
  els.btnStart.classList.toggle('is-busy', state.busy[t.id] === 'start');
  els.btnStop.classList.toggle('is-busy', state.busy[t.id] === 'stop');
  els.btnStop.title = t.running && !t.running.managed ? '這個服務不是由 Hub 啟動，無法在這裡停止' : '';

  if (s === 'running') {
    els.placeholder.classList.add('tb-hidden');
    els.frameBox.classList.remove('tb-hidden');
    setFrame(t);
    return;
  }
  setFrame(null);
  const rows = [['版本', t.version || '?'], ['執行環境', t.runtime || '?']];
  if (t.web) rows.push(['預設 port', `${t.port}（被占用時自動換）`]);
  kv(rows);
  let hint = '';
  if (!t.installed) hint = `${t.error || '未安裝'}。請執行 Setup.bat。`;
  else if (!t.web) hint = `這個工具沒有 Web 模式，請用 CLI：hub run ${t.id}`;
  else if (state.lastError[t.id]) hint = `上次啟動失敗：${state.lastError[t.id]}`;
  renderPlaceholder(t.name, t.desc || '', TOOL_ICONS[t.id] || 'square', hint);
  els.phStart.classList.toggle('tb-hidden', !t.web || !t.installed);
  els.phStart.disabled = !canStart;
  els.phStart.classList.toggle('is-busy', state.busy[t.id] === 'start');
}

function renderAll() {
  els.pageTool.classList.toggle('tb-hidden', state.page !== 'tool');
  els.pageSettings.classList.toggle('tb-hidden', state.page !== 'settings');
  renderNav();
  if (state.page === 'tool') renderTool();
}

// ---------- 導覽 ----------
function setUrl() {
  const q = state.page === 'settings' ? '?page=settings' : (state.selected ? `?tool=${encodeURIComponent(state.selected)}` : location.pathname);
  history.replaceState(null, '', q);
}

function select(id) {
  state.page = 'tool';
  state.selected = id;
  save('hub.selected', id);
  setUrl();
  renderAll();
}

function openSettings() {
  state.page = 'settings';
  setUrl();
  renderAll();
  loadPython();
}

// ---------- 工具操作 ----------
async function refresh() {
  try {
    const data = await apiGet('/api/tools');
    state.tools = data.tools || [];
    if (!state.selected || !toolById(state.selected)) {
      state.selected = state.tools.length ? state.tools[0].id : null;
      if (state.page === 'tool') setUrl();
    }
    state.failCount = 0;
    renderAll();
  } catch (err) {
    state.failCount += 1;
    if (state.failCount === 1) { setTimeout(refresh, 800); return; }  // 先安靜重試一次
    if (state.page !== 'tool') return;
    els.phStart.classList.add('tb-hidden');
    els.phMeta.innerHTML = '';
    renderPlaceholder('Hub 後端連線失敗', '', 'triangle-alert', `${err.message}（Hub 視窗是否已關閉？）`);
  }
}

async function startTool(id) {
  if (!id || state.busy[id]) return;
  state.busy[id] = 'start';
  delete state.lastError[id];
  renderAll();
  try {
    const r = await apiPost('/api/tools/start', { id });
    toast('ok', `已啟動（port ${r.result.port}）`);
  } catch (err) {
    state.lastError[id] = err.message;
    toast('danger', `啟動失敗：${err.message}`, 7000);
  } finally {
    delete state.busy[id];
    await refresh();
  }
}

async function stopTool(id) {
  if (!id || state.busy[id]) return;
  const ok = await confirmDialog('停止工具', `確定要停止「${(toolById(id) || {}).name}」？進行中的工作會被中斷。`);
  if (!ok) return;
  state.busy[id] = 'stop';
  renderAll();
  try {
    await apiPost('/api/tools/stop', { id });
    toast('ok', '已停止');
  } catch (err) {
    toast('danger', `停止失敗：${err.message}`, 7000);
  } finally {
    delete state.busy[id];
    await refresh();
  }
}

// ---------- 設定：外觀 ----------
function buildSwatches() {
  els.swatches.innerHTML = '';
  for (const k of TbTheme.accents) {
    const b = el('button', 'tb-swatch');
    b.type = 'button';
    b.dataset.accent = k;
    b.title = ACCENT_NAMES[k] || k;
    b.setAttribute('aria-label', b.title);
    b.addEventListener('click', () => TbTheme.setAccent(k));
    els.swatches.appendChild(b);
  }
}
function syncThemeControls() {
  const t = TbTheme.get();
  document.querySelectorAll('[data-mode]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.mode === t.mode)));
  els.swatches.querySelectorAll('.tb-swatch').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.accent === t.accent)));
}
document.querySelectorAll('[data-mode]').forEach((b) => b.addEventListener('click', () => TbTheme.set(b.dataset.mode)));
document.addEventListener('tb-theme-change', () => { syncThemeControls(); postThemeToFrame(); });

// ---------- 設定：Python ----------
function pyMode() {
  const r = document.querySelector('input[name=pyMode]:checked');
  return r ? r.value : 'auto';
}
function setPyMode(m) {
  document.querySelectorAll('input[name=pyMode]').forEach((r) => { r.checked = r.value === m; });
  els.pyManual.classList.toggle('tb-hidden', m !== 'manual');
}
document.querySelectorAll('input[name=pyMode]').forEach((r) => r.addEventListener('change', () => {
  setPyMode(pyMode());
  if (pyMode() === 'manual') els.pyPath.focus();
}));

function pyRow(iconName, title, sub, badge) {
  const row = el('div', 'tb-list__item');
  row.innerHTML = icon(iconName, { size: 16 });
  const main = el('div', 'tb-list__main');
  main.appendChild(el('div', 'tb-list__title', title));
  main.appendChild(el('div', 'tb-list__sub tb-mono', sub));
  row.appendChild(main);
  if (badge) row.appendChild(el('span', 'tb-badge tb-badge--accent', badge));
  return row;
}

function renderPySources(data) {
  els.pySources.innerHTML = '';
  const auto = (data.sources || []).filter((c) => c.source !== 'settings'); // 指定路徑在下方另外處理
  const used = auto.find((c) => c.usable);
  for (const c of auto) {
    const iconName = c.usable ? 'circle-check' : (c.found ? 'triangle-alert' : 'x');
    const sub = c.found ? [c.path, c.version, c.message].filter(Boolean).join(' · ') : '找不到';
    els.pySources.appendChild(pyRow(iconName, c.label, sub, used && c.source === used.source ? '會使用' : ''));
  }
  for (const t of data.tools || []) {
    if (t.source === 'venv') els.pySources.appendChild(pyRow(TOOL_ICONS[t.id] || 'square', `${t.name} 用自己的 .venv`, t.path, ''));
  }
  if (!els.pySources.children.length) els.pySources.appendChild(el('div', 'tb-muted tb-small', '偵測不到任何 Python。'));
}

async function loadPython() {
  els.pySources.innerHTML = '';
  els.pySources.appendChild(el('div', 'tb-muted tb-small', '偵測中…'));
  try {
    const [s, p] = await Promise.all([apiGet('/api/settings'), apiGet('/api/python')]);
    state.settings = s.settings || { pythonPath: '' };
    els.pyPath.value = state.settings.pythonPath || '';
    setPyMode(state.settings.pythonPath ? 'manual' : 'auto');
    els.pySaved.textContent = state.settings.pythonPath ? '目前：使用指定路徑' : '目前：自動偵測';
    renderPySources(p);
  } catch (err) {
    els.pySources.innerHTML = '';
    els.pySources.appendChild(el('div', 'tb-muted tb-small', `讀取失敗：${err.message}`));
  }
}

function setPyResult(kind, text) {
  els.pyResult.textContent = text;
  els.pyResult.className = `tb-field__hint${kind ? ` hub-py-result--${kind}` : ''}`;
}

async function checkPython() {
  const p = els.pyPath.value.trim();
  if (!p) { setPyResult('danger', '請先輸入路徑。'); els.pyPath.focus(); return; }
  els.pyCheck.classList.add('is-busy');
  try {
    const r = (await apiPost('/api/python/check', { path: p })).result;
    if (r.usable) setPyResult('ok', `可以使用：Python ${r.version}`);
    else setPyResult('danger', `不能使用：${r.message}`);
  } catch (err) {
    setPyResult('danger', `檢查失敗：${err.message}`);
  } finally {
    els.pyCheck.classList.remove('is-busy');
  }
}

async function savePython() {
  const manual = pyMode() === 'manual';
  const p = manual ? els.pyPath.value.trim() : '';
  if (manual && !p) { setPyResult('danger', '請先輸入路徑，或改選自動偵測。'); els.pyPath.focus(); return; }
  els.pySave.classList.add('is-busy');
  try {
    const r = await apiPost('/api/settings', { pythonPath: p });
    state.settings = r.settings;
    toast('ok', manual ? 'Python 路徑已儲存，下次啟動 Python 工具時生效' : '已改回自動偵測');
    await loadPython();
  } catch (err) {
    setPyResult('danger', err.message);
    toast('danger', `儲存失敗：${err.message}`, 7000);
  } finally {
    els.pySave.classList.remove('is-busy');
  }
}
els.pyCheck.addEventListener('click', checkPython);
els.pySave.addEventListener('click', savePython);
els.pyPath.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') checkPython(); });

// ---------- 週期更新（分頁不可見時暫停） ----------
function startPolling() {
  if (state.pollTimer) clearInterval(state.pollTimer);
  state.pollTimer = setInterval(() => { if (!document.hidden) refresh(); }, 3000);
}
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });

// ---------- 綁定 ----------
els.navSettings.addEventListener('click', (ev) => { ev.preventDefault(); openSettings(); });
els.btnStart.addEventListener('click', () => startTool(state.selected));
els.phStart.addEventListener('click', () => startTool(state.selected));
els.btnStop.addEventListener('click', () => stopTool(state.selected));
els.btnReload.addEventListener('click', () => {
  const t = toolById(state.selected);
  if (t && t.running) { state.frameKey = ''; setFrame(t); }
});
els.btnPopout.addEventListener('click', () => {
  const t = toolById(state.selected);
  if (t && t.running) window.open(`${t.running.url}/?${TbTheme.query()}`, '_blank', 'noopener');
});

// ---------- 啟動 ----------
(async function init() {
  if (window.TbIcons) TbIcons.render(document);
  buildSwatches();
  syncThemeControls();
  renderAll();
  if (state.page === 'settings') loadPython();
  try {
    const h = await apiGet('/api/health');
    els.hubVersion.textContent = `Hub v${h.version}`;
    els.hubInfo.textContent = `127.0.0.1:${h.port} · 只綁本機`;
  } catch (_) { /* 拿不到版本不影響使用 */ }
  await refresh();
  startPolling();
})();
