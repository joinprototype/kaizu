import AppKit
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// A tab dragged from the sidebar. Deliberately not text: web views take
    /// text drops, and would swallow a tab dragged onto the page.
    static let kaizuTab = UTType(exportedAs: "com.joinprototype.kaizu.tab")
}

extension NSPasteboard.PasteboardType {
    static let kaizuTab = Self(UTType.kaizuTab.identifier)
}

/// What dragging a sidebar tab carries: the tab's id.
struct TabDrag: Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .kaizuTab) { drag in
            Data(drag.id.uuidString.utf8)
        } importing: { data in
            guard let drag = TabDrag(data) else { throw CocoaError(.coderReadCorrupt) }
            return drag
        }
    }

    init(id: UUID) {
        self.id = id
    }

    init?(_ data: Data?) {
        guard let data, let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { return nil }
        self.id = id
    }

    /// The tab on an AppKit drag, for views SwiftUI's drop handling can't
    /// reach (the page, under its web view).
    init?(_ pasteboard: NSPasteboard) {
        self.init(pasteboard.data(forType: .kaizuTab))
    }
}
