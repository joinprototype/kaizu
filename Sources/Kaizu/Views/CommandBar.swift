import AppKit
import BrowserCore
import SwiftUI

enum Suggestion: Identifiable {
    /// "20+20 = 40", "10 km = 6.21 mi"; Enter copies it.
    case answer(QuickAnswer)
    /// "yt lofi" → search YouTube for "lofi".
    case shortcut(SearchShortcut, query: String)
    case url(URL)
    case search(String)
    case command(PaletteCommand)
    case tab(BrowserTab)
    case history(HistoryStore.Entry)
    case archived(ArchivedTabRecord)

    var id: String {
        switch self {
        case .answer(let answer): "answer:\(answer.question)"
        case .shortcut(let shortcut, let query): "shortcut:\(shortcut.keyword):\(query)"
        case .url(let url): "url:\(url.absoluteString)"
        case .search(let query): "search:\(query)"
        case .command(let command): "command:\(command.id)"
        case .tab(let tab): "tab:\(tab.id)"
        case .history(let entry): "history:\(entry.url.absoluteString)"
        case .archived(let archived): "archived:\(archived.id)"
        }
    }
}

/// Arc-style floating command bar for ⌘T (new tab) and ⌘L (edit current URL):
/// addresses, searches, instant answers, commands, open tabs, history, archive.
struct CommandBar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let mode: CommandBarMode
    @State private var text: String
    @State private var selection = 0
    @State private var historyMatches: [HistoryStore.Entry] = []
    /// The profile's most visited pages, for inline completion.
    @State private var frequentURLs: [URL] = []
    /// The search engine's suggestions, when turned on in Settings.
    @State private var engineSuggestions: [String] = []
    private static let suggestionSession = URLSession(configuration: .ephemeral)
    @State private var hasAppeared = false
    @Namespace private var selectionHighlight

    init(mode: CommandBarMode, initialText: String) {
        self.mode = mode
        _text = State(initialValue: initialText)
    }

    private var suggestions: [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tabs = store.activeSpace.allTabs
        guard !query.isEmpty else {
            let others = tabs.filter { $0 !== store.selectedTab }
            return mode == .newTab ? others.prefix(6).map(Suggestion.tab) : []
        }
        var results: [Suggestion] = []
        if let answer = QuickAnswer.evaluate(query, rates: CurrencyFeed.shared.rates) {
            results.append(.answer(answer))
        }
        if let match = SearchShortcut.match(query, in: store.settings.searchShortcuts) {
            results.append(.shortcut(match.shortcut, query: match.query))
        }
        if let url = URLInput.explicitURL(query) {
            results.append(.url(url))
        }
        results.append(.search(query))
        results += engineSuggestions.filter { $0.caseInsensitiveCompare(query) != .orderedSame }.prefix(3).map(Suggestion.search)
        results += store.commands(matching: query).prefix(3).map(Suggestion.command)
        let matchingTabs = tabs.filter { $0.id != store.selectedTab?.id && Self.matches(query, title: $0.displayTitle, url: $0.url) }
        results += matchingTabs.prefix(5).map(Suggestion.tab)
        let openURLs = Set(tabs.compactMap(\.url))
        results += historyMatches.filter { !openURLs.contains($0.url) }.prefix(4).map(Suggestion.history)
        let archived = store.archive.filter { Self.matches(query, title: $0.tab.title, url: $0.tab.url) }
        results += archived.prefix(3).map(Suggestion.archived)
        // What you usually pick for this leads (after an instant answer).
        if let top = store.topChoice(for: query, among: results), let index = results.firstIndex(where: { $0.id == top.id }) {
            let lead = results.remove(at: index)
            let afterAnswer = results.first.map { if case .answer = $0 { true } else { false } } ?? false
            results.insert(lead, at: afterAnswer ? 1 : 0)
        }
        return results
    }

    private func choose(_ suggestion: Suggestion) {
        store.learn(suggestion, for: text)
        store.perform(suggestion, mode: mode)
    }

    /// Asks the search engine (if allowed) once typing pauses. Never for
    /// anything that looks like an address or a shortcut, which can be private.
    private func fetchEngineSuggestions() async -> [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.settings.searchSuggestions, query.count > 1, !Self.looksLikeAddress(query),
              SearchShortcut.match(query, in: store.settings.searchShortcuts) == nil,
              let url = store.settings.searchEngine.suggestionsURL(for: query)
        else { return [] }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled, let (data, _) = try? await Self.suggestionSession.data(from: url) else { return [] }
        return SearchEngine.suggestions(from: data)
    }

    /// "go/payroll", "nas:5000", "jira.c", "192.168.1": half-typed addresses
    /// that `URLInput` doesn't take yet.
    private static func looksLikeAddress(_ query: String) -> Bool {
        URLInput.explicitURL(query) != nil || (!query.contains(" ") && query.contains { ".:/".contains($0) })
    }

    /// Applies late-arriving results without moving the highlight off the
    /// row it's on (new rows can land above it), easing the rows apart.
    private func keepingSelection(_ update: () -> Void) {
        let selected = suggestions.indices.contains(selection) ? suggestions[selection].id : nil
        withAnimation(Motion.snap) {
            update()
            selection = suggestions.firstIndex { $0.id == selected } ?? 0
        }
    }

    private static func matches(_ query: String, title: String, url: URL?) -> Bool {
        title.localizedCaseInsensitiveContains(query) || (url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // A click around the bar puts it away. (In the window the scrim
            // is drawn behind, so it fades rather than scales.)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            card
                .padding(.top, mode == .quick ? QuickBarController.margin : 110)
        }
        .onAppear { hasAppeared = true }
        .task {
            // An empty search lists everything, most visited first.
            frequentURLs = await store.history?.search("", profile: store.activeSpace.profile.id, limit: 400).map(\.url) ?? []
        }
        .onChange(of: text) {
            selection = 0
            if CurrencyConversion.parse(text) != nil {
                CurrencyFeed.shared.requestIfNeeded()
            }
        }
        .task(id: text) {
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty, let history = store.history else { return historyMatches = [] }
            let matches = await history.search(query, profile: store.activeSpace.profile.id)
            guard !Task.isCancelled else { return }
            keepingSelection { historyMatches = matches }
        }
        .task(id: text) {
            let suggestions = await fetchEngineSuggestions()
            guard !Task.isCancelled else { return }
            keepingSelection { engineSuggestions = suggestions }
        }
    }

    private var card: some View {
        let suggestions = suggestions
        let palette = store.activeSpace.theme.variant(scheme)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: mode == .newTab ? "plus.magnifyingglass" : "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                KeyTextField(
                    text: $text,
                    placeholder: mode == .currentTab ? "Enter address…" : "Search, enter address, or type 20+20…",
                    onMove: { delta in
                        guard !suggestions.isEmpty else { return }
                        withAnimation(Motion.snap) {
                            selection = (selection + delta + suggestions.count) % suggestions.count
                        }
                    },
                    onSubmit: {
                        guard suggestions.indices.contains(selection) else { return }
                        choose(suggestions[selection])
                    },
                    onCancel: dismiss,
                    complete: { typed in
                        let known = frequentURLs + store.activeSpace.allTabs.compactMap(\.url) + historyMatches.map(\.url)
                        return InlineCompletion.complete(typed, from: known)
                    }
                )
            }
            .padding(.horizontal, 18)
            .frame(height: 56)

            if !suggestions.isEmpty {
                Divider().opacity(0.6)
                VStack(spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        SuggestionRow(
                            presentation: suggestion.presentation(searchEngine: store.settings.searchEngine),
                            isSelected: index == selection,
                            palette: palette
                        )
                        .matchedGeometryEffect(id: suggestion.id, in: selectionHighlight)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : -4)
                        .animation(Motion.pop?.delay(Double(index) * 0.015), value: hasAppeared)
                        .onTapGesture { choose(suggestion) }
                        .onHover { hovering in
                            if hovering {
                                withAnimation(Motion.snap) { selection = index }
                            }
                        }
                    }
                }
                // One pill that slides to the selected row, rather than one
                // per row cross-fading (which dims it mid-way).
                .background(alignment: .topLeading) {
                    if suggestions.indices.contains(selection) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.accent)
                            .matchedGeometryEffect(id: suggestions[selection].id, in: selectionHighlight, isSource: false)
                    }
                }
                .padding(8)
            }
            Divider().opacity(0.6)
            HStack(spacing: 14) {
                KeyHint(keys: "↩", label: "open")
                KeyHint(keys: "↑↓", label: "select")
                KeyHint(keys: "esc", label: "close")
                Spacer()
                Text("Try 20+20, 100 usd to eur, yt lofi")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 30)
        }
        .frame(width: 620)
        .background(Surface.elevated(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Surface.hairline(scheme))
        }
        .shadow(color: .black.opacity(0.25), radius: 40, y: 16)
    }

    private func dismiss() {
        if mode == .quick {
            store.quickBar?.hide()
        } else {
            store.dismissCommandBar()
        }
    }
}

// MARK: - Rows

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            KeyCap(keys: keys, size: 10)
            Text(label)
        }
    }
}

/// Everything a suggestion row shows, decided in one place.
struct SuggestionPresentation {
    enum Icon {
        case symbol(String)
        case favicon(BrowserTab)
    }

    var icon: Icon
    var title: String
    var subtitle: String?
    /// Trailing hint for what Enter does, when it isn't obvious.
    var action: String?
}

extension Suggestion {
    @MainActor
    func presentation(searchEngine: SearchEngine) -> SuggestionPresentation {
        switch self {
        case .answer(let answer):
            .init(icon: .symbol("equal.circle"), title: answer.answer, subtitle: answer.question, action: "Copy")
        case .shortcut(let shortcut, let query):
            .init(icon: .symbol("magnifyingglass"), title: query, subtitle: "Search \(shortcut.name)")
        case .url(let url):
            .init(icon: .symbol("globe"), title: url.absoluteString, subtitle: "Open page")
        case .search(let query):
            .init(icon: .symbol("magnifyingglass"), title: query, subtitle: "Search \(searchEngine.name)")
        case .command(let command):
            .init(icon: .symbol(command.symbol), title: command.title, subtitle: "Command", action: command.shortcut)
        case .tab(let tab):
            .init(icon: .favicon(tab), title: tab.displayTitle, subtitle: tab.url?.displayHost, action: "Switch to Tab")
        case .history(let entry):
            .init(icon: .symbol("clock.arrow.circlepath"), title: entry.title.isEmpty ? entry.url.displayHost : entry.title, subtitle: entry.url.displayHost)
        case .archived(let archived):
            .init(
                icon: .symbol("archivebox"),
                title: archived.tab.title.isEmpty ? archived.tab.url?.displayHost ?? "Archived tab" : archived.tab.title,
                subtitle: archived.tab.url?.displayHost,
                action: "Reopen"
            )
        }
    }
}

private struct SuggestionRow: View {
    let presentation: SuggestionPresentation
    let isSelected: Bool
    let palette: Theme.Variant

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch presentation.icon {
                case .symbol(let name): Image(systemName: name)
                case .favicon(let tab): FaviconView(tab: tab, size: 16)
                }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let subtitle = presentation.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .opacity(0.65)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let action = presentation.action {
                Text(action)
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.7)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .foregroundStyle(isSelected ? AnyShapeStyle(palette.onAccent) : AnyShapeStyle(.primary))
        .contentShape(Rectangle())
    }
}
