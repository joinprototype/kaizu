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
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let view = WKWebView(frame: frame, configuration: configuration)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        app.activate()
        view.load(URLRequest(url: URL(string: CommandLine.arguments[1])!))
        withExtendedLifetime(window) { app.run() }
    }
}
