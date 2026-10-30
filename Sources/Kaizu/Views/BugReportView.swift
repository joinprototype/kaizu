import AppKit
import SwiftUI

/// Help → Report a Bug…
struct BugReportView: View {
    @Environment(BrowserStore.self) private var store
    @State private var summary = ""
    @State private var includesDiagnostics = true
    @State private var isWriting = false
    @State private var status: String?

    private var isEmpty: Bool {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $summary)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                } header: {
                    Text("What went wrong?")
                } footer: {
                    FooterText("The site you were on and what you did just before help most.")
                }
                Section {
                    Toggle("Include diagnostics", isOn: $includesDiagnostics)
                } footer: {
                    FooterText(includesDiagnostics
                        ? "Your Mac's model, a few Kaizu settings (blocking, extensions, how many tabs), this session's log and crash reports from the last two weeks. Addresses in the log are scrambled. Never your history or what's on your pages."
                        : "Only the Kaizu and macOS versions are included.")
                }
            }
            .formStyle(.grouped)
            HStack {
                if let status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show in Finder") {
                    Task { await reveal() }
                }
                Button("Send…") {
                    Task { await send() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isEmpty)
            }
            .disabled(isWriting)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 520, height: 430)
    }

    private func send() async {
        guard let zip = await write() else { return }
        if BugReport.compose(summary: summary, attachment: zip) {
            summary = ""
            UtilityWindows.closeBugReport()
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([zip])
            status = "Mail isn't set up here. Send the zip in Finder to \(BugReport.recipient)."
        }
    }

    /// The report unzipped (to look through) and zipped (to send another way).
    private func reveal() async {
        guard let zip = await write() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([zip.deletingPathExtension(), zip])
    }

    private func write() async -> URL? {
        isWriting = true
        status = "Gathering…"
        defer { isWriting = false }
        do {
            let zip = try await BugReport.write(summary: summary, includingDiagnostics: includesDiagnostics, store: store)
            status = nil
            return zip
        } catch {
            status = "Couldn't write the report: \(error.localizedDescription)"
            return nil
        }
    }
}
