import AppKit
import SwiftUI
import WebKit

extension BrowserStore {
    /// The old space slides out to its side while the new one comes in
    /// (see SpacePager); `animation` is the swipe's spring when one ends it.
    func switchTo(_ space: Space, animation: Animation? = Motion.glide) {
        guard space.id != activeSpaceID else { return }
        let from = spaces.firstIndex { $0.id == activeSpaceID } ?? 0
        let leaving = activeSpaceID
        spaceSwitchForward = (spaces.firstIndex { $0 === space } ?? 0) > from
        leavingSpaceID = leaving
        withAnimation(animation) {
            activeSpaceID = space.id
            revealingSpaceID = nil
            spaceSwipeOffset = 0
        } completion: { [weak self] in
            if self?.leavingSpaceID == leaving { self?.leavingSpaceID = nil }
        }
        // What was open over the old space's page stays with it.
        capture = nil
        reader = nil
        closePeek()
        endHidingItems()
        space.selectedTab?.activate()
        focusWebView()
        scheduleSave()
    }

    /// What the sidebar shows side by side: the active space, plus one
    /// that's leaving or being uncovered by a swipe.
    var pagerSpaces: [Space] {
        spaces.filter { $0.id == activeSpaceID || $0.id == leavingSpaceID || $0.id == revealingSpaceID }
    }

    /// -1, 0 or 1: left of the active space, the active space, right of it.
    func pagerPosition(of space: Space) -> Int {
        guard let active = spaces.firstIndex(where: { $0.id == activeSpaceID }),
              let index = spaces.firstIndex(where: { $0 === space })
        else { return 0 }
        return (index - active).signum()
    }

    var revealingSpace: Space? {
        spaces.first { $0.id == revealingSpaceID }
    }

    func switchToSpace(number: Int) {
        guard spaces.indices.contains(number - 1) else { return }
        switchTo(spaces[number - 1])
    }

    func switchToAdjacentSpace(_ offset: Int) {
        if let space = adjacentSpace(offset) {
            switchTo(space)
        }
    }

    /// Two-finger swipe left/right over the sidebar switches spaces, like
    /// Arc. The sidebar follows the fingers one to one, with the next space
    /// beside it (rubber-banding past the first and last), and on release
    /// a flick or a swipe past halfway carries on into the next space at the
    /// fingers' speed; otherwise it springs back.
    func installSpaceSwipeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window, self.isSidebarVisible || self.isSidebarPeeking,
                  event.locationInWindow.x < self.sidebarWidth
            else { return event }
            switch event.phase {
            case .began:
                self.spaceSwipeTravel = 0
                self.spaceSwipeSamples = []
                self.spaceSwipeGeneration += 1
            case .changed:
                guard var travel = self.spaceSwipeTravel, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { break }
                // Vertical from the start: it's a scroll, leave it alone.
                if travel == 0, abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
                    self.spaceSwipeTravel = nil
                    break
                }
                // Positive when the fingers move left, whichever way scrolling is set.
                travel += event.scrollingDeltaX * (event.isDirectionInvertedFromDevice ? -1 : 1)
                self.trackSpaceSwipe(to: travel, at: event.timestamp)
            case .ended, .cancelled:
                guard let travel = self.spaceSwipeTravel else { break }
                self.spaceSwipeTravel = nil
                self.finishSpaceSwipe(travel: travel, at: event.timestamp, switches: event.phase == .ended)
            default:
                break
            }
            return event
        }
    }

    /// `travel`: how far the fingers have moved, positive to the left.
    func trackSpaceSwipe(to travel: CGFloat, at time: TimeInterval) {
        spaceSwipeTravel = travel
        spaceSwipeSamples.append((time, travel))
        spaceSwipeSamples.removeAll { time - $0.time > 0.08 }
        let neighbor = adjacentSpace(travel > 0 ? 1 : -1)
        if revealingSpaceID != neighbor?.id {
            revealingSpaceID = neighbor?.id
        }
        let page = sidebarWidth
        spaceSwipeOffset = neighbor == nil ? -Self.rubberBand(travel, over: page) : -min(max(travel, -page), page)
    }

    /// `time`: when the fingers lifted. Fingers that stopped before lifting
    /// have no speed left, however fast they moved earlier.
    func finishSpaceSwipe(travel: CGFloat, at time: TimeInterval, switches: Bool) {
        let page = sidebarWidth
        let direction: CGFloat = travel > 0 ? 1 : -1
        let recent = spaceSwipeSamples.filter { time - $0.time <= 0.08 }
        var velocity: CGFloat = 0  // travel per second
        if let first = recent.first, let last = recent.last, last.time > first.time {
            velocity = (last.travel - first.travel) / (last.time - first.time)
        }
        // Where the flick would carry it, as when paging a scroll view.
        let projected = travel + velocity * 0.15
        if switches, let next = adjacentSpace(Int(direction)), abs(projected) > page / 2, projected * direction > 0 {
            let remaining = max(page - abs(travel), 1)
            switchTo(next, animation: Self.swipeSpring(speed: velocity * direction, distance: remaining))
        } else {
            let distance = abs(spaceSwipeOffset)
            let swipe = spaceSwipeGeneration
            withAnimation(Self.swipeSpring(speed: -velocity * direction, distance: distance)) {
                spaceSwipeOffset = 0
            } completion: { [weak self] in
                // Unless another swipe has started since.
                guard let self, self.spaceSwipeGeneration == swipe else { return }
                self.revealingSpaceID = nil
            }
        }
    }

    /// A spring that starts at the fingers' speed (toward where it's going).
    private static func swipeSpring(speed: CGFloat, distance: CGFloat) -> Animation? {
        guard !Motion.isReduced else { return nil }
        let velocity = distance > 1 ? min(max(speed, 0) / distance, 20) : 0
        return .interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: velocity)
    }

    /// Past the first or last space the sidebar gives less the further you pull.
    private static func rubberBand(_ travel: CGFloat, over page: CGFloat) -> CGFloat {
        let stretch = (1 - 1 / (abs(travel) * 0.55 / page + 1)) * page
        return travel < 0 ? -stretch : stretch
    }

    private func adjacentSpace(_ offset: Int) -> Space? {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }),
              spaces.indices.contains(index + offset)
        else { return nil }
        return spaces[index + offset]
    }

    // MARK: - Editing

    func beginNewSpace() {
        spaceDraft = SpaceDraft(
            name: "",
            hue: Theme.all[spaces.count % Theme.all.count].hue,
            symbol: Space.symbols[spaces.count % Space.symbols.count],
            profile: .new
        )
    }

    func beginEditing(_ space: Space) {
        spaceDraft = SpaceDraft(
            spaceID: space.id, name: space.name, hue: space.hue, symbol: space.symbol,
            profile: .existing(space.profile.id), appearance: space.appearance
        )
    }

    func commit(_ draft: SpaceDraft) {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let id = draft.spaceID, let space = spaces.first(where: { $0.id == id }) {
            space.name = name
            space.hue = draft.hue
            space.symbol = draft.symbol
            space.appearance = draft.appearance
        } else {
            let space = Space(profile: profile(for: draft.profile, name: name), name: name, symbol: draft.symbol, hue: draft.hue)
            space.appearance = draft.appearance
            spaces.append(space)
            switchTo(space)
        }
        spaceDraft = nil
        scheduleSave()
    }

    private func profile(for choice: SpaceDraft.ProfileChoice, name: String) -> Profile {
        if case .existing(let id) = choice, let profile = profiles.first(where: { $0.id == id }) {
            return profile
        }
        let profile = Profile(name: name)
        profiles.append(profile)
        return profile
    }

    // MARK: - Deleting

    /// Whether deleting `space` also deletes its profile (no other space uses it).
    func deletesProfile(_ space: Space) -> Bool {
        !spaces.contains { $0 !== space && $0.profile === space.profile }
    }

    /// Removes the space and its tabs; when it was the profile's last space,
    /// the profile's favorites and all of its website data go too.
    func delete(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0 === space }) else { return }
        let deletingProfile = deletesProfile(space)
        let tabs = space.pinned.tabs + space.today + (deletingProfile ? space.profile.favorites : [])
        for tab in tabs {
            extensions.didClose(tab)
            tab.discard()
        }
        closedTabs.removeAll { $0.spaceID == space.id }
        archive.removeAll { $0.spaceID == space.id }
        settings.linkRoutes.removeAll { $0.spaceID == space.id }
        if space.id == activeSpaceID {
            switchTo(spaces[index == 0 ? 1 : index - 1])
        }
        withAnimation(Motion.snap) {
            _ = spaces.remove(at: index)
        }
        if deletingProfile {
            removeWebsiteData(of: space.profile)
        }
        saveArchive()
        scheduleSave()
    }

    private func removeWebsiteData(of profile: Profile) {
        profiles.removeAll { $0 === profile }
        let id = profile.id
        Task { await history?.removeAll(profile: id) }
        forgetChoices(of: id)
        Task {
            // WebKit refuses while the store is still in use; give it a moment to let go.
            for _ in 0..<5 {
                try? await Task.sleep(for: .seconds(1))
                if (try? await WKWebsiteDataStore.remove(forIdentifier: id)) != nil { return }
            }
        }
    }
}
