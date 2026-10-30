import AppKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSWindowController {
    init(store: BrowserStore) {
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
        window.setFrameAutosaveName("KaizuBrowserWindow")

        super.init(window: window)
        store.window = window
        store.updateWindowChrome(animated: false)
        store.updateWindowAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
