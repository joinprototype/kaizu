import BrowserCore
import Foundation

struct ClosedTab {
    let spaceID: UUID
    let profileID: UUID
    let record: TabRecord
    var navigationState: Data?

    // Keep older URLs and titles reopenable without retaining unlimited page state.
    static let historyCount = 32
    static let maxStateBytes = 1024 * 1024
}

extension Array where Element == ClosedTab {
    @MainActor
    mutating func remember(_ tab: BrowserTab, in spaceID: UUID) {
        let state = tab.currentState
        append(ClosedTab(spaceID: spaceID, profileID: tab.profile.id, record: tab.record,
                         navigationState: state.flatMap { $0.count <= ClosedTab.maxStateBytes ? $0 : nil }))
        if count > ClosedTab.historyCount {
            self[count - ClosedTab.historyCount - 1].navigationState = nil
        }
    }
}
