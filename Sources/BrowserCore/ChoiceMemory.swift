import Foundation

/// What you usually pick for what you type, so the command bar can put it
/// first (Spotlight's "top hit"): choose GitHub after typing "gi" a couple
/// of times and "gi" leads with GitHub. Remembered for every prefix of the
/// query, so "g" learns too. Local only; small and bounded.
public struct ChoiceMemory: Codable, Equatable, Sendable {
    struct Choice: Codable, Equatable, Sendable {
        var key: String
        var count: Int
        var lastUsed: Date
    }

    /// Typed prefix → choices made after typing it, most used first.
    private var choices: [String: [Choice]] = [:]

    static let longestPrefix = 16
    static let choicesPerPrefix = 4
    static let maximumPrefixes = 2000
    /// Picked this often before it leads.
    static let confidence = 2

    public init() {}

    public mutating func record(query: String, choice key: String, at date: Date = .now) {
        let query = Self.normalized(query)
        guard !query.isEmpty else { return }
        for length in 1...min(query.count, Self.longestPrefix) {
            let prefix = String(query.prefix(length))
            var list = choices[prefix] ?? []
            if let index = list.firstIndex(where: { $0.key == key }) {
                list[index].count += 1
                list[index].lastUsed = date
            } else {
                list.append(Choice(key: key, count: 1, lastUsed: date))
            }
            list.sort { ($0.count, $0.lastUsed) > ($1.count, $1.lastUsed) }
            choices[prefix] = Array(list.prefix(Self.choicesPerPrefix))
        }
        trim()
    }

    /// The choice to lead with for `query`, among `candidates` (what's on
    /// offer right now), if one has been picked often enough. None for
    /// queries longer than what's remembered: the rest would be ignored.
    public func topChoice(for query: String, among candidates: Set<String>) -> String? {
        let query = Self.normalized(query)
        guard !query.isEmpty, query.count <= Self.longestPrefix else { return nil }
        return choices[query]?.first { $0.count >= Self.confidence && candidates.contains($0.key) }?.key
    }

    public mutating func forget(_ key: String) {
        for prefix in choices.keys {
            choices[prefix]?.removeAll { $0.key == key }
            if choices[prefix]?.isEmpty == true { choices[prefix] = nil }
        }
    }

    /// Drops the prefixes used longest ago once there are too many.
    private mutating func trim() {
        guard choices.count > Self.maximumPrefixes else { return }
        let byAge = choices.sorted { ($0.value.map(\.lastUsed).max() ?? .distantPast) < ($1.value.map(\.lastUsed).max() ?? .distantPast) }
        for (prefix, _) in byAge.prefix(choices.count - Self.maximumPrefixes) {
            choices[prefix] = nil
        }
    }

    private static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
