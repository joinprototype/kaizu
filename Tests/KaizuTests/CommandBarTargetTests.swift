import AppKit
import Testing
@testable import Kaizu

/// ↩ opens where the bar was opened for, ⌘↩ in the background, ⌥↩ in a
/// split; other mixes are a plain ↩.
struct CommandBarTargetTests {
    @Test func keysPickWhereAPageOpens() {
        #expect(CommandBarTarget([]) == .usual)
        #expect(CommandBarTarget(.command) == .background)
        #expect(CommandBarTarget(.option) == .split)
        #expect(CommandBarTarget([.command, .capsLock]) == .background)
        #expect(CommandBarTarget([.command, .shift]) == .usual)
        #expect(CommandBarTarget([.option, .command]) == .usual)
    }
}
