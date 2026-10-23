# CLAUDE.md — Project Rules & Working Agreement

## Project Overview

**App name:** booklist (working title)
**Goal:** A native macOS bookmarks and wishlist manager designed to be ADHD-friendly.

**Core problem it solves:**
People with ADHD often end up with dozens of open browser tabs and disorganized bookmarks because they lose track of what they've already saved. This app should be a calm, focused alternative — a single place to capture, organize, and retrieve URLs without feeling overwhelmed.

**Design philosophy:**
- Reduce cognitive load at every step
- Fast capture (saving a link should take seconds, not decisions)
- Easy retrieval (search and tags over deep folder hierarchies)
- Clear visual hierarchy — one thing at a time
- Avoid information overload in the UI

---

## Tech Stack

| Layer        | Technology         | Notes                                      |
|--------------|--------------------|--------------------------------------------|
| Language     | Swift 5.x          | Latest stable                              |
| UI           | SwiftUI            | Declarative, macOS-native                  |
| Persistence  | SwiftData          | Already bootstrapped in the project        |
| Concurrency  | Swift async/await  | Never use Combine                          |
| Platform     | macOS only         | No iOS/iPadOS targets needed               |
| Min target   | macOS 14+          | Required for SwiftData                     |

---

## Architecture

- **Pattern:** MVVM (Model–View–ViewModel)
- Models live in `Models/` and use `@Model` (SwiftData)
- Views live in `Views/` and are broken into small, focused SwiftUI views
- ViewModels (when needed) live in `ViewModels/` and handle business logic
- No God views — if a view body grows complex, extract subviews

---

## Code Style

- **Naming:** PascalCase for types and structs, camelCase for properties and methods
- **State:** Use `@State private var` for local UI state, `@Query` for SwiftData queries
- **Constants:** Use `let` wherever possible
- **Optionals:** Avoid force-unwrapping (`!`). Use `if let`, `guard let`, or `??`
- **Indentation:** 4 spaces
- **Comments:** Only add comments where the logic is not self-evident
- **No Combine:** Use Swift async/await for async work
- **No UIKit:** Keep everything in SwiftUI

---

## File & Folder Conventions

```
booklist/
├── Models/          # SwiftData @Model classes
├── Views/           # SwiftUI views, broken into subfolders by feature
├── ViewModels/      # ViewModels (only when views need non-trivial logic)
├── Services/        # Any shared services (e.g. URL metadata fetching)
└── Resources/       # Assets, colors, etc.
```

Create folders as features are added — don't pre-create empty ones.

---

## Working Agreement

### For Claude:
- Always read the relevant files before suggesting changes
- Limit changes to what was explicitly asked — no unsolicited refactors
- When adding a feature, implement the simplest version that works first
- Prefer editing existing files over creating new ones
- Before any architectural decision, explain the trade-offs briefly
- If something is unclear or ambiguous, ask before building
- Do not add error handling for impossible scenarios
- Do not add abstractions for one-off use cases
- Answer, then verify and correct yourself before finalizing

### For Ivan (the developer):
- Provide requirements as a list before we start each feature
- Share reference screenshots or example apps when available
- Confirm architectural direction before implementation begins
- Ask questions freely — this is your first Swift project
- Ask Codex to review Claude's output

---

## Development Workflow

1. Ivan describes a feature or shares requirements/examples
2. We discuss the approach (data model, UI structure, interactions)
3. Claude implements in small, reviewable steps
4. Build and verify with Xcode tools (`BuildProject`, `XcodeRefreshCodeIssuesInFile`)
5. **Run the full test suite (`RunAllTests`) after every change — no exceptions**
   - All 149 tests must stay green before the session ends
   - If a change breaks a test, fix it before moving on
6. Iterate until the feature feels right
7. Claude to update the documentation with the new requirements and/or descriptions
8. Codex will review Claude's output once it's done

---

## Releasing a beta

A new beta must never lose a tester's library. Beta 1.2 (3) did (the App Group entitlement was
removed, so SwiftData opened a new, empty store) — these steps exist so it can't happen again.

1. **Never change without a rehearsal:** bundle ID, signing team, entitlements/capabilities, or
   the data models (`Bookmark`, `Folder`, `Tag`). No capability that needs a provisioning profile
   (App Groups, iCloud, Push, Associated Domains…) while betas use the free account.
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` on **all** targets.
3. `RunAllTests` — `ReleaseSafetyTests` must pass: store location, entitlements, and opening the
   library fixtures of earlier releases (`LibraryFixture_*`).
4. Archive (Release) + export (`mac-application`), see the beta-distribution notes.
5. `scripts/check-beta.sh <new booklist.app> <previous booklist.app>` — must say **OK to send**.
6. **Rehearse the upgrade** whenever step 5 reports a change, or the data models changed:
   install the *previous* beta in /Applications, open it and note the bookmark count, quit;
   install the new one, open it — same count, same folders, images present. Backups
   (File › Restore from Backup…) are the safety net while rehearsing.
7. If the data models changed: add a new `LibraryFixture_<version>` (generated from the new
   models) and a test that opens it. Never regenerate an existing fixture.
8. Tester message: install steps + remind them to set up the backup folder (the app asks once).

---

## Current State

_Last updated: 2026-04-28_

Core app is functional. All foundation phases are complete.

### Features implemented
- **Models:** `Bookmark`, `Folder`, `Tag` — all SwiftData `@Model` classes
- **Navigation:** `NavigationSplitView` with Inbox / All / Folder sidebar, `SidebarSelection` enum
- **Views - Sidebar:** `SidebarView`, `FolderRowView` (context menu: rename, delete, share), `FolderFormView`
- **Views — Content:** `ContentAreaView` (toolbar, search, tag filter bar), `BookmarkCardView`, `MasonryView`, `GridView`, `BookmarkListView` (Table), `TagFilterBar`
- **Views — Manage:** `ManagePanelView` (floating edit sheet: tags checkbox picker, folder picker, wishlist toggle)
- **Views — Capture:** `CaptureView` (URL paste + metadata auto-fetch), `ImagePickerGrid`
- **Views — Import:** `ImportView` (Netscape HTML + booklist HTML round-trip import, per-item review form)
- **Views — Reader:** `ReaderView` (WKWebView reader mode via `ReaderService`)
- **Views — Settings:** `AppSettingsView` (General: dock/menu bar/launch-at-login, Display: card toggles, Sync: JSON folder sync)
- **Views — Shared:** `Color+Hex`, `IconPickerView` (SF Symbol + color picker), `ImageUploadZone`, `TagPickerField`, `CaptureRouter`, `BookmarkTransfer`
- **Services:** `MetadataFetcher` (OG/meta tags, Safari UA), `ExportService` (HTML + embedded `__BOOKLIST_DATA__` JSON), `ImportService` (Netscape + booklist round-trip), `SyncService` (JSON snapshot/restore with security-scoped bookmarks), `ReaderService`, `ImageStore`
- **Share Extension:** `booklist share.appex` — macOS Share Sheet target, sends URLs into CaptureView
- **Share Sheet output:** `BookmarksExport: Transferable` — selection-aware `ShareLink` in toolbar, card context menus, list context menu, and sidebar folder context menu
- **Sync:** folder-based JSON sync (free alternative to iCloud), auto-export on quit, auto-import on launch
- **Menu bar + dock:** `NSStatusItem` menu bar icon, dynamic activation policy fix (Cmd+Tab works in accessory mode)
- **Sample data:** `SampleData.swift` — 12 bookmarks, 5 tags, 6 folders (DEBUG only, skipped when sync is enabled)

---

## Key Decisions Log

| Date       | Decision                                                              | Reason                                                        |
|------------|-----------------------------------------------------------------------|---------------------------------------------------------------|
| 2026-04-19 | SwiftData for persistence                                             | Modern, native, already in template                           |
| 2026-04-19 | macOS-only target                                                     | User's stated requirement                                     |
| 2026-04-19 | No Combine — async/await only                                         | Simpler, modern Swift                                         |
| 2026-04-19 | MVVM architecture                                                     | Clean separation for a first project                          |
| 2026-04-28 | Custom folder colors + icons via `IconPickerView` (SF Symbol + color) | O3 requirement; self-contained picker component               |
| 2026-04-28 | Menu bar icon (`NSStatusItem`) + dynamic activation policy            | P4 requirement; fix: app unreachable via Cmd+Tab in accessory mode |
| 2026-04-28 | Reader mode via `WKWebView` in `ReaderService`                        | I6 requirement; simpler than custom parser                    |
| 2026-04-28 | Share Extension target (`booklist share.appex`)                       | C2 requirement; separate app extension for macOS Share Sheet  |
| 2026-04-28 | Export to HTML with embedded `__BOOKLIST_DATA__` JSON                 | P6 + lossless round-trip re-import without a custom format    |
| 2026-04-28 | Folder-based JSON sync (security-scoped bookmark) instead of iCloud   | iCloud/CloudKit requires paid developer account ($99/yr); free alternative |
| 2026-04-28 | `BookmarksExport: Transferable` with eager snapshot of SwiftData models | Required to avoid SwiftData thread-safety issues in `ShareLink` |
| 2026-04-28 | All bookmark filtering done in-memory (no SwiftData predicates)        | Personal-scale data; avoids predicate complexity              |
| 2026-10-19 | Card/picker images loaded via `ImageStore.thumbnail` (ImageIO downsampling + NSCache), not `AsyncImage` | Full-resolution decoding of every card used hundreds of MB |
| 2026-10-19 | Cards release decoded images when scrolled off-screen (`onScrollVisibilityChange`), keeping aspect ratio | Masonry isn't lazy; memory must not scale with library size |
| 2026-10-19 | Saved images capped at 1600px, written via `CGImageDestination` (no `tiffRepresentation`) | Avoids huge uncompressed copies on save |
| 2026-10-19 | `MetadataFetcher` is `nonisolated` + `@concurrent` | Project defaults to MainActor; HTML regex parsing froze the UI during capture |
| 2026-10-19 | Undo (⌘Z) instead of delete confirmations; window `undoManager` bound to `mainContext` in `ContentView` | Confirmations on every delete add friction; app passes its own container so `isUndoEnabled:` modifier isn't available |
| 2026-10-19 | `BookmarkBulkActions` + `BookmarkOrganizeMenu` shared by card and list context menus | Bulk move/tag/delete for Inbox triage; one implementation keeps both view modes identical |
| 2026-10-19 | Wishlist sidebar item stays an "unfiled wishlist inbox" (collection == nil) | Ivan's decision — revisit later |
| 2026-10-19 | "Unfiled" dot only shown in All view, accent colour, with tooltips | Red dot on every Inbox/Wishlist card was redundant and anxiety-inducing |
| 2026-10-19 | File › New Window replaced by File › Save Link… | AppDelegate tracks a single main window; extra windows broke menu-bar show/hide |
| 2026-10-19 | `KeyboardShortcuts` SPM package (sindresorhus) for the global capture hotkey — first third-party dependency | User-recordable shortcut; works in the sandbox without Accessibility permission. Carbon API alternative rejected (more code, presets only) |
| 2026-10-19 | `AppDelegate.bringUpMainWindow` + `openMainWindow` hook (set by MenuBarIcon / menu items) | `openWindow` is view-only; lets the hotkey recreate a window closed in dock mode |
| 2026-10-19 | Single native toolbar: `.searchable` search field, view picker, View Options menu (sort + card size), share, +. Import → File menu (⇧⌘I); gear removed | One bar instead of two; native search; more room for cards. `.searchable` logs a one-time AppKit "layoutSubtreeIfNeeded" WarnOnce at launch — framework-internal, verified by bisecting |
| 2026-10-19 | Card size as named presets (`CardSize`: Small/Medium/Large/Extra Large) in toolbar menu + View menu (⌘= / ⌘−); slider stays in Settings | The slider already snapped to 5 column counts; names are clearer. "=" not "+" because "+" needs Shift |
| 2026-10-19 | Per-item view mode stored as a UserDefaults map (`ViewModeMemory`, keyed by `SidebarSelection.storageKey`) rather than a `Folder` field | No schema/sync change; also covers Inbox/Wishlist/All. Trade-off: local to each Mac |
| 2026-10-19 | `ImageStore` rejects non-2xx responses before decoding and remembers failed remote URLs for the session | A dead image link (404 HTML page) was re-downloaded every time its card scrolled on screen, logging ImageIO decode errors |
| 2026-10-19 | Plain value types used by tests (`SidebarSelection`, `ViewMode`, `CardSize`, `ViewModeMemory`) are `nonisolated` | Target defaults to MainActor; otherwise their Equatable conformances are main-actor-only (Swift 6 error in tests) |
| 2026-10-19 | Capture "Save" bound to ⌘Return (was Return) | Plain Return must insert a newline in the multi-line note field |
| 2026-10-19 | Reader panel guarded by `Bookmark.isAlive` + closes when its bookmark disappears from the query | Deleting the open bookmark via hover/context menu left the reader on a deleted model (crash risk) |
| 2026-10-19 | Prices normalised via `PriceFormatter` to preferred symbol + amount ("€18"); page currency text is dropped | User feedback: "18 EUR" / "18 €" from shop pages ignored the € default. No conversion — a foreign-currency page gets the preferred symbol |
| 2026-10-19 | Folder drag & drop in the sidebar (`FolderTransfer`, UTType exported in Info.plist); "Library" header = make top-level; move rules in `FolderTree.canMove/move` | Feedback: "Move into…" listed bare names, same-named subfolders were indistinguishable. Menu now shows full paths too |
| 2026-10-19 | Discoverable multi-select: hover checkmark on cards, floating selection bar (2+ selected), ⌘A via `onCommand(selectAll:)` | Feedback: multi-select existed (⌘/⇧-click) but testers never found it |
| 2026-10-19 | Notes use `NoteEditor` (TextEditor + placeholder), not `TextField(axis: .vertical)` | On macOS, Return in a TextField commits and selects all instead of inserting a newline |
| 2026-10-19 | Card selection checkmark at the thumbnail's bottom-left; hover actions top-centre via `ViewThatFits` (full → compact → 2×2) | Top-right actions were off-centre and overflowed narrow cards onto the checkmark |
| 2026-10-19 | Icon picker uses the full SF Symbols + emoji catalogue from `Resources/IconCatalog.json`, generated by `scripts/generate_icon_catalog.py` (system CoreGlyphs data + Unicode emoji-test.txt). **Re-run the script after a macOS/Xcode update or a deployment-target change** | Hand-typed lists had ~700 symbols / ~300 emoji and drifted from Apple's names (e.g. `doc` → `document`). Generated data: ~6,900 symbols in Apple's categories with keywords + aliases, ~1,900 emoji searchable by name |
| 2026-10-19 | Icon picker shows one symbol category at a time (category chips, Suggested default) — never the full catalogue in one scroll | macOS caches every drawn SF Symbol (~85 KB each, no purge API): browsing all ~6,900 took the app from 77 MB to ~560 MB. Emoji are cheap (~22 MB for all) and stay in one scroll |
| 2026-10-19 | Sidebar folders: one drag for reorder + nest via `FolderDropDelegate` — top quarter of a row = above, middle = inside, bottom quarter = below (line/outline indicator). `onMove` removed | `onMove` stops receiving drags once rows are draggable. DropDelegate is used because it reports the pointer position; the dragged folder is tracked in `FolderDrag.draggedID` (in-app only). Rows drag via `.itemProvider` applied at row level (after `.tag`, List-native drag), **not** `.onDrag`/`.draggable` on the label — those gesture-based drags stopped starting after one drag (reproduced in `booklistUITests/FolderDragUITests`). The model change is applied ~80 ms after the drop so the source row isn't rebuilt mid-drag |
| 2026-10-20 | Reddit posts: JSON API → oEmbed (`reddit.com/oembed`) → HTML. oEmbed gives title + author; subreddit is taken from the URL; images come from the embed page (`embed.reddit.com/<same path>`, `*.redd.it` `<img>` sources only). Capture keeps a post's own image selected; the generated Reddit card is only auto-selected when there are no images | Reddit now returns 403 for `.json` and a JS bot-check page titled just "Reddit" for HTML; oEmbed and the embed page still answer without a challenge (no selftext) |
| 2026-10-20 | Amazon links (any `amazon.<tld>` storefront, also after short-link redirects) default to wishlist in capture (`PageMetadata.isProductPage`). Price from the buy-box `a-offscreen` span → `displayPrice` JSON → first `a-price`; main photo from `#landingImage`/`#imgBlkFront` `data-old-hires`; `/images/G/` UI graphics skipped | Amazon has no og:image or structured price data, so generic extraction found no price and offered nav sprites as images. Toggle is set before fetching so it applies even if Amazon serves a captcha |
| 2026-10-20 | JSON-LD price search walks the whole tree (ProductGroup.hasVariant, BuyAction.object, @graph…) and accepts AggregateOffer `lowPrice`; the visible-text fallback skips add-on/shipping/instalment elements and any "…/month" rate | Tested 22 real US/EU product pages: Zalando and MediaMarkt prices were nested and missed, Fnac returned a warranty's "0,89 €/mois", PcComponentes returned a recommended product's price |
| 2026-10-20 | Wishlist default extended to any product page: `isProductPage` = Amazon, or a price was found, or the page declares a product (`og:type` containing "product", JSON-LD `Product`/`ProductGroup`) | Ivan's decision. Real-page check: all 16 reachable shop pages flagged; 9 non-shop pages (news, Wikipedia, GitHub, YouTube, recipe, a headphone review) not flagged. Risk: review pages whose JSON-LD embeds a `Product` |
| 2026-10-20 | Sites are "learned": capture's wishlist default for a host (`WishlistSites`, host minus `www.`/`m.`) follows the **newest** item saved from it, decided before fetching; product-page detection can still switch it on. Once the user flips the toggle (`wishlistChosenByUser`), no automatic default overrides it — including a fetch finishing later; otherwise the default is recomputed per URL | Ivan's request — covers shops the page detection misses, while keeping user agency: saving a shop's blog post as a bookmark turns that site's default back off. Derived from the library, not a stored list: syncs/imports for free. Exact host so www.apple.com (store) ≠ developer.apple.com (docs); trade-off: en.zalando.de ≠ www.zalando.de |
| 2026-10-20 | Masonry = lazy columns + batches: one `LazyVStack` per column, cards placed shortest-column-first from **estimated** heights (`MasonryEstimate`: image aspect read from the file header via `ImageStore.aspectRatio(ofLocalImage:)`, text lines from font sizes); columns hold `batchSize` (150) cards and grow when scrolled within 2 screens of the bottom. Arrow keys navigate on the estimated frames | Stress test: the old all-cards-up-front `Layout` reached 1.5 GB within seconds at 3,000 items and grew with library size. Now 159 MB at rest with 3,000 items. Ivan chose the mix (lazy alone = unbounded placement work; batches alone = memory still grows) |
| 2026-10-20 | Bulk move/tag change relationships from the folder/tag side in one batch (`BookmarkBulkActions`) | Per-bookmark assignment updates the inverse array each time — quadratic: 5,000 items took ~9 s each for move and tag, now ~0.4 s / ~0.05 s |
| 2026-10-20 | `StorageCleanup` at launch (skipped with `-uiTesting`): deletes `CFNetworkDownload_*.tmp` leftovers and saved images no bookmark references, both only if older than 24 h | A real install had 705 MB of download temp files left by older builds and 40% of saved images orphaned (deleted bookmarks, unchosen capture candidates). The grace period protects captures/imports in progress |
| 2026-10-20 | Stress tooling: `StressTests` (5,000-item data layer) in the normal suite; `StressUITests` + `StressData` (`-uiTesting -stressItems N`, DEBUG only, images in tmp) opt-in. UI-test timings in List view are an XCUITest artifact (its accessibility snapshot builds every table row) — measure real performance by launching the app directly and using `footprint` | Repeatable heavy-usage checks without touching the user's library |
| 2026-10-22 | Removed the unused App Groups entitlement (`group.lepi.booklist`) from the app and the share extension. **Don't add capabilities that need a provisioning profile** (App Groups, iCloud, Push, Associated Domains…) while betas are signed with the free account | Beta 1.2 (2) was killed on a tester's Mac at launch ("Code Signature Invalid / Taskgated"): `group.`-prefixed app groups need a profile, and free-account profiles only list the developer's own Mac. Nothing used the group — the share extension hands links over via the `booklist://` URL scheme. Without it no profile is embedded and the build runs on other Macs after "Open Anyway" |
| 2026-10-22 | Store pinned to the app container (`ModelConfiguration(groupContainer: .none)`); **File › Recover Library from Earlier Beta…** (`LibraryRecovery`) merges the old App-Group store into the current library; `StorageCleanup` refuses to delete images when the library is empty or most images look orphaned | With an App Group entitlement SwiftData silently stores the library in the group container — every beta ≤ 1.2 (2) did. Removing the entitlement made 1.2 (3) open an empty store (testers "lost" everything), and the launch cleanup then deleted all saved images as orphans. The sandbox only reaches the old folder through an open panel; the store is copied and read from the copy, merged by ID (tags also by name), and missing local images fall back to the page's web image |
| 2026-10-22 | Three layers so an update can't lose the library: (1) `BackupService` — automatic local backups (launch, at most every 20 h, and on quit; newest 7; never of an empty library; one before every sync import) + File › Restore from Backup…; (2) `BackupFolderPrompt` — once per version until set up, asks for a sync folder outside the app (offers to merge a backup already in it); sync export refuses to replace a non-empty snapshot with an empty library; (3) release process — `ReleaseSafetyTests` (store location, entitlements, `LibraryFixture_1_2` opens), `scripts/check-beta.sh`, "Releasing a beta" checklist | Ivan: losing data on a beta update is unacceptable. Local backups cover a moved/empty store; only a folder outside the container survives macOS replacing the container (the tester's case); the checks catch the cause before a build ships — check-beta.sh flags exactly the 1.2 (3) entitlement change |
| 2026-10-23 | Large-library performance, measured on a copy of a tester's 1,027-item library with `ProfileDriver` (DEBUG, `-uiTesting -profileLibrary -profileDriver`): (1) `ManagePanelView` edits a `Draft` (title, URL, note, price, thumbnail), saved 0.6 s after the last change and on close — typing 138 → 2–4 ms per character (274 → 2 ms after scrolling); (2) one library `@Query` in `ContentView`, passed to the sidebar and content area, **without a sort descriptor** (with unsaved changes SwiftData sorts in memory via slow key paths) — `filteredAndSorted` sorts with precomputed keys; (3) `ContentAreaView` memoizes the filtered list (`DisplayMemo`, invalidated by a new query array, selection, search, tags, sort) and filters by `appliedSearch` (0.15 s after typing) — search typing 57–135 → 16 ms per character; (4) `BookmarksExport` stores IDs and builds the export when shared | Tester: app "almost unusable", CPU 100 %, 46 s hang (spindump: main thread in lazy-stack view-list updates). Every bookmark write re-ran the whole window per keystroke. Remaining: each real change (save, tag, move, open link) still re-fetches the library (~140–220 ms on an M2) — replacing `@Query` with a self-maintained list was judged too risky (views reading deleted models) for now |
| 2026-10-23 | Amazon images = the product gallery only: `colorImages.initial` from the image block (`hiRes`, else `large`), in Amazon's order; `#landingImage` only as a fallback. No other `<img>` from Amazon pages | Ivan: the picker showed logos, Prime badges, "From the manufacturer" banners (`/images/S/aplus-media…`, `al-eu…`) and 40–100 px thumbnails. Checked on amazon.es/.com/.de/.co.uk: 7–20 full-size photos each. Seller-uploaded promo graphics that are part of the gallery itself (e.g. an Audible offer) still appear, at the end |
| 2026-10-23 | `AmazonImageRepair` at launch (once per `amazonImageRepairVersion`, after a backup): Amazon bookmarks keep only their product photos, at full size (main photo `_ML2_`/`_SX300_`, gallery thumbnails `_US40_`/`_US100_`/`_SR38,50_`, size suffix dropped), and a junk card image becomes the main photo. Offline, from the saved candidates — no re-fetching of hundreds of Amazon pages. A local image or any other `/images/I/` photo the user picked is kept | Ivan's library: 295 of 349 Amazon items showed the nav sprite or a banner (recovery's fallback used the first web candidate, which was junk). Bump `version` when a new page layout is found; repaired bookmarks only hold full-size URLs, so a rerun leaves them alone |
| 2026-10-20 | UI test target `booklistUITests`, opt-in via `touch /tmp/booklist-run-ui-tests`; app launched with `-uiTesting` (in-memory store, sync off, window opened on launch) | UI tests drive the real mouse, so routine runs skip them; `-uiTesting` keeps the user's library and sync file untouched |
| 2026-10-19 | Settings consolidated to 4 tabs: General (incl. currency), Display (cards + list columns), Tags, Sync | Fewer tabs = less hunting |
