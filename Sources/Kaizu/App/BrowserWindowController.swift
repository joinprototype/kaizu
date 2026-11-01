import AppKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    private static let frameName = "KaizuBrowserWindow"
    private let store: BrowserStore

    init(store: BrowserStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Kaizu"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 420)

        let hostingView = NSHostingView(rootView: BrowserView().environment(store))
        hostingView.sizingOptions = []
        window.contentView = hostingView

        window.center()
        if let frame = store.savedFrame {
            window.setFrame(from: frame)
        } else if store === store.app.stores[0] {
            // Where sessions from before several windows left it.
            window.setFrameUsingName(Self.frameName)
        }

        super.init(window: window)
        window.delegate = self
        store.windowController = self
        store.window = window
        store.updateWindowChrome(animated: false)
        store.updateWindowAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        store.app.windowDidBecomeKey(store)
    }

    func windowDidMove(_ notification: Notification) {
        store.app.scheduleSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        store.app.scheduleSave()
    }

    func windowWillClose(_ notification: Notification) {
        store.app.windowDidClose(store)
    }
}
