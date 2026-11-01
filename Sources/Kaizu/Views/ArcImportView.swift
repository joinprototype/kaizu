import BrowserCore
import SwiftUI

/// File → Import from Arc…: shows what would come across, then brings it in.
struct ArcImportView: View {
    @Environment(BrowserStore.self) private var store
    let source: URL
    @State private var sidebar: ArcSidebar?
    @State private var problem: String?
    @State private var includesToday = true

    var body: some View {
        Group {
            if let sidebar {
                preview(of: sidebar)
            } else if let problem {
                Text(problem)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 460, height: 420)
        .task { await load() }
    }

    private func preview(of sidebar: ArcSidebar) -> some View {
        let plan = store.arcImport(of: sidebar, includesToday: includesToday)
        let inSpaces = plan.summary.reduce(0) { $0 + $1.pinned + $1.today }
        return VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(Array(plan.summary.enumerated()), id: \.offset) { _, space in
                        LabeledContent(space.name, value: detail(of: space))
                    }
                    if plan.tabCount > inSpaces {
                        LabeledContent("Favorites", value: "\(plan.tabCount - inSpaces)")
                    }
                } footer: {
                    FooterText("Logins, history and extensions stay in Arc. Kaizu only reads Arc's sidebar and doesn't change it.")
                }
                Section {
                    Toggle("Bring Today's tabs too", isOn: $includesToday)
                } footer: {
                    if sidebar.skipped > 0 {
                        FooterText("\(sidebar.skipped) \(sidebar.skipped == 1 ? "item" : "items") Kaizu can't open, like Easels and Notes, will stay behind.")
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { UtilityWindows.closeArcImport() }
                    .keyboardShortcut(.cancelAction)
                Button(plan.tabCount == 0 ? "Nothing New" : "Import \(plan.tabCount) \(plan.tabCount == 1 ? "Tab" : "Tabs")") {
                    store.app.front.importFromArc(plan)
                    UtilityWindows.closeArcImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.tabCount == 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func detail(of space: ArcImport.SpaceSummary) -> String {
        if space.pinned == 0, space.today == 0 { return "Nothing new" }
        return [
            space.pinned > 0 ? "\(space.pinned) pinned" : nil,
            space.today > 0 ? "\(space.today) in Today" : nil,
        ].compactMap(\.self).joined(separator: ", ")
    }

    private func load() async {
        let source = source
        let result = await Task.detached { Result { try ArcSidebar.load(from: source) } }.value
        switch result {
        case .success(let loaded):
            sidebar = loaded
        case .failure(ArcSidebarError.unreadable):
            Log.session.error("Couldn't make sense of Arc's sidebar file")
            problem = "Kaizu couldn't read Arc's sidebar. Tell us with Help, then Report a Bug."
        case .failure:
            problem = "Arc's sidebar isn't on this Mac. Open Kaizu on the Mac where you use Arc to import it."
        }
    }
}
