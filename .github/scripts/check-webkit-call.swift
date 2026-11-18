import AppKit
import WebKit

// Run the same WebRTC page in a plain WebKit view to distinguish browser-specific failures.
@main @MainActor enum CheckWebKitCall {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let url = URL(string: CommandLine.arguments[1])!
        let side = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "side" }?.value
        let screen = NSScreen.main!.visibleFrame
        let width = min(screen.width * 0.42, 560)
        let frame = NSRect(x: side == "A" ? screen.minX : screen.maxX - width, y: screen.minY,
                           width: width, height: min(screen.height * 0.55, 480))
        let view = WKWebView(frame: frame, configuration: configuration)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.level = .floating
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        app.activate()
        view.load(URLRequest(url: url))
        withExtendedLifetime(window) { app.run() }
    }
}
