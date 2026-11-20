import Foundation

package nonisolated enum AppDefaults {
    /// Where Kaizu keeps its own preferences: settings, paused sites,
    /// extensions, filter-list checks. A debug run with `KAIZU_SUPPORT` gets
    /// its own set, named after that folder, so QA runs never change the
    /// preferences of the Kaizu the user is browsing with (the debug build
    /// shares its bundle identifier). Running again on the same folder sees
    /// what the last run left. `UserDefaults` is thread-safe, so sharing it is fine.
    package nonisolated(unsafe) static let shared: UserDefaults = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["KAIZU_SUPPORT"] {
            let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
            let name = (Bundle.main.bundleIdentifier ?? "com.joinprototype.kaizu") + ".qa." + stableHash(folder)
            if let suite = UserDefaults(suiteName: name) { return suite }
        }
        #endif
        return .standard
    }()

    #if DEBUG
    /// FNV-1a: the same folder gives the same name on every launch, unlike `hashValue`.
    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
    #endif
}
