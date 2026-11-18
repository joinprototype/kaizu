<p align="center">
  <img src="site/apple-touch-icon.png" width="84" height="84" alt="">
</p>

<h1 align="center">Kaizu</h1>

<p align="center">An Arc-style browser for Mac. Bring your sidebar, keep work and personal logins separate, and browse with WebKit.</p>

<p align="center">
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fkaizu.joinprototype.com%2Fversion.json&amp;query=%24.version&amp;label=release&amp;color=35466e" alt="Current Kaizu release"></a>
  <img src="https://img.shields.io/badge/macOS-15.4%2B-555555" alt="macOS 15.4 and later">
  <img src="https://img.shields.io/badge/Mac-Apple%20silicon-555555" alt="Apple silicon">
</p>

<p align="center">
  <strong><a href="https://kaizu.joinprototype.com/download">Download for Mac</a></strong> ·
  <a href="https://kaizu.joinprototype.com/#open">First launch</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="docs/ROADMAP.md">Roadmap</a>
</p>

<p align="center">
  <img src="site/img/commandbar.jpg" width="800" alt="Kaizu’s sidebar beside a Wikipedia page, with the command bar converting 10 km to 6.21 miles.">
</p>

## What you can do in v0.2.5

- **Bring your Arc setup.** On the Mac where you use Arc, choose **File → Import from Arc…** to preview your spaces, pinned folders, favorites and tabs. Use **File → Import Browsing Data…** for bookmarks and history from a Chromium browser or a Safari export.
- **Give each project a space.** Pin the pages you keep coming back to and let Today tabs archive themselves. Use separate profiles when you want separate logins and cookies.
- **Stay on the keyboard.** Press ⌘T to jump to an open tab, find an archived page, run a menu command or convert a measurement. Press ⌘/ to see the shortcuts.
- **Keep your place.** Peek at a link, open it beside the page you’re reading, or split a window into up to four panes. Idle tabs can go to sleep and wake when you return.
- **Control what loads.** Kaizu blocks ads and trackers, rejects supported cookie prompts and strips tracking parameters. Open the site settings in the address bar to pause blocking for one site.

On the development branch, **Import from Arc…** also opens a saved sidebar JSON or Markdown export from another Mac. You can browse recently archived tabs in History and import a WebKit content-blocker rule list in Settings. [Unreleased changes](CHANGELOG.md#unreleased)

## Install

Download the disk image, open it and drag Kaizu into Applications. The current build is ad-hoc signed and macOS asks for approval on first launch. Once installed, Kaizu checks for signed updates automatically. [First-launch instructions](https://kaizu.joinprototype.com/#open) · [GitHub releases and downloads](https://github.com/joinprototype/kaizu/releases/latest)

Found a bug? Choose **Help → Report a Bug** in Kaizu, or open a [GitHub issue](https://github.com/joinprototype/kaizu/issues). You can also reach the team at [help@joinprototype.com](mailto:help@joinprototype.com).

## Build and test

Use Xcode with the macOS 27 SDK and Swift 6. The app runs on Apple silicon with macOS 15.4 or later.

```sh
swift test                # run the BrowserCore and app test suites
make run                  # build debug, bundle build/Kaizu.app, launch
make app CONFIG=release   # release bundle
make icon                 # regenerate Resources/AppIcon.icns from scripts/make-icon.swift
```

You can also `open Package.swift` in Xcode and hit Run. The Info.plist is
embedded into the binary, so WebKit gets a bundle identifier either way.

Debug builds accept `KAIZU_DEBUG=commandbar|location|space|settings|history|private|peek|switcher|extension|nosidebar|reader|pin|split|splitdrop|capture|quickbar|open|arcimport` to
boot straight into a UI state (handy for screenshots), and
`KAIZU_SUPPORT=/some/folder` to keep that launch's session and history out
of your real ones. Settings and website data follow the bundle id: for a
copy that can't touch your real browser at all, give its Info.plist another
`CFBundleIdentifier` and re-sign it.

## Release

In GitHub Actions, open **Mac build and tests**, choose **Run workflow**, and select the candidate branch or tag. The rehearsal builds one runtime package and checks migration from v0.2.5 and installation of the signed update on both hosted macOS 15 and macOS 27. Each upgrade checks the restored login, draft, tab, space and profile. The job logs report the exact macOS version. [Run the Mac checks](https://github.com/joinprototype/kaizu/actions/workflows/mac.yml)

For a notarized Mac release, set `KAIZU_DEVELOPER_ID` to the **Developer ID Application** signing identity and `KAIZU_NOTARY_PROFILE` to a Keychain profile created with `xcrun notarytool store-credentials`. Set `version` to the release number.

```sh
scripts/release.sh --notarize "$version"
cd site && npx wrangler deploy
```

Before building, the script checks that the selected Ed25519 update signing key matches the public key trusted by Kaizu. It signs the app with Hardened Runtime, waits for Apple to accept it, and staples the ticket. It then signs the update ZIP and signs, notarizes, and staples the DMG. The browser’s updater verifies the finished ZIP before the script replaces the site files. Local packaging and CI use `scripts/release.sh "$version"` with an ad-hoc app signature. [Apple’s notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

Add a dated entry to [CHANGELOG.md](CHANGELOG.md) and commit the release metadata. After deploying the site, create a GitHub release tagged `v<version>` at that release commit. Attach the same DMG and update ZIP that went to the site and copy the changelog entry into the release notes.

Build one release at a time with the update signing key. Kaizu reads `version.json` 10
seconds after launch and every 6 hours. A newer build downloads quietly and goes in on restart or
quit, once its Ed25519 signature, bundle id, build number and code signature all check out. If
anything fails, or Kaizu can't replace itself, people get a notice with the download link instead.
It uses Apple frameworks only.

## Docs

- The [roadmap](docs/ROADMAP.md#path-to-10-on-mac) tracks Arc parity, switching workflows and the checks still open for 1.0.
- [Extension compatibility](docs/ROADMAP.md#extension-compatibility) lists the tested builds of Bitwarden, uBlock Origin Lite, Dark Reader and TabCloser, plus options for 1Password.
- The [architecture guide](docs/ARCHITECTURE.md) covers the module layout and state model.
- The [research notes](docs/research/) cover Arc and other browsers.

## Data

Kaizu keeps spaces, tabs and browsing history on your Mac. Submitted searches go to your chosen engine. Suggestions while typing are off by default. [Privacy details in the repository](site/privacy/index.html)

- App state: `~/Library/Application Support/Kaizu/`
- WebKit profile data: `~/Library/WebKit/com.joinprototype.kaizu/WebsiteDataStore/<profile-uuid>/`

Don't change the bundle ID: WebKit keys profile data (logins) by it.

## License

Kaizu's own code is under the [Mozilla Public License 2.0](LICENSE.md), which
grants no rights to the Kaizu name or logo.

Bundled third-party files keep their own licenses:

- EasyList, EasyPrivacy and the EasyList Cookie List: see [Resources/Filters](Resources/Filters/README.md)
- autoconsent (MPL-2.0) and Readability (Apache-2.0): see [Resources/Scripts](Resources/Scripts/README.md)
- IM Fell, the type on Kaizu's headings (SIL Open Font License): [Resources/Fonts](Resources/Fonts/OFL.txt)
- Site fonts (SIL OFL 1.1): see [site/fonts/OFL.txt](site/fonts/OFL.txt)
