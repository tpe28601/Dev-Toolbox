/* hub-bg.js — Hub 主題風格：繪製前先套用，避免閃爍。
 * 風格：?bg= 參數 > localStorage hub.bg > graphite（石墨，預設）。
 *   plain＝經典（ui-kit 原色，不設 data-hub-bg 屬性）；其他值見 hub.css 的 data-hub-bg。
 * 風格強度固定「明顯」（舊版的 hub.bgStrength 設定不再使用）。
 * 只影響 Hub 介面本身，不影響嵌入的工具頁面。 */
(function () {
  'use strict';
  var BG = ['graphite', 'warm', 'nord', 'contrast', 'black', 'glass', 'frost', 'metal', 'pearl',
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
})();
