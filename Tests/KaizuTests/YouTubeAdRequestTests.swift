import Testing
import WebKit
@testable import Kaizu

/// youtube-ads.js asks YouTube for in-page videos without an ad by adding
/// two fields to the player request's `params`. Run against the real script
/// in a YouTube-origin page (no network: the page is a local string).
@MainActor
struct YouTubeAdRequestTests {
    @Test func playerRequestsGetTheNoAdFields() async throws {
        let view = try await youTubePage()
        // /get_watch nests the player request, keeping YouTube's own fields.
        let nested = try await serialize(
            "{context: {client: {clientName: 'WEB'}}, playerRequest: {videoId: 'abc', params: 'ugUEEgJlbg%3D%3D', playbackContext: {}}}",
            in: view)
        #expect(nested == "ugUEEgJlbqABAaIGAS4%3D")
        // /player sends it at the top, sometimes without params.
        let bare = try await serialize("{context: {client: {clientName: 'WEB'}}, videoId: 'abc', playbackContext: {}}", in: view)
        #expect(bare == "oAEBogYBLg%3D%3D")
    }

    @Test func fieldsAreAddedOnce() async throws {
        let view = try await youTubePage()
        let twice = try await view.callAsyncJavaScript("""
            const body = {context: {client: {clientName: 'WEB'}}, videoId: 'abc', params: 'ugUEEgJlbg%3D%3D', playbackContext: {}};
            JSON.stringify(body);
            return JSON.parse(JSON.stringify(body)).params;
            """, contentWorld: .page) as? String
        #expect(twice == "ugUEEgJlbqABAaIGAS4%3D")
    }

    // The fallback to a plain request after an unplayable answer needs
    // sessionStorage, which a page loaded from a string doesn't get; it's
    // checked against YouTube itself instead.
    @Test func leavesEmbedsAlone() async throws {
        let view = try await youTubePage()
        let embed = try await serialize(
            "{context: {client: {clientName: 'WEB_EMBEDDED_PLAYER'}}, videoId: 'abc', params: 'ugUEEgJlbg%3D%3D', playbackContext: {}}",
            in: view)
        #expect(embed == "ugUEEgJlbg%3D%3D")
    }

    private func serialize(_ body: String, in view: WKWebView) async throws -> String? {
        let result = try await view.callAsyncJavaScript(
            "const body = \(body); return JSON.parse(JSON.stringify(body)).playerRequest?.params ?? JSON.parse(JSON.stringify(body)).params ?? null;",
            contentWorld: .page)
        return result as? String
    }

    private func youTubePage() async throws -> WKWebView {
        let script = try #require(ContentBlocker.youTubeScript)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(script)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), configuration: config)
        view.loadHTMLString("<!doctype html><title>t</title>", baseURL: URL(string: "https://www.youtube.com/watch?v=abc"))
        for _ in 0..<100 {
            let ready = "location.hostname === 'www.youtube.com' && document.readyState === 'complete'"
            if (try? await view.evaluateJavaScript(ready) as? Bool) == true { return view }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("YouTube fixture page did not load")
        return view
    }
}
