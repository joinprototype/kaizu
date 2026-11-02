#if DEBUG
import AppKit
import BrowserCore
import CoreSpotlight

/// Lets screenshots / manual QA jump straight into a UI state:
///   KAIZU_DEBUG=commandbar|currency|location|space|settings|history|private|peek|switcher|extension|nosidebar|reader|pin|split|splitdrop|capture|quickbar|open|swipe|spotlight|spotlightreset|commands|learn|appearance|hide|hotkeys|tour|bugreport|brokensite|windows|privatewindow|tabmoves|stress|sites|showcase|browsingdata|arcimport|arcimport-run .build/debug/Kaizu
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
@MainActor
enum DebugHooks {
    private static var arcFile: URL {
        ProcessInfo.processInfo.environment["KAIZU_ARC"].map { URL(fileURLWithPath: $0) } ?? ArcSidebar.fileURL
    }

    /// KAIZU_SHOT=/path.png saves the window as a picture.
    private static func saveShot(ofWindow title: String) {
        saveShot(of: NSApp.windows.first { $0.title == title })
    }

    private static func saveShot(of window: NSWindow?, to file: String? = nil) {
        guard let path = file ?? ProcessInfo.processInfo.environment["KAIZU_SHOT"],
              let view = window?.contentView,
              let picture = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: picture)
        try? picture.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func qaPrivateWindow(_ store: BrowserStore) {
        let app = store.app
        func check(_ name: String, _ passed: Bool) {
            FileHandle.standardError.write(Data("QA private \(passed ? "ok" : "FAILED"): \(name)\n".utf8))
        }
        func settle(_ seconds: Double = 0.5) async {
            try? await Task.sleep(for: .seconds(seconds))
        }
        Task {
            let site = URL(string: "https://example.org/")!
            let regular = store.openTab(site)
            await settle(3)
            let hidden = app.openPrivateWindow()
            await settle()
            check("it's a window of its own, in front", hidden.isPrivate && app.front === hidden && app.regularFront === store)
            check("its space isn't shared", !app.spaces.contains { $0 === hidden.activeSpace } && hidden.spaces.count == 1)
            check("its profile is in memory", hidden.activeSpace.profile.isPrivate && !hidden.activeSpace.profile.dataStore.isPersistent)
            check("it's dark", hidden.window?.appearance?.name == .darkAqua)

            let one = hidden.openTab(URL(string: "https://example.org/private-page"))
            await settle(3)
            check("a page opens in it", hidden.selectedTab === one && one.webView.window === hidden.window)
            let two = hidden.openTab(site, after: one, select: false)
            check("and more tabs", hidden.activeSpace.today.count == 2 && two.profile === one.profile)

            saveShot(of: hidden.window)
            let cookie = "document.cookie = 'kaizu=private'; document.cookie"
            _ = try? await one.webView.evaluateJavaScript(cookie)
            let outside = (try? await regular.webView.evaluateJavaScript("document.cookie")) as? String ?? "?"
            check("its cookies stay in it", !outside.contains("kaizu=private"))

            hidden.close(two)
            hidden.reopenClosedTab()
            await settle()
            check("⇧⌘T works inside it", hidden.activeSpace.today.count == 2 && app.closedTabs.isEmpty)

            let secret = URL(string: "https://example.org/private-page")!
            hidden.select(two)
            app.front = store
            check("a page off screen stays with its private window", one.store === hidden)
            check("an ordinary one with the ordinary windows", store.selectedTab !== regular || regular.store === store)
            let others = app.openPrivateWindow()
            others.window?.performClose(nil)
            await settle()
            check("and a second private window doesn't take it", one.store === hidden)
            hidden.window?.makeKeyAndOrderFront(nil)
            app.front = hidden
            hidden.select(one)
            await settle()

            hidden.toggleBlockingOnCurrentSite(one)
            let saved = UserDefaults.standard.stringArray(forKey: "blockingPausedSites") ?? []
            check("pausing blocking there isn't saved", store.contentBlocker.isPaused(on: secret) && !saved.contains("example.org") && !store.contentBlocker.pausedSites.contains("example.org"))

            let closing = hidden.openTab(URL(string: "https://example.org/closing"))
            await settle()
            hidden.close(closing)
            await settle()
            check("closing a tab there moves to its neighbor", hidden.selectedTab != nil)

            hidden.togglePin(one)
            hidden.newFolder()
            check("nothing pins there", hidden.activeSpace.pinned.isEmpty)
            check("the archive isn't offered there", hidden.archive.isEmpty)

            let count = hidden.activeSpace.today.count
            app.regularFront.openExternal(URL(string: "https://example.org/from-another-app")!)
            await settle()
            check("links from other apps skip it", hidden.activeSpace.today.count == count)
            let littleWindows = app.littleWindows.count
            hidden.openLittleWindow(URL(string: "https://example.org/little"))
            await settle()
            check("a little window from it stays inside it", app.littleWindows.count == littleWindows && hidden.activeSpace.today.count == count + 1)

            app.save()
            let session = (try? String(contentsOf: AppPaths.support.appending(path: "session.json"), encoding: .utf8)) ?? ""
            check("the session doesn't mention it", session.contains("example.org") && !session.contains("private-page") && !session.contains("\"Private\""))
            let stored = await store.history?.search("private-page", profile: hidden.activeSpace.profile.id) ?? []
            let shared = await store.history?.search("private-page", profile: store.activeSpace.profile.id) ?? []
            check("history doesn't either", stored.isEmpty && shared.isEmpty)
            app.updateSpotlight()
            check("nor Spotlight", !app.spotlightIdentifiers.contains(one.id.uuidString))

            let ordinary = app.openWindow()
            await settle()
            check("⌘N from it is an ordinary window", !ordinary.isPrivate && app.stores.contains { $0 === ordinary })
            ordinary.window?.performClose(nil)
            hidden.window?.makeKeyAndOrderFront(nil)
            app.front = hidden
            await settle()

            hidden.window?.performClose(nil)
            await settle()
            check("closing it ends it", app.privateStores.isEmpty && one.isDiscarded && hidden.window == nil)
            check("and the ordinary window is in front again", app.front === store)
            check("a site paused there is forgotten", !store.contentBlocker.isPaused(on: secret))
            NSApp.terminate(nil)
        }
    }

    private static func qaTabMoves(_ store: BrowserStore) {
        func check(_ name: String, _ passed: Bool) {
            FileHandle.standardError.write(Data("QA tabs \(passed ? "ok" : "FAILED"): \(name)\n".utf8))
        }
        Task {
            if let named = store.spaces.flatMap(\.allTabs).first(where: { $0.customTitle != nil }) {
                check("a name comes back after quitting", named.displayTitle == "My page")
                return NSApp.terminate(nil)
            }
            let home = store.activeSpace
            let page = URL(string: "https://example.com/")!
            let tab = store.openTab(page)
            try? await Task.sleep(for: .seconds(2))
            let pageTitle = tab.title
            store.rename(tab, to: "  My page ")
            check("a tab takes a name", tab.displayTitle == "My page" && tab.title == pageTitle)
            store.rename(tab, to: "   ")
            check("no name goes back to the page's", tab.customTitle == nil && tab.displayTitle == pageTitle)
            store.rename(tab, to: "My page")

            store.commit(SpaceDraft(name: "Same profile", hue: Theme.all[1].hue, symbol: Space.symbols[1], profile: .existing(home.profile.id)))
            let same = store.activeSpace
            store.commit(SpaceDraft(name: "Other profile", hue: Theme.all[2].hue, symbol: Space.symbols[2], profile: .new))
            let other = store.activeSpace
            store.switchTo(home)
            try? await Task.sleep(for: .seconds(1))

            let webView = tab.webView
            let stay = store.openTab(URL(string: "https://example.com/stay"))
            store.select(tab)
            store.move(tab, toSpace: same)
            try? await Task.sleep(for: .milliseconds(500))
            check("moved within a profile it stays live", same.today.contains(tab) && !home.today.contains(tab) && tab.webView === webView && !tab.isDiscarded)
            check("the window moves on", store.selectedTab === stay)

            store.switchTo(same)
            store.move(tab, toSpace: other)
            try? await Task.sleep(for: .milliseconds(500))
            let reopened = other.today.first
            check("across profiles it reopens there", tab.isDiscarded && same.today.isEmpty && reopened?.profile === other.profile && reopened?.url == tab.url)
            check("with its name", reopened?.displayTitle == "My page")
            check("nothing selected where it left", store.selectedTab == nil)
            store.switchTo(home)
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        }
    }

    private static func qaShowcase(_ store: BrowserStore) {
        guard let folder = ProcessInfo.processInfo.environment["KAIZU_SHOTS"] else { return }
        func shoot(_ name: String) {
            guard let view = store.window?.contentView, let picture = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: picture)
            try? picture.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
        }
        func tab(_ address: String, _ title: String) -> BrowserTab {
            BrowserTab(profile: store.activeSpace.profile, app: store.app, url: URL(string: address), title: title, pinnedURL: URL(string: address))
        }
        Task {
            let space = store.activeSpace
            shoot("empty-dark")
            space.appearance = .light
            store.updateWindowAppearance()
            try? await Task.sleep(for: .seconds(2))
            shoot("empty-light")

            for (address, title) in [("https://mail.google.com/", "Gmail"), ("https://calendar.google.com/", "Calendar"), ("https://github.com/", "GitHub"), ("https://www.youtube.com/", "YouTube")] {
                space.profile.favorites.append(tab(address, title))
            }
            let reading = Folder(name: "Reading", isExpanded: true, children: [
                .tab(tab("https://www.theverge.com/", "The Verge")),
                .tab(tab("https://news.ycombinator.com/", "Hacker News")),
            ])
            space.pinned = [.tab(tab("https://www.notion.so/", "Notes")), .tab(tab("https://www.figma.com/", "Figma")), .folder(reading)]
            let pages = [
                ("https://en.wikipedia.org/wiki/Nautical_chart", "Nautical chart - Wikipedia"),
                ("https://www.bbc.com/", "BBC Home"),
                ("https://stackoverflow.com/", "Newest Questions - Stack Overflow"),
                ("https://www.apple.com/", "Apple"),
            ]
            for (address, title) in pages.reversed() {
                store.openTab(URL(string: address), select: false).title = title
            }
            store.commit(SpaceDraft(name: "Work", hue: Theme.all[5].hue, symbol: Space.symbols[1], profile: .existing(space.profile.id)))
            store.commit(SpaceDraft(name: "Home", hue: Theme.all[0].hue, symbol: Space.symbols[2], profile: .existing(space.profile.id)))
            store.switchTo(space)
            for favorite in space.profile.favorites + space.pinned.tabs + space.today {
                favorite.activate()
            }
            store.select(space.today[0])
            try? await Task.sleep(for: .seconds(8))
            shoot("page-light")

            for (index, theme) in Theme.all.enumerated() where ["verdigris", "navy", "ochre"].contains(theme.id) {
                let other = store.spaces[1]
                other.hue = theme.hue
                other.appearance = index % 2 == 0 ? .dark : .light
                store.switchTo(other)
                try? await Task.sleep(for: .seconds(1.5))
                shoot("theme-\(theme.id)")
                store.switchTo(space)
                try? await Task.sleep(for: .seconds(0.6))
            }
            store.showCommandBar(.newTab)
            try? await Task.sleep(for: .seconds(1))
            shoot("commandbar-light")
            typeIntoKeyWindow("wiki")
            try? await Task.sleep(for: .seconds(1.5))
            shoot("commandbar-typed")
            store.dismissCommandBar()
            store.showToast("Pinned to \(space.name)", symbol: "pin.fill")
            try? await Task.sleep(for: .seconds(0.5))
            shoot("toast-light")

            space.appearance = .dark
            store.updateWindowAppearance()
            try? await Task.sleep(for: .seconds(2))
            shoot("page-dark")
            store.showCommandBar(.newTab)
            try? await Task.sleep(for: .seconds(1))
            shoot("commandbar-dark")
            store.dismissCommandBar()
            space.appearance = .light
            store.updateWindowAppearance()
            try? await Task.sleep(for: .seconds(1))

            store.showFindBar()
            store.updateFind("chart")
            try? await Task.sleep(for: .seconds(1))
            shoot("find")
            store.hideFindBar()
            store.advanceTabSwitcher(backwards: false)
            try? await Task.sleep(for: .seconds(1))
            shoot("switcher")
            store.commitTabSwitcher(to: 0)
            store.peek(URL(string: "https://www.bbc.com/")!, from: space.today[0])
            try? await Task.sleep(for: .seconds(3))
            shoot("peek")
            store.closePeek()
            try? await Task.sleep(for: .seconds(1))
            store.beginEditing(space)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: store.window?.attachedSheet, to: folder + "/space-editor.png")
            store.spaceDraft = nil
            try? await Task.sleep(for: .seconds(1))
            let lost = store.openTab(URL(string: "https://nonexistent.invalid/"))
            try? await Task.sleep(for: .seconds(3))
            shoot("error")
            store.close(lost)
            try? await Task.sleep(for: .seconds(2))
            store.toggleReader()
            try? await Task.sleep(for: .seconds(4))
            FileHandle.standardError.write(Data("QA reader shown: \(store.reader != nil)\n".utf8))
            shoot("reader")
            store.closeReader()
            UtilityWindows.showAbout(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "About Kaizu" }, to: folder + "/about.png")
            NSApp.windows.first { $0.title == "About Kaizu" }?.close()
            UtilityWindows.showKeyboardShortcuts(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "Keyboard Shortcuts" }, to: folder + "/shortcuts.png")
            NSApp.windows.first { $0.title == "Keyboard Shortcuts" }?.close()
            UtilityWindows.showHistory(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "History" }, to: folder + "/history.png")
            NSApp.windows.first { $0.title == "History" }?.close()

            UtilityWindows.showSettings(app: store.app)
            try? await Task.sleep(for: .seconds(1))
            saveShot(of: NSApp.windows.first { $0.title == "Settings" }, to: folder + "/settings.png")
            NSApp.windows.first { $0.title == "Settings" }?.close()

            let hidden = store.app.openPrivateWindow()
            let page = hidden.openTab(URL(string: "https://www.apple.com/"))
            page.title = "Apple"
            try? await Task.sleep(for: .seconds(3))
            saveShot(of: hidden.window, to: folder + "/private.png")
            hidden.window?.performClose(nil)

            store.select(space.today[1])
            store.openLittleWindow(URL(string: "https://example.com/"))
            try? await Task.sleep(for: .seconds(2))
            saveShot(of: NSApp.keyWindow, to: folder + "/little.png")
            NSApp.terminate(nil)
        }
    }

    private static func qaStress(_ store: BrowserStore) {
        let app = store.app
        let count = ProcessInfo.processInfo.environment["KAIZU_TABS"].flatMap(Int.init) ?? 2_000
        func log(_ text: String) {
            FileHandle.standardError.write(Data("QA stress: \(text)\n".utf8))
        }
        func time(_ label: String, times: Int = 1, _ body: () -> Void) {
            let start = ContinuousClock.now
            for _ in 0..<times { body() }
            let total = (ContinuousClock.now - start) / times
            log("\(label): \(Double(total.components.attoseconds) / 1e15 + Double(total.components.seconds) * 1000) ms")
        }
        var process = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var query = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        sysctl(&query, 4, &process, &size, nil, 0)
        let started = process.kp_proc.p_starttime
        let launch = Date().timeIntervalSince1970 - (Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
        log("launch: \(Int(launch * 1000)) ms with \(store.activeSpace.allTabs.count) tabs")
        Task {
            let space = store.activeSpace
            if space.pinned.tabs.count < count {
                let pages = (0..<count).map { BrowsingData.Bookmark.page(title: "Page \($0) - Example", url: URL(string: "https://example.com/\($0)")!) }
                let data = BrowsingData(bookmarks: pages)
                let bookmarks = data.bookmarkFolder(named: "Stress", skipping: [])
                await app.importBrowsingData([], bookmarks: bookmarks, into: space)
                log("added \(space.pinned.tabs.count) pinned tabs")
            }
            let first = store.openTab(URL(string: "about:blank"))
            let second = store.openTab(URL(string: "about:blank"))
            try? await Task.sleep(for: .seconds(1))
            log("tabs in space: \(space.allTabs.count)")
            time("selectedTab", times: 1000) { _ = store.selectedTab }
            time("allTabs", times: 100) { _ = space.allTabs }
            time("backgroundMediaTab", times: 100) { _ = store.backgroundMediaTab }
            time("isShowing", times: 1000) { _ = store.isShowing(first) }
            time("tab switch (model only)", times: 200) { store.select(first); store.select(second) }
            time("save on the main thread") { app.save(inBackground: true) }
            time("updateSpotlight unchanged") { app.updateSpotlight() }
            if let folder = space.pinned.folders.first {
                time("open folder") {
                    store.toggle(folder)
                    store.window?.contentView?.layoutSubtreeIfNeeded()
                    store.window?.displayIfNeeded()
                }
                try? await Task.sleep(for: .seconds(1))
                time("tab switch, folder open") {
                    store.select(first)
                    store.window?.contentView?.layoutSubtreeIfNeeded()
                    store.window?.displayIfNeeded()
                }
                time("close folder") {
                    store.toggle(folder)
                    store.window?.contentView?.layoutSubtreeIfNeeded()
                    store.window?.displayIfNeeded()
                }
            }
            second.title = "Changed"
            time("saveTabStates") { app.saveTabStates() }
            try? await Task.sleep(for: .seconds(2))
            NSApp.terminate(nil)
        }
    }

    private static func qaSites(_ store: BrowserStore) {
        let environment = ProcessInfo.processInfo.environment
        guard let list = environment["KAIZU_SITES"], let text = try? String(contentsOfFile: list, encoding: .utf8) else { return }
        let probe = """
            JSON.stringify({text: document.body ? document.body.innerText.trim().length : -1,
              nodes: document.querySelectorAll('*').length, images: document.images.length,
              height: document.documentElement.scrollHeight,
              consent: (window.autoconsentStandalone?.messages ?? []).filter(m => m.type != 'eval').map(m => m.type + (m.cmp ? ':' + m.cmp : '') + (m.result !== undefined ? '=' + m.result : '')).slice(-6),
              oneTap: !!document.querySelector('iframe[src*="accounts.google.com/gsi/iframe/select"]') && getComputedStyle(document.querySelector('iframe[src*="accounts.google.com/gsi/iframe/select"]')).display != 'none'})
            """
        let settling = environment["KAIZU_SITE_WAIT"].flatMap(Double.init) ?? 2.5
        Task {
            for line in text.split(separator: "\n") {
                guard let url = URL(string: String(line)) else { continue }
                let tab = store.openTab(url)
                let start = ContinuousClock.now
                try? await Task.sleep(for: .seconds(1))
                while tab.isLoading, ContinuousClock.now - start < .seconds(15) {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                let loaded = (ContinuousClock.now - start).components.seconds
                try? await Task.sleep(for: .seconds(settling))
                let result = (try? await tab.webView.evaluateJavaScript(probe)) as? String ?? "{}"
                let name = url.host() ?? "site"
                FileHandle.standardError.write(Data("QA site \(name) | \(tab.url?.host() ?? "none") | \(loaded)s\(tab.isLoading ? " still loading" : "") | \(result) | \(tab.title.prefix(50))\n".utf8))
                if let folder = environment["KAIZU_SHOTS"], let image = await tab.screenshot(of: nil), let data = image.tiffRepresentation {
                    let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                    try? png?.write(to: URL(fileURLWithPath: folder).appending(path: "\(name).png"))
                }
                store.close(tab)
            }
            NSApp.terminate(nil)
        }
    }

    private static func qaBrowsingData(_ store: BrowserStore) {
        func log(_ text: String) {
            FileHandle.standardError.write(Data("QA browsing data: \(text)\n".utf8))
        }
        UtilityWindows.showBrowsingDataImport(app: store.app)
        log("browsers \(ChromiumProfile.installed().map(\.title))")
        guard let path = ProcessInfo.processInfo.environment["KAIZU_IMPORT"] else {
            Task {
                try? await Task.sleep(for: .seconds(3))
                saveShot(ofWindow: "Import Browsing Data")
            }
            return
        }
        let source: BrowsingDataImportView.Source
        if path == "arc", let arc = ChromiumProfile.installed().first(where: { $0.browser == "Arc" }) {
            source = .browser(arc)
        } else if path.hasSuffix(".zip") || path.hasSuffix(".html") || path.hasSuffix(".json") {
            source = .file(URL(fileURLWithPath: path))
        } else {
            source = .browser(ChromiumProfile(browser: "QA", title: "QA", directory: URL(fileURLWithPath: path)))
        }
        Task {
            do {
                let data = try await Task.detached { try source.read() }.value
                let space = store.activeSpace
                let profile = space.profile.id
                let pinnedBefore = space.pinned.count
                let bookmarks = data.bookmarkFolder(named: source.folderName, skipping: space.pinnedAddresses)
                log("read \(data.visits.count) pages, \(bookmarks?.count ?? 0) new bookmarks")
                await store.app.importBrowsingData(data.visits, bookmarks: bookmarks, into: space)
                let stored = await store.history?.recent(profile: profile, limit: 100_000).count ?? 0
                log("toast \(store.toast?.message ?? "none")")
                log("stored \(stored) pages, pinned \(pinnedBefore) -> \(space.pinned.count), folder open \(space.pinned.folders.last?.isExpanded ?? false)")
                log("second time \(data.bookmarkFolder(named: source.folderName, skipping: space.pinnedAddresses)?.count ?? 0) new bookmarks")
                let moved = store.openTab(URL(string: "https://example.com/moved-in"))
                if let folder = space.pinned.folders.last {
                    store.move(moved, to: .pinned(folder: folder, before: nil))
                }
                store.undoToast()
                try? await Task.sleep(for: .seconds(1))
                log("a tab moved into the folder survives undo: \(space.today.contains(moved) && !moved.isDiscarded && moved.pinnedURL == nil)")
                let left = await store.history?.recent(profile: profile, limit: 100_000).count ?? 0
                log("after undo \(left) pages, pinned \(space.pinned.count)")
            } catch {
                log("failed \(error)")
            }
        }
    }

    private static func qaWindows(_ store: BrowserStore) {
        let app = store.app
        func check(_ name: String, _ passed: Bool) {
            FileHandle.standardError.write(Data("QA windows \(passed ? "ok" : "FAILED"): \(name)\n".utf8))
        }
        func settle() async {
            try? await Task.sleep(for: .milliseconds(500))
        }
        func page(_ path: String) -> URL? {
            URL(string: "https://example.com/\(path)")
        }
        Task {
            if app.stores.count > 1 {
                let second = app.stores[1]
                let saved = second.savedFrame
                await settle()
                check("two windows came back", app.stores.count == 2)
                check("each window kept its own tab", store.selectedTab != nil && second.selectedTab != nil && store.selectedTab !== second.selectedTab)
                check("second window kept its place", saved != nil && second.window?.frameDescriptor == saved)
                check("first window kept its place", store.savedFrame != nil && store.window?.frameDescriptor == store.savedFrame)
                second.window?.performClose(nil)
                await settle()
                check("closing a window leaves its tabs in the sidebar", app.stores.count == 1 && store.activeSpace.today.count == 4)
                store.window?.performClose(nil)
                await settle()
                check("the last window only hides", app.stores.count == 1 && store.window?.isVisible == false)
                check("⌘N brings it back instead of leaving it hidden", app.openWindow() === store && app.stores.count == 1)
                await settle()
                check("with its page", store.window?.isVisible == true && store.selectedTab != nil)
                return NSApp.terminate(nil)
            }

            let one = store.openTab(page("one"))
            let two = store.openTab(page("two"), select: false)
            await settle()
            let second = app.openWindow()
            await settle()
            check("a new window starts on the same space, empty, in front", second.activeSpaceID == store.activeSpaceID && second.selectedTab == nil && app.front === second)
            check("and off to the side of the last", second.window?.frame != store.window?.frame)

            second.perform(.url(page("typed")!), mode: .newTab)
            await settle()
            let typed = second.selectedTab
            check("a page opened from the command bar opens in that window", typed?.url?.lastPathComponent == "typed" && typed?.webView.window === second.window)
            check("and the other window keeps its page", store.selectedTab === one && one.webView.window === store.window)
            store.settings.linkRoutes = [LinkRoute(pattern: "example.com", spaceID: second.activeSpaceID)]
            app.front.openExternal(page("routed")!)
            await settle()
            let routed = second.selectedTab
            check("a link routed to this space opens in the window in front", routed?.url?.lastPathComponent == "routed" && store.selectedTab === one)
            store.settings.linkRoutes = []
            typed.map(second.close)
            routed.map(second.close)

            second.select(two)
            await settle()
            check("each window shows its own tab", second.selectedTab === two && two.webView.window === second.window && one.webView.window === store.window)

            second.select(one)
            await settle()
            check("selecting a tab shown elsewhere brings that window forward", app.front === store && second.selectedTab === two)
            check("as the key window, when Kaizu is the active app", !NSApp.isActive || store.window?.isKeyWindow == true)

            store.close(two)
            await settle()
            check("closing a tab never steals one from another window", second.selectedTab == nil && store.selectedTab === one)

            let three = second.openTab(page("three"))
            await settle()
            store.moveToNewWindow(one)
            await settle()
            let third = app.stores[2]
            check("a tab can move to a window of its own", third.selectedTab === one)
            check("its page goes with it", one.webView.window === third.window)
            check("the window it left has nothing free to show", store.selectedTab == nil)

            let four = store.openTab(page("four"))
            await settle()
            store.addToSplit(three)
            await settle()
            check("a split takes its pane from the window showing it", second.selectedTab == nil && three.webView.window === store.window && four.webView.window === store.window)
            check("and leaves no page behind", third.window?.isVisible == true && one.webView.window === third.window)
            third.select(three)
            await settle()
            check("a split shows in one window", third.selectedTab === one && app.front === store)
            let five = third.openTab(page("five"))
            await settle()
            let split = store.activeSpace.split
            third.addToSplit(one)
            third.closeSplit()
            check("a window leaves another's split alone", store.activeSpace.split == split && third.selectedTab === five)
            third.select(one)
            await settle()
            store.closeSplit()
            store.select(four)
            await settle()

            let home = store.activeSpace
            store.commit(SpaceDraft(name: "Work", hue: Theme.all[1].hue, symbol: Space.symbols[1], profile: .existing(home.profile.id)))
            await settle()
            second.select(four)
            store.switchTo(home)
            await settle()
            check("a tab another window took isn't selected any more", store.selectedTab == nil && second.selectedTab === four)

            let empty = app.openWindow()
            await settle()
            empty.addToSplit(four)
            await settle()
            check("a window with nothing to split with takes nothing", second.selectedTab === four && empty.selectedTab == nil)
            empty.window?.performClose(nil)
            await settle()

            let work = store.spaces.last ?? home
            let favorite = store.openTab(page("favorite"))
            store.move(favorite, to: .favorites(before: nil))
            await settle()
            second.switchTo(work)
            second.select(favorite)
            await settle()
            store.switchTo(home)
            store.moveToNewWindow(favorite)
            await settle()
            let fourth = app.stores[app.stores.count - 1]
            check("a favorite shown on another space moves out too", fourth.selectedTab === favorite && favorite.webView.window === fourth.window && second.selectedTab == nil)
            fourth.window?.performClose(nil)
            await settle()
            second.switchTo(home)
            second.select(four)
            await settle()

            third.select(five)
            await settle()
            five.lastActiveAt = .distantPast
            third.window?.performClose(nil)
            await settle()
            store.select(one)
            await settle()
            check("a closed window's tabs can show elsewhere", app.stores.count == 2 && one.webView.window === store.window)
            check("and count as just used", five.lastActiveAt.map { -$0.timeIntervalSinceNow < 60 } == true)

            store.window?.setFrameOrigin(NSPoint(x: 240, y: 60))
            second.window?.setFrameOrigin(NSPoint(x: 200, y: 90))
            NSApp.terminate(nil)
        }
    }

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
            store.app.quickBar = QuickBarController(app: store.app)
            store.app.quickBar?.show()
            typeIntoKeyWindow()
        case "commandbar":
            store.showCommandBar(.newTab)
            typeIntoKeyWindow()
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
                store.app.updateSpotlight()
                store.select(store.openTab(nil))
                store.app.openSpotlightItem(tab.id.uuidString)
                FileHandle.standardError.write(Data("QA spotlight indexed \(store.app.spotlightIdentifiers.count) selected pinned \(store.selectedTab === tab)\n".utf8))
            }
        case "windows":
            qaWindows(store)
        case "privatewindow":
            qaPrivateWindow(store)
        case "tabmoves":
            qaTabMoves(store)
        case "showcase":
            qaShowcase(store)
        case "stress":
            qaStress(store)
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
                store.app.learn(.tab(second), for: "ex", in: store.activeSpace.profile)
                store.app.learn(.tab(second), for: "ex", in: store.activeSpace.profile)
                store.app.save()
            } else {
                let lead = store.app.topChoice(for: "ex", among: tabs.map(Suggestion.tab), in: store.activeSpace.profile)
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
                let details = BugReport.siteDetails(for: url, store: store).joined(separator: "; ")
                FileHandle.standardError.write(Data("QA broken site: \(details)\n".utf8))
            }
        case "arcimport":
            UtilityWindows.showArcImport(app: store.app, from: arcFile)
            Task {
                try? await Task.sleep(for: .seconds(2))
                saveShot(ofWindow: "Import from Arc")
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
    private static func typeIntoKeyWindow(_ typed: String? = nil) {
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
