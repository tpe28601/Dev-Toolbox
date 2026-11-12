/* hub-bg.js — Hub 主題風格：繪製前先套用，避免閃爍。
 * 風格：?bg= 參數 > localStorage hub.bg > plain（預設，不設 data-hub-bg 屬性）。
 * 強度：?strength= 參數 > localStorage hub.bgStrength > bold（明顯；soft＝內斂）。
 * 值與樣式見 hub.css 的 data-hub-bg／data-hub-strength；只影響 Hub 介面本身。 */
(function () {
  'use strict';
  var BG = ['glow', 'grid', 'dots', 'dusk', 'forest', 'mono', 'cyber'];
  try {
    var q = new URLSearchParams(location.search);
    var v = q.get('bg') || localStorage.getItem('hub.bg');
    if (v && BG.indexOf(v) >= 0) document.documentElement.dataset.hubBg = v;
    var s = q.get('strength') || localStorage.getItem('hub.bgStrength');
    document.documentElement.dataset.hubStrength = (s === 'soft') ? 'soft' : 'bold';
  } catch (e) { /* 無痕模式：維持 plain + bold */ }
})();
