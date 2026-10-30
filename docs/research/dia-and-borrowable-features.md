# Dia, ⌘D, command bar and delight: what Kaizu can borrow

*Snapshot 2026-10-25. Sources linked inline. **(unverified)** = not confirmed from a primary source; **(memory)** = from general product knowledge, not re-checked today. Context in [arc-and-market.md](arc-and-market.md) is not repeated.*

## TL;DR

- Dia is a Chromium, AI-first browser. Its free tier has no AI; chat, skills and integrations cost $10-20/mo or $100/mo. It kept Arc's sidebar, pins and favorites, and has been re-adding Arc features all year. It dropped Spaces, the Arc command bar and Boosts.
- Worth borrowing without being AI-first: `@`-scoped context ideas, skills as saved prompts, "Ask on page", Dia's shortcut and pin polish (return a pin to its base URL, copy as Markdown link).
- Best AI path for Kaizu: **no model of our own.** A side panel hosting the user's own claude.ai / chatgpt.com / gemini session, plus an opt-in "send this page" button. Firefox ships this already.
- ⌘D: Arc pins or unpins the tab (it has no bookmarks). Dia's behaviour is not documented; Chrome-style bookmark is likely. Official visuals are not described anywhere I could find. Exact descriptions below, with confidence marked.
- Command bar: calculator, unit and time-zone conversion, quicklinks and commands are cheap local wins. Avoid remote suggestions by default.

## 1. Dia today

**Features.** Sidebar with an AI chat pane, tabs, pinned tabs and Tab Groups ([SupaSidebar review](https://supasidebar.com/blog/dia-browser-mac-review-2026)). Chat is scoped by `@`-mentions to a tab, a Tab Group, history or the whole profile; `@Gmail`, `@Google Calendar`, `@Tabs` and others exist ([changelog](https://www.diabrowser.com/changelog)). **Skills** are named, reusable prompts. A natural-language skill builder shipped Oct 2025 and skills reached Windows on Oct 15, 2026 (changelog). "Ask on Page" answers about the current page. Free tier also has profiles, split view, PiP, a built-in ad/tracker blocker and sync ([plans](https://www.diabrowser.com/plans)).

**How the AI works.** Page and tab text is sent to hosted models; the plans page says it uses "models that won't store your data". Context is explicit: you `@`-mention what the model may read. Memory surfaces earlier chats and tabs (SupaSidebar; reviewers say it can slow 8 GB Macs, **unverified**). Integrations (Slack, Gmail, Notion, Outlook, GitHub, Calendar, Figma) are the paid hook.

**Pricing.** Free "Better Browser" (no AI); "Better Answers" at $10 on the card but $20 in the FAQ; "Better Days" at $100 with 6x usage, Morning Brief, decks and meeting prep; 14-day trial of the top tier ([plans](https://www.diabrowser.com/plans)). Older sources describe a free tier plus $20 "Pro" ([Wikipedia](https://en.wikipedia.org/wiki/Dia_(web_browser))); pricing has changed, so check before quoting.

**Arc features kept or added back** (changelog): pinned tabs outside Favorites (Mac 1.52, Oct 8, 2026), Arc-style recent-tabs switcher (1.51), tab search includes pins, ⌘-Return returns a pin to its base URL (1.4), ⌥-click splits, ⌥⇧⌘C copies a Markdown link, custom pin names carried from Arc import, new tabs at top (1.21), auto-PiP for Meet ([TechCrunch](https://techcrunch.com/2025/11/03/dias-ai-browser-starts-adding-arcs-greatest-hits-to-its-feature-set/)). **Dropped:** Spaces (profiles instead), Boosts, Easels, Little Arc, and the ⌘T fuzzy command bar, replaced by an AI chat box that Arc users say breaks muscle memory (SupaSidebar). Apple-silicon Mac only; Windows since late 2026.

**Reception.** Praised as fast and stable; complaints are tab management for ex-Arc users, the paywall, Atlassian ownership and breadth of data collection (SupaSidebar; [vantaige](https://vantaige.io/ai-tool/dia), vendor-ish). Reddit/HN threads were not retrievable today, so community sentiment is **unverified** beyond the HN summary already in arc-and-market.md.

**Worth borrowing without being AI-first**
1. Return-to-base-URL on pinned tabs (⌘-Return). Cheap, loved by Arc users.
2. Copy page URL as Markdown link (⌥⇧⌘C).
3. Pins appearing in tab search.
4. Skills as the idea of *saved prompts* (see below), not agents.
5. Bookmark button that only appears on address-pill hover ([Dia design post](https://browsercompany.substack.com/p/the-strategy-behind-dias-design)).

### AI without our own model

Pattern: host the provider's real web app and let the user's login do the billing.

- **Firefox** (v135+) has a sidebar with ChatGPT, Claude, Gemini, Copilot, Le Chat; works with free or paid accounts and can send selected text or page context ([coverage](https://getcoai.com/news/firefox-just-made-your-favorite-ai-chatbots-available-in-its-browser-sidebar); Mozilla's own support page failed to load, so details are secondary).
- **Chrome extensions** such as "AI Sidebar" load the real chatgpt.com / claude.ai in a panel ([listing](https://chromewebstore.google.com/detail/bfabadmipmkngbdagbjkpjflihlclckc), marketing claims). Sider/Monica/Merlin are *not* this: they bill their own backends ([comparison](https://nexasphere.io/blog/the-best-chrome-extensions-for-running-chatgpt-and-claude-side-by)).
- **Edge Copilot Mode** (side pane, reads open tabs, opt-in history; [YourStory](https://yourstory.com/ai-story/microsoft-edge-copilot-mode-ai-browser)) and **Opera Aria** ([TechCrunch](https://techcrunch.com/2023/05/24/opera-launches-new-integrated-ai-sidebar-powered-by-openais-chatgpt)) use the vendor's own model, not your subscription. Vivaldi and Orion keep AI out. Safari 27 adds on-device-style tab grouping and page monitoring ("Notify Me") but I found no page-chat feature ([9to5Mac](https://9to5mac.com/2026/06/09/heres-everything-new-coming-to-safari-on-macos-27-golden-gate/)) **(unverified)**. Arc's "Ask on Page" was Arc Max, now retired with Arc.

**Kaizu design.** A second `WKWebView` in a right panel (reuse the split-view machinery), persistent per-profile data store so login sticks. "Send page": user presses a button; we inject page title, URL and `innerText` (or selection) into the provider's input box and optionally submit, or copy to clipboard as fallback. Risks: provider DOM changes break injection (keep a clipboard fallback), some sites block embedding via `X-Frame-Options` (irrelevant for a top-level WKWebView), Google login in WKWebView can fail (see roadmap login notes), and ToS for automating the chat UI is grey **(unverified)**. Never send a page without a user gesture; show what will be sent. This fits "no account, no AI paywall".

## 2. ⌘D

**Arc (official).** ⌘D = "Pin/Unpin current tab"; pressing again unpins; Arc has no bookmarks; pinned tabs sit in the top half of the sidebar above the line and never auto-archive ([shortcuts](https://resources.arc.net/hc/en-us/articles/20595231349911-Keyboard-Shortcuts), [help](https://resources.arc.net/hc/en-us/articles/19231060187159), the latter 403'd for me, taken from search snippets).
*Visual, from memory, **unverified** (no source describes it):* the tab row animates up from the Today list across the divider into the Pinned section of the current Space, its title keeps its place and the row gains the pinned style (favicon-forward, no close button until hover). No toast, no dialog, no sound. Feedback is purely the row moving. Unpin: the row drops back below the line to the top of Today.

**Dia.** Official docs do not describe ⌘D. A third-party shortcut list says ⌘D = "Bookmark this page" ([pie-menu](https://www.pie-menu.com/shortcuts/dia)) **(unverified)**. Dia's bookmark control appears only when hovering the URL ([design post](https://browsercompany.substack.com/p/the-strategy-behind-dias-design)). ⌘⇧D pins to Favorites (changelog, Mac 1.54, Oct 22, 2026), while a Raycast listing says ⌘⇧D opens the bookmark manager, which conflicts. *Visual: not found. Best inference, **unverified**:* Chrome-style small bubble anchored under the bookmark icon at the right of the address pill. I could not confirm a HUD or icon; test in the app before copying.

**Chrome (memory).** ⌘D: star in the omnibox fills and a bubble anchors under it: title "Bookmark added", Name field, Folder dropdown, "Done" and "Remove"; click away dismisses. **Safari (memory).** ⌘D: a small sheet drops from the toolbar: "Add this page to: [Favorites v]", editable name and description, Cancel and Add. Both are blocking-ish popovers; Arc's is a silent move.

**Suggestion for Kaizu.** Do Arc's behaviour (it matches the pinned-first model) but add what Arc lacked: a 1.5 s non-modal pill toast at the bottom of the sidebar, "Pinned to Work · Undo (⌘Z)", with a short spring of the row into the pin area and a soft haptic. Reduce Motion: cross-fade.

## 3. Command bar / launcher

What others do (mostly **memory**; verified items linked):

| Feature | Who | Presentation |
|---|---|---|
| Inline calculator | Chrome omnibox (answers as you type, [source](https://blog.logrocket.com/what-to-look-out-for-when-working-with-chrome/)), Spotlight, Raycast, Alfred | Top row `= 40`; Enter copies result |
| Unit / currency / time zone | Spotlight (units, currency), Raycast (all three, live rates), Chrome via Google answers | Result row with both values; "Copy" action |
| Quicklinks / search shortcuts | Chrome "site search" (`@yt`, `yt<Tab>`), Safari ("Quick Website Search"), Raycast quicklinks | Tab-to-search chip in the field: `YouTube v cats` |
| Commands / actions | Arc ("Pin tab", "Archive"), Raycast, Chrome `chrome://` entries, Dia ("new jira") | Verb rows with shortcut hints |
| Clipboard history, emoji | Raycast, Alfred | Out of scope for a browser |
| Inline answers | Google Suggest, Safari Suggestions | Remote; see privacy |

**Privacy.** Chrome sends every keystroke to Google Suggest (default search provider) unless turned off; Safari sends queries to Apple (Safari Suggestions) and the search engine, with Apple masking IP **(memory; Apple's support page did not state it)**. Currency rates need a network fetch: cache daily from a public source, never per keystroke. Kaizu rule: everything above runs locally; search suggestions off by default and clearly labelled as "sends what you type to <engine>".

## 4. Small touches worth stealing

- **Undo toast** after destructive or moving actions (Things, Linear, iOS). Close tab, archive, unpin: "Undo" for 5 s.
- **Reopen closed tab with state** (scroll, back list) via `interactionState`.
- **Springy "snap" to drop targets** while dragging tabs into pins (Arc, Things).
- **Status in one glyph** (Linear): tab dot for audio, loading, downloading, blocked trackers count.
- **Raycast-style hint bar** at the bottom of the command bar: `↩ Open  ⌘↩ New tab  ⌥↩ Split`, changing with selection.
- **Confetti-free empty states** with a line of personality (Things "All done").
- **Number the first nine tabs** with ⌘1-9 hint when ⌘ is held (iOS shortcut sheet, Arc).
- **Haptics** on trackpad for pin, snap, split divider detent.
- **Copy feedback**: the pill flashes "Link copied" in place of the URL for 1 s (Craft, Notion).
- **Quick-capture**: select text, ⌥⌘S saves a clip with URL into a space note (Craft, Notion Web Clipper). L effort; skip for now.
- **Dark/accent follows Space** (already Arc, already ours).
- **Page-aware empty new tab**: recents plus pinned grid; no feed.

## Recommendations for Kaizu (ranked)

1. **Command bar inline answers: calculator, units, time zone (local only)**: S. Highest delight for lowest cost; matches Raycast/Chrome; no network.
2. **⌘D = pin/unpin with undo pill + row animation**: S. Arc muscle memory for refugees; the toast fixes Arc's silent move.
3. **Quicklinks / site-search shortcuts (`yt cats`, Tab to search chip), user-editable in Settings**: S-M. Also unlocks `@`-style prefixes later.
4. **Hint bar with ⌘↩ / ⌥↩ actions in the command bar**: S. Teaches power features without a tutorial (fits the novelty-tax principle).
5. **Pin polish from Dia: ⌘-Return back to base URL, Copy as Markdown link, pins in tab search**: S. Verified Dia wins, and ex-Arc users expect them.
6. **Undo toasts for close/archive/unpin**: S-M. Safety principle ("never lose user data").
7. **Currency conversion with daily-cached rates**: M. Needs a rates source and cache; show "rates from <date>".
8. **Bring-your-own AI side panel (host claude.ai / chatgpt.com, "Send page" button, no model, no account)**: M. Neutral on the "no AI headline" principle: opt-in, user-billed. Prototype with split-view code; test Google login first.
9. **Saved prompts ("Skills lite") for that panel**: M. Only after 8.
10. **Remote search suggestions (opt-in)**: S technically, with a privacy label; default off.
11. **Clip / quick-capture**: L. Defer.

## Not verified / next checks

- Dia ⌘D behaviour and visuals: test in the app (Dia is free).
- Arc ⌘D animation: screen-record in Arc before Dec 22, while it still runs.
- Safari 27 page-AI features, Firefox sidebar page-context details (Mozilla page failed to load), Reddit/HN sentiment on Dia.
