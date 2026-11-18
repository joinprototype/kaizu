import AppKit
import WebKit

@MainActor
final class StorageControl: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        guard Bundle.main.bundleIdentifier?.hasPrefix("dev.kaizu.qa.webkit-storage.") == true,
              arguments.count == 3, let profile = UUID(uuidString: arguments[1]),
              let url = URL(string: arguments[2]), url.scheme == "http", url.host == "127.0.0.1"
        else { exit(64) }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile)
        let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let view = WKWebView(frame: frame, configuration: configuration)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.window = window
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.load(URLRequest(url: url))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = StorageControl()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
