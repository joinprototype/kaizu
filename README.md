# Kaizu

An Arc-style browser for macOS built on WebKit (the Safari engine), with a
quiet, crafted soul. Vertical tabs, pinned tabs, a command bar, and real profiles with
fully isolated website data.

**[Download for Mac](https://kaizu.joinprototype.com)**. Free, open source and early. It needs an
Apple silicon Mac on macOS 15.4 or later. Apple hasn't checked Kaizu yet, so your Mac stops it the
first time: the site has the steps. After that it updates itself.

Found a bug? Choose Help → Report a Bug in Kaizu, or write to
[help@joinprototype.com](mailto:help@joinprototype.com). Made by
[Prototype](https://joinprototype.com) in Santa Monica.

## What's in it

- **Sidebar**: spaces (two-finger swipe), favorites, pinned tabs and folders, Today tabs that archive themselves, peek on hover when hidden
- **Command bar** (⌘T): addresses with inline completion, open tabs, history, archived tabs, commands by name (every menu item too), `20+20`, `10 km to mi`, `100 usd to eur`, `yt lofi`; optionally from any app with a shortcut (Settings → General), like Spotlight; pinned tabs and favorites show up in the system Spotlight too
- **Windows**: little windows for links from other apps, private windows, split view (up to 4; drag a tab onto the page), link peek, ⌃Tab recent-tab switcher
- **Privacy, built in**: ads and trackers blocked (EasyList/EasyPrivacy, updated daily), YouTube ads, cookie pop-ups rejected automatically, tracking parameters stripped, HTTPS first, Global Privacy Control; per-site pause
- **Light on the Mac**: idle tabs hibernate (and on memory pressure) and wake where you left them
- **Extensions**: "Add to Kaizu" on Chrome Web Store and Firefox Add-ons pages, or from a folder, a `.zip` or a Safari extension app
- **Capture** (⇧⌘2): drag over part of the page to copy it as an image
- **Hide Distracting Items**: click away banners and clutter; the site remembers
- **Reading**: Reader (⇧⌘R), picture in picture when you leave a playing video, per-tab mute
- **Remembers per site**: camera, microphone and location answers, zoom; all of it (plus blocking and clearing the site's data) in a popover from the address pill's lock

## Run

Requires macOS 15.4+ and Xcode 16.3+ (Swift 6).

```sh
make run                  # build debug, bundle build/Kaizu.app, launch
make app CONFIG=release   # release bundle
make icon                 # regenerate Resources/AppIcon.icns from scripts/make-icon.swift
```

You can also `open Package.swift` in Xcode and hit Run. The Info.plist is
embedded into the binary, so WebKit gets a bundle identifier either way.

Debug builds accept `KAIZU_DEBUG=commandbar|location|space|settings|history|private|peek|switcher|extension|nosidebar|reader|pin|split|splitdrop|capture|quickbar|open` to
boot straight into a UI state (handy for screenshots), and
`KAIZU_SUPPORT=/some/folder` to keep that launch's session and history out
of your real ones. Settings and website data follow the bundle id: for a
copy that can't touch your real browser at all, give its Info.plist another
`CFBundleIdentifier` and re-sign it.

## Release

```sh
scripts/release.sh 0.1.3      # bump the version, write the DMG, signed zip and version.json into site/
cd site && npx wrangler deploy
```

Run one release at a time, and it needs the update signing key. Kaizu reads `version.json` 10
seconds after launch and every 6 hours. A newer build downloads quietly and goes in on restart or
quit, once its Ed25519 signature, bundle id, build number and code signature all check out. If
anything fails, or Kaizu can't replace itself, people get a notice with the download link instead.
It uses Apple frameworks only.

## Docs

- [Roadmap](docs/ROADMAP.md): what's missing vs Arc, phases, motion spec
- [Architecture](docs/ARCHITECTURE.md): module layout, state model, rules
- [Research](docs/research/): market and Arc analysis

## Data

- App state: `~/Library/Application Support/Kaizu/`
- WebKit profile data: `~/Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore/<profile-uuid>/`

Don't change the bundle ID: WebKit keys profile data (logins) by it.

## License

Kaizu's own code is under the [Mozilla Public License 2.0](LICENSE.md), which
grants no rights to the Kaizu name or logo.

Bundled third-party files keep their own licenses:

- EasyList, EasyPrivacy and the EasyList Cookie List: see [Resources/Filters](Resources/Filters/README.md)
- autoconsent (MPL-2.0) and Readability (Apache-2.0): see [Resources/Scripts](Resources/Scripts/README.md)
- Site fonts (SIL OFL 1.1): see [site/fonts/OFL.txt](site/fonts/OFL.txt)
