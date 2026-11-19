# Kaizu Architecture

How the code is organized today, where it's going, and the rules that keep it
clean as features pile up. Read this before adding a feature.

## Boundaries in the current build

SwiftPM builds the `Kaizu` executable, the `BrowserCore` library and its test target. Session formats and migrations, Arc import planning, history, split layout calculations and filter conversion live in BrowserCore. They can be exercised without opening a browser window.

The executable contains the UI, app and window models, and WebKit integration. Its folders organize responsibilities within one target. `AppModel` owns shared spaces and profiles. Each `BrowserStore` owns one window’s selection and overlays. `BrowserTab` currently owns page state, creates its web view, observes navigation and handles media. Several views and models import WebKit directly.

## Design goals

1. **Engine stays behind a wall.** Only the `WebEngine` module imports WebKit.
   UI and models talk to a tab through our own types, never `WKWebView`.
2. **Models are the source of truth, views are dumb.** Views read `@Observable`
   models and call intent methods. No view mutates arrays or reaches into WebKit.
3. **Every user action is a Command.** Menus, shortcuts, the command bar,
   context menus (and later AI "tidy" features) all run the same `Command`.
   One implementation, one place to add undo, analytics, or availability rules.
4. **User data is sacred.** Persisted formats are versioned and migrated, never
   silently reshaped. Bundle ID `com.joinprototype.kaizu` stays fixed (WebKit keys
   profile data by it).
5. **Design tokens, not literals.** Colors, radii, spacing and motion come from
   `DesignSystem`. A hex literal or `withAnimation(.spring(...))` in a feature
   view is a review smell.
6. **Strict Swift 6 concurrency.** UI + models are `@MainActor`; slow work
   (history writes, favicon fetches, icon decoding) lives in actors.
7. **No singletons outside the composition root.** Services are created once in
   `AppEnvironment` and injected (SwiftUI `Environment`, AppKit initializers).

## Target module layout

SwiftPM targets give us compile-time boundaries (a view literally can't import
WebKit), faster incremental builds, and testable cores.

```
Package.swift
Sources/
  KaizuApp/      executable: main, AppDelegate, menus, window controllers,
                   AppEnvironment (composition root: builds and wires everything)
  BrowserUI/       SwiftUI features, one folder each:
    Window/          root view, content card, split layout
    Sidebar/         top bar, address pill, favorites, pinned tree, tab list
    CommandBar/      field, ranking, suggestion rows
    Spaces/          switcher, swipe paging, space/profile editors
    Settings/  Downloads/  Find/  Peek/  LittleWindow/ ...
  DesignSystem/    Theme, Surface, Motion, Typography, Metrics, shared components
  BrowserCore/     pure Swift (no AppKit/WebKit): models, commands, session
                   schema + migrations, URL input, search engines, ranking
  WebEngine/       WebKit adapter: PageController (owns WKWebView), navigation
                   + UI delegates, downloads, favicons, user agent, content
                   blocking, WKWebExtension host, snapshots
  Storage/         file locations, SessionStore (JSON), HistoryStore (SQLite+FTS5)
Tests/
  BrowserCoreTests/  StorageTests/  WebEngineTests/
Resources/         Info.plist, AppIcon.icns, bundled rule lists
scripts/           make-icon.swift, snapshot.sh, release tooling
docs/              this file, ROADMAP.md, research/
```

Dependency direction (arrows = "may import"):

```
KaizuApp ──▶ BrowserUI ──▶ DesignSystem
     │             │
     │             └──────▶ BrowserCore ◀── WebEngine
     ├──▶ WebEngine                 ▲
     └──▶ Storage ──────────────────┘
```

`BrowserUI` never imports `WebEngine` directly; it gets a page's `NSView` through
a small protocol (`PageViewProviding`) that `KaizuApp` wires up.

## Target state model

```
AppModel (one per app, @MainActor @Observable)
├── profiles: [Profile]          data containers → one WKWebsiteDataStore each
├── spaces:   [Space]            what the sidebar shows; each uses one profile
│   ├── favorites / pinned: [SidebarItem]   tab | folder | split group
│   └── today: [TabID]                      auto-archived after N hours
├── tabs: [TabID: Tab]           persisted fields + observable page state
├── services: history, downloads, favicons, extensions, session store
└── windows: [WindowModel]

WindowModel (one per window; today's `BrowserStore`)
├── activeSpaceID, selectedTabIDs (one per space)
├── sidebar: visible / peeking / width
├── commandBar, toast, find bar, peek
```

- A profile owns website data and shared favorites. Each space uses one profile. Session v2 migrated the earlier combined records into separate profiles and spaces.
- **Tab ≠ PageController.** `Tab` is the persisted/observable record (URL,
  title, pinned URL, last active). `PageController` (WebEngine) is created lazily
  when a tab is shown, owns the `WKWebView`, and pushes title/URL/progress into
  the `Tab`. Unloading a tab = dropping its controller. Today both live in
  `BrowserTab`.
- A `WKWebView` can only be in one view hierarchy, so a tab is shown in at most
  one window/pane at a time; selecting it elsewhere moves focus to it.
- **A split is a tree of panes.** `Space.splitLayout` is a `SplitNode`: a pane,
  or a row or column of nodes with shares, so any pane can split again the other
  way. Arc 1.171 saves less (flat `childrenIds`, one `layoutOrientation` and one
  `itemWidthFactors` per split); Kaizu goes further so one pane can sit above
  two. A drop takes half the pane it lands on, or half the split within 36 pt of
  its outer edge (a row across all of it), and its preview shows that room.
  `BrowserCore/SplitLayout.swift` holds what can be tested without a window: tree
  edits, frames, dividers, the session form. `SplitContent` only draws them: all
  panes are siblings keyed by tab, so changing the layout moves pages and never
  rebuilds them.
  Sessions stay v2. `splitLayout` sits beside the flat `split` list, which stays
  for older builds: they skip the tree and show the same panes side by side, and
  their next save drops the shape, never a tab. Older files' `splitWidths` load as
  a row. A tree that disagrees with `split`, or comes from a later build, gives way
  to the list, so it can't lose the session.
- Windows on the same space list the same sidebar and each selects its own tab;
  no two windows keep the same tab selected. This is Arc's model, kept on
  purpose: Arc tried separate Today tabs per window and went back in 1.5.
  `AppModel.front` is the window
  menus and shortcuts act on: the key one, or the last that was. Closing the
  last window only hides it.
- A private window is a `BrowserStore` with a `privateSpace`, kept in
  `AppModel.privateStores`: its `spaces` is that one space, so everything else
  a window does just works, and whatever goes through `AppModel.spaces` and
  `stores` (session, history sweeps, Spotlight, extensions) never sees it.
  Links from other apps, Spotlight and Settings use `regularFront`.

## Command registry

`App/CommandRegistry.swift` declares the main menu as data: `MenuSpec`s of
`MenuEntry` (a `Command`, a separator or a submenu), in menu order.

```swift
struct Command: Identifiable {
    let id: String               // "file.newTab", "view.reader"
    let title: String
    let key: Key?                // character + modifiers; nil for none
    let isHidden: Bool           // hidden, shortcut still works (⌘1…⌘9)
    let action: Action           // .run { app in … } or .send(#selector(…))
    let isEnabled: (@MainActor (AppModel) -> Bool)?
    let isOn: (@MainActor (AppModel) -> Bool)?   // checkmark
}
```

- `MainMenu.make(app:)` builds the menu bar from it. `.run` commands become
  `CommandMenuItem`s, which validate through `isEnabled`/`isOn`. `.send`
  commands (Undo, Copy, Hide, Minimize, Enter Full Screen…) stay plain items
  that the responder chain answers and validates, as AppKit expects.
- A menu that follows the model is `.dynamic`: Spaces is rebuilt from
  `CommandRegistry.spaceEntries` each time it opens (a `DynamicMenu`).
- The command bar's menu results and the Keyboard Shortcuts card walk the
  built menu bar and take each of our items from its `Command`. Items that
  AppKit owns (the `.send` ones, which it may retitle or rekey, and those it
  inserts: Close All, AutoFill, Start Dictation, Emoji & Symbols, the window
  list) are read as they stand. Menu results keep their `menu.<path>` ids,
  which is what learned picks are stored under.
- The command bar's own curated commands (`paletteCommands`: state-dependent
  titles, symbols, keywords) take their shortcut hints from the registry.
- Shortcuts can become user-remappable later.

## Persistence

- The session records carry a schema version. `SessionRecord.decode` reads the current format or migrates a v1 file. On migration the app attempts to preserve the old bytes before writing the new format.
- The app throttles session saves and performs atomic writes on a serial queue. Before starting browser services, `SessionFiles` backs up the successfully decoded session. If the primary is malformed, it preserves the damaged bytes under a unique name and restores a decodable backup. A newer schema or an unrecoverable error stops startup before a save can replace the session.
- History uses SQLite with FTS5 behind an actor. The archive is a separate JSON file with a limit of 500 tabs.
- Locations: `~/Library/Application Support/Kaizu/` (ours),
  `~/Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore/<profile-uuid>/` (WebKit's).

## Logs and bug reports

- `Log`: OSLog, subsystem `com.joinprototype.kaizu`, one `Logger` per area.
  Log failures and state changes, not routine events. Hosts go in as
  `.private(mask: .hash)` (never at all from private windows); error domains
  and codes are public.
- `Diagnostics`: MetricKit payloads saved to `Diagnostics/` (newest 20), plus
  macOS's own crash reports (.ips) for Kaizu and the WebKit processes it starts.
- Help → Report a Bug: `BugReport` writes `Report.txt`, this session's
  `Kaizu.log` (read back with `OSLogStore`) and two weeks of crash reports to a
  temporary folder, zips it, and opens a Mail draft. Nothing leaves the Mac
  unless the user sends that draft.
- Report a Broken Site: `BrokenSiteReport` (BrowserCore, tested) builds the text,
  the form shows it word for word, and it goes out as a Mail draft with no
  attachment. The site's name only; the full address is opt-in, without
  tracking parameters or logins. No log, so it holds nothing beyond that text.

## Design system

`DesignSystem` owns every visual decision:

- `Theme`: curated palettes with hand-picked light/dark variants
  (backdrop, accent, onAccent). Never derive colors from hue math.
- `Surface`: opaque elevated surfaces, hairlines, scrims. Never put a material
  over web content (page colors bleed through).
- `Typeface`: IM Fell for names (`display`, upright like land on a chart) and
  sections (`water`, in italics); New York everywhere else, from
  `fontDesign(.serif)` at the root of each window.
- `CompassRose`, `RhumbWeb`, `Neatline`, `Graticule`: the chart Kaizu is drawn
  on. The rose and rhumb lines are drawn once into pictures: live vector art
  is redrawn whenever anything in the window animates.
- `Motion`: named springs (`.snap` for chrome, `.pop` for small moments of delight,
  `.glide` for layout) plus Reduce Motion handling in one place.
- `Sound`: the interface sounds, synthesized from struck tones and filtered
  noise with nothing bundled. `Support/SoundPlayer` checks the setting (off
  by default) and macOS's interface-sound setting, and drops repeats.
  `SoundEngine` plays the sounds on its own queue with one `AVAudioEngine`,
  which stops when idle. Sounds are only for user actions, never for events
  a page can repeat.
- `Metrics`: radii, spacing, sidebar dimensions.

## Testing & dev loop

- Swift Testing for `BrowserCore`/`Storage` (URL parsing, ranking, migrations,
  tab/space operations).
- Visual checks: debug builds read `KAIZU_DEBUG=<state>` to boot into a UI
  state; `scripts/snapshot.sh` screenshots the window for review.
- GitHub Actions runs the Swift tests, builds the release app and verifies its code signature on the Xcode 27 runner.
- Logging with `os.Logger`, one subsystem per module.

## Where things live today

| Concern | Files |
|---|---|
| Shared state | `Models/AppModel.swift` + `AppModel+Persistence/Archive/Hibernation/Choices/Spotlight/QuickBar/DataImport.swift` |
| A window's state and actions | `Models/BrowserStore.swift` + `BrowserStore+Tabs/Spaces/Split/Recents/Find/Peek/Reader/External/Privacy/Commands.swift`, `App/BrowserWindowController.swift` |
| A tab and its web view | `Models/BrowserTab.swift` (navigation delegate, mute, picture in picture), `BrowserTab+UIDelegate.swift` (dialogs, popups, permissions), `WebEngine/MediaEvents.swift` |
| Command bar | `Views/CommandBar.swift`, `Views/KeyTextField.swift` (inline completion); answers in `BrowserCore/QuickAnswer.swift`, `CurrencyConversion.swift`, `TimeZoneAnswer.swift`, `SearchShortcut.swift`, `InlineCompletion.swift`; commands it offers in `BrowserStore+Commands.swift` |
| Menus and commands | `App/Command.swift` (`Command`, `MenuSpec`), `App/CommandRegistry.swift` (every main-menu command), `App/MainMenu.swift` (builds the menu bar) |
| Privacy | `WebEngine/ContentBlocker.swift` (rule lists, page scripts, per-site pause), `AutoconsentBridge.swift` with `BrowserCore/ContentBlocking/Autoconsent.swift` (cookie pop-ups: per-frame rules, page-state checks by snippet id), `RuleListCompiler.swift` (compiles in a short-lived copy of the app, started with `--compile-rule-list`), `FilterListUpdater.swift`, `BrowserCore/ContentBlocking/`, `TrackingParameters.swift` |
| Extensions | `WebEngine/ExtensionHost.swift`, `ExtensionAdapters.swift`, `Views/ExtensionViews.swift` |
| Page right-click menu | `WebEngine/PageContextMenu.swift`: `PageWebView` edits WebKit's menu as it opens. Its item identifiers aren't public, so an item WebKit renames just stays as it was. Link destinations fire WebKit's own item, which knows the link, and `createWebViewWith` routes it. |
| Sound in a page | `BrowserTab.isPlayingSound`: WebKit's public playback state calls a silent autoplaying video playing, so it's checked against `_isPlayingAudio`, the one private name Kaizu reads. Without it a tab goes by the public state. The speaker, mini player, auto picture in picture, archiving and hibernation all go by this |
| Site notifications | `WebEngine/SiteNotifications.swift`: a page script stands in for `Notification` and talks to a relay in our content world over DOM events (a handler in the page's world would add `window.webkit`). Its scripts are among the content blocker's standard scripts, because the blocker replaces every user script when its setup changes. Private windows run them too and read nothing, so pages can't spot one. `inactiveSchedulingPolicy` is read only when a web view is made, so a site allowed later reloads from a toast, or in the hibernation sweep once idle. |
| Reader | `BrowserStore+Reader.swift` (Readability in an isolated world), `Views/ReaderView.swift` |
| Arc import | `BrowserCore/ArcSidebar.swift` (reads the file), `ArcImport.swift` (plans what to add, adds only), `Models/BrowserStore+ArcImport.swift`, `Views/ArcImportView.swift` |
| Browsing data import | `BrowserCore/BrowsingData.swift`, `ChromiumProfile.swift` (reads a copy of `History`, plus `Bookmarks`), `SafariExport.swift` (streams only history and bookmarks out of the .zip, nothing unpacked; it also holds passwords), `Models/AppModel+DataImport.swift`, `Views/BrowsingDataImportView.swift` |
| Network fetches we make | filter lists (daily), favicons (http/https, 1 MB cap), Frankfurter exchange rates (on first currency query), search suggestions (opt-in) |
| Bundled page scripts | `Resources/Scripts/` (see its README for sources and licenses) |

Page scripts we write run in WebKit's isolated `.defaultClient` world where
possible (media events, mute, picture in picture, Reader, autoconsent), so
pages can't see or tamper with them. Autoconsent shares that world with the
media script, which already runs in every frame, so it adds no world of its
own; the few checks that need the page's globals are run by the app in the
page's world, chosen by id from the snippets that ship with its rules. `ContentBlocker.standardScripts` survive the blocker's
reinstalls, which clear a controller's scripts.

## Migration from today's layout

The core library and per-window model are in place. Remaining work can be split into independently tested changes:

1. ~~Add `Tests/`~~ (done: `BrowserCore` + Swift Testing); `swift format` config; tests for store ops.
2. Extract `DesignSystem` target (no deps, easy win).
3. Extract `WebEngine`: split `BrowserTab` into `Tab` + `PageController`.
4. Extract `BrowserCore` models + `Storage`; add `schemaVersion`.
5. ~~Introduce `Command`s and generate menus from them.~~ Done: see Command
   registry. (`AppModel` split off for multiple windows; `BrowserStore` is the
   window model, name unchanged.)
6. ~~Session v2: Profile/Space split with migration.~~ Done: records and the
   v1→v2 migration live in `BrowserCore/Session` with tests.
