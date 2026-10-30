# Kaizu Architecture

How the code is organized today, where it's going, and the rules that keep it
clean as features pile up. Read this before adding a feature.

## Principles

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

## State model

```
AppModel (one per app, @MainActor @Observable)
├── profiles: [Profile]          data containers → one WKWebsiteDataStore each
├── spaces:   [Space]            what the sidebar shows; each uses one profile
│   ├── favorites / pinned: [SidebarItem]   tab | folder | split group
│   └── today: [TabID]                      auto-archived after N hours
├── tabs: [TabID: Tab]           persisted fields + observable page state
├── services: history, downloads, favicons, extensions, session store
└── windows: [WindowModel]

WindowModel (one per window)
├── activeSpaceID, selectedTabID(s) (split view = several)
├── sidebar: visible / peeking / width
├── commandBar, toast, find bar, peek
```

- **Profile ≠ Space** (Arc's model). Today they're merged in `Profile`; the
  session v2 migration splits each into one Profile + one Space.
- **Tab ≠ PageController.** `Tab` is the persisted/observable record (URL,
  title, pinned URL, last active). `PageController` (WebEngine) is created lazily
  when a tab is shown, owns the `WKWebView`, and pushes title/URL/progress into
  the `Tab`. Unloading a tab = dropping its controller. Today both live in
  `BrowserTab`.
- A `WKWebView` can only be in one view hierarchy, so a tab is shown in at most
  one window/pane at a time; selecting it elsewhere moves focus to it.

## Commands

```swift
struct Command: Identifiable {
    let id: CommandID            // "tab.close", "space.next", "sidebar.toggle"
    let title: String
    let shortcut: KeyboardShortcut?
    let isAvailable: (CommandContext) -> Bool
    let perform: (CommandContext) -> Void
}
```

`MainMenu` is generated from the registry, the command bar searches it
("Copy URL", "New Space"…), and shortcuts can become user-remappable later.

## Persistence

- `session.json` gets a `schemaVersion`; `SessionMigrator` upgrades old files
  step by step (v1 → v2 …) with a test per migration using fixture files.
- Writes are debounced + atomic; keep `session.backup.json` from the last
  successful launch for corruption recovery.
- History and archive go in SQLite with FTS5 (likely GRDB, our first justified
  dependency), written from an actor off the main thread.
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

## Design system

`DesignSystem` owns every visual decision:

- `Theme`: curated palettes with hand-picked light/dark variants
  (backdrop, accent, onAccent). Never derive colors from hue math.
- `Surface`: opaque elevated surfaces, hairlines, scrims. Never put a material
  over web content (page colors bleed through).
- `Motion`: named springs (`.snap` for chrome, `.pop` for small moments of delight,
  `.glide` for layout) plus Reduce Motion handling in one place.
- `Metrics`: radii, spacing, sidebar dimensions.

## Testing & dev loop

- Swift Testing for `BrowserCore`/`Storage` (URL parsing, ranking, migrations,
  tab/space operations).
- Visual checks: debug builds read `KAIZU_DEBUG=<state>` to boot into a UI
  state; `scripts/snapshot.sh` screenshots the window for review.
- CI (GitHub Actions, macOS runner): build, test, `swift format lint`.
- Logging with `os.Logger`, one subsystem per module.

## Where things live today

| Concern | Files |
|---|---|
| App state and actions | `Models/BrowserStore.swift` + `BrowserStore+Tabs/Spaces/Split/Recents/Archive/Hibernation/Find/Peek/Reader/External/Persistence/Privacy/Commands.swift` |
| A tab and its web view | `Models/BrowserTab.swift` (navigation and UI delegates, permissions, mute, picture in picture, `MediaEvents`) |
| Command bar | `Views/CommandBar.swift`, `Views/KeyTextField.swift` (inline completion); answers in `BrowserCore/QuickAnswer.swift`, `CurrencyConversion.swift`, `SearchShortcut.swift`, `InlineCompletion.swift`; command registry in `BrowserStore+Commands.swift` |
| Privacy | `WebEngine/ContentBlocker.swift` (rule lists, page scripts, per-site pause), `FilterListUpdater.swift`, `BrowserCore/ContentBlocking/`, `TrackingParameters.swift` |
| Extensions | `WebEngine/ExtensionHost.swift`, `ExtensionAdapters.swift`, `Views/ExtensionViews.swift` |
| Reader | `BrowserStore+Reader.swift` (Readability in an isolated world), `Views/ReaderView.swift` |
| Network fetches we make | filter lists (daily), favicons (http/https, 1 MB cap), ECB rates (on first currency query), search suggestions (opt-in) |
| Bundled page scripts | `Resources/Scripts/` (see its README for sources and licenses) |

Page scripts we write run in WebKit's isolated `.defaultClient` world where
possible (media events, mute, picture in picture, Reader), so pages can't see
or tamper with them. `ContentBlocker.standardScripts` survive the blocker's
reinstalls, which clear a controller's scripts.

## Migration from today's layout

Today: one target, folders `App/ Models/ Views/ Support/ DesignSystem/`, with
`BrowserStore` doing everything. Do it in small, always-working steps:

1. ~~Add `Tests/`~~ (done: `BrowserCore` + Swift Testing); `swift format` config; tests for store ops.
2. Extract `DesignSystem` target (no deps, easy win).
3. Extract `WebEngine`: split `BrowserTab` into `Tab` + `PageController`.
4. Extract `BrowserCore` models + `Storage`; add `schemaVersion`.
5. Split `BrowserStore` into `AppModel` + `WindowModel`; introduce `Command`s
   and generate menus from them. (Partly: the store is split by concern into
   `BrowserStore+Tabs/Spaces/Archive/Persistence/Privacy.swift`.)
6. ~~Session v2: Profile/Space split with migration.~~ Done: records and the
   v1→v2 migration live in `BrowserCore/Session` with tests.
