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
