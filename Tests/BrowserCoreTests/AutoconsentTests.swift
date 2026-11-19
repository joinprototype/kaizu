import Foundation
import Testing
@testable import BrowserCore

@Suite struct AutoconsentTests {
    static let scripts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../Resources/Scripts")
        .standardizedFileURL
    static let bundledRules = try! Autoconsent.Rules(data: Data(contentsOf: scripts.appendingPathComponent("autoconsent-rules.json")))
    static let bundledSnippets = try! Autoconsent.Snippets(data: Data(contentsOf: scripts.appendingPathComponent("autoconsent-snippets.json")))

    // MARK: Rule filtering

    /// Five rules: two generic, one that also runs in frames, two site-specific
    /// (one of them for frames only).
    static let sample = """
        {"v":1,"s":["#generic","#both","#frame-only","#site","#unused","#late"],
         "r":[
          [1,"generic",0,"",22,[0],[{"e":0}],[{"v":0}],[{"k":0}],[],{}],
          [1,"both",0,"",2,[],[{"e":1}],[],[{"if":{"e":1},"then":[{"k":1}]}],[],{}],
          [1,"frame-only",0,"^https://cmp\\\\.example/",1,[],[{"e":2}],[],[],[],{}],
          [1,"site",0,"^https://(www\\\\.)?shop\\\\.test/",22,[],[{"any":[{"e":3}]}],[],[{"cc":5}],[],{"intermediate":true}]
         ],
         "index":{"genericRuleRange":[0,2],"frameRuleRange":[1,3],"specificRuleRange":[2,4],"genericStringEnd":2,"frameStringEnd":3}}
        """

    static func decoded(_ selection: Autoconsent.Rules.Selection) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(selection.json.utf8)) as? [String: Any])
    }

    @Test func aMainFrameWithoutASiteRuleGetsTheGenericRulesAndTheirStrings() throws {
        let rules = try Autoconsent.Rules(data: Data(Self.sample.utf8))
        let selection = rules.select(url: "https://elsewhere.test/", mainFrame: true)
        #expect(selection.ruleNames == ["generic", "both"])
        let json = try Self.decoded(selection)
        #expect(json["s"] as? [String] == ["#generic", "#both"])
        #expect((json["r"] as? [Any])?.count == 2)
        #expect(json["v"] as? Int == 1)
    }

    @Test func aMatchingSiteRuleBringsItsStringsAndBlanksTheUnusedOnes() throws {
        let rules = try Autoconsent.Rules(data: Data(Self.sample.utf8))
        let selection = rules.select(url: "https://www.shop.test/cart", mainFrame: true)
        #expect(selection.ruleNames == ["generic", "both", "site"])
        let json = try Self.decoded(selection)
        #expect(json["s"] as? [String] == ["#generic", "#both", "", "#site", "", "#late"])
        let site = try #require((json["r"] as? [[Any]])?.last)
        #expect((site[10] as? [String: Bool])?["intermediate"] == true)
    }

    @Test func aSubframeGetsOnlyFrameRulesMatchingItsAddress() throws {
        let rules = try Autoconsent.Rules(data: Data(Self.sample.utf8))
        #expect(rules.select(url: "https://cmp.example/notice", mainFrame: false).ruleNames == ["both", "frame-only"])
        let other = rules.select(url: "https://ads.test/frame", mainFrame: false)
        #expect(other.ruleNames == ["both"])
        // Cut after the last string a chosen rule uses.
        #expect(try Self.decoded(other)["s"] as? [String] == ["", "#both"])
        // A rule for main frames only never reaches a frame, nor a frame-only rule a main frame.
        #expect(!rules.select(url: "https://cmp.example/", mainFrame: true).ruleNames.contains("frame-only"))
    }

    @Test func malformedRulesAreRefused() {
        #expect(throws: (any Error).self) { try Autoconsent.Rules(data: Data(#"{"v":1}"#.utf8)) }
        let outOfRange = Self.sample.replacingOccurrences(of: #""genericRuleRange":[0,2]"#, with: #""genericRuleRange":[0,9]"#)
        #expect(throws: (any Error).self) { try Autoconsent.Rules(data: Data(outOfRange.utf8)) }
    }

    @Test func theBundledRulesAllLoad() {
        let rules = Self.bundledRules
        #expect(rules.unreadablePatterns.isEmpty)
        #expect(rules.rules.count > 1_000)
        #expect(rules.genericRules.count > 300)
    }

    /// The Swift port must pick what autoconsent's own `filterCompactRules`
    /// picks. The fixture comes from running it on the sites in autoconsent's
    /// test suite (scripts/autoconsent/parity.cjs).
    @Test func theBundledRulesFilterLikeAutoconsentItself() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/autoconsent-filter-parity.json")
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try #require(fixture["cases"] as? [[String: Any]])
        let generic = try #require(fixture["generic"] as? Int)
        #expect(fixture["version"] as? Int == Self.bundledRules.version, "regenerate the fixture with scripts/vendor-autoconsent.sh")
        #expect(cases.count > 500)
        var specificMatches = 0
        for test in cases {
            let site = try #require(test["url"] as? String)
            let mainFrame = try #require(test["mainFrame"] as? Bool)
            let selection = Self.bundledRules.select(url: site, mainFrame: mainFrame)
            let names = mainFrame ? Array(selection.ruleNames.dropFirst(generic)) : selection.ruleNames
            #expect(names == test["rules"] as? [String], "\(site) main frame: \(mainFrame)")
            #expect(selection.stringCount == test["strings"] as? Int, "\(site) main frame: \(mainFrame)")
            #expect(selection.usedStringCount == test["used"] as? Int, "\(site) main frame: \(mainFrame)")
            if mainFrame && !names.isEmpty { specificMatches += 1 }
        }
        #expect(specificMatches > 100, "the fixture should exercise site-specific rules")
    }

    @Test func framesGetFarLessThanTheWholeList() throws {
        let rules = Self.bundledRules
        let main = rules.select(url: "https://www.cookiebot.com/en/help/", mainFrame: true).json
        let frame = rules.select(url: "https://ads.example/frame.html", mainFrame: false).json
        let start = Date()
        for _ in 0..<100 { _ = rules.select(url: "https://www.example.com/some/page?query=1", mainFrame: true).json }
        let perFrame = Date().timeIntervalSince(start) / 100
        print("autoconsent rules: main frame \(main.utf8.count) B, subframe \(frame.utf8.count) B, \(String(format: "%.2f", perFrame * 1000)) ms per main frame")
        #expect(main.utf8.count < 200_000)
        #expect(frame.utf8.count < 20_000)
        #expect(try JSONSerialization.jsonObject(with: Data(main.utf8)) is [String: Any])
    }

    @Test func theInitReplyCarriesSettingsAndRules() throws {
        let reply = Autoconsent.initReply(rules: Self.bundledRules, url: "https://example.com/", mainFrame: false)
        let json = try #require(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        #expect(json["type"] as? String == "initResp")
        let config = try #require(json["config"] as? [String: Any])
        #expect(config["isMainWorld"] as? Bool == false)
        #expect(config["autoAction"] as? String == "optOut")
        let rules = try #require(json["rules"] as? [String: Any])
        #expect((rules["compact"] as? [String: Any])?["r"] is [Any])
    }

    // MARK: Messages

    @Test func onlyWellFormedMessagesAreUnderstood() {
        #expect(Autoconsent.Message(["type": "init", "url": "https://example.com/a"]) == .initialize(url: "https://example.com/a"))
        #expect(Autoconsent.Message(["type": "init", "url": "http://example.com/"]) == .initialize(url: "http://example.com/"))
        #expect(Autoconsent.Message(["type": "init", "url": "about:blank"]) == nil)
        #expect(Autoconsent.Message(["type": "init", "url": "file:///etc/passwd"]) == nil)
        #expect(Autoconsent.Message(["type": "init"]) == nil)
        #expect(Autoconsent.Message(["type": "eval", "id": "1", "snippetId": "EVAL_X"]) == .evaluate(id: "1", snippet: "EVAL_X"))
        #expect(Autoconsent.Message(["type": "eval", "id": "1", "code": "alert(1)"]) == nil)
        #expect(Autoconsent.Message(["type": "eval", "id": String(repeating: "1", count: 65), "snippetId": "EVAL_X"]) == nil)
        #expect(Autoconsent.Message(["type": "eval", "id": 1, "snippetId": "EVAL_X"]) == nil)
        #expect(Autoconsent.Message(["type": "report"]) == nil)
        #expect(Autoconsent.Message("init") == nil)
        #expect(Autoconsent.Message([1, 2]) == nil)
    }

    // MARK: Snippets

    @Test func onlyShippedSnippetsCanRun() throws {
        let snippets = Self.bundledSnippets
        #expect(snippets.count > 50)
        let script = try #require(snippets.script(for: "EVAL_DIDOMI_TEST"))
        #expect(script.contains("window.Didomi"))
        #expect(script.hasPrefix("(() => { try { return !!("))
        #expect(snippets.script(for: "alert(document.cookie)") == nil)
        #expect(snippets.script(for: "") == nil)
    }

    /// The table and the isolated script must come from the same release, or
    /// a rule could ask for a check the app doesn't have.
    @Test func everySnippetTheScriptKnowsIsShipped() throws {
        let script = try String(contentsOf: Self.scripts.appendingPathComponent("autoconsent-isolated.js"), encoding: .utf8)
        let ids = Set(script.matches(of: /EVAL_[A-Z0-9_]+/).map { String($0.output) })
        #expect(ids.count > 50)
        let missing = ids.filter { Self.bundledSnippets.script(for: $0) == nil }
        #expect(missing.isEmpty, "\(missing.sorted())")
    }
}
