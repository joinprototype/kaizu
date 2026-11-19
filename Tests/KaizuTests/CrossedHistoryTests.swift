import AppKit
import Testing
import WebKit
@testable import Kaizu

/// Web pages and extension pages each need their own web view, so a tab
/// crossing between them keeps the one it left for Back and Forward.
/// (Plain pages stand in for both sides: the crossing is what's tested.)
@MainActor
struct CrossedHistoryTests {
    @Test func backAndForwardStepAcrossWebViews() async throws {
        _ = NSApplication.shared
        let tab = BrowserTab(profile: Profile(name: "Temporary", isPrivate: true), app: nil, url: nil)
        let pages = try ["one", "two", "settings"].map { try #require(URL(string: "data:text/html," + $0)) }
        for page in pages.prefix(2) {
            tab.webView.load(URLRequest(url: page))
            try await waitFor(page, in: tab)
        }
        let first = tab.webView

        tab.cross(to: pages[2])
        try await waitFor(pages[2], in: tab)
        #expect(tab.webView !== first)
        #expect(!tab.webView.canGoBack && tab.canGoBack && !tab.canGoForward)

        // Back into the old web view, its own history intact.
        tab.goBack()
        try await waitFor(pages[1], in: tab)
        #expect(tab.webView.backForwardList.backItem?.url == pages[0])
        #expect(tab.canGoBack && tab.canGoForward)
        tab.goBack()
        try await waitFor(pages[0], in: tab)
        tab.goForward()
        try await waitFor(pages[1], in: tab)

        // Forward out of it again.
        tab.goForward()
        try await waitFor(pages[2], in: tab)
        #expect(tab.canGoBack && !tab.canGoForward)
    }

    @Test func goingSomewhereNewDropsForward() async throws {
        _ = NSApplication.shared
        let tab = BrowserTab(profile: Profile(name: "Temporary", isPrivate: true), app: nil, url: nil)
        let pages = try ["one", "settings", "elsewhere"].map { try #require(URL(string: "data:text/html," + $0)) }
        tab.webView.load(URLRequest(url: pages[0]))
        try await waitFor(pages[0], in: tab)
        tab.cross(to: pages[1])
        try await waitFor(pages[1], in: tab)
        tab.goBack()
        try await waitFor(pages[0], in: tab)
        #expect(tab.canGoForward)

        tab.load(pages[2])
        try await waitFor(pages[2], in: tab)
        #expect(!tab.canGoForward && tab.crossedForward.isEmpty)
        #expect(tab.canGoBack)
    }

    @Test func keepsOnlyTheLatestCrossings() async throws {
        _ = NSApplication.shared
        let tab = BrowserTab(profile: Profile(name: "Temporary", isPrivate: true), app: nil, url: nil)
        let pages = try (0...BrowserTab.crossedLimit + 1).map { try #require(URL(string: "data:text/html,\($0)")) }
        tab.webView.load(URLRequest(url: pages[0]))
        try await waitFor(pages[0], in: tab)
        for page in pages.dropFirst() {
            tab.cross(to: page)
            try await waitFor(page, in: tab)
        }
        #expect(tab.crossedBack.count == BrowserTab.crossedLimit)
        #expect(tab.crossedBack.first?.url == pages[1])
    }

    private func waitFor(_ page: URL, in tab: BrowserTab) async throws {
        for _ in 0..<100 {
            if tab.webView.url == page, !tab.webView.isLoading { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("\(page) did not load")
    }
}
