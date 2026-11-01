import Foundation
import Testing
@testable import BrowserCore

@Suite struct ArcSidebarTests {
    static func fixture() throws -> ArcSidebar {
        let url = try #require(Bundle.module.url(forResource: "StorableSidebar", withExtension: "json", subdirectory: "Fixtures"))
        return try ArcSidebar.load(from: url)
    }

    static func tab(_ title: String, _ address: String) -> ArcSidebar.Tab {
        ArcSidebar.Tab(title: title, url: URL(string: address)!)
    }

    /// A one-space sidebar around `items`, whose pinned root is "PIN".
    static func sidebar(pinned: [String], items: String, containers: String = "") throws -> ArcSidebar {
        let children = pinned.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        { "sidebar": { "containers": [ \(containers) { "global": {} }, {
          "spaces": [ "S", { "id": "S", "containerIDs": ["pinned", "PIN"] } ],
          "items": [ "PIN", { "id": "PIN", "parentID": null, "childrenIds": [\(children)],
                              "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "S" } } } } }
                     \(items) ]
        } ] } }
        """
        return try ArcSidebar.parse(Data(json.utf8))
    }

    @Test func readsSpacesFoldersAndToday() throws {
        let sidebar = try Self.fixture()
        #expect(sidebar.spaces.map(\.name) == ["Work", "Home"])
        let work = sidebar.spaces[0]
        #expect(work.profile == ArcSidebar.defaultProfile)
        #expect(work.pinned.tabs.map(\.url.host) == ["tracker.example.test", "wiki.example.test", "api.example.test"])
        guard case .folder("Docs", let docs) = work.pinned[1] else {
            Issue.record("Docs should be a folder")
            return
        }
        #expect(docs.count == 2)
        // The title someone gave the tab wins over the page's.
        #expect(work.pinned.tabs[1].title == "Handbook (renamed)")
        // A split view's tabs stay, one after the other.
        #expect(work.today.map(\.url.host) == ["news.example.test", "left.example.test", "right.example.test"])
    }

    @Test func findsSectionsByMarkerNotPosition() throws {
        let home = try Self.fixture().spaces[1]
        #expect(home.profile == "Profile 1")
        #expect(home.today.map(\.url.host) == ["shop.example.test"])
        #expect(home.pinned.tabs.map(\.url.host) == ["recipes.example.test", "trains.example.test"])
    }

    @Test func countsWhatItLeavesOut() throws {
        #expect(try Self.fixture().skipped == 1)  // the easel
    }

    @Test func favoritesGoByProfile() throws {
        let sidebar = try Self.fixture()
        #expect(sidebar.favorites[ArcSidebar.defaultProfile]?.isEmpty == false)
        #expect(sidebar.favorites["Profile 1"]?.isEmpty == false)
    }

    @Test func picksTheGlobalContainer() throws {
        let sidebar = try Self.sidebar(pinned: ["T"], items: """
        , "T", { "id": "T", "childrenIds": [], "data": { "tab": { "savedURL": "https://a.test/", "savedTitle": "A" } } }
        """, containers: """
        { "littleBrowser": { "_0": "X" } }, { "spaces": [], "items": [] },
        """)
        #expect(sidebar.spaces.first?.pinned == [.tab(Self.tab("A", "https://a.test/"))])
    }

    @Test func namesSpacesWithoutTitles() throws {
        #expect(try Self.sidebar(pinned: [], items: "").spaces.first?.name == "Space 1")
    }

    @Test func leavesOutPagesItCannotOpen() throws {
        let sidebar = try Self.sidebar(pinned: ["A", "B", "C"], items: """
        , "A", { "id": "A", "childrenIds": [], "data": { "tab": { "savedURL": "arc://settings", "savedTitle": "Settings" } } }
        , "B", { "id": "B", "childrenIds": [], "data": { "tab": { "savedURL": "", "savedTitle": "Empty" } } }
        , "C", { "id": "C", "childrenIds": [], "data": { "tab": { "savedURL": "https://c.test/", "savedTitle": "\\u200b C \\n" } } }
        """)
        #expect(sidebar.spaces.first?.pinned == [.tab(Self.tab("C", "https://c.test/"))])
        #expect(sidebar.skipped == 2)
    }

    @Test func leavesOutLiveAndEmptyFolders() throws {
        let sidebar = try Self.sidebar(pinned: ["L", "E"], items: """
        , "L", { "id": "L", "title": "PRs", "childrenIds": [], "data": { "list": { "automaticLiveFolderData": {} } } }
        , "E", { "id": "E", "title": "Empty", "childrenIds": [], "data": { "list": {} } }
        """)
        #expect(sidebar.spaces.first?.pinned.isEmpty == true)
        #expect(sidebar.skipped == 1)
    }

    @Test func survivesCyclesAndMissingChildren() throws {
        let sidebar = try Self.sidebar(pinned: ["F", "GONE"], items: """
        , "F", { "id": "F", "title": "Loop", "childrenIds": ["G"], "data": { "list": {} } }
        , "G", { "id": "G", "title": "Back", "childrenIds": ["F", "T"], "data": { "list": {} } }
        , "T", { "id": "T", "childrenIds": [], "data": { "tab": { "savedURL": "https://t.test/", "savedTitle": "T" } } }
        """)
        #expect(sidebar.spaces.first?.pinned.tabs.map(\.title) == ["T"])
    }

    @Test func keepsChildrenThatOnlyNameTheirParent() throws {
        let sidebar = try Self.sidebar(pinned: [], items: """
        , "T", { "id": "T", "parentID": "PIN", "childrenIds": [], "data": { "tab": { "savedURL": "https://t.test/", "savedTitle": "T" } } }
        """)
        #expect(sidebar.spaces.first?.pinned.tabs.map(\.title) == ["T"])
    }

    @Test func refusesWhatIsNotASidebar() {
        #expect(throws: ArcSidebarError.unreadable) { try ArcSidebar.parse(Data("<html>".utf8)) }
        #expect(throws: ArcSidebarError.unreadable) { try ArcSidebar.parse(Data("{}".utf8)) }
    }

    @Test func turnsColorsIntoHues() {
        #expect(ArcSidebar.hue(red: 1, green: 0, blue: 0) == 0)
        #expect(abs(ArcSidebar.hue(red: 0, green: 0, blue: 1)! - 4.0 / 6) < 0.0001)
        #expect(ArcSidebar.hue(red: 0.5, green: 0.5, blue: 0.5) == nil)
        #expect(ArcSidebar.hue(red: 1.4, green: -0.2, blue: 0) == 0)
    }
}

@Suite struct ArcImportTests {
    static let hues = [0.1, 0.2, 0.3]
    static let symbols = ["a", "b", "c"]
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let profileID = UUID()

    static func plan(
        _ sidebar: ArcSidebar, profiles: [ProfileRecord]? = nil, spaces: [SpaceRecord]? = nil, includesToday: Bool = true
    ) -> ArcImport {
        ArcImport(
            sidebar, profiles: profiles ?? [ProfileRecord(id: profileID, name: "Personal", favorites: [])],
            spaces: spaces ?? [emptySpace()], includesToday: includesToday, hues: hues, symbols: symbols, now: now
        )
    }

    static func emptySpace(name: String = "Personal") -> SpaceRecord {
        SpaceRecord(id: UUID(), name: name, symbol: "a", hue: 0, profileID: profileID, selectedTabID: nil, pinned: [], today: [])
    }

    static func tab(_ address: String) -> ArcSidebar.Tab {
        ArcSidebar.Tab(title: address, url: URL(string: address)!)
    }

    static func sidebar(name: String = "Personal", profile: String = ArcSidebar.defaultProfile) -> ArcSidebar {
        ArcSidebar(
            spaces: [ArcSidebar.Space(
                name: name, profile: profile, hue: nil,
                pinned: [.tab(tab("https://a.test/")), .folder(name: "Docs", children: [.tab(tab("https://b.test/"))])],
                today: [tab("https://c.test/")]
            )],
            favorites: [profile: [tab("https://f.test/")]], skipped: 0
        )
    }

    @Test func addsToASpaceOfTheSameName() {
        let plan = Self.plan(Self.sidebar(name: "personal"))
        #expect(plan.newSpaces.isEmpty)
        #expect(plan.newProfiles.isEmpty)
        #expect(plan.pinned.values.first?.count == 2)
        #expect(plan.today.values.first?.count == 1)
        #expect(plan.favorites[Self.profileID]?.count == 1)
        #expect(plan.tabCount == 4)
        #expect(plan.summary == [.init(name: "personal", isNew: false, pinned: 2, today: 1)])
    }

    @Test func aLoneEmptySpaceBecomesTheFirstArcSpace() throws {
        var sidebar = Self.sidebar(name: "Work")
        sidebar.spaces[0].hue = 0.77
        let space = Self.emptySpace()
        let plan = Self.plan(sidebar, spaces: [space])
        #expect(plan.takeover == .init(spaceID: space.id, name: "Work", hue: 0.77))
        #expect(plan.newSpaces.isEmpty)
        #expect(plan.pinned[space.id]?.count == 2)
    }

    @Test func aSpaceInUseIsNeverTakenOver() {
        var space = Self.emptySpace()
        space.today = [TabRecord(id: UUID(), title: "Open", url: URL(string: "https://open.test/"))]
        let plan = Self.plan(Self.sidebar(name: "Work"), spaces: [space])
        #expect(plan.takeover == nil)
        #expect(plan.newSpaces.map(\.name) == ["Work"])
    }

    @Test func makesNewSpacesOnTheDefaultProfile() throws {
        let plan = Self.plan(Self.sidebar(name: "Work"), spaces: [Self.emptySpace(), Self.emptySpace(name: "Other")])
        let space = try #require(plan.newSpaces.first)
        #expect(space.profileID == Self.profileID)
        #expect(space.hue == 0.3)
        #expect(space.symbol == "c")
        #expect(plan.newProfiles.isEmpty)
    }

    @Test func keepsOtherArcProfilesApart() throws {
        let plan = Self.plan(Self.sidebar(name: "Client", profile: "Profile 1"))
        let profile = try #require(plan.newProfiles.first)
        #expect(profile.name == "Client")
        #expect(profile.favorites.map(\.url) == [URL(string: "https://f.test/")])
        #expect(plan.newSpaces.first?.profileID == profile.id)
        #expect(plan.favorites.isEmpty)
    }

    @Test func sharesOneNewProfileAcrossItsSpaces() {
        var sidebar = Self.sidebar(name: "One", profile: "Profile 1")
        sidebar.spaces.append(Self.sidebar(name: "Two", profile: "Profile 1").spaces[0])
        let plan = Self.plan(sidebar)
        #expect(plan.newProfiles.count == 1)
        #expect(Set(plan.newSpaces.map(\.profileID)).count == 1)
    }

    @Test func keepsArcsColorWhenThereIsOne() {
        var sidebar = Self.sidebar(name: "Work")
        sidebar.spaces[0].hue = 0.77
        let plan = Self.plan(sidebar, spaces: [Self.emptySpace(), Self.emptySpace(name: "Other")])
        #expect(plan.newSpaces.first?.hue == 0.77)
    }

    @Test func pinnedTabsReturnHome() {
        let plan = Self.plan(Self.sidebar())
        guard case .tab(let tab) = plan.pinned.values.first?.first else {
            Issue.record("Expected a pinned tab")
            return
        }
        #expect(tab.pinnedURL == tab.url)
    }

    @Test func todayTabsStartTheirClockAtTheImport() {
        let tab = Self.plan(Self.sidebar()).today.values.first?.first
        #expect(tab?.lastActiveAt == Self.now)
        #expect(tab?.pinnedURL == nil)
    }

    @Test func canLeaveTodayBehind() {
        let plan = Self.plan(Self.sidebar(), includesToday: false)
        #expect(plan.today.isEmpty)
        #expect(plan.summary.first?.today == 0)
    }

    @Test func importingTwiceBringsNothingNew() {
        let first = Self.plan(Self.sidebar())
        var space = Self.emptySpace()
        space.pinned = first.pinned[first.pinned.keys.first!]!
        space.today = first.today[first.today.keys.first!]!
        let profile = ProfileRecord(id: Self.profileID, name: "Personal", favorites: first.favorites[Self.profileID]!)
        let second = Self.plan(Self.sidebar(), profiles: [profile], spaces: [space])
        #expect(second.tabCount == 0)
        #expect(second.pinned.isEmpty)
        #expect(second.today.isEmpty)
    }

    @Test func keepsOnlyTheNewTabsOfAFolder() throws {
        var space = Self.emptySpace()
        space.pinned = [.tab(TabRecord(id: UUID(), title: "B", url: URL(string: "https://b.test/")))]
        let plan = Self.plan(Self.sidebar(), spaces: [space])
        let added = try #require(plan.pinned[space.id])
        #expect(added.count == 1)  // the folder's only tab is already here
    }

    @Test func worksFromTheFixture() throws {
        let plan = Self.plan(try ArcSidebarTests.fixture())
        #expect(plan.takeover?.name == "Work")
        #expect(plan.newSpaces.map(\.name) == ["Home"])
        #expect(plan.newProfiles.map(\.name) == ["Home"])
        #expect(plan.tabCount > 0)
    }
}
