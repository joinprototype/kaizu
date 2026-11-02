import BrowserCore
import SwiftUI

struct SidebarView: View {
    @Environment(BrowserStore.self) private var store
    let space: Space
    @Namespace private var rows

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarTopBar(tab: store.selectedTab(in: space))
            AddressPill(tab: store.selectedTab(in: space))
            if !store.extensions.installed.isEmpty, !store.isPrivate {
                ExtensionsBar()
            }
            // Favorites belong to the profile, so they stay put while spaces
            // that share it slide by underneath.
            if !space.profile.favorites.isEmpty {
                FavoritesGrid(space: space)
                    .id(space.profile.id)
                    .transition(.opacity)
            }
            SpacePager()
                .frame(maxHeight: .infinity, alignment: .top)
            if let playing = store.backgroundMediaTab {
                NowPlayingCard(tab: playing)
                    .transition(Motion.dissolving(.move(edge: .bottom).combined(with: .opacity)))
            }
            SpaceSwitcher()
        }
        // Media starts and stops from page events, outside any animation.
        .animation(Motion.snap, value: store.backgroundMediaTab?.id)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                SidebarChart()
                WindowDragArea()
            }
        }
        .environment(\.sidebarRowNamespace, rows)
    }
}

/// Each space's own part of the sidebar (pinned and today), side by side:
/// the active space in place, a neighbor beside it while a swipe uncovers
/// it, and the space just left sliding away to its side.
private struct SpacePager: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        GeometryReader { geometry in
            // One sidebar width apart: the section plus the sidebar's margins.
            let page = geometry.size.width + 20
            ZStack(alignment: .topLeading) {
                ForEach(store.pagerSpaces) { space in
                    SpaceSection(space: space)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .modifier(PagerOffset(position: store.pagerPosition(of: space), page: page))
                        .transition(.asymmetric(insertion: .offset(x: store.spaceSwitchForward ? page : -page), removal: .identity))
                }
            }
        }
        .clipped()
    }
}

/// A modifier of its own so each scroll event of a swipe re-renders only
/// the offsets, not the sections.
private struct PagerOffset: ViewModifier {
    @Environment(BrowserStore.self) private var store
    let position: Int
    let page: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: CGFloat(position) * page + store.spaceSwipeOffset)
    }
}

/// What the sidebar is drawn on: rhumb lines running out from a compass rose
/// low in the corner, which turns to a new bearing with each space.
private struct SidebarChart: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width * 1.06, 300)
            let center = CGPoint(x: geometry.size.width * 0.68, y: geometry.size.height - side * 0.36)
            ZStack {
                RhumbWeb(size: geometry.size, center: center)
                TurningRose()
                    .scaleEffect(side / TurningRose.size)
                    .position(center)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// On its own, so a swipe turns it without redrawing the sidebar.
private struct TurningRose: View {
    @Environment(BrowserStore.self) private var store
    /// Not a whole number of points: every space points somewhere new.
    private static let turn = 67.5
    /// One picture, scaled: the sidebar's edge goes through every width.
    static let size: CGFloat = 300

    var body: some View {
        let index = store.spaces.firstIndex { $0.id == store.activeSpaceID } ?? 0
        let swipe = Double(store.spaceSwipeOffset / max(store.sidebarWidth, 1))
        CompassRose(size: Self.size)
            // An empty page has its own rose.
            .opacity(store.selectedTab == nil ? 0 : 0.3)
            .animation(Motion.hover, value: store.selectedTab == nil)
            .rotationEffect(.degrees((Double(index) - swipe) * Self.turn))
    }
}

private struct SpaceSection: View {
    let space: Space

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if !space.profile.isPrivate {
                    PinnedSection(space: space)
                }
                TodaySection(space: space)
            }
        }
        .scrollIndicators(.never)
    }
}

/// Row shared with the traffic lights: sidebar toggle and navigation buttons.
private struct SidebarTopBar: View {
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
private struct AddressPill: View {
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

            if let url = tab?.url, url.host() != nil {
                let isPaused = store.contentBlocker.isPaused(on: url)
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

/// Big icon tiles for the profile's most-used sites, shared by its spaces.
private struct FavoritesGrid: View {
    @Environment(BrowserStore.self) private var store
    let space: Space

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(space.profile.favorites) { tab in
                FavoriteTile(tab: tab, isSelected: tab.id == store.selectedTabIDs[space.id])
                    .tabDropTarget(.favorites(before: tab.id))
            }
        }
        .tabDropTarget(.favorites(before: nil))
    }
}

/// The space's pinned tabs and folders.
private struct PinnedSection: View {
    @Environment(BrowserStore.self) private var store
    let space: Space

    var body: some View {
        SectionHeader(title: space.name, isName: true) {
            IconButton(systemName: "folder.badge.plus", help: "New Folder") { store.newFolder() }
        }
        .tabDropTarget(.pinned(folder: nil, before: nil))
        ForEach(space.pinned) { item in
            SidebarItemView(item: item, space: space, depth: 0)
                .transition(Motion.row)
        }
    }
}

/// Unpinned tabs, newest first; archived automatically when left alone.
private struct TodaySection: View {
    @Environment(BrowserStore.self) private var store
    let space: Space

    var body: some View {
        SectionHeader(title: "Today", note: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
            if !space.today.isEmpty {
                Button("Clear") { store.clearToday(in: space) }
                    .buttonStyle(.plain)
                    .help("Close all of today's tabs")
            }
        }
        .padding(.top, 8)
        .tabDropTarget(.today(before: space.today.first?.id))
        NewTabRow()
        ForEach(space.today) { tab in
            TabRow(tab: tab, isSelected: tab.id == store.selectedTabIDs[space.id])
                .tabDropTarget(.today(before: tab.id), opensGap: true)
                .transition(Motion.row)
        }
        // Room to drop a tab at the end of the list.
        Color.clear
            .frame(height: 60)
            .contentShape(Rectangle())
            .tabDropTarget(.today(before: nil))
    }
}

/// A space's name, lettered like a place on the chart; or a section,
/// lettered like water, with a word in passing that gives way on hover.
private struct SectionHeader<Trailing: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    var isName = false
    var note: String?
    @ViewBuilder let trailing: () -> Trailing
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(isName ? Typeface.display(23) : Typeface.water(17))
                .foregroundStyle(isName ? AnyShapeStyle(Ink.iron(scheme)) : AnyShapeStyle(.secondary))
                .lineLimit(1)
            Spacer()
            if isHovering {
                trailing()
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let note {
                Text(note)
                    .font(Typeface.water(12.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: isName ? 36 : 28)
        .contentShape(Rectangle())
        .onHoverFade($isHovering)
    }
}

private struct NewTabRow: View {
    @Environment(BrowserStore.self) private var store
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            Text("New tab")
            Spacer()
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .sidebarRow(isHovering: isHovering)
        .onTapGesture { store.showCommandBar(.newTab) }
        .onHoverFade($isHovering)
    }
}
