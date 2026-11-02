import AppKit
import BrowserCore
import WebKit

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let store else { return nil }
        if let destination = linkDestination {
            linkDestination = nil
            if let url = navigationAction.request.url {
                store.open(url, at: destination, from: self)
            }
            return nil
        }
        let tab = store.openTab(navigationAction.request.url, after: self, configuration: configuration)
        return tab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        store?.close(self)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        guard let window = webView.window else { return completionHandler(nil) }
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    /// Camera and microphone: ask once per site and remember the answer
    /// (except in private windows), instead of WebKit asking on every visit.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let devices = switch type {
        case .camera: ["camera"]
        case .microphone: ["microphone"]
        default: ["camera", "microphone"]
        }
        decidePermission(for: origin.host, devices: devices, decisionHandler: decisionHandler)
    }

    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        decidePermission(for: origin.host, devices: ["location"], decisionHandler: decisionHandler)
    }

    /// Uses a remembered answer, or asks with "Remember for this site".
    /// Answers are shared by every profile, like Safari's website settings;
    /// private windows always ask and never remember.
    private func decidePermission(
        for host: String,
        devices: [String],
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard let settings = app?.settings else { return decisionHandler(.prompt) }
        let remembers = !profile.isPrivate
        if remembers {
            let remembered = devices.map { settings.sitePermissions[host]?[$0] }
            if remembered.allSatisfy({ $0 == true }) { return decisionHandler(.grant) }
            if remembered.contains(false) { return decisionHandler(.deny) }
        }

        let alert = NSAlert()
        alert.messageText = "Allow “\(host)” to use your \(devices.joined(separator: " and "))?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        if remembers {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Remember for this site"
            alert.suppressionButton?.state = .on
        }
        present(alert) { response in
            let allowed = response == .alertFirstButtonReturn
            if remembers, response != .abort, alert.suppressionButton?.state == .on {
                for device in devices {
                    settings.setPermission(device, to: allowed, on: host)
                }
            }
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    func confirmOpeningApp(for target: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: target) else { return }
        let alert = NSAlert()
        alert.messageText = "Open “\(FileManager.default.displayName(atPath: app.path))”?"
        alert.informativeText = "\(url?.displayHost ?? "This page") wants to open this application."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(target)
            }
        }
    }

    /// Shows the alert as a sheet on the tab's window. Pages in the
    /// background get `.abort` instead: an app-modal dialog from a tab you
    /// can't see would freeze the whole browser.
    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard isLoaded, let window = webView.window else { return completion(.abort) }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }
}
