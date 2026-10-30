import BrowserCore
import Foundation
import Testing

struct ChoiceMemoryTests {
    private let github = "tab:github"
    private let gmail = "tab:gmail"

    @Test func leadsWithWhatYouPickOften() {
        var memory = ChoiceMemory()
        memory.record(query: "gi", choice: github)
        #expect(memory.topChoice(for: "gi", among: [github, gmail]) == nil, "once isn't a habit")
        memory.record(query: "gi", choice: github)
        #expect(memory.topChoice(for: "gi", among: [github, gmail]) == github)
        #expect(memory.topChoice(for: "g", among: [github, gmail]) == github, "shorter prefixes learn too")
        #expect(memory.topChoice(for: "git", among: [github, gmail]) == nil, "longer ones haven't been typed")
    }

    @Test func onlyAmongWhatsOffered() {
        var memory = ChoiceMemory()
        memory.record(query: "gi", choice: github)
        memory.record(query: "gi", choice: github)
        #expect(memory.topChoice(for: "gi", among: [gmail]) == nil)
    }

    @Test func theMoreUsedChoiceWins() {
        var memory = ChoiceMemory()
        for _ in 0..<2 { memory.record(query: "g", choice: github) }
        for _ in 0..<3 { memory.record(query: "g", choice: gmail) }
        #expect(memory.topChoice(for: "g", among: [github, gmail]) == gmail)
    }

    @Test func ignoresCaseAndSpacesAndCanForget() {
        var memory = ChoiceMemory()
        memory.record(query: " GI ", choice: github)
        memory.record(query: "gi", choice: github)
        #expect(memory.topChoice(for: "Gi", among: [github]) == github)
        memory.forget(github)
        #expect(memory.topChoice(for: "gi", among: [github]) == nil)
    }

    @Test func noLeadPastWhatsRemembered() {
        var memory = ChoiceMemory()
        let long = "how to make pasta sauce at home"
        memory.record(query: long, choice: "search:sauce")
        memory.record(query: long, choice: "search:sauce")
        #expect(memory.topChoice(for: "how to make pasta salad at home", among: ["search:sauce"]) == nil)
        #expect(memory.topChoice(for: "how to make", among: ["search:sauce"]) == "search:sauce")
    }

    @Test func survivesEncoding() throws {
        var memory = ChoiceMemory()
        memory.record(query: "gi", choice: github)
        memory.record(query: "gi", choice: github)
        let decoded = try JSONDecoder().decode(ChoiceMemory.self, from: JSONEncoder().encode(memory))
        #expect(decoded == memory)
        #expect(decoded.topChoice(for: "gi", among: [github]) == github)
    }
}
