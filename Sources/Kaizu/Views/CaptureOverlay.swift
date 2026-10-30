import SwiftUI

/// Over a page being captured (⇧⌘2): dims it, and the area you drag over
/// stays clear. Letting go copies that area.
struct CaptureOverlay: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var selection: CGRect?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    if let selection {
                        path.addRect(selection)
                    }
                }
                .fill(.black.opacity(0.32), style: FillStyle(eoFill: true))

                if let selection {
                    Rectangle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                        .frame(width: selection.width, height: selection.height)
                        .offset(x: selection.minX, y: selection.minY)
                    Text("\(Int(selection.width)) × \(Int(selection.height))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .offset(x: selection.minX, y: selection.maxY + 6)
                } else {
                    hint
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        selection = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.location.x - value.startLocation.x),
                            height: abs(value.location.y - value.startLocation.y)
                        )
                        .intersection(CGRect(origin: .zero, size: geometry.size))
                    }
                    .onEnded { _ in
                        if let selection, selection.width > 4, selection.height > 4 {
                            store.finishCapture(selection)
                        } else {
                            selection = nil
                        }
                    }
            )
        }
        .pointerStyle(.rectSelection)
        .transition(.opacity)
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .foregroundStyle(.secondary)
            Text("Drag over an area to copy it")
            Divider().frame(height: 14)
            KeyCap(keys: "↩", size: 11)
            Text("whole page")
                .foregroundStyle(.secondary)
            KeyCap(keys: "esc", size: 11)
                .padding(.leading, 4)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Surface.elevated(scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(Surface.hairline(scheme)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// Over a page while picking items to hide (Hide Distracting Items).
struct HidingItemsHint: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            Text("Click items to hide them on this site")
            Divider().frame(height: 14)
            Button("Done") { store.endHidingItems() }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
            KeyCap(keys: "esc", size: 11)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Surface.elevated(scheme), in: Capsule())
        .overlay(Capsule().strokeBorder(Surface.hairline(scheme)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
