#if DEBUG
import AppKit
import BrowserCore
import CoreSpotlight
import WebKit

/// Lets screenshots / manual QA jump straight into a UI state:
///   KAIZU_DEBUG=commandbar|currency|notifications|notifywake|contextmenu|location|space|settings|history|private|peek|switcher|extension|nosidebar|reader|pin|split|splitdrop|capture|quickbar|open|swipe|spotlight|spotlightreset|commands|learn|appearance|hide|hotkeys|tour|bugreport|brokensite|windows|privatewindow|tabmoves|stress|sites|consent|showcase|browsingdata|arcimport|arcimport-run .build/debug/Kaizu
/// With `commandbar` or `quickbar`, KAIZU_TYPE="gi" types into it key by key (through
/// the real field editor, so inline completion runs).
/// `reader` shows Reader for the selected tab, or for KAIZU_URL.
/// KAIZU_SUPPORT=/some/folder keeps the session, history and so on there
/// instead of Application Support, so QA doesn't touch the real ones.
/// Settings and website data follow the bundle id, so for a fully separate
/// copy also give its Info.plist its own CFBundleIdentifier (re-sign), and
/// delete ~/Library/{WebKit,Caches,Preferences}/<that id> afterwards.
/// `split` splits with the most recent tab, stacks it, then closes it.
/// `splitdrop` hands each page a stand-in for AppKit's drag (a real one from the
/// sidebar isn't simulated): shows the preview on each side of a page, drops there
/// and at the split's outer edge to build rows, stacks and bentos, drags the
/// dividers with mouse events sent through the window, logs each rule as ok or
/// FAILED, leaves one pane above two, saves and quits, with pictures in the folder
/// KAIZU_SHOTS if set. Run again on the same KAIZU_SUPPORT to check what came
/// back, or on a session from an older build to log the split it kept. Opens
/// tabs: use with KAIZU_SUPPORT.
/// `open` opens KAIZU_URL and logs whether the page is showing after 6 s.
/// `bugreport` opens Report a Bug, then writes a report and logs its path.
/// `brokensite` opens KAIZU_URL, pauses blocking there and takes the toast's
/// Report… to the form; KAIZU_SHOT=/path.png saves the form as a picture.
/// `windows` drives several windows, logs each rule as ok or FAILED, saves and
/// quits; run again on the same KAIZU_SUPPORT to check what came back.
/// `privatewindow` drives a private window, logs each rule as ok or FAILED and quits.
/// `tabmoves` renames tabs and moves them between spaces, logs each rule as ok or
/// FAILED and quits; run again on the same KAIZU_SUPPORT to check names came back.
/// `stress` adds KAIZU_TABS pinned tabs (2,000 by default) if there are fewer, times
/// what they cost, then quits; run again on the same KAIZU_SUPPORT to time a launch.
/// `sites` loads each address in the file KAIZU_SITES and logs how it went, with a
/// picture of each in the folder KAIZU_SHOTS if set, then quits.
/// `showcase` fills a window with believable tabs and saves pictures of its main
/// states, light and dark, to the folder KAIZU_SHOTS, then quits.
/// `browsingdata` opens Import Browsing Data; with KAIZU_IMPORT set to a profile
/// folder, an export file, or "arc", it imports that, logs the result and undoes it.
/// `arcimport` opens Import from Arc; `arcimport-run` imports without it and logs
/// the result. KAIZU_ARC=/path/to/StorableSidebar.json reads that instead of Arc's.
enum DebugHooks {
    private static var arcFile: URL {
        ProcessInfo.processInfo.environment["KAIZU_ARC"].map { URL(fileURLWithPath: $0) } ?? ArcSidebar.fileURL
    }

    /// KAIZU_SHOT=/path.png saves the window as a picture.
    static func saveShot(ofWindow title: String) {
        saveShot(of: NSApp.windows.first { $0.title == title })
    }

    static func saveShot(of window: NSWindow?, to file: String? = nil) {
        guard let path = file ?? ProcessInfo.processInfo.environment["KAIZU_SHOT"],
              let view = window?.contentView,
              let picture = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: picture)
        try? picture.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func apply(to store: BrowserStore) {
        switch ProcessInfo.processInfo.environment["KAIZU_DEBUG"] {
        case "private-blocking":
            Task {
                do {
                    try await checkPrivateBlocking(in: store)
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(Data("Private-window blocking check failed: \(error)\n".utf8))
                    exit(1)
                }
            }
        case "notification-routing", "notification-routing-restored":
            Task { await qaNotificationRouting(store) }
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
            store.app.quickBar = QuickBarController(app: store.app)
            store.app.quickBar?.show()
            typeIntoKeyWindow()
        case "commandbar":
            store.showCommandBar(.newTab)
            typeIntoKeyWindow()
            Task {
                try? await Task.sleep(for: .seconds(6))
                saveShot(of: store.window)
            }
        case "currency":
            // KAIZU_TYPE answered through the real feed and its cache.
            let query = ProcessInfo.processInfo.environment["KAIZU_TYPE"] ?? "100 usd to kzt"
            CurrencyFeed.shared.requestIfNeeded()
            Task {
                try? await Task.sleep(for: .seconds(4))
                let answer = QuickAnswer.evaluate(query, rates: CurrencyFeed.shared.rates)
                FileHandle.standardError.write(Data("QA currency \(query): \(answer?.answer ?? "no answer") (\(answer?.question ?? "-"))\n".utf8))
                NSApp.terminate(nil)
            }
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
            // Splits with the most recent tab, stacks it after 2 s, closes it
            // after 6 s. Logs how many pages are in the window at each step.
            store.splitWithRecentTab()
            Task {
                try? await Task.sleep(for: .seconds(2))
                logPageCount(store, "split")
                if let tab = store.selectedTab, let other = store.activeSpace.splitTabs.first(where: { $0 !== tab }) {
                    store.split(other, with: tab.id, at: .pane(other.id, .bottom))
                }
                try? await Task.sleep(for: .seconds(2))
                logPageCount(store, "stacked")
                try? await Task.sleep(for: .seconds(2))
                store.closeSplit()
                try? await Task.sleep(for: .seconds(1))
                logPageCount(store, "closed")
            }
        case "split-capacity":
            checkSplitCapacity(store)
        case "splitdrop":
            qaSplitDrop(store)
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
                store.app.updateSpotlight()
                store.select(store.openTab(nil))
                store.app.openSpotlightItem(tab.id.uuidString)
                FileHandle.standardError.write(Data("QA spotlight indexed \(store.app.spotlightIdentifiers.count) selected pinned \(store.selectedTab === tab)\n".utf8))
            }
        case "windows":
            qaWindows(store)
        case "privatewindow":
            qaPrivateWindow(store)
        case "notifications":
            qaNotifications(store)
        case "contextmenu":
            qaContextMenu(store)
        case "notifywake":
            // After a "notifications" run: its allowed tab comes back loaded.
            Task {
                try? await Task.sleep(for: .seconds(6))
                let tabs = store.app.spaces.flatMap(\.allTabs)
                let allowed = tabs.first { $0.url?.host() == "example.com" }
                let other = tabs.first { $0.url?.host() == "example.org" }
                let passed = allowed?.isLoaded == true && allowed !== store.selectedTab && other?.isLoaded == false
                FileHandle.standardError.write(Data("QA notify \(passed ? "ok" : "FAILED"): allowed tab woke at launch, another stayed asleep\n".utf8))
                NSApp.terminate(nil)
            }
        case "little-window-promotion":
            Task { await checkLittleWindowPromotion(in: store) }
        case "archive-sweep-interrupt":
            interruptArchiveSweep(in: store)
        case "archive-interrupt", "archive-restored":
            checkArchiveRecovery(in: store, interrupt: ProcessInfo.processInfo.environment["KAIZU_DEBUG"] == "archive-interrupt")
        case "tabsearch":
            qaTabSearch(store)
        case "tabmoves":
            qaTabMoves(store)
        case "showcase":
            qaShowcase(store)
        case "stress":
            qaStress(store)
        case "memory":
            qaMemory(store)
        case "consent":
            qaConsent(store)
        case "rulelists":
            qaRuleLists(store)
        case "listrefresh":
            qaListRefresh(store)
        case "audible":
            qaAudible(store)
        case "sites":
            qaSites(store)
        case "browsingdata":
            qaBrowsingData(store)
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
                store.app.learn(.tab(second, in: store.activeSpace), for: "ex", in: store.activeSpace.profile)
                store.app.learn(.tab(second, in: store.activeSpace), for: "ex", in: store.activeSpace.profile)
                store.app.save()
            } else {
                let lead = store.app.topChoice(for: "ex", among: tabs.map { .tab($0, in: store.activeSpace) }, in: store.activeSpace.profile)
                let leads = lead.map { if case .tab(let tab, _) = $0 { tab.url?.absoluteString ?? "" } else { "" } } ?? "nothing"
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
                store.app.applyQuickBarKey()
                FileHandle.standardError.write(Data("QA hotkey \(key.title): \(store.app.isQuickBarKeyTaken ? "taken" : "free")\n".utf8))
            }
            store.settings.quickBarKey = nil
            store.app.applyQuickBarKey()
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
            UtilityWindows.showSettings(app: store.app)
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
            UtilityWindows.showHistory(app: store.app)
        case "bugreport":
            UtilityWindows.showBugReport(app: store.app)
            // Also writes a report (as "Show in Finder" would) and logs where.
            Task {
                try? await Task.sleep(for: .seconds(3))
                let zip = try? await BugReport.write(summary: "QA report", includingDiagnostics: true, store: store)
                FileHandle.standardError.write(Data("QA report \(zip?.path ?? "failed")\n".utf8))
            }
        case "brokensite":
            guard let url = ProcessInfo.processInfo.environment["KAIZU_URL"].flatMap(URL.init(string:)) else { break }
            let tab = store.openTab(url)
            Task {
                try? await Task.sleep(for: .seconds(4))
                store.toggleBlockingOnCurrentSite(tab)
                store.toast?.undo?()
                try? await Task.sleep(for: .seconds(2))
                saveShot(ofWindow: "Report a Broken Site")
                let details = BugReport.siteDetails(for: url, tab: tab, store: store).joined(separator: "; ")
                FileHandle.standardError.write(Data("QA broken site: \(details)\n".utf8))
            }
        case "arcimport":
            UtilityWindows.showArcImport(app: store.app, from: arcFile)
            Task {
                try? await Task.sleep(for: .seconds(2))
                saveShot(ofWindow: "Import from Arc")
            }
        case "bookmark-import-undo":
            Task {
                await checkBookmarkImportUndo(in: store)
                NSApp.terminate(nil)
            }
        case "arcimport-undo-restored":
            Task {
                await checkRestoredArcImportUndo(in: store)
                NSApp.terminate(nil)
            }
        case "arcimport-undo-edits":
            Task {
                do {
                    try await checkArcImportUndo(in: store, file: arcFile)
                    NSApp.terminate(nil)
                } catch {
                    print("Arc import Undo check failed:", error)
                    exit(1)
                }
            }
        case "arcimport-run":
            do {
                let plan = store.arcImport(of: try ArcSidebar.load(from: arcFile), includesToday: true)
                store.importFromArc(plan)
                store.app.save()
                FileHandle.standardError.write(Data("QA arc \(plan.tabCount) tabs, spaces \(store.spaces.map(\.name))\n".utf8))
                if ProcessInfo.processInfo.environment["KAIZU_ARC_UNDO"] != nil {
                    store.toast?.undo?()
                    store.app.save()
                    FileHandle.standardError.write(Data("QA arc undone, spaces \(store.spaces.map(\.name)), tabs \(store.spaces.map(\.allTabs.count))\n".utf8))
                }
            } catch {
                FileHandle.standardError.write(Data("QA arc failed: \(error)\n".utf8))
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
    static func typeIntoKeyWindow(_ typed: String? = nil) {
        guard let text = typed ?? ProcessInfo.processInfo.environment["KAIZU_TYPE"] else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            for character in text {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                editor.insertText(String(character), replacementRange: editor.selectedRange())
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    static func logPageCount(_ store: BrowserStore, _ label: String) {
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
