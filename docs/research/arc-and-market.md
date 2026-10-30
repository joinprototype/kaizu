# Arc, its fallout, and the market for a WebKit Arc-style browser

*Research snapshot as of 2026-10-24, written for Kaizu. Claims are linked inline. Anything not confirmed from a primary or credible source is marked **(unverified)**.*

## TL;DR

1. **Arc is shutting down, and the deadline is about 8 weeks away.** On Oct 22, 2026 The Browser Company (TBC) said Arc for macOS and Windows **stops working Dec 22, 2026**. New accounts are already disabled, and account data is deleted within 30 days ([arc.net](https://arc.net/)). Right now a large group of people are deciding which browser to move to.
2. **Arc's own post-mortem calls its problem a "novelty tax".** Only 5.52% of DAUs used more than one Space, 4.17% used Live Folders, and 0.4% used Calendar Preview ([2025 letter](https://browsercompany.substack.com/p/letter-to-arc-members-2025)). The part of Arc people loved was small: the sidebar, pinned vs. auto-archiving tabs, the command bar, and a few power features.
3. **Departing Arc users name the same features they will miss:** the sidebar, auto-clearing tabs, Spaces, split view, **Air Traffic Control**, Peek, **Little Arc** and Boosts ([HN](https://news.ycombinator.com/item?id=50197601)). Dia, the official successor, has **no Little Arc** ([PiunikaWeb](https://piunikaweb.com/2026/10/13/arc-might-soon-be-abandoned-as-atlassian-pushes-users-towards-dia/)).
4. **Dia is pushing Arc users away.** It is Chromium-based, owned by Atlassian, and charges for AI: $10–20/mo and $100/mo, with no AI on the free tier ([plans](https://www.diabrowser.com/plans)). Arc users are scattering to Zen, Orion, Helium, Crest, or back to Chrome.
5. **Vertical tabs alone no longer set a browser apart.** Firefox (Mar 2025) and Chrome (Apr 2026) ship them natively ([Mozilla](https://www.mozilla.org/firefox/136.0/releasenotes), [TechCrunch](https://techcrunch.com/2026/04/07/chrome-is-finally-getting-vertical-tabs/)). Safari 27 still lacks them. Kaizu must win on the *Arc feel*, not on the tab layout.
6. **The AI-browser hype has cooled.** OpenAI shut down ChatGPT Atlas on Aug 9, 2026 ([TechCrunch](https://techcrunch.com/2026/07/09/openai-is-shutting-down-atlas-but-its-ai-browser-ambitions-are-still-growing/)). Dia put its AI behind a paywall, and Vivaldi markets "keep browsing human". A browser with no AI, no account and no subscription is now a selling point.
7. **Few browsers are built on WebKit, and they only target Apple platforms.** Orion hit 1.0 in Nov 2025, and Kagi **dropped Linux/Windows on Oct 2, 2026** ([Kagi](https://blog.kagi.com/update-orion-linux-windows)). SigmaOS has pivoted to AI, and Nook and Ora are early open-source clones. The closest threat is **Crest** (Chromium plus WebKit per site), which already imports Arc data and has a Little Arc equivalent ([crestbrowser.com](https://crestbrowser.com/)).
8. **WebKit's tradeoffs are real on both sides.** On the plus side, Apple claims up to 5 more hours of streaming than Chrome (its own test), and engine security fixes ship with the OS. That matters because TBC gave **security cost** as the reason for killing Arc. On the minus side: extensions have gaps, passkeys need a restricted entitlement, Google checks the user agent, and some web apps are tuned only for Chromium.
9. **Arc grew through craft, scarcity and identity, not features.** It was invite-only until July 2023, and its "unboxing" onboarding gave early "little wins" and ended with a membership card. Opera GX (~33M MAU) shows that a browser sold on aesthetic identity can reach scale.
10. **Ranked opportunities for Kaizu:** (1) an Arc importer plus a core that faithfully matches Arc, shipped before Dec 22; (2) trust: local-first, no kill switch, no AI paywall; (3) delight and identity, which the kawaii brand provides; (4) battery life and native feel.

---

## 1. Why Arc succeeded

**Product decisions**
- **The sidebar works like a file system.** Unpinned tabs **auto-archive after 12 hours**, and pinned tabs persist ([Input, 2022](https://www.inverse.com/input/design/the-browser-company-arc-design-interview)). HN commenters still single out this "browser that cleans itself" ([HN](https://news.ycombinator.com/item?id=50197601)).
- **The command bar** (⌘T) is a Spotlight-style overlay that searches tabs, history, settings and the web.
- **Signature features:** **Spaces** (each with its own theme and profile), **Air Traffic Control** (routes external links to a Space), **Little Arc** (a floating mini window for links from other apps), split view with up to 4 panes, **Peek**, **Boosts** (CSS/JS site restyling) and **Easels** ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))).
- **It ran on Chromium with full Chrome-extension support,** so switching from Chrome cost almost nothing.

**Design, brand and craft**
- TBC presented the browser as "a room, not a window", with a launch color burst and a softly lit frame inspired by Robert Irwin. It borrowed from film and game design ([Input](https://www.inverse.com/input/design/the-browser-company-arc-design-interview)).
- **Onboarding as "unboxing":** a game-like tutorial with early "little wins" (picking a gradient) that ended in a **personalized membership card**. TBC onboarded its first users manually over calls before building this flow ([Input](https://www.inverse.com/input/design/the-browser-company-arc-design-interview)).
- **The community was treated as "members"** and addressed candidly in public letters ([2025 letter](https://browsercompany.substack.com/p/letter-to-arc-members-2025)). Specifics of Arc's sound and animation design are **(unverified)**.

**Distribution and positioning**
- **Invite-only scarcity** from 2022 until Mac 1.0 in July 2023 ([9to5Mac](https://9to5mac.com/2023/07/25/arc-browser-no-waitlist/)). The Windows beta opened with **500k+ on the waitlist** ([TechCrunch](https://techcrunch.com/2023/12/11/arc-browser-launches-its-windows-client-in-beta/)). Invite codes and screenshots spread on social media.
- **Positioning as "the Chrome replacement"** for power users, backed by $128M in funding ($550M valuation in Mar 2024, per [TechCrunch](https://techcrunch.com/2024/03/21/the-browser-company-raises-50-million-at-550-million-valuation)). User counts were never published; outside estimates run from the mid-hundreds-of-thousands to about 1M **(unverified)** ([TidBITS](https://tidbits.com/?p=70764)).

## 2. What went wrong

- **The learning curve, or "novelty tax".** Most users never adopted the signature features. Retention looked like "a specialized professional tool". A former Apple executive's advice was to build a "piano, not a saxophone" ([letter](https://browsercompany.substack.com/p/letter-to-arc-members-2025)).
- **Performance.** Users reported RAM and battery drain, especially with many Spaces or media-heavy sites ([r/ArcBrowser](https://www.reddit.com/r/ArcBrowser/comments/17al028/why_i_left_arc/)). TBC later said performance and security belong "in the foundation" ([letter](https://browsercompany.substack.com/p/letter-to-arc-members-2025)).
- **Security.** In Sep 2024 a misconfigured Firebase backend allowed **remote code execution via Boosts** (CVE-2024-45489). It was fixed in a day; TBC then hired a security engineer and started a bug bounty ([NVD](https://nvd.nist.gov/vuln/detail/CVE-2024-45489), [Techzine](https://www.techzine.eu/news/applications/124668/leak-in-arc-browser-fixed-after-one-day)). In 2026, TBC gave security cost as the reason for the shutdown ([arc.net](https://arc.net/)).
- **A mandatory account and pushy onboarding** drew criticism ([Deceptive Patterns](https://deceptive.design/articles/arc-browsers-pushy-account-requirements)). It now reads as a **remote kill switch** ([HN](https://news.ycombinator.com/item?id=50197601)).
- **Windows** shipped Apr 30, 2024 (Windows 11 only, written in Swift) without Little Arc ([AlternativeTo](https://alternativeto.net/news/2024/5/the-browser-company-finally-launches-the-windows-version-of-the-arc-web-browser/)). It split a small team, and "Arc 2.0" was shelved in Oct 2024 ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))).
- **AI features.** Arc Max (Oct 2023) got mixed reviews ([TechCrunch](https://techcrunch.com/2023/10/03/arc-browsers-new-ai-powered-features-combine-openai-and-anthropics-models), [TidBITS](https://tidbits.com/?p=64292)). Arc Search's "Browse for Me" caused TBC's first backlash, over pages that keep traffic away from publishers ([Engadget](https://www.engadget.com/who-makes-money-when-ai-reads-the-internet-for-us-200246690.html)).
- **The pivot (May 2025).** TBC stopped developing Arc's core, admitted it was "too cautious on AI", and declined to open-source Arc because its internal framework (ADK) also powers Dia ([letter](https://browsercompany.substack.com/p/letter-to-arc-members-2025)).
- **The Atlassian acquisition** was announced Sep 4, 2025 as **$610M all-cash** ([TidBITS](https://tidbits.com/2025/09/04/atlassian-acquires-the-browser-company-for-610-million/)) and **closed Oct 21, 2025** ([Business Wire](https://www.businesswire.com/news/home/20251021473486/en/Atlassian-Completes-Acquisition-of-The-Browser-Company-of-New-York)), with the goal of "an AI browser for knowledge work".
- **The sunset (Oct 22, 2026).** Arc Search loses its AI on Nov 23, and desktop Arc dies on Dec 22. The Dia migration maps Spaces to Profiles and Folders to Tab Groups, and carries pins and favorites across ([arc.net](https://arc.net/)).

**What Arc users say now** ([HN](https://news.ycombinator.com/item?id=50197601), [PiunikaWeb](https://piunikaweb.com/2026/09/23/the-best-life-after-arc-browser-not-ready-replace-arc/)):
- **What they miss:** the auto-hiding sidebar, pins and auto-clearing tabs, ATC, Little Arc, Peek, split view, Boosts.
- **What they dislike:** the kill switch, "AI garbage", Atlassian, and Dia's paywall. A required Atlassian account for Dia is claimed on HN **(unverified)**.
- **What they want:** Arc open-sourced (about 10 HN comments), or simply something that keeps working.

## 3. Competitive landscape (macOS, late 2026)

| Browser | Engine | Notes |
|---|---|---|
| **Dia** (TBC/Atlassian) | Chromium | Official successor with an Arc importer. AI costs $10–20 or $100/mo; the free tier has no AI ([plans](https://www.diabrowser.com/plans)). No Little Arc. Sentiment toward it is poor. |
| **Zen** | Gecko (Firefox 158) | The most-recommended Arc clone, with workspaces, split view and sync ([warp2search](https://www.warp2search.net/story/zen-browser-1233b-ships-with-firefox-158-security-fixes/)). No native Arc import ([GitHub](https://github.com/zen-browser/desktop/discussions/8967)). Users report bugs. |
| **Crest** | Chromium, with WebKit per site | Open source (MPL-2.0) and in early access, without a security audit. Imports Arc Spaces, folders and passwords, and has Quick Window (its Little Arc), Peek and Chrome extensions ([site](https://crestbrowser.com/)). **The most direct threat.** |
| **Orion** (Kagi) | WebKit | 1.0 on Nov 25, 2025 ([AlternativeTo](https://alternativeto.net/news/2025/11/orion-1-0-launches-for-macos-with-privacy-first-design-and-webkit-engine)). No telemetry, no AI, and profiles act as separate apps. Supports many Chrome and Firefox extensions but not all (about 70% of the API claimed, **unverified**; 1Password issues reported, per [SupaSidebar](https://supasidebar.com/blog/orion-browser-mac-review-2026)). Linux and Windows dropped ([Kagi](https://blog.kagi.com/update-orion-linux-windows)). |
| **SigmaOS** | WebKit | Mac-only, now selling an AI assistant on $20–30/mo plans ([EveryDev](https://www.everydev.ai/tools/sigmaos)). |
| **Nook / Ora** | WebKit | Open source (GPL-3.0), about 2k GitHub stars each. Ora is "not ready for daily use" ([Ora](https://github.com/the-ora/browser), [Nook](https://github.com/nook-browser/Nook)). Kaizu's closest technical peers. |
| **Safari 27** | WebKit | Has profiles but no vertical tabs. Adds AI auto tab groups and AI-built extensions ([9to5Mac](https://9to5mac.com/2026/06/09/heres-everything-new-coming-to-safari-on-macos-27-golden-gate/)). |
| **Chrome / Firefox / Edge / Brave** | Chromium / Gecko | All have native vertical tabs now. Some Arc users are going back to Chrome. |
| **Vivaldi / Helium** | Chromium | Vivaldi: anti-AI and highly customizable ([PCWorld](https://www.pcworld.com/article/2892582/vivaldi-rejects-ai-browsing-humans-over-hype.html)). Helium: ungoogled, uBO built in, in beta ([Techlore](https://techlore.tech/helium-browser-review-a-truly-minimal-privacy-focused-chromium-browser/)). |
| **Opera Air / GX** | Chromium | Air is a "mindfulness" browser ([Opera](https://press.opera.com/2025/02/04/opera-air-browser/)). GX has ~33M MAU ([Opera Q3'25](https://www.barchart.com/story/news/35756004/opera-reports-third-quarter-2025-results-ahead-of-expectations-raises-full-year-guidance-ranges-for-both-revenue-and-adjusted-ebitda)). Both prove browsers can be sold on mood and identity. |
| **Comet / Atlas** | Chromium | Comet is an agentic browser, free since Oct 2025 **(secondary sources)**. Atlas **shut down Aug 9, 2026** ([9to5Mac](https://9to5mac.com/2026/07/09/openai-is-discontinuing-chatgpt-atlas-its-standalone-desktop-browser/)). |

## 4. WebKit in 2026: advantages and disadvantages

**Advantages**
- **Efficiency.** Apple claims up to **5 more hours** of streaming than Chrome (its own Aug 2026 test on an M5 Air, [apple.com](https://www.apple.com/safari/)). Independent data is thin and mixed ([Birchtree](https://birchtree.me/blog/everyone-says-chrome-devastates-mac-battery-life-but-does-it-i-tested-for-36-hours-to-find-out/)). Treat battery life as an edge to measure, not something to promise.
- **Security comes from Apple.** WebKit fixes ship with macOS and Safari updates, so a solo developer never maintains a Chromium fork, which is exactly the upkeep TBC cited when it killed Arc. Kagi found running WebKit *off* Apple platforms too costly, so staying macOS-only fits the engine.
- **Native APIs keep improving.** Safari 27-era WKWebView adds `willSubmitForm` (useful for password capture), cookie lookup per URL, and more ([WebKit blog](https://webkit.org/blog/17967/news-from-wwdc26-webkit-in-safari-27-beta/)).

**Disadvantages**
- **Extensions.** `WKWebExtension` (macOS 15.4+) loads MV2/MV3 extensions from a folder or ZIP ([Apple docs](https://developer.apple.com/documentation/webkit/wkwebextension)). There is no store, so installing, updating and filling in APIs that exist only in Chrome is the developer's job. Even Orion still has gaps.
- **Passkeys** need the `com.apple.developer.web-browser.public-key-credential` entitlement. The Account Holder requests it through a dedicated form, and developers report slow or unclear approvals ([Apple forums](https://developer.apple.com/forums/thread/829169)).
- **Google sign-in.** Google blocks OAuth in "embedded webviews" ([Google](https://developers.googleblog.com/2021/06/upcoming-security-changes-to-googles-oauth-2.0-authorization-endpoint.html)). Kaizu's Safari user-agent suffix works for now but could break if Google changes how it detects browsers.
- **Compatibility.** Web apps tuned for Chromium sometimes misbehave, and power users keep Chrome as a fallback. Content blocking is declarative (`WKContentRuleList`), which is weaker than uBO.
- Whether third-party WKWebView browsers get the same Web Push, Apple Pay and ITP behavior as Safari is **(unverified)**.

## 5. Opportunities and risks

**Opportunities, ranked**
1. **An importer for departing Arc users, plus a core that faithfully matches Arc.** Timing makes this the top bet. Arc's sidebar lives in one local file, `~/Library/Application Support/Arc/StorableSidebar.json`, which open-source tools already parse ([arc-export](https://github.com/ivnvxd/arc-export)). Dia and Crest have importers; Zen, Orion and Safari don't. Pair it with what Dia lacks: **Little Arc** and **ATC**.
2. **Trust as the product: "it can't be switched off".** No account, no telemetry, no AI paywall, local data, and possibly open source. This answers the kill-switch anger directly, and it is a promise an indie project can keep where a company owned by Atlassian or OpenAI cannot.
3. **Delight and identity.** Every competitor is dark, minimal or "AI". A glossy, candy-colored browser with a mascot stands out in screenshots, which is how Arc spread. Likely audiences: students, creatives, people who share desk setups, and fans of cute aesthetics.
4. **Battery life and native feel.** A real difference from Arc, Dia and Zen, but a secondary message because Orion and Safari make the same claim.
5. **Privacy through per-profile isolation plus blocking.** Necessary, but not differentiating.

**Risks**
1. **The window for Arc users closes fast, and the market is crowded.** Dia offers the official path, Crest has an importer, and Zen has the community. Most migrations will happen by Dec 22.
2. **One broken site loses a power user.** A failing password manager, Google login, passkey or Chromium-only web app is enough.
3. **Apple and Google control key pieces.** The passkey entitlement, Google's webview policy and user-agent detection can each break core flows.
4. **Sustainability for a solo developer.** Users just burned by a kill switch will distrust a one-person project, and there is no clear revenue model.
5. **Brand and novelty tax.** "Kawaii" may read as a toy to professionals, and too much novelty is what killed Arc's adoption.

---

## What this means for Kaizu

**P0: ship before Dec 22, 2026**
1. **Arc importer as the headline feature.** Parse `StorableSidebar.json` and map Spaces to profiles, pinned tabs and folders to pinned items, and favorites to the pinned grid. Keep each Space's colors and icons, and show a preview with a one-click import. Build the landing page around it: "Arc closes Dec 22. Bring your sidebar home." The local file should outlive Arc's servers, which would keep the importer useful after shutdown **(unverified)**.
2. **Close the gaps Arc users name.** Add auto-archive for unpinned tabs (12h default), **Little Arc** (links from other apps open in a mini window that can be promoted to a tab), **ATC** (rules that route links to a profile), Peek, and split view. Little Arc and ATC are the cheapest strong differentiators against Dia.
3. **Unblock logins.** Apply for the passkey entitlement now, since the queue is slow. Add password autofill and test Google sign-in in every profile. A failed login is how WebKit browsers lose users.

**P1: build trust and delight**
4. **Publish a public promise:** no account, no telemetry, no AI paywall, and Kaizu keeps working if development stops. Consider open-sourcing the code, or committing to do so if the project ends.
5. **Built-in content blocking** via `WKContentRuleList`, on by default.
6. **Onboarding with "little wins".** Let users pick a candy color for a profile, have the mascot react, and finish with a cute member card. Keep the default behavior close to a normal browser and reveal power features gradually, to avoid the novelty tax.
7. **Measure and publish battery life** against Arc, Dia, Chrome and Zen on the same machine. Only publish numbers you reproduced yourself.

**P2: later**
8. **Extensions through `WKWebExtension`:** start with a curated set (a password manager, a blocker, Dark Reader), not a claim of Chrome Web Store parity.
9. **Growth:** an optional invite list, shareable themes, and a "letters to members" tone. Target students, creatives and fans of cute aesthetics first.

**Avoid:** Windows/Linux (Kagi's lesson), AI as the headline, the long tail of Arc features (Easels, the Boosts editor, Live Folders) before the core is solid, and a mandatory account.

---

### Could not verify
- Arc's real user counts, and the "12% weekly growth" quote attributed to a Lenny's Podcast appearance.
- Specifics of Arc's sound and animation design.
- Whether Dia requires an Atlassian account.
- Orion's "~70% WebExtensions API" figure.
- Whether `StorableSidebar.json` stays usable after Dec 22.
- WKWebView parity with Safari on Web Push, Apple Pay and ITP.
- Whether individual developer accounts can get the passkey entitlement.
- Comet's pricing and status.
- Dia's exact Answers price: the plans page lists both $10 and $20.
