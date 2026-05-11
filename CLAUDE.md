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

### For Ivan (the developer):
- Provide requirements as a list before we start each feature
- Share reference screenshots or example apps when available
- Confirm architectural direction before implementation begins
- Ask questions freely — this is your first Swift project

---

## Development Workflow

1. Ivan describes a feature or shares requirements/examples
2. We discuss the approach (data model, UI structure, interactions)
3. Claude implements in small, reviewable steps
4. Build and verify with Xcode tools (`BuildProject`, `XcodeRefreshCodeIssuesInFile`)
5. Iterate until the feature feels right

---

## Current State

- Xcode project bootstrapped with SwiftData template
- Placeholder `Item` model and `ContentView` — both will be replaced
- No real features implemented yet

---

## Key Decisions Log

| Date       | Decision                                      | Reason                              |
|------------|-----------------------------------------------|-------------------------------------|
| 2026-04-19 | SwiftData for persistence                     | Modern, native, already in template |
| 2026-04-19 | macOS-only target                             | User's stated requirement           |
| 2026-04-19 | No Combine — async/await only                 | Simpler, modern Swift               |
| 2026-04-19 | MVVM architecture                             | Clean separation for a first project |
