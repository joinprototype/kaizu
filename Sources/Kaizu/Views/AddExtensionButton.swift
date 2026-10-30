import BrowserCore
import SwiftUI

/// On an extension's Chrome Web Store or Firefox Add-ons page, whose own
/// "Add to Chrome" button only works in that browser: adds it to Kaizu.
struct AddExtensionOverlay: View {
    let tab: BrowserTab

    var body: some View {
        let listing = tab.profile.isPrivate ? nil : ExtensionGallery.listing(for: tab.url)
        ZStack {
            if let listing {
                AddExtensionButton(listing: listing)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .padding(16)
        .animation(Motion.pop, value: listing)
    }
}

private struct AddExtensionButton: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let listing: ExtensionGallery.Listing

    var body: some View {
        let extensions = store.extensions
        let isInstalled = extensions.isInstalled(listing)
        let isDownloading = extensions.downloading == listing
        Button {
            Task { await extensions.install(listing) }
        } label: {
            HStack(spacing: 8) {
                if isDownloading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isInstalled ? "checkmark" : "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                }
                Text(isInstalled ? "Added to Kaizu" : isDownloading ? "Adding…" : "Add to Kaizu")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Surface.elevated(scheme), in: Capsule())
            .overlay(Capsule().strokeBorder(Surface.hairline(scheme)))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isInstalled || extensions.downloading != nil)
        .animation(Motion.snap, value: isInstalled)
        .animation(Motion.snap, value: isDownloading)
    }
}
