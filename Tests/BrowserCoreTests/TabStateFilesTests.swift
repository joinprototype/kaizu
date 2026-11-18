import BrowserCore
import Foundation
import Testing

struct TabStateFilesTests {
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
