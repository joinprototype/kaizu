import AppKit
import SwiftUI

/// Arc's Peek: links from favorites and pinned tabs to other sites open in a
/// preview card over the page, so the pinned app stays where it was.
extension BrowserStore {
    /// Whether `tab` should peek external links instead of navigating away.
    func peeksLinks(from tab: BrowserTab) -> Bool {
        tab !== peek && (tab.profile.favorites.contains(tab) || spaces.contains { $0.pinned.tabs.contains(tab) })
    }

    func peek(_ url: URL, from opener: BrowserTab) {
        // A link while the last peek grows into a tab waits for it.
        guard !isPeekExpanding else { return }
        peek?.discard()
        let tab = BrowserTab(profile: opener.profile, app: app, url: url)
        withAnimation(Motion.pop) {
            peek = tab
        }
        tab.activate()
    }

    func closePeek() {
        guard let tab = peek, !isPeekExpanding else { return }
        // Torn down once the card has gone, so it doesn't fade out blank.
        withAnimation(Motion.snap, completionCriteria: .removed) {
            peek = nil
        } completion: {
            tab.discard()
        }
        focusWebView()
    }

    /// Keeps the peeked page as a real tab (no reload): the card grows to
    /// fill the page, then the tab takes its place, already there.
    func expandPeek() {
        guard let tab = peek, !isPeekExpanding else { return }
        withAnimation(Motion.glide) {
            isPeekExpanding = true
        } completion: { [self] in
            // Decided now, not when it started: the space may have changed
            // (or gone) while the card grew. A space with the page's profile.
            guard peek === tab, let space = space(on: tab.profile) else {
                isPeekExpanding = false
                return
            }
            if space !== activeSpace {
                switchTo(space)
            }
            withAnimation(Motion.pop) {
                space.today.insert(tab, at: 0)
            }
            extensions.didOpen(tab)
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                peek = nil
                isPeekExpanding = false
                select(tab, in: space)
            }
            scheduleSave()
        }
    }

    /// Esc closes a capture, item hiding, peek or Reader even while the page
    /// has keyboard focus; Enter finishes a capture.
    func installEscapeMonitor() {
        addEventMonitor(matching: .keyDown) { store, event in
            // Not while the command bar or a sheet wants the key.
            guard store.commandBar == nil, store.window?.attachedSheet == nil else { return event }
            let isEscape = event.keyCode == 53
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            // A capture only on the page in front, and Return in a text field stays the field's.
            if let capture = store.capture, capture == store.selectedTab?.id, isEscape || isReturn,
               !(store.window?.firstResponder is NSTextView) {
                isEscape ? store.cancelCapture() : store.finishCapture()
            } else if isEscape, store.hidingItemsTabID != nil {
                store.endHidingItems()
            } else if isEscape, store.peek != nil {
                store.closePeek()
            } else if isEscape, store.reader != nil {
                store.closeReader()
            } else {
                return event
            }
            return nil
        }
    }
}
