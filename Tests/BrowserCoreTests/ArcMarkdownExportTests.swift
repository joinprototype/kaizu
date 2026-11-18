import Foundation
import Testing
@testable import BrowserCore

struct ArcMarkdownExportTests {
    @Test func loadsSpacesAndNestedFoldersFromSavedFile() throws {
        let file = try #require(Bundle.module.url(forResource: "Arc Data Export", withExtension: "md", subdirectory: "Fixtures"))
        let sidebar = try ArcSidebar.load(from: file)
        #expect(sidebar.spaces.map(\.name) == ["Design", "Personal"])
        #expect(Set(sidebar.spaces.map(\.profile)).count == 2)
        #expect(sidebar.skipped == 1)
        #expect(sidebar.favorites.isEmpty && sidebar.spaces.allSatisfy { $0.today.isEmpty })
        let pinned = sidebar.spaces[0].pinned
        #expect(pinned.count == 3)
        guard case .folder("Research", let research) = pinned[1], research.count == 2,
              case .folder("Type", let typography) = research[1] else {
            Issue.record("Expected the nested Type folder inside Research")
            return
        }
        #expect(typography.tabs.first?.url.absoluteString == "https://type.example.test/specimen?size=24#sample")
        #expect(sidebar.spaces[1].pinned.tabs.map(\.url.host) == ["calendar.example.test", "mail.example.test"])
    }

    @Test func acceptsWindowsLineEndingsAndUntitledHeadings() throws {
        let text = "\u{feff}#\r\n##\r\n- https://example.test/\r\n"
        let sidebar = try ArcSidebar.parseMarkdownExport(Data(text.utf8))
        #expect(sidebar.spaces.first?.name == "Untitled Space")
        #expect(sidebar.spaces.first?.pinned == [.folder(name: "Folder", children: [
            .tab(.init(title: "example.test", url: URL(string: "https://example.test/")!))
        ])])
    }

    @Test func rejectsMissingSpaceOrMissingWebLinks() {
        for text in ["- https://example.test/", "# Work\n- file:///tmp/item", "Notes for today"] {
            #expect(throws: ArcSidebarError.unreadable) { try ArcSidebar.parseMarkdownExport(Data(text.utf8)) }
        }
    }
}
