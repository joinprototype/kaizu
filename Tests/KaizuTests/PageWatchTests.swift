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
        // As the watcher sets it up: out of a window, scripts keep running.
        let configuration = WKWebViewConfiguration()
        configuration.preferences.inactiveSchedulingPolicy = .none
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        view.loadHTMLString("""
            <body><main></main><script>
            setTimeout(() => { document.querySelector('main').innerHTML = '<span id=price>\\n  $39.99 </span>'; }, 700);
            </script>
            """, baseURL: URL(string: "https://shop.example.com/"))
        let text = await PageWatcher.text(of: "#price", in: view, patience: .seconds(10))
        #expect(text.map(PageWatches.normalized) == "$39.99")
        #expect(await PageWatcher.text(of: "#gone", in: view, patience: .milliseconds(600)) == nil)
        #expect(await PageWatcher.text(of: "not a [selector", in: view, patience: .milliseconds(600)) == nil)
    }

    /// Nobody sees the page being checked: dialogs, windows and app links
    /// get nowhere, and the part is still read.
    @Test func checkedPagesGetNoDialogsOrWindows() async throws {
        _ = NSApplication.shared
        let html = """
            <body><b id=price>$12</b><script>
            alert("hi"); confirm("sure?"); prompt("name?");
            window.open("https://example.com/");
            location.href = "zoommtg://join";
            </script>
            """
        let url = try #require(URL(string: "data:text/html," + html.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!))
        let part = WatchedPart(id: UUID(), url: url, selector: "#price", title: "", profileID: UUID(), text: "$10")
        let watcher = PageWatcher(app: nil)
        let started = ContinuousClock.now
        let text = await watcher.read(part, profile: Profile(name: "Temporary", isPrivate: true))
        #expect(text == "$12")
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    /// Pages often change their query as they load (locale, session):
    /// opening one still counts as seeing its change.
    @Test func seenGoesByPageNotQuery() throws {
        let (watches, _) = watches()
        var told = 0
        watches.onUnseenChange = { told += 1 }
        let part = try #require(watches.add(url: URL(string: "https://www.shop.example.com/kettle?ref=home")!, selector: "#p", text: "1", title: "", profileID: profile))
        watches.record(part.id, found: "2")
        #expect(told == 1)
        watches.markSeen(URL(string: "https://shop.example.com/kettle/?lang=fr#top"))
        #expect(watches.unseenCount == 0 && told == 2)
        watches.record(part.id, found: "3")
        watches.markSeen(URL(string: "https://shop.example.com/teapot"))
        #expect(watches.unseenCount == 1)
        // Stopping a changed part takes it off the Dock's count too.
        watches.remove(part.id)
        #expect(watches.unseenCount == 0 && told == 4)
    }

    @Test func deletedProfilesTakeTheirParts() {
        let (watches, _) = watches()
        let other = UUID()
        watches.add(url: page, selector: "#a", text: "a", title: "", profileID: profile)
        watches.add(url: page, selector: "#a", text: "a", title: "", profileID: other)
        watches.removeAll(profile: profile)
        #expect(watches.parts.map(\.profileID) == [other])
    }

    /// A page still loading something when time's up is read anyway.
    @Test func aPageThatNeverFinishesIsStillRead() async throws {
        _ = NSApplication.shared
        // The image never answers, so the page's load never finishes.
        let html = "<body><b id=price>$12</b><img src='https://10.255.255.1/never.png'>"
        let url = try #require(URL(string: "data:text/html," + html.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!))
        let part = WatchedPart(id: UUID(), url: url, selector: "#price", title: "", profileID: UUID(), text: "$10")
        let watcher = PageWatcher(app: nil, loadTimeout: .seconds(2))
        let text = await watcher.read(part, profile: Profile(name: "Temporary", isPrivate: true))
        #expect(text == "$12")
    }
}
