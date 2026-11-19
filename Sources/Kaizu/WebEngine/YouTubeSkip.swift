import AppKit
import DesignSystem
import WebKit

/// Presses YouTube's Skip button with a real click when an ad offers it.
///
/// YouTube ignores a press made from script, so `youtube-skip.js` (in the
/// isolated client world, out of the page's reach) reports where the hidden
/// button is and this sends the web view a mouse click there. It only
/// clicks for YouTube's main frame, at most once a second, and only while
/// the web view itself has focus, so it can never take the keyboard from
/// the address bar or another field the user is typing in. In full screen
/// it leaves the ad to youtube-ads.js, which runs it through quickly.
final class YouTubeSkip: NSObject, WKScriptMessageHandler {
    static let handlerName = "kaizuYouTubeSkip"
    static var world: WKContentWorld { .defaultClient }

    static let script: WKUserScript? = {
        guard let url = BundledResource.url(named: "youtube-skip", extension: "js", in: "Scripts"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world)
    }()

    private static let shared = YouTubeSkip()
    private var lastClick = ContinuousClock.now - .seconds(10)

    #if DEBUG
    /// Clicks sent, for QA hooks.
    static var clicks = 0
    #endif

    /// Once per content controller; the script comes and goes with blocking,
    /// through the content blocker.
    static func install(on controller: WKUserContentController) {
        controller.add(shared, contentWorld: world, name: handlerName)
    }

    nonisolated static func isYouTube(_ host: String) -> Bool {
        host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == "https", Self.isYouTube(origin.host),
              let webView = message.webView, let window = webView.window,
              // In full screen the page is drawn in another window, where
              // this point wouldn't land on the button.
              webView.fullscreenState == .notInFullscreen,
              let body = message.body as? [String: Any],
              let x = (body["x"] as? NSNumber)?.doubleValue, let y = (body["y"] as? NSNumber)?.doubleValue,
              x.isFinite, y.isFinite,
              ContinuousClock.now - lastClick > .milliseconds(900)
        else { return }
        // Never while the user is typing somewhere else in the window.
        if let responder = window.firstResponder, responder !== window,
           (responder as? NSView)?.isDescendant(of: webView) != true {
            return
        }
        let zoom = webView.pageZoom
        let local = NSPoint(x: x * zoom, y: webView.isFlipped ? y * zoom : webView.bounds.height - y * zoom)
        guard webView.bounds.contains(local) else { return }
        lastClick = .now
        Self.click(at: webView.convert(local, to: nil), in: webView, window: window)
    }

    private static func click(at point: NSPoint, in webView: WKWebView, window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ) else { return }
            if type == .leftMouseDown {
                webView.mouseDown(with: event)
            } else {
                webView.mouseUp(with: event)
            }
        }
        #if DEBUG
        clicks += 1
        #endif
    }
}
