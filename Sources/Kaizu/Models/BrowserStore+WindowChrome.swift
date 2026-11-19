import AppKit
import DesignSystem
import SwiftUI

extension BrowserStore {
    // MARK: - Window chrome

    func toggleSidebar() {
        // Views keep the transition they last rendered with, so a change of
        // transition has to render before the sidebar moves: then toggle.
        let docksFromPeek = !isSidebarVisible && isSidebarPeeking
        if sidebarDocksFromPeek != docksFromPeek {
            sidebarDocksFromPeek = docksFromPeek
            Task { @MainActor [weak self] in self?.toggleSidebar() }
            return
        }
        withAnimation(Motion.snap) {
            isSidebarVisible.toggle()
            isSidebarPeeking = false
        } completion: { [weak self] in
            self?.sidebarDocksFromPeek = false
        }
        updateWindowChrome()
        scheduleSave()
    }

    /// Opens after a short hover intent (so flicking the pointer to the
    /// window edge doesn't trigger it) and closes after a grace period (so a
    /// small overshoot past the sidebar doesn't snap it away).
    func setSidebarPeeking(_ peeking: Bool) {
        // A late "left" from a sidebar that already closed mustn't cancel a reopen.
        if !peeking, !isSidebarPeeking { return }
        peekTask?.cancel()
        guard !isSidebarVisible, peeking != isSidebarPeeking else { return }
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(peeking ? 120 : 280))
            guard !Task.isCancelled, let self, !self.isSidebarVisible else { return }
            self.applySidebarPeeking(peeking)
        }
    }

    /// The pointer left the window edge before the peek opened.
    func cancelSidebarPeek() {
        guard !isSidebarPeeking else { return }
        peekTask?.cancel()
    }

    private func applySidebarPeeking(_ peeking: Bool) {
        withAnimation(Motion.snap) {
            isSidebarPeeking = peeking
        }
        updateWindowChrome()
    }

    /// The active space's light or dark (or the system's), for the whole
    /// window, pages included.
    func updateWindowAppearance() {
        // Also runs while a session is being applied, when spaces may be empty.
        guard let window else { return }
        let appearance: NSAppearance? = switch previewAppearance ?? spaces.first(where: { $0.id == activeSpaceID })?.appearance ?? .auto {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        // Setting it redraws the whole window, so only when it changes
        // (most space switches keep it).
        guard window.appearance?.name != appearance?.name else { return }
        window.appearance = appearance
    }

    /// Traffic lights live in the sidebar; they fade with it when it's
    /// collapsed (and are hidden after, so they can't be clicked unseen).
    func updateWindowChrome(animated: Bool = true) {
        let hidden = !isSidebarVisible && !isSidebarPeeking
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window?.standardWindowButton(kind) else { continue }
            if !hidden { button.isHidden = false }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? 0.18 : 0
                button.animator().alphaValue = hidden ? 0 : 1
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isSidebarVisible, !self.isSidebarPeeking else { return }
                    button.isHidden = true
                }
            }
        }
    }
}
