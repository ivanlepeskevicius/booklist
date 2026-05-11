# Product Requirements — booklist

_Last updated: 2026-04-19 — capture flow clarified; nesting corrected; milestones updated_

---

## Product Vision

A native macOS app that replaces the chaos of open browser tabs and messy bookmark folders.
The target user has ADHD and gets overwhelmed by disorganized digital information. The app should feel calm, fast, and rewarding to use — not like another tool to maintain.

**Core promise:** Save anything in seconds. Find it immediately. Always know why you saved it.

---

## Reference Apps — Key Takeaways

| App | What to borrow |
|---|---|
| **Resurf** | Floating capture widget, local-first, reader mode, Inbox+Areas+Tags structure |
| **DoubleMemory** | Translucent/visual aesthetic, Pinterest mood board, ⌘C×2 quick capture, rich metadata cards |
| **Anybox** | Native macOS feel, Spotlight-like search, nested tags+folders, floating Anydock bar |
| **Raindrop** | Multiple view modes (masonry included), clean tag management |
| **Moonsift** | Wishlist mode: minimal card with product image + price + link only |
| **Couch** | Notes visible per item (but app is too slow — be faster) |

---

## Requirements

### 1. Capture & Input

| ID | Requirement | Priority |
|----|-------------|----------|
| C1 | Global keyboard shortcut to open a quick-capture overlay from anywhere (active app, browser, anywhere on macOS) | Must |
| C2 | macOS Share Sheet integration so any app can send links/images directly to booklist | Must |
| C3 | Paste a URL → immediately auto-fetch metadata (title, description, candidate images, favicon) → show a review modal so the user can edit before saving | Must |
| C4 | Drag & drop a URL, image, or file from any app into booklist | Should |
| C5 | Browser extension (Arc/Chrome later) to save current tab with one click | Should |
| C6 | Capture note/text alongside URL at save time — without opening a new screen | Must |
| C7 | Assign tags and collection during capture — without leaving the capture widget | Should |
| C8 | During capture, show all images found on the page and let the user pick which one to use as the card thumbnail | Must |

---

### 2. Organization & Structure

| ID | Requirement | Priority |
|----|-------------|----------|
| O1 | Collections (folders) can be nested to unlimited depth — user decides their own hierarchy | Must |
| O2 | Tags: flat, fast-to-assign, multiple per item | Must |
| O3 | Each collection gets a custom color and icon (emoji or SF Symbol) | Must |
| O4 | Each tag gets a custom color | Should |
| O5 | Inbox: all new saves land here until manually organized | Must |
| O6 | Smart Collections: auto-populate based on rules (e.g., "tagged #design", "saved this week") | Could |
| O7 | Move items between collections via drag & drop | Must |

---

### 3. Item Cards & Content

| ID | Requirement | Priority |
|----|-------------|----------|
| I1 | Each item displays: thumbnail, title, domain, and a note snippet — all visible without opening the item | Must |
| I2 | Note is always visible on the card (even just the first line). User should immediately know *why* they saved it | Must |
| I3 | Auto-fetched thumbnail can be replaced with a custom image | Must |
| I4 | Thumbnail size is adjustable per view (small / medium / large) | Should |
| I5 | Support saving images directly (not just URLs) | Should |
| I6 | Built-in reader view: open links in a distraction-free reader inside the app | Should |
| I7 | Built-in lightweight browser: open full page inside the app without switching to Safari | Could |
| I8 | Mark items as read/unread | Should |
| I9 | Star/pin items to top of their collection | Must |

---

### 4. Wishlist Mode

_Inspired by Moonsift — a distinct, simplified mode for products you want to buy._

| ID | Requirement | Priority |
|----|-------------|----------|
| W1 | Dedicated "Wishlist" collection type with a different card layout: large product image, price, retailer name, and a small link | Must |
| W2 | Manually add price when saving a product | Must |
| W3 | Price tracking: detect if the saved page price has changed and alert the user | Could |
| W4 | Group wishlist items by occasion/category (e.g., "Birthday", "Home") | Should |
| W5 | Wishlist cards do not show notes to reduce clutter | Must |

---

### 5. Visual Design & Layouts

| ID | Requirement | Priority |
|----|-------------|----------|
| V1 | Multiple view modes per collection: **List**, **Grid**, **Masonry (Pinterest-style)** | Must |
| V2 | Masonry view arranges cards in variable-height columns, respecting image proportions | Must |
| V3 | View mode is saved per collection | Should |
| V4 | Beautiful, native macOS aesthetic — follows Apple Human Interface Guidelines | Must |
| V5 | Custom accent color per collection influences card headers and tags | Should |
| V6 | Light and dark mode support | Must |
| V7 | Adjustable font size in reader mode | Should |
| V8 | Translucent/vibrancy effects in sidebars and panels where appropriate | Could |

---

### 6. Search & Retrieval

| ID | Requirement | Priority |
|----|-------------|----------|
| S1 | Global search across all items: title, URL, notes, tags | Must |
| S2 | Instant results as you type (no submit needed) | Must |
| S3 | Filter search by: collection, tag, date range, item type | Should |
| S4 | Spotlight integration: find booklist items from macOS Spotlight | Could |
| S5 | Recently viewed / recently saved quick-access panel | Should |

---

### 7. Platform & System Integration

| ID | Requirement | Priority |
|----|-------------|----------|
| P1 | All data stored locally on-device — no mandatory cloud account | Must |
| P2 | iCloud sync (optional, opt-in) to sync across user's own devices | Should |
| P3 | Launch at login option | Must |
| P4 | Menu bar icon for fast access without opening the full window | Should |
| P5 | iOS companion app (save from iOS Share Sheet, browse collections) | Could |
| P6 | Export: JSON, CSV, or HTML for portability | Should |
| P7 | Import from Raindrop, browser bookmarks (HTML), Safari Reading List | Could |

---

### 8. UX Principles (Non-Negotiable)

These are not features — they are constraints that apply to every decision:

1. **3-click rule:** Any core action (save, find, open) must be reachable in 3 interactions or fewer.
2. **Notes at a glance:** Notes must be visible without opening an item. The user should never need to open something just to remember why they saved it.
3. **No blank states without guidance:** Empty collections, first launch, and zero search results should offer helpful, calm next steps.
4. **Keyboard-first:** Every common action should have a keyboard shortcut.
5. **Native feel:** No web wrappers, no Electron-style UI. Should feel like it was made by Apple.

---

## Out of Scope (for now)

- Collaboration / sharing collections with other users
- AI-powered summaries or auto-tagging (could revisit)
- Web clipper for full-page saving (clutter risk)
- Built-in todo list (may add later — keep focus)
- Windows / Android versions

---

## Milestones (Rough)

| Phase | Status | Focus |
|---|---|---|
| **Phase 1 — Foundation** | ✅ Done | Data models (Bookmark, Folder, Tag), full UI skeleton (sidebar, masonry/grid/list, manage panel) |
| **Phase 2 — Capture** | 🔄 In progress | URL paste → metadata fetch → review modal with image picker; sample data |
| **Phase 3 — Folders & Tags** | Pending | Add/edit/delete folders and tags from the UI; drag & drop to move items |
| **Phase 4 — Polish** | Pending | Custom folder colors/icons, reader mode, launch at login, menu bar icon |
| **Phase 5 — Wishlist** | Pending | Wishlist card layout, price field, price tracking |
| **Phase 6 — Sync & Mobile** | Pending | iCloud sync, iOS companion app |
