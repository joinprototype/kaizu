import AppKit
import SwiftUI

/// Arc's "Little Arc": a small window for a quick look at a link, with one
/// click to promote it to a full tab. Private windows reuse it with an
/// in-memory profile that disappears when the window closes.
@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate {
    let tab: BrowserTab
    var isPrivate: Bool { tab.profile.isPrivate }
    private unowned let app: AppModel
    private var isPromoted = false

    init(tab: BrowserTab, app: AppModel) {
        self.tab = tab
        self.app = app
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 320)
        super.init(window: window)

        let view = LittleBrowserView(tab: tab) { [weak self] in self?.promote() }
        window.title = tab.profile.isPrivate ? "Private" : "Little Window"
        let hostingView = NSHostingView(rootView: FollowsFrontWindow(app: app, content: view))
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.delegate = self
        window.center()
        window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX + 40, y: window.frame.maxY - 40))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func promote() {
        guard !isPrivate else { return }
        isPromoted = true
        app.front.adopt(tab)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if !isPromoted {
            tab.discard()
        }
        app.littleWindows.removeAll { $0 === self }
    }
}
