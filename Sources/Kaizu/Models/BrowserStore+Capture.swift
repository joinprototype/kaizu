import AppKit
import SwiftUI

/// ⇧⌘2, Arc's Capture: the page dims, and the area you drag over is copied
/// as an image. Enter copies everything visible; Esc cancels.
extension BrowserStore {
    /// Pages the overlay can't sit on (little windows, under a peek or
    /// Reader) are copied whole straight away.
    func beginCapture(of tab: BrowserTab) {
        guard tab === selectedTab, peek == nil, reader == nil, window?.isKeyWindow == true else {
            return copyScreenshot(of: tab)
        }
        withAnimation(Motion.snap) { capture = tab.id }
    }

    /// Copies `rect` of the captured page, in its points (nil: all of it).
    func finishCapture(_ rect: CGRect? = nil) {
        guard let id = capture else { return }
        cancelCapture()
        if let tab = activeSpace.allTabs.first(where: { $0.id == id }) {
            copyScreenshot(of: tab, rect: rect)
        }
    }

    func cancelCapture() {
        withAnimation(Motion.snap) { capture = nil }
    }

    func copyScreenshot(of tab: BrowserTab? = nil, rect: CGRect? = nil) {
        guard let tab = tab ?? selectedTab else { return }
        Task {
            guard let image = await tab.screenshot(of: rect) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            showToast("Capture copied", symbol: "camera.viewfinder")
        }
    }
}
