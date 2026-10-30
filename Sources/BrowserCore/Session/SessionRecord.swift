import Foundation

/// On-disk snapshot of the browser: profiles, spaces and their tabs.
///
/// Versioned: `SessionRecord.decode` upgrades older files step by step, so
/// user data survives every format change.
public struct SessionRecord: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var schemaVersion: Int
    public var activeSpaceID: UUID?
    public var isSidebarVisible: Bool
    public var sidebarWidth: Double
    public var profiles: [ProfileRecord]
    public var spaces: [SpaceRecord]

    public init(
        activeSpaceID: UUID?,
        isSidebarVisible: Bool,
        sidebarWidth: Double,
        profiles: [ProfileRecord],
        spaces: [SpaceRecord]
    ) {
        self.schemaVersion = Self.currentVersion
        self.activeSpaceID = activeSpaceID
        self.isSidebarVisible = isSidebarVisible
        self.sidebarWidth = sidebarWidth
        self.profiles = profiles
        self.spaces = spaces
    }
}

/// A browsing identity: its own cookies and storage, plus favorites shared by
/// every space that uses it.
public struct ProfileRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var favorites: [TabRecord]

    public init(id: UUID, name: String, favorites: [TabRecord]) {
        self.id = id
        self.name = name
        self.favorites = favorites
    }
}

/// What the sidebar shows: pinned items and today's tabs, backed by a profile.
public struct SpaceRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var hue: Double
    public var profileID: UUID
    public var selectedTabID: UUID?
    public var pinned: [SidebarItemRecord]
    /// Unpinned tabs, archived automatically when left alone.
    public var today: [TabRecord]
    /// Tabs shown side by side (2–4), in order. Optional so files from before
    /// split view still decode without a migration.
    public var split: [UUID]?
    /// Each split pane's share of the width, when dragged away from equal.
    public var splitWidths: [Double]?
    /// "light" or "dark" when the space forces one; nil follows the system.
    public var appearance: String?

    public init(
        id: UUID, name: String, symbol: String, hue: Double, profileID: UUID,
        selectedTabID: UUID?, pinned: [SidebarItemRecord], today: [TabRecord],
        split: [UUID]? = nil, splitWidths: [Double]? = nil, appearance: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.hue = hue
        self.profileID = profileID
        self.selectedTabID = selectedTabID
        self.pinned = pinned
        self.today = today
        self.split = split
        self.splitWidths = splitWidths
        self.appearance = appearance
    }
}

/// A pinned-section entry: a tab, or a folder of further entries.
public enum SidebarItemRecord: Codable, Equatable, Sendable {
    case tab(TabRecord)
    case folder(FolderRecord)

    private enum CodingKeys: String, CodingKey {
        case tab, folder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let tab = try container.decodeIfPresent(TabRecord.self, forKey: .tab) {
            self = .tab(tab)
        } else {
            self = .folder(try container.decode(FolderRecord.self, forKey: .folder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tab(let tab): try container.encode(tab, forKey: .tab)
        case .folder(let folder): try container.encode(folder, forKey: .folder)
        }
    }
}

public struct FolderRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isExpanded: Bool
    public var children: [SidebarItemRecord]

    public init(id: UUID, name: String, isExpanded: Bool, children: [SidebarItemRecord]) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.children = children
    }
}

public struct TabRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL?
    /// Where a favorite or pinned tab returns to when "closed".
    public var pinnedURL: URL?
    public var lastActiveAt: Date?

    public init(id: UUID, title: String, url: URL?, pinnedURL: URL? = nil, lastActiveAt: Date? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.pinnedURL = pinnedURL
        self.lastActiveAt = lastActiveAt
    }
}

/// A today tab that was archived after sitting unused; reopenable from the command bar.
public struct ArchivedTabRecord: Codable, Equatable, Sendable, Identifiable {
    public var tab: TabRecord
    public var spaceID: UUID
    public var archivedAt: Date

    public var id: UUID { tab.id }

    public init(tab: TabRecord, spaceID: UUID, archivedAt: Date) {
        self.tab = tab
        self.spaceID = spaceID
        self.archivedAt = archivedAt
    }
}

// MARK: - Coding

public enum SessionError: Error, Equatable {
    case unsupportedVersion(Int)
}

extension SessionRecord {
    /// Decodes any known version, upgrading it to the current one.
    /// `sourceVersion` tells the caller whether a migration happened.
    public static func decode(_ data: Data, now: Date = Date()) throws -> (record: SessionRecord, sourceVersion: Int) {
        struct VersionProbe: Decodable {
            var schemaVersion: Int?
        }
        let version = try JSONCoding.decoder.decode(VersionProbe.self, from: data).schemaVersion ?? 1
        switch version {
        case 1:
            return (try JSONCoding.decoder.decode(SessionRecordV1.self, from: data).upgraded(now: now), 1)
        case currentVersion:
            return (try JSONCoding.decoder.decode(SessionRecord.self, from: data), version)
        default:
            throw SessionError.unsupportedVersion(version)
        }
    }

    public func encoded() throws -> Data {
        try JSONCoding.encoder.encode(self)
    }
}

/// Shared JSON settings for everything Kaizu persists.
public enum JSONCoding {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
