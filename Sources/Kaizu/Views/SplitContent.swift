import BrowserCore
import SwiftUI

/// The selected tab's split: panes in rows and columns in any mix, the focused
/// one outlined, with dividers you can drag (double-click one to even out its
/// row). With one pane it's just the page. Panes are siblings here whatever the
/// layout's shape, so changing it moves pages and never rebuilds them.
struct SplitContent: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let space: Space
    let panes: [BrowserTab]
    let focused: BrowserTab
    /// A sidebar tab being dragged over a pane, and where it would land.
    @State private var drop: (tab: UUID, place: SplitPlace)?

    private static let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let layout = space.layout(of: panes)
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let shape = layout.geometry(in: bounds, gap: Self.gap)
            ZStack {
                ForEach(panes, id: \.id) { pane in
                    if let frame = shape.panes[pane.id] {
                        SplitPane(tab: pane, isFocused: pane === focused, isSplit: panes.count > 1, theme: space.theme) { point in
                            shape.place(at: point, on: pane.id)
                        } onDropHover: { hover in
                            withAnimation(Motion.snap) { drop = hover }
                        }
                        .frame(width: frame.width, height: frame.height)
                        // Panes joining or leaving a split ease in and out;
                        // switching between lone pages stays instant.
                        .transition(panes.count > 1 ? Motion.dissolving(.opacity.combined(with: .scale(scale: 0.98))) : .identity)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
                ForEach(shape.dividers) { divider in
                    SplitDivider(divider: divider, layout: layout) { start, distance in
                        space.splitLayout = start.resized(divider, by: distance)
                    } onEnd: {
                        store.scheduleSave()
                    } onReset: {
                        space.splitLayout = layout.evened(divider)
                        store.scheduleSave()
                    }
                    .position(x: divider.frame.midX, y: divider.frame.midY)
                }
                if let drop, let frame = layout.placing(drop.tab, at: drop.place).geometry(in: bounds, gap: Self.gap).panes[drop.tab] {
                    SplitDropPreview(frame: frame.insetBy(dx: 6, dy: 6), accent: space.theme.accent(scheme))
                }
            }
        }
        // A drag's end goes unheard if its page leaves first.
        .onChange(of: panes) { drop = nil }
    }
}

/// The room a dragged tab would take.
private struct SplitDropPreview: View {
    let frame: CGRect
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(accent.opacity(0.10))
            .strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .animation(Motion.glide, value: frame)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// The draggable strip in the gap between two panes.
private struct SplitDivider: View {
    let divider: SplitNode.Divider
    let layout: SplitNode
    /// The layout when the drag began, and how far it has moved since.
    let onDrag: (_ start: SplitNode, _ distance: Double) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void
    @GestureState private var dragStart: SplitNode?

    private var isStacked: Bool { divider.direction == .stacked }

    var body: some View {
        Color.clear
            .frame(width: isStacked ? divider.frame.width : 12, height: isStacked ? 12 : divider.frame.height)
            .contentShape(Rectangle())
            .pointerStyle(isStacked ? .rowResize : .columnResize)
            .gesture(
                // GestureState resets itself, even when the drag is cancelled.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($dragStart) { _, start, _ in start = start ?? layout }
                    .onChanged { value in
                        onDrag(dragStart ?? layout, isStacked ? value.translation.height : value.translation.width)
                    }
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
    let place: (CGPoint) -> SplitPlace
    let onDropHover: ((tab: UUID, place: SplitPlace)?) -> Void
    @State private var isHovering = false

    private var drop: SplitDrop {
        SplitDrop(
            accepts: { [weak store] id in store?.canSplit(tab, with: id) ?? false },
            place: place,
            perform: { [weak store] id, place in store?.split(tab, with: id, at: place) },
            hover: onDropHover
        )
    }

    var body: some View {
        PageView(tab: tab, accent: theme.accent(scheme), splitDrop: drop)
            .overlay {
                if let reader = store.reader, reader.tabID == tab.id {
                    ReaderView(article: reader)
                        .id(reader.id)
                        .transition(Motion.dissolving(.opacity.combined(with: .scale(scale: 0.99))))
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
                        .transition(Motion.dissolving(.move(edge: .top).combined(with: .opacity)))
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
