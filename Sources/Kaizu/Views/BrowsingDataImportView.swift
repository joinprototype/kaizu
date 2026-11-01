import AppKit
import BrowserCore
import SwiftUI
import UniformTypeIdentifiers

/// File → Import Browsing Data…: history and bookmarks from another browser.
/// Chromium browsers are read where they are; Safari hands over an export.
struct BrowsingDataImportView: View {
    enum Source: Hashable, Sendable {
        case browser(ChromiumProfile)
        case file(URL)

        var title: String {
            switch self {
            case .browser(let profile): profile.title
            case .file(let url): url.lastPathComponent
            }
        }

        var folderName: String {
            switch self {
            case .browser(let profile): "\(profile.browser) Bookmarks"
            case .file(let url): url.pathExtension.lowercased() == "zip" ? "Safari Bookmarks" : "Imported Bookmarks"
            }
        }

        func read() throws -> BrowsingData {
            switch self {
            case .browser(let profile): try profile.read()
            case .file(let url): try SafariExport.read(url)
            }
        }
    }

    @Environment(BrowserStore.self) private var store
    private let browsers = ChromiumProfile.installed()
    @State private var file: URL?
    @State private var source: Source?
    @State private var data: BrowsingData?
    @State private var problem: String?
    @State private var spaceID: UUID?
    @State private var includesHistory = true
    @State private var includesBookmarks = true
    @State private var isImporting = false

    private var sources: [Source] {
        browsers.map(Source.browser) + (file.map { [.file($0)] } ?? [])
    }

    private var space: Space {
        store.spaces.first { $0.id == spaceID } ?? store.activeSpace
    }

    private var bookmarks: BookmarkImport? {
        guard let data, let source else { return nil }
        return data.bookmarkFolder(named: source.folderName, skipping: space.pinnedAddresses)
    }

    var body: some View {
        let bookmarks = bookmarks
        let bringsHistory = includesHistory && data?.visits.isEmpty == false
        let bringsBookmarks = includesBookmarks && bookmarks != nil
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Import from", selection: $source) {
                        if sources.isEmpty {
                            Text("No browsers found").tag(Source?.none)
                        }
                        ForEach(sources, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    LabeledContent("Safari, or a bookmarks file") {
                        Button("Choose File…", action: chooseFile)
                    }
                } footer: {
                    FooterText("In Safari, choose File → Export Browsing Data to File…, then pick the .zip here. Only its history and bookmarks are read, never its passwords or cards.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(.secondary) }
                } else if let data {
                    contents(of: data, bookmarks: bookmarks)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { UtilityWindows.closeBrowsingDataImport() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { start(history: bringsHistory, bookmarks: bringsBookmarks ? bookmarks : nil) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting || !(bringsHistory || bringsBookmarks))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 460, height: 460)
        .onAppear { source = sources.first }
        .task(id: source) { await load() }
    }

    @ViewBuilder
    private func contents(of data: BrowsingData, bookmarks: BookmarkImport?) -> some View {
        Section {
            if !data.visits.isEmpty {
                Toggle("History: \(data.visits.count.counted("page"))", isOn: $includesHistory)
            }
            if let bookmarks {
                Toggle("Bookmarks: \(bookmarks.count.formatted()) as a pinned folder", isOn: $includesBookmarks)
            }
            if data.visits.isEmpty, bookmarks == nil {
                Text(data.isEmpty ? "Nothing here to bring across." : "You already have these bookmarks here.")
                    .foregroundStyle(.secondary)
            }
            if store.spaces.count > 1 {
                Picker("Into space", selection: Binding(get: { space.id }, set: { spaceID = $0 })) {
                    ForEach(store.spaces) { Text($0.name).tag($0.id) }
                }
            }
        } footer: {
            FooterText(footer(for: data, bookmarks: bookmarks))
        }
    }

    private func footer(for data: BrowsingData, bookmarks: BookmarkImport?) -> String {
        var notes = ["Kaizu only reads this and doesn't change it. Logins and extensions stay behind."]
        if data.visits.count == BrowsingData.visitLimit {
            notes.append("History is the newest \(BrowsingData.visitLimit.formatted()) pages.")
        }
        if bookmarks?.count == BrowsingData.bookmarkLimit {
            notes.append("Bookmarks stop at \(BrowsingData.bookmarkLimit.formatted()).")
        }
        return notes.joined(separator: " ")
    }

    private func load() async {
        data = nil
        problem = nil
        guard let source else { return }
        do {
            let read = try await Task.detached { try source.read() }.value
            guard !Task.isCancelled else { return }
            data = read
        } catch {
            guard !Task.isCancelled else { return }
            problem = "Kaizu couldn't read this. If the browser is busy, quit it and try again."
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json, .html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        file = url
        source = .file(url)
    }

    private func start(history: Bool, bookmarks: BookmarkImport?) {
        isImporting = true
        let visits = history ? data?.visits ?? [] : []
        let space = space
        Task {
            await store.app.importBrowsingData(visits, bookmarks: bookmarks, into: space)
            UtilityWindows.closeBrowsingDataImport()
        }
    }
}
