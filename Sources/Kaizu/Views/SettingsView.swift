import AppKit
import BrowserCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            LinkSettings()
                .tabItem { Label("Links", systemImage: "arrow.triangle.branch") }
            ExtensionSettings()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @Environment(BrowserStore.self) private var store
    @State private var isDefaultBrowser = DefaultBrowser.isCurrent

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                LabeledContent("Default browser") {
                    if isDefaultBrowser {
                        Text("Kaizu is your default browser")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Make Default") {
                            Task {
                                await DefaultBrowser.makeCurrent()
                                isDefaultBrowser = DefaultBrowser.isCurrent
                            }
                        }
                    }
                }
                Picker("Search engine", selection: $settings.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Show \(settings.searchEngine.name) suggestions", isOn: $settings.searchSuggestions)
                    .disabled(!settings.searchEngine.offersSuggestions)
            } footer: {
                FooterText(settings.searchEngine.offersSuggestions
                    ? "Suggestions send what you type in the command bar to \(settings.searchEngine.name) as you type. Addresses and shortcuts aren't sent."
                    : "\(settings.searchEngine.name) doesn't offer suggestions.")
            }
            Section {
                Picker("Archive Today tabs after", selection: $settings.archiveAfter) {
                    ForEach(Settings.ArchiveInterval.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                FooterText("Unpinned tabs you haven't looked at in this long are archived. Find them again from the command bar (⌘T).")
            }
            Section {
                Toggle("Picture in picture when leaving a playing video", isOn: $settings.autoPictureInPicture)
            } footer: {
                FooterText("The video floats over everything while you browse other tabs, and goes back into its page when you return.")
            }
            Section {
                Picker("Quick search from any app", selection: $settings.quickBarKey) {
                    Text("Off").tag(Settings.QuickBarKey?.none)
                    ForEach(Settings.QuickBarKey.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .onChange(of: settings.quickBarKey) { store.applyQuickBarKey() }
            } footer: {
                if let key = settings.quickBarKey, store.isQuickBarKeyTaken {
                    FooterText("\(key.title) is already used by macOS or another app. Pick a different shortcut.")
                } else {
                    FooterText("Like Spotlight, for the web: the command bar comes up over whatever you're doing. Answers show right there; pages open in a little window.")
                }
            }
            Section {
                ForEach($settings.searchShortcuts) { $shortcut in
                    HStack {
                        TextField("Keyword", text: $shortcut.keyword, prompt: Text("yt"))
                            .frame(width: 56)
                        TextField("Name", text: $shortcut.name, prompt: Text("YouTube"))
                            .frame(width: 110)
                        TextField("Search URL", text: $shortcut.template, prompt: Text("https://site.com/search?q=%s"))
                        Button {
                            settings.searchShortcuts.removeAll { $0.id == shortcut.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                }
                HStack {
                    Button("Add Shortcut") {
                        settings.searchShortcuts.append(SearchShortcut(keyword: "", name: "", template: ""))
                    }
                    Spacer()
                    Button("Restore Defaults") { settings.searchShortcuts = SearchShortcut.builtIn }
                        .disabled(settings.searchShortcuts == SearchShortcut.builtIn)
                }
            } header: {
                Text("Search shortcuts")
            } footer: {
                FooterText("Type a keyword and a space in the command bar to search a site: “yt lofi”. %s marks where your search goes.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        let blocker = store.contentBlocker
        Form {
            Section {
                Toggle("Block ads and trackers", isOn: Binding(get: { blocker.isEnabled }, set: blocker.setEnabled))
                Toggle("Reject cookie pop-ups automatically", isOn: Binding(get: { blocker.isCookieRejectionEnabled }, set: blocker.setCookieRejectionEnabled))
            } footer: {
                FooterText("Also always on: HTTPS-first browsing, tracking-parameter removal and the Global Privacy Control signal.")
            }
            Section("Blocking paused on") {
                if blocker.pausedSites.isEmpty {
                    Text("No sites. Use the shield in the address bar to pause blocking on a site.")
                        .foregroundStyle(.secondary)
                }
                ForEach(blocker.pausedSites.sorted(), id: \.self) { site in
                    LabeledContent(site) {
                        Button("Resume") { blocker.resume(site) }
                    }
                }
            }
            Section("Site permissions") {
                let sites = store.settings.sitePermissions
                if sites.isEmpty {
                    Text("No sites. Sites you allow or block appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sites.keys.sorted(), id: \.self) { host in
                    LabeledContent {
                        Button("Forget") { store.settings.sitePermissions[host] = nil }
                    } label: {
                        Text(host)
                        Text(Self.summary(sites[host] ?? [:]))
                    }
                }
            }
            Section {
                LabeledContent("Browsing history") {
                    Button("Clear History…") { store.clearHistory() }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// "Camera allowed · Microphone blocked"
    private static func summary(_ devices: [String: Bool]) -> String {
        devices.keys.sorted().map { "\($0.capitalized) \(devices[$0] == true ? "allowed" : "blocked")" }
            .joined(separator: " · ")
    }
}

private struct LinkSettings: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                Picker("Links from other apps open in", selection: $settings.externalLinks) {
                    ForEach(Settings.ExternalLinks.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                ForEach($settings.linkRoutes) { $route in
                    HStack {
                        TextField("Site", text: $route.pattern, prompt: Text("site.com or site.com/path"))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                        Picker("Space", selection: $route.spaceID) {
                            ForEach(store.spaces) { Text($0.name).tag($0.id) }
                        }
                        .frame(width: 140)
                        Button {
                            settings.linkRoutes.removeAll { $0.id == route.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .labelsHidden()
                }
                Button("Add Rule") {
                    settings.linkRoutes.append(LinkRoute(pattern: "", spaceID: store.activeSpace.id))
                }
            } header: {
                Text("Air Traffic Control")
            } footer: {
                FooterText("Links from other apps that match a rule open in that space, with its logins. The first matching rule wins.")
            }
        }
        .formStyle(.grouped)
    }
}

private enum DefaultBrowser {
    @MainActor
    static var isCurrent: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?.standardizedFileURL
            == Bundle.main.bundleURL.standardizedFileURL
    }

    /// macOS asks the user to confirm.
    @MainActor
    static func makeCurrent() async {
        try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
    }
}

/// Grouped-form footers default to trailing alignment for multi-line text.
struct FooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
