import Foundation
import OSLog

/// Keeps filter lists fresh: the app ships snapshots, and once a day we fetch
/// newer copies into Application Support. List authors expect updates every
/// few days ("! Expires: 4 days").
enum FilterListUpdater {
    static let sources: [String: URL] = [
        "easylist": URL(string: "https://easylist.to/easylist/easylist.txt")!,
        "easyprivacy": URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
        "cookies": URL(string: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt")!,
    ]
    static let interval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "filterListsLastChecked"
    private static let log = Logger(subsystem: Log.subsystem, category: "FilterListUpdater")

    static var directory: URL {
        AppPaths.support.appending(path: "Filters", directoryHint: .isDirectory)
    }

    /// The newer of the downloaded copy and the snapshot bundled with the app.
    static func text(for name: String) -> String? {
        let bundled = BundledResource.url(named: name, extension: "txt", in: "Filters")
        let downloaded = directory.appending(path: "\(name).txt")
        let candidates = [downloaded, bundled].compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { modificationDate($0) > modificationDate($1) }
        return candidates.lazy.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first
    }

    /// Fetches lists if the last check was over a day ago. Returns true when
    /// at least one list changed (so rules need recompiling).
    @MainActor
    static func updateIfDue() async -> Bool {
        let defaults = UserDefaults.standard
        guard Date().timeIntervalSince1970 - defaults.double(forKey: lastCheckKey) > interval else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let session = URLSession(configuration: .ephemeral)
        var changed = false
        for (name, url) in sources {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8),
                  isPlausibleFilterList(text)
            else {
                log.error("Couldn't update \(name, privacy: .public)")
                continue
            }
            if text != Self.text(for: name) {
                try? data.write(to: directory.appending(path: "\(name).txt"), options: .atomic)
                changed = true
                log.info("Updated \(name, privacy: .public)")
            }
        }
        defaults.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        return changed
    }

    /// Guards against captive portals and error pages replacing a good list.
    static func isPlausibleFilterList(_ text: String) -> Bool {
        text.hasPrefix("[Adblock") && text.utf8.count > 10_000
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
