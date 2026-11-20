import OSLog

/// Kaizu's unified log. Read it live with Console.app or
/// `log stream --predicate 'subsystem == "com.joinprototype.kaizu"'`;
/// Help → Report a Bug attaches this session's entries.
///
/// Addresses are logged as hashes (never in private windows), so a report can
/// tell "the same site failed twice" without saying which site.
package nonisolated enum Log {
    package static let subsystem = "com.joinprototype.kaizu"

    package static let app = Logger(subsystem: subsystem, category: "App")
    package static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    package static let session = Logger(subsystem: subsystem, category: "Session")
    package static let downloads = Logger(subsystem: subsystem, category: "Downloads")
    package static let diagnostics = Logger(subsystem: subsystem, category: "Diagnostics")
}
