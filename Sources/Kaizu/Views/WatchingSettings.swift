import SwiftUI

/// Settings → Watching: the parts of pages Kaizu checks for you.
struct WatchingSettings: View {
    @Environment(BrowserStore.self) private var store
    @State private var isChecking = false

    var body: some View {
        let watches = store.app.watches
        Form {
            Section {
                if watches.parts.isEmpty {
                    Text("Nothing watched yet. On a page, choose View → Watch Part of Page…, then click a price or a stock label.")
                        .foregroundStyle(.secondary)
                }
                ForEach(watches.parts) { part in
                    WatchedPartRow(part: part)
                }
            } footer: {
                FooterText("Kaizu opens each page out of sight about once an hour while it’s running, with that profile’s sign-ins, and tells you when the part’s text changes.")
            }
            if !watches.parts.isEmpty {
                Section {
                    LabeledContent("Check all pages") {
                        Button(isChecking ? "Checking…" : "Check Now") {
                            isChecking = true
                            Task {
                                await store.app.watcher.check(watches.parts)
                                isChecking = false
                            }
                        }
                        .disabled(isChecking)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct WatchedPartRow: View {
    @Environment(BrowserStore.self) private var store
    let part: WatchedPart

    var body: some View {
        LabeledContent {
            HStack {
                Button("Open") { store.app.openWatched(part) }
                Button("Stop") { store.app.watches.remove(part.id) }
            }
        } label: {
            HStack(spacing: 6) {
                if part.isUnseen {
                    Circle().fill(.tint).frame(width: 6, height: 6)
                }
                Text(part.title.isEmpty ? part.host : part.title)
                    .lineLimit(1)
            }
            Text(part.text)
                .lineLimit(2)
            Text(status)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(part.isLost ? .orange : .secondary)
        }
    }

    private var status: String {
        if part.isLost { return "\(part.host) · Can’t find it on the page anymore" }
        var pieces = [part.host]
        if let changedAt = part.changedAt, let previous = part.previous {
            pieces.append("Was “\(previous)”, changed \(changedAt.formatted(.relative(presentation: .named)))")
        } else if let checkedAt = part.checkedAt {
            pieces.append("Checked \(checkedAt.formatted(.relative(presentation: .named)))")
        }
        return pieces.joined(separator: " · ")
    }
}
