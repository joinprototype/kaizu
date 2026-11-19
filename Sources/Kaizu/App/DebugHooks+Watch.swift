#if DEBUG
import AppKit
import SwiftUI
import WebKit

extension DebugHooks {
    /// KAIZU_DEBUG=watch (needs KAIZU_SUPPORT): picks example.com's first paragraph
    /// with the real picker, then fakes an older text and checks the page
    /// out of sight, which should find the change. KAIZU_SHOT gets the
    /// window with the change's toast.
    static func qaWatch(_ store: BrowserStore) {
        precondition(ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] != nil)
        runCheck("watch") {
            struct Failure: Error, CustomStringConvertible { let description: String }
            @MainActor func expect(_ ok: Bool, _ what: String) throws {
                log("QA watch \(ok ? "ok" : "FAILED"): \(what)")
                if !ok { throw Failure(description: what) }
            }
            let watches = store.app.watches
            for part in watches.parts { watches.remove(part.id) }
            var changes: [WatchedPart] = []
            PageWatcher.onChange = { changes.append($0) }

            let tab = store.openTab(URL(string: "https://example.com/"))
            for _ in 0..<100 where tab.isLoading || tab.url?.host() != "example.com" || tab.title.isEmpty {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(1))
            let expected = PageWatches.normalized(try await tab.webView.evaluateJavaScript("document.querySelector('p').innerText") as? String ?? "")
            store.beginHidingItems(on: tab, for: .watch)
            try expect(store.hidingItemsTabID == tab.id && store.pickingPurpose == .watch, "picker open for watching")
            try await Task.sleep(for: .milliseconds(500))
            _ = try await tab.webView.callAsyncJavaScript("""
                window.__kaizuQA = true;
                const r = document.querySelector("p").getBoundingClientRect();
                const [x, y] = [r.left + 10, r.top + r.height / 2];
                const shield = document.elementFromPoint(x, y);
                for (const type of ["mousemove", "click"]) {
                    shield.dispatchEvent(new MouseEvent(type, { clientX: x, clientY: y, bubbles: true, cancelable: true }));
                }
                return 0;
                """, in: nil, contentWorld: HiddenItems.world)
            try await Task.sleep(for: .seconds(1.5))
            let part = watches.parts.first
            try expect(part?.text == expected && !expected.isEmpty, "picked the paragraph (\(part?.selector ?? "nothing"): \(part?.text ?? ""))")
            try expect(store.hidingItemsTabID == nil, "picker closed after the pick")
            let heading = try await tab.webView.evaluateJavaScript("getComputedStyle(document.querySelector('p')).display") as? String
            try expect(heading != "none", "paragraph still on the page")
            guard let part else { return }

            // Nothing changed yet: a check finds the same text.
            await store.app.watcher.check([part])
            try expect(changes.isEmpty && watches.parts.first?.checkedAt != nil, "unchanged page, no change")

            // As if the page said something else at the last check.
            watches.remove(part.id)
            guard let older = watches.add(url: part.url, selector: part.selector, text: "Older text",
                                          title: part.title, profileID: part.profileID)
            else { throw Failure(description: "couldn't add") }
            await store.app.watcher.check([older])
            try expect(changes.map(\.text) == [expected], "change found out of sight")
            try expect(watches.unseenCount == 1 && NSApp.dockTile.badgeLabel == "1", "Dock count \(NSApp.dockTile.badgeLabel ?? "none")")
            try await Task.sleep(for: .seconds(1))
            saveShot(of: store.window)

            // Opening the page marks it seen.
            tab.reload()
            for _ in 0..<100 where watches.unseenCount > 0 { try await Task.sleep(for: .milliseconds(100)) }
            try expect(watches.unseenCount == 0 && NSApp.dockTile.badgeLabel == nil, "seen after opening the page")

            // A selector that no longer matches counts as a miss, not a change.
            watches.remove(older.id)
            guard let lost = watches.add(url: part.url, selector: "#gone", text: "x", title: "", profileID: part.profileID)
            else { throw Failure(description: "couldn't add") }
            await store.app.watcher.check([lost])
            try expect(watches.parts.first?.misses == 1 && changes.count == 1, "missing part is a miss")

            // The settings list, with a changed part and a missing one (KAIZU_SHOT2).
            if let path = ProcessInfo.processInfo.environment["KAIZU_SHOT2"],
               let changed = watches.add(url: part.url, selector: part.selector, text: "Older text", title: part.title, profileID: part.profileID) {
                watches.record(changed.id, found: expected)
                for _ in 1..<WatchedPart.missesToGiveUp { watches.record(lost.id, found: nil) }
                let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 560, height: 460), styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = NSHostingView(rootView: WatchingSettings().environment(store))
                window.orderFront(nil)
                try await Task.sleep(for: .seconds(1))
                saveShot(of: window, to: path)
                window.orderOut(nil)
                watches.remove(changed.id)
            }
            watches.remove(lost.id)
        }
    }
}
#endif
