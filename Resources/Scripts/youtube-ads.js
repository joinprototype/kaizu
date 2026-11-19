// Kaizu: YouTube ad removal, built in (no extension needed).
//
// Injected at document start into every frame, in the page's own JavaScript
// world, so it can intercept the player data before YouTube's code reads it.
// Three layers:
//   1. On a page opened directly, strip the ad payloads (adPlacements,
//      adSlots, playerAds…) from the player data embedded in the page, so
//      the video starts without a pre-roll. When one was booked, YouTube
//      still holds the video back for about the ad's length (a black player,
//      5-15 s); ad blockers in Safari see the same wait (Nov 2026).
//      Responses fetched in-page (clicking another video) are left alone:
//      stripped, every click would stall that way, while unstripped most
//      start at once, and an ad that does come is handled by layer 2. Once
//      an ad has run, YouTube books fewer for a while.
//   2. Safety net for ads that do start, one or several in a row: hidden
//      from the first frame (picture, badge, countdown, captions, controls),
//      muted and run through quickly; then the user's sound, speed and
//      place come back. Speed alone gains little: YouTube holds the video
//      back for the ad's real length (or until Skip). Skip, once offered, is
//      pressed by Kaizu with a real click (youtube-skip.js), since YouTube
//      ignores a press from script. Seeking an ad to its end
//      no longer works: YouTube seeks it back and the player stays on the ad.
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

  // The first player response, embedded in the page as a global.
  let initialPlayerResponse;
  try {
    Object.defineProperty(window, 'ytInitialPlayerResponse', {
      configurable: true,
      get: () => initialPlayerResponse,
      set: (value) => { initialPlayerResponse = strip(value); },
    });
  } catch (_) {}

  // Hidden by style rather than by script, so nothing of an ad is drawn
  // even for a frame: while an ad plays, everything in the player but
  // YouTube's loading spinner (the picture, badge, countdown, captions,
  // controls). Opacity keeps the video playing, which display:none or
  // visibility:hidden might not.
  const hidden = [
    '.html5-video-player.ad-showing > :not(.ytp-spinner)',
    '.html5-video-player.ad-interrupting > :not(.ytp-spinner)',
    '.html5-video-player .video-ads', '.html5-video-player [class*="ytp-ad-"]',
  ];
  const style = document.createElement('style');
  // The Skip button stays see-through but takes clicks: YouTube ignores a
  // press from script, so Kaizu sends it a real click (youtube-skip.js).
  style.textContent = `${hidden.join(',\n')} { opacity: 0 !important; pointer-events: none !important; }\n`
    + '.html5-video-player .ytp-skip-ad-button { pointer-events: auto !important; }';
  const addStyle = () => {
    if (style.isConnected) return;
    (document.head || document.documentElement)?.appendChild(style);
  };
  addStyle();
  document.addEventListener('DOMContentLoaded', addStyle, { once: true });

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

  // Safety net for ads that slip through. Each ad in a pod gets the same
  // treatment; the user's sound and speed come back after the last one.
  // It must never leave the video worse off than the ad would have:
  //   - an ad that stops advancing (one the network can't feed at 16x, or
  //     one left paused) plays on at normal speed;
  //   - an ad break with nothing to play (an empty interstitial waiting for
  //     a click) gets its button pressed, and if that doesn't end it, the
  //     video is loaded again where it was;
  //   - when the video comes back somewhere else than where it left off
  //     (or where the user had just seeked to), it's put back there.
  const AD_RATE = 16;
  const playerOf = () => document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
  // From the address, not the player: during an ad the player reports the ad.
  const videoIdOf = () => new URLSearchParams(location.search).get('v');
  let adRate = AD_RATE;
  let mutedForAd = false;
  let spedUpForAd = false;
  let adClock = null;
  let emptySince = 0;
  let reloadedFor = null;
  let inAd = false;
  // Where the video was, for putting it back after an ad break. Only
  // noted once the address has named the same video for a couple of
  // seconds: right after a click the old video is still playing under the
  // new address. Its length tells the two apart too.
  let place = null;
  let restore = null;
  let current = { id: null, since: 0 };
  let adEndedAt = 0;
  const settled = (id, now) => {
    if (current.id !== id) current = { id, since: now };
    return now - current.since > 2000;
  };

  const handleAd = () => {
    const player = playerOf();
    const video = player?.querySelector('video');
    if (!video) return;
    const now = Date.now();
    if (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting')) {
      if (!inAd) {
        inAd = true;
        // Only a real place: near the start, wherever YouTube resumes is fine.
        restore = place && place.id === videoIdOf() && place.time > 3 ? { ...place } : null;
      }
      if (!video.muted) {
        video.muted = true;
        mutedForAd = true;
      }
      if (!adClock || adClock.time !== video.currentTime) {
        adClock = { time: video.currentTime, at: now };
      } else if (now - adClock.at > 3000) {
        adClock.at = now;
        adRate = 1;
        if (video.paused) video.play().catch(() => {});
      }
      if (video.playbackRate !== adRate) {
        video.playbackRate = adRate;
        spedUpForAd = true;
      }
      player.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button')?.click();
      // Nothing to play: no ad media loaded.
      if (!(video.duration > 0) || video.readyState === 0) {
        emptySince ||= now;
        if (now - emptySince > 1500) {
          player.querySelector('[class*="interstitial"] button, [class*="interstitial"] [role="button"]')?.click();
        }
        const id = videoIdOf();
        if (now - emptySince > 4500 && id && reloadedFor !== id && player.loadVideoById) {
          reloadedFor = id;
          emptySince = 0;
          player.loadVideoById({ videoId: id, startSeconds: restore?.id === id ? restore.time : 0 });
        }
      } else {
        emptySince = 0;
      }
      return;
    }
    if (inAd) {
      inAd = false;
      if (mutedForAd) {
        video.muted = false;
        mutedForAd = false;
      }
      if (spedUpForAd) {
        if (video.playbackRate === adRate) video.playbackRate = 1;
        spedUpForAd = false;
      }
      adRate = AD_RATE;
      adClock = null;
      emptySince = 0;
      adEndedAt = now;
    }
    if (video.seeking || !(video.duration > 0)) return;
    const id = videoIdOf();
    // Just back from an ad break and left paused at the start: play on.
    if (now - adEndedAt < 5000 && video.paused && video.currentTime < 1 && video.readyState >= 3) {
      video.play().catch(() => {});
    }
    if (restore) {
      // Back from an ad break: once the video plays again, check its place.
      if (restore.id === id && video.readyState >= 2) {
        if (Math.abs(video.duration - restore.length) < 1 && Math.abs(video.currentTime - restore.time) > 3) {
          player.seekTo ? player.seekTo(restore.time, true) : (video.currentTime = restore.time);
        }
        restore = null;
      } else if (restore.id !== id) {
        restore = null;
      }
      return;
    }
    if (settled(id, now)) place = { id, time: video.currentTime, length: video.duration };
  };
  // A seek moves the place to come back to, even if an ad break starts
  // before the video gets there.
  document.addEventListener('seeking', (event) => {
    const player = playerOf();
    if (!player || event.target !== player.querySelector('video')) return;
    if (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting')) return;
    const id = videoIdOf();
    if (!settled(id, Date.now()) || !(event.target.duration > 0)) return;
    place = { id, time: event.target.currentTime, length: event.target.duration };
  }, true);
  // Media events catch an ad as it starts (muted before it's heard);
  // the timer covers anything they miss.
  for (const type of ['loadstart', 'play', 'playing', 'ratechange', 'volumechange']) {
    document.addEventListener(type, handleAd, true);
  }
  setInterval(() => {
    dismissEnforcement();
    handleAd();
  }, 250);
})();
