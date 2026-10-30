import SwiftUI

struct FindBar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            KeyTextField(
                text: $query,
                placeholder: "Find on page",
                fontSize: 13,
                onMove: { store.findNext(backwards: $0 < 0) },
                onSubmit: { store.findNext() },
                onCancel: { store.hideFindBar() }
            )
            .frame(width: 170)
            if store.find?.matchFound == false {
                Text("Not found")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
            IconButton(systemName: "chevron.up", help: "Previous (⇧⌘G)") { store.findNext(backwards: true) }
            IconButton(systemName: "chevron.down", help: "Next (⌘G)") { store.findNext() }
            IconButton(systemName: "xmark", help: "Close (Esc)") { store.hideFindBar() }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(Surface.elevated(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Surface.hairline(scheme)))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onChange(of: query) { store.updateFind(query) }
        .onChange(of: store.selectedTab?.id) { store.hideFindBar() }
    }
}
