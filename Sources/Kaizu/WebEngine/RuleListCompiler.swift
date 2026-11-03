import BrowserCore
import CryptoKit
import OSLog
import WebKit

/// Compiles filter lists in a short-lived copy of the app. A compile peaks near
/// 600 MB and malloc holds on to about 230 MB of it afterwards, which only
/// comes back when the process that did the work exits.
///
/// The helper is this same binary, started with an argument and stopped before
/// `NSApplication`, so it has no Dock icon and shares the app's rule list store.
@MainActor
enum RuleListCompiler {
    private static let argument = "--compile-rule-list"
    /// A list takes seconds. One that's stuck can't hold up the others.
    private static let helperLimit: Duration = .seconds(120)
    private static let log = Logger(subsystem: Log.subsystem, category: "RuleListCompiler")

    /// The list this process was started to compile, when it's the helper.
    static var requestedList: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// The helper's whole run.
    static func runAndExit(list name: String) -> Never {
        Task {
            var compiled = false
            if let store = WKContentRuleListStore.default(), let text = FilterListUpdater.text(for: name) {
                compiled = await compile(name, text: text, into: store) != nil
            }
            exit(compiled ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        // Not `dispatchMain`: WebKit answers through the main run loop.
        while true { RunLoop.main.run() }
    }

    /// Starts the helper and waits for it. On true the list is in the store.
    static func compileInHelper(_ name: String) async -> Bool {
        guard let executable = Bundle.main.executableURL else { return false }
        let helper = Process()
        helper.executableURL = executable
        helper.arguments = [argument, name]
        helper.qualityOfService = .utility
        return await withCheckedContinuation { continuation in
            helper.terminationHandler = { continuation.resume(returning: $0.terminationStatus == EXIT_SUCCESS) }
            do {
                try helper.run()
            } catch {
                return continuation.resume(returning: false)
            }
            Task {
                try? await Task.sleep(for: helperLimit)
                if helper.isRunning { helper.terminate() }
            }
        }
    }

    static func compile(_ name: String, text: String, into store: WKContentRuleListStore) async -> WKContentRuleList? {
        let started = ContinuousClock.now
        let output = await Task.detached(priority: .utility) {
            let output = FilterListConverter.convert(text)
            return (json: try? output.rules.encodedJSON(), count: output.rules.count, skipped: output.skipped)
        }.value
        guard let json = output.json else { return nil }
        do {
            let list = try await store.compileContentRuleList(forIdentifier: identifier(for: name, text: text), encodedContentRuleList: json)
            log.info("Compiled \(name, privacy: .public): \(output.count) rules, \(output.skipped) skipped, \(started.duration(to: .now), privacy: .public)")
            return list
        } catch {
            let reason = (error as NSError).userInfo[NSHelpAnchorErrorKey] as? String ?? error.localizedDescription
            log.error("Couldn't compile \(name, privacy: .public): \(reason, privacy: .public)")
            return nil
        }
    }

    /// Keyed by contents and converter version, so WebKit's cached copy is only
    /// used while it still matches.
    static func identifier(for name: String, text: String) -> String {
        let fingerprint = SHA256.hash(data: Data(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(name)-v\(FilterListConverter.version)-\(fingerprint)"
    }
}
