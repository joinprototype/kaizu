import SwiftUI
import UniformTypeIdentifiers
import WebEngine

struct ImportedRuleListSettings: View {
    let blocker: ContentBlocker
    @State private var failure: String?

    var body: some View {
        let lists = blocker.importedLists
        Section {
            ForEach(lists.entries) { entry in
                HStack {
                    Toggle(entry.name, isOn: Binding(get: { entry.enabled }, set: { enabled in
                        change { try await lists.setEnabled(enabled, id: entry.id) }
                    }))
                    Spacer()
                    Button("Remove") { change { try await lists.remove(entry.id) } }
                }
                if let problem = lists.problems[entry.id] {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Import Rule List…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                panel.prompt = "Import"
                if panel.runModal() == .OK, let url = panel.url {
                    change { try await lists.add(url) }
                }
            }
            if let problem = lists.indexError {
                Text("Couldn’t read saved rule lists. " + problem)
            }
        } header: {
            Text("Custom blocking rules")
        } footer: {
            FooterText("Import a Safari content-blocker JSON file. Rules apply on the next page load wherever ad and tracker blocking is on.")
        }
        .disabled(lists.busy || lists.indexError != nil)
        .alert("Couldn’t update rule lists", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func change(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await action() }
            catch { failure = error.localizedDescription }
        }
    }
}
