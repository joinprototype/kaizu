import AppKit
import WebKit

@MainActor
final class StorageControl: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private var mode = "quit"
    private var pageExit: WKNavigation?
    private weak var view: WKWebView?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        guard Bundle.main.bundleIdentifier?.hasPrefix("dev.kaizu.qa.webkit-storage.") == true,
              arguments.count == 4, ["quit", "hold", "navigate", "drain"].contains(arguments[3]), let profile = UUID(uuidString: arguments[1]),
              let url = URL(string: arguments[2]), url.scheme == "http", url.host == "127.0.0.1"
        else { exit(64) }

        mode = arguments[3]
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "report")
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile)
        let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let view = WKWebView(frame: frame, configuration: configuration)
        self.view = view
        view.navigationDelegate = self
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
        if mode != "hold" { NSApp.terminate(nil) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard mode == "navigate" || mode == "drain" else { return .terminateNow }
        guard let view else { exit(66) }
        if pageExit == nil {
            pageExit = view.loadHTMLString("<title>Closing</title>", baseURL: nil)
            guard pageExit != nil else { exit(67) }
        }
        return .terminateLater
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let pageExit, navigation === pageExit else { return }
        FileHandle.standardOutput.write(Data("navigated\n".utf8))
        Task { @MainActor in
            if mode == "drain" { try? await Task.sleep(for: .milliseconds(750)) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = StorageControl()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
