#if DEBUG
import AppKit
import WebKit

extension DebugHooks {
    /// KAIZU_DEBUG=crossing KAIZU_EXTENSION=/path/to/unpacked-extension (one
    /// with an options page linking to https://example.org/): Back and
    /// Forward between a web page and the extension's page, both ways.
    static func qaCrossing(_ store: BrowserStore) {
        runCheck("crossing") {
            struct Failure: Error, CustomStringConvertible { let description: String }
            func expect(_ ok: Bool, _ what: String) throws {
                log("QA crossing \(ok ? "ok" : "FAILED"): \(what)")
                if !ok { throw Failure(description: what) }
            }
            @MainActor func wait(_ what: String, _ condition: () -> Bool) async throws {
                for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
                try expect(condition(), what)
            }
            guard let path = ProcessInfo.processInfo.environment["KAIZU_EXTENSION"] else {
                throw Failure(description: "KAIZU_EXTENSION not set")
            }
            await store.extensions.install(from: URL(fileURLWithPath: path), askFirst: false)
            try await wait("extension loaded") { store.extensions.controller.extensionContexts.first?.optionsPageURL != nil }
            let options = store.extensions.controller.extensionContexts.first!.optionsPageURL!
            let web = URL(string: "https://example.com/")!
            let tab = store.openTab(web)
            @MainActor func at(_ url: URL) -> Bool {
                guard let current = tab.url, !tab.isLoading else { return false }
                return current.host() == url.host() && current.scheme == url.scheme
            }

            try await wait("web page open") { at(web) }
            tab.load(options)
            try await wait("crossed to the extension page") { at(options) }
            try expect(tab.canGoBack && !tab.canGoForward, "Back on, Forward off")
            tab.goBack()
            try await wait("Back to the web page") { at(web) }
            try expect(tab.canGoForward, "Forward on")
            tab.goForward()
            try await wait("Forward to the extension page") { at(options) }
            let title = try await tab.webView.evaluateJavaScript("document.title") as? String
            try expect(title == "Crossing options", "extension page drawn (\(title ?? "nil"))")

            // A link on the extension page out to the web, and Back again.
            let other = URL(string: "https://example.org/")!
            _ = try await tab.webView.evaluateJavaScript("document.getElementById('out').click(); 0")
            try await wait("link out to the web") { at(other) }
            tab.goBack()
            try await wait("Back to the extension page") { at(options) }
            tab.goBack()
            try await wait("Back to the first web page") { at(web) }
            try expect(!tab.canGoBack && tab.canGoForward, "Back off at the start, Forward on")
            saveShot(of: store.window)
        }
    }
}
#endif
