import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Toolbar buttons for installed extensions, under the address bar.
struct ExtensionsBar: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.extensions.installed) { item in
                ExtensionButton(item: item)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ExtensionButton: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let item: ExtensionHost.Installed
    @State private var frame: CGRect = .zero
    @State private var isHovering = false

    var body: some View {
        let action = store.extensions.action(for: item, on: store.selectedTab)
        let icon = action?.icon(for: CGSize(width: 16, height: 16)) ?? item.icon
        Button {
            store.extensions.performAction(for: item, on: store.selectedTab, anchor: frame)
        } label: {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                }
            }
            .frame(width: 16, height: 16)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? SidebarFill.hover(scheme) : .clear)
                    .animation(Motion.hover, value: isHovering)
            )
            .overlay(alignment: .topTrailing) {
                if let badge = action?.badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(.red))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(action?.isEnabled == false ? 0.4 : 1)
        .help(action?.label ?? item.name)
        .onHoverFade($isHovering)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .contextMenu {
            if let site = store.extensions.availableSite(for: item, on: store.selectedTab) {
                Button("Allow Access to \(site.host ?? site.string)…") {
                    store.extensions.requestSite(for: item, on: store.selectedTab)
                }
            }
            if let options = item.context.optionsPageURL {
                Button("Options") { store.openTab(options) }
            }
            Button("Remove “\(item.name)”") { store.extensions.uninstall(item.id) }
        }
    }
}

/// Settings → Extensions.
struct ExtensionSettings: View {
    @Environment(BrowserStore.self) private var store
    @State private var safariApps: [URL] = []

    var body: some View {
        let host = store.extensions
        Form {
            Section {
                if !host.hasRegistrations {
                    Text("No extensions yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(host.installed) { item in
                    InstalledExtensionRow(item: item) { host.uninstall(item.id) }
                    ForEach(host.additionalSites(for: item), id: \.self) { site in
                        LabeledContent(site) {
                            Button("Remove Access") { host.removeSite(site, for: item) }
                        }
                    }
                }
                ForEach(host.unavailable) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Retry") { Task { await host.load(item.id) } }
                            .disabled(host.loading.contains(item.id))
                        Button("Remove") { host.uninstall(item.id) }
                    }
                }
                HStack {
                    Button("Add Extension…", action: chooseExtension)
                    Spacer()
                }
            } footer: {
                FooterText("Choose a Mac app containing a Safari web extension, an unpacked extension folder, or a .zip. Some extensions depend on APIs their original browser provides.")
            }
            Section {
                if safariApps.isEmpty {
                    Text("No Safari web extensions found in Applications.")
                        .foregroundStyle(.secondary)
                }
                ForEach(safariApps, id: \.self) { app in
                    LabeledContent(app.deletingPathExtension().lastPathComponent) {
                        let added = host.hasSafariApp(app)
                        let adding = host.isAddingSafariApp(app)
                        Button(added ? "Added" : adding ? "Adding…" : "Add") {
                            Task { await host.install(from: app) }
                        }
                        .disabled(added || adding)
                    }
                }
            } header: {
                Text("From Safari")
            } footer: {
                FooterText("Keep the Mac app installed. Kaizu loads its web extension from the app. Features that use a desktop connection, such as biometric vault unlock, may be unavailable.")
            }
        }
        .formStyle(.grouped)
        .task { safariApps = await Task.detached(priority: .utility) { ExtensionHost.safariExtensionApps() }.value }
    }

    private func chooseExtension() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle, .folder, .zip]
        panel.prompt = "Add"
        panel.message = "Choose a Mac app with a Safari web extension, an extension folder, or a .zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.extensions.install(from: url) }
    }
}

/// Background scripts can fail after WebKit has accepted an installation.
private struct InstalledExtensionRow: View {
    let item: ExtensionHost.Installed
    let remove: () -> Void
    @State private var messages: [String] = []

    var body: some View {
        HStack(spacing: 10) {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "puzzlepiece.extension").frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                Text(item.version).font(.caption).foregroundStyle(.secondary)
                if !messages.isEmpty {
                    DisclosureGroup("Extension issues (\(messages.count))") {
                        Text(messages.joined(separator: "\n"))
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            Spacer()
            Button("Remove", action: remove)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: WKWebExtensionContext.errorsDidUpdateNotification, object: item.context)) { _ in
            refresh()
        }
    }

    private func refresh() {
        messages = item.context.errors.map(\.localizedDescription)
    }
}
