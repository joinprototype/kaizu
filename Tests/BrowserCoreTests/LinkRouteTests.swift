import Foundation
import Testing
@testable import BrowserCore

@Suite struct LinkRouteTests {
    let work = UUID()

    private func route(_ pattern: String) -> LinkRoute {
        LinkRoute(pattern: pattern, spaceID: work)
    }

    @Test(arguments: [
        ("github.com", "https://github.com/apple/swift", true),
        ("github.com", "https://gist.github.com/x", true),
        ("www.github.com", "https://github.com/", true),
        ("https://github.com", "https://github.com/", true),
        ("github.com", "https://notgithub.com/", false),
        ("github.com/myorg", "https://github.com/myorg/repo", true),
        ("github.com/myorg/", "https://github.com/MyOrg", true),
        ("github.com/myorg", "https://github.com/myorganization", false),
        ("", "https://github.com/", false),
    ])
    func matching(pattern: String, url: String, expected: Bool) {
        #expect(route(pattern).matches(URL(string: url)!) == expected)
    }

    @Test func firstMatchingRuleWins() {
        let specific = route("github.com/myorg")
        let general = LinkRoute(pattern: "github.com", spaceID: UUID())
        #expect([specific, general].first(matching: URL(string: "https://github.com/myorg/x")!) == specific)
        #expect([specific, general].first(matching: URL(string: "https://github.com/other")!) == general)
    }
}

@Suite struct SearchEngineTests {
    @Test func queryIsFullyEncoded() {
        #expect(SearchEngine.google.searchURL(for: "tom & jerry = 1+1")?.absoluteString == "https://www.google.com/search?q=tom%20%26%20jerry%20%3D%201%2B1")
        #expect(SearchEngine.duckDuckGo.searchURL(for: "a b")?.absoluteString == "https://duckduckgo.com/?q=a%20b")
    }

    @Test func suggestions() {
        #expect(SearchEngine.duckDuckGo.suggestionsURL(for: "a&b")?.absoluteString == "https://duckduckgo.com/ac/?type=list&q=a%26b")
        #expect(SearchEngine.startpage.suggestionsURL(for: "a") == nil)
        let response = Data(#"["kaizu",["kaizu browser","kaizu city"],[],{"google:suggestsubtypes":[[512]]}]"#.utf8)
        #expect(SearchEngine.suggestions(from: response) == ["kaizu browser", "kaizu city"])
        #expect(SearchEngine.suggestions(from: Data("<html>".utf8)).isEmpty)
    }
}
