import Testing
@testable import Kaizu

/// The hints shown while ⌘ is held match what ⌘1–9 select.
struct TabNumberTests {
    @Test func firstEightThenTheLast() {
        let twelve = (0..<12).map { BrowserStore.tabNumber(at: $0, of: 12) }
        #expect(twelve == [1, 2, 3, 4, 5, 6, 7, 8, nil, nil, nil, 9])
        let three = (0..<3).map { BrowserStore.tabNumber(at: $0, of: 3) }
        #expect(three == [1, 2, 3])
        let nine = (0..<9).map { BrowserStore.tabNumber(at: $0, of: 9) }
        #expect(nine == [1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(BrowserStore.tabNumber(at: 5, of: 3) == nil)
    }
}
