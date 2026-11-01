import AppKit
import BrowserCore
import SwiftUI

/// Report a Broken Site…: a few answers, a chance to try the page without
/// blocking, and the exact text that goes out, ending in a Mail draft.
struct BrokenSiteReportView: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab
    /// The page when the report started; the tab may have moved on since.
    let url: URL
    @State private var problem: BrokenSiteReport.Problem?
    @State private var note = ""
    @State private var blockingTest = BrokenSiteReport.BlockingTest.notTried
    @State private var includesAddress = false
    @State private var status: String?

    private var report: BrokenSiteReport {
        BrokenSiteReport(
            url: url,
            problem: problem,
            note: note,
            blockingTest: blockingTest,
            includesAddress: includesAddress,
            details: BugReport.siteDetails(for: url, store: store)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("What's wrong?", selection: $problem) {
                        Text("Choose…").tag(BrokenSiteReport.Problem?.none)
                        ForEach(BrokenSiteReport.Problem.allCases, id: \.self) { problem in
                            Text(problem.rawValue).tag(Optional(problem))
                        }
                    }
                    TextField("Anything else? (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(report.site)
                }
                if store.contentBlocker.isEnabled {
                    Section {
                        Toggle("Block ads and trackers here", isOn: Binding(
                            get: { !store.contentBlocker.isPaused(on: url) },
                            set: { _ in
                                store.contentBlocker.togglePause(on: url)
                                tab.reload()
                            }
                        ))
                        if store.contentBlocker.isPaused(on: url) {
                            Picker("Did that fix it?", selection: $blockingTest) {
                                ForEach(BrokenSiteReport.BlockingTest.allCases, id: \.self) { test in
                                    Text(test.rawValue).tag(test)
                                }
                            }
                        }
                    } footer: {
                        FooterText("Blocking is the usual cause. Turning it off reloads the page, and it stays off for this site.")
                    }
                }
                Section {
                    Toggle("Include the full page address", isOn: $includesAddress)
                    DisclosureGroup("What will be sent") {
                        Text(report.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } footer: {
                    FooterText(includesAddress
                        ? "Addresses can hold private details, like an order number."
                        : "Only the site's name, never the page you were on.")
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
                Button("Send…", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem == nil)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 480, height: 500)
    }

    private func send() {
        let report = report
        if BugReport.compose(subject: report.subject, items: [report.text]) {
            UtilityWindows.closeBrokenSiteReport()
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report.text, forType: .string)
            status = "Mail isn't set up here. Report copied: paste it into an email to \(BugReport.recipient)."
        }
    }
}
