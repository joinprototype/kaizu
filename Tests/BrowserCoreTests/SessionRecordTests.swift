import Foundation
import Testing
@testable import BrowserCore

@Suite struct SessionRecordTests {
    static let profileID = UUID(uuidString: "E5B2B57C-22ED-4BD7-8DC3-10AA399AAEC4")!
    static let pinnedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let tabID = UUID(uuidString: "74BB84E7-EE7E-4C3F-A39C-AEA693A9A5B8")!

    /// A real v1 session as written by Kaizu 0.1.
    static let v1JSON = """
    {
      "activeProfileID" : "\(profileID)",
      "isSidebarVisible" : true,
      "profiles" : [
        {
          "hue" : 0.06,
          "id" : "\(profileID)",
          "name" : "Personal",
          "pinnedTabs" : [
            { "id" : "\(pinnedID)", "pinnedURL" : "https://mail.example.com/", "title" : "Mail", "url" : "https://mail.example.com/inbox" }
          ],
          "selectedTabID" : "\(tabID)",
          "symbol" : "person.fill",
          "tabs" : [
            { "id" : "\(tabID)", "title" : "Apple", "url" : "https://www.apple.com/" }
          ]
        }
      ],
      "sidebarWidth" : 248
    }
    """

    @Test func upgradesVersion1KeepingProfileIdentity() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let (record, sourceVersion) = try SessionRecord.decode(Data(Self.v1JSON.utf8), now: now)

        #expect(sourceVersion == 1)
        #expect(record.schemaVersion == SessionRecord.currentVersion)
        // Same id: the profile keeps its WebKit data store (logins).
        #expect(record.profiles == [
            ProfileRecord(id: Self.profileID, name: "Personal", favorites: [
                TabRecord(id: Self.pinnedID, title: "Mail", url: URL(string: "https://mail.example.com/inbox"), pinnedURL: URL(string: "https://mail.example.com/"), lastActiveAt: now),
            ]),
        ])
        #expect(record.spaces == [
            SpaceRecord(
                id: Self.profileID, name: "Personal", symbol: "person.fill", hue: 0.06, profileID: Self.profileID,
                selectedTabID: Self.tabID, pinned: [],
                today: [TabRecord(id: Self.tabID, title: "Apple", url: URL(string: "https://www.apple.com/"), lastActiveAt: now)]
            ),
        ])
        #expect(record.activeSpaceID == Self.profileID)
    }

    @Test func currentVersionRoundTrips() throws {
        let folder = FolderRecord(id: UUID(), name: "Work", isExpanded: false, children: [
            .tab(TabRecord(id: UUID(), title: "Docs", url: URL(string: "https://docs.example.com"))),
            .folder(FolderRecord(id: UUID(), name: "Nested", isExpanded: true, children: [])),
        ])
        let record = SessionRecord(
            activeSpaceID: Self.profileID, isSidebarVisible: false, sidebarWidth: 300,
            profiles: [ProfileRecord(id: Self.profileID, name: "Personal", favorites: [])],
            spaces: [SpaceRecord(
                id: Self.profileID, name: "Personal", symbol: "star.fill", hue: 0.6, profileID: Self.profileID,
                selectedTabID: nil, pinned: [.folder(folder)],
                today: [TabRecord(id: Self.tabID, title: "Apple", url: nil, lastActiveAt: Date(timeIntervalSince1970: 1_790_000_000))],
                split: [Self.tabID, Self.pinnedID], splitWidths: [0.6, 0.4], appearance: "dark"
            )]
        )
        let (decoded, sourceVersion) = try SessionRecord.decode(try record.encoded())
        #expect(sourceVersion == SessionRecord.currentVersion)
        #expect(decoded == record)
    }

    @Test func folderEntriesEncodeWithReadableKeys() throws {
        let json = String(decoding: try JSONCoding.encoder.encode([SidebarItemRecord.folder(
            FolderRecord(id: Self.tabID, name: "Work", isExpanded: true, children: [])
        )]), as: UTF8.self)
        #expect(json.contains(#""folder" : {"#))
        #expect(!json.contains("_0"))
    }

    @Test func rejectsFutureVersions() {
        #expect(throws: SessionError.unsupportedVersion(99)) {
            try SessionRecord.decode(Data(#"{"schemaVersion": 99}"#.utf8))
        }
    }
}
