import CryptoKit
import WebKit

/// Keeps the user's original WebKit JSON so a purged or outdated compiled cache can be rebuilt.
@MainActor @Observable
final class ImportedRuleLists {
    struct Entry: Codable, Identifiable {
        let id: String
        let name: String
        var enabled: Bool
    }

    private let directory: URL
    private var index: URL { directory.appendingPathComponent("lists.json") }
    private(set) var entries: [Entry] = []
    private(set) var busy = true
    private(set) var problems: [String: String] = [:]
    private(set) var indexError: String?
    @ObservationIgnored var didChange: (() -> Void)?
    @ObservationIgnored private var compiled: [String: WKContentRuleList] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func install(on controller: WKUserContentController) {
        for entry in entries where entry.enabled {
            if let list = compiled[entry.id] { controller.add(list) }
        }
    }

    func restore() async {
        defer { busy = false }
        do {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: index))
            let hex = CharacterSet(charactersIn: "0123456789abcdef")
            guard Set(entries.map(\.id)).count == entries.count,
                  entries.allSatisfy({ $0.id.utf8.count == 64 && $0.id.rangeOfCharacter(from: hex.inverted) == nil })
            else { throw CocoaError(.fileReadCorruptFile) }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return
        } catch {
            entries = []
            indexError = error.localizedDescription
            return
        }
        for entry in entries where entry.enabled {
            do { compiled[entry.id] = try await load(entry.id) }
            catch { problems[entry.id] = error.localizedDescription }
        }
    }

    func add(_ url: URL) async throws {
        guard !busy, indexError == nil else { throw ListError.unavailable }
        busy = true
        defer { busy = false }
        let (data, id) = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return (data, id)
        }.value
        guard !entries.contains(where: { $0.id == id }) else { throw ListError.duplicate }
        guard let json = String(data: data, encoding: .utf8) else { throw ListError.encoding }
        let list = try await load(id, json: json)
        do {
            try data.write(to: source(id), options: .atomic)
            try save(entries + [Entry(id: id, name: url.lastPathComponent, enabled: true)])
        } catch {
            await discardFiles(id)
            throw error
        }
        compiled[id] = list
        didChange?()
    }

    func setEnabled(_ enabled: Bool, id: String) async throws {
        guard !busy, indexError == nil else { throw ListError.unavailable }
        guard let position = entries.firstIndex(where: { $0.id == id }), entries[position].enabled != enabled else { return }
        busy = true
        defer { busy = false }
        let list = enabled ? try await load(id) : nil
        var updated = entries
        updated[position].enabled = enabled
        try save(updated)
        compiled[id] = list
        problems[id] = nil
        didChange?()
    }

    func remove(_ id: String) async throws {
        guard !busy, indexError == nil else { throw ListError.unavailable }
        guard entries.contains(where: { $0.id == id }) else { return }
        busy = true
        defer { busy = false }
        try save(entries.filter { $0.id != id })
        compiled[id] = nil
        problems[id] = nil
        didChange?()
        await discardFiles(id)
    }

    private func discardFiles(_ id: String) async {
        // The committed index controls which lists can load, even if cleanup is interrupted.
        try? FileManager.default.removeItem(at: source(id))
        if let store = try? ruleStore() { try? await store.removeContentRuleList(forIdentifier: id) }
    }

    private func source(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }

    private func save(_ updated: [Entry]) throws {
        try JSONEncoder().encode(updated).write(to: index, options: .atomic)
        entries = updated
    }

    private func ruleStore() throws -> WKContentRuleListStore {
        let cache = directory.appending(path: "Compiled", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        guard let store = WKContentRuleListStore(url: cache) else { throw ListError.store }
        return store
    }

    private func load(_ id: String, json: String? = nil) async throws -> WKContentRuleList {
        let store = try ruleStore()
        if let cached = try? await store.contentRuleList(forIdentifier: id) { return cached }
        let text = try json ?? String(contentsOf: source(id), encoding: .utf8)
        guard let list = try await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: text)
        else { throw ListError.store }
        return list
    }

    private enum ListError: LocalizedError {
        case unavailable, duplicate, encoding, store
        var errorDescription: String? {
            switch self {
            case .unavailable: "Rule lists are unavailable for editing."
            case .duplicate: "These rules have already been imported."
            case .encoding: "Choose a UTF-8 WebKit JSON rule list."
            case .store: "WebKit couldn’t open the compiled rule list."
            }
        }
    }
}
