import BrowserCore
import DesignSystem
import SwiftUI

/// Row shared with the traffic lights: sidebar toggle and navigation buttons.
struct SidebarTopBar: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab?

    var body: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 72)
            IconButton(systemName: "sidebar.left", help: "Toggle Sidebar (⌘S)") {
                store.toggleSidebar()
            }
            IconButton(systemName: "arrow.left", help: "Back (⌘[)") {
                tab?.goBack()
            }
            .disabled(!(tab?.canGoBack ?? false))
            IconButton(systemName: "arrow.right", help: "Forward (⌘])") {
                tab?.goForward()
            }
            .disabled(!(tab?.canGoForward ?? false))
            if tab?.isLoading == true {
                IconButton(systemName: "xmark", help: "Stop (⌘.)") { tab?.stopLoading() }
            } else {
                IconButton(systemName: "arrow.clockwise", help: "Reload (⌘R)") { tab?.reload() }
                    .disabled(tab == nil)
            }
        }
        .frame(height: 28)
    }
}

/// Shows the current host; clicking opens the command bar to edit the URL.
struct AddressPill: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let tab: BrowserTab?
    @State private var isHovering = false
    @State private var isShowingSiteSettings = false

    var body: some View {
        HStack(spacing: 6) {
            // The lock opens the site's settings; the rest edits the address.
            if !store.didCopyLink, let tab, let url = tab.url, url.host() != nil {
                Button {
                    isShowingSiteSettings.toggle()
                } label: {
                    SiteGlyph(url: url, isLoading: tab.isLoading)
                        .id(tab.id)
                        .contentShape(Rectangle().inset(by: -4))
                }
                .buttonStyle(.plain)
                .help("Settings for This Site")
                .popover(isPresented: $isShowingSiteSettings, arrowEdge: .bottom) {
                    SiteSettingsView(tab: tab)
                        .environment(store)
                }
            }
            Button {
                store.showCommandBar(tab == nil ? .newTab : .currentTab)
            } label: {
                HStack(spacing: 6) {
                    if store.didCopyLink {
                        Label("Copied", systemImage: "checkmark")
                            .foregroundStyle(.secondary)
                            .transition(Motion.dissolving(.opacity.combined(with: .scale(scale: 0.9))))
                    } else if let tab, let url = tab.url {
                        if url.host() == nil {
                            SiteGlyph(url: url, isLoading: tab.isLoading)
                                .id(tab.id)
                        }
                        Text(url.displayHost)
                            .lineLimit(1)
                    } else {
                        Text("Search or enter address")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let tab, let url = tab.url, url.host() != nil {
                let isPaused = store.contentBlocker.isPaused(on: url, privateID: tab.profile.privateID)
                if isHovering || isPaused {
                    Button {
                        store.toggleBlockingOnCurrentSite()
                    } label: {
                        Image(systemName: isPaused ? "shield.slash" : "checkmark.shield")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isPaused ? "Blocking paused on this site. Click to resume." : "Pause blocking on this site")
                }
            }

            if isHovering, tab?.url != nil {
                Button {
                    store.copyLink()
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy Link (⇧⌘C)")
            }
        }
        .font(.system(size: 13.5))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(SidebarFill.subtle(scheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Ink.iron(scheme).opacity(isHovering ? 0.28 : 0.16), lineWidth: 0.75)
        }
        .onHoverFade($isHovering)
    }
}

/// The address pill's leading glyph. While a page loads, a compass needle
/// swings, searching; when it's in, the needle settles on north and gives
/// way to the lock again.
private struct SiteGlyph: View {
    let url: URL
    let isLoading: Bool
    @State private var showsNeedle = false
    @State private var angle = 0.0

    var body: some View {
        ZStack {
            if showsNeedle {
                CompassNeedle()
                    .rotationEffect(.degrees(angle))
                    .transition(.opacity)
            } else {
                Image(systemName: url.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(width: 12, height: 12)
        .task(id: isLoading) {
            if isLoading {
                // Quick loads don't get a needle at all.
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.snap) { showsNeedle = true }
                guard !Motion.isReduced else { return }
                var east = true
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.8)) { angle = east ? 30 : -22 }
                    east.toggle()
                    try? await Task.sleep(for: .milliseconds(800))
                }
            } else if showsNeedle {
                withAnimation(Motion.settle) { angle = 0 }
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.snap) { showsNeedle = false }
            }
        }
    }
}

/// A two-tone needle: the north half in claret, like the icon's compass rose.
private struct CompassNeedle: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let half = size.width * 0.22
            var north = Path()
            north.addLines([CGPoint(x: mid.x, y: 0), CGPoint(x: mid.x + half, y: mid.y), CGPoint(x: mid.x - half, y: mid.y)])
            var south = Path()
            south.addLines([CGPoint(x: mid.x, y: size.height), CGPoint(x: mid.x + half, y: mid.y), CGPoint(x: mid.x - half, y: mid.y)])
            context.fill(north, with: .color(Ink.claret(scheme)))
            context.fill(south, with: .color(.secondary))
        }
    }
}
