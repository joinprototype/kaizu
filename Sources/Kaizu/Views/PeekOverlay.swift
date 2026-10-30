import BrowserCore
import SwiftUI

/// The peek card. Its scrim is separate (see ContentArea), so only the
/// card scales; while it grows into a tab, its frame melts away until just
/// the page is left, filling the content area.
struct PeekOverlay: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let tab: BrowserTab

    var body: some View {
        let isExpanding = store.isPeekExpanding
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                FaviconView(tab: tab, size: 14)
                Text(tab.url?.displayHost ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                IconButton(systemName: "link", help: "Copy Link") { store.copyLink(of: tab) }
                IconButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Open as Tab") { store.expandPeek() }
                IconButton(systemName: "xmark", help: "Close (Esc)") { store.closePeek() }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: isExpanding ? 0 : 36)
            .opacity(isExpanding ? 0 : 1)
            .clipped()

            PageView(tab: tab, accent: store.activeSpace.theme.accent(scheme))
                .pageCard(cornerRadius: isExpanding ? 10 : 8, shadow: false)
                .padding([.horizontal, .bottom], isExpanding ? 0 : 6)
        }
        .background(
            Surface.elevated(scheme).opacity(isExpanding ? 0 : 1),
            in: RoundedRectangle(cornerRadius: isExpanding ? 10 : 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isExpanding ? 10 : 14, style: .continuous)
                .strokeBorder(Surface.hairline(scheme).opacity(isExpanding ? 0 : 1))
        )
        .shadow(color: .black.opacity(isExpanding ? 0 : 0.3), radius: 30, y: 12)
        .padding(.horizontal, isExpanding ? 0 : 44)
        .padding(.vertical, isExpanding ? 0 : 24)
    }
}
