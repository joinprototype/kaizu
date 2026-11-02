import BrowserCore
import SwiftUI

struct LittleBrowserView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let tab: BrowserTab
    let onPromote: () -> Void
    @State private var isEditingAddress = false
    @State private var address = ""

    private var theme: Theme {
        (store.spaces.first { $0.profile === tab.profile } ?? store.activeSpace).theme
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer().frame(width: 70)  // traffic lights
                IconButton(systemName: "arrow.left", help: "Back") { tab.goBack() }
                    .disabled(!tab.canGoBack)
                IconButton(systemName: "arrow.right", help: "Forward") { tab.goForward() }
                    .disabled(!tab.canGoForward)
                if isEditingAddress {
                    KeyTextField(
                        text: $address,
                        placeholder: "Search or enter address",
                        font: Typeface.textField(13),
                        caret: theme.accent(scheme),
                        onMove: { _ in },
                        onSubmit: submitAddress,
                        onCancel: { isEditingAddress = false }
                    )
                } else {
                    Button {
                        address = tab.url?.absoluteString ?? ""
                        isEditingAddress = true
                    } label: {
                        HStack(spacing: 6) {
                            if let url = tab.url {
                                Image(systemName: url.scheme == "https" ? "lock.fill" : "globe")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(tab.url?.displayHost ?? "Search or enter address")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                IconButton(systemName: "link", help: "Copy Link") { store.copyLink(of: tab) }
                    .disabled(tab.url == nil)
                IconButton(systemName: "arrow.up.forward.app", help: "Open in Kaizu (⌘O)") { onPromote() }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background { WindowDragArea() }

            PageView(tab: tab, accent: theme.accent(scheme))
            .pageCard(shadow: false)
            .padding([.horizontal, .bottom], 6)
        }
        .background(theme.backdrop(scheme))
        .ignoresSafeArea()
        .onAppear {
            if tab.url == nil { isEditingAddress = true }
        }
    }

    private func submitAddress() {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLInput.explicitURL(query) ?? (query.isEmpty ? nil : store.settings.searchEngine.searchURL(for: query)) else { return }
        tab.load(url)
        isEditingAddress = false
    }
}
