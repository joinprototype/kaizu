import OSLog

/// Kaizu's unified log. Read it live with Console.app or
/// `log stream --predicate 'subsystem == "com.joinprototype.kaizu"'`;
/// Help → Report a Bug attaches this session's entries.
///
/// Addresses are logged as hashes (never in private windows), so a report can
/// tell "the same site failed twice" without saying which site.
enum Log {
    static let subsystem = "com.joinprototype.kaizu"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    static let session = Logger(subsystem: subsystem, category: "Session")
    static let downloads = Logger(subsystem: subsystem, category: "Downloads")
    static let diagnostics = Logger(subsystem: subsystem, category: "Diagnostics")
}
