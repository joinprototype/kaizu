import BrowserCore
import Foundation

/// The command bar learning what you pick (see ChoiceMemory), per profile,
/// kept in Choices.json next to the session. Clear History forgets it.
extension BrowserStore {
    private static var choicesURL: URL {
        AppPaths.support.appending(path: "Choices.json")
    }

    func loadChoices() {
        guard let data = try? Data(contentsOf: Self.choicesURL),
              let saved = try? JSONDecoder().decode([UUID: ChoiceMemory].self, from: data)
        else { return }
        choices = saved
    }

    /// `suggestion` was picked after typing `query`.
    func learn(_ suggestion: Suggestion, for query: String) {
        let profile = activeSpace.profile
        guard !profile.isPrivate, let key = suggestion.memoryKey else { return }
        choices[profile.id, default: ChoiceMemory()].record(query: query, choice: key)
        saveChoices()
    }

    /// What to lead with for `query`, among the suggestions on offer.
    func topChoice(for query: String, among suggestions: [Suggestion]) -> Suggestion? {
        guard let memory = choices[activeSpace.profile.id] else { return nil }
        let keys = Set(suggestions.compactMap(\.memoryKey))
        guard let key = memory.topChoice(for: query, among: keys) else { return nil }
        return suggestions.first { $0.memoryKey == key }
    }

    func forgetChoices() {
        choices = [:]
        try? FileManager.default.removeItem(at: Self.choicesURL)
    }

    /// A deleted profile's, or one page deleted from history.
    func forgetChoices(of profile: UUID, url: URL? = nil) {
        if let url {
            choices[profile]?.forget("url:\(url.absoluteString)")
        } else {
            choices[profile] = nil
        }
        saveChoices()
    }

    /// A few kilobytes, written in place: a background write could land
    /// after Clear History and bring it all back.
    private func saveChoices() {
        guard let data = try? JSONEncoder().encode(choices) else { return }
        try? data.write(to: Self.choicesURL, options: .atomic)
    }
}

extension Suggestion {
    /// Stable across launches; nil for what shouldn't be learned (answers).
    var memoryKey: String? {
        switch self {
        case .answer: nil
        case .shortcut(let shortcut, _): "shortcut:\(shortcut.keyword)"
        case .url(let url): "url:\(url.absoluteString)"
        case .history(let entry): "url:\(entry.url.absoluteString)"
        case .search(let query): "search:\(query.lowercased())"
        case .command(let command): "command:\(command.id)"
        case .tab(let tab): "tab:\(tab.id)"
        case .archived(let archived): "archived:\(archived.id)"
        }
    }
}
