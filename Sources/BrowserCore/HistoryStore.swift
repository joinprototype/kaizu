import Foundation
import SQLite3

/// Pages visited, kept per profile and searchable for the command bar.
/// A small SQLite file; all access is serialized by the actor, off the main thread.
public actor HistoryStore {
    public struct Entry: Sendable, Equatable, Identifiable {
        public var url: URL
        public var title: String
        public var visitCount: Int
        public var lastVisit: Date

        public var id: URL { url }
    }

    public enum Failure: Error {
        case cannotOpen(String)
        case cannotWrite(String)
    }

    /// Only rows created by this import are eligible for Undo.
    public struct ImportUndo: Sendable {
        fileprivate let batch: String
        fileprivate let profile: UUID
        fileprivate var counts: [String: Int] = [:]
    }

    private enum Value {
        case text(String)
        case real(Double)
        case integer(Int)
    }

    /// Owns the SQLite handle and closes it when the store goes away. Only
    /// ever used through the actor, hence the unchecked Sendable.
    private final class Connection: @unchecked Sendable {
        let handle: OpaquePointer

        init(_ handle: OpaquePointer) {
            self.handle = handle
        }

        deinit {
            sqlite3_close(handle)
        }
    }

    private let connection: Connection
    private var db: OpaquePointer { connection.handle }

    public init(fileURL: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(fileURL.path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw Failure.cannotOpen(message)
        }
        connection = Connection(handle)
        sqlite3_busy_timeout(handle, 1_000)
        guard sqlite3_exec(handle, """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS visits (
                profile TEXT NOT NULL,
                url TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                visit_count INTEGER NOT NULL DEFAULT 1,
                last_visit REAL NOT NULL,
                import_batch TEXT,
                PRIMARY KEY (profile, url)
            );
            CREATE INDEX IF NOT EXISTS visits_by_recency ON visits (profile, last_visit DESC);
            """, nil, nil, nil) == SQLITE_OK else {
            throw Failure.cannotOpen(String(cString: sqlite3_errmsg(handle)))
        }
        // Existing versions name the columns they write, so they can still open this database.
        if sqlite3_table_column_metadata(handle, nil, "visits", "import_batch", nil, nil, nil, nil, nil) != SQLITE_OK {
            let rc = sqlite3_exec(handle, "ALTER TABLE visits ADD COLUMN import_batch TEXT", nil, nil, nil)
            guard rc == SQLITE_OK || sqlite3_table_column_metadata(handle, nil, "visits", "import_batch", nil, nil, nil, nil, nil) == SQLITE_OK else {
                throw Failure.cannotOpen(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    public func recordVisit(profile: UUID, url: URL, title: String, at date: Date = Date()) {
        guard url.isWebPage else { return }
        run("""
            INSERT INTO visits (profile, url, title, visit_count, last_visit) VALUES (?1, ?2, ?3, 1, ?4)
            ON CONFLICT (profile, url) DO UPDATE SET
                visit_count = visit_count + 1,
                last_visit = ?4,
                title = CASE WHEN ?3 = '' THEN title ELSE ?3 END
            """, [.text(profile.uuidString), .text(url.absoluteString), .text(title), .real(date.timeIntervalSince1970)])
    }

    /// Matches in URL or title, ranked by "frecency": visit count decayed by
    /// days since the last visit.
    public func search(_ text: String, profile: UUID, limit: Int = 5, now: Date = Date()) -> [Entry] {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return entries("""
            SELECT url, title, visit_count, last_visit FROM visits
            WHERE profile = ?1 AND (url LIKE ?2 ESCAPE '\\' OR title LIKE ?2 ESCAPE '\\')
            ORDER BY visit_count / (1.0 + (?3 - last_visit) / 86400.0) DESC
            LIMIT ?4
            """, [.text(profile.uuidString), .text("%\(escaped)%"), .real(now.timeIntervalSince1970), .integer(limit)])
    }

    public func recent(profile: UUID, limit: Int = 50) -> [Entry] {
        entries(
            "SELECT url, title, visit_count, last_visit FROM visits WHERE profile = ?1 ORDER BY last_visit DESC LIMIT ?2",
            [.text(profile.uuidString), .integer(limit)]
        )
    }

    public func remove(_ url: URL, profile: UUID) {
        run("DELETE FROM visits WHERE profile = ?1 AND url = ?2", [.text(profile.uuidString), .text(url.absoluteString)])
    }

    /// Pages from another browser, all at once. A page already here keeps its
    /// title and takes the higher count and the later date, so importing
    /// twice changes nothing. The receipt undoes only what this import added.
    public func importVisits(_ visits: [BrowsingData.Visit], profile: UUID) throws -> ImportUndo {
        var undo = ImportUndo(batch: UUID().uuidString, profile: profile)
        guard !visits.isEmpty else { return undo }
        guard let insert = prepare("INSERT OR IGNORE INTO visits (profile, url, title, visit_count, last_visit, import_batch) VALUES (?1, ?2, ?3, ?4, ?5, ?6)", []) else {
            throw Failure.cannotWrite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(insert) }
        // A later import that changes a row owns those edits. An identical re-import leaves Undo intact.
        guard let update = prepare("""
                UPDATE visits SET
                    import_batch = CASE WHEN import_batch = ?6 THEN import_batch
                        WHEN visit_count < ?4 OR last_visit < ?5 OR (title = '' AND ?3 != '') THEN NULL ELSE import_batch END,
                    visit_count = max(visit_count, ?4),
                    last_visit = max(last_visit, ?5),
                    title = CASE WHEN title = '' THEN ?3 ELSE title END
                WHERE profile = ?1 AND url = ?2
                """, [])
        else { throw Failure.cannotWrite(String(cString: sqlite3_errmsg(db))) }
        defer { sqlite3_finalize(update) }
        try inTransaction {
            for visit in visits {
                let values: [Value] = [
                    .text(profile.uuidString), .text(visit.url.absoluteString), .text(visit.title),
                    .integer(visit.count), .real(visit.lastVisit.timeIntervalSince1970), .text(undo.batch),
                ]
                try runAgain(insert, values)
                if sqlite3_changes(db) > 0 {
                    undo.counts[visit.url.absoluteString] = visit.count
                } else {
                    try runAgain(update, values)
                    if let count = undo.counts[visit.url.absoluteString] {
                        undo.counts[visit.url.absoluteString] = max(count, visit.count)
                    }
                }
            }
        }
        return undo
    }

    /// Retain genuine later visits. Deleting and revisiting the same URL creates an unmarked row.
    public func undoImport(_ undo: ImportUndo) throws {
        guard !undo.counts.isEmpty else { return }
        let match = "WHERE profile = ?1 AND url = ?2 AND import_batch = ?3"
        guard let delete = prepare("DELETE FROM visits \(match) AND visit_count = ?4", []) else {
            throw Failure.cannotWrite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(delete) }
        guard let keep = prepare("UPDATE visits SET visit_count = visit_count - ?4, import_batch = NULL \(match) AND visit_count > ?4", []) else {
            throw Failure.cannotWrite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(keep) }
        try inTransaction {
            for (url, count) in undo.counts {
                let values: [Value] = [.text(undo.profile.uuidString), .text(url), .text(undo.batch), .integer(count)]
                try runAgain(delete, values)
                if sqlite3_changes(db) == 0 { try runAgain(keep, values) }
            }
        }
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else {
            throw Failure.cannotWrite(String(cString: sqlite3_errmsg(db)))
        }
        do {
            try body()
            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw Failure.cannotWrite(String(cString: sqlite3_errmsg(db)))
            }
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    /// Forgets everything, or only one profile's history.
    public func removeAll(profile: UUID? = nil) {
        if let profile {
            run("DELETE FROM visits WHERE profile = ?1", [.text(profile.uuidString)])
        } else {
            run("DELETE FROM visits", [])
        }
    }

    // MARK: - SQLite plumbing

    private func run(_ sql: String, _ values: [Value]) {
        guard let statement = prepare(sql, values) else { return }
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    /// For a statement prepared once and used for many rows.
    private func runAgain(_ statement: OpaquePointer, _ values: [Value]) throws {
        bind(values, to: statement)
        defer { sqlite3_reset(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.cannotWrite(String(cString: sqlite3_errmsg(db))) }
    }

    private func entries(_ sql: String, _ values: [Value]) -> [Entry] {
        guard let statement = prepare(sql, values) else { return [] }
        defer { sqlite3_finalize(statement) }
        var results: [Entry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let url = URL(string: String(cString: sqlite3_column_text(statement, 0))) else { continue }
            results.append(Entry(
                url: url,
                title: String(cString: sqlite3_column_text(statement, 1)),
                visitCount: Int(sqlite3_column_int64(statement, 2)),
                lastVisit: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        return results
    }

    private func prepare(_ sql: String, _ values: [Value]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        bind(values, to: statement)
        return statement
    }

    private func bind(_ values: [Value], to statement: OpaquePointer?) {
        // SQLite copies bound text (SQLITE_TRANSIENT) so Swift strings can go away.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .real(let real): sqlite3_bind_double(statement, index, real)
            case .integer(let integer): sqlite3_bind_int64(statement, index, Int64(integer))
            }
        }
    }
}
