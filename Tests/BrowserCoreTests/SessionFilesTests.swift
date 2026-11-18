import Foundation
import Testing
@testable import BrowserCore

@Suite struct SessionFilesTests {
    private func withFiles(_ test: (SessionFiles) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        try test(SessionFiles(directory: dir))
    }

    @Test func restoresLastOpenedSessionAndPreservesDamagedBytes() throws {
        try withFiles { files in
            #expect(try files.open() == nil)
            let old = Data(SessionRecordTests.v1JSON.utf8)
            try old.write(to: files.primary)
            let migrated = try #require(try files.open())
            #expect(migrated.migrated)
            #expect(try Data(contentsOf: files.directory.appending(path: "session.v1.backup.json")) == old)

            let good = try migrated.record.encoded()
            try good.write(to: files.primary)
            _ = try files.open()
            let damaged = Data("{".utf8)
            try damaged.write(to: files.primary)
            let restored = try #require(try files.open())
            #expect(restored.recovered)
            #expect(restored.record == (try SessionRecord.decode(good)).record)
            #expect(try Data(contentsOf: files.primary) == good)
            let filesOnDisk = try FileManager.default.contentsOfDirectory(at: files.directory, includingPropertiesForKeys: nil)
            let preserved = try #require(filesOnDisk.first { $0.lastPathComponent.hasPrefix("session.unreadable-") })
            #expect(try Data(contentsOf: preserved) == damaged)

            try FileManager.default.removeItem(at: files.primary)
            #expect(try files.open()?.recovered == true)
            #expect(try Data(contentsOf: files.primary) == good)
        }
    }

    @Test func neverReplacesAnUnknownVersionWithAnOlderBackup() throws {
        try withFiles { files in
            try Data(SessionRecordTests.v1JSON.utf8).write(to: files.primary)
            _ = try files.open()
            let future = Data(#"{"schemaVersion":99}"#.utf8)
            try future.write(to: files.primary)
            #expect(throws: SessionError.unsupportedVersion(99)) { try files.open() }
            #expect(try Data(contentsOf: files.primary) == future)
        }
    }

    @Test func repairsLegacyBookmarkUndoCopiesAndKeepsDistinctEdits() throws {
        try withFiles { files in
            let now = Date(timeIntervalSince1970: 1_790_000_000)
            var session = try SessionRecord.decode(Data(SessionRecordTests.v1JSON.utf8), now: now).record
            let original = try #require(session.spaces[0].today.first)
            var edited = original
            edited.url = URL(string: "https://example.org/edited")
            edited.customTitle = "Keep my edit"
            var separateTab = original
            separateTab.id = UUID()
            session.spaces[0].today = [original, separateTab, original, edited, edited, separateTab]
            let bytes = try session.encoded()
            try bytes.write(to: files.primary)
            let history = Data("opaque WebKit history".utf8)
            try FileManager.default.createDirectory(at: files.tabStates, withIntermediateDirectories: true)
            let ambiguous = files.tabStates.appending(path: "\(original.id).state")
            let unrelated = files.tabStates.appending(path: "\(separateTab.id).state")
            try history.write(to: ambiguous)
            try history.write(to: unrelated)

            let opened = try #require(try files.open())
            #expect(opened.needsSave)
            #expect(!opened.migrated)
            #expect(!opened.recovered)
            let tabs = opened.record.spaces[0].today
            #expect(tabs.count == 3)
            #expect(Array(tabs.prefix(2)) == [original, separateTab])
            let kept = try #require(tabs.last)
            #expect(Set(tabs.map(\.id)).count == 3)
            edited.id = kept.id
            #expect(kept == edited)
            #expect(opened.record.windows[0].selectedTabIDs[session.spaces[0].id] == original.id)
            #expect(try Data(contentsOf: files.directory.appending(path: "session.backup.json")) == bytes)
            #expect(!FileManager.default.fileExists(atPath: ambiguous.path))
            #expect(try Data(contentsOf: unrelated) == history)
            let contents = try FileManager.default.contentsOfDirectory(at: files.directory, includingPropertiesForKeys: nil)
            let preserved = try #require(contents.first { $0.lastPathComponent.hasPrefix("tabstate-\(original.id)-") })
            #expect(try Data(contentsOf: preserved) == history)

            try opened.record.encoded().write(to: files.primary)
            let again = try #require(try files.open())
            #expect(again.record == opened.record)
            #expect(!again.needsSave)
        }
    }

    @Test func corruptionWithoutAReadableBackupLeavesTheOriginalAlone() throws {
        try withFiles { files in
            let bad = Data("damaged".utf8)
            try bad.write(to: files.primary)
            #expect(throws: (any Error).self) { try files.open() }
            try bad.write(to: files.directory.appending(path: "session.backup.json"))
            #expect(throws: (any Error).self) { try files.open() }
            #expect(try Data(contentsOf: files.primary) == bad)
        }
    }
}
