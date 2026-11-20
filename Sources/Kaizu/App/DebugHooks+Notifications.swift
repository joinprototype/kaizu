#if DEBUG
import AppKit
import BrowserCore
import WebEngine
import WebKit

extension DebugHooks {
    static func qaNotifications(_ store: BrowserStore) {
        let app = store.app
        let settings = store.settings
        let permission = SiteNotifications.permission
        func say(_ text: String) {
            log("QA notify \(text)")
        }
        func check(_ name: String, _ passed: Bool) {
            say("\(passed ? "ok" : "FAILED"): \(name)")
        }
        func settle(_ seconds: Double = 0.5) async {
            try? await Task.sleep(for: .seconds(seconds))
        }
        /// Checks `condition` every 100 ms until it holds or `timeout` runs
        /// out; returns whether it held. For checks that something happens.
        func until(_ timeout: Double = 10, _ condition: () async -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .seconds(timeout)
            while ContinuousClock.now < deadline {
                if await condition() { return true }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return await condition()
        }
        /// Until the tab's page has finished loading.
        func loaded(_ tab: BrowserTab) async {
            // Let a load that was just asked for start first.
            await settle(0.2)
            _ = await until { !tab.webView.isLoading && tab.webView.url != nil }
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
            await loaded(blocked)
            let asked = store.openTab(URL(string: "https://example.net/"))
            await loaded(asked)
            let allowed = store.openTab(URL(string: "https://example.com/"))
            await loaded(allowed)

            // Kaizu runs a script at the end of every load to find the icon.
            // In the page's world that counts as a click, which a page that
            // hooks the DOM could spend on asking for permission.
            let bait = store.openTab(URL(string: "https://example.edu/"))
            await loaded(bait)
            bait.webView.configuration.userContentController.addUserScript(WKUserScript(source: """
                for (const name of ['querySelector', 'querySelectorAll']) {
                  const real = document[name];
                  document[name] = function (...args) { Notification.requestPermission(); return real.apply(this, args) };
                }
                """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            bait.reload()
            await loaded(bait)
            // The icon script runs once the load ends; give a question time to show.
            await settle(1)
            check("finding a page's icon can't raise the question", store.window?.attachedSheet == nil)
            if store.window?.attachedSheet != nil {
                answerQuestion(allow: false)
                settings.sitePermissions["example.edu"] = nil
            }
            store.close(bait)
            await settle()
            let icon = store.openTab(URL(string: "https://github.com/"))
            check("and icons are still found", await until { icon.favicon != nil })
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
            check("permissions.query agrees", await until { await page(allowed, "window.__state") == "granted" })
            check("subframes keep WebKit's own", await page(allowed, """
                (() => { const f = document.createElement('iframe'); document.body.append(f); return f.contentWindow.Notification.permission })()
                """) != "granted")

            _ = await page(allowed, "void new Notification('Hello', { body: 'From the page', tag: 'one' })")
            check("allowed site reaches macOS", await until { delivered == ["example.com: Hello"] })
            _ = await page(allowed, "void ServiceWorkerRegistration.prototype.showNotification.call({}, 'From a worker')")
            check("registration.showNotification too", await until { delivered.contains("example.com: From a worker") })
            delivered = []
            _ = await page(blocked, "void Object.assign(new Notification('Nope'), { onerror() { window.__refused = true } })")
            let refused = await until { await page(blocked, "window.__refused") == "true" }
            check("blocked site doesn't", delivered.isEmpty && refused)
            let site = URL(string: "https://example.com/")!
            store.contentBlocker.togglePause(on: site, privateID: allowed.profile.privateID)
            allowed.reload()
            await loaded(allowed)
            check("pausing blocking keeps it", await page(allowed, "Notification.permission") == "granted")
            store.contentBlocker.togglePause(on: site, privateID: allowed.profile.privateID)
            allowed.reload()
            await loaded(allowed)
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
            check("a real click raises it", await until(3) { store.window?.attachedSheet != nil })
            answerQuestion(allow: true)
            let told = await until(3) { await page(asked, "window.__asked") == "granted" }
            check("and the page hears the answer", told && settings.sitePermissions["example.net"]?[permission] == true)
            check("an open tab then needs a rebuild", asked.needsRebuildToNotify)
            asked.rebuildToNotify()
            await loaded(asked)
            let rebuilt = await until {
                asked.webView.configuration.preferences.inactiveSchedulingPolicy == .throttle
                    && !asked.needsRebuildToNotify && asked.webView.window != nil
            }
            check("Reload rebuilds it in place", rebuilt)
            check("on the same page", asked.url?.host() == "example.net")

            settings.sitePermissions["example.net"] = nil
            asked.reload()
            await loaded(asked)
            _ = await page(asked, askOnClick)
            await click(asked)
            _ = await until(3) { store.window?.attachedSheet != nil }
            _ = await page(asked, "void (location.href = 'https://example.edu/')")
            _ = await until { asked.url?.host() == "example.edu" }
            await loaded(asked)
            answerQuestion(allow: true)
            let answered = await until(3) {
                settings.sitePermissions["example.net"]?[permission] == true && settings.sitePermissions["example.edu"] == nil
            }
            check("the answer goes to the site that asked, not where it went", answered)

            store.select(allowed)
            await settle(1)
            _ = await page(allowed, "void document.addEventListener('click', () => { window.open('https://example.com/popup') })")
            await click(allowed)
            let opened = { store.activeSpace.allTabs.first(where: { $0.url?.path() == "/popup" }) }
            _ = await until { opened() != nil }
            if let popup = opened() {
                await loaded(popup)
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
            // A suspended page stops counting at once; a throttled one (what
            // an allowed tab gets) keeps going at about one tick in two
            // seconds. So: past the first stretch, is it still counting?
            say("waiting 20 s with both in the background")
            await settle(10)
            let before = Int(await page(allowed, "window.__ticks")) ?? 0
            await settle(10)
            let awake = (Int(await page(allowed, "window.__ticks")) ?? 0) - before
            let asleep = Int(await page(blocked, "window.__ticks")) ?? 0
            say("background ticks: allowed \(awake) in the last 10 s, other \(asleep) in 20 s")
            // Whether WebKit pauses the other one varies: only this is ours.
            check("an allowed tab keeps running in the background", awake >= 3)

            let shown = app.reveal(tabWithID: allowed.id)
            check("a click brings its tab forward", await until(3) { shown === allowed && store.selectedTab === allowed })
            check("a closed tab is reported gone", app.reveal(tabWithID: UUID()) == nil)

            let twin = store.openTab(URL(string: "https://example.com/second"), select: false)
            twin.activate()
            await loaded(twin)
            store.select(asked)
            await settle()
            await app.hibernateIdleTabs()
            check("a tab just left is never reloaded", allowed.isLoaded && twin.isLoaded)
            await app.hibernateIdleTabs(olderThan: 0.001)
            check("one tab per site stays, not all", await until(3) { [allowed, twin].filter(\.isLoaded).count == 1 && !blocked.isLoaded })
            await app.hibernateIdleTabs(olderThan: 0)
            check("a memory warning takes it too", await until(3) { !allowed.isLoaded && !twin.isLoaded })
            app.wakeTabsThatNotify()
            check("the sweep wakes one again", await until { [allowed, twin].filter(\.isLoaded).count == 1 })
            let awakeTab = allowed.isLoaded ? allowed : twin
            let sleepingTab = allowed.isLoaded ? twin : allowed

            store.select(blocked)
            await loaded(blocked)
            store.select(awakeTab)
            await settle()
            settings.sitePermissions["example.org"] = [permission: true]
            check("a site allowed later calls for a rebuild", blocked.needsRebuildToNotify)
            await app.hibernateIdleTabs()
            check("not while recently used", blocked.needsRebuildToNotify)
            await app.hibernateIdleTabs(olderThan: 0.001)
            let rebuiltIdle = await until {
                let policy = blocked.isLoaded ? blocked.webView.configuration.preferences.inactiveSchedulingPolicy : .suspend
                return policy == .throttle && !blocked.needsRebuildToNotify && blocked.url?.host() == "example.org"
            }
            check("once idle it's rebuilt, on the same page", rebuiltIdle)
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
            await loaded(kept)

            let hidden = app.openPrivateWindow()
            await settle()
            let inPrivate = hidden.openTab(URL(string: "https://example.com/"))
            await loaded(inPrivate)
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
            check("it waits on its tab, away from it", await until(3) { kept.unreadNotifications == 1 && NSApp.dockTile.badgeLabel == "1" })
            saveShot(of: store.window)
            store.select(kept)
            check("until you look", await until(3) { kept.unreadNotifications == 0 && NSApp.dockTile.badgeLabel == nil })
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
            await loaded(elsewhere)
            await app.hibernateIdleTabs(olderThan: 0)
            check("a hidden split can hibernate", await until(3) { !kept.isLoaded && !asked.isLoaded })
            store.select(kept)
            check("and comes back when shown", await until { kept.isLoaded && asked.isLoaded })
            store.closeSplit()
            store.close(elsewhere)
            await settle()
            store.select(asked)
            await settle()
            _ = await page(kept, "void new Notification('Then closed')")
            check("another one waits", await until(3) { kept.unreadNotifications == 1 })
            let spare = store.openTab(URL(string: "https://example.com/third"), select: false)
            store.close(kept)
            check("closing the tab clears the Dock", await until(3) { NSApp.dockTile.badgeLabel == nil })
            spare.activate()
            await loaded(spare)

            let macOS = await SiteNotifications.requestDelivery()
            say("macOS delivers: \(macOS.map(String.init(describing:)) ?? "won't for this build")")
            app.save()
            await settle()
            say("done")
            NSApp.terminate(nil)
        }
    }

    /// `notifywake`, after a `notifications` run: its allowed tab comes back loaded.
    static func qaNotifyWake(_ store: BrowserStore) {
        Task {
            try? await Task.sleep(for: .seconds(6))
            let tabs = store.app.spaces.flatMap(\.allTabs)
            let allowed = tabs.first { $0.url?.host() == "example.com" }
            let other = tabs.first { $0.url?.host() == "example.org" }
            let passed = allowed?.isLoaded == true && allowed !== store.selectedTab && other?.isLoaded == false
            log("QA notify \(passed ? "ok" : "FAILED"): allowed tab woke at launch, another stayed asleep")
            NSApp.terminate(nil)
        }
    }
}
#endif
