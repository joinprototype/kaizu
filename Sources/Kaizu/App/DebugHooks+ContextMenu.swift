#if DEBUG
import AppKit
import BrowserCore
import WebKit

extension DebugHooks {
    /// Launch with `open`: right clicks take a window in front.
    static func qaContextMenu(_ store: BrowserStore) {
        let app = store.app
        func say(_ text: String) {
            log("QA menu \(text)")
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
            var dismissed = false
            PageWebView.onContextMenu = { menu in
                titles = menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    menu.cancelTracking()
                    if let choice, let index = menu.items.firstIndex(where: { $0.title == choice }) {
                        menu.performActionForItem(at: index)
                    }
                    dismissed = true
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
            // Only once the menu's gone: it takes the release while it's up.
            _ = await until(3) { dismissed }
            await settle(0.2)
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
            let spelling = NSMenuItem(title: "", action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: "")
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
            check("New Tab makes one tab of the link", await until { store.activeSpace.today.count == before + 1 })
            if let newTab = store.selectedTab, newTab !== tab {
                check("and the page loads in it", await until { await page(newTab, "document.body.innerText.length > 50") == "true" })
                store.close(newTab)
            } else {
                check("and selects it", false)
            }
            store.select(tab)
            _ = await until(3) { store.selectedTab === tab && tab.webView.window != nil }

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
            _ = await until(3) { store.activeSpace.today.contains { $0 !== tab } }
            // And that the page it was on doesn't follow the link too.
            await settle(1)
            let background = store.activeSpace.today.first { $0 !== tab }
            check("a middle click opens a background tab", background != nil && store.selectedTab === tab && tab.url?.host() == "example.com")
            if let background { store.close(background) }
            store.select(tab)
            _ = await until(3) { store.selectedTab === tab && tab.webView.window != nil }

            _ = await rightClick(tab, x, y, choosing: "Open Link in Split View")
            check("Split View opens it beside the page", await until { store.activeSpace.splitTabs.count == 2 && store.activeSpace.splitTabs.contains(tab) })
            check("with no stray tab", store.activeSpace.today.count == before + 1)
            let added = store.activeSpace.splitTabs.first { $0 !== tab }
            store.closeSplit()
            if let added { store.close(added) }
            store.select(tab)
            _ = await until(3) { store.selectedTab === tab && tab.webView.window != nil }

            let windows = app.stores.count
            _ = await rightClick(tab, x, y, choosing: "Open Link in New Window")
            check("New Window opens another window", await until { app.stores.count == windows + 1 })
            app.stores.last?.window?.performClose(nil)
            _ = await until(3) { app.stores.count == windows }
            store.window?.makeKeyAndOrderFront(nil)
            await settle()

            _ = await rightClick(tab, x, y, choosing: "Open Link in Private Window")
            _ = await until { app.privateStores.first?.selectedTab?.url != nil }
            let hidden = app.privateStores.first
            check("Private Window opens it there", hidden?.selectedTab?.url != nil && hidden?.isPrivate == true)
            if let shown = hidden?.selectedTab {
                await loaded(shown)
                _ = await until { await page(shown, "!!document.querySelector('a')") == "true" }
                let inside = await center(of: "a", in: shown)
                let there = await rightClick(shown, inside.0, inside.1)
                say("in a private window: \(there)")
                check("a private window offers no way out of it", !there.contains("Open Link in New Window") && !there.contains("Open Link in Private Window"))
            }
            hidden?.window?.performClose(nil)
            _ = await until(3) { app.privateStores.isEmpty }
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
            check("and goes there with the selection", await until { store.selectedTab?.url?.host()?.contains("duckduckgo") == true })
            store.settings.searchEngine = .google
            say("done")
            NSApp.terminate(nil)
        }
    }
}
#endif
