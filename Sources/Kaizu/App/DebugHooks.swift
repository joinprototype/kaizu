#if DEBUG
import AppKit
import BrowserCore
import CoreSpotlight

/// Lets screenshots / manual QA jump straight into a UI state:
///   KAIZU_DEBUG=commandbar|location|space|settings|history|private|peek|switcher|extension|nosidebar|reader|pin|split|splitdrop|capture|quickbar|open|swipe|spotlight|spotlightreset|commands|learn|appearance|hide|hotkeys|tour|bugreport .build/debug/Kaizu
/// With `commandbar` or `quickbar`, KAIZU_TYPE="gi" types into it key by key (through
/// the real field editor, so inline completion runs).
/// `reader` shows Reader for the selected tab, or for KAIZU_URL.
/// KAIZU_SUPPORT=/some/folder keeps the session, history and so on there
/// instead of Application Support, so QA doesn't touch the real ones.
/// Settings and website data follow the bundle id, so for a fully separate
/// copy also give its Info.plist its own CFBundleIdentifier (re-sign), and
/// delete ~/Library/{WebKit,Caches,Preferences}/<that id> afterwards.
/// `splitdrop` calls the drop handlers directly; a real drag isn't simulated.
/// `open` opens KAIZU_URL and logs whether the page is showing after 6 s.
/// `bugreport` opens Report a Bug, then writes a report and logs its path.
@MainActor
enum DebugHooks {
    static func apply(to store: BrowserStore) {
        switch ProcessInfo.processInfo.environment["KAIZU_DEBUG"] {
        case "open":
            // KAIZU_URL in a new tab.
            if let url = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)) {
                store.openTab(url)
            }
            Task {
                try? await Task.sleep(for: .seconds(6))
                let shown = store.window?.contentView.flatMap(webContainer(in:)) != nil
                FileHandle.standardError.write(Data("QA selected \(String(describing: store.selectedTab?.url)) page shown \(shown)\n".utf8))
                // KAIZU_INSTALL=1 on a store page installs its extension without asking.
                if ProcessInfo.processInfo.environment["KAIZU_INSTALL"] != nil,
                   let listing = ExtensionGallery.listing(for: store.selectedTab?.url) {
                    await store.extensions.install(listing, askFirst: false)
                    let names = store.extensions.installed.map(\.name)
                    FileHandle.standardError.write(Data("QA installed \(names) listed \(store.extensions.isInstalled(listing))\n".utf8))
                }
            }
        case "quickbar":
            // Straight to the panel: at launch Kaizu is in front, where
            // the shortcut would open the in-window bar instead.
            store.quickBar = QuickBarController(store: store)
            store.quickBar?.show()
            typeIntoKeyWindow()
        case "commandbar":
            store.showCommandBar(.newTab)
            typeIntoKeyWindow()
        case "reader":
            // KAIZU_URL opens a throwaway tab for it, closed again after 12 s.
            let tab = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)).map { store.openTab($0) }
            Task {
                try? await Task.sleep(for: .seconds(4))
                store.toggleReader()
                try? await Task.sleep(for: .seconds(8))
                if let tab { store.close(tab) }
            }
        case "pin":
            // ⌘D on the selected tab, undone again after 2.5 s (while the
            // toast, and so its Undo, is still up).
            if let tab = store.selectedTab {
                store.togglePin(tab)
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    store.undoToast()
                }
            }
        case "split":
            // Splits with the most recent tab; closed again after 6 s. Logs
            // how many pages are in the window, split and after.
            store.splitWithRecentTab()
            Task {
                try? await Task.sleep(for: .seconds(2))
                logPageCount(store, "split")
                try? await Task.sleep(for: .seconds(4))
                store.closeSplit()
                try? await Task.sleep(for: .seconds(1))
                logPageCount(store, "closed")
            }
        case "splitdrop":
            // Opens two pages, shows the drop preview on the second, then
            // drops the first on its left half. Opens tabs: use with
            // KAIZU_SUPPORT.
            let first = store.openTab(URL(string: "https://www.swift.org/about/"))
            let second = store.openTab(URL(string: "https://example.com/"))
            Task {
                try? await Task.sleep(for: .seconds(3))
                let page = store.window?.contentView.flatMap(webContainer(in:))
                page?.tabDrop?.hover(.leading)
                try? await Task.sleep(for: .seconds(4))
                page?.tabDrop?.hover(nil)
                store.split(second, with: first.id, on: .leading)
            }
        case "capture":
            // Opens a page and starts ⇧⌘2 on it. Opens a tab: use with KAIZU_SUPPORT.
            let tab = store.openTab(URL(string: "https://www.swift.org/about/"))
            Task {
                try? await Task.sleep(for: .seconds(3))
                store.beginCapture(of: tab)
            }
        case "location":
            store.showCommandBar(.currentTab)
        case "space":
            store.beginNewSpace()
        case "spotlight":
            // Pins KAIZU_URL's tab, saves (which indexes it), then opens
            // it again as Spotlight would and logs what got selected.
            if let url = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)) {
                let tab = store.openTab(url)
                store.togglePin(tab)
                store.save()
                store.select(store.openTab(nil))
                store.openSpotlightItem(tab.id.uuidString)
                FileHandle.standardError.write(Data("QA spotlight indexed \(store.spotlightIdentifiers.count) selected pinned \(store.selectedTab === tab)\n".utf8))
            }
        case "commands":
            // Logs what the command bar would offer for KAIZU_TYPE.
            Task {
                try? await Task.sleep(for: .seconds(1))
                let query = ProcessInfo.processInfo.environment["KAIZU_TYPE"] ?? ""
                let commands = store.commands(matching: query)
                let found = commands.map { "\($0.title) [\($0.shortcut ?? "")]" }
                FileHandle.standardError.write(Data("QA commands for \(query): \(found)\n".utf8))
                // KAIZU_RUN=1: runs the first one after the menus have been
                // rebuilt (the Spaces menu remakes its items), e.g. for "edit space".
                guard ProcessInfo.processInfo.environment["KAIZU_RUN"] == "1", let first = commands.first else { return }
                try? await Task.sleep(for: .seconds(1.2))
                _ = store.commands(matching: query)
                first.perform()
                FileHandle.standardError.write(Data("QA ran \(first.title): space editor open \(store.spaceDraft != nil)\n".utf8))
            }
        case "learn":
            // First launch: picks the second of two tabs twice after typing
            // "ex". Next launch: logs what "ex" leads with.
            let tabs = store.activeSpace.today
            if tabs.count < 2 {
                let first = store.openTab(URL(string: "https://example.com/"))
                let second = store.openTab(URL(string: "https://example.org/"))
                _ = first
                store.learn(.tab(second), for: "ex")
                store.learn(.tab(second), for: "ex")
                store.save()
            } else {
                let lead = store.topChoice(for: "ex", among: tabs.map(Suggestion.tab))
                let leads = lead.map { if case .tab(let tab) = $0 { tab.url?.absoluteString ?? "" } else { "" } } ?? "nothing"
                FileHandle.standardError.write(Data("QA learned: ex leads with \(leads)\n".utf8))
            }
        case "appearance":
            // A light space and an automatic one: logs the window's look in each.
            store.activeSpace.appearance = .light
            store.updateWindowAppearance()
            let first = store.activeSpace
            store.commit(SpaceDraft(name: "QA", hue: 0.6, symbol: "star", profile: .existing(first.profile.id)))
            let auto = store.window?.effectiveAppearance.name.rawValue ?? "?"
            store.switchTo(first)
            let light = store.window?.effectiveAppearance.name.rawValue ?? "?"
            FileHandle.standardError.write(Data("QA appearance: light space \(light), auto space \(auto)\n".utf8))
        case "hide":
            // Clicks example.com's paragraph through the picking shield (by
            // script; see HiddenItems.isReal), reloads, and logs what was
            // remembered and whether it stays hidden.
            let tab = store.openTab(URL(string: "https://example.com/"))
            Task {
                try? await Task.sleep(for: .seconds(4))
                store.beginHidingItems(on: tab)
                try? await Task.sleep(for: .seconds(1))
                _ = try? await tab.webView.evaluateJavaScript("""
                    window.__kaizuQA = true;
                    const r = document.querySelector("p").getBoundingClientRect();
                    const [x, y] = [r.left + r.width / 2, r.top + r.height / 2];
                    const shield = document.elementFromPoint(x, y);
                    for (const type of ["mousemove", "click"]) {
                        shield.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, bubbles: true, cancelable: true }));
                    }
                    0
                    """, in: nil, contentWorld: HiddenItems.world)
                try? await Task.sleep(for: .seconds(1))
                store.endHidingItems()
                let remembered = store.settings.hiddenItems(on: tab.url)
                tab.reload()
                try? await Task.sleep(for: .seconds(4))
                let display = try? await tab.webView.evaluateJavaScript("getComputedStyle(document.querySelector('p')).display")
                FileHandle.standardError.write(Data("QA hide: remembered \(remembered), after reload display \(String(describing: display))\n".utf8))
                store.settings.showHiddenItems(on: tab.url)
            }
        case "hotkeys":
            // Which quick bar shortcuts this Mac lets us have.
            for key in Settings.QuickBarKey.allCases {
                store.settings.quickBarKey = key
                store.applyQuickBarKey()
                FileHandle.standardError.write(Data("QA hotkey \(key.title): \(store.isQuickBarKeyTaken ? "taken" : "free")\n".utf8))
            }
            store.settings.quickBarKey = nil
            store.applyQuickBarKey()
            // ⌘Space is Spotlight's: must come back taken.
            let spotlight = GlobalHotKey(keyCode: 49, modifiers: 256) {}
            FileHandle.standardError.write(Data("QA hotkey ⌘Space: \(spotlight == nil ? "taken" : "free")\n".utf8))
        case "tour":
            let tour = MotionTour(store: store)
            Task { await tour.run() }
        case "spotlightreset":
            // Removes everything this copy of the app put in Spotlight.
            CSSearchableIndex.default().deleteAllSearchableItems { error in
                FileHandle.standardError.write(Data("QA spotlight cleared \(error == nil)\n".utf8))
            }
        case "swipe":
            // Swipes like the trackpad monitor would: a slow drag past
            // halfway (switches), a short flick (switches), a short slow drag
            // (springs back). Needs two spaces; logs the state after each.
            Task {
                if store.spaces.count < 2 {
                    store.commit(SpaceDraft(name: "QA", hue: 0.6, symbol: "star", profile: .existing(store.spaces[0].profile.id)))
                }
                store.switchTo(store.spaces[0])
                for (label, steps, interval) in [("slow past half", 12, 0.04), ("flick", 4, 0.01), ("short", 3, 0.05)] {
                    try? await Task.sleep(for: .seconds(1))
                    let forward = store.activeSpace === store.spaces[0]
                    let start = ProcessInfo.processInfo.systemUptime
                    store.spaceSwipeTravel = 0
                    store.spaceSwipeSamples = []
                    var travel: CGFloat = 0
                    for step in 1...steps {
                        travel = CGFloat(step) * 12 * (forward ? 1 : -1)
                        store.trackSpaceSwipe(to: travel, at: start + Double(step) * interval)
                    }
                    store.spaceSwipeTravel = nil
                    store.finishSpaceSwipe(travel: travel, at: start + Double(steps) * interval, switches: true)
                    try? await Task.sleep(for: .seconds(1))
                    FileHandle.standardError.write(Data("QA \(label): active \(store.activeSpace.name) pager \(store.pagerSpaces.map(\.name)) offset \(store.spaceSwipeOffset)\n".utf8))
                }
            }
        case "settings":
            UtilityWindows.showSettings(store: store)
        case "peek":
            if let tab = store.selectedTab {
                store.peek(URL(string: "https://www.swift.org/about/")!, from: tab)
            }
        case "switcher":
            store.advanceTabSwitcher(backwards: false)
        case "extension":
            // KAIZU_EXTENSION=/path/to/unpacked-extension
            if let path = ProcessInfo.processInfo.environment["KAIZU_EXTENSION"] {
                Task { await store.extensions.install(from: URL(fileURLWithPath: path), askFirst: false) }
            }
        case "history":
            UtilityWindows.showHistory(store: store)
        case "bugreport":
            UtilityWindows.showBugReport(store: store)
            // Also writes a report (as "Show in Finder" would) and logs where.
            Task {
                try? await Task.sleep(for: .seconds(3))
                let zip = try? await BugReport.write(summary: "QA report", includingDiagnostics: true, store: store)
                FileHandle.standardError.write(Data("QA report \(zip?.path ?? "failed")\n".utf8))
            }
        case "private":
            store.openPrivateWindow()
        case "nosidebar":
            if store.isSidebarVisible { store.toggleSidebar() }
        default:
            break
        }
    }

    /// KAIZU_TYPE, key by key, into the focused field.
    private static func typeIntoKeyWindow() {
        guard let text = ProcessInfo.processInfo.environment["KAIZU_TYPE"] else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            for character in text {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                editor.insertText(String(character), replacementRange: editor.selectedRange())
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private static func logPageCount(_ store: BrowserStore, _ label: String) {
        func count(_ view: NSView) -> Int {
            (view is WebContainerView ? 1 : 0) + view.subviews.reduce(0) { $0 + count($1) }
        }
        let pages = store.window?.contentView.map(count) ?? 0
        FileHandle.standardError.write(Data("QA \(label): \(pages) pages\n".utf8))
    }

    private static func webContainer(in view: NSView) -> WebContainerView? {
        view as? WebContainerView ?? view.subviews.lazy.compactMap(webContainer(in:)).first
    }
}
#endif
