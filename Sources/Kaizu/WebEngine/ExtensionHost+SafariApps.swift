import Foundation

extension ExtensionHost {
    nonisolated private static let safariExtensionPoint = "com.apple.Safari.web-extension"

    /// Safari web extensions bundled in apps under /Applications.
    /// `safariExtensionApps()`, off the main thread: it walks the Applications folders.
    @concurrent
    nonisolated static func findSafariExtensionApps() async -> [URL] {
        safariExtensionApps()
    }

    nonisolated static func safariExtensionApps() -> [URL] {
        let apps = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        return apps.filter { $0.pathExtension == "app" && safariExtensionBundle(in: $0) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated static func safariExtensionBundle(in app: URL) -> Bundle? {
        let plugins = app.appending(path: "Contents/PlugIns")
        let appexes = (try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)) ?? []
        return appexes.lazy.compactMap(Bundle.init(url:)).first { bundle in
            let point = (bundle.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
            return point == safariExtensionPoint
        }
    }
}
