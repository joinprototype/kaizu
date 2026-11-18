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
        #expect(plan.summary == [.init(name: "personal", isNew: false, sidebarPosition: 1, profileName: "Personal", pinned: 2, today: 1)])
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

    @Test func sameNamedDestinationsCannotCollapseIndependentArcProfiles() throws {
        var source = Self.sidebar(name: "Client", profile: "Profile 1")
        source.spaces.append(Self.sidebar(name: "Personal").spaces[0])
        source.favorites[ArcSidebar.defaultProfile] = [Self.tab("https://personal.test/")]
        let spaces = [Self.emptySpace(name: "Personal"), Self.emptySpace(name: "Client")]
        let plan = Self.plan(source, spaces: spaces)
        let client = try #require(plan.newProfiles.first)
        #expect(client.favorites.map(\.url) == [URL(string: "https://f.test/")])
        #expect(plan.favorites[Self.profileID]?.map(\.url) == [URL(string: "https://personal.test/")])
        #expect(plan.newSpaces.map(\.profileID) == [client.id])
        #expect(plan.pinned[spaces[1].id] == nil)

        var personal = spaces[0]
        personal.pinned = plan.pinned[personal.id] ?? []
        personal.today = plan.today[personal.id] ?? []
        let profiles = [ProfileRecord(id: Self.profileID, name: "Personal", favorites: plan.favorites[Self.profileID] ?? []), client]
        let again = Self.plan(source, profiles: profiles, spaces: [personal, spaces[1]] + plan.newSpaces)
        #expect(again.tabCount == 0)
        #expect(again.newSpaces.isEmpty)
        #expect(again.newProfiles.isEmpty)
    }

    @Test func repeatImportKeepsSameNamedWorkAndPersonalSpacesInTheirProfiles() throws {
        var source = Self.sidebar(name: "Inbox", profile: "Work")
        source.spaces[0].pinned = [.tab(Self.tab("https://work.test/"))]
        var personal = Self.sidebar(name: "Inbox").spaces[0]
        personal.pinned = [.tab(Self.tab("https://personal.test/"))]
        source.spaces.append(personal)
        source.favorites[ArcSidebar.defaultProfile] = [Self.tab("https://personal-mail.test/")]

        var home = Self.emptySpace()
        home.today = [TabRecord(id: UUID(), title: "Existing", url: URL(string: "https://existing.test/"))]
        let first = Self.plan(source, spaces: [home])
        let workProfile = try #require(first.newProfiles.first)
        let profiles = [
            ProfileRecord(id: Self.profileID, name: "Personal", favorites: first.favorites[Self.profileID] ?? []),
            workProfile
        ]
        let spaces = [home] + first.newSpaces
        let repeated = Self.plan(source, profiles: profiles, spaces: spaces)
        #expect(repeated.tabCount == 0)
        #expect(repeated.newSpaces.isEmpty)

        let added = Self.tab("https://new-work.test/")
        source.spaces[0].pinned.append(.tab(added))
        let updated = Self.plan(source, profiles: profiles, spaces: spaces)
        let workSpace = try #require(spaces.first { $0.profileID == workProfile.id })
        #expect(updated.tabCount == 1)
        #expect(updated.pinned[workSpace.id]?.tabs.map(\.pinnedURL) == [added.url])
        #expect(updated.summary.map(\.profileName) == [workProfile.name, "Personal"])
        #expect(updated.summary.first?.sidebarPosition == 2)
    }

    @Test func repeatImportUsesProfileFavoritesWhenSameNamedSpacesShareTheirTabs() throws {
        var source = Self.sidebar(name: "Inbox", profile: "Work")
        source.spaces.append(Self.sidebar(name: "Inbox", profile: "Home").spaces[0])
        source.favorites["Home"] = [Self.tab("https://personal-mail.test/")]
        let original = Self.emptySpace()
        let first = Self.plan(source, spaces: [original])
        let profiles = [ProfileRecord(id: Self.profileID, name: "Existing", favorites: [])] + first.newProfiles
        #expect(first.summary.map(\.sidebarPosition) == [2, 3])
        let spaces = [original] + first.newSpaces.reversed()
        let repeatPlan = Self.plan(source, profiles: profiles, spaces: spaces)
        #expect(repeatPlan.tabCount == 0)
        #expect(repeatPlan.summary.map(\.sidebarPosition) == [3, 2])
        #expect(repeatPlan.summary.allSatisfy { !$0.isNew })
        source.spaces[0].today.append(Self.tab("https://work-update.test/"))
        let updated = Self.plan(source, profiles: profiles, spaces: spaces)
        let work = try #require(first.newSpaces.first)
        #expect(updated.tabCount == 1)
        #expect(updated.today[work.id]?.map(\.url) == [URL(string: "https://work-update.test/")])
    }

    @Test(arguments: [ArcSidebar.defaultProfile, "Personal"])
    func siblingSpaceIdentifiesTheProfileOfAnOtherwiseIdenticalInbox(personalProfile: String) throws {
        var source = Self.sidebar(name: "Inbox", profile: "Work")
        source.favorites = [:]
        let personal = Self.sidebar(name: "Inbox", profile: personalProfile).spaces[0]
        let projects = Self.sidebar(name: "Projects", profile: "Work").spaces[0]
        source.spaces += [personal, projects]

        var home = Self.emptySpace()
        home.today = [TabRecord(id: UUID(), title: "Existing", url: URL(string: "https://existing.test/"))]
        let first = Self.plan(source, spaces: [home])
        let workInbox = try #require(first.newSpaces.first)
        let spaces = [home] + first.newSpaces
        let profiles = [ProfileRecord(id: Self.profileID, name: "Main", favorites: [])] + first.newProfiles

        source.spaces.swapAt(0, 1)
        let repeated = Self.plan(source, profiles: profiles, spaces: spaces)
        #expect(repeated.tabCount == 0)
        #expect(repeated.newSpaces.isEmpty)
        #expect(repeated.summary.map(\.sidebarPosition) == [3, 2, 4])

        let added = Self.tab("https://work.test/new-project")
        source.spaces[1].pinned.append(.tab(added))
        let updated = Self.plan(source, profiles: profiles, spaces: spaces)
        #expect(updated.tabCount == 1)
        #expect(updated.pinned[workInbox.id]?.tabs.map(\.pinnedURL) == [added.url])
    }

    @Test(arguments: [false, true])
    func unrelatedSpaceNameCannotOverrideAnExistingInboxPin(reverse: Bool) {
        let marker = Self.tab("https://personal.test/known-pin")
        let added = Self.tab("https://personal.test/new-pin")
        var source = Self.sidebar(name: "Inbox")
        source.spaces[0].pinned = [.tab(marker), .tab(added)]
        source.spaces.append(Self.sidebar(name: "Projects").spaces[0])

        if reverse { source.spaces.reverse() }

        let workID = UUID()
        var workInbox = Self.emptySpace(name: "Inbox")
        workInbox.profileID = workID
        var workProjects = Self.emptySpace(name: "Projects")
        workProjects.profileID = workID
        var personalInbox = Self.emptySpace(name: "Inbox")
        personalInbox.pinned = [.tab(TabRecord(id: UUID(), title: "Existing", url: marker.url, pinnedURL: marker.url))]
        let profiles = [ProfileRecord(id: workID, name: "Work", favorites: []),
                        ProfileRecord(id: Self.profileID, name: "Personal", favorites: [])]
        let plan = Self.plan(source, profiles: profiles, spaces: [workInbox, workProjects, personalInbox])
        #expect(plan.pinned[personalInbox.id]?.tabs.map(\.pinnedURL) == [added.url])
        #expect(plan.pinned[workInbox.id] == nil)
        #expect(plan.newSpaces.map(\.profileID) == [Self.profileID])
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

    @Test func repeatImportKeepsEditedFoldersAndNavigatedPins() throws {
        let home = Self.tab("https://b.test/")
        let nested = Self.tab("https://nested.test/")
        let new = Self.tab("https://new.test/")
        var source = Self.sidebar()
        source.spaces[0].pinned = [.folder(name: "Docs", children: [
            .tab(home), .folder(name: "API", children: [.tab(nested), .tab(new)])
        ])]
        let old = TabRecord(id: UUID(), title: "Renamed", url: URL(string: "https://b.test/later"), pinnedURL: home.url)
        let local = TabRecord(id: UUID(), title: "My local tab", url: URL(string: "https://local.test/"))
        let inner = FolderRecord(id: UUID(), name: "API", isExpanded: false, children: [
            .tab(TabRecord(id: UUID(), title: "Saved", url: nested.url)), .tab(local)
        ])
        let outer = FolderRecord(id: UUID(), name: "Docs", isExpanded: false, children: [.folder(inner), .tab(old)])
        var space = Self.emptySpace()
        space.pinned = [.folder(outer)]
        let plan = Self.plan(source, spaces: [space], includesToday: false)
        #expect(plan.pinned[space.id] == nil)
        #expect(plan.folderAdditions.keys.sorted() == [inner.id])
        let added = try #require(plan.folderAdditions[inner.id]?.tabs.first)
        #expect(added.pinnedURL == new.url)
        #expect(plan.addedItemIDs.contains(added.id))
        #expect(plan.summary.first?.pinned == 1)
        #expect(plan.tabCount == 2) // One nested tab and one favorite.
        #expect(plan.addedItemIDs.isDisjoint(with: [inner.id, outer.id, old.id, local.id]))
    }

    @Test func doesNotGuessBetweenSameNamedSiblingFolders() {
        let folder = { FolderRecord(id: UUID(), name: "Docs", isExpanded: false, children: []) }
        var space = Self.emptySpace()
        space.pinned = [.folder(folder()), .folder(folder())]
        var source = Self.sidebar()
        let twoDestinations = Self.plan(source, spaces: [space])
        #expect(twoDestinations.folderAdditions.isEmpty)
        #expect(twoDestinations.pinned[space.id]?.tabCount == 2)

        space.pinned.removeLast()
        source.spaces[0].pinned.append(.folder(name: "Docs", children: [.tab(Self.tab("https://second.test/"))]))
        let twoSources = Self.plan(source, spaces: [space])
        #expect(twoSources.folderAdditions.isEmpty)
        #expect(twoSources.pinned[space.id]?.tabCount == 3)
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
        let workID = try #require(plan.takeover?.spaceID)
        let imported = try #require(plan.pinned[workID]?.tabs)
        let renamed = try #require(imported.first { $0.title == "Handbook (renamed)" })
        #expect(renamed.customTitle == "Handbook (renamed)")
        #expect(imported.contains { $0.customTitle == nil })
        #expect(plan.tabCount > 0)
    }
}
