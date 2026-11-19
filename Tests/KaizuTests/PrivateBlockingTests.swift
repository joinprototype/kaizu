import Foundation
import Testing
@testable import Kaizu

@MainActor
struct PrivateBlockingTests {
    @Test func aPrivatePauseOnlyReleasesItsOwnPendingNavigation() throws {
        let suite = "dev.kaizu.tests.private-blocking." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let blocker = ContentBlocker(defaults: defaults)
        let first = UUID(), second = UUID()
        let parent = URL(string: "https://example.test/")!
        let page = URL(string: "https://team.example.test/")!
        var released: [String] = []
        blocker.whenReady(for: page) { released.append("regular") }
        blocker.whenReady(for: page, privateID: first) { released.append("first") }
        blocker.whenReady(for: page, privateID: second) { released.append("second") }
        #expect(released.isEmpty)

        blocker.togglePause(on: parent, privateID: first)
        #expect(released == ["first"])
        #expect(blocker.pausedSites.isEmpty)
        #expect(defaults.stringArray(forKey: "blockingPausedSites") == nil)

        blocker.togglePause(on: parent, privateID: nil)
        #expect(released == ["first", "regular", "second"])
        blocker.togglePause(on: page, privateID: second)
        #expect(!blocker.isPaused(on: page, privateID: second))
        #expect(blocker.isPaused(on: page, privateID: nil))
        #expect(defaults.stringArray(forKey: "blockingPausedSites") == ["example.test"])

        blocker.forgetPrivateOverrides(for: second)
        #expect(blocker.isPaused(on: page, privateID: second))
    }
}
