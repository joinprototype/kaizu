#if DEBUG
import AppKit
import BrowserCore
import WebKit

/// Lets screenshots / manual QA jump straight into a UI state:
///   KAIZU_DEBUG=commandbar|currency|notifications|notifywake|contextmenu|location|space|settings|history|private|peek|switcher|extension|nosidebar|reader|pin|split|splitdrop|capture|quickbar|open|swipe|spotlight|spotlightreset|commands|learn|appearance|hide|hotkeys|tour|bugreport|brokensite|windows|privatewindow|tabmoves|tabsearch|stress|memory|sites|consent|rulelists|listrefresh|audible|showcase|browsingdata|arcimport|arcimport-run .build/debug/Kaizu
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
///
/// The checks CI runs (see .github/workflows/mac.yml) quit when done, and
/// exit with status 1 when they fail.
enum DebugHooks {
    static var arcFile: URL {
        ProcessInfo.processInfo.environment["KAIZU_ARC"].map { URL(fileURLWithPath: $0) } ?? ArcSidebar.fileURL
    }

    static func apply(to store: BrowserStore) {
        let mode = ProcessInfo.processInfo.environment["KAIZU_DEBUG"]
        switch mode {
        // Checks for CI.
        case "private-blocking":
            runCheck("Private-window blocking") { try await checkPrivateBlocking(in: store) }
        case "arcimport-undo-edits":
            runCheck("Arc import Undo") { try await checkArcImportUndo(in: store, file: arcFile) }
        case "arcimport-undo-restored":
            runCheck { await checkRestoredArcImportUndo(in: store) }
        case "bookmark-import-undo":
            runCheck { await checkBookmarkImportUndo(in: store) }
        case "notification-routing", "notification-routing-restored":
            Task { await qaNotificationRouting(store) }
        case "little-window-promotion":
            Task { await checkLittleWindowPromotion(in: store) }
        case "split-capacity":
            checkSplitCapacity(store)
        case "archive-sweep-interrupt":
            interruptArchiveSweep(in: store)
        case "archive-interrupt", "archive-restored":
            checkArchiveRecovery(in: store, interrupt: mode == "archive-interrupt")

        // Scenarios that log what happened.
        case "open": qaOpen(store)
        case "currency": qaCurrency()
        case "commands": qaCommands(store)
        case "learn": qaLearn(store)
        case "reader": qaReader(store)
        case "pin": qaPin(store)
        case "split": qaSplit(store)
        case "splitdrop": qaSplitDrop(store)
        case "capture": qaCapture(store)
        case "hide": qaHide(store)
        case "watch": qaWatch(store)
        case "brokensite": qaBrokenSite(store)
        case "bugreport": qaBugReport(store)
        case "spotlight": qaSpotlight(store)
        case "spotlightreset": clearSpotlight()
        case "hotkeys": qaHotKeys(store)
        case "appearance": qaAppearance(store)
        case "swipe": qaSwipe(store)
        case "windows": qaWindows(store)
        case "privatewindow": qaPrivateWindow(store)
        case "notifications": qaNotifications(store)
        case "notifywake": qaNotifyWake(store)
        case "contextmenu": qaContextMenu(store)
        case "tabsearch": qaTabSearch(store)
        case "tabmoves": qaTabMoves(store)
        case "showcase": qaShowcase(store)
        case "stress": qaStress(store)
        case "memory": qaMemory(store)
        case "consent": qaConsent(store)
        case "rulelists": qaRuleLists(store)
        case "listrefresh": qaListRefresh(store)
        case "audible": qaAudible(store)
        case "sites": qaSites(store)
        case "browsingdata": qaBrowsingData(store)
        case "arcimport": qaArcImportWindow(store)
        case "arcimport-run": qaArcImportRun(store)
        case "tour":
            let tour = MotionTour(store: store)
            Task { await tour.run() }

        // Straight into a UI state.
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
        case "location":
            store.showCommandBar(.currentTab)
        case "space":
            store.beginNewSpace()
        case "settings":
            UtilityWindows.showSettings(app: store.app)
        case "history":
            UtilityWindows.showHistory(app: store.app)
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
        case "private":
            store.openPrivateWindow()
        case "nosidebar":
            if store.isSidebarVisible { store.toggleSidebar() }
        default:
            break
        }
    }

    /// Runs a CI check, then quits. A thrown error is logged under `name`
    /// and fails the run.
    static func runCheck(_ name: String = "", _ check: @escaping () async throws -> Void) {
        Task {
            do {
                try await check()
                NSApp.terminate(nil)
            } catch {
                log("\(name) check failed: \(error)")
                exit(1)
            }
        }
    }

    /// One line of QA output, on standard error.
    nonisolated static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
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

    /// Checks `condition` every 100 ms until it holds or `timeout` runs out;
    /// returns whether it held. For QA checks that something happens: they
    /// go on as soon as it has, instead of after a fixed sleep.
    static func until(_ timeout: Double = 10, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }

    /// Until the tab's page has finished loading.
    static func loaded(_ tab: BrowserTab) async {
        // Let a load that was just asked for start first.
        try? await Task.sleep(for: .milliseconds(200))
        _ = await until { !tab.webView.isLoading && tab.webView.url != nil }
    }

    static func logPageCount(_ store: BrowserStore, _ label: String) {
        func count(_ view: NSView) -> Int {
            (view is WebContainerView ? 1 : 0) + view.subviews.reduce(0) { $0 + count($1) }
        }
        let pages = store.window?.contentView.map(count) ?? 0
        log("QA \(label): \(pages) pages")
    }

    static func webContainer(in view: NSView) -> WebContainerView? {
        view as? WebContainerView ?? view.subviews.lazy.compactMap(webContainer(in:)).first
    }
}
#endif
