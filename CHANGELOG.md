# Kaizu changelog

## Unreleased

Kaizu can fill logins from Apple’s Passwords app. Click into a login field and press the key at its right end, or choose **Edit → Fill from Passwords…** (⌥⌘\\). In the picker, choose **Passwords…**, unlock with Touch ID and pick a login: Kaizu fills it into the page and forgets it. Kaizu never reads your saved passwords; macOS hands over only the login you pick. A login goes only to the site it was picked on. On sign-ins that ask for the username first, the password waits up to two minutes for that site’s password page. The key appears on fields in the page itself, not in embedded frames, where the menu command works instead.

In the command bar, ⌘↩ opens the chosen page in a background tab and ⌥↩ opens it beside the current page in a split. The hints at the bottom of the bar show them while a page is selected.

On a Force Touch trackpad, Kaizu taps lightly when a drag lands somewhere: a tab reaching a gap in the sidebar or a new place in a split, and a split divider reaching the point where its two panes are the same size, where it now also holds for a moment.

Hold ⌘ for a moment and the sidebar shows which tab each of ⌘1–9 goes to: the first eight visible tabs, from Favorites down, and ⌘9 for the last. The numbers go away when you let go, press a key or click.

VoiceOver can use the sidebar. Tabs, folders, favorites and New Tab read as buttons by name, say which one is selected, and open with VoiceOver's press; a tab's Close and Mute, which only show on hover, are in VoiceOver's actions (VO-⌘-Space), and folders say whether they're expanded. Icon buttons (Back, Reload, Copy Link, the shield, the space switcher, Remove in Settings, Show in Finder) are read by name instead of by icon, without their keyboard shortcut.

Kaizu can watch part of a page for you, such as a price, a stock label or a score. Choose **View → Watch Part of Page…** (or "Watch" in the command bar, or from the site menu in the address bar) and click the part. About once an hour while Kaizu is running, it opens the page out of sight with that profile's sign-ins and the usual blocking, and tells you when the part's text changes: in a macOS notification where macOS allows it, otherwise with a message in the window, a bounce and a count on the Dock icon. Opening the page clears the count. **Settings → Watching** lists what's watched, what each part said before and when it changed, and parts Kaizu can no longer find. Only secure (https) pages in regular windows can be watched, up to 50 parts.

Back and Forward now work between web pages and extension pages, such as an extension's settings. Each side needs its own kind of page view, so going from one to the other used to start the tab's history over. Kaizu now keeps the last 10 page views a tab left this way and steps into them when Back or Forward reaches the end. They're kept until you quit. The trackpad swipe still stops at the crossing.

YouTube videos opened from a link outside YouTube, such as in Messages or Slack, now start in about the time a click inside YouTube takes. When YouTube had booked an ad for the page, Kaizu used to strip it but still had to wait out a black player for the ad’s length (5–15 s). Kaizu now has YouTube’s player load the same video again, asking for it without an ad, and keeps the link’s start time.

Kaizu can play soft paper sounds: turn on **Settings → General → Play soft sounds**. They’re off by default. Opening the command bar unfolds a sheet, opening and closing tabs lays down and draws away a card, pinning presses the paper, switching spaces turns a page and splitting folds a crease. They play only for your own actions while Kaizu is in front, follow the macOS “Play user interface sound effects” setting and alert volume, and a held key or a quick run plays once.

Cookie pop-up rejection now runs out of the page's reach. Kaizu loads DuckDuckGo's autoconsent library in a separate script world that pages can't see or change. Each frame receives only the rules that apply to its address, instead of the full 600 KB script and rule set. Across ten busy news and shopping sites, the pages used about 30% less CPU while loading. Memory use stayed about the same. Rejection worked as before on Cookiebot, CookieYes, Didomi, OneTrust, Sourcepoint and Usercentrics sites. The old in-page script is no longer bundled, so the app is about 600 KB smaller.

Quitting Kaizu now writes every profile's cookies to disk before the app exits, and an update waits for WebKit to finish saving site data before it reopens Kaizu. Previously WebKit could still be saving after Kaizu exited, so a quick relaunch after an update could lose a recent login or draft.

Clear Today keeps the remaining pinned panes on screen. Undo restores the earlier split when you’ve kept its layout. Older workspaces reopen with cleared panes removed from their saved splits.

Undoing a browsing history import keeps visits you made afterward, including pages you cleared and revisited.

In **File → Import Browsing Data…**, a Safari ZIP containing multiple history or bookmark files now lets you choose the files to import. The destination shows both the space and its profile, so you can bring Work and Personal across separately.

Repeating an Arc sidebar import respects Today tabs you already imported and then navigated, moved within the same profile, or auto-archived. This uses the original tab ID saved by new JSON imports. Older imports still match open pages by address.

Reopening a recently auto-archived tab restores its Back and Forward history, including after restarting Kaizu. The 32 newest archive entries can each keep up to 1 MiB of navigation state. Other entries reopen at their saved address.

Reopen Closed Tab (⇧⌘T) restores Back and Forward history for the 32 most recently closed Today tabs when each snapshot fits in 1 MiB. Older tabs and larger pages reopen at their saved address. After Clear Today, Undo skips tabs you already reopened.

The Arc import preview shows each destination’s profile and sidebar position so you can distinguish spaces with the same name before importing. When both profiles have identical pins in a space, re-import also checks the other space names in the same Arc profile.

Pressing ⌘O in a little window moves the live page into its opening space, even after you switch windows. If that space was deleted, the page can move to another space in the same profile. Deleting the profile closes its little windows.

In **Settings → Privacy → Import Rule List…**, add a WebKit content-blocker JSON file. You can turn individual lists off or remove them. Imported rules follow the shield’s per-site pause setting.

Undoing a bookmark import keeps a single copy of each pre-existing tab and removes imported tabs that moved to Today or Favorites.

Opening a workspace saved by an older build repairs duplicate Today rows left by bookmark Undo. If you edited the copies separately, Kaizu keeps both. When two copies point to different pages, each reopens its own URL and Kaizu backs up the shared navigation history.

Undoing an Arc import preserves tabs and folders you added afterward, including changes made in another window. A newly imported profile also survives Undo once you have used its website data.

**File → Import from Arc…** now accepts a saved sidebar JSON or the Markdown file from Arc’s Export Data command. Markdown links become pinned tabs inside the exported spaces and folders. The sidebar JSON also preserves profile groups, Favorites and Today tabs.

Pausing or resuming blocking in a private window now affects only that window. Regular windows keep their saved site preferences.

Pasting an address such as `example.com?view=weekly` or `example.com#notes` now opens the page directly. The address bar also recognizes bracketed IPv6 addresses with ports.

Split with Recent Tab keeps a full four-pane layout on screen. From a standalone tab, it can start a new split with a previously used pane.

Closing the focused pane or undoing an import that supplied it keeps the remaining split panes on screen.

Auto-archive keeps background tabs that are using the camera or microphone, including while capture is muted.

When a site requests the camera and microphone together, Kaizu asks only about devices that still need an answer. Declining the microphone preserves an existing camera permission.

An extension that activates a background tab now selects it in that tab’s own window. The focused window keeps its current space and page. Switching spaces also tells extensions which tab became active.

Settings → Extensions now shows the errors WebKit reports for each installed extension. Extension pages opened with this build keep their address and local storage across restarts. Reopen any extension settings tabs saved by an older build from the extension's toolbar menu.

Arc imports preserve custom tab names and keep independent Arc profiles separate when existing Kaizu spaces share a profile.

Kaizu can recover a damaged session from its last successfully opened copy and keeps the damaged file for inspection.

Quitting now finishes earlier tab-history saves before writing the final Back and Forward history for open tabs. Open web pages also get time to save their last draft edit when you quit or restart for an update.

If two update checks overlap, quitting Kaizu installs the newest build it has verified. Once an update is ready, Kaizu removes its downloaded ZIP and any older verified build from the update cache.

Choose **History → Recently Archived Tabs** to browse by day, search by page or space name, and restore a tab to its original space.

Press ⌘T and type a title or part of an address to find open tabs across spaces in your current profile. Each match names its space. Selecting it takes you back to the existing tab, including tabs in collapsed folders. Archived tab suggestions are now scoped to the current profile too.

Ad and cookie-banner blocking now covers 155 more hiding filters from EasyList and the Cookie List, the ones that target class names with brackets or colons such as `.h-[90px]`. A tracker block marked `$important` now stays blocked even when another filter allows it.

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
