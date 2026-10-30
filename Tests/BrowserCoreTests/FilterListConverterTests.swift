import Foundation
import Testing
@testable import BrowserCore

@Suite struct FilterListConverterTests {
    private func convert(_ text: String) -> [ContentRule] {
        FilterListConverter.convert(text).rules
    }

    private let subresources = ["font", "image", "media", "raw", "script", "style-sheet", "svg-document"]

    @Test func domainAnchorBlocksSubresourcesAndFrames() {
        let rules = convert("||ads.example.com^")
        let filter = #"^[^:]+://+([^:/]+\.)?ads\.example\.com[/:?=&]"#
        #expect(rules == [
            ContentRule(trigger: .init(urlFilter: filter, resourceType: subresources), action: .init(type: .block)),
            ContentRule(trigger: .init(urlFilter: filter, resourceType: ["document"], loadContext: ["child-frame"]), action: .init(type: .block)),
        ])
    }

    @Test func typedThirdPartyFilter() {
        #expect(convert("||cdn.example.com/banner.js$script,third-party") == [
            ContentRule(
                trigger: .init(urlFilter: #"^[^:]+://+([^:/]+\.)?cdn\.example\.com/banner\.js"#, resourceType: ["script"], loadType: ["third-party"]),
                action: .init(type: .block)
            ),
        ])
    }

    @Test func subdocumentWithDomainOption() {
        #expect(convert("/adframe/*$subdocument,domain=a.com|b.com") == [
            ContentRule(
                trigger: .init(urlFilter: "/adframe/", ifDomain: ["*a.com", "*b.com"], resourceType: ["document"], loadContext: ["child-frame"]),
                action: .init(type: .block)
            ),
        ])
    }

    @Test func excludedTypesAreSubtracted() {
        let rule = convert("||tracker.net^$~image,~subdocument").first
        #expect(rule?.trigger.resourceType == ["font", "media", "raw", "script", "style-sheet", "svg-document"])
        #expect(convert("||tracker.net^$~image,~subdocument").count == 1)
    }

    @Test(arguments: [
        "||x.com^$domain=a.com|~b.a.com",
        "||x.com^$popup",
        "||x.com^$csp=script-src 'none'",
        "||x.com^$redirect=noopjs",
        "||x.com^$document",
        #"/banner\d+/"#,
        "||x.com/a|b",
        "/ad",
        "*$script",
    ])
    func unsupportedNetworkFiltersAreSkipped(line: String) {
        #expect(convert(line).isEmpty)
    }

    @Test func documentExceptionAllowlistsSiteAndComesLast() {
        let rules = convert("@@||example.com^$document\n||ads.net^$script")
        #expect(rules.first?.action.type == .block)
        #expect(rules.last == ContentRule(trigger: .init(urlFilter: ".*", ifDomain: ["*example.com"]), action: .init(type: .ignorePreviousRules)))
    }

    @Test func genericCosmeticRulesStayOnePerSelector() {
        #expect(convert("##.ad-banner\n##.sponsored\n##.ad-banner") == [
            ContentRule(trigger: .init(urlFilter: ".*"), action: .init(type: .cssDisplayNone, selector: ".ad-banner")),
            ContentRule(trigger: .init(urlFilter: ".*"), action: .init(type: .cssDisplayNone, selector: ".sponsored")),
        ])
    }

    @Test func scopedCosmeticRulesAreGroupedPerDomain() {
        let rules = convert("example.com##.a\nexample.com##.b\nother.org##.c")
        #expect(rules.map(\.action.selector) == [".a, .b", ".c"])
        #expect(rules.map(\.trigger.ifDomain) == [["*example.com"], ["*other.org"]])
    }

    @Test func cosmeticExceptionExcludesDomain() {
        #expect(convert("##.ad\nnews.com#@#.ad") == [
            ContentRule(trigger: .init(urlFilter: ".*", unlessDomain: ["*news.com"]), action: .init(type: .cssDisplayNone, selector: ".ad")),
        ])
    }

    @Test func cosmeticExceptionOnPartOfASiteDropsTheSiteRule() {
        #expect(convert("example.com##.banner\nshop.example.com#@#.banner").isEmpty)
        #expect(convert("example.com##.banner\nother.org#@#.banner").map(\.trigger.ifDomain) == [["*example.com"]])
    }

    @Test func cosmeticExceptionJoinsAnExclusionList() {
        #expect(convert("~a.com##.ad\nb.com#@#.ad") == [
            ContentRule(trigger: .init(urlFilter: ".*", unlessDomain: ["*a.com", "*b.com"]), action: .init(type: .cssDisplayNone, selector: ".ad")),
        ])
    }

    @Test(arguments: [
        "example.com#?#div:has-text(Sponsored)",
        "example.com##+js(set, a, 1)",
        "##div:-abp-has(.ad)",
        "##a::before",
        "example.com#$#body { overflow: auto }",
        "example.*##.ad",
        "~example.com,other.com##.ad",
    ])
    func unsupportedCosmeticFiltersAreSkipped(line: String) {
        #expect(convert(line).isEmpty)
    }

    @Test(arguments: [#"##a[href^="https://ads."]:not(.keep)"#, "##div:has(> .sponsored)", "##div:nth-child(2n+1)"])
    func supportedSelectorsAreKept(line: String) {
        #expect(convert(line).count == 1)
    }

    @Test func commentsAndHeadersAreIgnored() {
        let output = FilterListConverter.convert("[Adblock Plus 2.0]\n! Title: x\n\n")
        #expect(output.rules.isEmpty)
        #expect(output.skipped == 0)
    }

    @Test func maxRulesKeepsExceptions() {
        let output = FilterListConverter.convert("||a.com^$script\n||b.com^$script\n@@||c.com^$script", maxRules: 2)
        #expect(output.rules.map(\.action.type) == [.block, .ignorePreviousRules])
        #expect(output.skipped == 1)
    }

    @Test func encodedJSONUsesWebKitKeys() throws {
        let json = try convert("||ads.net^$script,match-case").encodedJSON()
        #expect(json.contains(#""url-filter":"^[^:]+://+([^:/]+\\.)?ads\\.net[/:?=&]""#))
        #expect(json.contains(#""resource-type":["script"]"#))
        #expect(json.contains(#""url-filter-is-case-sensitive":true"#))
        #expect(!json.contains("if-domain"))
    }
}

@Suite struct URLInputTests {
    @Test func domainsBecomeHTTPS() {
        #expect(URLInput.explicitURL("github.com/apple")?.absoluteString == "https://github.com/apple")
    }

    @Test func localhostAndIPsUseHTTP() {
        #expect(URLInput.explicitURL("localhost:3000")?.absoluteString == "http://localhost:3000")
        #expect(URLInput.explicitURL("192.168.1.1")?.absoluteString == "http://192.168.1.1")
    }

    @Test(arguments: ["hello world", "v1.2", "swift"])
    func phrasesAreNotURLs(text: String) {
        #expect(URLInput.explicitURL(text) == nil)
    }

    @Test func explicitSchemesPassThrough() {
        #expect(URLInput.explicitURL("http://example.com")?.scheme == "http")
    }


    @Test(arguments: [
        ("https://mail.google.com/x", "google.com"),
        ("https://google.com", "google.com"),
        ("http://192.168.1.1:8080/", "192.168.1.1"),
        ("http://localhost:3000", "localhost"),
    ])
    func siteKeyGroupsSubdomains(url: String, expected: String) {
        #expect(URL(string: url)?.siteKey == expected)
    }

    @Test func displayHostDropsWWW() {
        #expect(URL(string: "https://www.apple.com/mac")!.displayHost == "apple.com")
    }
}
