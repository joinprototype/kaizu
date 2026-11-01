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
            window.setFrameAutosaveName(Self.frameName)
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

    /// This window became the first: its frame is the one autosaved now,
    /// without moving it to where the old first window was.
    func takeAutosavedFrame() {
        window?.saveFrame(usingName: Self.frameName)
        window?.setFrameAutosaveName(Self.frameName)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        store.app.windowDidBecomeKey(store)
    }

    func windowWillClose(_ notification: Notification) {
        store.app.windowDidClose(store)
    }
}
