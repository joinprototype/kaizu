# Extensions, ad blocking and password managers in WebKit browsers

*Research snapshot as of 2026-10-24, written for Kaizu. Claims are linked inline. Anything not confirmed from a primary source or from code is marked **(unverified)**.*

## TL;DR

- **Safari Web Extensions can be reused. Safari content blockers and Safari App Extensions cannot.** Orion (since v130, Dec 2024), Nook (since Feb 2026) and one hobby browser load the web half of a Safari Web Extension straight from the `.appex` inside the app in `/Applications`. None of them can reach the extension's native companion code.
- **Content blockers are locked to Safari by a private entitlement.** macOS defines the `com.apple.Safari.content-blocker` extension point so that only a process holding `com.apple.private.extension-host.safari-content-blocker` can host it, and Safari holds it. I found no third-party browser that loads them, and Orion's and Crest's docs explicitly rule them out.
- **The WebKit browsers that are winning on extensions use WebKit's `WKWebExtension` (or Orion's own engine), plus Chrome-style native messaging, plus a built-in `WKContentRuleList` blocker.** Crest gave up and moved extensions to Chromium.

## Comparison

| Browser | Extension runtime | Chrome / Firefox ext. | Safari Web Ext. | Safari content blockers / App Ext. | Ad blocking | Passwords / passkeys |
|---|---|---|---|---|---|---|
| **Orion** (Kagi, closed) | Own WebExtensions implementation on WebKit, written before `WKWebExtension`; about 70% API coverage by Kagi's own count | Yes, CWS and AMO | **Yes** since 130: pick the `.app` via Install from Disk | No ("only Safari Web Extensions") | Built-in ABP→WebKit converter. EasyList and EasyPrivacy on by default, plus custom lists and a YouTube script. Scriptlets "Planned" | Built-in Keychain manager. 1Password and Bitwarden run as extensions. **Passkey entitlement since Dec 2024** |
| **DuckDuckGo** (Apache-2.0) | `WKWebExtension` framework. Ships embedded extensions, while third-party ones are behind an internal flag | CWS downloader, 1Password, Bitwarden and iCloud Passwords. All **internal-only** | No | No | Tracker Radar → `WKContentRuleList`. YouTube ad blocking ships as a bundled MV3 extension (internal-only) | Built-in vault and native Bitwarden-app integration. **Holds passkey entitlement** (Jul 2024) |
| **SigmaOS** (closed) | Proprietary; it calls itself the "first WebKit browser to support Chrome extensions" | Curated plus CWS | No evidence | No evidence | Built-in. Lists **(unverified)** | Apple Keychain plus password-manager extensions. Passkeys **(unverified)** |
| **Crest** (MPL-2.0) | 0.7+: extensions only on its **Chromium** engine. Up to 0.6: WebKit with its own compatibility layer | CWS on Chromium pages only | **No** (explicit) | **No** (explicit) | Bundled "Balanced" `WKContentRuleList`, on WebKit pages only | Crest Passwords in Keychain. **Holds passkey entitlement** |
| **Nook** (GPL-3.0) | `WKWebExtension`, macOS 15.5+ | CWS, Edge and AMO | **Yes**: scans `/Applications` and copies the resources | No | adblock-rust → `WKContentRuleList`, plus cosmetic filters and uBO scriptlets | No built-in manager; relies on extensions. No passkey entitlement |
| **Ora** (GPL-3.0) | None on `main`. `WKWebExtension` PR is open | No | No | No | AdGuard lists via SafariConverterLib, with no scriptlets | Built-in "Ora Passwords". **Holds passkey entitlement** |

## Per-browser notes

**Orion.** Kagi ported "hundreds of WebExtension APIs… never meant to work with WebKit", and says about 70% are supported ([help](https://help.kagi.com/orion/browser-extensions/macos-extensions.html)). The Orion 130 notes (Dec 10, 2024) say: "Install Safari web extensions directly in Orion (Extensions → Install from Disk; only Safari Web Extensions are currently supported)", shipped with passkeys for macOS 14+ ([release notes](https://orionbrowser.com/updates/orion-release-notes.html)). Before that, users loaded `…/PlugIns/X.appex/Contents/Resources/manifest.json` by hand ([forum #93](https://orionfeedback.org/d/93-safari-extension-support)). Testers found that the 1Password Safari extension "installs and loads fine… but then it can't connect to the desktop 1password app". StopTheMadness, an App Extension with no manifest, does not work. Kagi said "We got the passkeys entitlement from Apple" on Dec 4, 2024 ([forum #3025](https://orionfeedback.org/d/3025-support-passkeys)). The ad blocker compiles ABP-style lists into WebKit rules ([help](https://help.kagi.com/orion/features/custom-blocklists.html)). 1Password works through the Chrome extension once the user adds Orion as a trusted browser.

**DuckDuckGo.** The open-source monorepo has a full `WKWebExtension` stack in [`SharedPackages/WebExtensions`](https://github.com/duckduckgo/apple-browsers/tree/main/SharedPackages/WebExtensions). It includes a Chrome Web Store downloader, scriptlet signing, and bundled Dark Reader, autoconsent and `content-blocker-extension-apple.zip`, an MV3 extension with DNR rules for YouTube and uBO scriptlets. In [`FeatureFlag.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/FeatureFlag.swift), `webExtensions` is enabled, but `webExtensionNativeMessaging`, `webExtensionBitwarden`, `webExtensionOnePassword`, `webExtensionICloudPasswords` and `adBlockingExtension` are `.internalOnly`. [`NativeMessagingHostManifest.swift`](https://github.com/duckduckgo/apple-browsers/blob/main/macOS/DuckDuckGo/WebExtensions/NativeMessaging/NativeMessagingHostManifest.swift) reads the `NativeMessagingHosts` folders of Chrome, Edge, Brave and Vivaldi, including `/Library/Google/Chrome/…/com.apple.passwordmanager.json` for iCloud Passwords. There is no Safari-extension code. Bitwarden integration talks to the Bitwarden desktop app and has been built in since 2022 ([Bitwarden](https://bitwarden.com/help/duckduckgo-macos-browser-integration/)).

**SigmaOS.** Its docs say you can install from the Chrome Web Store, and that passwords live in Apple Keychain ([docs](https://docs.sigmaos.com/common-questions)). It would not explain how it runs Chrome extensions, calling the method proprietary ([Fast Company](https://www.fastcompany.com/90669133/radical-browser-tabs-sigmaos)). 1Password staff called it unsupported and untested.

**Crest.** Earlier versions ran extensions in WebKit "with their own compatibility layer" ([guide](https://crestbrowser.com/guides/extension-compatibility/)). Commits from Aug 2026 under `CrestMac/Infrastructure/WebKit/Extensions` point to a WebKit extension-controller stack. In 0.7, Crest moved extensions to ungoogled-chromium. Its docs state: "Firefox add-ons, Safari Web Extensions, Safari content blockers, and Safari App Extensions are not supported". Password-manager extensions "depend on that app trusting Crest's signature". [`Crest.entitlements`](https://github.com/pauljoda/Crest/blob/main/CrestMac/Configuration/Crest.entitlements) includes `web-browser.public-key-credential`.

**Nook** ([repo](https://github.com/nook-browser/Nook)):
- **Safari discovery.** [`ExtensionManager+Installation.swift`](https://github.com/nook-browser/Nook/blob/develop/Nook/Managers/ExtensionManager/ExtensionManager%2BInstallation.swift) has `discoverSafariExtensions()`. It enumerates `/Applications` and `~/Applications`, picks out each `.appex` whose `NSExtensionPointIdentifier == com.apple.Safari.web-extension` and which has `Contents/Resources/manifest.json`, then copies the resources into its own store. This landed in Feb 2026.
- **Messaging.** [`CLAUDE.md`](https://github.com/nook-browser/Nook/blob/develop/Nook/Managers/ExtensionManager/CLAUDE.md) documents interception of Safari-only native-message commands (`copyToClipboard`, `showPopover`, `sleep`). It also documents an in-process stand-in for Bitwarden's appex biometric unlock, Chrome-style stdio native messaging, and an `externally_connectable` bridge. The bridge exists because pages call Safari extension IDs that do not match `WKWebExtension` IDs.
- **Blocking.** [`NookBlocker`](https://github.com/nook-browser/Nook/tree/develop/Packages/NookBlocker) bundles EasyList, EasyPrivacy, uBO filters and uBO scriptlets. It switched from AdGuard's GPL converter to Brave's MPL [adblock-rust](https://github.com/nook-browser/Nook/blob/develop/Nook/ThirdParty/AdblockRustFFI/README.md).
- **Entitlements.** `Nook.entitlements` has no passkey entitlement and no sandbox.

**Ora** ([repo](https://github.com/the-ora/browser)):
- **Blocking.** [`FilterListCatalogService.swift`](https://github.com/the-ora/browser/blob/main/ora/Features/Privacy/Services/FilterListCatalogService.swift) lists the AdGuard Base, Mobile Ads, Tracking, URL Tracking and Annoyances filters. [`ContentBlockerCompileService.swift`](https://github.com/the-ora/browser/blob/main/ora/Features/Privacy/Services/ContentBlockerCompileService.swift) runs `ContentBlockerConverter().convertArray(…, advancedBlocking: false)`.
- **Passwords.** [`PasswordManagerProviderRegistry.swift`](https://github.com/the-ora/browser/blob/main/ora/Features/Passwords/Services/PasswordManagerProviderRegistry.swift) has 1Password and Bitwarden commented out as "reserved".
- **Extensions.** `WKWebExtension(resourceBaseURL:)` lives only in [PR #137](https://github.com/the-ora/browser/pull/137), open since Oct 2025.
- **Entitlements.** `ora.entitlements` holds the passkey entitlement and is sandboxed.

**Others.**
- [LeonardoLarranaga/Browser](https://github.com/LeonardoLarranaga/Browser/blob/main/Browser/SafariExtensions/SafariExtensions.swift) (experimental, Sep 2026) has the user pick a `.app` through a security-scoped bookmark. It filters `Contents/PlugIns/*.appex` by `com.apple.Safari.web-extension` and calls `WKWebExtension(appExtensionBundle:)` directly. It has no native-messaging handler.
- Refrax is dual-engine. Firn and nuance-dev/Web bundle EasyList with no extension support.

## Has anyone used Safari-installed extensions?

**Safari Web Extensions: YES, partially.** Orion, Nook and LeonardoLarranaga/Browser all do it the same way. They read the extension's JS, HTML and CSS and `manifest.json` from the `.appex` resources of the app the user installed from the App Store, then run them in their own WebExtension runtime. No entitlement, private API or re-download is involved. `WKWebExtension(appExtensionBundle:)` only reads bundle resources ([WebKit source](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebExtension.mm)).

Three things do **not** carry over:
- **Native messaging to the companion app's `SafariWebExtensionHandler`.** 1Password for Safari loads but cannot reach 1Password.
- **Safari's per-extension state:** enabled state, permissions, storage and sync.
- **Safari's extension IDs.**

**Safari content blockers: NO.** Nobody has done it, and it is blocked by design. On this Mac, `/System/Library/ExtensionKit/ExtensionPoints/com.apple.Safari.content-blocker.appexpt` declares `NSExtensionHostEntitlement = com.apple.private.extension-host.safari-content-blocker` and `EXRequiredEntitlements = com.apple.private.can-load-any-content-blocker`. `codesign -d --entitlements - /Applications/Safari.app` shows Safari holds both. Third parties cannot be granted `com.apple.private.*` entitlements, which is exactly why `NSExtension` lookups return nil for us.

Apple's public answer since 2015 has been to compile your own rules. WebKit bug [148632](https://bugs.webkit.org/show_bug.cgi?id=148632), "Please allow WKWebView to use Content Blocking extensions", was closed as a duplicate of "Expose public APIs for content filters", the request that became `WKContentRuleList`. An Orion user confirms that "Wipr doesn't work outside of Safari" ([forum](https://orionfeedback.org/d/11879-requesting-more-powerful-inbuilt-adblocking-functionality-equivalent-to-ublock-origin-or-adguard-safari)). The local `AdGuard for Safari.app` contains six content-blocker appexes plus one `com.apple.Safari.extension` popup and **no** web extension, so nothing in it is loadable.

**Safari App Extensions: NO.** `com.apple.Safari.extension.appexpt` requires `com.apple.private.extension-host.safari-extension`. Kagi called them "closed source proprietary format", and later status reports confirm they still do not work. The web-extension point itself requires `com.apple.private.can-load-any-content-blocker` to host the native handler. That is the root reason native messaging to Safari companions is impossible.

## Recommendations for Kaizu

1. **Drop Safari content-blocker reuse.** Do not ask for Full Disk Access to scrape AdGuard's group container. It is hostile to privacy, fragile, and AdGuard's lists are public anyway.
2. **Ship a built-in blocker on `WKContentRuleList`.**
   - **Lists:** EasyList, EasyPrivacy, AdGuard Base/Tracking and uBO filters.
   - **Converter:** pick by license. Brave's adblock-rust is MPL-2.0 (Nook). AdGuard's SafariConverterLib is GPL-3.0 (Ora).
   - **YouTube:** add cosmetic and scriptlet injection, or copy DDG's pattern of a bundled MV3 extension (DNR plus scriptlets) loaded through `WKWebExtension`.
3. **Host extensions with `WKWebExtension`** (macOS 15.4+; Nook targets 15.5 for reliable content scripts).
   - **Install sources:** CWS CRX and AMO.
   - **IDs:** derive Chrome IDs from the manifest `key`.
   - **Native messaging:** implement Chrome-style stdio native messaging over the Chrome, Brave and Edge `NativeMessagingHosts` manifests (DDG, Nook). This is what unlocks 1Password (the user clicks "Add Browser"; Kaizu must be Developer ID signed — [1Password](https://support.1password.com/additional-browsers/)), Bitwarden and possibly iCloud Passwords.
4. **Add an "Import from Safari" for web extensions only.**
   - **How:** scan for `com.apple.Safari.web-extension` appexes that contain `manifest.json`, then load them with `WKWebExtension(appExtensionBundle:)`, keeping a bookmark to the app so App Store updates flow through.
   - **What to tell users:** "companion-app features may not work".
   - **When to prefer the Chrome build:** if the extension is also on CWS, offer that build, because native messaging works there.
   - **Shims:** add per-extension shims (clipboard, `showPopover`) the way Nook does.
5. **Apply now for `com.apple.developer.web-browser.public-key-credential`.** DDG, Orion, Crest and Ora all have it. Orion only got it in Dec 2024, about 2 years after users first asked for passkeys.
6. **Set expectations.** Publish a verified-extension list covering uBO Lite, 1Password, Bitwarden and Dark Reader. Crest's retreat to Chromium and DDG's internal-only gating show how large the compatibility gaps are.

## Unverified

- Whether Orion runs a custom WebKit build or uses private APIs on system WebKit.
- How Orion's "Use Orion's Keychain" toggle reads Safari passwords.
- Whether Orion adopted SafariConverterLib (feature request #8026 is tagged "Done").
- SigmaOS's extension mechanism, its filter lists, its passkey entitlement, and whether it is still maintained.
- DDG third-party extensions: internal-only in code, but they could be enabled remotely.
- Whether Apple's iCloud Passwords helper accepts browsers other than Chrome, Edge and similar.
- Whether Nook's Bitwarden biometric stand-in passes Keychain ACLs.
- Whether uBO Lite's Safari build runs under `WKWebExtension`.
- Whether a sandboxed app can enumerate `/Applications/*/Contents/PlugIns` without the user selecting the app.
- That Crest's pre-0.7 stack was `WKWebExtension`-based (inferred from paths and commit messages).
