@testable import Kaizu
import Testing
@testable import WebEngine
import WebKit

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

    // A page opened directly with an ad booked: the player loads the same
    // video again (through a request that asks without an ad), at the
    // link's start time.
    @Test func directlyOpenedBookedVideosLoadAgain() async throws {
        let view = try await youTubePage(at: "/watch?v=abc&t=1m5s", body: Self.player(booked: true))
        #expect(try await loaded(in: view) == "abc@65")
        // The ad data is gone from what YouTube's code reads.
        let left = try await view.evaluateJavaScript("'adPlacements' in window.ytInitialPlayerResponse") as? Bool
        #expect(left == false)
    }

    @Test func unbookedVideosAndOtherPagesStayAsTheyAre() async throws {
        let plain = try await youTubePage(at: "/watch?v=abc", body: Self.player(booked: false))
        #expect(try await loaded(in: plain) == nil)
        let embed = try await youTubePage(at: "/embed/abc", body: Self.player(booked: true))
        #expect(try await loaded(in: embed) == nil)
    }

    /// A stand-in player that notes what it's asked to load, then the page's
    /// player data, as YouTube embeds it.
    private static func player(booked: Bool) -> String {
        let ads = booked ? "adPlacements: [{}], " : ""
        return """
            <div id=movie_player></div>
            <script>
            document.getElementById('movie_player').loadVideoById = (video) => {
              window.loadedVideo = video.videoId + '@' + video.startSeconds;
            };
            window.ytInitialPlayerResponse = {\(ads)videoDetails: {videoId: 'abc'}};
            </script>
            """
    }

    private func loaded(in view: WKWebView) async throws -> String? {
        try await Task.sleep(for: .milliseconds(300))
        return try await view.evaluateJavaScript("window.loadedVideo ?? null") as? String
    }

    private func youTubePage(at path: String = "/watch?v=abc", body: String = "") async throws -> WKWebView {
        let script = try #require(ContentBlocker.youTubeScript)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(script)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), configuration: config)
        view.loadHTMLString("<!doctype html><title>t</title><body>\(body)</body>", baseURL: URL(string: "https://www.youtube.com" + path))
        for _ in 0..<100 {
            let ready = "location.hostname === 'www.youtube.com' && document.readyState === 'complete'"
            if (try? await view.evaluateJavaScript(ready) as? Bool) == true { return view }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("YouTube fixture page did not load")
        return view
    }
}
