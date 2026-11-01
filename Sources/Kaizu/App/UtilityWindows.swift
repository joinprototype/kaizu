import AppKit
import BrowserCore
import SwiftUI

/// One-per-app windows (Settings, History): created on first use, then
/// brought back to the front.
@MainActor
enum UtilityWindows {
    private static var windows: [String: NSWindow] = [:]

    static func showSettings(app: AppModel) {
        show("Settings", size: NSSize(width: 560, height: 460), app: app) { SettingsView() }
    }

    static func showHistory(app: AppModel) {
        show("History", size: NSSize(width: 620, height: 640), resizable: true, app: app) { HistoryView() }
    }

    static func showBugReport(app: AppModel) {
        show("Report a Bug", size: NSSize(width: 520, height: 430), app: app) { BugReportView() }
    }

    static func closeBugReport() {
        windows["Report a Bug"]?.close()
    }

    static func showBrokenSiteReport(tab: BrowserTab, url: URL, app: AppModel) {
        closeBrokenSiteReport()
        show("Report a Broken Site", size: NSSize(width: 480, height: 500), app: app) { BrokenSiteReportView(tab: tab, url: url) }
    }

    /// Forgotten: each report starts from its own page.
    static func closeBrokenSiteReport() {
        forget("Report a Broken Site")
    }

    static func showArcImport(app: AppModel, from source: URL = ArcSidebar.fileURL) {
        show("Import from Arc", size: NSSize(width: 460, height: 420), app: app) { ArcImportView(source: source) }
    }

    /// Forgotten: next time it reads Arc's sidebar afresh.
    static func closeArcImport() {
        forget("Import from Arc")
    }

    static func showBrowsingDataImport(app: AppModel) {
        show("Import Browsing Data", size: NSSize(width: 460, height: 460), app: app) { BrowsingDataImportView() }
    }

    /// Forgotten: next time it looks for browsers afresh.
    static func closeBrowsingDataImport() {
        forget("Import Browsing Data")
    }

    private static func forget(_ title: String) {
        windows[title]?.close()
        windows[title] = nil
    }

    private static func show(
        _ title: String,
        size: NSSize,
        resizable: Bool = false,
        app: AppModel,
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
        window.contentView = NSHostingView(rootView: FollowsFrontWindow(app: app, content: content()))
        window.center()
        window.setFrameAutosaveName("Kaizu\(title)Window")
        windows[title] = window
        window.makeKeyAndOrderFront(nil)
    }
}

/// For windows that outlive any one browser window: the one in front is
/// their store, whichever that is by now.
struct FollowsFrontWindow<Content: View>: View {
    let app: AppModel
    let content: Content

    var body: some View {
        content.environment(app.front)
    }
}
