import AppKit
import BrowserCore
import SwiftUI

/// ⌘Y: the active space's profile history, grouped by day and searchable.
struct HistoryView: View {
    @Environment(BrowserStore.self) private var store
    @State private var query = ""
    @State private var entries: [HistoryStore.Entry] = []
    @State private var selection: URL?

    private struct DaySection {
        let title: String
        let entries: [HistoryStore.Entry]
    }

    private var sections: [DaySection] {
        let calendar = Calendar.current
        let days = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.lastVisit) }
        return days.keys.sorted(by: >).map { day in
            let title = calendar.isDateInToday(day) ? "Today"
                : calendar.isDateInYesterday(day) ? "Yesterday"
                : day.formatted(date: .complete, time: .omitted)
            return DaySection(title: title, entries: days[day, default: []].sorted { $0.lastVisit > $1.lastVisit })
        }
    }

    var body: some View {
        let profile = store.activeSpace.profile
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(profile.name) history", text: $query)
                    .textFieldStyle(.plain)
                Button("Clear History…") {
                    store.clearHistory()
                    Task { await reload(profile: profile.id) }
                }
            }
            .padding(12)
            Divider()
            List(selection: $selection) {
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.entries) { entry in
                            HistoryRow(entry: entry)
                                .tag(entry.url)
                                .onTapGesture(count: 2) { open(entry) }
                                .contextMenu {
                                    Button("Open in New Tab") { open(entry) }
                                    Button("Copy Link") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
                                    }
                                    Divider()
                                    Button("Delete from History") { delete(entry, profile: profile.id) }
                                }
                        }
                    }
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No History Yet" : "No Results", systemImage: "clock")
                }
            }
            .onKeyPress(.return) {
                guard let selection, let entry = entries.first(where: { $0.url == selection }) else { return .ignored }
                open(entry)
                return .handled
            }
        }
        .task(id: "\(profile.id)|\(query)") { await reload(profile: profile.id) }
    }

    private func reload(profile: UUID) async {
        guard let history = store.history else { return }
        let text = query.trimmingCharacters(in: .whitespaces)
        entries = text.isEmpty
            ? await history.recent(profile: profile, limit: 500)
            : await history.search(text, profile: profile, limit: 200)
    }

    private func open(_ entry: HistoryStore.Entry) {
        store.openTab(entry.url)
        store.window?.makeKeyAndOrderFront(nil)
    }

    private func delete(_ entry: HistoryStore.Entry, profile: UUID) {
        entries.removeAll { $0.url == entry.url }
        Task { await store.history?.remove(entry.url, profile: profile) }
        store.forgetChoices(of: profile, url: entry.url)
    }
}

private struct HistoryRow: View {
    let entry: HistoryStore.Entry

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let host = entry.url.host(), let icon = FaviconStore.shared.cachedImage(for: host) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? entry.url.displayHost : entry.title)
                    .lineLimit(1)
                Text(entry.url.displayHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(entry.lastVisit.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
