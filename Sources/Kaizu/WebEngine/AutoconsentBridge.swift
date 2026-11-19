import BrowserCore
import DesignSystem
import OSLog
import WebKit

/// Rejects cookie pop-ups with DuckDuckGo's autoconsent, the way DuckDuckGo's
/// own browsers and extension run it.
///
/// The library alone, 110 KB, runs in WebKit's isolated client world in
/// every frame, the world Kaizu's media script already
/// creates there, so it costs no extra world. Pages can't see or tamper with
/// it. Each frame asks this handler for its rules, and gets only those that
/// can apply to its address (`Autoconsent.Rules`). Checks that must read the
/// page's own globals are run here, in the page's world, by snippet id only:
/// see `Autoconsent.Snippets` for the trust boundary.
final class AutoconsentBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "kaizuAutoconsent"
    /// Where the script runs, and where debug builds read what it did.
    static var world: WKContentWorld { .defaultClient }

    /// Runs in every frame: many consent pop-ups live in iframes.
    static let script: WKUserScript? = {
        guard let url = BundledResource.url(named: "autoconsent-isolated", extension: "js", in: "Scripts"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)
    }()

    /// Parsed once, off the main thread when `warmUp` gets there first.
    nonisolated static let rules: Autoconsent.Rules? = load("autoconsent-rules") { try Autoconsent.Rules(data: $0) }
    nonisolated static let snippets: Autoconsent.Snippets? = load("autoconsent-snippets") { try Autoconsent.Snippets(data: $0) }
    private static let shared = AutoconsentBridge()
    private static let log = Logger(subsystem: Log.subsystem, category: "Autoconsent")

    #if DEBUG
    /// What frames were sent, for QA hooks.
    static var framesServed = 0
    static var mainFramesServed = 0
    static var bytesServed = 0
    static var evaluations = 0
    #endif

    private nonisolated static func load<T>(_ name: String, _ parse: (Data) throws -> T) -> T? {
        guard let url = BundledResource.url(named: name, extension: "json", in: "Scripts") else {
            Logger(subsystem: Log.subsystem, category: "Autoconsent").error("Missing \(name, privacy: .public).json")
            return nil
        }
        do {
            return try parse(Data(contentsOf: url))
        } catch {
            Logger(subsystem: Log.subsystem, category: "Autoconsent").error("Unreadable \(name, privacy: .public).json: \(error, privacy: .public)")
            return nil
        }
    }

    /// Reads the rules in the background, before the first page asks.
    static func warmUp() {
        Task.detached(priority: .utility) {
            _ = rules
            _ = snippets
        }
    }

    /// Once per content controller; the script itself comes and goes with
    /// the setting, through the content blocker.
    static func install(on controller: WKUserContentController) {
        controller.addScriptMessageHandler(shared, contentWorld: world, name: handlerName)
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        switch Autoconsent.Message(message.body) {
        case .initialize(let url):
            guard let rules = Self.rules else { return replyHandler(nil, "no rules") }
            let reply = Autoconsent.initReply(rules: rules, url: url, mainFrame: message.frameInfo.isMainFrame)
            #if DEBUG
            Self.framesServed += 1
            Self.mainFramesServed += message.frameInfo.isMainFrame ? 1 : 0
            Self.bytesServed += reply.utf8.count
            #endif
            replyHandler(reply, nil)
        case .evaluate(let id, let snippet):
            func answer(_ result: Bool) {
                replyHandler(["type": "evalResp", "id": id, "result": result], nil)
            }
            guard let script = Self.snippets?.script(for: snippet) else {
                Self.log.error("Unknown autoconsent snippet \(snippet, privacy: .public)")
                return answer(false)
            }
            guard let webView = message.webView else { return answer(false) }
            #if DEBUG
            Self.evaluations += 1
            #endif
            webView.evaluateJavaScript(script, in: message.frameInfo, in: .page) { result in
                answer((try? result.get()) as? Bool ?? false)
            }
        case nil:
            replyHandler(nil, "unknown message")
        }
    }
}
