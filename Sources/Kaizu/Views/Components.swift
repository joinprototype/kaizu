import SwiftUI

struct IconButton: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    let systemName: String
    var help = ""
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovering && isEnabled ? SidebarFill.hover(scheme) : .clear)
                        .animation(Motion.hover, value: isHovering)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isEnabled ? 1 : 0.4)
        .onHoverFade($isHovering)
        .help(help)
    }
}

/// Empty sidebar space acts like a title bar: drag to move the window.
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }
}

struct ToastView: View {
    @Environment(\.colorScheme) private var scheme
    let toast: Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let symbol = toast.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
            Text(toast.message)
                .contentTransition(.numericText())
            if toast.undo != nil {
                Divider().frame(height: 14)
                Button(toast.actionTitle, action: onUndo)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Surface.elevated(scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(Surface.hairline(scheme)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// A keyboard key ("⌘T", "esc") drawn as a little cap.
struct KeyCap: View {
    let keys: String
    var size: CGFloat = 12

    var body: some View {
        Text(keys)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .padding(.horizontal, size * 0.55)
            .padding(.vertical, size * 0.2)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: size * 0.4))
    }
}

extension View {
    /// Tracks the pointer with the standard hover fade, so whatever appears
    /// or changes color under it eases instead of popping.
    func onHoverFade(_ isHovering: Binding<Bool>) -> some View {
        onHover { hovering in
            withAnimation(Motion.hover) { isHovering.wrappedValue = hovering }
        }
    }
}

// MARK: - Sidebar rows

extension View {
    /// Shared look for sidebar rows: height, padding, indentation and the
    /// hover/selection fill.
    func sidebarRow(depth: Int = 0, isSelected: Bool = false, isHovering: Bool) -> some View {
        modifier(SidebarRowStyle(depth: depth, isSelected: isSelected, isHovering: isHovering))
    }

    /// Accepts tabs dragged around the sidebar (payload: the tab's UUID) and
    /// moves them to `destination`. Rows pass `opensGap` so the list parts
    /// above them while a tab hovers, showing where it will land.
    func tabDropTarget(_ destination: TabDestination, opensGap: Bool = false) -> some View {
        modifier(TabDropTarget(destination: destination, opensGap: opensGap))
    }

    /// Lets a tab glide between sections (Today ↔ Pinned, into folders) and
    /// morph between a row and a favorite tile, instead of fading out in one
    /// place and in at another.
    @ViewBuilder
    func sidebarRowGeometry(_ id: UUID, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

extension EnvironmentValues {
    /// Set by the sidebar; see `sidebarRowGeometry`.
    @Entry var sidebarRowNamespace: Namespace.ID?
}

private struct SidebarRowStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let depth: Int
    let isSelected: Bool
    let isHovering: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, 10 + CGFloat(depth) * 14)
            .padding(.trailing, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? SidebarFill.selected(scheme) : isHovering ? SidebarFill.hover(scheme) : .clear)
                    .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 1, y: 1)
                    .animation(Motion.hover, value: isHovering)
                    .animation(Motion.snap, value: isSelected)
            )
            .contentShape(Rectangle())
    }
}

private struct TabDropTarget: ViewModifier {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let destination: TabDestination
    let opensGap: Bool
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        VStack(spacing: 2) {
            if opensGap, isTargeted {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SidebarFill.hover(scheme))
                    .frame(height: 30)
                    .transition(.opacity)
            }
            content
        }
        .animation(Motion.glide, value: isTargeted)
        .dropDestination(for: TabDrag.self) { drags, _ in
            guard let tab = drags.first.flatMap(store.tab) else { return false }
            store.move(tab, to: destination)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}
