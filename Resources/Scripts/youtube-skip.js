// Kaizu: finds YouTube's Skip button for a real click.
//
// youtube-ads.js hides an ad and runs it through fast, but long ads
// (1-4 minutes) still take 10-30 s that way, behind the spinner. YouTube
// offers Skip a few seconds in, and ignores a press made from script (an
// untrusted click), so Kaizu presses it as a real click instead. The
// button stays invisible: youtube-ads.js keeps it see-through but lets it
// take the click.
//
// Runs in WebKit's isolated client world, where pages can't see it or call
// the handler; it only reads the page's layout. Kaizu checks again before
// clicking: main frame, YouTube, and the user not typing elsewhere.
(() => {
  'use strict';
  if (window.top !== window || !/(^|\.)youtube\.com$/.test(location.hostname)) return;
  const handler = window.webkit?.messageHandlers?.kaizuYouTubeSkip;
  if (!handler) return;

  let asked = 0;
  const check = () => {
    const player = document.querySelector('.html5-video-player.ad-showing');
    const button = player?.querySelector('.ytp-skip-ad-button');
    if (!button || button.disabled) return;
    const box = button.getBoundingClientRect();
    if (box.width < 4 || box.height < 4) return;
    const x = box.left + box.width / 2;
    const y = box.top + box.height / 2;
    if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) return;
    // Only when the click would land on the button itself.
    const hit = document.elementFromPoint(x, y);
    if (!hit || (hit !== button && !button.contains(hit))) return;
    const now = Date.now();
    if (now - asked < 1000) return;
    asked = now;
    handler.postMessage({ x, y });
  };
  setInterval(check, 250);
})();
