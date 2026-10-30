import SwiftUI

/// The selected tab's split: panes side by side, the focused one outlined,
/// with dividers you can drag (double-click one to even them out). With one
/// pane it's just the page.
struct SplitContent: View {
    @Environment(BrowserStore.self) private var store
    let space: Space
    let panes: [BrowserTab]
    let focused: BrowserTab

    private static let gap: CGFloat = 8
    private static let minimumShare = 0.15

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width - Self.gap * CGFloat(panes.count - 1)
            let shares = shares
            HStack(spacing: Self.gap) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                    SplitPane(tab: pane, isFocused: pane === focused, isSplit: panes.count > 1, theme: space.theme)
                        .frame(width: max(available * shares[index], 0))
                        // Panes joining or leaving a split ease in and out;
                        // switching between lone pages stays instant.
                        .transition(panes.count > 1 ? .opacity.combined(with: .scale(scale: 0.98)) : .identity)
                        .overlay(alignment: .trailing) {
                            if index < panes.count - 1 {
                                SplitDivider(shares: shares) { start, distance in
                                    space.splitWidths = Self.resized(start, at: index, by: available > 0 ? distance / available : 0)
                                } onEnd: {
                                    store.scheduleSave()
                                } onReset: {
                                    space.splitWidths = []
                                    store.scheduleSave()
                                }
                                .offset(x: Self.gap / 2 + 6)
                            }
                        }
                }
            }
        }
    }

    private var shares: [Double] {
        space.splitWidths.count == panes.count
            ? space.splitWidths
            : Array(repeating: 1 / Double(panes.count), count: panes.count)
    }

    /// `start` with the divider after pane `index` moved by `fraction` of the width.
    private static func resized(_ start: [Double], at index: Int, by fraction: Double) -> [Double] {
        let pair = start[index] + start[index + 1]
        let left = min(max(start[index] + fraction, minimumShare), pair - minimumShare)
        var widths = start
        widths[index] = left
        widths[index + 1] = pair - left
        return widths
    }
}

/// The draggable strip in the gap between two panes.
private struct SplitDivider: View {
    let shares: [Double]
    /// The shares when the drag began, and how far it has moved since.
    let onDrag: (_ start: [Double], _ distance: Double) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void
    @GestureState private var dragStart: [Double]?

    var body: some View {
        Color.clear
            .frame(width: 12)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                // GestureState resets itself, even when the drag is cancelled.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($dragStart) { _, start, _ in start = start ?? shares }
                    .onChanged { value in onDrag(dragStart ?? shares, value.translation.width) }
                    .onEnded { _ in onEnd() }
            )
            .onTapGesture(count: 2) { withAnimation(Motion.snap) { onReset() } }
    }
}

private struct SplitPane: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let tab: BrowserTab
    let isFocused: Bool
    let isSplit: Bool
    let theme: Theme
    @State private var isHovering = false

    var body: some View {
        PageView(tab: tab, accent: theme.accent(scheme), splitDrop: store.splitDrop(onto: tab))
            .overlay {
                if let reader = store.reader, reader.tabID == tab.id {
                    ReaderView(article: reader)
                        .id(reader.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                AddExtensionOverlay(tab: tab)
            }
            .overlay {
                if store.capture == tab.id {
                    CaptureOverlay()
                }
            }
            .overlay(alignment: .top) {
                if store.hidingItemsTabID == tab.id {
                    HidingItemsHint()
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .pageCard(shadow: false)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.accent(scheme).opacity(isSplit && isFocused ? 0.9 : 0), lineWidth: 2)
                    .animation(Motion.snap, value: isFocused)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if isSplit, isHovering, store.capture != tab.id {
                    IconButton(systemName: "xmark", help: "Remove from Split View") { store.removeFromSplit(tab) }
                        .background(Surface.elevated(scheme).opacity(0.9), in: Circle())
                        .padding(8)
                }
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .onHoverFade($isHovering)
    }
}
