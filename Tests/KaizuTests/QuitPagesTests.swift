import AppKit
import Testing
@testable import Kaizu

@MainActor
struct QuitPagesTests {
    @Test func deferredReplyRunsWhileAppKitWaitsInItsModalLoop() {
        let pages = QuitPages()
        var replies = 0
        pages.start([]) { replies += 1 }

        // Simulate terminateLater called from an action already executing on the main actor.
        let deadline = Date(timeIntervalSinceNow: 3)
        let wake = Timer(fire: deadline, interval: 0, repeats: false) { _ in }
        RunLoop.main.add(wake, forMode: .modalPanel)
        defer { wake.invalidate() }
        while replies == 0 && Date() < deadline {
            _ = RunLoop.main.run(mode: .modalPanel, before: Date(timeIntervalSinceNow: 0.05))
        }
        #expect(replies == 1)
    }
}
