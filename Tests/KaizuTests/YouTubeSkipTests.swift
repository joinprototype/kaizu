import Testing
import WebKit
@testable import Kaizu

@MainActor
struct YouTubeSkipTests {
    @Test func clicksOnlyForYouTubeItself() {
        #expect(YouTubeSkip.isYouTube("youtube.com"))
        #expect(YouTubeSkip.isYouTube("www.youtube.com"))
        #expect(YouTubeSkip.isYouTube("m.youtube.com"))
        #expect(!YouTubeSkip.isYouTube("youtube.com.example.test"))
        #expect(!YouTubeSkip.isYouTube("notyoutube.com"))
        #expect(!YouTubeSkip.isYouTube("www.youtube-nocookie.com"))
    }

    @Test func theFinderScriptRunsInTheMainFrameOnly() throws {
        let script = try #require(YouTubeSkip.script)
        #expect(script.isForMainFrameOnly)
        #expect(script.source.contains(YouTubeSkip.handlerName))
    }
}
