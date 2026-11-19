# Brave adblock-rust's content-blocking converter vs ours

Roadmap item: Sprint, Privacy pack, "evaluate Brave's adblock-rust converter vs ours (coverage, scriptlets)". Measured on Nov 18, 2026.

## TL;DR

- **Keep our converter.** On the four bundled lists, Brave's converter produces fewer rules, but several of its conversions are wrong in ways that block or hide the wrong things. We found six, each reproduced below.
- **Nothing Brave's converter handles that ours skips is worth porting.** The one gap with real volume was CSS-escaped selectors (160 lines), and ours was the one that refused them. Brave's converter converts them; we now do too.
- Brave iOS doesn't use the converter's cosmetic half. brave-core calls it with `RuleTypes::NetworkOnly` and does hiding, procedural filters and scriptlets in page scripts from the engine. That engine, not the converter, is the part worth evaluating if Kaizu ever wants scriptlets.
- Three small fixes landed in `FilterListConverter` (version 3 to 4). All four bundled lists still compile in WebKit.
- A follow-up with measured payoff: merge each untyped filter's two rules into one and add a single trailing top-frame exception. In a prototype that cut EasyList from 132,685 to 76,756 rules and 23.8 MB to 8.5 MB of JSON. Not shipped here; see "Follow-ups".

## What was compared

| Thing | Version |
|---|---|
| adblock-rust | v0.13.6 (commit `1108c61472dd`, 2026-11-17), built with `--features content-blocking`, release profile, Homebrew cargo 1.94.1 (the repo pins 1.100 in `rust-toolchain.toml`; Homebrew cargo ignores that and it built fine). Release binary of the harness: 3.9 MB. |
| Kaizu converter | `FilterListConverter` version 3 (before) and 4 (after the fixes in this branch) |
| EasyList | `! Version: 202610250646` |
| EasyPrivacy | `! Version: 202610250646` |
| EasyList Cookie List | `! Last modified: 2026-10-24 20:25 UTC` |
| kaizu.txt | ours, 21 filter lines, unversioned |
| Machine | Apple silicon, macOS 27, Swift 6.4.2 |

Brave's side is `FilterSet::into_content_blocking()` as called by `brave-core` (`components/brave_shields/core/common/adblock/rs/src/engine.rs`, `convert_rules_to_content_blocking`, iOS only). Each list is converted and compiled on its own, as Kaizu's `RuleListCompiler` does.

The harnesses (a Rust one linking adblock-rust, a Swift one compiling our two source files plus WebKit) and the scripts are in `docs/research/adblock-comparison-harness/`. Set `ADBLOCK_SCRATCH` to a scratch folder for clones, build products and outputs; the scripts read the filter lists and converter sources from this repository.

How WebKit behaviour was established: a Swift tool compiled each JSON file with `WKContentRuleListStore` in a throwaway store directory. Resource-type, ordering and top-level-document questions were answered by loading a page into a `WKWebView` with the rules applied, served from a loopback Python server that logs which requests arrive (a blocked request never reaches it). The decision tests (below) use a matcher modelled on those results, with adblock-rust's own `Engine` as the reference for what the filter lists mean.

## Rule counts and size

Per list, one WebKit rule list each.

| List | Non-comment lines | Brave rules | Kaizu v3 rules | Kaizu v4 rules |
|---|---|---|---|---|
| EasyList | 85,816 | 82,455 | 132,644 | 132,685 |
| EasyPrivacy | 56,406 | 56,298 | 111,609 | 111,609 |
| Cookie List | 25,351 | 25,325 | 26,242 | 26,268 |
| kaizu.txt | 21 | 22 | 4 | 4 |

Why we emit more: an untyped filter such as `||ads.example.com^` becomes two rules in ours (all subresource types, plus `document` limited to `load-context: child-frame`), so no rule can ever block a top-level page. Brave emits one rule with no `resource-type` and appends a single trailing "ignore previous rules for first-party documents" rule. Brave also groups no cosmetic selectors (one rule per selector); ours joins up to 50 site-specific selectors per rule.

| List | Brave JSON | Kaizu v4 JSON | Brave compile (median of 3) | Kaizu v4 compile (median of 3) | Compiles? |
|---|---|---|---|---|---|
| EasyList | 8.8 MB | 23.8 MB | 1.67 s | 2.34 s | both |
| EasyPrivacy | 6.0 MB | 21.6 MB | 1.49 s | 1.84 s | both |
| Cookie List | 3.1 MB | 3.5 MB | 0.89 s | 1.19 s | both |
| kaizu.txt | 3 KB | 1 KB | 1 ms | 1 ms | both |

WebKit's cap is real. Converting all four lists into one Brave list gives 164,097 rules, and WebKit refuses it: `Rule list compilation failed: Too many rules in JSON array`. The limit is 150,000 (brave-core hard-codes `MAX_CB_LIST_SIZE = 150000`, citing WebKit's `maxRuleCount`, and truncates before the trailing exception rule). Our converter's `maxRules` default is the same and we stay under it per list.

Compile times are one machine, one run of three each, so read them as "same order of magnitude, ours about 25 to 40 percent slower", not as precise.

## Lines each converter skips or can't express

Counts are filter lines, grouped by what the line asks for. A line counts as skipped when its converter emits nothing for it.

| Category | Brave | Kaizu v3 | Kaizu v4 |
|---|---|---|---|
| `$popup` (EasyList) | 2,970 | 2,970 | 2,970 |
| `$document` blocking (see below) | 1 | 587 | 587 |
| Procedural / extended CSS (`#?#`, `:has-text()` …) | 38 | 346 | 346 |
| Entity domains (`google.*##…`) | 253 | 255 | 253 |
| `$generichide` | 169 | 169 | 169 |
| Cosmetic selector other / unsupported (escapes, `::before`, …) | 39 | 203 | 51 |
| `$redirect` | 30 | 30 | 30 |
| Scriptlets (`##+js(…)`) | 30 | 30 | 30 |
| Regex network filters | 26 | 26 | 26 |
| Non-ASCII cosmetic | 10 | 10 | 10 |
| `$rewrite` | 8 | 8 | 8 |
| `$csp` | 5 | 5 | 5 |
| `:style()` / `:remove()` actions | 4 | 4 | 4 |
| `$ping` or `$websocket` as the only type (no mapping in Brave) | 58 | 0 | 0 |
| Other (odd `$domain=`, `$object`, `$method`, match-all, HTML filters, `#$#`) | 8 | 17 | 16 |
| `$removeparam`, `$badfilter`, `$cname`, `$replace` | 0 | 0 | 0 |
| **Total skipped lines** | **3,649** | **4,660** | **4,505** |

None of the four lists contains `$removeparam`, `$badfilter`, `$cname` or `$replace`, so those rows are zero by absence, not support. Per list for v4: EasyList 4,331, EasyPrivacy 82, Cookie List 92, kaizu.txt 0. Brave: 3,476, 136, 37, 0.

Brave skips fewer lines. That number overstates it, because several lines Brave "converts" are converted wrongly (next section).

## Where Brave's conversion is wrong

Each of these reproduces on the bundled lists. They're why a lower skip count isn't a better result.

| # | Behaviour in Brave's converter | Evidence |
|---|---|---|
| 1 | The trailing `^` of a filter is dropped, not turned into a separator, so `||ads.example.com^` also matches `ads.example.com.evil.test` and `ads.example.comx.test`. | 250 of 250 lookalike URLs built from plain `||host^` filters were blocked. Reference engine and Kaizu: 0 of 250. |
| 2 | A `^` in the middle of a pattern is escaped to a literal caret, so the rule can never match. | 110 of 120 sampled mid-`^` blocking filters were missed by Brave. Kaizu: 0 missed. The same bug makes `@@` exceptions with a mid `^` never fire, which showed up as 6 extra blocks in the main sample (Kaizu: 1, see below). |
| 3 | `$document` filters get `resource-type: []`. WebKit reads an empty array as "all types" (verified by loading a page: `[]` blocked every kind of request). 584 EasyList rules therefore block every request matching the pattern, not just page loads. | 4 of 40 sampled `||host^$document` filters blocked a plain third-party script from that host that the reference engine allows. |
| 4 | Cosmetic exceptions (`site.com#@#.ad`) are emitted as a hide rule with `unless-domain: [site.com]`, never as `ignore-previous-rules`. The exception isn't honoured, and the selector is hidden on every other site. | 652 `#@#` lines in the bundled lists. Example: `techymedies.com#@##ad-top` becomes `{"css-display-none", "#ad-top", unless-domain ["techymedies.com"]}`. |
| 5 | Cosmetic `if-domain` entries have no `*` prefix, so `example.com##.ad` doesn't apply on `www.example.com` (per Apple's rule format; network `domain=` entries do get the `*`). 10,765 EasyList rules and 7,937 Cookie List rules are affected. | Counted from the output JSON. I did not load a subdomain page to confirm the runtime effect. |
| 6 | Procedural filters like `site#?#.x:has-text(Sponsored)` are passed through as the selector. 308 lines count as converted but WebKit can't apply `:has-text()`. | Output JSON contains `.wrapper__0d616:has-text(Get Reward)` verbatim. |

Brave's side wins in one place: `$ping` and `$websocket` as the only type. adblock-rust has no mapping and skips them (58 lines, plus 3 more that also carry `domain=`); ours maps `ping` to WebKit's `other` and `websocket` to `websocket`.

None of this hurts Brave iOS, because it converts network filters only and handles cosmetics through the engine. It matters if we adopt the converter's output as-is, which is the question here.

## Blocking decisions on real URLs

Method. 1,721 requests, three deciders: adblock-rust's `Engine` loaded with all four lists (the reference for what ABP filters mean), Kaizu's rules, and Brave's rules (each list a separate rule list, matched with the verified WebKit semantics).

- 528 URLs derived from the lists' own patterns: 380 random blocking filters and 110 exceptions across the three big lists (hosts, paths, wildcards, `^`, `domain=`, types), 18 clean control URLs, and 20 top-level navigations to `||host^$document` hosts.
- 1,193 URLs read from the static HTML (script, img, iframe, stylesheet) of cnn.com, bbc.com, theverge.com, cnet.com, espn.com, weather.com, dailymail.co.uk, wired.com and foxnews.com. nytimes.com and forbes.com returned a ~770 byte bot wall and imdb.com returned nothing, so they contribute no URLs. Requests injected by JavaScript aren't in this set.

| Group | Requests | Reference blocks | Kaizu blocks | Brave blocks | Kaizu missed | Brave missed | Kaizu extra | Brave extra |
|---|---|---|---|---|---|---|---|---|
| Control (clean URLs, top-level pages) | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Cookie List patterns | 70 | 60 | 60 | 60 | 0 | 0 | 0 | 0 |
| EasyList patterns | 220 | 161 | 161 | 163 | 0 | 0 | 0 | 2 |
| EasyPrivacy patterns | 200 | 160 | 161 | 163 | 0 | 1 | 1 | 4 |
| Real sites, static HTML | 1,193 | 17 | 17 | 17 | 0 | 0 | 0 | 0 |
| Top-level `$document` navigations | 20 | 20 | 0 | 0 | 20 | 20 | 0 | 0 |
| **All** | **1,721** | **418** | **399** | **403** | **20** | **21** | **1** | **6** |

- The 20 "missed" top-level navigations are by design in both converters: the reference engine blocks the page, WebKit content blockers can't do that without a rule that blocks top-level documents, which Kaizu avoids by policy.
- Kaizu's one extra block is an exception in EasyPrivacy (`@@||yieldlove.com/v2/yieldlove-stroeer.js$domain=kino.de`) for a script that EasyList blocks. Exceptions don't cross rule lists, because each list is compiled separately. This is inherent to the per-list design and applies to Brave's output too.
- Before the `$important` fix, Kaizu also missed one (`||googletagmanager.com/gtm.js$important,domain=nexon.com`, overridden by an exception). That's the "Kaizu missed" cell that went from 1 to 0 in EasyPrivacy.
- The 18 control URLs, which include top-level page loads for wikipedia.org, github.com, youtube.com and apple.com, were never blocked by any decider.
- Adversarial set (410 requests, same method):

| Group | Requests | Reference blocks | Kaizu blocks | Brave blocks |
|---|---|---|---|---|
| Lookalike host suffix (`host` + `x.test`) | 150 | 0 | 0 | 150 |
| Lookalike host with dot (`host.evil.test`) | 100 | 0 | 0 | 100 |
| Mid-pattern `^` filters | 120 | 120 | 120 | 10 |
| Third-party script from a `$document` host | 40 | 36 | 36 | 40 |

The real-site sample is small and static. It shows no divergence on ad and tracker URLs that appear in page source, but it can't test the failure modes above, which need crafted URLs.

## Cosmetic handling and WebKit limits

| Topic | Brave converter | Kaizu |
|---|---|---|
| Cosmetic rules in iOS use | Not used. brave-core passes `RuleTypes::NetworkOnly`; hiding comes from the engine's `hide_selectors`. | Converted to `css-display-none` rules. |
| Rule cap (150,000) | Appends the trailing exception last, truncates arbitrary earlier rules when over (`swap` then `truncate`). | Exceptions always ship; network blocks first, then hiding, then the cut. Reports the drop in `skipped`. |
| `if-domain` / `unless-domain` | `if-domain` and `unless-domain` together are refused (`UnlessAndIfDomainTogetherUnsupported`). Network entries get `*`; cosmetic don't. | Refuses the mix too. All entries get `*`. Cosmetic exceptions turn into `unless-domain` on the hide rule, or are dropped when they'd need to un-hide part of an included site. |
| Entities (`google.*`) | Refused unless a plain hostname is listed beside it. | Same. |
| Domains over 65,535 domain-conditioned `.*` rules | Not handled (not needed for iOS). | Caps site-wide domain-scoped hiding at 60,000 rules (WebKit hits a `RELEASE_ASSERT` at 65,535). |
| Non-ASCII | Refused; punycodes `domain=` hosts. | Refused. |
| `url-filter` regex | Escapes `. + ? ^ $ { } ( ) | [ ] \`, turns `*` into `.*`, uses `^[^:]+:(//)?([^/]+\.)?host` for `||`. Refuses full-regex filters. | `^[^:]+://+([^:/]+\.)?host`, `^` becomes `[/:?=&]`, refuses `/regex/`, `|`, `{}`, `()`, `[]`, `\` in patterns, short unanchored patterns, bare `*`. |

Resource types, measured in a WKWebView with a loopback server (a type "blocks" a request if it never arrived):

| `resource-type` | Blocked |
|---|---|
| (absent) | everything, including frames |
| `[]` (empty) | everything, same as absent |
| `raw` | fetch, XHR, `sendBeacon`, EventSource, WebSocket, `<a ping>`, `link rel=preload as=fetch` |
| `fetch` | `fetch()` and XHR only |
| `other` | `sendBeacon`, EventSource, `<a ping>`, preload |
| `websocket` | WebSocket only |
| `document` | iframes (the test page itself was not covered by the pattern) |
| `ping` | `<a ping>` only |

Other WebKit facts confirmed in the same harness: `ignore-previous-rules` for `document` plus `load-type: first-party` lets a top-level page load through a catch-all block (what Brave relies on); a block rule placed after an `ignore-previous-rules` still blocks (what `$important` needs); escaped selectors like `.h-\[90px\]`, `#\30 _id`, `.group\/ads`, `.lg\:min-h-\[290px\]` hide correctly, including inside a grouped site-specific rule.

An observation we didn't expect: WebKit's compiler accepted Brave's `:has-text(...)` selectors without error, so unknown pseudo-class names don't fail compilation (they just never match). The converter's comment says one invalid selector makes WebKit reject the whole list. I did not test syntax errors such as unbalanced brackets, so I can't confirm or refute that, and the conservative allowlist stays.

## Scriptlets, redirects and other things content-blocker JSON can't do

WebKit content-blocker JSON has five actions: `block`, `block-cookies`, `css-display-none`, `make-https`, `ignore-previous-rules`. No script injection, no request rewriting, no response header changes. So these can't be expressed in JSON by anyone:

| Feature | Lines in the bundled lists | In adblock-rust | In Brave iOS |
|---|---|---|---|
| Scriptlets `##+js(…)` | 30 (all EasyPrivacy) | Resource storage plus `url_cosmetic_resources()` returns `injected_script` for a URL. Resources are uBlock Origin compatible (`resource-assembler` feature parses uBO's files). Privileged scriptlets are gated by permission bits such as `COOKIE_ACCESS`. | `CosmeticFilterModel` decodes `hide_selectors`, `procedural_actions`, `exceptions`, `injected_script`, `generichide`; an iOS scripts feature (`ios/browser/brave_shields/scriptlets`) injects the script into frames; a `content_cosmetic_ios.js` queries class and id selectors on the page. |
| `$redirect` / `$redirect-rule` | 30 | Redirect resources in the engine; the converter refuses (`NetworkRedirectUnsupported`). | Not in the rule list. |
| `$removeparam` | 0 | Refused by the converter (`NetworkRemoveparamUnsupported`). | n/a |
| `$csp`, `$replace`, `$header` | 5 | Refused by the converter. | n/a |
| Procedural cosmetic (`:has-text`, `:xpath`) | 346 | Parsed to `procedural_actions` (JSON), run by a page script. | Same page script path. |
| `$generichide` | 169 | Sets `generichide` for the URL; the page script stops asking for generic selectors. | Same. |

So Brave "covers" scriptlets on iOS by running a Rust filter engine in process and shipping a page script per frame, not through content blockers. The bundled lists only have 30 scriptlet lines, so the current gain would be small. The value shows up with uBO's own lists and Brave's, which Kaizu doesn't bundle.

Kaizu already runs its own page scripts (YouTube ad stripping, DuckDuckGo autoconsent). If it ever wants general scriptlets, the converter doesn't help; the relevant piece is the engine and its resources.

## Fixes made to our converter

Version 3 to 4. All four lists compile; `swift test` passes (216 tests); `scripts/build-trial.sh` succeeds.

| Fix | Before | After |
|---|---|---|
| CSS-escaped selectors (`.h-\[90px\]`, `#\30 _id`, `.lg\:min-h-\[290px\]`): the selector check skips a CSS escape whole instead of rejecting any backslash | 160 lines skipped | 5 skipped, 155 converted (EasyList 124, Cookie List 31). Skipped lines 4,660 to 4,505. |
| `$important` blocks follow the exceptions (which only cancel earlier rules) | An `@@` filter cancelled them. One sampled request was missed. | 0 missed in the sample. |
| `$object` beside other types is accepted and dropped; bare `$object` is skipped so it can't widen to every subresource | 3 lines skipped | 1 converted, 2 skipped. |

Safety: a bundled-list test now asserts that no block rule can reach a top-level document (every block rule has a `resource-type` without `document`, or `document` limited to `child-frame`). It passes on all four lists.

I did not change: regex filters (26 lines, the same lines Brave refuses), the `$document` handling (Brave's translation is wrong, see above), anything that would put `document` in a block rule.

## Recommendation

**Keep our converter, with the three fixes above. Do not adopt adblock-rust's converter.**

- Licensing is fine. adblock-rust is MPL-2.0 and Kaizu is MPL-2.0, so linking or vendoring is allowed. Cost isn't licensing. It's a Rust toolchain in the build, an FFI layer, a 3.9 MB native library plus 60 crates, for a converter whose output is smaller (fewer rules, less JSON) but wrong on correctness in the six ways above.
- Behaviours adopted from Brave's output: CSS escapes in selectors (the only coverage gap that mattered), and `$object` beside other types.
- Behaviours deliberately not adopted: dropping the trailing `^`, literal mid-pattern `^`, `$document` with an empty type list, cosmetic exceptions as hide rules, un-starred cosmetic domains.
- `$important` ordering is beyond Brave (it ignores `$important` too).

## Follow-ups worth a roadmap line each

1. **One rule per untyped filter plus one trailing top-frame exception.** Brave's idea, with a stricter exception: `{"url-filter":".*", "resource-type":["document"], "load-context":["top-frame"]} → ignore-previous-rules` as the very last rule, instead of Brave's first-party exception (which also exempts same-site iframes). Prototyped by rewriting our output:

   | List | Rules now | Prototype | JSON now | Prototype | Compile now (median of 3) | Prototype |
   |---|---|---|---|---|---|---|
   | EasyList | 132,685 | 76,756 | 23.8 MB | 8.5 MB | 2.34 s | 2.03 s |
   | EasyPrivacy | 111,609 | 56,789 | 21.6 MB | 6.4 MB | 1.84 s | 1.53 s |
   | Cookie List | 26,268 | 24,663 | 3.5 MB | 3.1 MB | 1.19 s | 1.11 s |

   Decisions on all 1,721 requests were identical to the current output. The cost: the guarantee "no rule blocks a top-level page" moves from per-rule to one final rule, so rule truncation and ordering must keep that rule last, and the bundled-list test needs rewriting around it. I'd want a stress test on that before shipping.
2. **`$popup`** (2,970 EasyList lines, skipped by both). WebKit has a `popup` resource type. I did not test whether `WKWebView` applies it to `window.open`.
3. **`$generichide` / `$elemhide` exceptions** (169 lines, skipped by both) and **entity domains** (253). Expressible with ordering changes; each needs its own test.
4. **Cross-list exceptions** don't apply because each list compiles on its own. One sampled request shows the effect. Merging lists is blocked by the 150,000 cap.

## What I couldn't measure

- Real recorded browsing: only static HTML from nine homepages, with no JavaScript-injected requests and no logged-in flows. A recorded-traffic run (for example a local proxy log from a browsing session) would tell us whether the lookalike and `$document` problems matter in practice.
- Runtime effect of un-starred cosmetic `if-domain` entries on subdomains: counted in the JSON, not tested in a page.
- Whether `popup` type rules work in WKWebView.
- Brave iOS beyond what's in brave-core's source: I read `engine.rs`, `CosmeticFilterModel.swift` and file names under `ios/browser/brave_shields/scriptlets`, not the full injection path, and didn't run Brave iOS.
- AdGuard's converter: not run (GPL-3.0). Not compared.
- Memory use of a compiled list, and per-request match cost. Compile time only, one machine.
- The decision matcher models WebKit from what the loopback tests showed (resource types, ordering, first-party document exception, empty arrays). Rules were compiled by the real WebKit, but request matching for the 1,721 URLs ran in my model, not in WebKit. The load-type "third-party" test uses a simple registrable-domain approximation.
