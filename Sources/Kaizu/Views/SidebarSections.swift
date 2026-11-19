import BrowserCore
import DesignSystem
import SwiftUI

/// Big icon tiles for the profile's most-used sites, shared by its spaces.
struct FavoritesGrid: View {
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
struct PinnedSection: View {
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
struct TodaySection: View {
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
        .accessibleRow("New Tab") { store.showCommandBar(.newTab) }
        .onHoverFade($isHovering)
    }
}
