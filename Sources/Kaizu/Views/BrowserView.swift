import SwiftUI

/// Window root: tinted backdrop, sidebar on the left, page card on the right.
struct BrowserView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        @Bindable var store = store
        let space = store.activeSpace

        ZStack(alignment: .topLeading) {
            SpaceBackdrop()

            HStack(spacing: 0) {
                if store.isSidebarVisible {
                    SidebarView(space: space)
                        .frame(width: store.sidebarWidth)
                        .overlay(alignment: .trailing) { SidebarResizeHandle() }
                        .transition(store.sidebarDocksFromPeek ? .identity : .move(edge: .leading).combined(with: .opacity))
                }
                ContentArea(space: space)
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
                    .padding(.leading, store.isSidebarVisible ? 0 : 8)
            }

            if !store.isSidebarVisible {
                peekingSidebar(space)
            }

            // The scrim fades; only the bar itself scales.
            if store.commandBar != nil {
                Surface.scrim(scheme)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if let mode = store.commandBar {
                CommandBar(
                    mode: mode,
                    initialText: mode == .currentTab ? store.selectedTab?.url?.absoluteString ?? "" : ""
                )
                .id(mode)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            if let switcher = store.tabSwitcher {
                TabSwitcherOverlay(state: switcher)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                ToastView(toast: toast) { store.undoToast() }
                    .id(toast.id)
                    .padding(.bottom, 28)
                    .transition(.offset(y: 12).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .sheet(item: $store.spaceDraft) { draft in
            SpaceEditor(draft: draft)
                .environment(store)
        }
    }

    /// Arc-style: with the sidebar hidden, hovering the left edge slides it in over the page.
    @ViewBuilder
    private func peekingSidebar(_ space: Space) -> some View {
        Color.clear
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { $0 ? store.setSidebarPeeking(true) : store.cancelSidebarPeek() }

        if store.isSidebarPeeking {
            SidebarView(space: space)
                .frame(width: store.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(space.theme.backdrop(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 18, x: 4)
                .padding([.vertical, .leading], 4)
                .onHover { store.setSidebarPeeking($0) }
                .transition(store.sidebarDocksFromPeek ? .identity : .move(edge: .leading).combined(with: .opacity))
        }
    }
}

private struct SidebarResizeHandle: View {
    @Environment(BrowserStore.self) private var store
    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? store.sidebarWidth
                        startWidth = start
                        store.sidebarWidth = min(max(start + value.translation.width, 200), 420)
                    }
                    .onEnded { _ in
                        startWidth = nil
                        store.scheduleSave()
                    }
            )
    }
}

/// The window's backdrop. Switching spaces blends its colors, following the
/// fingers during a swipe, instead of cross-fading two gradients (which
/// dips through grey halfway).
private struct SpaceBackdrop: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.self) private var environment

    var body: some View {
        var colors = resolved(store.previewTheme ?? store.activeSpace.theme)
        if let revealing = store.revealingSpace, store.spaceSwipeOffset != 0 {
            let progress = Float(min(abs(store.spaceSwipeOffset) / store.sidebarWidth, 1))
            colors = zip(colors, resolved(revealing.theme)).map { from, to in
                var mixed = from
                mixed.animatableData += (to.animatableData - from.animatableData).scaled(by: Double(progress))
                return mixed
            }
        }
        return BlendedGradient(start: colors[0], end: colors[colors.count - 1])
    }

    private func resolved(_ theme: Theme) -> [Color.Resolved] {
        theme.variant(scheme).backdrop.map { $0.resolve(in: environment) }
    }
}

private struct BlendedGradient: View, Animatable {
    var start: Color.Resolved
    var end: Color.Resolved

    nonisolated var animatableData: AnimatablePair<Color.Resolved.AnimatableData, Color.Resolved.AnimatableData> {
        get { AnimatablePair(start.animatableData, end.animatableData) }
        set {
            start.animatableData = newValue.first
            end.animatableData = newValue.second
        }
    }

    var body: some View {
        LinearGradient(colors: [Color(start), Color(end)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
