// Dev-Toolbox Hub 前端（ui-kit 3.0）。只與 Hub 後端（同 origin）通訊；工具畫面由 iframe 承載。
'use strict';

const $ = (id) => document.getElementById(id);
const els = {
  nav: $('toolNav'), navSettings: $('navSettings'), navDash: $('navDash'), navTheme: $('navTheme'),
  hubVersion: $('hubVersion'), hubInfo: $('hubInfo'),
  pageTool: $('pageTool'), pageSettings: $('pageSettings'), pageDash: $('pageDash'),
  dashGrid: $('dashGrid'), dashSummary: $('dashSummary'), dashRefresh: $('dashRefresh'),
  dashActs: $('dashActs'), dashShutdown: $('dashShutdown'),
  toolName: $('toolName'), toolBadge: $('toolBadge'), toolStatus: $('toolStatus'),
  toolUpdate: $('toolUpdate'), hubUpdate: $('hubUpdate'),
  btnStop: $('btnStop'), btnReload: $('btnReload'), btnPopout: $('btnPopout'),
  frameBox: $('frameBox'), placeholder: $('placeholder'),
  phIcon: $('phIcon'), phTitle: $('phTitle'), phDesc: $('phDesc'), phMeta: $('phMeta'),
  phCallout: $('phCallout'), phHint: $('phHint'), phStart: $('phStart'),
  swatches: $('swatches'), bgSeg: $('bgSeg'), strengthSeg: $('strengthSeg'), pySources: $('pySources'), pyManual: $('pyManual'), pyPath: $('pyPath'),
  pyCheck: $('pyCheck'), pyResult: $('pyResult'), pySaved: $('pySaved'), pySave: $('pySave'),
  toastArea: $('toastArea'), confirmBackdrop: $('confirmBackdrop'), confirmIcon: $('confirmIcon'),
  confirmTitle: $('confirmTitle'), confirmText: $('confirmText'), confirmOk: $('confirmOk'), confirmCancel: $('confirmCancel'),
};

const TOOL_ICONS = {
  'git-ref-manager': 'git-branch', 'agents-cfg-manager': 'package', 'key-manager': 'key',
  'build-runner': 'terminal', 'hlk-viewer': 'shield', 'script-editor': 'file-code',
  'token-meter': 'layout-dashboard'
};
const ACCENT_NAMES = { blue: '藍', green: '綠', violet: '紫', orange: '橘', rose: '玫瑰' };

const params = new URLSearchParams(location.search);
const state = {
  tools: [],
  // 預設首頁是總覽；?tool= 直達工具頁、?page=settings 直達設定頁（舊書籤 URL 仍有效）
  page: ['settings', 'manage'].includes(params.get('page')) ? params.get('page')
    : (params.get('tool') && params.get('page') !== 'dash') ? 'tool' : 'dash',
  selected: params.get('tool') || load('hub.selected') || null,
  busy: {},          // id -> 'start' | 'stop'
  lastError: {},     // id -> message
  activity: null,    // /api/activity 最近的工作（總覽頁輪詢）
  dashFp: '',        // 總覽卡片的渲染指紋：資料沒變就不重建（避免 5 秒輪詢打斷懸浮按鈕）
  failCount: 0,      // 連續連線失敗次數；偶發一次不顯示錯誤
  pollTimer: null,
  hubClosed: false,
  settings: { pythonPath: '' },
  hub: null,         // /api/health 回傳（版本／port/uptime），供總覽摘要列
  hubAt: 0,          // 取得 state.hub 的時間（performance.now），讓 uptime 在兩次輪詢之間逐秒前進
  loaded: false,     // 第一次 /api/tools 成功前為 false：總覽顯示「讀取中…」而不是 0 / 0
  uptimeTimer: null,
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

function confirmDialog(title, text, options = {}) {
  if (!els.confirmBackdrop.classList.contains('tb-hidden')) return Promise.resolve(false);
  return new Promise((resolve) => {
    const opener = document.activeElement; // 關閉後把焦點還回去
    els.confirmIcon.innerHTML = icon('triangle-alert', { size: 22 });
    els.confirmTitle.textContent = title;
    els.confirmText.textContent = text;
    els.confirmOk.textContent = options.label || '確定';
    els.confirmOk.classList.toggle('tb-btn--danger', !options.label);
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
function visibleTools() { return state.tools.filter((t) => t.installed && !t.hidden); }
function toolById(id) { return visibleTools().find((t) => t.id === id) || null; }
function toolIcon(t) {
  return /^[a-z0-9][a-z0-9-]{0,39}$/.test(t.icon || '') ? t.icon
    : TOOL_ICONS[t.id] || (t.source === 'link' ? 'external-link' : 'square');
}
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
  if (t.source === 'link') return '網站連結';
  const s = toolState(t);
  if (s === 'busy') return busyLabel(state.busy[t.id]);
  if (s === 'missing') return t.error || '未安裝';
  if (s === 'running') {
    const r = t.running;
    return `v${t.version} · 127.0.0.1:${r.port} · pid ${r.pid}${r.managed ? '' : '（非 Hub 啟動）'}`;
  }
  return t.web ? `v${t.version}` : `v${t.version} · 只有 CLI`;
}

function busyLabel(action) {
  return { start: '啟動中…', stop: '停止中…', update: '下載並安裝中…' }[action];
}

// ---------- 工具 iframe（keep-alive） ----------
// 每個看過的工具一個 panel＋iframe：切頁只 hide/show，不重建、不重新載入，
// 工具頁面狀態（表單、進行中的工作面板等）完整保留；工具停止或 port 變更才銷毀。
const frames = new Map();   // id -> { panel, frame, url, origin }

function createFrame(t) {
  const panel = el('div', 'hub-frame-panel tb-hidden');
  const frame = el('iframe');
  frame.title = t.name || '工具畫面';
  frame.setAttribute('referrerpolicy', 'no-referrer');
  const origin = new URL(t.running.url).origin;
  frame.addEventListener('load', () => {
    const th = TbTheme.get();
    try { frame.contentWindow.postMessage({ type: 'tb-theme', mode: th.mode, accent: th.accent }, origin); } catch (_) { /* 尚未載入 */ }
  });
  const src = `${t.running.url}/?${TbTheme.query()}&embedded=1`;
  frame.src = src;
  panel.appendChild(frame);
  els.frameBox.appendChild(panel);
  const rec = { panel, frame, url: t.running.url, src, origin };
  frames.set(t.id, rec);
  return rec;
}

function destroyFrame(id) {
  const rec = frames.get(id);
  if (!rec) return;
  rec.panel.remove();   // 移出 DOM 即卸載 iframe
  frames.delete(id);
}

// 每次重新render：工具已停止或 port 變更的 frame 立即銷毀（下次顯示時重建）
function syncFrames() {
  for (const [id, rec] of frames) {
    const t = toolById(id);
    if (!t || !t.running || t.running.url !== rec.url) destroyFrame(id);
  }
}

// 主題變更：广播給所有 frame（含隱藏中的，切回來時也是正確主題）
function postThemeToFrames() {
  const th = TbTheme.get();
  for (const rec of frames.values()) {
    try { rec.frame.contentWindow.postMessage({ type: 'tb-theme', mode: th.mode, accent: th.accent }, rec.origin); } catch (_) { /* 尚未載入 */ }
  }
}

function showFrame(t) {
  for (const rec of frames.values()) rec.panel.classList.add('tb-hidden');
  if (!t || !t.running) return;
  (frames.get(t.id) || createFrame(t)).panel.classList.remove('tb-hidden');
}

// ---------- 畫面 ----------
function renderNav() {
  els.nav.innerHTML = '';
  for (const t of visibleTools()) {
    const s = toolState(t);
    const a = el('a', 'tb-nav__item hub-nav__tool');
    a.href = `?tool=${encodeURIComponent(t.id)}`;
    if (state.page === 'tool' && t.id === state.selected) a.setAttribute('aria-current', 'page');
    a.title = `${t.name}｜${stateLabel(t)}`;
    a.innerHTML = icon(toolIcon(t), { anim: 'pop' });
    a.appendChild(el('span', 'tb-nav__label', t.name));
    const dot = el('span', `${DOT[s]} hub-nav__dot`);
    dot.setAttribute('aria-hidden', 'true');
    a.appendChild(dot);
    a.addEventListener('click', (ev) => { ev.preventDefault(); if (t.url) openLink(t); else select(t.id); });
    els.nav.appendChild(a);
  }
  if (state.page === 'dash') els.navDash.setAttribute('aria-current', 'page');
  else els.navDash.removeAttribute('aria-current');
  if (state.page === 'settings') els.navSettings.setAttribute('aria-current', 'page');
  else els.navSettings.removeAttribute('aria-current');
  if (state.page === 'manage') $('navManage').setAttribute('aria-current', 'page');
  else $('navManage').removeAttribute('aria-current');
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
  renderUpdateButton(els.toolUpdate, t?.canUpdate ? t : null);
  if (!t) {
    els.toolName.textContent = 'Dev-Toolbox';
    els.toolBadge.className = 'tb-hidden';
    els.toolStatus.textContent = '';
    [els.btnStop, els.btnReload, els.btnPopout].forEach((b) => { b.disabled = true; });
    els.phMeta.innerHTML = '';
    els.phStart.classList.add('tb-hidden');
    renderPlaceholder('請選擇工具', '從側邊欄開啟工具，或到「管理工具」新增。', 'layout-dashboard', '');
    showFrame(null);
    return;
  }
  const s = toolState(t);
  els.toolName.textContent = t.name;
  els.toolBadge.className = BADGE[s][0];
  els.toolBadge.textContent = BADGE[s][1];
  els.toolStatus.textContent = stateLabel(t);

  const canStart = s === 'stopped' && (t.web || t.cli);
  // 右上不放啟動钮（入口是佔位頁的「啟動這個工具」）；停止钮只在啟動後
  // （含啟動中/停止中，便于顯示 spinner）才顯示。
  const showActions = s === 'running' || s === 'busy';
  els.btnStop.classList.toggle('tb-hidden', !showActions);
  els.btnStop.disabled = s !== 'running' || !t.running.managed;
  els.btnReload.disabled = s !== 'running';
  els.btnPopout.disabled = s !== 'running';
  els.btnStop.classList.toggle('is-busy', state.busy[t.id] === 'stop');
  els.btnStop.title = t.running && !t.running.managed ? '這個服務不是由 Hub 啟動，無法在這裡停止' : '';

  if (s === 'running') {
    els.placeholder.classList.add('tb-hidden');
    els.frameBox.classList.remove('tb-hidden');
    showFrame(t);
    return;
  }
  showFrame(null);
  const rows = [['版本', t.version || '?'], ['執行環境', t.runtime || '?']];
  if (t.web) rows.push(['預設 port', `${t.port}（被占用時自動換）`]);
  kv(rows);
  let hint = '';
  if (!t.installed) hint = `${t.error || '未安裝'}。請執行 Setup.bat。`;
  else if (!t.web && t.cli) hint = '開啟後會在新的終端機視窗執行。';
  else if (state.lastError[t.id]) hint = `上次啟動失敗：${state.lastError[t.id]}`;
  renderPlaceholder(t.name, t.desc || '', toolIcon(t), hint);
  els.phStart.classList.toggle('tb-hidden', !(t.web || t.cli) || !t.installed);
  els.phStart.disabled = !canStart;
  els.phStart.classList.toggle('is-busy', state.busy[t.id] === 'start');
}

// ---------- 總覽（dashboard） ----------
function fmtUptime(sec) {
  sec = Math.max(0, Math.floor(+sec || 0));
  const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
  return h ? `${h} 小時 ${m} 分` : (m ? `${m} 分 ${sec % 60} 秒` : `${sec} 秒`);
}

// 摘要列：uptime 以最後一次 /api/health 的值加上本機經過時間推算，每秒更新
function renderDashSummary() {
  if (state.hubClosed) return;
  if (!state.loaded) { els.dashSummary.textContent = '讀取中…'; return; }
  const tools = visibleTools().filter((t) => !t.url);
  const run = tools.filter((t) => t.running).length;
  const parts = [`${run} / ${tools.length} 個工具執行中`];
  if (state.hub) {
    const sec = (+state.hub.uptimeSec || 0) + (performance.now() - state.hubAt) / 1000;
    parts.push(`Hub 已運行 ${fmtUptime(sec)}`);
  }
  els.dashSummary.textContent = parts.join('　·　');
}

function renderDash() {
  if (state.hubClosed) {
    els.pageDash.classList.add('is-closed');
    els.dashSummary.textContent = 'Hub 已關閉，可以關閉此分頁。';
    return;
  }
  renderDashSummary();
  if (!state.loaded) return;   // 清單還沒回來：保留「讀取中…」，不畫空卡片

  // 卡片是整組重建的：資料（含 busy／activity）沒變就不重建，
  // 否則 5 秒輪詢會重置過渡動畫，也容易打斷正在懸浮操作按鈕的滑鼠。
  const fp = JSON.stringify([state.tools, state.busy, state.activity]);
  if (fp === state.dashFp) return;
  state.dashFp = fp;

  els.dashGrid.innerHTML = '';
  $('dashEmpty').classList.toggle('tb-hidden', visibleTools().length > 0);
  for (const t of visibleTools()) {
    if (t.url) {
      const link = el('article', 'tb-card hub-library-row');
      const text = el('div', 'hub-library-info');
      text.append(el('strong', '', t.name), el('div', 'tb-muted', t.desc || t.url));
      link.append(text, libraryButton('開啟', () => openLink(t)));
      els.dashGrid.appendChild(link);
      continue;
    }
    const s = toolState(t);
    const busy = state.busy[t.id];
    const card = el('article', 'tb-card tb-card--interactive hub-tool-card');
    if (s !== 'missing') card.tabIndex = 0;
    card.setAttribute('data-tool', t.id);

    const top = el('div', 'hub-tool-card__top');
    const ic = el('span', 'tb-card__icon');
    ic.innerHTML = icon(toolIcon(t));
    top.appendChild(ic);
    top.appendChild(el('span', 'hub-tool-card__name', t.name));
    top.appendChild(el('span', DOT[s]));   // 右上狀態點：綠／藍 pulse／灰／紅（ui-kit tb-dot）
    card.appendChild(top);

    let stateText = BADGE[s][1];
    if (s === 'busy') stateText = busyLabel(busy);
    card.appendChild(el('div', 'hub-tool-card__state', stateText));

    let sub;
    if (s === 'running') sub = `127.0.0.1:${t.running.port} · v${t.version}${t.running.managed ? '' : ' · 非 Hub 啟動'}`;
    else if (s === 'busy') sub = t.version ? `v${t.version}` : '';
    else if (s === 'missing') sub = t.error || '未安裝';
    else sub = [t.runtimeDetail, t.version ? `v${t.version}` : ''].filter(Boolean).join(' · ');
    card.appendChild(el('div', 'tb-muted tb-small hub-tool-card__sub', sub));

    // 快速操作：懸浮／鍵盤聚焦才浮現的小钮（啟動中/停止中常駐以顯示 spinner）；
    // 規則與工具頁相同——啟動只給未啟動、停止只給執行中。
    if (busy) card.classList.add('is-busy-acts');
    const acts = el('div', 'hub-tool-card__acts');
    if (t.installed && t.web) {
      if (s === 'stopped' || busy === 'start') {
        const sb = el('button', 'tb-btn tb-btn--icon');
        sb.type = 'button';
        sb.title = '啟動';
        sb.innerHTML = icon('play', { anim: 'nudge' });
        sb.disabled = s !== 'stopped';
        sb.classList.toggle('is-busy', busy === 'start');
        sb.addEventListener('click', (ev) => { ev.stopPropagation(); startTool(t.id); });
        acts.appendChild(sb);
      }
      if (s === 'running' || busy === 'stop') {
        const pb = el('button', 'tb-btn tb-btn--icon tb-btn--danger');
        pb.type = 'button';
        pb.title = (t.running && !t.running.managed) ? '這個服務不是由 Hub 啟動，無法在這裡停止' : '停止';
        pb.innerHTML = icon('square', { anim: 'pop' });
        pb.disabled = s !== 'running' || !t.running.managed;
        pb.classList.toggle('is-busy', busy === 'stop');
        pb.addEventListener('click', (ev) => { ev.stopPropagation(); stopTool(t.id); });
        acts.appendChild(pb);
      }
      if (s === 'running') {
        const ob = el('button', 'tb-btn tb-btn--icon');
        ob.type = 'button';
        ob.title = '在新視窗開啟';
        ob.innerHTML = icon('external-link', { anim: 'nudge' });
        ob.addEventListener('click', (ev) => {
          ev.stopPropagation();
          window.open(`${t.running.url}/?${TbTheme.query()}`, '_blank', 'noopener');
        });
        acts.appendChild(ob);
      }
    }
    card.appendChild(acts);

    if (s !== 'missing') {
      card.addEventListener('click', () => select(t.id));
      card.addEventListener('keydown', (ev) => { if (ev.key === 'Enter' && ev.target === card) select(t.id); });
    }
    els.dashGrid.appendChild(card);
  }
  renderActivity();
}

// ---------- 最近的工作（/api/activity：Hub 讀各工具 history.jsonl 聚合）----------
function fmtAgo(ms) {
  const d = Date.now() - ms;
  if (d < 60e3) return '剛剛';
  if (d < 3600e3) return `${Math.floor(d / 60e3)} 分鐘前`;
  if (d < 86400e3) return `${Math.floor(d / 3600e3)} 小時前`;
  if (d < 7 * 86400e3) return `${Math.floor(d / 86400e3)} 天前`;
  return new Date(ms).toLocaleDateString('zh-TW', { month: 'numeric', day: 'numeric' }) + ' 日';
}

const ACT_ICON = { ok: 'circle-check', warn: 'triangle-alert', fail: 'circle-x' };
const ACT_BADGE = {
  warn: ['tb-badge tb-badge--warn', '成功但有略過'],
  fail: ['tb-badge tb-badge--danger', '失敗'],
};

function renderActivity() {
  if (!els.dashActs) return;
  els.dashActs.innerHTML = '';
  const items = (state.activity && state.activity.result) || [];
  if (!items.length) {
    els.dashActs.appendChild(el('div', 'tb-muted tb-small', '目前沒有工作記錄；工具執行過工作後會顯示在這裡。'));
    return;
  }
  for (const a of items) {
    const row = el('div', 'tb-card tb-card--interactive hub-act');
    row.tabIndex = 0;
    const ic = el('span', `hub-act__icon hub-act__icon--${a.status}`);
    ic.innerHTML = icon(ACT_ICON[a.status] || 'info');
    row.appendChild(ic);
    const main = el('div', 'hub-act__main');
    const ttl = el('div', 'hub-act__title');
    ttl.appendChild(document.createTextNode(a.title || ''));
    main.appendChild(ttl);
    const src = toolById(a.tool);
    // 工具名放副標（標題常超長，放進去會被截斷）
    main.appendChild(el('div', 'tb-muted tb-small hub-act__sub',
      [src ? src.name : '', a.detail, a.time ? fmtAgo(a.time) : ''].filter(Boolean).join(' · ') || '—'));
    row.appendChild(main);
    const bd = ACT_BADGE[a.status];
    if (bd) row.appendChild(el('span', bd[0], bd[1]));
    if (src) {
      row.addEventListener('click', () => select(a.tool));
      row.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') select(a.tool); });
    }
    els.dashActs.appendChild(row);
  }
}

function renderAll() {
  syncFrames();   // 先清掉已停止／port 變更的 frame，再決定畫面
  els.pageTool.classList.toggle('tb-hidden', state.page !== 'tool');
  els.pageSettings.classList.toggle('tb-hidden', state.page !== 'settings');
  els.pageDash.classList.toggle('tb-hidden', state.page !== 'dash');
  $('pageManage').classList.toggle('tb-hidden', state.page !== 'manage');
  renderNav();
  if (state.page === 'tool') renderTool();
  if (state.page === 'settings') renderUpdateButton(els.hubUpdate, hubUpdateTarget());
  if (state.page === 'dash') renderDash();
  if (state.page === 'manage') renderLibrary();
}

// ---------- 導覽 ----------
function setUrl() {
  const q = state.page !== 'tool' ? `?page=${state.page}`
    : (state.selected ? `?tool=${encodeURIComponent(state.selected)}` : location.pathname);
  history.replaceState(null, '', q);
}

function openDash() {
  state.page = 'dash';
  setUrl();
  renderAll();
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

// ---------- Hub 與工具操作 ----------
async function refresh() {
  if (state.hubClosed || $('libraryDialog').open) return;
  try {
    const data = await apiGet('/api/tools');
    if (state.hubClosed || $('libraryDialog').open) return;
    state.tools = data.tools || [];
    state.loaded = true;
    if (!state.selected || !toolById(state.selected)) {
      state.selected = visibleTools().find((t) => !t.url)?.id || null;
      if (state.page === 'tool') setUrl();
    }
    if (state.page === 'dash') {   // 總覽頁多取 uptime 與「最近的工作」（各一個請求，失敗各自降級）
      const [hb, act] = await Promise.allSettled([apiGet('/api/health'), apiGet('/api/activity?limit=12')]);
      if (state.hubClosed) return;
      state.hub = hb.status === 'fulfilled' ? hb.value : null;
      state.hubAt = performance.now();
      state.activity = act.status === 'fulfilled' ? act.value : null;
    }
    state.failCount = 0;
    renderAll();
  } catch (err) {
    if (state.hubClosed) return;
    state.failCount += 1;
    if (state.failCount === 1) { setTimeout(refresh, 800); return; }  // 先安靜重試一次
    if (state.page !== 'tool') return;
    els.phStart.classList.add('tb-hidden');
    els.phMeta.innerHTML = '';
    renderPlaceholder('Hub 後端連線失敗', '', 'triangle-alert', `${err.message}（Hub 視窗是否已關閉？）`);
  }
}

async function shutdownHub() {
  if (els.dashShutdown.disabled) return;
  const ok = await confirmDialog('關閉 HUB', '確定要關閉 Dev-Toolbox Hub？由 Hub 啟動的工具也會停止，進行中的工作會被中斷。');
  if (!ok) return;
  els.dashShutdown.disabled = true;
  try {
    await apiPost('/api/shutdown');
  } catch (err) {
    els.dashShutdown.disabled = false;
    toast('danger', `關閉 Hub 失敗：${err.message}`, 7000);
    return;
  }
  state.hubClosed = true;
  clearInterval(state.pollTimer);
  clearInterval(state.uptimeTimer);
  state.tools = [];
  els.dashRefresh.disabled = true;
  els.navSettings.classList.add('tb-hidden');
  openDash();
  toast('ok', 'Hub 已關閉');
}

async function startTool(id) {
  if (!id || state.busy[id]) return;
  state.busy[id] = 'start';
  delete state.lastError[id];
  renderAll();
  try {
    const r = await apiPost('/api/tools/start', { id });
    toast('ok', r.result.opened ? '已開啟工具' : `已啟動（port ${r.result.port}）`);
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

const updateChecks = new Map();

function hubUpdateTarget() {
  return state.hub?.version ? { id: 'dev-toolbox', name: 'Dev-Toolbox Hub', version: state.hub.version } : null;
}

function renderUpdateButton(button, tool) {
  let check = tool && updateChecks.get(tool.id);
  if (tool && (!check || check.current !== tool.version || (!check.pending && check.expires < Date.now() && !state.busy[tool.id]))) {
    check = { current: tool.version, pending: true };
    updateChecks.set(tool.id, check);
    apiPost('/api/tools/update/check', { id: tool.id }).then(({ update }) => {
      check.offer = update;
      check.expires = Date.now() + (update ? 8 : 5) * 60000;
    }).catch(() => {
      check.expires = Date.now() + 60000;
    }).finally(() => {
      check.pending = false;
      renderAll();
    });
  }
  const offer = check?.offer;
  button.classList.toggle('tb-hidden', !offer);
  button.disabled = !offer || Boolean(tool && state.busy[tool.id]);
  button.textContent = offer ? (button.disabled ? '下載並安裝中…' : `下載更新 v${offer.version}`) : '';
}

async function applyUpdate(tool) {
  if (!tool || state.busy[tool.id] || !els.confirmBackdrop.classList.contains('tb-hidden')) return;
  const { id, name, version } = tool;
  const check = updateChecks.get(id);
  const update = check?.offer;
  if (!update || check.current !== version || check.expires < Date.now()) { renderAll(); return; }
  const isHub = id === 'dev-toolbox';
  const running = tool.running;
  if (running && !running.managed) {
    toast('warn', '請先關閉在 Hub 外啟動的工具，再安裝更新。', 7000);
    return;
  }
  const details = [
    `${name} v${version} → v${update.version}`,
    isHub ? 'Hub 會重新啟動，由 Hub 啟動的工具也會停止。'
      : running ? '工具會重新啟動，進行中的工作會被中斷。' : '',
    update.notes,
  ].filter(Boolean).join('\n\n');
  if (!await confirmDialog('下載並安裝更新', details, { label: '下載並安裝' })) return;
  state.busy[id] = 'update';
  renderAll();
  try {
    const { result } = await apiPost('/api/tools/update/apply', { id, version: update.version, restart: isHub || Boolean(running) });
    if (isHub) {
      state.hubClosed = true;
      location.replace(`${result.url}/?page=settings`);
      return;
    }
    destroyFrame(id);
    toast('ok', `${name} 已更新至 v${result.version}。`);
  } catch (err) {
    toast('danger', `${name} 更新失敗：${err.message}`, 7000);
  } finally {
    updateChecks.delete(id);
    delete state.busy[id];
    await refresh();
    renderAll();
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
  renderThemeBtn();
  syncBgControls();
  syncStrengthControls();
}
document.querySelectorAll('[data-mode]').forEach((b) => b.addEventListener('click', () => TbTheme.set(b.dataset.mode)));
document.addEventListener('tb-theme-change', () => { syncThemeControls(); postThemeToFrames(); });

// ---------- 側欄深淺色快速切換（light → dark → system 循環） ----------
const THEME_NEXT = { light: 'dark', dark: 'system', system: 'light' };
const THEME_META = { light: ['sun', '淺色'], dark: ['moon', '深色'], system: ['monitor', '跟隨系統'] };
function renderThemeBtn() {
  const [ic, label] = THEME_META[TbTheme.get().mode] || THEME_META.system;
  els.navTheme.innerHTML = icon(ic) + `<span class="tb-nav__label">${label}</span>`;
  els.navTheme.title = `目前主題：${label}（點擊切換：淺色 → 深色 → 跟隨系統）`;
}
els.navTheme.addEventListener('click', (ev) => {
  ev.preventDefault();
  TbTheme.set(THEME_NEXT[TbTheme.get().mode] || 'light');
});

// ---------- 主題風格（僅 Hub 整體色調，localStorage hub.bg；hub-bg.js 繪製前先套） ----------
const BG_NAMES = { plain: '純色', glow: '光暈', grid: '網格', dots: '點陣', dusk: '暮色', forest: '森林', mono: '黑白', cyber: '霓虹' };
function setBg(v) {
  if (!BG_NAMES[v]) return;
  save('hub.bg', v);
  if (v === 'plain') delete document.documentElement.dataset.hubBg;
  else document.documentElement.dataset.hubBg = v;
  syncBgControls();
}
function syncBgControls() {
  const cur = document.documentElement.dataset.hubBg || 'plain';
  els.bgSeg.querySelectorAll('[data-bg]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.bg === cur)));
}
els.bgSeg.querySelectorAll('[data-bg]').forEach((b) => b.addEventListener('click', () => setBg(b.dataset.bg)));

// ---------- 風格強度（bold 明顯／soft 內斂，localStorage hub.bgStrength） ----------
const STRENGTH_NAMES = { bold: '明顯', soft: '內斂' };
function setStrength(v) {
  if (!STRENGTH_NAMES[v]) return;
  save('hub.bgStrength', v);
  document.documentElement.dataset.hubStrength = v;
  syncStrengthControls();
}
function syncStrengthControls() {
  const cur = document.documentElement.dataset.hubStrength || 'bold';
  els.strengthSeg.querySelectorAll('[data-strength]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.strength === cur)));
}
els.strengthSeg.querySelectorAll('[data-strength]').forEach((b) => b.addEventListener('click', () => setStrength(b.dataset.strength)));

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
  if (state.hubClosed) return;
  if (state.pollTimer) clearInterval(state.pollTimer);
  state.pollTimer = setInterval(() => { if (!document.hidden) refresh(); }, 3000);
  if (!state.uptimeTimer) {
    state.uptimeTimer = setInterval(() => {
      if (!document.hidden && state.page === 'dash' && !state.hubClosed) renderDashSummary();
    }, 1000);
  }
}
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });


let libraryFingerprint = '';
let editingLink = null;
let libraryDialogSession = 0;

function isCurrentLibraryDialog(session) {
  return $('libraryDialog').open && session === libraryDialogSession;
}

function libraryButton(label, action, primary = false) {
  const b = el('button', primary ? 'tb-btn tb-btn--primary' : 'tb-btn', label);
  b.type = 'button';
  b.addEventListener('click', action);
  return b;
}

function openLink(t) {
  if (!/^https?:\/\//i.test(t.url)) return;
  window.open(t.url, '_blank', 'noopener,noreferrer');
}

function renderLibrary() {
  const rows = state.tools.map(({ id, name, source, hidden, version, desc, url, path, icon, error, web, cli, installed }) =>
    ({ id, name, source, hidden, version, desc, url, path, icon, error, web, cli, installed }));
  const fingerprint = JSON.stringify([state.loaded, rows, state.busy]);
  if (fingerprint === libraryFingerprint) return;
  libraryFingerprint = fingerprint;
  const list = $('libraryList');
  const focusKey = list.contains(document.activeElement) ? document.activeElement.dataset.focusKey : null;
  const fragment = document.createDocumentFragment();
  if (!state.loaded) fragment.append(el('p', 'tb-muted', '讀取中…'));
  const groups = [
    ['我的工具', rows.filter((t) => t.source !== 'catalog')],
    ['可安裝的官方工具', rows.filter((t) => t.source === 'catalog')],
  ];
  for (const [heading, tools] of groups) {
    if (!tools.length) continue;
    const section = el('section', 'hub-library-group');
    section.append(el('h2', '', heading));
    for (const t of tools) {
      const row = el('article', 'tb-card hub-library-row');
      const glyph = el('span', 'hub-library-icon');
      glyph.innerHTML = icon(toolIcon(t));
      glyph.setAttribute('aria-hidden', 'true');
      const info = el('div', 'hub-library-info');
      const category = { import: '本機匯入', link: '網站連結', catalog: '官方工具', managed: '官方工具', bundled: '本機工具' }[t.source];
      info.append(el('strong', '', t.name), el('div', 'tb-muted', [category, t.version && 'v' + t.version].filter(Boolean).join(' · ')));
      if (t.error && t.source !== 'catalog') info.append(el('div', 'hub-library-error', t.error));
      if (t.desc || t.path || t.url) info.append(el('div', 'tb-muted', [t.desc, t.path || t.url].filter(Boolean).join(' · ')));
      const actions = el('div', 'hub-library-actions');
      if (t.source === 'catalog') {
        const install = libraryButton(state.busy[t.id] ? '處理中…' : '安裝', () => installTool(t), true);
        install.disabled = Boolean(state.busy[t.id]);
        install.dataset.focusKey = t.id + ':install';
        actions.append(install);
      } else {
        if (t.url) actions.append(libraryButton('開啟', () => openLink(t)), libraryButton('編輯', () => showLibraryDialog('link', t)));
        else if (t.installed && (t.web || t.cli) && !t.hidden) actions.append(libraryButton('開啟', () => select(t.id)));
        const label = el('label', 'tb-switch');
        const toggle = el('input');
        toggle.type = 'checkbox';
        toggle.role = 'switch';
        toggle.checked = !t.hidden;
        toggle.disabled = Boolean(state.busy[t.id]);
        toggle.dataset.focusKey = t.id + ':visibility';
        toggle.setAttribute('aria-label', '在 Hub 顯示 ' + t.name);
        toggle.addEventListener('change', () => changeLibrary(t, { action: 'visibility', id: t.id, hidden: !toggle.checked }));
        label.append(toggle, el('span', '', '顯示在 Hub'));
        actions.append(label);
        if (t.source === 'link' || t.source === 'import') {
          actions.append(libraryButton('移除', async () => {
            if (await confirmDialog('移除 ' + t.name, '將這個項目從 Hub 移除。', { label: '移除' })) {
              await changeLibrary(t, { action: 'remove', id: t.id });
            }
          }));
        }
      }
      row.append(glyph, info, actions);
      section.append(row);
    }
    fragment.append(section);
  }
  list.replaceChildren(fragment);
  if (focusKey) Array.from(list.querySelectorAll('[data-focus-key]')).find((node) => node.dataset.focusKey === focusKey)?.focus();
}

async function changeLibrary(t, body) {
  if (state.busy[t.id]) return;
  state.busy[t.id] = 'library';
  renderAll();
  try { await apiPost('/api/tools/library', body); }
  catch (err) { toast('danger', err.message); }
  finally { delete state.busy[t.id]; await refresh(); }
}

async function installTool(t) {
  if (state.busy[t.id]) return;
  state.busy[t.id] = 'install';
  renderAll();
  try {
    const { update } = await apiPost('/api/tools/update/check', { id: t.id });
    if (!update) { toast('warn', '目前沒有相容的安裝套件。'); return; }
    if (!await confirmDialog('安裝 ' + t.name, ['v' + update.version, update.notes].filter(Boolean).join('\n\n'), { label: '下載並安裝' })) return;
    await apiPost('/api/tools/update/apply', { id: t.id, version: update.version, restart: false });
    toast('ok', t.name + ' 已安裝。');
  } catch (err) { toast('danger', '安裝失敗：' + err.message, 7000); }
  finally { delete state.busy[t.id]; await refresh(); }
}

function showLibraryDialog(mode, t = null) {
  libraryDialogSession += 1;
  editingLink = t;
  $('libraryForm').reset();
  $('libraryBrowse').disabled = $('librarySave').disabled = false;
  $('libraryTitle').textContent = mode === 'import' ? '匯入本機工具' : t ? '編輯網站連結' : '新增網站連結';
  $('importFields').hidden = mode !== 'import';
  $('linkFields').hidden = mode !== 'link';
  $('libraryPath').required = mode === 'import';
  $('libraryName').required = $('libraryUrl').required = mode === 'link';
  $('libraryName').value = t?.name || '';
  $('libraryUrl').value = t?.url || '';
  $('libraryDescription').value = t?.desc || '';
  $('libraryIcon').value = t?.icon || '';
  $('libraryError').textContent = '';
  $('libraryDialog').showModal();
  $(mode === 'import' ? 'libraryPath' : 'libraryName').focus();
}

$('navManage').addEventListener('click', (ev) => {
  ev.preventDefault(); state.page = 'manage'; setUrl(); renderAll();
});
$('importTool').addEventListener('click', () => showLibraryDialog('import'));
$('addLink').addEventListener('click', () => showLibraryDialog('link'));
$('libraryCancel').addEventListener('click', () => $('libraryDialog').close());
$('libraryBrowse').addEventListener('click', async () => {
  const session = libraryDialogSession;
  const b = $('libraryBrowse');
  b.disabled = true;
  $('librarySave').disabled = true;
  $('libraryError').textContent = '';
  try {
    const { path } = await apiPost('/api/tools/folder', {});
    if (path && isCurrentLibraryDialog(session)) $('libraryPath').value = path;
  } catch (err) {
    if (isCurrentLibraryDialog(session)) $('libraryError').textContent = err.message;
  } finally {
    if (isCurrentLibraryDialog(session)) b.disabled = $('librarySave').disabled = false;
  }
});
$('libraryForm').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const b = $('librarySave');
  if (b.disabled) return;
  const session = libraryDialogSession;
  const body = $('linkFields').hidden
    ? { action: 'import', path: $('libraryPath').value }
    : { action: 'link', id: editingLink?.id, name: $('libraryName').value, url: $('libraryUrl').value,
      description: $('libraryDescription').value, icon: $('libraryIcon').value };
  b.disabled = true;
  $('libraryError').textContent = '';
  try {
    await apiPost('/api/tools/library', body);
    if (isCurrentLibraryDialog(session)) $('libraryDialog').close();
    await refresh();
  } catch (err) {
    if (isCurrentLibraryDialog(session)) $('libraryError').textContent = err.message;
  } finally {
    if (isCurrentLibraryDialog(session)) b.disabled = false;
  }
});

// ---------- 綁定 ----------
els.navDash.addEventListener('click', (ev) => { ev.preventDefault(); openDash(); });
els.dashRefresh.addEventListener('click', () => refresh());
els.dashShutdown.addEventListener('click', shutdownHub);
els.navSettings.addEventListener('click', (ev) => { ev.preventDefault(); openSettings(); });
els.phStart.addEventListener('click', () => startTool(state.selected));
els.toolUpdate.addEventListener('click', () => applyUpdate(toolById(state.selected)));
els.hubUpdate.addEventListener('click', () => applyUpdate(hubUpdateTarget()));
els.btnStop.addEventListener('click', () => stopTool(state.selected));
els.btnReload.addEventListener('click', () => {
  // 工具 frame 與 Hub 跨來源，contentWindow.location.reload() 會拋 SecurityError；
  // 重新指派 src 屬性即使是同一 URL 也恆觸發重新導覽，跨來源安全。
  const rec = frames.get(state.selected);
  if (rec) rec.frame.src = rec.src;
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
    state.hub = h;
    els.hubVersion.textContent = `Hub v${h.version}`;
    els.hubInfo.textContent = `127.0.0.1:${h.port} · 只綁本機`;
  } catch (_) { /* 拿不到版本不影響使用 */ }
  await refresh();
  startPolling();
})();
