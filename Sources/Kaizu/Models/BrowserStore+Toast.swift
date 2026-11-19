import SwiftUI

/// A short message at the bottom of the window, optionally with Undo.
struct Toast: Identifiable {
    let id = UUID()
    var message: String
    var symbol: String?
    var undo: (@MainActor () -> Void)?
    var actionTitle = "Undo"
}

extension BrowserStore {
    func showToast(
        _ message: String,
        symbol: String? = nil,
        undo: (@MainActor () -> Void)? = nil,
        actionTitle: String = "Undo",
        lasts: Duration? = nil
    ) {
        toastTask?.cancel()
        // The same kind of toast again (zoom steps) changes in place.
        if var current = toast, current.symbol == symbol, current.undo == nil, undo == nil {
            current.message = message
            withAnimation(Motion.snap) { toast = current }
        } else {
            withAnimation(Motion.pop) {
                toast = Toast(message: message, symbol: symbol, undo: undo, actionTitle: actionTitle)
            }
        }
        toastTask = Task { [weak self] in
            // Leave time to reach for Undo.
            try? await Task.sleep(for: lasts ?? .seconds(undo == nil ? 1.6 : 4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.snap) {
                self?.toast = nil
            }
        }
    }

    func undoToast() {
        let undo = toast?.undo
        withAnimation(Motion.snap) {
            toast = nil
        }
        undo?()
    }
}
