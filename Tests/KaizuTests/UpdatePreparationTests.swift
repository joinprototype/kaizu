import Foundation
import Testing
@testable import BrowserCore
@testable import Kaizu

@MainActor
struct UpdatePreparationTests {
    private func update(_ build: Int) -> StagedUpdate {
        StagedUpdate(app: URL(fileURLWithPath: "/fixture/\(build)/Kaizu.app"), version: "0.0.\(build)", build: build)
    }

    @Test(arguments: [true, false])
    func newerVerifiedBuildSurvivesLateCompletion(olderSucceeds: Bool) async throws {
        let state = UpdatePreparation()
        let (release, gate) = AsyncStream<Void>.makeStream()
        let older = state.prepare(build: 11) {
            for await _ in release { break }
            if !olderSucceeds { throw UpdateFailure.badSignature }
            return update(11)
        }
        let newest = update(12)
        _ = try await state.prepare(build: 12) { newest }.value
        gate.finish()
        #expect(try await older.value == newest)
        #expect(state.staged == newest)
        let cached = state.prepare(build: 11) { throw UpdateFailure.badDownload }
        #expect(try await cached.value == newest)
    }

    @Test func concurrentChecksShareFailuresAndCanRetry() async throws {
        let state = UpdatePreparation()
        let fallback = update(10)
        _ = try await state.prepare(build: 10) { fallback }.value
        let first = state.prepare(build: 11) { throw UpdateFailure.badSignature }
        let duplicate = state.prepare(build: 11) { throw UpdateFailure.badDownload }
        #expect(first == duplicate)
        await #expect(throws: UpdateFailure.badSignature) { try await first.value }
        #expect(state.staged == fallback)
        let retry = update(11)
        #expect(try await state.prepare(build: 11) { retry }.value == retry)
        #expect(state.staged == retry)
    }
}
