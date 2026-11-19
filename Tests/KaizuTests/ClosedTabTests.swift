import AppKit
import Testing
import WebKit
@testable import Kaizu

@MainActor
struct ClosedTabTests {
    @Test func reopeningKeepsBothDirectionsOfWebKitHistory() async throws {
        _ = NSApplication.shared
        let profile = Profile(name: "Temporary", isPrivate: true)
        let tab = BrowserTab(profile: profile, app: nil, url: nil)
        let pages = try ["one", "two", "three"].map { try #require(URL(string: "data:text/html," + $0)) }
        for page in pages {
            tab.webView.load(URLRequest(url: page))
            try await waitForPage(page, in: tab.webView)
        }
        tab.webView.goBack()
        try await waitForPage(pages[1], in: tab.webView)
        tab.customTitle = "Reading"
        var stack: [ClosedTab] = []
        stack.remember(tab, in: UUID())
        tab.discard()

        let entry = stack.popLast()
        let closed = try #require(entry)
        let restored = BrowserTab(reopening: closed.record, profile: profile, app: nil, navigationState: closed.navigationState)
        #expect(!restored.isLoaded)
        restored.activate()
        try await waitForPage(pages[1], in: restored.webView)
        #expect(restored.customTitle == "Reading")
        #expect(restored.webView.backForwardList.backItem?.url == pages[0])
        #expect(restored.webView.backForwardList.forwardItem?.url == pages[2])
        restored.webView.goForward()
        try await waitForPage(pages[2], in: restored.webView)
        restored.webView.goBack()
        try await waitForPage(pages[1], in: restored.webView)
    }

    @Test func olderAndOversizedSnapshotsKeepTheirTabRecords() throws {
        let spaceID = UUID()
        let profile = Profile(name: "Temporary", isPrivate: true)
        var stack: [ClosedTab] = []
        for index in 0...ClosedTab.historyCount {
            let tab = BrowserTab(profile: profile, app: nil, url: nil, title: String(index))
            tab.savedState = Data([1])
            stack.remember(tab, in: spaceID)
        }
        #expect(stack.first?.record.title == "0")
        #expect(stack.first?.navigationState == nil)
        #expect(stack.dropFirst().allSatisfy { $0.navigationState == Data([1]) })
        let large = BrowserTab(profile: profile, app: nil, url: nil, title: "Large")
        large.savedState = Data(count: ClosedTab.maxStateBytes + 1)
        stack.remember(large, in: spaceID)
        let closed = try #require(stack.last)
        #expect(closed.navigationState == nil)
        #expect(closed.record.title == "Large")
        #expect(closed.profileID == profile.id && closed.spaceID == spaceID)
    }

    private func waitForPage(_ page: URL, in view: WKWebView) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while (view.url != page || view.isLoading) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(view.url == page && !view.isLoading)
        let body = try await view.evaluateJavaScript("document.body.textContent") as? String
        try #require(body == page.absoluteString.components(separatedBy: ",").last)
    }
}
