import BrowserCore
import SwiftUI

/// Safari's "Settings for this website", from the address pill's lock:
/// everything Kaizu remembers about the site in one place.
struct SiteSettingsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tab: BrowserTab

    var body: some View {
        if let url = tab.url, let host = url.host() {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    FaviconView(tab: tab, size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.displayHost)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Label(
                            url.scheme == "https" ? "Connection is secure" : "Connection isn’t secure",
                            systemImage: url.scheme == "https" ? "lock.fill" : "lock.open"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Block ads and trackers")
                        Toggle("", isOn: Binding(
                            get: { !store.contentBlocker.isPaused(on: url) },
                            set: { _ in store.toggleBlockingOnCurrentSite(tab) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!store.contentBlocker.isEnabled)
                        .gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        Text("Zoom")
                        HStack(spacing: 2) {
                            IconButton(systemName: "minus", help: "Zoom Out") { tab.zoom(by: -0.1) }
                            Button("\(Int((store.settings.zoom(for: url) * 100).rounded()))%") { tab.resetZoom() }
                                .buttonStyle(.plain)
                                .monospacedDigit()
                                .frame(minWidth: 40)
                                .help("Actual Size")
                            IconButton(systemName: "plus", help: "Zoom In") { tab.zoom(by: 0.1) }
                        }
                    }
                    permissionRow("Camera", device: "camera", host: host)
                    permissionRow("Microphone", device: "microphone", host: host)
                    permissionRow("Location", device: "location", host: host)
                }
                .font(.system(size: 13))
                Divider()
                HStack {
                    Button("Hide Distracting Items…") {
                        dismiss()
                        store.beginHidingItems(on: tab)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    let hidden = store.settings.hiddenItems(on: url).count
                    if hidden > 0 {
                        Button("Show \(hidden) Hidden") { store.showHiddenItems(on: tab) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                Button("Clear Cookies and Site Data…", role: .destructive) {
                    dismiss()
                    store.clearSiteData(for: tab)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.system(size: 13))
            }
            .padding(16)
            .frame(width: 300)
        }
    }

    private func permissionRow(_ title: String, device: String, host: String) -> some View {
        GridRow {
            Text(title)
            Picker(title, selection: Binding(
                get: { store.settings.sitePermissions[host]?[device] },
                set: { allowed in
                    store.settings.sitePermissions[host, default: [:]][device] = allowed
                    if store.settings.sitePermissions[host]?.isEmpty == true {
                        store.settings.sitePermissions[host] = nil
                    }
                }
            )) {
                Text("Ask").tag(Bool?.none)
                Text("Allow").tag(Bool?.some(true))
                Text("Block").tag(Bool?.some(false))
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
