import Foundation

/// Opens a session before any browser services can schedule a save.
public struct SessionFiles: Sendable {
    public struct Opened {
        public let record: SessionRecord
        public let migrated: Bool
        public let recovered: Bool
    }

    public let directory: URL
    public var primary: URL { directory.appending(path: "session.json") }
    private var backup: URL { directory.appending(path: "session.backup.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public func open() throws -> Opened? {
        let bytes = try readIfPresent(primary)
        if let bytes {
            do {
                let opened = try decode(bytes, recovered: false)
                // One snapshot per successful launch, before any new edits.
                try bytes.write(to: backup, options: .atomic)
                return opened
            } catch is DecodingError {
                // Only malformed JSON or records can fall back. A future schema,
                // a read error or a failed backup must leave the primary alone.
            }
        }

        guard let saved = try readIfPresent(backup) else {
            if bytes != nil { throw CocoaError(.fileReadCorruptFile) }
            return nil
        }
        let opened = try decode(saved, recovered: true)
        if bytes != nil {
            // Keep each damaged primary, even if recovery happens twice.
            let preserved = directory.appending(path: "session.unreadable-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: primary, to: preserved)
        }
        try saved.write(to: primary, options: .atomic)
        return opened
    }

    private var legacyArchive: URL { directory.appending(path: "archive.json") }

    public func readLegacyArchive() throws -> [ArchivedTabRecord] {
        guard let data = try readIfPresent(legacyArchive) else { return [] }
        return try JSONCoding.decoder.decode([ArchivedTabRecord].self, from: data)
    }

    /// Keep older releases able to reopen these entries, without overwriting an unreadable original.
    public func writeLegacyArchive(_ entries: [ArchivedTabRecord]) throws {
        let encoded = try JSONCoding.encoder.encode(entries)
        if let data = try readIfPresent(legacyArchive) {
            guard data != encoded else { return }
            do {
                _ = try JSONCoding.decoder.decode([ArchivedTabRecord].self, from: data)
            } catch is DecodingError {
                try data.write(to: directory.appending(path: "archive.unreadable-\(UUID().uuidString).json"), options: .atomic)
            }
        } else if entries.isEmpty {
            return
        }
        try encoded.write(to: legacyArchive, options: .atomic)
    }

    private func decode(_ data: Data, recovered: Bool) throws -> Opened {
        let (record, version) = try SessionRecord.decode(data)
        let migrated = version < SessionRecord.currentVersion
        if migrated {
            try data.write(to: directory.appending(path: "session.v\(version).backup.json"), options: .atomic)
        }
        return Opened(record: record, migrated: migrated, recovered: recovered)
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
