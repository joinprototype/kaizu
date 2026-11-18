import BrowserCore
import Foundation
import Testing

struct TabStateFilesTests {
    @Test func archiveSnapshotSurvivesSweepsAndBecomesALiveTab() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TabStateFiles(directory: directory)
        let other = UUID()
        let live = Data("live tab".utf8), history = Data("archived history".utf8)
        files.save([other: live], inBackground: true)
        let id = try files.storeArchivedState(history)
        #expect(files.read(other) == live)
        files.save([other: live], retaining: [id], inBackground: true)
        files.save([:], retaining: [id])
        let relaunched = TabStateFiles(directory: directory)
        #expect(relaunched.read(id) == history)
        #expect(relaunched.read(other) == nil)
        let newer = Data("new navigation after reopening".utf8)
        relaunched.save([id: newer])
        #expect(relaunched.read(id) == newer)
        relaunched.save([:])
        #expect(relaunched.read(id) == nil)
    }

    @Test func quitCommitsTheNewestHistoryAfterQueuedSweeps() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = TabStateFiles(directory: directory)
        let existing = UUID(), newTab = UUID(), closedTab = UUID()
        let initial = Data("before navigation".utf8), latest = Data("after navigation".utf8)
        var sweep = [existing: initial, closedTab: initial]
        for _ in 0..<128 { sweep[UUID()] = initial }

        files.save(sweep, inBackground: true)
        files.save([closedTab: initial], inBackground: true)
        files.save([existing: latest, newTab: initial])

        let reopened = TabStateFiles(directory: directory)
        #expect(reopened.read(existing) == latest)
        #expect(reopened.read(newTab) == initial)
        #expect(reopened.read(closedTab) == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(Set(names) == ["\(existing).state", "\(newTab).state"])
    }
}
