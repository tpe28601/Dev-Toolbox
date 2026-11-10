(function () {
  'use strict';
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var I = function (n, o) { return TbIcons.svg(n, o); };

  // ---- 頁面切換 ----
  function show(id) {
    if (!$('#page-' + id)) id = 'overview';
    $$('.demo-page').forEach(function (p) { p.classList.toggle('tb-hidden', p.id !== 'page-' + id); });
    $$('#nav .tb-nav__item').forEach(function (a) {
      if (a.getAttribute('href') === '#' + id) { a.setAttribute('aria-current', 'page'); $('#crumb').textContent = a.textContent.trim(); }
      else a.removeAttribute('aria-current');
    });
  }
  window.addEventListener('hashchange', function () { show(location.hash.slice(1)); });
  show(location.hash.slice(1));

  // ---- 深淺色與強調色 ----
  var ACC = { blue: '#2563eb', green: '#15803d', violet: '#7c3aed', orange: '#c2410c', rose: '#e11d48' };
  var NAMES = { blue: '藍', green: '綠', violet: '紫', orange: '橘', rose: '玫瑰' };
  ['#swatches', '#swatches2'].forEach(function (sel) {
    var host = $(sel);
    Object.keys(ACC).forEach(function (k) {
      var b = document.createElement('button');
      b.className = 'tb-swatch'; b.dataset.accent = k; b.title = NAMES[k]; b.style.background = ACC[k];
      b.addEventListener('click', function () { TbTheme.setAccent(k); });
      host.appendChild(b);
    });
  });
  $$('[data-mode]').forEach(function (b) { b.addEventListener('click', function () { TbTheme.set(b.dataset.mode); }); });
  function sync() {
    var t = TbTheme.get();
    $$('[data-mode]').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.mode === t.mode)); });
    $$('.tb-swatch').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.accent === t.accent)); });
  }
  document.addEventListener('tb-theme-change', sync); sync();

  // ---- 分頁示範 ----
  $$('.tb-tabs').forEach(function (bar) {
    bar.addEventListener('click', function (e) {
      var t = e.target.closest('.tb-tab'); if (!t) return;
      $$('.tb-tab', bar).forEach(function (x) { x.setAttribute('aria-selected', String(x === t)); });
    });
  });

  // ---- 提示 ----
  function toast(kind, text, ms) {
    var icon = { ok: 'circle-check', warn: 'triangle-alert', danger: 'circle-x' }[kind] || 'info';
    var el = document.createElement('div');
    el.className = 'tb-toast tb-toast--' + kind;
    el.innerHTML = I(icon) + '<div style="flex:1"></div><button class="tb-btn tb-btn--ghost tb-btn--icon tb-btn--sm" title="關閉">' + I('x', { cls: 'tb-icon--sm' }) + '</button>';
    el.children[1].textContent = text;
    el.querySelector('button').onclick = function () { el.remove(); };
    $('#toasts').appendChild(el);
    setTimeout(function () { el.remove(); }, ms || (kind === 'danger' ? 8000 : 4000));
  }
  var TXT = { ok: '已同步 42 個 ref', warn: '同步完成，但略過 3 個 ref', danger: '啟動失敗：找不到 Python' };
  $$('[data-toast]').forEach(function (b) { b.onclick = function () { toast(b.dataset.toast, TXT[b.dataset.toast]); }; });

  // ---- 對話框 ----
  var dlg = $('#dlg'), last = null;
  function confirmDialog(o) {
    return new Promise(function (resolve) {
      last = document.activeElement;
      dlg.querySelector('.tb-dialog').classList.toggle('tb-dialog--danger', !!o.danger);
      $('#dlgIcon').innerHTML = I(o.danger ? 'triangle-alert' : 'circle-help', { size: 20 });
      $('#dlgTitle').textContent = o.title; $('#dlgBody').textContent = o.body;
      var ok = $('#dlgOk'), name = $('#dlgName');
      ok.className = 'tb-btn ' + (o.danger ? 'tb-btn--danger' : 'tb-btn--primary'); ok.textContent = o.ok || '確定';
      $('#dlgNameField').classList.toggle('tb-hidden', !o.expect);
      if (o.expect) { $('#dlgNameLabel').textContent = '請輸入「' + o.expect + '」確認'; name.value = ''; ok.disabled = true; name.oninput = function () { ok.disabled = name.value !== o.expect; }; }
      else ok.disabled = false;
      dlg.classList.remove('tb-hidden');
      (o.expect ? name : $('#dlgCancel')).focus();
      function done(v) { dlg.classList.add('tb-hidden'); document.removeEventListener('keydown', key); if (last) last.focus(); resolve(v); }
      function key(e) { if (e.key === 'Escape') done(false); }
      document.addEventListener('keydown', key);
      ok.onclick = function () { done(true); }; $('#dlgCancel').onclick = function () { done(false); };
      dlg.onclick = function (e) { if (e.target === dlg) done(false); };
    });
  }
  $('#openConfirm').onclick = function () { confirmDialog({ title: '停止工具', body: '確定要停止「Git Ref Manager」？進行中的工作會被中斷。', ok: '停止' }).then(function (v) { if (v) toast('ok', '已停止'); }); };
  $('#openDanger').onclick = function () { confirmDialog({ title: '刪除 SSH 金鑰', body: '會刪除 id_ed25519 與 id_ed25519.pub，無法復原。', ok: '刪除', danger: true, expect: 'id_ed25519' }).then(function (v) { if (v) toast('ok', '已刪除 id_ed25519'); }); };

  // ---- 工作面板 ----
  var log = $('#log'), bar = $('#jobBar'), st = $('#jobState');
  function line(cls, text) { var s = document.createElement('span'); s.className = cls || ''; s.textContent = text + '\n'; log.appendChild(s); log.scrollTop = log.scrollHeight; }
  function runJob(dry) {
    log.textContent = ''; st.className = 'tb-badge tb-badge--accent'; st.textContent = dry ? '預覽中' : '執行中';
    var steps = [['', '[A] D:\\MyProject · main'], ['', '[B] D:\\MyProject_2'], [dry ? 'dry' : 'ok', (dry ? '[dry-run] ' : '') + '更新 origin/main a1b2c3d → 9f8e7d6'], [dry ? 'dry' : 'ok', (dry ? '[dry-run] ' : '') + '新增 origin/feature/x'], ['warn', '[!] 略過 origin/a/b：D/F 衝突'], ['ok', dry ? '預覽完成：會更新 2 個，略過 1 個' : '完成：更新 2 個，略過 1 個（exit 2）']];
    var i = 0;
    (function tick() {
      if (i >= steps.length) { st.className = 'tb-badge ' + (dry ? 'tb-badge--dry' : 'tb-badge--warn'); st.textContent = dry ? '預覽完成' : '成功但有略過'; if (!dry) toast('warn', '同步完成，但略過 1 個 ref'); return; }
      line(steps[i][0], steps[i][1]); i++; bar.style.width = Math.round(i / steps.length * 100) + '%'; setTimeout(tick, 350);
    })();
  }
  $('#previewBtn').onclick = function () { runJob(true); };
  $('#runBtn').onclick = function () { runJob(false); };
  $('#jobToggle').onclick = function () {
    var c = $('#job').classList.toggle('is-collapsed');
    this.innerHTML = I(c ? 'chevron-up' : 'chevron-down');
  };

  // ---- Python 設定 ----
  $$('input[name="py"]').forEach(function (r) {
    r.onchange = function () {
      var manual = $('input[name="py"]:checked').value === 'manual';
      $('.demo-py-manual').classList.toggle('tb-hidden', !manual);
      $('.demo-py-auto').classList.toggle('tb-hidden', manual);
    };
  });
  $('#pyCheck').onclick = function () {
    var v = $('#pyPath').value.trim(), out = $('#pyResult'), btn = this;
    btn.classList.add('is-busy');
    setTimeout(function () {
      btn.classList.remove('is-busy');
      if (/python(w)?\.exe$/i.test(v)) { out.className = 'tb-field__hint'; out.innerHTML = I('circle-check', { cls: 'tb-icon--sm demo-ok' }) + ' Python 3.12.4，可以使用'; }
      else { out.className = 'tb-field__error'; out.textContent = '找不到 python.exe，或版本低於 3.11'; }
    }, 600);
  };

  // ---- 圖標清單 ----
  var SUGGEST = { 'refresh-cw': 'spin', 'settings': 'spin', 'loader': 'spin', 'sun': 'spin', 'history': 'spin', 'folder': 'bounce', 'folder-open': 'bounce', 'download': 'bounce', 'save': 'bounce', 'circle-help': 'bounce', 'info': 'bounce', 'trash-2': 'wiggle', 'key': 'wiggle', 'moon': 'wiggle', 'triangle-alert': 'wiggle', 'play': 'nudge', 'chevron-right': 'nudge', 'external-link': 'nudge', 'git-branch': 'draw', 'check': 'draw', 'circle-check': 'draw', 'terminal': 'draw' };
  var grid = $('#iconGrid');
  TbIcons.names.forEach(function (n) {
    var a = SUGGEST[n] || 'pop';
    var c = document.createElement('div');
    c.className = 'tb-card tb-card--hover demo-icon';
    c.innerHTML = I(n, { anim: a }) + '<div class="demo-icon__name">' + n + '</div><div class="demo-icon__anim">' + a + '</div>';
    grid.appendChild(c);
  });
})();
