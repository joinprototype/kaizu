// Kaizu: YouTube ad removal, built in (no extension needed).
//
// Injected at document start into every frame, in the page's own JavaScript
// world, so it can intercept the player data before YouTube's code reads it.
// Three layers:
//   1. Strip ad payloads (adPlacements, adSlots, playerAds…) from player
//      responses, whether they arrive inline, via fetch or via XHR + JSON.
//   2. Safety net: if an ad still starts, mute it, jump to its end and press
//      Skip, then restore the user's sound.
//   3. Close the "Ad blockers violate YouTube's Terms" pop-up and resume the
//      video it paused.
(() => {
  'use strict';
  if (!/(^|\.)youtube(-nocookie)?\.com$/.test(location.hostname)) return;

  const AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];

  const strip = (value) => {
    if (value && typeof value === 'object') {
      for (const key of AD_KEYS) {
        if (key in value) delete value[key];
      }
      if (value.playerResponse && typeof value.playerResponse === 'object') strip(value.playerResponse);
    }
    return value;
  };

  // Player responses parsed from XHR/fetch text.
  const parse = JSON.parse;
  JSON.parse = function (...args) {
    return strip(parse.apply(this, args));
  };

  // Player responses read with response.json().
  const json = Response.prototype.json;
  Response.prototype.json = function (...args) {
    return json.apply(this, args).then(strip);
  };

  // The first player response, embedded in the page as a global.
  let initialPlayerResponse;
  try {
    Object.defineProperty(window, 'ytInitialPlayerResponse', {
      configurable: true,
      get: () => initialPlayerResponse,
      set: (value) => { initialPlayerResponse = strip(value); },
    });
  } catch (_) {}

  // kaizu.txt hides the ad blocker pop-up so it doesn't flash, but hidden
  // isn't closed: its overlay stays open, so the backdrop swallows clicks,
  // focus is pulled back into the dialog and the page won't scroll. Closing
  // it releases all three.
  const dismissEnforcement = () => {
    const dialog = document.querySelector('ytd-enforcement-message-view-model')?.closest('tp-yt-paper-dialog');
    if (!dialog || dialog.opened === false) return;
    if (typeof dialog.close === 'function') {
      dialog.close();
    } else {
      dialog.remove();
    }
    if (location.pathname === '/watch') {
      document.querySelector('#movie_player video')?.play().catch(() => {});
    }
  };

  // Safety net for ads that slip through.
  let mutedForAd = false;
  setInterval(() => {
    dismissEnforcement();
    const player = document.querySelector('.html5-video-player');
    if (!player) return;
    const video = player.querySelector('video');
    if (player.classList.contains('ad-showing')) {
      if (video) {
        if (!video.muted) {
          video.muted = true;
          mutedForAd = true;
        }
        if (Number.isFinite(video.duration) && video.currentTime < video.duration - 0.1) {
          video.currentTime = video.duration;
        }
      }
      player.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button')?.click();
    } else if (mutedForAd && video) {
      video.muted = false;
      mutedForAd = false;
    }
  }, 300);
})();
