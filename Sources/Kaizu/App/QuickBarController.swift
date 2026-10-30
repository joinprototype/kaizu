import AppKit
import SwiftUI

/// The command bar on its own, over whatever app you're in (Ghostty's quick
/// terminal, Raycast's launcher): a shortcut set in Settings → General
/// brings it up, answers show right there, pages open in a little window.
/// Esc, the shortcut again, or clicking elsewhere puts it away.
@MainActor
final class QuickBarController: NSObject, NSWindowDelegate {
    private let panel: QuickBarPanel
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private weak var store: BrowserStore?
    /// Room around the bar for its shadow.
    static let margin: CGFloat = 48

    init(store: BrowserStore) {
        self.store = store
        panel = QuickBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620 + Self.margin * 2, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// On the screen with the pointer, a little above the middle, where
    /// Spotlight sits.
    func show() {
        guard let store else { return }
        // A new identity each time: empty, nothing selected.
        hostingView.rootView = AnyView(CommandBar(mode: .quick, initialText: "").id(UUID()).environment(store))
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            let top = visible.maxY - visible.height * 0.18 + Self.margin
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: top - size.height))
        }
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.isReduced ? 0 : 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        // The bar stays in the hidden panel: this often runs from inside
        // its own text field's Return or Esc.
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

/// Borderless panels don't take the keyboard unless asked; this one types
/// without bringing Kaizu forward.
private final class QuickBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
