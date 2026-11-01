import AppKit
import BrowserCore
import SwiftUI

/// One-per-app windows (Settings, History): created on first use, then
/// brought back to the front.
@MainActor
enum UtilityWindows {
    private static var windows: [String: NSWindow] = [:]

    static func showSettings(store: BrowserStore) {
        show("Settings", size: NSSize(width: 560, height: 460), store: store) { SettingsView() }
    }

    static func showHistory(store: BrowserStore) {
        show("History", size: NSSize(width: 620, height: 640), resizable: true, store: store) { HistoryView() }
    }

    static func showBugReport(store: BrowserStore) {
        show("Report a Bug", size: NSSize(width: 520, height: 430), store: store) { BugReportView() }
    }

    static func closeBugReport() {
        windows["Report a Bug"]?.close()
    }

    static func showBrokenSiteReport(tab: BrowserTab, url: URL, store: BrowserStore) {
        closeBrokenSiteReport()
        show("Report a Broken Site", size: NSSize(width: 480, height: 500), store: store) { BrokenSiteReportView(tab: tab, url: url) }
    }

    /// Forgotten, not just closed: each report starts from its own page.
    static func closeBrokenSiteReport() {
        windows["Report a Broken Site"]?.close()
        windows["Report a Broken Site"] = nil
    }

    static func showArcImport(store: BrowserStore, from source: URL = ArcSidebar.fileURL) {
        show("Import from Arc", size: NSSize(width: 460, height: 420), store: store) { ArcImportView(source: source) }
    }

    /// Forgotten, not just closed: next time it reads Arc's sidebar afresh.
    static func closeArcImport() {
        windows["Import from Arc"]?.close()
        windows["Import from Arc"] = nil
    }

    static func showBrowsingDataImport(store: BrowserStore) {
        show("Import Browsing Data", size: NSSize(width: 460, height: 460), store: store) { BrowsingDataImportView() }
    }

    /// Forgotten, not just closed: next time it looks for browsers afresh.
    static func closeBrowsingDataImport() {
        windows["Import Browsing Data"]?.close()
        windows["Import Browsing Data"] = nil
    }

    private static func show(
        _ title: String,
        size: NSSize,
        resizable: Bool = false,
        store: BrowserStore,
        @ViewBuilder content: () -> some View
    ) {
        if let window = windows[title] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable {
            style.formUnion([.resizable, .miniaturizable])
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content().environment(store))
        window.center()
        window.setFrameAutosaveName("Kaizu\(title)Window")
        windows[title] = window
        window.makeKeyAndOrderFront(nil)
    }
}
