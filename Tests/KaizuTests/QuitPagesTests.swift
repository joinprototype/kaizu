import AppKit
import Testing
import WebKit
@testable import Kaizu

@MainActor
struct QuitPagesTests {
    @Test func deferredReplyRunsWhileAppKitWaitsInItsModalLoop() {
        let pages = QuitPages()
        var replies = 0
        pages.start([]) { replies += 1 }

        // Simulate terminateLater called from an action already executing on the main actor.
        let deadline = Date(timeIntervalSinceNow: 3)
        let wake = Timer(fire: deadline, interval: 0, repeats: false) { _ in }
        RunLoop.main.add(wake, forMode: .modalPanel)
        defer { wake.invalidate() }
        while replies == 0 && Date() < deadline {
            _ = RunLoop.main.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.05))
        }
        #expect(replies == 1)
    }

    @Test func cookiesAreOnDiskBeforeTheQuitReply() async throws {
        _ = NSApplication.shared
        let id = UUID()
        let store = WKWebsiteDataStore(forIdentifier: id)
        let token = UUID().uuidString
        let cookie = try #require(HTTPCookie(properties: [
            .domain: "quit.kaizu.test", .path: "/", .name: "login", .value: token,
            .expires: Date(timeIntervalSinceNow: 86_400),
        ]))
        await store.httpCookieStore.setCookie(cookie)
        let setAt = Date()

        let pages = QuitPages()
        var replies = 0
        pages.start([], cookieStores: [store]) { replies += 1 }
        runModalLoop { replies > 0 }
        #expect(replies == 1)
        // WebKit's own save timer runs about two seconds after a change.
        #expect(Date().timeIntervalSince(setAt) < 1.5)

        let webKit = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/WebKit")
        let files = try FileManager.default.contentsOfDirectory(at: webKit, includingPropertiesForKeys: nil).map {
            $0.appending(path: "WebsiteDataStore/\(id.uuidString.lowercased())/Cookies/Cookies.binarycookies")
        }
        let saved = files.compactMap { try? Data(contentsOf: $0) }
        #expect(saved.contains { $0.range(of: Data(token.utf8)) != nil })
        // The network process may still hold the store; the test helper's data folder is disposable.
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    /// Runs AppKit's modal panel mode, as terminateLater does, until `done` or three seconds.
    private func runModalLoop(until done: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 3)
        let wake = Timer(fire: deadline, interval: 0, repeats: false) { _ in }
        RunLoop.main.add(wake, forMode: .modalPanel)
        defer { wake.invalidate() }
        while !done() && Date() < deadline {
            _ = RunLoop.main.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.01))
        }
    }
}
