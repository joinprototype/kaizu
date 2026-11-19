import AppKit
import Testing
import WebKit
@testable import Kaizu

@MainActor
final class PageWatchTests {
    private let page = URL(string: "https://shop.example.com/kettle")!
    private let profile = UUID()
    private let suite = "dev.kaizu.tests.watches." + UUID().uuidString

    deinit { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    private func watches() -> (PageWatches, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        return (PageWatches(defaults: defaults), defaults)
    }

    @Test func textIsComparedWithoutLayoutWhitespace() {
        #expect(PageWatches.normalized("  $49.99\n\n  In stock\t") == "$49.99 In stock")
        #expect(PageWatches.normalized(String(repeating: "a", count: 1000)).count == PageWatches.maximumText)
    }

    @Test func aChangeIsRecordedOnceAndKept() throws {
        let (watches, defaults) = watches()
        let part = try #require(watches.add(url: page, selector: "#price", text: "$49.99", title: "Kettle", profileID: profile))
        #expect(watches.record(part.id, found: " $49.99 ") == nil)
        let changed = try #require(watches.record(part.id, found: "$39.99"))
        #expect(changed.text == "$39.99" && changed.previous == "$49.99" && changed.isUnseen)
        #expect(watches.record(part.id, found: "$39.99") == nil)
        #expect(watches.unseenCount == 1)

        // Kept across launches.
        let reopened = PageWatches(defaults: defaults)
        #expect(reopened.parts == watches.parts)

        watches.markSeen(page)
        #expect(watches.unseenCount == 0)
    }

    @Test func missesDontCountAsChanges() throws {
        let (watches, _) = watches()
        let part = try #require(watches.add(url: page, selector: "#price", text: "$49.99", title: "", profileID: profile))
        for _ in 0..<WatchedPart.missesToGiveUp {
            #expect(watches.record(part.id, found: nil) == nil)
            #expect(watches.record(part.id, found: "   ") == nil)
        }
        #expect(watches.parts[0].isLost && watches.parts[0].text == "$49.99")
        #expect(watches.record(part.id, found: "$49.99") == nil)
        #expect(!watches.parts[0].isLost)
    }

    @Test func pickingTheSamePartAgainDoesntAddIt() {
        let (watches, _) = watches()
        watches.add(url: page, selector: "#price", text: "$49.99", title: "", profileID: profile)
        watches.add(url: page, selector: "#price", text: "$45.00", title: "", profileID: profile)
        #expect(watches.parts.count == 1 && watches.parts[0].text == "$45.00")
        #expect(watches.add(url: page, selector: "#empty", text: " \n ", title: "", profileID: profile) == nil)
    }

    @Test func dueOldestFirst() throws {
        let (watches, _) = watches()
        let now = Date()
        let first = try #require(watches.add(url: page, selector: "#a", text: "a", title: "", profileID: profile))
        let second = try #require(watches.add(url: page, selector: "#b", text: "b", title: "", profileID: profile))
        watches.record(second.id, found: "b", at: now.addingTimeInterval(-7200))
        watches.record(first.id, found: "a", at: now.addingTimeInterval(-3700))
        #expect(watches.due(every: 3600, now: now).map(\.id) == [second.id, first.id])
        watches.record(first.id, found: "a", at: now)
        #expect(watches.due(every: 3600, now: now).map(\.id) == [second.id])
    }

    /// Pages that draw with scripts: the part is waited for.
    @Test func readsAPartDrawnLate() async throws {
        _ = NSApplication.shared
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.loadHTMLString("""
            <body><main></main><script>
            setTimeout(() => { document.querySelector('main').innerHTML = '<span id=price>\\n  $39.99 </span>'; }, 700);
            </script>
            """, baseURL: URL(string: "https://shop.example.com/"))
        let text = await PageWatcher.text(of: "#price", in: view, patience: .seconds(5))
        #expect(text.map(PageWatches.normalized) == "$39.99")
        #expect(await PageWatcher.text(of: "#gone", in: view, patience: .milliseconds(600)) == nil)
        #expect(await PageWatcher.text(of: "not a [selector", in: view, patience: .milliseconds(600)) == nil)
    }
}
