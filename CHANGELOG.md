# Kaizu changelog

## Unreleased

In **Settings → Privacy → Import Rule List…**, add a WebKit content-blocker JSON file. You can turn individual lists off or remove them. Imported rules follow the shield’s per-site pause setting.

Undoing a bookmark import keeps a single copy of each pre-existing tab and removes imported tabs that moved to Today or Favorites.

Undoing an Arc import preserves tabs and folders you added afterward, including changes made in another window. A newly imported profile also survives Undo once you have used its website data.

**File → Import from Arc…** now accepts a saved sidebar JSON or the Markdown file from Arc’s Export Data command. Markdown links become pinned tabs inside the exported spaces and folders. The sidebar JSON also preserves profile groups, Favorites and Today tabs.

When a site requests the camera and microphone together, Kaizu asks only about devices that still need an answer. Declining the microphone preserves an existing camera permission.

An extension that activates a background tab now selects it in that tab’s own window. The focused window keeps its current space and page. Switching spaces also tells extensions which tab became active.

Settings → Extensions now shows the errors WebKit reports for each installed extension. Extension pages opened with this build keep their address and local storage across restarts. Reopen any extension settings tabs saved by an older build from the extension's toolbar menu.

Arc imports preserve custom tab names and keep independent Arc profiles separate when existing Kaizu spaces share a profile.

Kaizu can recover a damaged session from its last successfully opened copy and keeps the damaged file for inspection.

Choose **History → Recently Archived Tabs** to browse by day, search by page or space name, and restore a tab to its original space.

Press ⌘T and type a title or part of an address to find open tabs across spaces in your current profile. Each match names its space. Selecting it takes you back to the existing tab, including tabs in collapsed folders. Archived tab suggestions are now scoped to the current profile too.

## 0.2.5 · November 2, 2026 · Build 10

Kaizu now refreshes its ad and tracker lists daily even if you leave the browser open. After an offline check it retries within an hour. New pages use the updated rules, and open pages pick them up when you reload.

## 0.2.4 · November 2, 2026

Kaizu now compiles blocking lists in a short-lived helper process, so the Mac can reclaim that memory as soon as compilation finishes.

## 0.2.3 · November 2, 2026

Silent autoplay videos no longer keep idle tabs awake. They also no longer trigger the sidebar speaker or automatic picture-in-picture.

## 0.2.2 · November 2, 2026

Right-click a link to open it in a split, a tab or another window. Middle-click opens a background tab. Spell checking is on by default and can be adjusted in the Edit menu.

## 0.2.1 · November 1, 2026

Fixed notification delivery across profiles, unread counts in visible split panes and session restoration when a saved split layout is malformed.

## 0.2.0 · November 1, 2026

Split a window into rows and columns in the same layout. Drag a tab to the outer edge to give a page the full width or height of the split.
