import AppKit

/// Help → Report a Bug: what the user wrote plus, if they agree, diagnostics,
/// zipped in a temporary folder and attached to a Mail draft. Nothing leaves
/// the Mac until they send that draft.
@MainActor
enum BugReport {
    static let recipient = "help@joinprototype.com"

    /// Writes the report folder and its zip; returns the zip (the folder sits
    /// next to it, unzipped, for a look before sending).
    static func write(summary: String, includingDiagnostics: Bool, store: BrowserStore) async throws -> URL {
        let manager = FileManager.default
        let stamp = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = manager.temporaryDirectory.appending(path: "Kaizu Report \(stamp)", directoryHint: .isDirectory)
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n---\n"
            + details(store: store, full: includingDiagnostics) + "\n"
        try Data(text.utf8).write(to: folder.appending(path: "Report.txt"))
        if includingDiagnostics {
            try await Task.detached {
                let log = (try? Diagnostics.sessionLog()) ?? "Couldn't read the log."
                try Data(log.utf8).write(to: folder.appending(path: "Kaizu.log"))
                let reports = Diagnostics.recentReports()
                guard !reports.isEmpty else { return }
                let crashes = folder.appending(path: "Crash Reports", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: crashes, withIntermediateDirectories: true)
                for report in reports {
                    try? FileManager.default.copyItem(at: report, to: crashes.appending(path: report.lastPathComponent))
                }
            }.value
        }
        return try await zip(folder)
    }

    /// A Mail draft to `recipient` with the zip attached. False if this Mac
    /// can't compose mail.
    static func compose(summary: String, attachment: URL) -> Bool {
        guard let service = NSSharingService(named: .composeEmail) else { return false }
        let summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = summary.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        service.recipients = [recipient]
        service.subject = "Kaizu bug: \(firstLine.prefix(60))"
        let items: [Any] = ["\(summary)\n\nKaizu \(Diagnostics.appVersion), \(Diagnostics.macOSVersion)\n", attachment]
        guard service.canPerform(withItems: items) else { return false }
        service.perform(withItems: items)
        return true
    }

    /// Versions always; with `full`, the setup that most often explains a bug.
    private static func details(store: BrowserStore, full: Bool) -> String {
        var lines = ["Kaizu \(Diagnostics.appVersion)", Diagnostics.macOSVersion]
        guard full else { return lines.joined(separator: "\n") }

        var tabs: [ObjectIdentifier: BrowserTab] = [:]
        for tab in store.spaces.flatMap(\.allTabs) {
            tabs[ObjectIdentifier(tab)] = tab
        }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let extensions = store.extensions.installed.map(\.name)
        let uptime = Duration.seconds(Date.now.timeIntervalSince(Diagnostics.launchedAt))
        lines += [
            "Mac: \(macModel), \(ProcessInfo.processInfo.physicalMemory >> 30) GB memory",
            "Language: \(Locale.preferredLanguages.first ?? "?")",
            "Appearance: \(isDark ? "dark" : "light"), scroll bars \(NSScroller.preferredScrollerStyle == .legacy ? "always shown" : "overlay")",
            "Blocking: ads \(store.contentBlocker.isEnabled ? "on" : "off"), cookie pop-ups \(store.contentBlocker.isCookieRejectionEnabled ? "on" : "off")",
            "Extensions: \(extensions.isEmpty ? "none" : extensions.joined(separator: ", "))",
            "Spaces: \(store.spaces.count), tabs: \(tabs.count) (\(tabs.values.filter(\.isLoaded).count) loaded)",
            "Running for \(uptime.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))",
        ]
        return lines.joined(separator: "\n")
    }

    private static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return model.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    private static func zip(_ folder: URL) async throws -> URL {
        let archive = folder.appendingPathExtension("zip")
        try? FileManager.default.removeItem(at: archive)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // No extended attributes: they'd show up as "._" files for whoever unzips it.
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noacl", "--keepParent", folder.path, archive.path]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return archive
    }
}
