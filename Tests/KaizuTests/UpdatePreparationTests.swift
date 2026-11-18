import Foundation
import Testing
@testable import BrowserCore
@testable import Kaizu

@MainActor
struct UpdatePreparationTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)

    private func update(_ build: Int) throws -> StagedUpdate {
        let app = root.appending(path: "\(build)/unpacked/Kaizu.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        return StagedUpdate(app: app, version: "0.0.\(build)", build: build)
    }

    private func cachedBuilds() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    @Test(arguments: [true, false])
    func newerVerifiedBuildSurvivesLateCompletion(olderSucceeds: Bool) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = UpdatePreparation(root: root)
        let (release, gate) = AsyncStream<Void>.makeStream()
        let older = state.prepare(build: 11) {
            for await _ in release { break }
            if !olderSucceeds { throw UpdateFailure.badSignature }
            return try update(11)
        }
        let newest = try update(12)
        _ = try await state.prepare(build: 12) { newest }.value
        gate.finish()
        #expect(try await older.value == newest)
        #expect(state.staged == newest)
        #expect(try cachedBuilds() == ["12"])
        #expect(FileManager.default.fileExists(atPath: newest.app.path))
        let cached = state.prepare(build: 11) { throw UpdateFailure.badDownload }
        #expect(try await cached.value == newest)
    }

    @Test func concurrentChecksShareFailuresAndCanRetry() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = UpdatePreparation(root: root)
        let fallback = try update(10)
        _ = try await state.prepare(build: 10) { fallback }.value
        let first = state.prepare(build: 11) { throw UpdateFailure.badSignature }
        let duplicate = state.prepare(build: 11) { throw UpdateFailure.badDownload }
        #expect(first == duplicate)
        await #expect(throws: UpdateFailure.badSignature) { try await first.value }
        #expect(state.staged == fallback)
        #expect(try cachedBuilds() == ["10"])
        #expect(FileManager.default.fileExists(atPath: fallback.app.path))
        let retry = try update(11)
        #expect(try await state.prepare(build: 11) { retry }.value == retry)
        #expect(state.staged == retry)
        #expect(try cachedBuilds() == ["11"])
        #expect(FileManager.default.fileExists(atPath: retry.app.path))
    }
}
