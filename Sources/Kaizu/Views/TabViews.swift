import SwiftUI

/// A pinned-section entry, rendered recursively so folders can nest.
struct SidebarItemView: View {
    @Environment(BrowserStore.self) private var store
    let item: SidebarItem
    let space: Space
    let depth: Int
    /// The folder this item sits in; nil at the top level.
    var parent: Folder?

    var body: some View {
        switch item {
        case .tab(let tab):
            TabRow(tab: tab, isSelected: tab.id == store.selectedTabIDs[space.id], depth: depth)
                .tabDropTarget(.pinned(folder: parent, before: tab.id), opensGap: true)
        case .folder(let folder):
            FolderRow(folder: folder, depth: depth)
            if folder.isExpanded {
                // Imported bookmarks can put thousands of tabs in one folder.
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(folder.children) { child in
                        SidebarItemView(item: child, space: space, depth: depth + 1, parent: folder)
                    }
                }
            }
        }
    }
}

struct TabRow: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.sidebarRowNamespace) private var rowNamespace
    let tab: BrowserTab
    let isSelected: Bool
    var depth = 0
    @State private var isHovering = false

    var body: some View {
        let inSplit = store.isInSplit(tab)
        HStack(spacing: 8) {
            FaviconView(tab: tab, size: 16)
            if store.renamingTabID == tab.id {
                RenameField(prompt: "Tab name", name: tab.displayTitle) { store.rename(tab, to: $0) } onCancel: {
                    store.renamingTabID = nil
                }
                .font(.system(size: 13))
            } else {
                Text(tab.displayTitle)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if tab.isPlayingMedia || tab.isMuted {
                RowAction(
                    systemName: tab.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    help: tab.isMuted ? "Unmute Tab" : "Mute Tab"
                ) { tab.toggleMute() }
            }
            if inSplit, !isHovering {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help("In split view")
            }
            if isHovering, tab.hasWanderedFromPin {
                RowAction(systemName: "arrow.uturn.backward", help: "Back to the pinned page") { tab.returnToPin() }
            }
            if isHovering, !isSelected, !inSplit,
               store.activeSpace.splitTabs.count < BrowserStore.maxSplitPanes {
                RowAction(systemName: "rectangle.split.2x1", help: "Open in Split View (⌃⇧=)") { store.addToSplit(tab) }
            }
            if isHovering {
                RowAction(systemName: "xmark", help: "Close Tab (⌘W)", weight: .bold) { store.close(tab) }
            }
        }
        .sidebarRow(depth: depth, isSelected: isSelected, isHovering: isHovering)
        .sidebarRowGeometry(tab.id, in: rowNamespace)
        .onTapGesture { store.select(tab) }
        .onHoverFade($isHovering)
        .draggable(TabDrag(id: tab.id)) {
            Label(tab.displayTitle, systemImage: "globe")
                .padding(6)
        }
        .contextMenu { TabContextMenu(tab: tab) }
    }
}

/// A sidebar row's name, being edited: Return or clicking away saves, Esc cancels.
private struct RenameField: View {
    let prompt: String
    let name: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @State private var draft = ""
    @State private var isCancelled = false
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField(prompt, text: $draft)
            .textFieldStyle(.plain)
            .focused($isEditing)
            .onAppear {
                draft = name
                isEditing = true
            }
            .onSubmit { onCommit(draft) }
            .onExitCommand {
                isCancelled = true
                onCancel()
            }
            .onChange(of: isEditing) { if !isEditing, !isCancelled { onCommit(draft) } }
    }
}

/// Small trailing button on a tab row (pause, split, close…).
private struct RowAction: View {
    let systemName: String
    let help: String
    var weight: Font.Weight = .semibold
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: weight))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct FolderRow: View {
    @Environment(BrowserStore.self) private var store
    let folder: Folder
    let depth: Int
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                .frame(width: 10)
            Image(systemName: folder.isExpanded ? "folder" : "folder.fill")
                .font(.system(size: 12))
            if store.renamingFolderID == folder.id {
                RenameField(prompt: "Folder name", name: folder.name) { store.rename(folder, to: $0) } onCancel: {
                    store.renamingFolderID = nil
                }
            } else {
                Text(folder.name)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .font(.system(size: 13))
        .sidebarRow(depth: depth, isHovering: isHovering)
        .onTapGesture { store.toggle(folder) }
        .onHoverFade($isHovering)
        .tabDropTarget(.pinned(folder: folder, before: nil))
        .contextMenu {
            Button("Rename") { store.renamingFolderID = folder.id }
            Button("Delete Folder") { store.delete(folder) }
        }
    }
}

struct FavoriteTile: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.sidebarRowNamespace) private var rowNamespace
    let tab: BrowserTab
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        FaviconView(tab: tab, size: 18)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? SidebarFill.selected(scheme) : isHovering ? SidebarFill.selected(scheme).opacity(0.7) : SidebarFill.subtle(scheme))
                    .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 1, y: 1)
            )
            // Morphs from (and back into) the tab's row when favorited.
            .sidebarRowGeometry(tab.id, in: rowNamespace)
            .contentShape(Rectangle())
            .onTapGesture { store.select(tab) }
            .onHoverFade($isHovering)
            .help(tab.displayTitle)
            .draggable(TabDrag(id: tab.id)) {
                FaviconView(tab: tab, size: 24).padding(6)
            }
            .contextMenu { TabContextMenu(tab: tab) }
    }
}

/// Context menu adapted to where the tab lives (favorites, pinned or today).
private struct TabContextMenu: View {
    @Environment(BrowserStore.self) private var store
    let tab: BrowserTab

    var body: some View {
        let space = store.activeSpace
        let isFavorite = tab.profile.favorites.contains(tab)
        let isToday = space.today.contains(tab)

        if !store.isPrivate {
            if isToday {
                Button("Pin Tab") { store.move(tab, to: .pinned(folder: nil, before: nil)) }
            } else {
                Button("Move to Today") { store.move(tab, to: .today(before: space.today.first?.id)) }
            }
            if !isFavorite {
                Button("Add to Favorites") { store.move(tab, to: .favorites(before: nil)) }
                Menu("Move to Folder") {
                    Button("New Folder") { store.newFolder(with: tab) }
                    let folders = space.pinned.folders
                    if !folders.isEmpty {
                        Divider()
                    }
                    ForEach(folders) { folder in
                        Button(folder.name) { store.move(tab, to: .pinned(folder: folder, before: nil)) }
                    }
                }
                let others = store.spaces.filter { $0 !== space }
                if !others.isEmpty {
                    Menu("Move to Space") {
                        ForEach(others) { other in
                            Button(other.name) { store.move(tab, toSpace: other) }
                        }
                    }
                }
            }
            Divider()
        }
        if store.isInSplit(tab) {
            Button("Remove from Split View") { store.removeFromSplit(tab) }
        } else if tab !== store.selectedTab {
            Button("Open in Split View") { store.addToSplit(tab) }
                .disabled(space.splitTabs.count >= BrowserStore.maxSplitPanes)
        }
        Divider()
        if tab.isPlayingMedia || tab.isMuted {
            Button(tab.isMuted ? "Unmute Tab" : "Mute Tab") { tab.toggleMute() }
        }
        if tab.hasWanderedFromPin {
            Button("Back to Pinned Page") { tab.returnToPin() }
        }
        if !isFavorite {
            Button("Rename…") { store.renamingTabID = tab.id }
        }
        Button("Copy Link") { store.copyLink(of: tab) }
            .disabled(tab.url == nil)
        Button("Copy as Markdown Link") { store.copyLink(of: tab, asMarkdown: true) }
            .disabled(tab.url == nil)
        Button("Duplicate Tab") { store.openTab(tab.url, after: tab) }
            .disabled(tab.url == nil)
        if !store.isPrivate {
            Button("Move to New Window") { store.moveToNewWindow(tab) }
        }
        Divider()
        Button(isToday ? "Close Tab" : "Reset Tab") { store.close(tab) }
    }
}

struct FaviconView: View {
    let tab: BrowserTab
    let size: CGFloat

    var body: some View {
        Group {
            if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .fill(.secondary.opacity(0.25))
                    .overlay {
                        Text(tab.displayTitle.prefix(1).uppercased())
                            .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
