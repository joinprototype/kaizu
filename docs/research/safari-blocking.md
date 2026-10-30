# How Safari/WebKit blocks ads and trackers, and what Kaizu can reuse

*Research snapshot as of 2026-10-25. Sources: WebKit `main` source and `safari-762x` release branches (checked Oct 2026), the macOS 27 SDK headers on this machine, webkit.org, and Apple docs. Claims that come only from reading source and have not been tested at runtime are tagged **(source)**. Anything not confirmed is tagged **(unverified)**. Companion doc: [webkit-browsers-extensions.md](webkit-browsers-extensions.md).*

## TL;DR
- Safari's blocking is **WebKit content rule lists**, the same public API Kaizu gets (`WKContentRuleListStore` + `WKUserContentController.addContentRuleList`). Even Safari's own "known tracker" blocking is just a rule list it installs under a `com.apple.*.TrackingResourceRequestContentBlocker` identifier (inferred from [backend](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionsBackend.cpp)).
- **ITP is already on by default in Kaizu's WKWebViews.** That includes full third-party cookie blocking. Advanced Tracking & Fingerprinting Protection, Link Tracking Protection, Private Relay for HTTPS, and Privacy Report are **Safari-only (SPI)**.
- **There is no public per-request "blocked" callback.** You count blocked requests by re-classifying them yourself (DuckDuckGo's approach) or by using a `WKWebExtension` declarativeNetRequest action count on macOS 15.4+.

## How Safari blocks

**Content blockers** ([2015 design post](https://webkit.org/blog/3476/content-blockers-first-look/), [Apple guide](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker)). Rules are declarative JSON, and the extension never sees URLs. Compiling a list works like this:
1. JSON is parsed and every `css-display-none` selector is validated. This runs **synchronously on the calling (main) thread** (`ASSERT(RunLoop::isMain())`) **(source)** ([store](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/APIContentRuleListStore.cpp)).
2. On a background queue, the URL regexes go into a combined prefix tree. That tree is split into NFAs capped at 75k nodes, then each NFA becomes a DFA and then DFA bytecode ([compiler](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionCompiler.cpp)).
3. The result is written to `ContentRuleList-<id>` in the store directory along with the original JSON source. That file is memory-mapped and shared with WebContent processes.

For each request, WebKit runs every attached list's bytecode against the ASCII-canonical URL (`data:` URLs are skipped). It then filters the matches through separate DFAs for top-URL and frame-URL conditions.

A [2020 commit](https://github.com/WebKit/WebKit/commit/d069434dea) ([bug 219626](https://bugs.webkit.org/show_bug.cgi?id=219626)) records some tuning data. Compiling 122k rules peaked at 146 MB, and the compiler is tuned for a "soft memory limit of 150MB". The rule cap went from 50k to **150k**.

**ITP** ([2017](https://webkit.org/blog/7675/intelligent-tracking-prevention/), [current policy page](https://webkit.org/tracking-prevention/)):
- **Classifier.** It is on-device and uses 3 features per registrable domain: subresource-under-N-sites, subframe-under-N-sites and unique redirects. In source it is an SVM loaded from a `corePrediction_model` resource, with a fallback rule: the vector length (hypot) above 3 means prevalent, above 30 means "very high" ([classifier](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Platform/classifier/ResourceLoadStatisticsClassifier.cpp)).
- **Protections:** blocks all third-party cookies (not just for classified domains), purges data of classified domains that lack user interaction, applies a 7-day cap on script-writable storage for sites without interaction, detects bounce tracking, caps cookies from CNAME/IP-cloaked hosts at 7 days, downgrades cross-site referrers to the origin, and caps JS cookies on pages reached via link decoration at 24h ([2020](https://webkit.org/blog/10218/full-third-party-cookie-blocking-and-more/)).

**Advanced Tracking & Fingerprinting Protection / Link Tracking Protection** ([Private Browsing 2.0](https://webkit.org/blog/15697/private-browsing-2-0/), [WWDC23 10053](https://developer.apple.com/videos/play/wwdc2023/10053/)):
- **Network blocking** comes from a rule list built from the **intersection of DuckDuckGo data and EasyPrivacy**.
- **Link Tracking Protection** strips query parameters before navigation and when a link is copied.
- **Fingerprinting protection** adds noise to canvas, WebGL and audio readback and pins screen metrics.
- **How they are switched on:** per-navigation `AdvancedPrivacyProtections` flags that Safari sets through SPI (`WKWebpagePreferences._networkConnectionIntegrityPolicy`). The parameter list comes from the private `WebPrivacy.framework` ([WebPrivacyHelpers.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Platform/cocoa/WebPrivacyHelpers.mm)) **(source)**.

## Rule format cheat sheet

**`url-filter` regex** (a JS-regex subset, ASCII only, **case-insensitive** unless `url-filter-is-case-sensitive: true`) ([URLFilterParser](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/URLFilterParser.cpp)):

| Supported | Rejected (whole list fails) |
|---|---|
| `.` `[a-z]` `[^…]` (negated classes) `\.` escapes | `\|` alternation ("Disjunctions are not supported yet") |
| `?` `*` `+` | `{n}`, `{n,m}` (unless they reduce to `?`/`*`/`+`) |
| `(…)` groups, which can be quantified | lookarounds, backreferences, `\b` |
| `^` only as the first term; `$` only as the last | `\d \w \s` and other built-in classes; non-ASCII |

**Triggers** ([parser](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionParser.cpp)). Release-branch membership below is from `git` ancestry; mapping branches to Safari versions is inferred.

| Field | Notes | Earliest WebKit |
|---|---|---|
| `url-filter` (required), `url-filter-is-case-sensitive` | | 2015 |
| `if-domain` / `unless-domain` | Matches the **top document host, exactly**. Prefix `*` to include subdomains. Values must be lowercase ASCII/punycode. Compiled internally into a top-URL regex | 2015 |
| `if-top-url` / `unless-top-url` | Regex on the full main-document URL | Safari 11 era |
| `if-frame-url` | Regex on the current frame's URL | 2021 (≤620) |
| `unless-frame-url` | | 621 (≈18.4 / macOS 15.4) |
| `load-type` `first-party`/`third-party` | Compares the resource's **registrable domain (eTLD+1) with the top document's**, not the frame's. Apple's docs still say "scheme, domain, port", which is stale | 2015 (eTLD+1 since 2021) |
| `load-context` `top-frame`/`child-frame` | | Safari 15 |
| `request-method` (single string) | | **622 (≈Safari 26)**. Older WebKit **silently ignores** it, so the rule fires for every method |

**Only one condition per rule** (`if-/unless-` domain, top-url or frame-url). Breaking this fails compilation with "A trigger cannot have more than one condition".

**`resource-type`** ([ResourceLoadInfo.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/loader/ResourceLoadInfo.cpp)):
- **Available on all supported versions:** `document`, `image`, `style-sheet`, `script` (which also covers JSON and text module loads), `font`, `media`, `svg-document`, `popup`, `ping`, `fetch` (XHR/fetch), `websocket`, `csp-report`, `other` (beacon, ping, icon, manifest, CSP reports), and `raw` (legacy: fetch + websocket + other + ping).
- **`top-document` / `child-document`:** **622+ only.** On older WebKit an unknown type **fails the whole list** ("Invalid string in the trigger flags array").
- Types reflect how the resource is *used*, not its MIME type.

**Actions:**

| Action | Effective in a plain WKWebView? |
|---|---|
| `block` | Yes. A blocked main-frame navigation fails with `WebKitErrorDomain` 104, "The URL was blocked by a content blocker" |
| `block-cookies` | Yes (strips cookies; cannot loosen ITP) |
| `css-display-none` + `selector` | Yes. Applies `display:none !important` |
| `make-https` | Yes. Only for `http`/`ws` on the default port |
| `ignore-previous-rules` | Yes. **Same list only**: it drops every earlier match in that list and that list's generic CSS sheet. It cannot override another list ([backend](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionsBackend.cpp)) |
| `notify` | Compiles, but is delivered only through SPI |
| `redirect`, `modify-headers` | **Compile, then silently do nothing.** They only apply when SPI `_activeContentRuleListActionPatterns` grants host patterns for that list. Public route: `WKWebExtension` DNR **(source)** |
| `ignore-following-rules` | **622+ only.** An unknown action type fails the list on older WebKit |

**Limits and errors:**
- **150,000 rules per list.** Several lists can be attached; I found no documented cap on the number of lists.
- An empty list is an error.
- The compile error has domain `WKErrorDomain`, code `WKErrorContentRuleListStoreCompileFailed`. The text is in **`NSHelpAnchorErrorKey`**, not `localizedDescription`: `"Rule list compilation failed: Invalid or unsupported regular expression."` **It never names the bad rule.** The detailed regex reason ("Error while parsing … : Disjunctions are not supported yet.") only goes to `dataLog` (stderr) ([WKContentRuleListStore.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKContentRuleListStore.mm), [errors](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionError.cpp)).
- Lookup can return `VersionMismatch`. Current WebKit recompiles automatically from the stored source, but code should handle both outcomes.

**Gotchas:**
- **An invalid CSS selector does not fail the list.** That single rule is **silently skipped** (behavior since the [2015 fix, bug 148446](https://bugs.webkit.org/show_bug.cgi?id=148446); [code](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionParser.cpp)). A rule whose `selector` is a hand-grouped list `"a, b, :has-text(x)"` is dropped **entirely** if any part is invalid. Validation uses quirks-mode parsing. Uppercase selectors and `:has()` were fixed in 2023.
- **Grouping is automatic now.** Rules without conditions that share an identical trigger are merged into one comma-joined selector at compile time. Rules with conditions are **never** merged, so group per-domain cosmetic rules yourself (after validating each selector).
- **Generic cosmetic rules are cheap.** Rules with `url-filter: ".*"` and no condition become one global stylesheet per list.
- **Avoid many `.*` + `if-domain` rules.** Each one becomes a separate "universal" action, and the compiler `RELEASE_ASSERT`s when there are ≥65,535 of them in a list. That would crash the compiling (app) process **(source, unverified in practice)**. Prefer domain-anchored `url-filter`s.
- **`if-domain: ["example.com"]` does not match `www.example.com`.** Use `"*example.com"`.
- **Quantifiers mid-pattern (`foo.*bar`) blow up DFA size** and can get the list rejected. Shared prefixes are cheap ([2015 post](https://webkit.org/blog/3476/content-blockers-first-look/)).
- **Features depend on the installed WebKit, not on the macOS major version.** Safari updates on older macOS carry WebKit with them **(unverified for current releases)**. To probe at runtime, compile a 1-rule list. Unknown *trigger keys* cannot be probed because they are ignored, so for those parse `Bundle(for: WKWebView.self)` `CFBundleVersion`. For example `22625.1.29…` means 625: drop the 2-digit prefix (prefix scheme inferred).

## Available to WKWebView apps?

| Feature | WKWebView on macOS 15+ | Public control |
|---|---|---|
| Content rule lists (block / css / cookies / https / ignore) | **Yes** (10.13+) | `WKContentRuleListStore`, `WKUserContentController` |
| `redirect` / `modify-headers` / `notify` | No (SPI) | Via `WKWebExtension` DNR (**15.4+**). Limits: 100 static rulesets, 50 enabled, 30k dynamic+session ([constants](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/Extensions/WebExtensionConstants.h)). Everything compiles into **one** rule list per extension, so the 150k cap applies **(source)** |
| ITP, incl. full 3P-cookie blocking | **On by default** for apps linked against the macOS 11+ SDK ([App-Bound Domains post](https://webkit.org/blog/10882/app-bound-domains/); [DefaultWebBrowserChecks.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/Shared/Cocoa/DefaultWebBrowserChecks.mm)) | No API. Adding `NSCrossWebsiteTrackingUsageDescription` to Info.plist **disables** ITP on macOS, because there is no TCC check there **(source)**. SPI: `_resourceLoadStatisticsEnabled` |
| Advanced Tracking & Fingerprinting Protection (tracker blocking, Advanced Fingerprinting Protection) | Off | SPI only. Safari 26 turns AFP on for all browsing in Safari **(secondary sources)** |
| Link Tracking Protection | Off | SPI plus the private WebPrivacy list. Do it yourself (see below) |
| Private Relay | HTTPS from WKWebView is **not** relayed. Only insecure HTTP (and possibly DNS) is ([Apple](https://developer.apple.com/support/prepare-your-network-for-icloud-private-relay/), [DTS forum](https://developer.apple.com/forums/thread/683957)) | Run your own relay with `WKWebsiteDataStore.proxyConfigurations` (14+) |
| Privacy Report | Safari UI only | SPI `_getResourceLoadStatisticsDataSummary` |
| HTTPS upgrade | Yes | `upgradeKnownHostsToHTTPS` (11.3), `preferredHTTPSNavigationPolicy` (**15.2**) |
| Global Privacy Control | — | `WKWebpagePreferences.globalPrivacyControlEnabled`, **macOS 27 only** |
| Blocked-request callback | No | SPI `_webView:contentRuleListWithIdentifier:performedAction:forURL:` (returns `_WKContentRuleListAction.blockedLoad` and related fields) |

## Counting blocked requests (no public API)
1. **DuckDuckGo pattern.** An injected script observes resource URLs through a `MutationObserver` on `src`, wrapped `fetch`/XHR/`Image.src`, and a scan on load. Native code re-classifies each URL against the **same tracker data** that generated the rules, and records it as "blocked" when blocking is enabled ([tracker-protection.js](https://github.com/duckduckgo/content-scope-scripts/blob/main/injected/src/features/tracker-protection.js), [TrackerProtectionEventMapper.swift](https://github.com/duckduckgo/apple-browsers/blob/main/SharedPackages/BrowserServicesKit/Sources/BrowserServicesKit/ContentScopeScript/TrackerProtectionEventMapper.swift)). The native matcher must copy WebKit's semantics: eTLD+1 of the *top* document, case-insensitive, resource type.
2. **WKWebExtension DNR (15.4+).** Call `setExtensionActionOptions({displayActionCountAsBadgeText:true})`. WebKit increments a per-tab count on every rule-list hit, and the host reads `WKWebExtensionAction.badgeText` via `webExtensionController(_:didUpdate:forExtensionContext:)` **(source)**.
3. **Partial signal:** blocked main-frame loads fail with code 104. Web Inspector also logs "Content blocker prevented frame displaying … from loading a resource from …" (debugging only).

## Recommendations for Kaizu's blocker
1. **Compile once and cache.** Ship JSON, not bytecode, because the on-disk format is versioned (currently v21). Use `storeWithURL:` pointing at a directory under Application Support, with identifiers like `ads-<sha256-prefix>`. At launch, call `lookUp` first and compile only on a miss, an update or `VersionMismatch`. Compiling parses on the **main thread**, so schedule it off the launch path and measure.
2. **Split lists by role**, each well under 150k rules:
   - `network-trackers`: domain rules, `load-type: third-party`
   - `network-ads`
   - `cosmetic-generic`: `.*`, no condition
   - `cosmetic-specific`: one rule per domain with a grouped, pre-validated selector list
   - `site-fixes`
3. **Allowlisting.** `ignore-previous-rules` does not cross lists, so append the per-site allowlist (`url-filter ".*"`, `if-domain ["*site"]`, `ignore-previous-rules`) to the **end of every list** and recompile when it changes. For an instant per-tab toggle, give each tab its own `WKUserContentController`, call `removeAllContentRuleLists()` and reload.
4. **Validate before WebKit does.** Run a converter-side regex linter that rejects `|`, `{}`, `\d`, `\b`, lookarounds and non-ASCII, and split alternations into separate rules. Validate selectors one by one before grouping, for example with `CSS.supports("selector(…)")` in a hidden WKWebView. Note that WebKit validates in quirks mode. Bisect when compile fails, because the error never names the rule.
5. **Target the WebKit 620 subset** (macOS 15.0) by default. Enable `unless-frame-url` from 621, and `top-document`/`child-document`/`request-method`/`ignore-following-rules` from 622 after a runtime probe. Never emit `request-method` for older WebKit.
6. **Converters to evaluate:** Brave [adblock-rust](https://github.com/brave/adblock-rust) (MPL-2.0; its `content_blocking` module emits this format), AdGuard [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) (**GPL-3.0**; its README documents per-Safari-version limits), and DDG [TrackerRadarKit](https://github.com/duckduckgo/TrackerRadarKit) (Apache-2.0). EasyList is mostly dead weight: in one study **90.16%** of its blocking rules gave no benefit (Snyder et al., below). Trim it to fit under the cap.
7. **Leave ITP on.** Don't add `NSCrossWebsiteTrackingUsageDescription`. Expect third-party cookies to be blocked, as in Safari. Use `nonPersistentDataStore()` for private windows.
8. **Build Link Tracking Protection yourself.** In `decidePolicyFor navigationAction`, cancel and reload with a cleaned URL (on macOS 27 use `WKWebpagePreferences.alternateRequest`). Also clean URLs on Copy Link. The parameter list (gclid, fbclid, msclkid…) needs curating, for example from AdGuard's URL Tracking filter **(unverified license)**.
9. **Use HTTPS APIs instead of `make-https`:** `upgradeKnownHostsToHTTPS` and `preferredHTTPSNavigationPolicy` (15.2+).
10. **Use DNR only where you need it.** Use `WKWebExtension` DNR (15.4+) only for redirect/header rules or badge counts. Keep the core blocker on plain rule lists so it works on 15.0.

## Papers worth citing
- Janc, Kotowicz, Weichselbaum, Clapis, *Information Leaks via Safari's Intelligent Tracking Prevention*, [arXiv:2001.07421](https://arxiv.org/abs/2001.07421) (2020). ITP state as a side channel.
- Snyder, Vastel, Livshits, *Who Filters the Filters*, SIGMETRICS 2020 / [arXiv:1810.09160](https://arxiv.org/abs/1810.09160). Rule bloat in EasyList, including an iOS content-blocker benchmark.
- Randall, Snyder et al., *Measuring UID Smuggling in the Wild*, IMC 2022 ([pdf](https://www.sysnet.ucsd.edu/~voelker/pubs/uid-smuggle-imc22.pdf); preprint *Trackers Bounce Back*, [arXiv:2203.10188](https://arxiv.org/abs/2203.10188)). Navigational/bounce tracking around partitioned storage, which is the rationale for link-decoration stripping.
- I found no Apple paper on the ITP classifier or on content-blocker performance. The WebKit posts and commit messages above are the primary record.
