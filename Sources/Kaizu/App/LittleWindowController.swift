import AppKit
import SwiftUI

/// Arc's "Little Arc": a small window for a quick look at a link, with one
/// click to promote it to a full tab.
@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate {
    let tab: BrowserTab
    private unowned let app: AppModel
    private weak var openingWindow: BrowserStore?
    private let openingSpaceID: UUID
    private var isPromoted = false

    init(tab: BrowserTab, openedFrom store: BrowserStore) {
        self.tab = tab
        app = store.app
        openingWindow = store
        openingSpaceID = store.activeSpace.id
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
        window.title = "Little Window"
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
        guard !isPromoted, app.littleWindows.contains(where: { $0 === self }) else { return }
        let from = app.stores.first { $0 === openingWindow } ?? app.regularFront
        guard let space = app.spaces.first(where: { $0.id == openingSpaceID }) ?? from.space(on: tab.profile),
              space.profile === tab.profile else {
            close()
            return
        }
        isPromoted = true
        from.windowForOpening(in: space).adopt(tab, in: space)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if !isPromoted {
            tab.discard()
        }
        app.littleWindows.removeAll { $0 === self }
    }
}
