import AppKit
import DesignSystem
import SwiftUI

/// Holding ⌘ on its own for a moment shows which tab each of ⌘1–9 goes to,
/// as Safari does.
extension BrowserStore {
    /// ⌘1–8 go to the first eight visible tabs, ⌘9 to the last.
    nonisolated static func tabNumber(at index: Int, of count: Int) -> Int? {
        guard index >= 0, index < count else { return nil }
        if index < 8 { return index + 1 }
        return index == count - 1 ? 9 : nil
    }

    func tabNumber(of tab: BrowserTab) -> Int? {
        let tabs = activeSpace.visibleTabs
        return tabs.firstIndex { $0 === tab }.flatMap { Self.tabNumber(at: $0, of: tabs.count) }
    }

    private static let held: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    func installTabNumberMonitor() {
        addEventMonitor(matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { store, event in
            if event.type == .flagsChanged, event.modifierFlags.intersection(Self.held) == .command {
                store.armTabNumbers()
            } else {
                store.hideTabNumbers()
            }
            return event
        }
    }

    /// Shown after half a second, so a quick ⌘ shortcut never flashes them.
    private func armTabNumbers() {
        tabNumberTask?.cancel()
        tabNumberTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled, isSidebarVisible, commandBar == nil, window?.isKeyWindow == true else { return }
            withAnimation(Motion.hover) { showsTabNumbers = true }
            // macOS keeps the release when ⌘ goes on to ⌘Tab or a system
            // shortcut, so this checks the keys rather than wait for it.
            while !Task.isCancelled, NSEvent.modifierFlags.intersection(Self.held) == .command,
                  NSApp.isActive, window?.isKeyWindow == true {
                try? await Task.sleep(for: .milliseconds(150))
            }
            if !Task.isCancelled { hideTabNumbers() }
        }
    }

    func hideTabNumbers() {
        tabNumberTask?.cancel()
        tabNumberTask = nil
        if showsTabNumbers {
            withAnimation(Motion.hover) { showsTabNumbers = false }
        }
    }
}

/// "⌘3" beside a tab while ⌘ is held.
struct TabNumberHint: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab

    var body: some View {
        if store.showsTabNumbers, let number = store.tabNumber(of: tab) {
            KeyCap(keys: "⌘\(number)", size: 10)
                .foregroundStyle(.secondary)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}
