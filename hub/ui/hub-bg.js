/* hub-bg.js — Hub 主題風格：繪製前先套用，避免閃爍。
 * 風格：?bg= 參數 > localStorage hub.bg > graphite（石墨，預設）。
 *   plain＝經典（ui-kit 原色，不設 data-hub-bg 屬性）；其他值見 hub.css 的 data-hub-bg。
 * 風格強度固定「明顯」，目前風格會同步給嵌入的工具頁面。 */
(function () {
  'use strict';
  var BG = ['graphite', 'warm', 'nord', 'contrast', 'black', 'liquid', 'glass', 'frost', 'metal', 'pearl',
    'glow', 'grid', 'dots', 'dusk', 'forest', 'mono', 'cyber'];
  var root = document.documentElement;
  root.dataset.hubStrength = 'bold';
  try {
    var q = new URLSearchParams(location.search);
    var v = q.get('bg') || localStorage.getItem('hub.bg') || 'graphite';
    if (BG.indexOf(v) >= 0) root.dataset.hubBg = v;
    // 側欄收合狀態（只在寬螢幕生效，見 hub.css 的 data-hub-side）
    if (localStorage.getItem('hub.side') === 'collapsed') root.dataset.hubSide = 'collapsed';
  } catch (e) {
    root.dataset.hubBg = 'graphite';   // 無痕模式：石墨、側欄展開
  }
  // 圖示列（data-hub-rail）：寬螢幕手動收合，或 641–960px 自動變窄，兩者共用 hub.css 同一套收合樣式
  try {
    var wide = matchMedia('(min-width: 961px)');
    var mid = matchMedia('(min-width: 641px) and (max-width: 960px)');
    var syncRail = function () {
      var rail = (wide.matches && root.dataset.hubSide === 'collapsed') || mid.matches;
      if (rail) root.dataset.hubRail = ''; else delete root.dataset.hubRail;
    };
    syncRail();
    [wide, mid].forEach(function (m) {
      if (m.addEventListener) m.addEventListener('change', syncRail); else m.addListener(syncRail);
    });
    window.addEventListener('resize', syncRail);   // 有些環境（裝置模擬）不送 change 事件
    new MutationObserver(syncRail).observe(root, { attributes: true, attributeFilter: ['data-hub-side'] });
  } catch (e) { /* 舊瀏覽器：沿用 ui-kit 的窄版樣式 */ }
})();
