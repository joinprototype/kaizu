import BrowserCore
import WebKit

/// A browsing identity: its own cookies, logins and storage, plus the
/// favorites shared by every space that uses it.
@MainActor @Observable
final class Profile: Identifiable {
    let id: UUID
    var name: String
    var favorites: [BrowserTab] = []
    /// Private windows: in-memory website data, no history, nothing saved.
    let isPrivate: Bool

    var privateID: UUID? { isPrivate ? id : nil }

    /// Website data lives under the profile's id, so it must never change.
    @ObservationIgnored private(set) var didOpenWebsiteData = false
    @ObservationIgnored private(set) lazy var dataStore: WKWebsiteDataStore = {
        didOpenWebsiteData = true
        return isPrivate ? .nonPersistent() : WKWebsiteDataStore(forIdentifier: id)
    }()

    init(id: UUID = UUID(), name: String, isPrivate: Bool = false) {
        self.id = id
        self.name = name
        self.isPrivate = isPrivate
    }

    var record: ProfileRecord {
        ProfileRecord(id: id, name: name, favorites: favorites.map(\.record))
    }
}
