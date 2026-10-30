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
        let action = store.extensions.action(for: item)
        let icon = action?.icon(for: CGSize(width: 16, height: 16)) ?? item.icon
        Button {
            store.extensions.performAction(for: item, anchor: frame)
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
            if let options = item.context.optionsPageURL {
                Button("Options") { store.openTab(options) }
            }
            Button("Remove “\(item.name)”") { store.extensions.uninstall(item) }
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
                if host.installed.isEmpty {
                    Text("No extensions yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(host.installed) { item in
                    HStack(spacing: 10) {
                        if let icon = item.icon {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "puzzlepiece.extension").frame(width: 24, height: 24)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                            Text(item.version).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") { host.uninstall(item) }
                    }
                }
                HStack {
                    Button("Add Extension…", action: chooseExtension)
                    Spacer()
                }
            } footer: {
                FooterText("Add an unpacked extension folder or a .zip in the standard WebExtension format (Chrome, Firefox). Most popular extensions work; a few Chrome-only features don't.")
            }
            Section {
                if safariApps.isEmpty {
                    Text("No Safari web extensions found in Applications.")
                        .foregroundStyle(.secondary)
                }
                ForEach(safariApps, id: \.self) { app in
                    LabeledContent(app.deletingPathExtension().lastPathComponent) {
                        Button("Add") { Task { await host.install(from: app) } }
                    }
                }
            } header: {
                Text("From Safari")
            } footer: {
                FooterText("Safari extensions run here without their companion app, so anything that needs the app (password autofill, for example) may not work.")
            }
        }
        .formStyle(.grouped)
        .task { safariApps = await Task.detached(priority: .utility) { ExtensionHost.safariExtensionApps() }.value }
    }

    private func chooseExtension() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .zip]
        panel.prompt = "Add"
        panel.message = "Choose an extension folder (with manifest.json) or a .zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.extensions.install(from: url) }
    }
}
