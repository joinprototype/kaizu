import BrowserCore
import DesignSystem
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
/// low in the sidebar, which turns to a new bearing with each space.
private struct SidebarChart: View {
    /// Clear of the sidebar's edges, so the rose reads as drawn on the chart
    /// rather than cut off by the window.
    private static let margin: CGFloat = 18
    /// The space switcher and its margin below the rose.
    private static let footer: CGFloat = 46

    var body: some View {
        GeometryReader { geometry in
            // The rose turns to any bearing, so it must fit whole in a circle this wide.
            let side = max(0, min(geometry.size.width - Self.margin * 2, 160))
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height - Self.footer - side / 2)
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
            .opacity(store.selectedTab == nil ? 0 : 0.16)
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
