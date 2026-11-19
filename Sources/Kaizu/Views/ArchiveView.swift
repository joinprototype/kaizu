import BrowserCore
import DesignSystem
import SwiftUI

/// Opened from History or the command bar, scoped to its browser window.
struct ArchiveView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: UUID?

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: store.spaces.map { ($0.id, $0.name) })
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = store.matchingArchivedTabs(text)
        let days = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.archivedAt) }
        let selected = entries.first { $0.id == selection }

        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Archived Tabs").font(Typeface.display(24))
            TextField("Search \(store.activeSpace.profile.name) archive", text: $query)
            List(selection: $selection) {
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Section(day.formatted(date: .complete, time: .omitted)) {
                        ForEach(days[day, default: []].sorted { $0.archivedAt > $1.archivedAt }) { entry in
                            VStack(alignment: .leading) {
                                Text(entry.tab.customTitle ?? (entry.tab.title.isEmpty ? entry.tab.url?.displayHost ?? "Untitled Tab" : entry.tab.title))
                                Text([names[entry.spaceID], entry.tab.url?.displayHost].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .tag(entry.id)
                            .onTapGesture(count: 2) { reopen(entry) }
                        }
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(text.isEmpty ? "No Archived Tabs" : "No Matching Tabs", systemImage: "archivebox")
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Reopen Tab") { if let selected { reopen(selected) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 540, height: 480)
    }

    private func reopen(_ entry: ArchivedTabRecord) {
        store.reopen(entry)
        dismiss()
    }
}
