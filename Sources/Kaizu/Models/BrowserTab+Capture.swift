import AppKit
import WebKit

extension BrowserTab {
    func printPage() {
        guard let _webView, let window = _webView.window else { return }
        let operation = _webView.printOperation(with: .shared)
        // WKWebView's print view starts with a zero frame and prints blank pages otherwise.
        operation.view?.frame = _webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    /// Saves the whole page as one PDF, asking where (Safari's Export as PDF).
    func exportPDF() {
        guard let _webView, let window = _webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = displayTitle.replacingOccurrences(of: "/", with: "-") + ".pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                do {
                    try await _webView.pdf().write(to: destination, options: .atomic)
                } catch {
                    let alert = NSAlert(error: error)
                    alert.messageText = "Couldn't export the page as PDF"
                    alert.beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }

    /// The visible part of the page (or `rect` of it, in the view's
    /// top-left-origin points), as an image.
    func screenshot(of rect: CGRect? = nil) async -> NSImage? {
        guard let _webView, _webView.window != nil else { return nil }
        let configuration = WKSnapshotConfiguration()
        if let rect {
            configuration.rect = rect
        }
        return try? await _webView.takeSnapshot(configuration: configuration)
    }

    /// Snapshots the page for the ⌃Tab switcher. Call while it's on screen.
    func captureThumbnail() {
        guard let _webView, _webView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        Task {
            if let image = try? await _webView.takeSnapshot(configuration: configuration) {
                thumbnail = image
            }
        }
    }
}
