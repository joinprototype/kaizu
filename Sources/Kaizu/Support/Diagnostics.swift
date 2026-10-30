import CryptoKit
import Foundation
import MetricKit
import OSLog

/// Crash and hang reports, kept on this Mac for Help → Report a Bug. Nothing
/// is sent anywhere on its own.
///
/// Two sources: MetricKit hands over crash, hang and resource diagnostics on
/// the launch after they happen (saved to `Diagnostics/`), and macOS writes
/// its own crash reports (.ips) for Kaizu and the WebKit processes it starts.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = Diagnostics()
    static let launchedAt = Date()
    static let directory = AppPaths.support.appending(path: "Diagnostics", directoryHint: .isDirectory)
    private static let keep = 20

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// "macOS 27.0 (Build 27A123)".
    static var macOSVersion: String {
        "macOS " + ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: "")
    }

    func start() {
        _ = Self.launchedAt
        MXMetricManager.shared.add(self)
        // Delivered before this launch subscribed (re-saving one is harmless).
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        for payload in payloads {
            let json = payload.jsonRepresentation()
            // Named by content, so the same payload delivered again overwrites itself.
            let digest = SHA256.hash(data: json).prefix(6).map { String(format: "%02x", $0) }.joined()
            let stamp = payload.timeStampEnd.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            let name = "metrickit-\(stamp.replacingOccurrences(of: ":", with: ""))-\(digest).json"
            try? json.write(to: Self.directory.appending(path: name), options: .atomic)
        }
        Log.diagnostics.notice("Received \(payloads.count) diagnostic reports from macOS")
        // Newest first; the rest go.
        let saved = (try? manager.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for old in saved.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).dropFirst(Self.keep) {
            try? manager.removeItem(at: old)
        }
    }

    /// Everything worth attaching from the last `days` days: MetricKit's
    /// reports, Kaizu's own crash reports, and those of WebKit processes
    /// (pages, GPU, network) that Kaizu started.
    static func recentReports(days: Int = 14) -> [URL] {
        let since = Date.now.addingTimeInterval(-Double(days) * 24 * 3600)
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        func files(in directory: URL) -> [URL] {
            let all = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
            return all.filter { ((try? $0.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast) > since }
        }
        let crashes = manager.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        let system = files(in: crashes).filter { url in
            let name = url.lastPathComponent
            guard url.pathExtension == "ips" else { return false }
            if name.hasPrefix("Kaizu") { return true }
            guard name.hasPrefix("com.apple.WebKit."),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { return false }
            return text.range(of: #""responsibleProc"\s*:\s*"Kaizu""#, options: .regularExpression) != nil
        }
        return files(in: directory) + system
    }

    /// This session's Kaizu entries, plus WebKit's errors from this process.
    /// Slow (a second or two): call off the main thread.
    static func sessionLog() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@ OR subsystem BEGINSWITH %@", Log.subsystem, "com.apple.WebKit")
        let entries = try store.getEntries(at: store.position(date: launchedAt), matching: predicate)
        let timeStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            let ours = entry.subsystem == Log.subsystem
            guard ours || entry.level == .error || entry.level == .fault else { continue }
            let level = switch entry.level {
            case .debug: "D"
            case .info: "I"
            case .notice: "N"
            case .error: "E"
            case .fault: "F"
            default: "-"
            }
            let category = ours ? entry.category : "WebKit.\(entry.category)"
            let time = entry.date.formatted(timeStyle)
            lines.append("\(time) \(level) \(category): \(entry.composedMessage)")
        }
        return lines.suffix(5000).joined(separator: "\n") + "\n"
    }
}
