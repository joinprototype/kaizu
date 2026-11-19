#if DEBUG
import AppKit
import BrowserCore
import WebKit

extension DebugHooks {
    static func qaNotifications(_ store: BrowserStore) {
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
        SiteNotifications.onDeliver = { message, _ in delivered.append(message) }
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
            store.contentBlocker.togglePause(on: site, privateID: allowed.profile.privateID)
            allowed.reload()
            await settle(3)
            check("pausing blocking keeps it", await page(allowed, "Notification.permission") == "granted")
            store.contentBlocker.togglePause(on: site, privateID: allowed.profile.privateID)
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
}
#endif
