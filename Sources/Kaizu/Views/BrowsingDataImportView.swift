import AppKit
import BrowserCore
import SwiftUI
import UniformTypeIdentifiers

/// File → Import Browsing Data…: history and bookmarks from another browser.
/// Chromium browsers are read where they are; Safari hands over an export.
struct BrowsingDataImportView: View {
    nonisolated enum Loaded: Sendable {
        case single(BrowsingData)
        case archive(SafariExport.Archive)

        func data(history: SafariExport.Selection, bookmarks: SafariExport.Selection) -> BrowsingData {
            switch self {
            case .single(let data): data
            case .archive(let archive): archive.needsSelection ? archive.selected(history: history, bookmarks: bookmarks) : archive.combined
            }
        }
    }

    nonisolated enum Source: Hashable, Sendable {
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

        /// Reading a big history file takes a while, so it runs off the main thread.
        @concurrent
        func read() async throws -> Loaded {
            switch self {
            case .browser(let profile): .single(try profile.read())
            case .file(let url) where url.pathExtension.lowercased() == "zip": .archive(try SafariExport.readArchive(url))
            case .file(let url): .single(try SafariExport.read(url))
            }
        }
    }

    @Environment(BrowserStore.self) private var store
    private let browsers = ChromiumProfile.installed()
    @State private var file: URL?
    @State private var source: Source?
    @State private var loaded: (source: Source, contents: Loaded)?
    @State private var historyFile = SafariExport.Selection.skip
    @State private var bookmarkFile = SafariExport.Selection.skip
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

    private var preview: Loaded? { loaded?.source == source ? loaded?.contents : nil }

    private var multiFileArchive: SafariExport.Archive? {
        if case .archive(let archive) = preview, archive.needsSelection { return archive }
        return nil
    }

    private var data: BrowsingData? {
        preview?.data(history: historyFile, bookmarks: bookmarkFile)
    }

    private var bookmarks: BookmarkImport? {
        guard let data, let source else { return nil }
        return data.bookmarkFolder(named: source.folderName, skipping: space.pinnedAddresses)
    }

    var body: some View {
        let bookmarks = bookmarks
        let bringsHistory = (multiFileArchive != nil || includesHistory) && data?.visits.isEmpty == false
        let bringsBookmarks = (multiFileArchive != nil || includesBookmarks) && bookmarks != nil
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
                    FooterText("In Safari, choose File → Export Browsing Data to File… and select only Bookmarks and History. Choose the exported ZIP here.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(.secondary) }
                } else if let data {
                    if let archive = multiFileArchive {
                        Section {
                            filePicker("History", names: archive.historyFiles, selection: $historyFile)
                            filePicker("Bookmarks", names: archive.bookmarkFiles, selection: $bookmarkFile)
                        } footer: {
                            FooterText("Choose the files to bring into this space. Repeat the import for another profile.")
                        }
                    }
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
    private func filePicker(_ label: String, names: [String], selection: Binding<SafariExport.Selection>) -> some View {
        if !names.isEmpty {
            Picker(label, selection: selection) {
                Text("Skip").tag(SafariExport.Selection.skip)
                ForEach(names, id: \.self) { Text($0).tag(SafariExport.Selection.file($0)) }
                if names.count > 1 { Text("All files").tag(SafariExport.Selection.all) }
            }
        }
    }

    @ViewBuilder
    private func contents(of data: BrowsingData, bookmarks: BookmarkImport?) -> some View {
        Section {
            if multiFileArchive != nil {
                if !data.visits.isEmpty { LabeledContent("History", value: data.visits.count.counted("page")) }
                if let bookmarks { LabeledContent("New bookmarks", value: bookmarks.count.formatted()) }
            } else {
                if !data.visits.isEmpty {
                    Toggle("History: \(data.visits.count.counted("page"))", isOn: $includesHistory)
                }
                if let bookmarks {
                    Toggle("Bookmarks: \(bookmarks.count.formatted()) as a pinned folder", isOn: $includesBookmarks)
                }
            }
            if data.visits.isEmpty, bookmarks == nil, multiFileArchive == nil || !data.isEmpty {
                Text(data.isEmpty ? "Nothing here to bring across." : "You already have these bookmarks here.")
                    .foregroundStyle(.secondary)
            }
            if store.spaces.count > 1 {
                Picker("Into space", selection: Binding(get: { space.id }, set: { spaceID = $0 })) {
                    ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                        Text("\(index + 1). \(space.name) · \(space.profile.name)").tag(space.id)
                    }
                }
            } else {
                LabeledContent("Into space", value: "\(space.name) · \(space.profile.name)")
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
        loaded = nil
        historyFile = .skip
        bookmarkFile = .skip
        problem = nil
        guard let source else { return }
        do {
            let read = try await source.read()
            guard !Task.isCancelled else { return }
            loaded = (source, read)
            // Safari profiles share one bookmarks file; a lone file needs no choice.
            if case .archive(let archive) = read {
                if archive.historyFiles.count == 1 { historyFile = .file(archive.historyFiles[0]) }
                if archive.bookmarkFiles.count == 1 { bookmarkFile = .file(archive.bookmarkFiles[0]) }
            }
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
