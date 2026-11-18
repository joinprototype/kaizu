import AppKit
import WebKit

@MainActor
final class StorageControl: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private var quitOnReport = false
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        guard Bundle.main.bundleIdentifier?.hasPrefix("dev.kaizu.qa.webkit-storage.") == true,
              arguments.count == 4, ["quit", "hold"].contains(arguments[3]), let profile = UUID(uuidString: arguments[1]),
              let url = URL(string: arguments[2]), url.scheme == "http", url.host == "127.0.0.1"
        else { exit(64) }

        quitOnReport = arguments[3] == "quit"
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "report")
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile)
        let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let view = WKWebView(frame: frame, configuration: configuration)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.window = window
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.load(URLRequest(url: url))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? String,
              ["match", "previous", "missing", "different", "error"].contains(value) else { exit(65) }
        FileHandle.standardOutput.write(Data((value + "\n").utf8))
        if quitOnReport { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = StorageControl()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
