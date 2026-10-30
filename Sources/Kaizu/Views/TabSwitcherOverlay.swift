import SwiftUI

/// ⌃Tab: recent tabs as page thumbnails; the highlighted one opens when ⌃ is released.
struct TabSwitcherOverlay: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let state: TabSwitcherState

    var body: some View {
        let tabs = state.tabIDs.compactMap { id in store.activeSpace.allTabs.first { $0.id == id } }
        let accent = store.activeSpace.theme.accent(scheme)
        HStack(spacing: 12) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                SwitcherCard(tab: tab, isHighlighted: index == state.index, accent: accent)
                    .onTapGesture { store.commitTabSwitcher(to: index) }
            }
        }
        .padding(14)
        .background(Surface.elevated(scheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Surface.hairline(scheme)))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        .padding(24)
    }
}

private struct SwitcherCard: View {
    let tab: BrowserTab
    let isHighlighted: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The current tab's thumbnail is taken as the switcher opens and
            // lands a moment later: it fades in over the old one.
            ZStack(alignment: .top) {
                if let thumbnail = tab.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .id(ObjectIdentifier(thumbnail))
                        .transition(.opacity)
                } else {
                    Rectangle()
                        .fill(.secondary.opacity(0.12))
                        .overlay { FaviconView(tab: tab, size: 32) }
                        .transition(.opacity)
                }
            }
            .animation(Motion.snap, value: tab.thumbnail)
            .frame(width: 168, height: 106, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 6) {
                FaviconView(tab: tab, size: 12)
                Text(tab.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(width: 168, alignment: .leading)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent, lineWidth: isHighlighted ? 3 : 0)
        }
        .scaleEffect(isHighlighted ? 1 : 0.96)
        .contentShape(Rectangle())
    }
}

/// Sidebar mini player for audio/video playing in a tab you're not looking at.
struct NowPlayingCard: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let tab: BrowserTab

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(tab: tab, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("Now playing")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(tab.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            IconButton(systemName: "pause.fill", help: "Pause") { tab.pauseMedia() }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 44)
        .background(SidebarFill.subtle(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { store.select(tab) }
    }
}
