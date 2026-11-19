# Bundled page scripts

| File | What | Source | License |
|---|---|---|---|
| `youtube-ads.js` | Strips YouTube ad payloads, skips leftover ads | Ours | Same as Kaizu |
| `autoconsent-isolated.js` | Finds cookie consent pop-ups and rejects non-essential cookies, from an isolated world | `@duckduckgo/autoconsent` 16.61.0, `dist/autoconsent.esm.js` bundled with our `scripts/autoconsent/content.js` by esbuild ([source](https://github.com/duckduckgo/autoconsent)) | MPL-2.0 (`autoconsent-LICENSE.txt`); the glue is ours |
| `autoconsent-rules.json` | The consent rules the app filters per frame | Same release, `rules/compact-rules.json`, unmodified | MPL-2.0 |
| `autoconsent-snippets.json` | The page-state checks the app may run in the page's world, by id | Same release, `evalSnippets` from `dist/autoconsent.cjs.js` | MPL-2.0 |
| `readability.js` | Finds the article on a page for Reader (⇧⌘R) | `@mozilla/readability` 0.6.0, `Readability.js`, unmodified ([source](https://github.com/mozilla/readability)) | Apache-2.0 (`readability-LICENSE.txt`) |

All autoconsent files come from one release and are rebuilt together with
`scripts/vendor-autoconsent.sh <version>`, which also regenerates the test
fixture that checks Kaizu's rule filtering against autoconsent's own.
