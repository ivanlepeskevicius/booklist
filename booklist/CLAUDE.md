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
| 2026-10-19 | Settings consolidated to 4 tabs: General (incl. currency), Display (cards + list columns), Tags, Sync | Fewer tabs = less hunting |
