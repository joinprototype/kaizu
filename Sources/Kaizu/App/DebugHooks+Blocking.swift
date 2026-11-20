#if DEBUG
import AppKit
import BrowserCore
import Storage
import WebEngine
import WebKit

extension DebugHooks {
    /// Meant for an empty rule list store, so the helper has to build them all.
    static func qaRuleLists(_ store: BrowserStore) {
        var passed = 0, failed = 0
        func check(_ label: String, _ condition: Bool) {
            if condition { passed += 1 } else { failed += 1 }
            log("QA rulelists \(condition ? "ok" : "FAILED"): \(label)")
        }
        Task {
            let started = ContinuousClock.now
            let blocker = store.contentBlocker
            while blocker.state != .ready, started.duration(to: .now) < .seconds(120) {
                try? await Task.sleep(for: .milliseconds(200))
            }
            log("QA rulelists ready after \(started.duration(to: .now))")
            check("blocking is ready", blocker.state == .ready)
            let stored = await WKContentRuleListStore.default()?.availableIdentifiers() ?? []
            for name in ContentBlocker.listNames {
                check("\(name) is in the store", stored.filter { $0.hasPrefix("\(name)-") }.count == 1)
            }

            let site = URL(string: "https://example.com/")!
            let tab = store.openTab(site)
            store.select(tab)
            await qaLoaded(tab)
            let hidden = await qaAdDisplay(in: tab)
            check("a generic ad rule hides an element (\(hidden))", hidden == "none")

            blocker.togglePause(on: site, privateID: tab.profile.privateID)
            tab.webView.reload()
            try? await Task.sleep(for: .seconds(1))
            await qaLoaded(tab)
            let shown = await qaAdDisplay(in: tab)
            check("and doesn't with blocking paused (\(shown))", shown == "block")
            blocker.togglePause(on: site, privateID: tab.profile.privateID)

            log("QA rulelists done: \(passed) ok, \(failed) failed")
            NSApp.terminate(nil)
        }
    }

    /// Meant for bundled lists older than what's online, with today's check
    /// already recorded, so the refresh here is the one that changes them.
    static func qaListRefresh(_ store: BrowserStore) {
        var passed = 0, failed = 0
        func check(_ label: String, _ condition: Bool) {
            if condition { passed += 1 } else { failed += 1 }
            log("QA listrefresh \(condition ? "ok" : "FAILED"): \(label)")
        }
        func stored() async -> Set<String> {
            Set(await WKContentRuleListStore.default()?.availableIdentifiers() ?? [])
        }
        let lastCheckKey = "filterListsLastChecked"
        Task {
            let blocker = store.contentBlocker
            for _ in 0..<600 where blocker.state != .ready {
                try? await Task.sleep(for: .milliseconds(200))
            }
            let before = await stored()
            let site = URL(string: "https://example.com/")!
            let open = store.openTab(site)
            store.select(open)
            await qaLoaded(open)
            check("blocking works before the refresh", await qaAdDisplay(in: open) == "none")

            await blocker.refreshLists()
            check("nothing changes while the check isn't due", await stored() == before)

            AppDefaults.shared.set(0.0, forKey: lastCheckKey)
            let started = ContinuousClock.now
            await blocker.refreshLists()
            let after = await stored()
            log("QA listrefresh refreshed in \(started.duration(to: .now))")
            check("the check is recorded", AppDefaults.shared.double(forKey: lastCheckKey) > 0)
            check("lists changed", after != before)
            check("a list that didn't change kept its copy", after.contains { $0.hasPrefix("kaizu-") && before.contains($0) })
            for name in ContentBlocker.listNames {
                check("one copy of \(name) in the store", after.filter { $0.hasPrefix("\(name)-") }.count == 1)
            }

            check("the open tab is still there", open.isLoaded && open.webView.url != nil)
            open.webView.reload()
            try? await Task.sleep(for: .seconds(1))
            await qaLoaded(open)
            check("reloading it blocks with the new lists", await qaAdDisplay(in: open) == "none")
            let new = store.openTab(site)
            store.select(new)
            await qaLoaded(new)
            check("so does a new tab", await qaAdDisplay(in: new) == "none")

            blocker.togglePause(on: site, privateID: new.profile.privateID)
            new.webView.reload()
            try? await Task.sleep(for: .seconds(1))
            await qaLoaded(new)
            check("pausing still works", await qaAdDisplay(in: new) == "block")
            blocker.togglePause(on: site, privateID: new.profile.privateID)

            log("QA listrefresh done: \(passed) ok, \(failed) failed")
            NSApp.terminate(nil)
        }
    }

    private static func qaLoaded(_ tab: BrowserTab) async {
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(100))
            if tab.isLoaded, !tab.isLoading, tab.webView.url != nil { break }
        }
    }

    /// The computed display of an element EasyList hides everywhere.
    private static func qaAdDisplay(in tab: BrowserTab) async -> String {
        let script = "const qaAd = document.body.appendChild(document.createElement('div')); qaAd.className = 'ADBox'; qaAd.textContent = 'ad'; getComputedStyle(qaAd).display"
        return (try? await tab.webView.evaluateJavaScript("{" + script + "}")) as? String ?? "no answer"
    }
}
#endif
