# What Kaizu connects to

Kaizu has no account, no analytics and no crash reporting. Apart from the pages you open, it makes the few requests below, each for one job. None of them sends cookies or anything about you or your Mac beyond what every web request carries: your IP address, and a user agent naming Kaizu's build and macOS's network library.

| What | When | Where | What it sends |
| --- | --- | --- | --- |
| Update check | 10 seconds after launch, then every 6 hours | `kaizu.joinprototype.com/version.json` | Nothing; it reads a small public file |
| Update download | When that file lists a newer build | `kaizu.joinprototype.com/updates/` | Nothing; the archive's signature is checked before it's used |
| Ad and tracker lists | At most once a day, retried hourly while offline | `easylist.to` (EasyList, EasyPrivacy), `secure.fanboy.co.nz` (cookie list) | Nothing |
| Exchange rates | Only after you type a currency conversion in the command bar; kept for half a day | `api.frankfurter.dev` | Nothing; one request for all rates, never what you typed |
| Site icons | When a page finishes loading | The site you're on | No cookies, even in its profile |
| Search suggestions | **Off unless you turn them on** (Settings → General); then as you pause typing in the command bar | Your search engine | What you typed, as the engine's own suggestion box would. Never for anything that looks like an address or a search shortcut, and never in a private window |
| Extension downloads | When you choose **Add to Kaizu** on a store listing | `clients2.google.com` (Chrome Web Store) or `addons.mozilla.org` | The extension's ID |

Crash and hang reports stay on your Mac. **Help → Report a Bug** writes a Mail draft. Its **Include diagnostics** switch, on by default, adds these reports, your Mac's model and a few Kaizu settings; turn it off to send only the Kaizu and macOS versions. Nothing leaves until you send the draft yourself.

Extensions you install can make their own requests, within the permissions they ask for.

WebKit's fraudulent-website warning is left at its default, which is on. It's part of macOS's WebKit, not Kaizu, and works as it does in Safari.

To check this list against the code, search the sources for `URLSession`: these are the only places Kaizu makes requests of its own.
