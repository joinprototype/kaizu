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

    private var backdrop: AnyShapeStyle {
        tab.profile.isPrivate
            ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A2A30), Color(hex: 0x17171B)], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(theme.backdrop(scheme))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer().frame(width: 70)  // traffic lights
                IconButton(systemName: "arrow.left", help: "Back") { tab.goBack() }
                    .disabled(!tab.canGoBack)
                IconButton(systemName: "arrow.right", help: "Forward") { tab.goForward() }
                    .disabled(!tab.canGoForward)
                if tab.profile.isPrivate {
                    Label("Private", systemImage: "eyeglasses")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white.opacity(0.85))
                }
                if isEditingAddress {
                    KeyTextField(
                        text: $address,
                        placeholder: "Search or enter address",
                        fontSize: 13,
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
                if !tab.profile.isPrivate {
                    IconButton(systemName: "arrow.up.forward.app", help: "Open in Kaizu (⌘O)") { onPromote() }
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background { WindowDragArea() }

            PageView(tab: tab, accent: theme.accent(scheme))
            .pageCard(shadow: false)
            .padding([.horizontal, .bottom], 6)
        }
        .background(backdrop)
        .environment(\.colorScheme, tab.profile.isPrivate ? .dark : scheme)
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
