#if DEBUG
import AppKit
import BrowserCore

extension DebugHooks {
    /// `currency`: KAIZU_TYPE answered through the real feed and its cache.
    static func qaCurrency() {
        let query = ProcessInfo.processInfo.environment["KAIZU_TYPE"] ?? "100 usd to kzt"
        CurrencyFeed.shared.requestIfNeeded()
        Task {
            try? await Task.sleep(for: .seconds(4))
            let answer = QuickAnswer.evaluate(query, rates: CurrencyFeed.shared.rates)
            log("QA currency \(query): \(answer?.answer ?? "no answer") (\(answer?.question ?? "-"))")
            NSApp.terminate(nil)
        }
    }

    /// `commands`: logs what the command bar would offer for KAIZU_TYPE.
    static func qaCommands(_ store: BrowserStore) {
        Task {
            try? await Task.sleep(for: .seconds(1))
            let query = ProcessInfo.processInfo.environment["KAIZU_TYPE"] ?? ""
            let commands = store.commands(matching: query)
            let found = commands.map { "\($0.title) [\($0.shortcut ?? "")]" }
            log("QA commands for \(query): \(found)")
            // KAIZU_RUN=1: runs the first one after the menus have been
            // rebuilt (the Spaces menu remakes its items), e.g. for "edit space".
            guard ProcessInfo.processInfo.environment["KAIZU_RUN"] == "1", let first = commands.first else { return }
            try? await Task.sleep(for: .seconds(1.2))
            _ = store.commands(matching: query)
            first.perform()
            log("QA ran \(first.title): space editor open \(store.spaceDraft != nil)")
        }
    }

    /// `learn`: on first launch, picks the second of two tabs twice after
    /// typing "ex". On the next launch, logs what "ex" leads with.
    static func qaLearn(_ store: BrowserStore) {
        let tabs = store.activeSpace.today
        if tabs.count < 2 {
            store.openTab(URL(string: "https://example.com/"))
            let second = store.openTab(URL(string: "https://example.org/"))
            store.app.learn(.tab(second, in: store.activeSpace), for: "ex", in: store.activeSpace.profile)
            store.app.learn(.tab(second, in: store.activeSpace), for: "ex", in: store.activeSpace.profile)
            store.app.save()
        } else {
            let lead = store.app.topChoice(for: "ex", among: tabs.map { .tab($0, in: store.activeSpace) }, in: store.activeSpace.profile)
            let leads = lead.map { if case .tab(let tab, _) = $0 { tab.url?.absoluteString ?? "" } else { "" } } ?? "nothing"
            log("QA learned: ex leads with \(leads)")
        }
    }
}
#endif
