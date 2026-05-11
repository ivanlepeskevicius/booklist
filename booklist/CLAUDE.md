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
