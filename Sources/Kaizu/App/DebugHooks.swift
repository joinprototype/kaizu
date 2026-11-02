#if DEBUG
import AppKit
import BrowserCore
import CoreSpotlight
import WebKit

/// What a page hears of a tab dragged over it, without the window server.
@MainActor
private final class StandInDrag: NSObject, NSDraggingInfo {
    let draggingLocation: NSPoint
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingDestinationWindow: NSWindow? = nil
    let draggingSourceOperationMask: NSDragOperation = .move
    let draggedImage: NSImage? = nil
    let draggingSource: Any? = nil
    let draggingSequenceNumber = 0
    let springLoadingHighlight: NSSpringLoadingHighlight = .none
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    var draggedImageLocation: NSPoint { draggingLocation }

    init(_ tab: UUID, at location: NSPoint) {
        draggingLocation = location
        draggingPasteboard.clearContents()
        draggingPasteboard.setData(Data(tab.uuidString.utf8), forType: .kaizuTab)
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}

/// Lets screenshots / manual QA jump straight into a UI state:
///   KAIZU_DEBUG=commandbar|currency|notifications|notifywake|contextmenu|location|space|settings|history|private|peek|switcher|extension|nosidebar|reader|pin|split|splitdrop|capture|quickbar|open|swipe|spotlight|spotlightreset|commands|learn|appearance|hide|hotkeys|tour|bugreport|brokensite|windows|privatewindow|tabmoves|stress|sites|showcase|browsingdata|arcimport|arcimport-run .build/debug/Kaizu
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

    /// Launch with `open`: right clicks take a window in front.
    private static func qaContextMenu(_ store: BrowserStore) {
        let app = store.app
        func say(_ text: String) {
            FileHandle.standardError.write(Data("QA menu \(text)\n".utf8))
        }
        func check(_ name: String, _ passed: Bool) {
            say("\(passed ? "ok" : "FAILED"): \(name)")
        }
        func settle(_ seconds: Double = 0.5) async {
            try? await Task.sleep(for: .seconds(seconds))
        }
        func page(_ tab: BrowserTab, _ script: String) async -> String {
            (try? await tab.webView.evaluateJavaScript("String(\(script))")) as? String ?? "failed"
        }
        /// Right-clicks `tab` at a page point and picks `choice`, if any.
        /// Returns what the menu listed.
        func rightClick(_ tab: BrowserTab, _ x: Double, _ y: Double, choosing choice: String? = nil) async -> [String] {
            guard let window = tab.webView.window else { return [] }
            var titles: [String] = []
            PageWebView.onContextMenu = { menu in
                titles = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    menu.cancelTracking()
                    if let choice, let index = menu.items.firstIndex(where: { $0.title == choice }) {
                        menu.performActionForItem(at: index)
                    }
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            await settle()
            let view = tab.webView
            let point = view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                )!
            }
            view.rightMouseDown(with: event(.rightMouseDown))
            await settle(1.2)
            // Only once the menu's gone: it takes the release while it's up.
            view.rightMouseUp(with: event(.rightMouseUp))
            await settle(0.3)
            return titles
        }
        func center(of selector: String, in tab: BrowserTab) async -> (Double, Double) {
            let json = await page(tab, "(() => { const r = document.querySelector('\(selector)').getBoundingClientRect(); return JSON.stringify([r.x + r.width / 2, r.y + r.height / 2]) })()")
            let values = (try? JSONDecoder().decode([Double].self, from: Data(json.utf8))) ?? [0, 0]
            return (values[0], values[1])
        }

        Task {
            let tab = store.openTab(URL(string: "https://example.com/"))
            // A fresh profile compiles its filter lists before the first load.
            for _ in 0..<40 where await page(tab, "!!document.querySelector('a')") != "true" {
                await settle()
            }
            let spelling = NSMenuItem(title: "", action: Selector(("toggleContinuousSpellChecking:")), keyEquivalent: "")
            _ = tab.webView.validateUserInterfaceItem(spelling)
            check("spelling is checked while typing", spelling.state == .on)

            let (x, y) = await center(of: "a", in: tab)
            let onLink = await rightClick(tab, x, y)
            say("on a link: \(onLink)")
            check("links open in a new tab", onLink.contains("Open Link in New Tab"))
            check("or in split view", onLink.contains("Open Link in Split View"))
            check("or a new window", onLink.contains("Open Link in New Window"))
            check("or a private window", onLink.contains("Open Link in Private Window"))

            let before = store.activeSpace.today.count
            _ = await rightClick(tab, x, y, choosing: "Open Link in New Tab")
            await settle(3)
            check("New Tab makes one tab of the link", store.activeSpace.today.count == before + 1)
            if let newTab = store.selectedTab, newTab !== tab {
                check("and the page loads in it", await page(newTab, "document.body.innerText.length > 50") == "true")
                store.close(newTab)
            } else {
                check("and selects it", false)
            }
            store.select(tab)
            await settle(1)

            // A middle click. Only a CGEvent can say which button: NSEvent's
            // factory can't, and with no window its location is the window's.
            let view = tab.webView
            let clicked = view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
            let height = NSScreen.screens.first?.frame.height ?? 0
            func middle(_ type: CGEventType) -> NSEvent? {
                let source = CGEvent(
                    mouseEventSource: nil, mouseType: type,
                    mouseCursorPosition: CGPoint(x: clicked.x, y: height - clicked.y), mouseButton: .center
                )
                return source.flatMap(NSEvent.init(cgEvent:))
            }
            NSApp.activate(ignoringOtherApps: true)
            await settle()
            if let down = middle(.otherMouseDown), let up = middle(.otherMouseUp) {
                say("middle click as NSEvent: button \(down.buttonNumber), location \(down.locationInWindow), wanted \(clicked)")
                view.otherMouseDown(with: down)
                await settle(0.3)
                view.otherMouseUp(with: up)
            }
            await settle(2)
            let background = store.activeSpace.today.first { $0 !== tab }
            check("a middle click opens a background tab", background != nil && store.selectedTab === tab && tab.url?.host() == "example.com")
            if let background { store.close(background) }
            store.select(tab)
            await settle(1)

            _ = await rightClick(tab, x, y, choosing: "Open Link in Split View")
            await settle(2)
            check("Split View opens it beside the page", store.activeSpace.splitTabs.count == 2 && store.activeSpace.splitTabs.contains(tab))
            check("with no stray tab", store.activeSpace.today.count == before + 1)
            let added = store.activeSpace.splitTabs.first { $0 !== tab }
            store.closeSplit()
            if let added { store.close(added) }
            store.select(tab)
            await settle(1)

            let windows = app.stores.count
            _ = await rightClick(tab, x, y, choosing: "Open Link in New Window")
            await settle(2)
            check("New Window opens another window", app.stores.count == windows + 1)
            app.stores.last?.window?.performClose(nil)
            await settle(1)
            store.window?.makeKeyAndOrderFront(nil)
            await settle()

            _ = await rightClick(tab, x, y, choosing: "Open Link in Private Window")
            await settle(2)
            let hidden = app.privateStores.first
            check("Private Window opens it there", hidden?.selectedTab?.url != nil && hidden?.isPrivate == true)
            if let shown = hidden?.selectedTab {
                let inside = await center(of: "a", in: shown)
                let there = await rightClick(shown, inside.0, inside.1)
                say("in a private window: \(there)")
                check("a private window offers no way out of it", !there.contains("Open Link in New Window") && !there.contains("Open Link in Private Window"))
            }
            hidden?.window?.performClose(nil)
            await settle(1)
            store.window?.makeKeyAndOrderFront(nil)
            await settle()

            let onPage = await rightClick(tab, 5, 5)
            say("on the page: \(onPage)")
            check("the page can be shared", onPage.contains { $0.hasPrefix("Share") })

            store.settings.searchEngine = .duckDuckGo
            _ = await page(tab, "void getSelection().selectAllChildren(document.querySelector('h1'))")
            let spot = await page(tab, "(() => { const r = getSelection().getRangeAt(0).getBoundingClientRect(); return JSON.stringify([r.x + r.width / 2, r.y + r.height / 2]) })()")
            let values = (try? JSONDecoder().decode([Double].self, from: Data(spot.utf8))) ?? [0, 0]
            let heading = (values[0], values[1])
            let onText = await rightClick(tab, heading.0, heading.1)
            say("on selected text: \(onText)")
            check("search uses your engine", onText.contains("Search with DuckDuckGo"))
            _ = await rightClick(tab, heading.0, heading.1, choosing: "Search with DuckDuckGo")
            await settle(2)
            check("and goes there with the selection", store.selectedTab?.url?.host()?.contains("duckduckgo") == true)
            store.settings.searchEngine = .google
            say("done")
            NSApp.terminate(nil)
        }
    }

    private static func qaNotifications(_ store: BrowserStore) {
        let app = store.app
        let settings = store.settings
        let permission = SiteNotifications.permission
        func say(_ text: String) {
            FileHandle.standardError.write(Data("QA notify \(text)\n".utf8))
        }
        func check(_ name: String, _ passed: Bool) {
            say("\(passed ? "ok" : "FAILED"): \(name)")
        }
        func settle(_ seconds: Double = 0.5) async {
            try? await Task.sleep(for: .seconds(seconds))
        }
        func page(_ tab: BrowserTab, _ script: String) async -> String {
            (try? await tab.webView.evaluateJavaScript("String(\(script))")) as? String ?? "failed"
        }
        /// A real click, as far as WebKit can tell: only those let a page ask.
        /// It takes a window in front, so launch this hook with `open`.
        func click(_ tab: BrowserTab) async {
            guard let window = tab.webView.window else { return say("no window to click in") }
            let point = tab.webView.convert(NSPoint(x: tab.webView.bounds.midX, y: tab.webView.bounds.midY), to: nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            await settle(1)
            say("clicking: app in front \(NSApp.isActive), window key \(window.isKeyWindow)")
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                )!
                if type == .leftMouseDown {
                    tab.webView.mouseDown(with: event)
                } else {
                    tab.webView.mouseUp(with: event)
                }
            }
        }
        func answerQuestion(allow: Bool) {
            guard let window = store.window, let sheet = window.attachedSheet else { return say("no question to answer") }
            window.endSheet(sheet, returnCode: allow ? .alertFirstButtonReturn : .alertSecondButtonReturn)
        }
        let askOnClick = "void document.addEventListener('click', () => Notification.requestPermission().then(s => { window.__asked = s }))"
        var delivered: [String] = []
        SiteNotifications.onDeliver = { delivered.append($0) }
        settings.sitePermissions["example.com"] = [permission: true]
        settings.sitePermissions["example.org"] = [permission: false]
        settings.sitePermissions["example.net"] = nil
        settings.sitePermissions["example.edu"] = nil

        Task {
            let blocked = store.openTab(URL(string: "https://example.org/"))
            await settle(3)
            let asked = store.openTab(URL(string: "https://example.net/"))
            await settle(3)
            let allowed = store.openTab(URL(string: "https://example.com/"))
            await settle(3)

            // Kaizu runs a script at the end of every load to find the icon.
            // In the page's world that counts as a click, which a page that
            // hooks the DOM could spend on asking for permission.
            let bait = store.openTab(URL(string: "https://example.edu/"))
            await settle(2)
            bait.webView.configuration.userContentController.addUserScript(WKUserScript(source: """
                for (const name of ['querySelector', 'querySelectorAll']) {
                  const real = document[name];
                  document[name] = function (...args) { Notification.requestPermission(); return real.apply(this, args) };
                }
                """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            bait.reload()
            await settle(4)
            check("finding a page's icon can't raise the question", store.window?.attachedSheet == nil)
            if store.window?.attachedSheet != nil {
                answerQuestion(allow: false)
                settings.sitePermissions["example.edu"] = nil
            }
            store.close(bait)
            await settle()
            let icon = store.openTab(URL(string: "https://github.com/"))
            await settle(5)
            check("and icons are still found", icon.favicon != nil)
            store.close(icon)
            await settle()
            store.select(allowed)
            await settle()

            check("pages get no window.webkit", await page(allowed, "typeof window.webkit") == "undefined")
            check("allowed site reads granted", await page(allowed, "Notification.permission") == "granted")
            check("tabs made before the blocker was ready get it too", await page(blocked, "Notification.permission") == "denied")
            check("unasked site reads default", await page(asked, "Notification.permission") == "default")
            let query = "void navigator.permissions.query({ name: 'notifications' }).then(s => { window.__state = s.state })"
            _ = await page(allowed, query)
            await settle()
            check("permissions.query agrees", await page(allowed, "window.__state") == "granted")
            check("subframes keep WebKit's own", await page(allowed, """
                (() => { const f = document.createElement('iframe'); document.body.append(f); return f.contentWindow.Notification.permission })()
                """) != "granted")

            _ = await page(allowed, "void new Notification('Hello', { body: 'From the page', tag: 'one' })")
            await settle()
            check("allowed site reaches macOS", delivered == ["example.com: Hello"])
            _ = await page(allowed, "void ServiceWorkerRegistration.prototype.showNotification.call({}, 'From a worker')")
            await settle()
            check("registration.showNotification too", delivered.contains("example.com: From a worker"))
            delivered = []
            _ = await page(blocked, "void Object.assign(new Notification('Nope'), { onerror() { window.__refused = true } })")
            await settle()
            let refused = await page(blocked, "window.__refused")
            check("blocked site doesn't", delivered.isEmpty && refused == "true")
            let site = URL(string: "https://example.com/")!
            store.contentBlocker.togglePause(on: site, temporarily: true)
            allowed.reload()
            await settle(3)
            check("pausing blocking keeps it", await page(allowed, "Notification.permission") == "granted")
            store.contentBlocker.togglePause(on: site, temporarily: true)
            allowed.reload()
            await settle(3)
            _ = await page(blocked, """
                void window.dispatchEvent(new CustomEvent('kaizu-notification-ask', { detail: JSON.stringify({ kind: 'show', id: 'x', title: 'Forged', ref: 99 }) }))
                """)
            await settle()
            check("nor by talking to the relay itself", delivered.isEmpty)

            store.select(asked)
            await settle(1)
            // Scripts run from here count as a click, so these wait until
            // that has worn off and fire on their own, as a page would.
            _ = await page(asked, """
                void setTimeout(() => Notification.requestPermission().then(s => { window.__asked = s }), 7000)
                """)
            _ = await page(asked, """
                void setTimeout(() => window.dispatchEvent(new CustomEvent('kaizu-notification-ask', { detail: JSON.stringify({ kind: 'request', ref: 98 }) })), 7500)
                """)
            await settle(9)
            let unasked = await page(asked, "window.__asked")
            check("no question without a click", unasked == "default")
            check("nor by forging the question", store.window?.attachedSheet == nil)
            _ = await page(asked, askOnClick)
            await settle(6)
            await click(asked)
            await settle(1)
            check("a real click raises it", store.window?.attachedSheet != nil)
            answerQuestion(allow: true)
            await settle(1)
            let told = await page(asked, "window.__asked")
            check("and the page hears the answer", told == "granted" && settings.sitePermissions["example.net"]?[permission] == true)
            check("an open tab then needs a rebuild", asked.needsRebuildToNotify)
            asked.rebuildToNotify()
            await settle(3)
            let live = asked.webView.configuration.preferences.inactiveSchedulingPolicy == .throttle
            check("Reload rebuilds it in place", live && !asked.needsRebuildToNotify && asked.webView.window != nil)
            check("on the same page", asked.url?.host() == "example.net")

            settings.sitePermissions["example.net"] = nil
            asked.reload()
            await settle(2)
            _ = await page(asked, askOnClick)
            await click(asked)
            await settle(1)
            _ = await page(asked, "void (location.href = 'https://example.edu/')")
            await settle(3)
            answerQuestion(allow: true)
            await settle(1)
            check(
                "the answer goes to the site that asked, not where it went",
                settings.sitePermissions["example.net"]?[permission] == true && settings.sitePermissions["example.edu"] == nil
            )

            store.select(allowed)
            await settle(1)
            _ = await page(allowed, "void document.addEventListener('click', () => { window.open('https://example.com/popup') })")
            await click(allowed)
            await settle(3)
            if let popup = store.activeSpace.allTabs.first(where: { $0.url?.path() == "/popup" }) {
                check("a popup is never rebuilt", !popup.needsRebuildToNotify && popup.notifyingHost == nil)
                check("so it keeps its opener", await page(popup, "window.opener !== null") == "true")
                popup.hibernate()
                check("once hibernated it's a tab like any other", popup.notifyingHost != nil)
                store.close(popup)
            } else {
                check("a popup opens as a tab", false)
            }
            await settle()

            let count = "void (window.__ticks = 0, setInterval(() => window.__ticks++, 1000))"
            _ = await page(allowed, count)
            _ = await page(blocked, count)
            store.select(asked)
            say("waiting 60 s with both in the background")
            await settle(60)
            let awake = Int(await page(allowed, "window.__ticks")) ?? 0
            let asleep = Int(await page(blocked, "window.__ticks")) ?? 0
            say("background ticks: allowed \(awake), other \(asleep)")
            // Whether WebKit pauses the other one varies: only this is ours.
            check("an allowed tab keeps running in the background", awake >= 25)

            let shown = app.reveal(tabWithID: allowed.id)
            await settle()
            check("a click brings its tab forward", shown === allowed && store.selectedTab === allowed)
            check("a closed tab is reported gone", app.reveal(tabWithID: UUID()) == nil)

            let twin = store.openTab(URL(string: "https://example.com/second"), select: false)
            twin.activate()
            await settle(3)
            store.select(asked)
            await settle()
            await app.hibernateIdleTabs()
            check("a tab just left is never reloaded", allowed.isLoaded && twin.isLoaded)
            await app.hibernateIdleTabs(olderThan: 0.001)
            await settle()
            check("one tab per site stays, not all", [allowed, twin].filter(\.isLoaded).count == 1 && !blocked.isLoaded)
            await app.hibernateIdleTabs(olderThan: 0)
            await settle()
            check("a memory warning takes it too", !allowed.isLoaded && !twin.isLoaded)
            app.wakeTabsThatNotify()
            await settle(3)
            check("the sweep wakes one again", [allowed, twin].filter(\.isLoaded).count == 1)
            let awakeTab = allowed.isLoaded ? allowed : twin
            let sleepingTab = allowed.isLoaded ? twin : allowed

            store.select(blocked)
            await settle(3)
            store.select(awakeTab)
            await settle()
            settings.sitePermissions["example.org"] = [permission: true]
            check("a site allowed later calls for a rebuild", blocked.needsRebuildToNotify)
            await app.hibernateIdleTabs()
            check("not while recently used", blocked.needsRebuildToNotify)
            await app.hibernateIdleTabs(olderThan: 0.001)
            await settle(3)
            let policy = blocked.isLoaded ? blocked.webView.configuration.preferences.inactiveSchedulingPolicy : .suspend
            check("once idle it's rebuilt, on the same page", policy == .throttle && !blocked.needsRebuildToNotify && blocked.url?.host() == "example.org")
            settings.sitePermissions["example.org"] = [permission: false]

            settings.archiveAfter = .twelveHours
            store.select(asked)
            await settle()
            awakeTab.lastActiveAt = .distantPast
            sleepingTab.lastActiveAt = .distantPast
            app.archiveStaleTabs()
            await settle()
            let today = store.activeSpace.today
            check("archiving keeps one tab per site", today.contains(awakeTab) != today.contains(sleepingTab))
            let kept = today.contains(awakeTab) ? awakeTab : sleepingTab
            kept.activate()
            await settle(3)

            let hidden = app.openPrivateWindow()
            await settle()
            let inPrivate = hidden.openTab(URL(string: "https://example.com/"))
            await settle(3)
            delivered = []
            check("private windows look like any other", await page(inPrivate, "Notification.toString().includes('native code')") == "false")
            check("but read no saved answers", await page(inPrivate, "Notification.permission") == "default")
            check("and aren't kept awake", inPrivate.notifyingHost == nil)
            _ = await page(inPrivate, "void new Notification('Private')")
            await settle()
            check("and deliver nothing", delivered.isEmpty)
            hidden.window?.performClose(nil)
            await settle()

            _ = await page(kept, "void new Notification('While away')")
            await settle()
            check("it waits on its tab, away from it", kept.unreadNotifications == 1 && NSApp.dockTile.badgeLabel == "1")
            saveShot(of: store.window)
            store.select(kept)
            await settle()
            check("until you look", kept.unreadNotifications == 0 && NSApp.dockTile.badgeLabel == nil)
            if NSApp.isActive {
                _ = await page(kept, "void new Notification('While looking')")
                await settle()
                check("nothing waits when you're looking", kept.unreadNotifications == 0)
            }
            store.select(asked)
            await settle()
            store.addToSplit(kept)
            await settle(1)
            store.select(asked)
            await settle(1)
            if NSApp.isActive {
                _ = await page(kept, "void new Notification('In the other pane')")
                await settle()
                check("nothing waits in a pane on screen", kept.unreadNotifications == 0)
            }
            let elsewhere = store.openTab(URL(string: "https://example.org/elsewhere"))
            await settle(2)
            await app.hibernateIdleTabs(olderThan: 0)
            await settle()
            check("a hidden split can hibernate", !kept.isLoaded && !asked.isLoaded)
            store.select(kept)
            await settle(3)
            check("and comes back when shown", kept.isLoaded && asked.isLoaded)
            store.closeSplit()
            store.close(elsewhere)
            await settle()
            store.select(asked)
            await settle()
            _ = await page(kept, "void new Notification('Then closed')")
            await settle()
            check("another one waits", kept.unreadNotifications == 1)
            let spare = store.openTab(URL(string: "https://example.com/third"), select: false)
            store.close(kept)
            await settle()
            check("closing the tab clears the Dock", NSApp.dockTile.badgeLabel == nil)
            spare.activate()
            await settle(3)

            let macOS = await SiteNotifications.requestDelivery()
            say("macOS delivers: \(macOS.map(String.init(describing:)) ?? "won't for this build")")
            app.save()
            await settle()
            say("done")
            NSApp.terminate(nil)
        }
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
            let named = store.openTab(URL(string: "https://example.org/named"))
            store.rename(named, to: "Named")
            store.close(named)
            store.reopenClosedTab()
            try? await Task.sleep(for: .milliseconds(500))
            check("⇧⌘T keeps a tab's name", store.selectedTab?.customTitle == "Named")
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        }
    }

    private static func qaSplitDrop(_ store: BrowserStore) {
        func check(_ name: String, _ passed: Bool) {
            FileHandle.standardError.write(Data("QA split \(passed ? "ok" : "FAILED"): \(name)\n".utf8))
        }
        let space = store.activeSpace
        /// One pane across the top, two below, sized by hand.
        func bento(_ top: UUID, _ left: UUID, _ right: UUID) -> SplitNode {
            .group(.stacked, [
                SplitChild(node: .pane(top), share: 0.6),
                SplitChild(node: .row([left, right], shares: [0.3, 0.7]), share: 0.4),
            ])
        }
        func catcher(of tab: BrowserTab) -> NSView? {
            (tab.webView.superview as? WebContainerView)?.dropTarget
        }
        func frame(of tab: BrowserTab) -> NSRect {
            tab.webView.convert(tab.webView.bounds, to: nil)
        }
        func close(_ first: CGFloat, _ second: CGFloat) -> Bool {
            abs(first - second) < 2
        }
        var shots = 0
        func shot(_ name: String) {
            guard let folder = ProcessInfo.processInfo.environment["KAIZU_SHOTS"] else { return }
            shots += 1
            saveShot(of: store.window, to: "\(folder)/\(shots)-\(name).png")
        }
        /// Drags `tab` towards that edge of `target`'s page, or right up to
        /// it for the split's own edge, shows the preview for a moment, then
        /// drops it.
        func drop(_ tab: BrowserTab, on target: BrowserTab, _ edge: SplitEdge, outer: Bool = false) async {
            guard let catcher = catcher(of: target) else { return check("the page is showing", false) }
            let box = catcher.convert(catcher.bounds, to: nil)
            let across = outer ? 10 : box.width / 4
            let down = outer ? 10 : box.height / 4
            let point = switch edge {
            case .left: NSPoint(x: box.minX + across, y: box.midY)
            case .right: NSPoint(x: box.maxX - across, y: box.midY)
            case .top: NSPoint(x: box.midX, y: box.maxY - down)
            case .bottom: NSPoint(x: box.midX, y: box.minY + down)
            }
            let drag = StandInDrag(tab.id, at: point)
            _ = catcher.draggingEntered(drag)
            try? await Task.sleep(for: .seconds(2))
            shot("preview-\(edge)")
            _ = catcher.performDragOperation(drag)
            catcher.draggingEnded(drag)
            try? await Task.sleep(for: .seconds(2))
            shot("dropped-\(edge)")
        }
        Task {
            if space.splitTabs.count == 3, space.split.count == 3 {
                let ids = space.split
                check("a bento comes back after quitting", space.splitLayout == bento(ids[0], ids[1], ids[2]))
                try? await Task.sleep(for: .seconds(3))
                logPageCount(store, "restored")
                return NSApp.terminate(nil)
            }
            if case .group(let direction, let children) = space.splitLayout, space.splitTabs.count > 1 {
                check("a split from before trees stays a row", direction == .sideBySide)
                FileHandle.standardError.write(Data("QA split kept: \(children.count) panes, widths \(children.map(\.share))\n".utf8))
                try? await Task.sleep(for: .seconds(2))
                return NSApp.terminate(nil)
            }
            let first = store.openTab(URL(string: "https://www.swift.org/about/"))
            let second = store.openTab(URL(string: "https://example.com/"))
            let third = store.openTab(URL(string: "https://example.org/"), select: false)
            let fourth = store.openTab(URL(string: "https://example.net/"), select: false)
            let fifth = store.openTab(URL(string: "https://www.iana.org/"), select: false)
            let names = [first.id: "a", second.id: "b", third.id: "c", fourth.id: "d", fifth.id: "e"]
            let layout = { describe(space.splitLayout, names) }
            try? await Task.sleep(for: .seconds(3))

            guard let window = store.window else { return check("there's a window", false) }
            actAsFrontmost(window)
            // App Nap, out of sight, stretches a double-click into two clicks.
            let awake = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "QA")

            await drop(first, on: second, .left)
            check("left of a page sits beside it", layout() == "[a | b]")
            logPageCount(store, "side by side")

            let wide = frame(of: first)
            let gap = NSPoint(x: wide.maxX + 4, y: wide.midY)
            await mouse(in: window, at: gap, dragTo: NSPoint(x: gap.x + 60, y: gap.y))
            try? await Task.sleep(for: .milliseconds(300))
            shot("divider-across")
            check("a divider drags across", close(frame(of: first).width, wide.width + 60))
            await mouse(in: window, at: NSPoint(x: gap.x + 60, y: gap.y))
            await mouse(in: window, at: NSPoint(x: gap.x + 60, y: gap.y), clicks: 2)
            try? await Task.sleep(for: .milliseconds(500))
            check("double-clicking it evens them out", close(frame(of: first).width, frame(of: second).width))

            await drop(third, on: second, .bottom)
            check("below a pane in a row stacks just that pane", layout() == "[a | [b / c]]")
            check("the pane beside it stays as it was", close(frame(of: first).height, wide.height) && close(frame(of: first).width, wide.width))
            logPageCount(store, "bento")

            await drop(fourth, on: first, .top)
            check("each column stacks, into a grid", layout() == "[[d / a] | [b / c]]")
            check("four is the limit", catcher(of: third)?.draggingEntered(StandInDrag(fifth.id, at: .zero)) == [])
            store.split(third, with: fifth.id, at: .pane(third.id, .top))
            check("a fifth changes nothing", layout() == "[[d / a] | [b / c]]")
            check("but its panes still move", store.canSplit(third, with: second.id))
            await drop(second, on: third, .right)
            check("a pane moves and what it left closes up", layout() == "[[d / a] | c | b]")

            store.removeFromSplit(fourth)
            check("a pane leaving closes up too", layout() == "[a | c | b]")
            store.select(third)
            store.addToSplit(fourth)
            check("a pane added from the sidebar joins the end", layout() == "[a | c | b | d]")
            store.removeFromSplit(fourth)
            store.select(fifth)
            store.addToSplit(third)
            check("a split with another tab starts a row", layout() == "[e | c]")

            await drop(first, on: third, .bottom, outer: true)
            check("the bottom edge of a split takes a row across it", layout() == "[[e | c] / a]")
            check("under both panes", close(frame(of: first).width, frame(of: fifth).width + frame(of: third).width + 8))
            await drop(second, on: third, .top, outer: true)
            check("the top edge joins the rows", layout() == "[b / [e | c] / a]")
            await drop(second, on: third, .right, outer: true)
            check("a pane moves to the side of the whole split", layout() == "[[[e | c] / a] | b]")
            check("beside everything", close(frame(of: second).height, frame(of: first).height + frame(of: third).height + 8))

            store.closeSplit()
            store.select(first)
            try? await Task.sleep(for: .seconds(1))
            await drop(second, on: first, .bottom)
            check("a lone page stacks", layout() == "[a / b]")
            await drop(third, on: second, .right)
            check("one pane on top, two below", layout() == "[a / [b | c]]")

            let top = frame(of: first)
            let left = frame(of: second)
            let right = frame(of: third)
            check("the top pane spans the two below", close(top.width, left.width + right.width + 8))

            let rule = NSPoint(x: top.midX, y: top.minY - 4)
            await mouse(in: window, at: rule, dragTo: NSPoint(x: rule.x, y: rule.y - 60))
            try? await Task.sleep(for: .milliseconds(300))
            shot("divider-down")
            check("the rule between rows drags down", close(frame(of: first).height, top.height + 60))
            check("taking from both panes below", close(frame(of: second).height, left.height - 60) && close(frame(of: third).height, right.height - 60))

            let bar = NSPoint(x: left.maxX + 4, y: frame(of: second).midY)
            await mouse(in: window, at: bar, dragTo: NSPoint(x: bar.x + 40, y: bar.y))
            try? await Task.sleep(for: .milliseconds(300))
            check("the divider between them drags across", close(frame(of: second).width, left.width + 40) && close(frame(of: third).width, right.width - 40))
            check("leaving the top pane alone", close(frame(of: first).width, top.width) && close(frame(of: first).height, top.height + 60))

            await mouse(in: window, at: NSPoint(x: bar.x + 40, y: bar.y))
            await mouse(in: window, at: NSPoint(x: bar.x + 40, y: bar.y), clicks: 2)
            try? await Task.sleep(for: .milliseconds(500))
            check("double-clicking evens its own row", close(frame(of: second).width, frame(of: third).width) && close(frame(of: first).height, top.height + 60))
            let moved = NSPoint(x: rule.x, y: rule.y - 60)
            await mouse(in: window, at: moved)
            await mouse(in: window, at: moved, clicks: 2)
            try? await Task.sleep(for: .milliseconds(500))
            check("and the rule evens the rows", close(frame(of: first).height, frame(of: second).height))

            let tallest = frame(of: second).height
            await mouse(in: window, at: rule, dragTo: NSPoint(x: rule.x, y: rule.y - 2000))
            try? await Task.sleep(for: .milliseconds(300))
            check("no pane drags away to nothing", frame(of: second).height > 40 && frame(of: second).height < tallest)

            space.splitLayout = bento(first.id, second.id, third.id)
            try? await Task.sleep(for: .milliseconds(300))
            shot("bento")
            ProcessInfo.processInfo.endActivity(awake)
            NSApp.terminate(nil)
        }
    }

    /// A layout as text: `[a / [b | c]]`.
    private static func describe(_ node: SplitNode?, _ names: [UUID: String]) -> String {
        switch node {
        case nil: "none"
        case .pane(let id): names[id] ?? "?"
        case .group(let direction, let children):
            "[" + children.map { describe($0.node, names) }.joined(separator: direction == .stacked ? " / " : " | ") + "]"
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

    /// Gestures ignore the click that would activate a window, and a QA run
    /// sits behind whatever's in front. Has the app say it's active and `window`
    /// say it's key without taking focus. Just that window: AppKit's own, like
    /// the menu bar's, aren't ready to be.
    private static func actAsFrontmost(_ window: NSWindow) {
        let isKey: @convention(block) (NSWindow) -> Bool = { [weak window] in $0 === window }
        if let method = class_getInstanceMethod(NSWindow.self, #selector(getter: NSWindow.isKeyWindow)) {
            method_setImplementation(method, imp_implementationWithBlock(isKey))
        }
        let isActive: @convention(block) (NSApplication) -> Bool = { _ in true }
        if let method = class_getInstanceMethod(NSApplication.self, #selector(getter: NSApplication.isActive)) {
            method_setImplementation(method, imp_implementationWithBlock(isActive))
        }
    }

    /// A press, an optional drag and a release, through the window as the
    /// mouse's would come. A real drag between views needs the window server;
    /// this reaches gestures, which can't tell.
    private static func mouse(in window: NSWindow, at start: NSPoint, dragTo end: NSPoint? = nil, clicks: Int = 1) async {
        func send(_ type: NSEvent.EventType, _ point: NSPoint) async {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1
            ) else { return }
            window.sendEvent(event)
            try? await Task.sleep(for: .milliseconds(30))
        }
        if let end {
            // Behind other apps, a click after a pause only wakes the window.
            await send(.leftMouseDown, start)
            await send(.leftMouseUp, start)
            try? await Task.sleep(for: .milliseconds(500))
            await send(.leftMouseDown, start)
            for step in 1...10 {
                let progress = CGFloat(step) / 10
                await send(.leftMouseDragged, NSPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress))
            }
        } else {
            await send(.leftMouseDown, start)
        }
        await send(.leftMouseUp, end ?? start)
    }

}
#endif
