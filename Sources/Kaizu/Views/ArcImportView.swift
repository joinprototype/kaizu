import AppKit
import BrowserCore
import Storage
import SwiftUI
import UniformTypeIdentifiers

/// File → Import from Arc…: shows what would come across, then brings it in.
struct ArcImportView: View {
    @Environment(BrowserStore.self) private var store
    @State private var source: URL
    @State private var readID = UUID()

    init(source: URL) {
        _source = State(initialValue: source)
    }

    private var isMarkdown: Bool { source.pathExtension.lowercased() == "md" }

    @State private var sidebar: ArcSidebar?
    @State private var problem: String?
    @State private var includesToday = true

    var body: some View {
        Group {
            if let sidebar {
                preview(of: sidebar)
            } else if let problem {
                VStack(spacing: 12) {
                    Text(problem)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Choose File…", action: chooseFile)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 460, height: 420)
        .task(id: readID) { await load() }
    }

    private func preview(of sidebar: ArcSidebar) -> some View {
        let plan = store.arcImport(of: sidebar, includesToday: includesToday)
        let inSpaces = plan.summary.reduce(0) { $0 + $1.pinned + $1.today }
        return VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("File", value: source.lastPathComponent)
                    ForEach(Array(plan.summary.enumerated()), id: \.offset) { _, space in
                        LabeledContent {
                            Text(detail(of: space))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(space.name)
                                Text(destination(of: space))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if plan.tabCount > inSpaces {
                        LabeledContent("Favorites", value: "\(plan.tabCount - inSpaces)")
                    }
                } footer: {
                    if isMarkdown {
                        FooterText("Each space gets a separate profile. Links become pinned tabs under their exported headings. Choose StorableSidebar.json to bring the original profile groups, Favorites and Today tabs.")
                    } else {
                        FooterText("To bring history, use File → Import Browsing Data…. Logins and extensions stay in Arc.")
                    }
                }
                if !isMarkdown {
                    Section {
                        Toggle("Bring Today's tabs too", isOn: $includesToday)
                    } footer: {
                        if sidebar.skipped > 0 {
                            FooterText("\(sidebar.skipped.counted("item")) Kaizu can't open, like Easels and Notes, will stay behind.")
                        }
                    }
                } else if sidebar.skipped > 0 {
                    FooterText("Skipped \(sidebar.skipped.counted("link")) with an unsupported address.")
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("Choose File…", action: chooseFile)
                Spacer()
                Button("Cancel") { UtilityWindows.closeArcImport() }
                    .keyboardShortcut(.cancelAction)
                Button(plan.tabCount == 0 ? "Nothing New" : "Import \(plan.tabCount.counted("Tab"))") {
                    store.importFromArc(plan)
                    UtilityWindows.closeArcImport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.tabCount == 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func destination(of space: ArcImport.SpaceSummary) -> String {
        let position = space.isNew ? "New space \(space.sidebarPosition)" : "Space \(space.sidebarPosition)"
        guard let profile = space.profileName else { return position }
        return "\(position) · \(profile) profile"
    }

    private func detail(of space: ArcImport.SpaceSummary) -> String {
        if space.pinned == 0, space.today == 0 { return "Nothing new" }
        return [
            space.pinned > 0 ? "\(space.pinned) pinned" : nil,
            space.today > 0 ? "\(space.today) in Today" : nil,
        ].compactMap(\.self).joined(separator: ", ")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.message = "Choose Arc Data Export.md or a saved StorableSidebar.json."
        panel.allowedContentTypes = [.json, UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sidebar = nil
        problem = nil
        source = url
        readID = UUID()
    }

    @concurrent
    private nonisolated static func read(_ source: URL) async -> Result<ArcSidebar, any Error> {
        Result { try ArcSidebar.load(from: source) }
    }

    private func load() async {
        let result = await Self.read(source)
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let loaded):
            sidebar = loaded
        case .failure(ArcSidebarError.unreadable):
            Log.session.error("Couldn't make sense of Arc's sidebar file")
            problem = "Choose Arc Data Export.md or StorableSidebar.json to preview its spaces and tabs."
        case .failure:
            problem = "Choose a saved sidebar or the Markdown file from Arc → Settings → Advanced → Export Data."
        }
    }
}
