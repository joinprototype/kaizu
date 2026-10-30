# Kaizu Roadmap

Arc-style browser, native WebKit, quiet craft. This is the living plan: what's
missing versus Arc, in what order we build it, and how it should *feel*.
Architecture rules live in [ARCHITECTURE.md](ARCHITECTURE.md); market research
in [research/](research/).

Effort: **S** = an evening, **M** = a few sessions, **L** = a project.

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
   - [ ] autoconsent v2: isolated content world + native rule filtering (DDG-style), smaller per-frame cost. Measure first: the 600 KB script is parsed in every frame; moving to an isolated world needs a native bridge for the rules that `eval` page state (DDG evaluates those in the page world), and must be checked on real CMPs before it replaces v1
   - [x] filter list auto-updates (daily; newer of downloaded vs bundled wins)
   - [x] per-site "pause blocking" (shield in address pill, per-tab controllers, no recompiles)
   - [ ] broken-site reporting
   - [x] strip tracking parameters (utm_*, fbclid, gclid…) on navigation and Copy Link
   - [ ] evaluate Brave's adblock-rust converter vs ours (coverage, scriptlets)
7. [ ] Find in page, history, Peek, split view **L** total
8. [ ] Phase 1 motion pass on the core interactions **M**
9. [ ] Arc importer from `StorableSidebar.json` with a preview + one-click import (format documented in research/arc-sidebar-format.md; fixture in Tests) **M**
10. [ ] Developer ID signing + notarization, apply for the passkey entitlement **M** (self-update and the test page at kaizu.joinprototype.com landed Oct 30)

## Product principles

1. **Feel first.** Every interaction has intentional motion; nothing jumps, nothing janks.
2. **Native and light.** WebKit + AppKit/SwiftUI. Battery life and memory are features.
3. **Quiet craft.** Understated, precise, built to last. Old-world chart-maker care; never flashy, never generic.
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
| Spaces (theme + tabs, bound to a profile) | ✓ | profile = space | P0 split, P1 swipe | M | — |
| Favorites row (per profile) | ✓ | pinned grid only | P3 | S | — |
| Pinned folders | ✓ | — | P3 | M | — |
| Today tabs auto-archive + Archive | ✓ | — | P3 | M | — |
| Command bar: history, actions, suggestions | ✓ | tabs + URL/search | P2 | M | — |
| History | ✓ | — | P2 | M | WebKit has no global history; we store it (SQLite+FTS5) |
| Find in page | ✓ | — | P2 | S | `findString(_:configuration:)` ✓ |
| Downloads panel | ✓ | silent save | P2 | S | `WKDownload` progress ✓ |
| Multiple / private windows | ✓ | one window | P2 | M | `WKWebsiteDataStore.nonPersistent()` |
| Back/forward kept across restarts | ✓ | URL only | P2 | S | `interactionState` ✓ |
| Ad + tracker blocking | via extensions | — | P2 built-in | M | `WKContentRuleList` ✓ (same engine as Safari content blockers) |
| Split view | ✓ | — | P3 | L | several page views per window |
| Peek (link preview overlay) | ✓ | — | P3 | M | promote preview to tab without reload |
| Little Arc (mini window) | ✓ | — | P3 | M | `NSPanel` |
| ⌃Tab recent-tab switcher | ✓ | cycles list order | P3 | M | `takeSnapshot` ✓ for thumbnails |
| Media: now playing, mute, auto-PiP | ✓ | now playing, mute | P3 | M | event-driven via isolated-world script; auto-PiP ✓ |
| Capture / screenshots | ✓ | — | P3 | S | `takeSnapshot`, `createPDF` ✓ |
| Extensions | Chrome Web Store | — | P4 | L | `WKWebExtension` ✓ (macOS 15.4+) |
| Password managers | extensions | manual typing | P4 via extensions | L | 1Password/Bitwarden web extensions |
| Passkeys | ✓ | blocked | P6 | — | needs Apple's browser passkey entitlement |
| Import (Arc / Chrome / Safari) | ✓ | — | P4 | M | Arc keeps its sidebar in `StorableSidebar.json` |
| Boosts (per-site CSS/JS) | ✓ | — | P5 | M | `WKUserScript` ✓ |
| AI features | Arc Max | — | P5, opt-in | M | side panel with the user's own claude.ai / ChatGPT login |
| Settings window | ✓ | — | P2 | S | — |
| Sync across devices | ✓ | — | later | L | CloudKit candidate |
| Easels, Windows/iOS apps | ✓ | — | not planned | — | — |

## Phase 0: Foundation

Make the codebase ready to grow (details in [ARCHITECTURE.md](ARCHITECTURE.md)).

- [x] GitHub repo (`joinprototype/kaizu`, `develop` → `master`) **S**
- [ ] CI (build + test + `swift format lint`); needs a runner with the macOS 27 SDK **S**
- [x] `Tests/` with Swift Testing: filter conversion, sessions, history, URL input, quick answers, completion (53 tests) **S**
- [ ] Split into modules: DesignSystem → WebEngine → BrowserCore + Storage **M**
- [ ] `BrowserStore` → `AppModel` + `WindowModel`; `Command` registry drives menus **M**
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
row insertion, Clear's teardown. Still open: pre-warming a web view per
profile so opening a tab never builds one mid-animation; measuring whether
the sidebar toggle's per-frame page resize stutters on heavy pages; Reduce
Motion swapping slides for dissolves (it currently just turns them off).

Measured (Oct 25, night) with `KAIZU_DEBUG=tour` on a 120 Hz display,
optimized build: every interaction (command bar, sidebar, space switch and
swipe, tab switch, split, peek, new/close tab, toasts) runs at 120 fps with
0 to 2 late frames (worst about 21 ms, so never below 60 fps). Most late
frames move around between runs (noise); the one that repeats is the frame
where a space swipe lets go and the new space's page takes over. Next
candidates: the command bar's first frames (it builds its rows), and
pre-warming the web view, as above.

Plus, where Kaizu gets its personality:
- [x] Loading delight: a compass needle in the address pill swings while a page loads and settles on north when done **S**
- [x] A chart-paper empty state: a sea chart's rhumb-line web, drawn outward once, in the chart-maker's three inks **S**
- [ ] Optional soft UI sounds (off by default) **S**
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
- [x] Command bar: inline domain autocomplete, currency conversion (ECB rates, fetched on first use) **M**
- [x] Command bar: opt-in search suggestions (Google, DuckDuckGo, Kagi, Bing; never for addresses) **S**
- [x] Command bar: editable search shortcuts (Settings → General) **S**
- [x] Built-in ad/tracker blocking with `WKContentRuleList` (see note below) **M**
- [x] Downloads panel (progress ring in the sidebar, list with progress, Show in Finder, double-click to open, clear) **S**
- [x] Settings window: search engine, default browser button, archive timing, blocker toggles, paused sites, link rules **S**
- [x] Private window (⇧⌘P): in-memory profile, no history/favicon cache/session, no extensions, links stay inside **M**
- [ ] Multiple full browser windows **M**
- [x] Restore back/forward history per tab (WebKit interaction state, saved on quit and every 5 min) **S**
- [x] Tab hibernation: background tabs idle 30 min (not playing media / using camera) and all of them on memory pressure **S**
- [x] Camera and microphone permissions remembered per site (forget in Settings → Privacy) **S**
- [x] Per-site zoom, remembered like Safari (⌘0 forgets it) **S**
- [x] Reader (⇧⌘R): Mozilla Readability in an isolated world, set in a serif on vellum, scripts off **M**
- [x] Location permission, remembered per site (macOS 27+; WebKit's own prompt before) **S**
- [x] Print (⌘P) **S**

## Phase 3: Arc signature features

- [x] Favorites row + pinned folders (nested, drag in/out, inline rename) **M**
- [x] Today tabs auto-archive + searchable Archive (12 h fixed; setting later) **M**
- [x] Split view (2–4 panes; context menu "Open in Split View", click to focus, saved per space) **L**
- [x] Split view: resizable dividers (double-click to even out), widths remembered across launches **S**
- [x] Split view: drag a sidebar tab onto a half of the page to split there **M**
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
  - Targets to verify: uBlock Origin Lite, 1Password, Bitwarden, Dark Reader
- [x] Install flow: unpacked folder or .zip (Settings → Extensions), install confirmation listing access **M**
- [x] Install from Chrome Web Store / Firefox Add-ons: "Add to Kaizu" on an extension's page (CRX unwrapped to its ZIP; XPI as is) **M**
- [x] Import from Safari: Settings → Extensions lists Safari *web* extensions in /Applications and loads them via `WKWebExtension(appExtensionBundle:)` **M**
- [ ] Chrome-style native messaging (reuse Chrome/Brave `NativeMessagingHosts` manifests) to unlock 1Password/Bitwarden desktop integration **M**. On hold: 1Password's app only talks to browsers it approves (it has a "trust this browser" option, but Orion, also WebKit, still failed with it per their forum); Bitwarden's app writes host manifests per known browser. Worth asking both vendors once Kaizu is public; their extensions work on their own meanwhile
- [ ] Import from Arc (spaces, pinned tabs, folders), Chrome, Safari (bookmarks, history) **M**

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

- [ ] ★ Quick search from any app (Ghostty's quick terminal, Raycast): a shortcut set in Settings brings the command bar over whatever you're in; answers right there, pages in a little window. Off by default **M**
- [x] Site settings popover from the address pill's lock (Safari's "Settings for this website"): blocking, zoom, camera/microphone/location (Ask/Allow/Block), clear the site's cookies and data **M**
- [x] Learned ranking: the command bar puts what you usually pick for a query first (local, per profile; Clear History forgets it) **S**
- [x] Every menu item findable in the command bar, read from the menus **S**
- [x] Pinned tabs and favorites in the system Spotlight (Core Spotlight): ⌘Space → "Gmail" opens your pinned tab **S**
- [ ] Watch page: pick part of a page, get a notification when it changes (price drop, restock) **M**

## Phase 6: Ship it

- [ ] Apple Developer Program; Developer ID signing; hardened runtime; notarization **M**
- [ ] Request the browser passkey entitlement (Google passkey sign-in) **S** + Apple review time
- [x] Auto-updates (own signed updater, no Sparkle), DMG **M**
- [x] Logs, crash reports (MetricKit + macOS .ips, kept locally), Help → Report a Bug (Mail draft with a zip) **S**
- [ ] Website, privacy policy, opt-in telemetry **M**
- [x] Bundle ID is `com.joinprototype.kaizu` (Oct 30) **S**

## Notes

**Why Safari extensions don't just work.** Kaizu uses WebKit (Safari's
engine), not Safari. Installed Safari extensions are wired into Safari itself:
- Content blockers (like AdGuard for Safari's six) hand their rule lists only
  to Safari, and macOS stops other apps from reading AdGuard's data.
- Legacy "Safari App Extensions" (AdGuard's toolbar popup) are Safari-only.
- Modern *web* extensions (WebExtension format) can be hosted by us via
  `WKWebExtension`, which is Phase 4.

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
