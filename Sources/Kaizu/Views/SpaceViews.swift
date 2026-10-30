import SwiftUI

/// Bottom of the sidebar: one button per space, plus "new space".
struct SpaceSwitcher: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var spaceToDelete: Space?
    @Namespace private var activeIndicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, space in
                SpaceButton(space: space, isActive: space.id == store.activeSpaceID, indicator: activeIndicator)
                    .help(index < 9 ? "\(space.name) (⌃\(index + 1))" : space.name)
                    .contextMenu {
                        Button("Edit Space…") { store.beginEditing(space) }
                        Button("Delete Space…", role: .destructive) { spaceToDelete = space }
                            .disabled(store.spaces.count < 2)
                    }
            }
            Spacer()
            if TowelDay.isToday {
                TowelButton()
            }
            if !DownloadManager.shared.items.isEmpty {
                DownloadsButton()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            IconButton(systemName: "plus", help: "New Space (⇧⌘N)") {
                store.beginNewSpace()
            }
        }
        // One disc that slides (and changes color) to the active space,
        // rather than one per button cross-fading, which dims it mid-way.
        .background(alignment: .topLeading) {
            Circle()
                .fill(store.activeSpace.theme.accent(scheme))
                .matchedGeometryEffect(id: store.activeSpaceID, in: activeIndicator, isSource: false)
        }
        // Downloads start from WebKit, outside any animation.
        .animation(Motion.snap, value: DownloadManager.shared.items.isEmpty)
        .confirmationDialog(
            "Delete “\(spaceToDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { spaceToDelete != nil },
                set: { if !$0 { spaceToDelete = nil } }
            ),
            presenting: spaceToDelete
        ) { space in
            Button("Delete Space", role: .destructive) { store.delete(space) }
        } message: { space in
            if store.deletesProfile(space) {
                Text("Its tabs, favorites and all website data (cookies, logins, site storage) will be permanently removed.")
            } else {
                Text("Its pinned and today tabs will be removed. Logins stay with the spaces that share its profile.")
            }
        }
    }
}

private struct SpaceButton: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let space: Space
    let isActive: Bool
    let indicator: Namespace.ID
    @State private var isHovering = false

    var body: some View {
        Button {
            store.switchTo(space)
        } label: {
            Image(systemName: space.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(space.theme.onAccent(scheme)) : AnyShapeStyle(.secondary))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(isHovering && !isActive ? SidebarFill.hover(scheme) : .clear)
                }
                // Where the switcher's active disc goes.
                .matchedGeometryEffect(id: space.id, in: indicator)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHoverFade($isHovering)
    }
}

struct SpaceEditor: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @State private var draft: SpaceDraft

    init(draft: SpaceDraft) {
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { draft.spaceID == nil }
    private var theme: Theme { Theme.forHue(draft.hue) }
    private let symbolColumns = Array(repeating: GridItem(.fixed(36), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: draft.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.onAccent(scheme))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.accent(scheme)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "New Space" : "Edit Space")
                        .font(.title3.weight(.semibold))
                    Text("Spaces keep their own tabs and look.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            if isNew {
                section("Logins") {
                    Picker("Logins", selection: $draft.profile) {
                        Text("Separate (new profile)").tag(SpaceDraft.ProfileChoice.new)
                        ForEach(store.profiles) { profile in
                            Text("Shared with \(profile.name)").tag(SpaceDraft.ProfileChoice.existing(profile.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            section("Color") {
                HStack(spacing: 10) {
                    ForEach(Theme.all) { option in
                        Circle()
                            .fill(option.accent(scheme))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle()
                                    .strokeBorder(.primary.opacity(option == theme ? 0.7 : 0), lineWidth: 2)
                                    .padding(-4)
                            }
                            .help(option.name)
                            .onTapGesture {
                                // The window takes the color at once, as a preview.
                                withAnimation(Motion.glide) {
                                    draft.hue = option.hue
                                    store.previewTheme = option
                                }
                            }
                    }
                }
                .padding(.leading, 4)
            }

            section("Appearance") {
                Picker("Appearance", selection: $draft.appearance) {
                    ForEach(Space.Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: draft.appearance) { store.previewAppearance = draft.appearance }
            }

            section("Icon") {
                LazyVGrid(columns: symbolColumns, alignment: .leading, spacing: 8) {
                    ForEach(Space.symbols, id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(draft.symbol == symbol ? theme.accent(scheme).opacity(0.25) : .secondary.opacity(0.08))
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { draft.symbol = symbol }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { store.spaceDraft = nil }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create Space" : "Save") { store.commit(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 380)
        .onDisappear {
            // Saved, the space has the color now; cancelled, it goes back.
            withAnimation(Motion.glide) { store.previewTheme = nil }
            store.previewAppearance = nil
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }
}
