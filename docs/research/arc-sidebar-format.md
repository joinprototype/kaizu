# Arc `StorableSidebar.json` on-disk format

Purpose: reference for the Kaizu Arc importer. Arc is closed source and the format is undocumented, so everything
below is reverse-engineered by third-party parsers. Researched 2026-10-25 from GitHub code (no Arc install available).
Marks: **[V]** = verified in at least one real-file fixture (adlio/linkcache, Zarrar09 sample) that was read and
inspected directly, and/or agreed by several independent parsers. **[U]** = unverified / single source / inferred.

Test fixture that follows this document: `Tests/BrowserCoreTests/Fixtures/StorableSidebar.json`.

## 0. File facts

- macOS: `~/Library/Application Support/Arc/StorableSidebar.json`. **[V]**
- Windows: `%LOCALAPPDATA%\Packages\TheBrowserCompany.Arc_<publisherHash>\LocalCache\Local\Arc\StorableSidebar.json`
  (match the `TheBrowserCompany.Arc_` prefix, expect exactly one). **[V]** (arc-export `main.py` `read_json`;
  blanc `arc-import-source.js` L19-L46). Same JSON schema as macOS; no schema difference reported by any parser. **[U]**
  that none exists.
- Plain UTF-8 JSON. Not encrypted, not compressed. Arc writes `"key" : value` spacing and `\/` escapes, both legal JSON.
  **[V]** (fixture read with stock `json.load`).
- Sibling files in the same folder: `StorableSidebar.<date>-<time>-<ms>.json` (Arc's own backup rotations),
  `StorableArchiveItems.json` (archived tabs, see section 8), `StorableWindows.json` (window state), `StorableHome.json`,
  `StorableProfiles.json` (contents unknown **[U]**). Per-profile Chromium data (history, favicons) lives in
  `Arc/User Data/<Default|Profile N>/`.
- Size: real files reach tens of MB because of the sync mirrors (section 7). Blanc caps at 32 MiB.
- Arc keeps the file open and rewrites it; read a copy, and re-stat after reading (blanc `readArcSidebarFile`).
- Timestamps (`createdAt`, `timeLastActiveAt`) are Apple reference-date seconds (since 2001-01-01 UTC, float):
  `unix = value + 978307200`. **[V]**

## 1. Top-level structure

```
root
  version                    int, always 1 in every fixture seen [V]
  sidebar
    containers[]             flat "key, value, key, value" array (see 1.1)
  sidebarSyncState           CloudKit mirror; ignore (section 7)
  firebaseSyncState          second mirror; ignore
```

### 1.1 Alternating `key, value` arrays

Arc serialises Swift dictionaries as flat arrays alternating key and value. Applies to: `sidebar.containers`,
`containers[n].spaces`, `.items`, `.topAppsContainerIDs`, `space.containerIDs`, `space.newContainerIDs`.
**[V]** (Zen `pairs()` in `ZenMigrationUtils.sys.mjs` L42-L54; Nook `Arc.swift` `pairs`; helium patch `ParseItems`).

| Array | key (even index) | value (odd index) |
|---|---|---|
| `sidebar.containers` | object: `{"global":{}}`, `{"littleBrowser":{"_0":uuid}}`, `{"standalone":{"_0":uuid}}` | the container data object |
| `spaces` | space id string | space object (also has `id`, equal to the key) |
| `items` | item id string | item object (also has `id`, equal to the key) |
| `topAppsContainerIDs` | profile tag object (same shape as `space.profile`) | item id of the favorites container |
| `containerIDs` | marker string `"pinned"` / `"unpinned"` | item id of that section's container |
| `newContainerIDs` | marker object `{"pinned":{}}` / `{"unpinned":{"_0":{"shared":{}}}}` | item id |

Robust reading: iterate in steps of 2 and skip malformed pairs, OR (simpler, what Ardia/blanc/Nook do) walk the array,
keep only elements that are JSON objects, and key them by their own `"id"`. Both give the same result because the id
string always equals `object.id`. Some third-party tests also use a plain object keyed by id; Crest's `Objects()`
accepts both array and object forms (`ArcSidebar.cs` L89-L105). **[U]** that Arc itself ever emits the object form.

### 1.2 Which container holds the data

`sidebar.containers` has, in order, `key, value` pairs. The real data container is **the value immediately after the
`{"global": {}}` key**. **[V]**
- adlio fixture: `containers = [ {"global":{}}, {spaces, topAppsContainerIDs, items} ]` (2 elements).
- Zarrar sample: 10 elements: `littleBrowser, <data>, standalone, <data>, standalone, <data>, standalone, <data>, global, <data>`.
  The `global` pair is **last**. Several data containers each with `items`/`spaces`/`topAppsContainerIDs` exist; only the
  `global` one is the user's sidebar. `littleBrowser` = Little Arc window, `standalone` = other windows (purpose **[U]**).
- Parsers that pick "first container with `spaces` and `items`" (blanc `arc-sidebar.js` L92-L93, Nook `Arc.swift`,
  Arcmark, Raycast) are wrong on files like the Zarrar sample. Correct rule (arc-export `convert_json_to_html`;
  Ardia `ArcSidebar.mainContainer` L122-L129): find index `i` where `containers[i-1]` has key `global`; fall back to
  first container with `spaces`/`items` that is not preceded by a `littleBrowser` key.

The data container's keys: `spaces`, `items`, `topAppsContainerIDs` (key order varies; do not rely on order).

## 2. Spaces: `containers[g+1].spaces[]`

| Key | Notes |
|---|---|
| `id` | Opaque string. Usually uppercase UUID, but the first space of an account can be `thebrowser.company.defaultPersonalSpaceID` (its containers are `thebrowser.company.defaultPersonalSpacePinnedContainerID` / `...UnpinnedContainerID`). Treat ids as opaque. **[V]** |
| `title` | Space name. May be missing/empty: fall back to `"Personal"` for the default id, else `"Space N"` (Zen `arcSpaceTitle`). **[V]** |
| `profile` | Profile tag, see 2.2. |
| `containerIDs` | `["pinned", P, "unpinned", U]` (strings). |
| `newContainerIDs` | `[{"pinned":{}}, P, {"unpinned":{"_0":{"shared":{}}}}, U]`. Same ids, object markers. Meaning of `"shared"` **[U]**. |
| `customInfo.iconType` | Icon, see 2.3. `customInfo` may be missing or null. |
| `customInfo.windowTheme` | Colors, see 2.4. |

### 2.1 Pinned vs unpinned (Today) containers

Resolve by **marker, never by position**: both `["pinned",P,"unpinned",U]` and `["unpinned",U,"pinned",P]` occur in the
wild (Nook comment; kyuzen research citing `boom/STORAGE.md` and `leohku/arc-blog`). A space can have only one of the two
**[U]** (Zarrar sample's first space has only unpinned, per kyuzen's notes; I did not re-verify). Prefer `containerIDs`,
fall back to `newContainerIDs` (key the object marker by its single key). Older exporters use only `newContainerIDs`
(arc-export `get_spaces`); some modern files might have only one of the two **[U]**.

Each container id is an item with `data.itemContainer.containerType.spaceItems._0 == <space id>` and `parentID: null`. **[V]**
- pinned container's children = the space's pinned tabs and folders ("Pinned" area under the favorites row).
- unpinned container's children = "Today" tabs (open, unsaved; Arc auto-archives them after a timer).

### 2.2 Profile tag

Same object shape in `space.profile` and in the keys of `topAppsContainerIDs`. **[V]**

```json
{ "default": {} }                                                         // default profile ("Default" dir)
{ "default": true }                                                        // also seen (jtotty/Zarrar fixtures, Raycast)
{ "custom": { "_0": { "directoryBasename": "Profile 1", "machineID": "<UUID>" } } }
```

- Test for the **presence** of the `default` key, not its value (`{}` vs `true` both occur).
- Custom profile: `directoryBasename` is the Chromium dir under `Arc/User Data/` (`Profile 1`, `Profile 2`...).
  `machineID` identifies the Mac that created the profile (the file syncs across Macs, so tags from other machines can
  appear). The literal string `"Default"` never appears; default maps to `User Data/Default`.
- Validate `directoryBasename` as a single path component (not empty, no `/` or `\`, not `.`/`..`) before using it as a path.
- Missing `profile` key: treat as default (blanc, Phi). Whether Arc omits it **[U]**.
- Profile display names (user-given, e.g. "Work") are not in this file. Nook reads them from `User Data/Local State`
  `profile.info_cache` **[U]** (not verified here). Ignore the internal `__ARC_SYSTEM_PROFILE` entry.

### 2.3 Icon: `customInfo.iconType`

Exactly one of, **[V]** (adlio fixture + Zen `arcSpaceIcon` + Ardia `emoji()`):
```json
{ "emoji_v2": "🏢", "emoji": 127970 }   // prefer emoji_v2 (string); emoji = Unicode scalar as int (legacy)
{ "emoji": 127970 }                     // older data: scalar only (reject invalid scalars / surrogates)
{ "icon": "planet" }                    // named SF-symbol-like Arc icon; full list [U]
```
Order: `emoji_v2` > `emoji` (int; Ardia also tolerates a string) > `icon` > none.

### 2.4 Theme: `customInfo.windowTheme`

Optional. Swift enums are encoded as `{"<case>": {"_0": payload}}`. Colors are
`{red, green, blue, alpha, colorSpace:"extendedSRGB"}`, components may be outside 0...1 (clamp). **[V]**
- Simple accent: `windowTheme.primaryColorPalette.midTone` (Nook, arc2zen, Ardia). Also `tintedLight`, `shaded`, `shadedDark`.
- Source of truth for what Arc paints: `windowTheme.background.single._0.style.color._0` then either
  `blendedSingleColor._0.color` (+ `modifiers.intensityFactor`, `noiseFactor`, `overlay:"grain"`) or
  `blendedGradient._0.baseColors[]` / `overlayColors[]` (Zen `arcSpaceTheme` L108-L160).
- Also `semanticColorPalette.appearanceBased.{light,dark}.*` (derived UI colors; ignore).
- Which of `midTone` or `background...color` Arc shows as "the" space color: **[U]**. They matched in the adlio fixture.
  Recommended: use `midTone`, fall back to first color found in `background`.

## 3. Items: `containers[g+1].items[]`

All items live in one flat id-keyed table; the tree is built from `childrenIds` (authoritative order) / `parentID`.

| Key | Notes |
|---|---|
| `id` | Same as the array key. Uppercase UUID (or `thebrowser.company.default...` for the default space containers). |
| `parentID` | Parent item id; `null` for roots (itemContainers). |
| `childrenIds` | Ordered child ids = display order. Present (possibly `[]`) on every item. Missing ids should be skipped. |
| `title` | User-set title, or `null`. For tabs it **overrides** `savedTitle`. For folders it is the folder name. |
| `createdAt` | Apple-epoch seconds. |
| `isUnread`, `originatingDevice` | Not needed. |
| `data` | Object with **exactly one key** naming the item kind (section 3.1). |

Tree walk should use `childrenIds` for order and fall back to `parentID == id` for children not listed (Zen, blanc do
this; the old arc-export and Arcmark use only `parentID`, which loses order). Guard against cycles with a visited set and
cap depth (Zen 32, Ardia 64, Crest `FolderTree.MaximumDepth`). Arc auto-creates a "Recently recovered" folder for orphans **[U]**
(Icesource DATA_MODEL.md).

### 3.1 Item kinds (key of `data`)

| `data` key | Detect | Meaning | Import |
|---|---|---|---|
| `tab` | `data.tab` exists | A tab (pinned, Today or favorite depending on ancestor container). Keys: `savedURL`, `savedTitle`, `savedMuteStatus`, `timeLastActiveAt`, `activeTabBeforeCreationID`, `referrerID`. **[V]** | yes |
| `list` | `data.list` exists (value `{}`) | Folder. Name = `title`. Nests arbitrarily (child `list`s). Live GitHub/Bitbucket PR folders carry `data.list.automaticLiveFolderData` (Ardia `liveFolderRole`) **[U]**: treat as an empty folder or skip. | yes (folder) |
| `itemContainer` | `data.itemContainer.containerType` | Root of a section. `containerType` is `{"spaceItems":{"_0":<spaceId>}}` or `{"topApps":{"_0":<profile tag>}}`. `parentID:null`. **[V]** | walk children only |
| `splitView` | `data.splitView` | Split view; `childrenIds` are the tabs shown together (max 4). Fields `layoutOrientation` ("horizontal" = side by side), `itemWidthFactors`, `customInfo`, `focusItemID`. Appears in pinned, in folders, in favorites and Today. | Kaizu: flatten (import child tabs in place) or skip; **decision needed** |
| `easel` | `data.easel` | Easel whiteboard: `{easelID, title}`. No URL. **[V]** (leohku parser, Ora `EaselData`) | skip |
| `arcDocument` | `data.arcDocument` | Arc Note: `{arcDocumentID}`. **[U]** (leohku parser only) | skip |
| `welcomeToArc` | `data.welcomeToArc` | Onboarding item. **[U]** (jtotty fixture via kyuzen) | skip |
| other | anything else | Unknown future kinds | skip, count, never fail |

Classification precedence used by all parsers: `tab` -> `list` -> `splitView` -> `itemContainer` -> skip.
Do **not** infer "folder" from `childrenIds` non-empty (Arcmark does; it misclassifies splitViews/containers). Detecting
by `data.list` is correct.

### 3.2 Tab details

- URL: `data.tab.savedURL`. Skip if empty or non-importable (`arc://...`, `about:` etc.; Zen allows only http/https/file/ftp;
  helium skips `arc://`). Nook/Icesource mention `data.tab.currentURL` as fallback **[U]** (not in any fixture I read).
- Title to display: **`item.title` if non-empty, else `data.tab.savedTitle`, else URL** (Raycast, arc-export, Nook, blanc,
  helium, Ardia agree; Zen's importer prefers `savedTitle`, which loses user renames, so do not copy that).
  Keep both: custom title and `savedTitle` (page title) are different things (Nook, Ardia keep `customTitle` + page title).
  Nook drops `customTitle` when equal to `savedTitle`.
- No favicon field exists on tabs. Favicons come from the profile's Chromium `User Data/<dir>/Favicons` SQLite. **[U]** that none exists.
- Pinned tab's `savedURL` is the pinned address; navigated-away URL is not stored.

## 4. Favorites ("top apps"): `containers[g+1].topAppsContainerIDs`

Alternating `[profileTag, containerItemId, ...]`. **[V]**
- Each `containerItemId` is an item: `data.itemContainer.containerType.topApps._0 == <same profile tag>`, `parentID:null`;
  favorites are its `childrenIds` in order (tabs, occasionally splitViews). Folders inside favorites: **[U]**; flatten if seen.
- Favorites belong to a **profile**, not a space. Every space with that profile shows the same row. Import: attach the
  favorites list to the profile and show it in every space of that profile (Nook copies them into each space).
- Match space to favorites by profile tag: default -> any tag with `default` key; custom -> `directoryBasename` (+ `machineID`).
- Duplicates: one profile can have **several** favorites containers (one per `machineID`; adlio fixture has
  `Profile 1` twice with different machineIDs, some empty). Union them by `directoryBasename`, deduping by URL
  (mhadi-exporter approach via kyuzen; Crest matches machineID first). The default profile's tag has no machineID.
- Fallback source: `sidebarSyncState.container.value.topAppsContainerIDs` (same pair layout; also `topAppsContainerID`
  singular) if the main one is empty (Nook).
- To find favorites without the profile tag, scan all items for `itemContainer.containerType.topApps` (blanc does this).

## 5. Walking algorithm (what the importer should do)

1. `root = JSON(file)`; `containers = root.sidebar.containers`. Find the data container after key `{"global":...}` (1.2).
2. `items[id] = object` from `container.items` (objects only; last wins on duplicate ids, as Crest does).
3. For each object in `container.spaces` (array order = sidebar order): title, profile tag, icon, theme;
   `pinnedId`/`todayId` from `containerIDs` (fallback `newContainerIDs`) by marker.
4. `children(id)`: `items[id].childrenIds` mapped through `items` (skip missing), then orphan `parentID` matches.
5. Convert recursively with a visited set: `data.tab` -> tab, `data.list` -> folder (recurse), `data.splitView` -> recurse
   into its children in place (or skip), anything else -> skip.
6. Favorites: for each pair in `topAppsContainerIDs`, convert the container's children, group by profile.
7. Space -> favorites: look up by the space's profile tag.
8. Ignore `sidebarSyncState` / `firebaseSyncState` except the favorites fallback in section 4.

## 6. Multi-window / multi-profile edge cases

- Little Arc / standalone windows have separate data containers inside `sidebar.containers`; only `global` is the sidebar (1.2).
- Multiple profiles: `space.profile` differs per space; favorites per profile (section 4); a space's tabs are all in that profile.
- Multiple Macs: `machineID` differs; the file may carry other machines' profile tags and empty favorites containers.
- Spaces without a title; the default personal space with a non-UUID id; spaces with only one of pinned/unpinned.
- Empty `savedURL` ("dangling" tabs), `arc://` URLs, empty folders (drop or keep: policy), duplicate URLs across pinned/favorites.
- Folder name `title` can be `null`: use "Untitled Folder".
- Invisible Unicode characters in titles from some sites (Icesource note); trim/normalize.
- Colors can be slightly negative or >1 (extended sRGB); clamp.
- Arc may be running and mid-save, or the iCloud-sync may rewrite the file; import from a copy.
- Windows Arc: only the path differs (section 0). **[U]** for any structural difference.

## 7. Versioning and the sync mirrors

- `root.version`: `1` in every fixture/real file seen. No parser branches on it. No documented schema versions. **[U]** whether
  Arc bumps it. The only evolution seen is in space container keys: `containerIDs` (strings) is older, `newContainerIDs` (objects)
  is newer; both usually present. Write the importer to accept either, to tolerate missing/new keys and unknown `data` kinds.
- `sidebarSyncState` (CloudKit) and `firebaseSyncState.syncData` (Firebase) hold copies. `sidebarSyncState.container.value`
  has `orderedSpaceIDs`, `topAppsContainerIDs`, `topAppsContainerID`, `version` (6 in adlio fixture); `spaceModels` and `items`
  are `{value:<same object>, encodedCKRecordFields:"<base64 bplist>"}` wrappers. They can be empty or stale. Read `sidebar`,
  ignore mirrors (exception: favorites fallback, section 4). Order of spaces: `spaces` array; whether `orderedSpaceIDs` wins
  on disagreement **[U]**.
- Shapes tolerated by existing importers because real files vary: `profile.default` as `{}` or `true`; `unpinned` marker with
  or without `_0`; `emoji` int or `emoji_v2` string.

## 8. Other files worth importing

- `StorableArchiveItems.json`: archived (auto-expired / manually closed) tabs. Shape (from `arc2zen/restore_auto_archived.py`,
  `arcaeologist/src/parser.js`): `{ "items": [ id, {…}, … ] }` where each item has `archivedAt` (Apple-epoch seconds),
  `reason` (`"auto"` or `"manual"`), `source.space._0` (space id), `sidebarItem` = a normal item (`sidebarItem.data.tab.savedURL`,
  `savedTitle`). **[U]** exact schema (two third-party readers only; I did not inspect a real file). Suggest importing as an
  optional "Archive" folder per space, not by default.
- `StorableWindows.json` (open window/tab state) and `StorableHome.json`: not parsed by any importer; skip.
- Not in the file: history, cookies, passwords, extensions, Boosts, Air Traffic Control rules (Chromium dirs / other files).

## 9. Commented minimal example

JSONC for illustration (the real file is plain JSON, no comments). Full valid version is the fixture.

```jsonc
{
  "version": 1,
  "sidebar": {
    "containers": [
      { "global": {} },                              // key; the container after this key is the real data
      {                                              // value: data container
        "spaces": [
          "SPACE-1", {                               // key, then object
            "id": "SPACE-1", "title": "Work",
            "profile": { "default": {} },            // default profile
            "containerIDs": ["pinned", "W-PIN", "unpinned", "W-TODAY"],
            "newContainerIDs": [{ "pinned": {} }, "W-PIN", { "unpinned": { "_0": { "shared": {} } } }, "W-TODAY"],
            "customInfo": {
              "iconType": { "emoji_v2": "🏢", "emoji": 127970 },   // or { "icon": "planet" }
              "windowTheme": { "primaryColorPalette": { "midTone": { "red": 0.42, "green": 0.73, "blue": 0.85, "alpha": 1, "colorSpace": "extendedSRGB" } } }
            }
          }
        ],
        "topAppsContainerIDs": [
          { "default": {} }, "FAV-DEFAULT",          // profile tag, favorites container id
          { "custom": { "_0": { "directoryBasename": "Profile 1", "machineID": "…" } } }, "FAV-P1"
        ],
        "items": [
          "W-PIN", {                                 // section root: parentID null, itemContainer
            "id": "W-PIN", "parentID": null, "title": null, "childrenIds": ["T1", "F1"],
            "data": { "itemContainer": { "containerType": { "spaceItems": { "_0": "SPACE-1" } } } }
          },
          "T1", { "id": "T1", "parentID": "W-PIN", "title": null, "childrenIds": [],
                  "data": { "tab": { "savedURL": "https://example.test/", "savedTitle": "Example" } } },
          "F1", { "id": "F1", "parentID": "W-PIN", "title": "Docs", "childrenIds": [],   // folder
                  "data": { "list": {} } },
          "FAV-DEFAULT", { "id": "FAV-DEFAULT", "parentID": null, "childrenIds": [],
                  "data": { "itemContainer": { "containerType": { "topApps": { "_0": { "default": {} } } } } } }
        ]
      }
    ]
  }
}
```

## 10. Sources

Read directly (code), with the part used:
- ivnvxd/arc-export `main.py` (`read_json`, `convert_json_to_html`, `get_spaces`, `convert_to_bookmarks`): Windows path, `global` rule, `newContainerIDs`. https://github.com/ivnvxd/arc-export/blob/main/main.py
- zen-browser/desktop `src/zen/migration/ZenMigrationUtils.sys.mjs` (`pairs` L42-L54, `arcSpaceTitle/Icon/Theme` L79-L160, `parseArcSidebar` ~L230-L330): full walker, theme, `kArcDefaultSpaceId`. https://github.com/zen-browser/desktop/blob/dev/src/zen/migration/ZenMigrationUtils.sys.mjs
- nook-browser/Nook `Nook/Managers/ImportManager/Arc.swift` (`parseArcSidebarData`, `key()`, `pairs()`, `hex()`): profile keys, favorites mirror fallback, customTitle handling. https://github.com/nook-browser/Nook/blob/main/Nook/Managers/ImportManager/Arc.swift
- mantrakp04/ardia `packages/import/ios/Core/ArcSidebar.swift` (`mainContainer` L122-L129, `profileDirectory` L149-L155, `containerIDs` L157-L167, `tree` L181-L203, `emoji` L219-L224, `midTone` L232): https://github.com/mantrakp04/ardia/blob/main/packages/import/ios/Core/ArcSidebar.swift
- bnfy/blanc `src/main/arc-sidebar.js` (`spaceContainerIds` L52-L66, `collect` L125-L157, topApps scan L179-L191) and `arc-import-source.js` (Windows/mac paths): https://github.com/bnfy/blanc/blob/main/src/main/arc-sidebar.js
- sanogueralorenzo/sanogueralorenzo.github.io `tools/crest/.../ArcSidebar.cs` (`Read` L48-L84, `Objects` L89-L105, `ReadItem` L107-L120, `ProfileKey` L140-L146, `Append` L166-L189): profile+machineID, splitView, duplicate favorites.
- raycast/extensions `extensions/browser-bookmarks/src/hooks/useArcBookmarks.ts` (types L13-L71, `getContainerIds` L86-L100): default vs custom profile, topApps by profile. https://github.com/raycast/extensions/blob/main/extensions/browser-bookmarks/src/hooks/useArcBookmarks.ts
- imputnet/helium `patches/helium/core/add-arc-importer.patch` (`ParseItems`, `ParseSpaces`, `WalkItem`): `itemContainer`, `arc://` skip, createdAt.
- Geek-1001/arcmark `docs/ARC_IMPORT_ARCHITECTURE.md` and `Sources/ArcmarkCore/ArcImportService.swift`: (cautionary) folder-by-`childrenIds` heuristic, first-container-with-spaces heuristic.
- the-ora/browser `ora/Features/Importer/Services/Importer.swift`: Codable models incl. `EaselData`.
- leohku/arc-blog `test-parser/parser.js`: enumerates `tab`, `arcDocument`, `easel`, `list`, `itemContainer`, `splitView`.
- rafcabezas/arc2zen `restore_auto_archived.py`, plainspace/arcaeologist `src/parser.js`: `StorableArchiveItems.json`.
- Real-file fixtures downloaded and inspected: adlio/linkcache `test_data/StorableSidebar.json` (2 containers, default+custom profiles, 3 `Profile 1` favorites containers, emoji and `icon` icons, `version` 1 / sync `version` 6); Zarrar09/A-New-Arc-Begins `tests/fixtures/sampleStorableSidebar.json` (10 containers with littleBrowser/standalone/global).

Read via secondary compilation (their line citations not independently re-verified):
- tigranhov/kyuzen-browser `docs/research/zen-arc-import-formats.md` section 1 (cites luizberti/boom `STORAGE.md`, Icesource/arc-tab-organizer `DATA_MODEL.md`, phibrowser/phibrowser-mac `ArcDataParser.swift`, mhadifilms/arc-exporter, pauljoda/Crest, happylinks/arc-mcp). Source of: `splitView` field list, `welcomeToArc`, `Profile` shapes, `standalone` containers.
- Icesource/arc-tab-organizer `DATA_MODEL.md`: quirks, related files.

## 11. Unverified list

1. `StorableArchiveItems.json` exact schema (only two scripts read; no real file inspected).
2. `currentURL` fallback on tabs (mentioned by Nook and Icesource; absent in fixtures).
3. Meaning of `{"unpinned":{"_0":{"shared":{}}}}`, `standalone`/`littleBrowser` container purposes.
4. Whether spaces can lack one of pinned/unpinned; whether `profile` is ever omitted.
5. Whether favorites can contain folders; whether notes/easels can have children.
6. Named `iconType.icon` values; `itemWidthFactors`/`focusItemID` semantics; `orderedSpaceIDs` vs `spaces` order precedence.
7. Any Windows-specific schema difference (only the path is documented). Any Arc-version-specific schema change (no `version` bump seen).
8. Profile display names location (`Local State` `profile.info_cache`); how to find "this Mac's" `machineID`.
9. `automaticLiveFolderData` (live PR folders) shape.
10. Whether `midTone` or `background...color` is the canonical space color.
11. Everything here is from files produced by Arc up to ~2025-2026; behavior of the final Arc release before Dec 22, 2026 is not confirmed. Re-check against a real export before shipping.
