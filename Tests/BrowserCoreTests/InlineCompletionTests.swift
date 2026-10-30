import Foundation
import Testing
@testable import BrowserCore

@Suite struct InlineCompletionTests {
    let sites = [
        URL(string: "https://www.github.com/anthropics/claude")!,
        URL(string: "https://gitlab.com/")!,
    ]

    @Test func completesHostKeepingTypedCase() {
        #expect(InlineCompletion.complete("git", from: sites) == "github.com")
        #expect(InlineCompletion.complete("GitL", from: sites) == "GitLab.com")
        #expect(InlineCompletion.complete("www.gi", from: sites) == "www.github.com")
    }

    @Test func completesPathsAfterASlash() {
        #expect(InlineCompletion.complete("github.com/an", from: sites) == "github.com/anthropics/claude")
    }

    @Test func keepsAFullyTypedAddress() {
        let known = [URL(string: "https://google.com.au/")!, URL(string: "https://google.com/")!]
        #expect(InlineCompletion.complete("google.com", from: known) == nil)
        #expect(InlineCompletion.complete("github.com/", from: sites + [URL(string: "https://github.com/")!]) == nil)
    }

    @Test func leavesSearchesAndFullMatchesAlone() {
        #expect(InlineCompletion.complete("g", from: sites) == nil)
        #expect(InlineCompletion.complete("git hub", from: sites) == nil)
        #expect(InlineCompletion.complete("gitlab.com", from: sites) == nil)
        #expect(InlineCompletion.complete("https://git", from: sites) == nil)
        #expect(InlineCompletion.complete("bitbucket", from: sites) == nil)
    }
}
