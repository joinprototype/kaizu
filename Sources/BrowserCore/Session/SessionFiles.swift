import Foundation

/// Opens a session before any browser services can schedule a save.
public struct SessionFiles: Sendable {
    public struct Opened {
        public let record: SessionRecord
        public let migrated: Bool
        public let recovered: Bool
        /// The in-memory session contains a schema upgrade or a repair to persist.
        public let needsSave: Bool
    }

    public let directory: URL
    public var primary: URL { directory.appending(path: "session.json") }
    public var tabStates: URL { directory.appending(path: "TabStates", directoryHint: .isDirectory) }
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
        let (saved, version) = try SessionRecord.decode(data)
        let migrated = version < SessionRecord.currentVersion
        if migrated {
            try data.write(to: directory.appending(path: "session.v\(version).backup.json"), options: .atomic)
        }
        var record = saved
        let repair = record.repairDuplicateTodayTabs()
        for id in repair.ambiguousStateIDs {
            // One WebKit history file served two different URLs. Keep its bytes, and
            // let each tab load its own recorded page instead of restoring the wrong one.
            let state = tabStates.appending(path: "\(id).state")
            if FileManager.default.fileExists(atPath: state.path) {
                let preserved = directory.appending(path: "tabstate-\(id)-\(UUID()).backup")
                try FileManager.default.moveItem(at: state, to: preserved)
            }
        }
        return Opened(record: record, migrated: migrated, recovered: recovered, needsSave: migrated || repair.changed)
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}

private extension SessionRecord {
    /// Older bookmark imports could save the same Today tab twice after Undo.
    /// Keep the first identity for window selections and splits. Preserve independently edited copies.
    mutating func repairDuplicateTodayTabs() -> (changed: Bool, ambiguousStateIDs: Set<UUID>) {
        var changed = false
        var ambiguousStateIDs = Set<UUID>()
        for index in spaces.indices {
            let today = spaces[index].today
            guard today.count > 1, Set(today.lazy.map(\.id)).count < today.count else { continue }
            var records = Set<TabRecord>()
            var firstByID: [UUID: TabRecord] = [:]
            spaces[index].today = today.compactMap { original in
                guard records.insert(original).inserted else { return nil }
                if let first = firstByID[original.id] {
                    if first.url != original.url { ambiguousStateIDs.insert(original.id) }
                    var edited = original
                    edited.id = UUID()
                    return edited
                }
                firstByID[original.id] = original
                return original
            }
            changed = true
        }
        return (changed, ambiguousStateIDs)
    }
}
