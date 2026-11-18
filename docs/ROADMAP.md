# Kaizu Roadmap

Arc-style browser, native WebKit, quiet craft. This is the living plan: what's
missing versus Arc, in what order we build it, and how it should *feel*.
Architecture rules live in [ARCHITECTURE.md](ARCHITECTURE.md); market research
in [research/](research/).

Effort: **S** = an evening, **M** = a few sessions, **L** = a project.

## Where things stand

| Area | Shipped | Planned work |
| --- | --- | --- |
| Moving to Kaizu | Arc sidebar import with a preview, bookmark and history import | Verify common password-manager extensions by hand |
| First launch | Mac download and signed automatic updates | Developer ID signing and Apple notarization |
| Everyday browsing | Split view, tab hibernation, daily filter updates and verified cookie rejection on two live sites | Compare content-blocking coverage and test more consent providers and regions |
| Browser integration | Per-site permissions and notification counts in the tab and Dock | Request Apple’s browser passkey entitlement and test macOS notification banners |

See the [changelog](../CHANGELOG.md) for version-by-version changes. The phases below track implementation details.

## Path to 1.0 on Mac

The first release should carry an Arc user from importing a sidebar through a week of browsing, a restart and an update with their tabs and logins intact. These are the checks we use to judge readiness.

| Priority | Work | Evidence to collect |
| --- | --- | --- |
| Recover a workspace | Offer a browsable, searchable archive per profile. Exercise session recovery, import undo and upgrades with existing data. | Reopen the intended page in its original space and recover pinned folders after a restart. Check with two profiles and a private window. |
| Trust it for daily work | Test extension installation, password filling, media calls, permissions and notifications on representative sites. | Record versions and observed outcomes for 1Password and Bitwarden, including desktop integration separately. Publish known limitations. |
| Ship safely | Add repeatable build and test checks. Sign with Developer ID, notarize and verify a clean install and a signed upgrade. Document what the browser sends off-device. | Test the downloadable release on the minimum supported macOS and a current Mac. Apple enrollment or a Developer ID certificate is pending. |
| Match the switching workflow | Preserve sidebar organization, Peek, little windows, routing and split layouts. Verify real Arc and Safari imports with consented or redacted samples. | Compare the preview with the resulting spaces, folders and tabs. Repeat the import and check Undo. |

Kaizu’s advantages to demonstrate are built-in tracking protection, a local sidebar with no account requirement, and mixed row-and-column splits. Performance comparisons require the same pages, hardware and measurement procedure in both browsers. Sync, Boosts, Easels and an AI panel are outside this proposed 1.0 scope. Cross-device sync remains a significant gap for people who use Arc on multiple devices.

### Migration checks

Two publicly available Arc sidebar samples were imported into separate, empty Kaizu sessions. The [linkcache fixture](https://github.com/adlio/linkcache/blob/95d64d3739b3d9afd4b4e3be58f8cd42e33c6062/test_data/StorableSidebar.json) produced 9 tabs in 2 spaces on 1 profile. The [A New Arc Begins fixture](https://github.com/Zarrar09/A-New-Arc-Begins/blob/41f0df8520c4ff13b7f25d387a9046547b927f31/tests/fixtures/sampleStorableSidebar.json) produced 78 tabs in 4 spaces on 2 profiles. After a restart, importing each sidebar again added zero tabs and preserved the saved session. Undo in a fresh run returned each session to one empty space. The source files retained their original hashes.

A fresh Mac selected a seven-link Markdown fixture through **File → Import from Arc…**, previewed five Design tabs and two Personal tabs, and saved both spaces in separate profiles. Reopening Kaizu and importing the same file again added zero tabs. Undo in a fresh workspace restored the original empty space. The fixture follows Arc’s export format. An independently generated Markdown export remains an additional compatibility check. [Native file-chooser run](https://github.com/joinprototype/kaizu/actions/runs/44297200508) · [Arc’s export guide](https://resources.arc.net/hc/en-us/articles/25583851606039-How-Do-I-Export-My-Data-from-Arc)

Chrome 157 wrote a fresh test profile with a loopback visit and a bookmark. Kaizu imported both, kept the bookmarks folder collapsed, recognized the bookmark on a repeat preview, and removed the imported visit and folder on Undo. A tab added to the folder after import survived Undo. Both source files retained their original hashes.

Kaizu imported four successful destination pages and five bookmarks from Chromium’s two Safari 18.4 history fixtures and bookmark file. It skipped redirect and failed-load entries. The bookmarks landed in a collapsed folder, a second preview found zero new bookmarks, and Undo preserved a tab moved into the folder after import. [Chromium fixtures](https://chromium.googlesource.com/chromium/src/+/f82317413d635d3dfc1abf79597fce56eb9eceff/components/test/data/user_data_importer/valid/)

On a fresh macOS 27.0.1 account, Safari visited and bookmarked a local page. Its export dialog accepted Bookmarks and History as the only selected categories. After Save, macOS requested authentication and the runner produced no ZIP. A locally authenticated export of those two categories is still needed to verify the complete Safari-to-Kaizu workflow. [Fresh Safari export attempt](https://github.com/joinprototype/kaizu/actions/runs/44294859012)

On macOS 15.8.2, the published v0.2.5 app opened a saved tab and received a persistent login cookie from a local test site. After the app quit, the runner replaced its bundle and launched the candidate without a URL. The same tab reopened in its original space and profile, and the site received its original cookie. CI repeats this [upgrade check](https://github.com/joinprototype/kaizu/actions/runs/44264250004) alongside a clean launch. A separate [production-feed check](https://github.com/joinprototype/kaizu/actions/runs/44281594637) lowered the test bundle’s advertised build number, then let the candidate download and verify the public v0.2.5 archive. Quitting installed build 10. The original tab and test login survived. The exact minimum macOS 15.4 and Apple notarization remain open checks.

One macOS 15 signed-update run installed v0.2.5 and reopened the page, but the site received no login cookie. The same commit passed on a fresh runner. In 12 separate macOS 27.0.1 profiles, quitting the development build zero to ten seconds after a local site confirmed login and reopening it preserved the cookie, local storage and the original tab, space and profile IDs every time. Those trials used the same app version for both launches. Ordinary restart timing did not reproduce the failure, and its cause remains open. The upgrade checks now compare a site’s local storage and HTTP-only login cookie independently. [Failed update check](https://github.com/joinprototype/kaizu/actions/runs/44298465917/attempts/1) · [Fresh-runner repeat](https://github.com/joinprototype/kaizu/actions/runs/44298465917/attempts/2)

Eight additional macOS 27.0.1 trials exchanged the app bundle between launches. Four moved from the [v0.2.5 source](https://github.com/joinprototype/kaizu/tree/v0.2.5) to [the development commit](https://github.com/joinprototype/kaizu/commit/ad763e80632fcd513389fed50a402b958adca86e), and four ran the reverse direction. Each direction covered quitting 0, 1, 5 and 10 seconds after the test site confirmed login. In all eight fresh profiles, the site received its original HTTP-only cookie, read its original local-storage value and reopened in the same tab, space and profile. These trials used debug builds with disposable bundle identifiers and a direct bundle swap. The intermittent macOS 15 production-updater failure remains open.

On macOS 27.0.1, the Firefox Add-ons builds of Bitwarden 2026.10.2 and 1Password 8.12.44.33 both installed in separate empty Kaizu profiles. Bitwarden opened a loading popup. Selecting 1Password on a loaded page showed no sign-in interface. WebKit loaded both background pages. Bitwarden reported an unsupported notification click event and 1Password reported a missing `chrome.notifications.onClicked` API. Sign-in, autofill and desktop integration remain unverified for both versions.

### Cookie consent on live sites

On macOS 27.0.1, fresh profiles with content blocking and automatic rejection turned off showed a banner on both sites below. Both providers initially reported that the visitor had made no choice. With Kaizu's default settings, both recorded a response. After quitting and reopening the browser with both protections off, each site still reported the same decision without showing its banner again.

| Site | What the site recorded |
| --- | --- |
| [Cookiebot help](https://www.cookiebot.com/en/help/) | `Cookiebot.hasResponse` became true. Necessary cookies were allowed. Preferences, statistics and marketing were declined. A separate profile with only automatic rejection enabled produced the same result. |
| [CookieYes documentation](https://www.cookieyes.com/documentation/retrieving-consent-data-using-api-getckyconsent/) | `getCkyConsent().isUserActionCompleted` became true. Necessary cookies were allowed. Functional, analytics, performance and advertisement cookies were declined. |

On Didomi's public demo, the SDK loaded but showed no notice in the control profile, including with the vendor's country-preview option. Rejection on that provider remains unverified. [Didomi sandbox](https://sandbox.didomi.io/cmp.html) · [Preview option](https://developers.didomi.io/cmp/web-sdk/getting-started)

### Notification clicks across profiles

On macOS 27.0.1, clicking through Kaizu’s notification-response handler used to reopen a closed Work tab in the front Personal window. The development build now records the profile and space when the page posts a notification. In a two-window test, a WebKit page created a notification, received its show event, then received its click event when Kaizu handled the response. After a cold launch, the saved notification reopened the original address in Work. Clicking an older notification after navigating elsewhere preserved the newer page. Deleting the Work profile left Personal untouched on a later click. The test exercises routing using the payload stored with a macOS notification. Displaying and clicking an actual system banner remains a signing and release check.

### Media calls and permissions

The packaged browser sent synthesized audio, canvas video and a data message between two local WebRTC peers on macOS 15.8.2 and 27.0.1. The receiver decoded non-silent audio, rendered a video frame and returned the message. On macOS 27.0.1, disconnecting the oscillator made the audio check fail while video and data still worked. A separate native-sheet test confirmed that declining a microphone request preserves an existing camera permission, and that private windows ask independently. [Packaged audio, video and data check](https://github.com/joinprototype/kaizu/actions/runs/44313608354) · [Permissions check](https://github.com/joinprototype/kaizu/actions/runs/44293624816)

On macOS 27.0.1, Kaizu used the public Janus Echo Test with a generated tone and a 160×90 canvas in place of physical devices. Janus echoed both tracks and a data-channel message over the network. Kaizu decoded nine returned video frames, displayed the expected resolution and measured nonzero audio energy on the incoming track. [Janus Echo Test](https://janus.conf.meetecho.com/demos/echotest.html)

On macOS 27.0.1, two fresh profiles with camera and microphone denied reached Jitsi Meet's prejoin screen. Kaizu rendered the display-name field, **Join meeting**, **Join options** and device controls. With capture denied, the page still displayed “Configuring devices…” after 40 seconds and its media elements had no tracks. The test ended in the lobby. Physical device capture and a call with a remote participant remain open. [Jitsi's pre-meeting device check](https://jitsi.org/blog/authentication-on-meet-jit-si/)

### Extension compatibility

In **Settings → Extensions → Add Extension…**, select the Mac app that contains a Safari web extension or choose a WebExtension ZIP. Kaizu reads the web extension in place from a Mac app, so keep the app installed. Safari App Extensions and Safari content-blocker bundles use different APIs. For example, AdGuard for Safari 3.0.0 contains six content blockers and a Safari App Extension. Kaizu's built-in ad and tracker blocker is available for that use case. [Apple's web extension loader](https://developer.apple.com/documentation/webkit/wkwebextension/init(appextensionbundle:)) · [Safari App Extensions](https://developer.apple.com/documentation/safariservices/safari-app-extensions)

Some tab-management extensions need access to the website whose tabs they manage. On the site, right-click the extension’s icon in the sidebar, choose **Allow Access to [host]…**, and review the site in the confirmation. This grants that extension access on that scheme and host across regular profiles. To revoke a grant, open **Settings → Extensions → Remove Access** next to the site.

These checks ran on a Kaizu development build on macOS 27.0.1 in fresh profiles.

| Extension package | What worked in Kaizu | Coverage |
|---|---|---|
| [uBlock Origin Lite 2026.1116.1650](https://github.com/uBlockOrigin/uBOL-home/releases/tag/2026.1116.1650), Safari ZIP | After restarting Kaizu, an EasyList rule blocked a matching request while a control request loaded. With the extension absent, both loaded. Kaizu's own blocker was off in both profiles. | The first matching request after launch got through before the extension rules took effect. Advanced filtering, cosmetic rules and the App Store bundle need separate checks. |
| [Dark Reader 4.9.135](https://github.com/darkreader/darkreader/releases/tag/v4.9.135), Chrome MV3 ZIP | After restarting Kaizu, Dark Reader applied its dynamic theme to a light page. The background changed from white to RGB(24, 26, 27) and black text became RGB(232, 230, 227). | One controlled page, default settings. |
| [TabCloser v4.3.0](https://github.com/sethcottle/tabcloser/releases/tag/v4.3.0), Safari app, Chrome and Firefox ZIPs | With access granted to `https://open.spotify.com/*`, all three packages closed a matching tab by 18 seconds and left the control tab open. | At default permissions, the matching tab stayed open for 25 seconds. The Safari package in this release reports 4.2.0 in its web manifest. Other service patterns remain untested. |

#### Password-manager alternatives

**Bitwarden for Safari.** In Kaizu, open **Settings → Extensions → Add Extension…** and select Bitwarden.app. Apps in Applications also appear under **From Safari**. Keep the app installed because Kaizu loads its extension in place.

On a development build running on macOS 27.0.1, Safari extension **2026.10.1**, bundled in Bitwarden desktop **2026.10.2**, signed in to a disposable self-hosted Vaultwarden **1.37.5** account. Selecting Autofill in the popup filled both the username and password on the matching HTTPS site. On a different host with the same form, the popup showed zero autofill suggestions and both fields stayed empty. [End-to-end test on macOS](https://github.com/joinprototype/kaizu/actions/runs/44291691454)

Desktop unlock, biometrics, passkeys and Bitwarden cloud accounts still need separate checks. The Mac App Store extension from the 2026.10.2 build also opened its welcome screen. Both Safari builds reported unsupported native messaging and a notification event. [Bitwarden desktop release](https://github.com/bitwarden/clients/releases/tag/desktop-v2026.10.2) · [Mac App Store extension build](https://github.com/bitwarden/clients/actions/runs/41090170889)

**1Password** distributes its Safari extension as a separate Mac App Store app. The desktop app also offers Universal Autofill (Command–Backslash) and Quick Access (Shift–Command–Space). Site recognition and filling through those shortcuts still need a Kaizu test. For browser-to-desktop communication, 1Password documents adding a signed browser in Applications. That route uses the Chrome or Firefox extension and requires working native messaging. On Mac, the signed browser must be in Applications. [Safari distribution](https://support.1password.com/update-extension/) · [Universal Autofill](https://support.1password.com/mac-universal-autofill/) · [Additional browsers](https://support.1password.com/additional-browsers/)

**KeePassXC** offers an extension-free alternative for people with a local vault. Its Global Auto-Type selects entries using the focused window title and types into the focused fields. A page controls its title, so users need to check the address before filling. Kaizu has yet to verify this workflow with a disposable KeePassXC database. [KeePassXC Auto-Type guide](https://keepassxc.org/docs/KeePassXC_UserGuide#_auto_type)

## Strategy (Oct 2026)

**Arc stops working on Dec 22, 2026** (announced Oct 22 on [arc.net](https://arc.net/);
new accounts already disabled; its makers push users to Dia, a Chromium AI
browser with paid tiers). Its users are choosing a new home right now. Full
analysis: [research/arc-and-market.md](research/arc-and-market.md).

What that means for us:
1. **Win Arc refugees before Dec 22.** Headline feature: an Arc importer
   (spaces, pinned tabs, folders, colors). Then the features they say they'll
   miss and Dia lacks: auto-archiving tabs, Little Arc, Air Traffic Control
   (route links to a profile), Peek, split view.
2. **Be the trustworthy one.** Local-first, no account, no AI paywall, keeps
   working forever. Arc's death is the pitch.
3. **Win on feel and identity, not tab layout.** Chrome and Firefox now ship
   vertical tabs; the Arc *feel* and Kaizu's quiet craft are the product.
4. **Avoid the "novelty tax".** Arc's own data: only ~5% of daily users used
   multiple Spaces. Keep defaults normal, reveal power features gradually.
5. **Don't:** Windows/Linux, AI as the headline, mandatory accounts, Arc's long
   tail (Easels, Live Folders) before the core is solid.

### Sprint: now → Dec 22

Pulled forward from the phases below, in order:
1. [x] Phase 0 minimum: commit, tests, session `schemaVersion` + migration, Profile/Space split **M**
3. [x] Today tabs auto-archive (12 h) + Archive searchable in the command bar **M**
4. [x] Little window for links from other apps, promotable to a tab without reloading (⌥⌘N, ⌘O) **M**
5. [x] Air Traffic Control: rules that route links to a space (Settings → Links) **S**
6. [ ] Privacy pack, on by default, no extensions needed **L**
   - [x] ad + tracker blocking (EasyList, EasyPrivacy → `WKContentRuleList`, compiled once, cached)
   - [x] YouTube ads v1 (our page script strips ad payloads, skips leftovers; in-page slots hidden)
   - [x] cookie-banner hiding (EasyList Cookie List)
   - [x] Global Privacy Control (macOS 27+), HTTPS-first navigation
   - [x] cookie pop-ups auto-rejected v1 (DuckDuckGo's autoconsent standalone, MPL-2.0; page world, all frames)
   - [ ] autoconsent v2: isolated content world + native rule filtering (DDG-style), smaller per-frame cost. Measured Nov 2: on ten heavy sites the 600 KB script costs about 100 MB of 2.4 GB, inside the noise between runs, so memory is no reason to do this. Moving to an isolated world needs a native bridge for the rules that `eval` page state (DDG evaluates those in the page world), and must be checked on real CMPs before it replaces v1
   - [x] filter list auto-updates (daily, also in a Kaizu left open for days, and retried hourly while offline; newer of downloaded vs bundled wins)
   - [x] per-site "pause blocking" (shield in address pill, per-tab controllers, no recompiles)
   - [x] broken-site reporting (site popover, Help menu, the toast after pausing): a Mail draft with the site's name, never the page unless asked; records whether turning blocking off fixed it
   - [x] strip tracking parameters (utm_*, fbclid, gclid…) on navigation and Copy Link
   - [ ] evaluate Brave's adblock-rust converter vs ours (coverage, scriptlets)
7. [x] Find in page, history, Peek, split view **L** total
8. [x] Phase 1 motion pass on the core interactions **M**
9. [x] Arc importer from `StorableSidebar.json` with a preview + one-click import (format documented in research/arc-sidebar-format.md; fixture in Tests) **M**
10. [ ] Developer ID signing + notarization, apply for the passkey entitlement **M** (self-update and the test page at kaizu.joinprototype.com landed Oct 30)

## Product principles

1. **Feel first.** Every interaction has intentional motion; nothing jumps, nothing janks.
2. **Native and light.** WebKit + AppKit/SwiftUI. Battery life and memory are features.
3. **Made with love.** Warm and alive, with old-world chart-maker care: real type, real inks, a rose that turns. Never minimal for its own sake, never flashy, never generic.
4. **Keyboard-first.** If you can click it, you can find it in the command bar.
5. **Never lose user data.** Versioned formats, migrations, backups.

## v0.1: done

Sidebar tabs · pinned grid · drag to reorder/pin · command bar (URL, search,
switch to tab) · profiles with isolated website data · hide/peek/resize sidebar ·
lazy tab loading · session restore · favicons · downloads to ~/Downloads ·
uploads, JS dialogs, error pages, Web Inspector · popups and ⌘-click as tabs ·
default-browser capable · curated themes · app icon.

## Gap versus Arc

| Area | Arc | Kaizu now | Plan | Effort | WebKit notes |
|---|---|---|---|---|---|
| Spaces (theme + tabs, bound to a profile) | ✓ | ✓ | — | M | — |
| Favorites row (per profile) | ✓ | ✓ | — | S | — |
| Pinned folders | ✓ | ✓ | — | M | — |
| Today tabs auto-archive + Archive | ✓ | ✓ | — | M | — |
| Command bar: history, actions, suggestions | ✓ | ✓ | — | M | — |
| History | ✓ | ✓ | — | M | WebKit has no global history; we store it (SQLite+FTS5) |
| Find in page | ✓ | ✓ | — | S | `findString(_:configuration:)` ✓ |
| Downloads panel | ✓ | ✓ | — | S | `WKDownload` progress ✓ |
| Multiple / private windows | ✓ | ✓ | — | M | `WKWebsiteDataStore.nonPersistent()` |
| Back/forward kept across restarts | ✓ | ✓ | — | S | `interactionState` ✓ |
| Ad + tracker blocking | via extensions | ✓ built in | — | M | `WKContentRuleList` ✓ (same engine as Safari content blockers) |
| Split view | ✓ | ✓ | — | L | several page views per window |
| Peek (link preview overlay) | ✓ | ✓ | — | M | promote preview to tab without reload |
| Little Arc (mini window) | ✓ | ✓ | — | M | `NSPanel` |
| ⌃Tab recent-tab switcher | ✓ | ✓ | — | M | `takeSnapshot` ✓ for thumbnails |
| Media: now playing, mute, auto-PiP | ✓ | ✓ | — | M | event-driven via isolated-world script; auto-PiP ✓ |
| Capture / screenshots | ✓ | ✓ | — | S | `takeSnapshot`, `createPDF` ✓ |
| Extensions | Chrome Web Store | ✓ Chrome Web Store, Firefox Add-ons, Safari | — | L | `WKWebExtension` ✓ (macOS 15.4+) |
| Password managers | extensions | Bitwarden for Safari filled a self-hosted login | partial | L | Verify 1Password autofill and desktop unlock separately |
| Site notifications | ✓ | on the tab and Dock; macOS banners need Developer ID | P6 | M | no public `Notification` delivery: a page script plus `UserNotifications`; macOS refuses ad-hoc signed apps |
| Passkeys | ✓ | blocked | P6 | — | needs Apple's browser passkey entitlement |
| Import (Arc / Chrome / Safari) | ✓ | ✓ | — | M | Arc keeps its sidebar in `StorableSidebar.json`; Chromium browsers share one history and bookmarks format; Safari exports a .zip |
| Boosts (per-site CSS/JS) | ✓ | Hide Distracting Items only | P5, if asked | M | `WKUserScript` ✓ |
| AI features | Arc Max | — | P5, opt-in | M | side panel with the user's own claude.ai / ChatGPT login |
| Settings window | ✓ | ✓ | — | S | — |
| Sync across devices | ✓ | — | later | L | CloudKit candidate |
| Easels, Windows/iOS apps | ✓ | — | not planned | — | — |

## Phase 0: Foundation

Make the codebase ready to grow (details in [ARCHITECTURE.md](ARCHITECTURE.md)).

- [x] GitHub repo (`joinprototype/kaizu`, `develop` → `master`) **S**
- [x] GitHub Actions runs Swift tests, builds the release app and verifies its bundle on Xcode 27
- [ ] Agree on formatting rules before enabling a lint check
- [x] `Tests/` with Swift Testing: filter conversion, sessions, history, URL input, quick answers, completion (53 tests) **S**
- [ ] Split into modules: DesignSystem → WebEngine → BrowserCore + Storage **M**
- [x] `AppModel` (what windows share) + one `BrowserStore` per window **M**
- [ ] `Command` registry drives menus **S**
- [x] Session `schemaVersion` + migrator; Profile/Space split (v2) **M**
- [x] `Motion` tokens; ad-hoc animation literals removed (`Metrics` still to do) **S**

## Phase 1: Feel (motion and polish)

The thing people will screenshot. Target: 120 Hz on ProMotion, zero dropped
frames on tab/space switches, Reduce Motion respected everywhere.

| Interaction | Behavior | Motion |
|---|---|---|
| Switch space | Two-finger swipe on the sidebar pages content *with your fingers* (interactive, rubber-bands at ends); backdrop cross-fades between themes | tracks gesture, release = `.snap` |
| Open tab | Row drops in at the top (scale 0.96 → 1, fade, height grows) | `.pop` |
| Close tab | Row collapses, neighbors slide up; ⌘Z brings it back | `.snap` |
| Reorder | Rows part to make a live gap under the cursor (no drop-on-target) | `.glide` |
| Pin | Row flies into the pinned grid and morphs into a tile (matched geometry) | `.pop` |
| Command bar | Pops in (scale + fade); rows stagger 15 ms; selection pill *slides* between rows | `.pop`, `.snap` |
| Sidebar toggle | Card expands with a spring; peek has 120 ms hover intent and 24 pt slop | `.snap` |
| Loading | Favicon becomes a ring spinner; progress bar glides then fades | ease |
| Tab switch | No white flash: container uses the page's `underPageBackgroundColor` | — |
| Hover | 120 ms fades on every hover state | ease |

Done (Oct 25): `Motion` tokens with Reduce Motion support, hover fades, rows
dropping in / fading out, command bar selection pill sliding, spaces sliding
in from the swipe direction with a backdrop cross-fade, two-finger swipe on
the sidebar to switch spaces, peek pop-in, rows gliding between Today and
Pinned on ⌘D (matched geometry), the active-space disc sliding between
spaces, peek hover intent (120 ms to open, 280 ms grace to close), rows
parting to show where a dragged tab will land, the sidebar following the
fingers during a space swipe (resisting at the ends), rows morphing into
favorite tiles and back. All planned motion is in; next is tuning it by eye.

Motion review (Oct 25, evening): every interaction read through for
clanks; fixed the loading bar ending, toasts, traffic lights, hover fades,
peek close/expand, Reader's blank fade, scrims scaling with their cards,
split open/close, ⌘S from a peek, the space swipe (now 1:1 with the next
space beside, velocity-carried, backdrop blending), sliding pill and disc,
row insertion, Clear's teardown. Reduce Motion swaps slides for dissolves
(Nov 1).

Settled by measuring (Nov 1): a new tab's web view takes about 30 ms, spent
before the row animation's first frame, so nothing stutters and pre-warming
stays out (it would also keep a spare web process open). The sidebar toggle
on heavy pages (New York Times, YouTube) is 0 to 9 late frames, worst 31 ms,
a little above light pages on the same busy machine: not visible.

Measured (Oct 25, night) with `KAIZU_DEBUG=tour` on a 120 Hz display,
optimized build: every interaction (command bar, sidebar, space switch and
swipe, tab switch, split, peek, new/close tab, toasts) runs at 120 fps with
0 to 2 late frames (worst about 21 ms, so never below 60 fps). Most late
frames move around between runs (noise); the one that repeats is the frame
where a space swipe lets go and the new space's page takes over. Next
candidate: the command bar's first frames (it builds its rows).

On a busy machine (load 10 or more) a space switch drops 14 to 24 frames in
bad moments and 0 to 3 in calm ones, in the builds from before and after the
chart room alike. Compare builds side by side before blaming a change.

Memory, measured Nov 2 with `KAIZU_DEBUG=memory` on an optimized build (phys
footprint, what Activity Monitor shows; RSS counts 570 MB of shared system code):
- Kaizu itself: about 42 MB at launch, no CPU and no wakeups when idle, 80 MB with
  ten tabs, 65 MB after closing them. Two rounds of opening and closing end level,
  and no tab or web view outlives closing. A warm launch takes about 250 ms.
- Ten heavy sites: 2.4 GB, 90% of it WebKit's page processes (the biggest about
  500 MB each). 3.3% CPU together when left idle. Blocking saves about 170 MB.
- Hibernating them leaves 183 MB. Before Nov 2 it left 1.3 GB: tabs counted as
  playing if a silent video was autoplaying.
- Compiling filter lists, on first launch and when an update changes them, now
  happens in a short-lived copy of the app, one per list. A real first launch
  compiles the bundled lists and then the day's downloads; in it the app's peak
  went from 644 to 165 MB, what it still holds a minute later from 345 to 50 MB,
  and its own CPU from 17 s to 0.7 s. A helper peaks at 386 MB and gives it all
  back by exiting. If one can't run, or takes over two minutes, the app compiles
  that list itself as it used to. The 165 MB left is a launch transient, not traced.
- Why a process: malloc kept the memory until the system ran short, and the peak
  is inside WebKit's compile, not ours. A hand-written encoder halved
  `JSONEncoder`'s own 280 MB but left the app's peak where it was and the leftover
  at 190 MB, and `malloc_zone_pressure_relief` made no clear difference.

Plus, where Kaizu gets its personality:
- [x] Loading delight: a compass needle in the address pill swings while a page loads and settles on north when done **S**
- [x] A chart-paper empty state: a sea chart's rhumb-line web, drawn outward once, in the chart-maker's three inks **S**
- [ ] Optional soft UI sounds (off by default) **S**
- [x] The chart room: IM Fell for names, New York for text, water lettered in italics; the icon's rose behind the sidebar, turning to a new bearing with each space and following the fingers in a swipe; rhumb lines, paper grain, gilt seals for favorites, paper slips, chart borders; "Where to?" **M**
- [x] Heritage space colors (Claret, Cognac, Ochre, Vellum, Sage, Verdigris, Navy, Heather) replace the candy palette; existing spaces map to the nearest **S**
- [x] Theme picker with live preview (the window takes the color as you pick; Cancel puts it back); per-space themes **S**
- [x] Light/dark/auto per space (pages follow it) **S**
- [x] Performance pass: tab rows observe only their own tab; only the page view reads load progress **S**

## Phase 2: Daily-driver essentials

What makes someone keep it as their default browser.

- [x] Find in page (⌘F, ⌘G, ⇧⌘G) **S**
- [x] History store (SQLite, per profile, frecency) + history in the command bar; Clear History **M**
- [x] History window (⌘Y): by day, search, open, copy, delete entries **S**
- [x] Command bar 2.0: instant answers (calculator, unit conversion), search shortcuts (yt, gh, w…), commands by name, key hints **M**
- [x] Command bar: inline domain autocomplete, currency conversion (Frankfurter rates, fetched on first use) **M**
- [x] Command bar: the time elsewhere ("time in tokyo", "3pm pst in almaty"), from macOS's own zone data **S**
- [x] Command bar: opt-in search suggestions (Google, DuckDuckGo, Kagi, Bing; never for addresses) **S**
- [x] Command bar: editable search shortcuts (Settings → General) **S**
- [x] Built-in ad/tracker blocking with `WKContentRuleList` (see note below) **M**
- [x] Downloads panel (progress ring in the sidebar, list with progress, Show in Finder, double-click to open, clear) **S**
- [x] Settings window: search engine, default browser button, archive timing, blocker toggles, paused sites, link rules **S**
- [x] Private window (⇧⌘P): a full window with tabs, split and Reader on its own in-memory profile; no history/favicon cache/session, no extensions, gone when it closes **M**
- [x] Multiple full browser windows (⌘N, Move to New Window): windows on a space share its sidebar and each shows its own tab; a tab's page is in one window at a time, so picking it elsewhere brings that window forward; all reopen on launch **M**
- [x] Restore back/forward history per tab (WebKit interaction state, saved on quit and every 5 min) **S**
- [x] Tab hibernation: background tabs idle 30 min (not playing sound / using camera) and all of them on memory pressure **S**
- [x] Camera and microphone permissions remembered per site (forget in Settings → Privacy) **S**
- [x] Per-site zoom, remembered like Safari (⌘0 forgets it) **S**
- [x] Reader (⇧⌘R): Mozilla Readability in an isolated world, set in a serif on vellum, scripts off **M**
- [x] Location permission, remembered per site (macOS 27+; WebKit's own prompt before) **S**
- [x] Print (⌘P) **S**
- [x] Page right-click menu: links open in a new tab, Split View, a new window or a private window; search uses your engine; Share on the page **S**
- [x] Spell checking on by default, with the standard Spelling and Grammar menu **S**
- [x] Site notifications: ask on a click, Ask/Allow/Block in the site popover; one tab of each allowed site stays loaded and keeps running in the background; a dot on the tab and a count on the Dock, with macOS banners once Kaizu has a Developer ID **M**

## Phase 3: Arc signature features

- [x] Favorites row + pinned folders (nested, drag in/out, inline rename) **M**
- [x] Rename a tab, and Move to Space (live within a profile, reopened across profiles) **S**
- [x] Today tabs auto-archive + searchable Archive (configurable, 12 h by default) **M**
- [x] Split view (2–4 panes; context menu "Open in Split View", click to focus, saved per space) **L**
- [x] Split view: resizable dividers (double-click to even out), widths remembered across launches **S**
- [x] Split view: drag a sidebar tab onto a side of the page to split there **M**
- [x] Split view: bento layouts: a pane splits again the other way, so rows and columns mix (one pane above two, a 2×2 grid), up to 4 panes **L**
- [x] Split view: drop right at the split's outer edge for a row or column across all of it **S**
- [x] Peek: links from favorites/pinned tabs to other sites open in a preview card; Esc/⌘W closes, "Open as Tab" keeps it without reloading **M**
- [x] Little window (⌥⌘N, and for links from other apps) **M**
- [x] ⌃Tab most-recent switcher with page thumbnails (⌥⌘↑/↓ keep sidebar order) **M**
- [x] Now playing: speaker icon on playing tabs, sidebar mini player for background media, pause **M**
- [x] Mute per tab (isolated-world script, iframes included; extensions can mute too) **M**
- [x] Auto picture-in-picture when leaving a playing video (Settings → General) **S**
- [x] Capture: visible page to the clipboard (⇧⌘2) **S**
- [x] Export as PDF (whole page, one long page like Safari) **S**
- [x] Capture: area select (⇧⌘2; Enter for the whole page) **S**

## Phase 4: Ecosystem

- [x] Web extension host on `WKWebExtension`: toolbar actions with badges, popups, permission prompts, tab/window bridging, persisted installs **L**
  - See [extension compatibility](#extension-compatibility) for the specific packages and features tested. 1Password sign-in and autofill remain open.
- [x] Install flow: unpacked folder or .zip (Settings → Extensions), install confirmation listing access **M**
- [x] Install from Chrome Web Store / Firefox Add-ons: "Add to Kaizu" on an extension's page (CRX unwrapped to its ZIP; XPI as is) **M**
- [x] Import from Safari: Settings → Extensions lists Safari *web* extensions in /Applications and loads them via `WKWebExtension(appExtensionBundle:)` **M**
- [ ] Chrome-style native messaging (reuse Chrome/Brave `NativeMessagingHosts` manifests) to unlock 1Password/Bitwarden desktop integration **M**. On hold: 1Password's app only talks to browsers it approves (it has a "trust this browser" option, but Orion, also WebKit, still failed with it per their forum); Bitwarden's app writes host manifests per known browser. Verify standalone extension autofill and desktop integration separately
- [x] Import from Arc (spaces, pinned tabs, folders, favorites, Today tabs) **M**
- [x] Import Browsing Data: history and bookmarks from Arc, Chrome, Brave, Edge, Vivaldi, a Safari export or any bookmarks .html; history goes to a space's profile, bookmarks to a closed pinned folder, Undo takes both back **M**

## Phase 5: Kaizu's own magic

Differentiators beyond Arc parity. To be sharpened with the market research
([research/arc-and-market.md](research/arc-and-market.md)).

- [x] Zap, the consumer way: Hide Distracting Items (Safari 18's name): click parts of a page to fade them away, remembered per site; Show N Hidden in the site popover **M**
- [ ] Boosts: per-site CSS/JS (developer-ish; only if asked) **M**
- [ ] Opt-in AI without our own accounts: a side panel with *your* claude.ai / chatgpt.com login and a "Send page" button **M**

### Borrowed from Spotlight, Raycast and Ghostty

Kaizu is a browser for everyone, not a developer tool: only ideas a
normal person would use, mostly invisible. (Considered and dropped: a
plain-text config file, link hints, per-tab hotkeys, command aliases,
quicklinks, a `kaizu://` scheme, focus mode, snippets, ⌘1–4 browse
modes, Quick Keys, inline action parameters.)

- [x] ★ Quick search from any app (Ghostty's quick terminal, Raycast): a shortcut set in Settings brings the command bar over whatever you're in; answers right there, pages in a little window. Off by default **M**
- [x] Site settings popover from the address pill's lock (Safari's "Settings for this website"): blocking, zoom, camera/microphone/location (Ask/Allow/Block), clear the site's cookies and data **M**
- [x] Learned ranking: the command bar puts what you usually pick for a query first (local, per profile; Clear History forgets it) **S**
- [x] Every menu item findable in the command bar, read from the menus **S**
- [x] Keyboard Shortcuts card (⌘/), read from the menus **S**
- [x] Pinned tabs and favorites in the system Spotlight (Core Spotlight): ⌘Space → "Gmail" opens your pinned tab **S**
- [ ] Watch page: pick part of a page, get a notification when it changes (price drop, restock) **M**

## Phase 6: Ship it

- [ ] Apple Developer Program; Developer ID signing; hardened runtime; notarization (macOS won't show a site's notifications before this) **M**
- [ ] Request the browser passkey entitlement (Google passkey sign-in) **S** + Apple review time
- [x] Auto-updates (own signed updater, no Sparkle), DMG **M**
- [x] Logs, crash reports (MetricKit + macOS .ips, kept locally), Help → Report a Bug (Mail draft with a zip) **S**
- [x] Public website with the Mac download and first-launch instructions
- [x] [Browser privacy guide](../site/privacy/index.html) covering local data, network requests and user-sent diagnostics
- [ ] Evaluate whether opt-in telemetry would answer a product question
- [x] Bundle ID is `com.joinprototype.kaizu` (Oct 30) **S**

## Notes

**Why Safari extensions don't just work.** Kaizu uses WebKit (Safari's
engine), not Safari. Installed Safari extensions are wired into Safari itself:
- Content blockers (like AdGuard for Safari's six) hand their rule lists only
  to Safari, and macOS stops other apps from reading AdGuard's data.
- Legacy "Safari App Extensions" (AdGuard's toolbar popup) are Safari-only.
- Modern *web* extensions (WebExtension format) can be hosted by us via
  `WKWebExtension`, available in Settings → Extensions.

Tested Oct 24, 2026: the system registry (`pluginkit`) lists AdGuard's six
blockers, but Foundation's extension host API returns none of them to a
non-Safari process. Root cause: the content-blocker extension point requires
private entitlements (`com.apple.private.extension-host.safari-content-blocker`,
`com.apple.private.can-load-any-content-blocker`) that only Safari holds. No
third-party browser reuses Safari content blockers (see
[research/webkit-browsers-extensions.md](research/webkit-browsers-extensions.md)). The
only way to reuse an installed AdGuard's rules is reading its compiled files
with Full Disk Access: fine as a personal hack, not something to ship.

**Ad blocking plan.** Phase 2 ships a built-in blocker: open filter lists
(EasyList, EasyPrivacy) converted to WebKit's content-rule JSON at build time,
compiled once by `WKContentRuleListStore`, cached, and attached to every tab.
This gives the same speed as Safari content blockers. It won't catch
script-injected ads (YouTube) — that needs scriptlets, i.e. Phase 4 with uBlock
Origin Lite. Licensing: AdGuard's converter library is GPL-3.0, so we don't
link it into the app; filter lists carry their own licenses (credit them).
