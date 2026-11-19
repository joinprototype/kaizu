import Testing
@testable import Kaizu

/// VoiceOver reads a shortcut out symbol by symbol, so spoken names drop it.
struct SpokenNameTests {
    @Test func shortcutsAreLeftOut() {
        #expect(spokenName("Close Tab (⌘W)") == "Close Tab")
        #expect(spokenName("Open in Split View (⌃⇧=)") == "Open in Split View")
        #expect(spokenName("Back (⌘[)") == "Back")
    }

    @Test func otherBracketsStay() {
        #expect(spokenName("Back to the pinned page") == "Back to the pinned page")
        #expect(spokenName("Downloads (2 running)") == "Downloads (2 running)")
        #expect(spokenName("") == "")
    }
}
