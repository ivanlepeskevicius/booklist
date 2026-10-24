#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import AppKit

/// DEBUG-only performance driver for reproducing a tester's slowdowns on a copy of their library:
/// `-uiTesting -profileLibrary -profileDriver`. It switches views, opens the edit panel, "types" into
/// the note and switches the thumbnail, and logs how long the main thread was blocked for each step
/// (`log show --predicate 'eventMessage CONTAINS "PROFILE"'`). No XCUITest involved, so the numbers
/// are the app's own.
enum ProfileDriver {
    static let selectNotification = Notification.Name("ProfileDriver.select")
    static let manageNotification = Notification.Name("ProfileDriver.manage")
    static let selectCardsNotification = Notification.Name("ProfileDriver.selectCards")

    static var isEnabled: Bool { LaunchMode.isUITesting && ProcessInfo.processInfo.arguments.contains("-profileDriver") }

    /// The tester's store bundled into the debug app (`Contents/Resources/Profiling/default.store`),
    /// copied to tmp so the bundle is never written to.
    static var libraryCopyURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(ProcessInfo.processInfo.processIdentifier).store")
        // `-profileRealLibrary`: a copy of this Mac's own library (store + its WAL files), so the
        // real one is never written to. Images are the real ones (read only).
        if arguments.contains("-profileRealLibrary") {
            let real = booklistApp.storeConfiguration(inMemory: false).url
            if !FileManager.default.fileExists(atPath: copy.path) {
                for suffix in ["", "-wal", "-shm"] {
                    let source = URL(fileURLWithPath: real.path + suffix)
                    guard FileManager.default.fileExists(atPath: source.path) else { continue }
                    try? FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
                }
            }
            return copy
        }
        guard arguments.contains("-profileLibrary"),
              let bundled = Bundle.main.url(forResource: "default", withExtension: "store", subdirectory: "Profiling")
        else { return nil }
        if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: bundled, to: copy) }
        return copy
    }

    /// Called before any image is requested. `-profileNoImageCache`: every web image is downloaded
    /// again, like the first launch after an update that changed many card images.
    static func prepare() {
        guard LaunchMode.isUITesting, ProcessInfo.processInfo.arguments.contains("-profileNoImageCache") else { return }
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)
    }

    @MainActor
    static func run(context: ModelContext) async {
        guard isEnabled else { return }
        let bookmarks = (try? context.fetch(FetchDescriptor<Bookmark>())) ?? []
        log("start: \(bookmarks.count) bookmarks")

        // `-profileScrollFirst`: what the tester did — scroll down at trackpad speed right after
        // launch, while the card images are still arriving.
        if ProcessInfo.processInfo.arguments.contains("-profileScrollFirst") {
            try? await Task.sleep(for: .seconds(2))
            for (name, selection) in [("Wishlist", SidebarSelection.wishlist), ("All", .all)] {
                NotificationCenter.default.post(name: selectNotification, object: selection)
                try? await Task.sleep(for: .seconds(1))
                log("slow scroll \(name): \(summary(await scrollDown(steps: 120, by: 120, pause: .milliseconds(60))))")
            }
        }
        // `-profileScrollOnly N`: only the scrolling, N rounds — the freezes were intermittent,
        // so one clean pass proves little.
        let scrollRounds = UserDefaults.standard.integer(forKey: "profileScrollOnly")
        if scrollRounds > 0 {
            Task {   // DIAGNOSTIC — remove
                while true {
                    try? await Task.sleep(for: .seconds(2))
                    log("counters: masonry body \(MasonryView.bodyCount), band changes \(MasonryView.bandChanges), width changes \(MasonryView.widthChanges)")
                }
            }
            NotificationCenter.default.post(name: selectNotification, object: SidebarSelection.all)
            try? await Task.sleep(for: .seconds(2))
            let savedViewMode = UserDefaults.standard.string(forKey: "viewMode")
            for round in 1...scrollRounds {
                for mode in [ViewMode.masonry, .list] {
                    UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
                    try? await Task.sleep(for: .seconds(1))
                    let down = await scrollToBottom()
                    let up = await scrollToTop()
                    log("round \(round) \(mode.rawValue): down \(summary(down)); up \(summary(up))")
                }
            }
            if let savedViewMode { UserDefaults.standard.set(savedViewMode, forKey: "viewMode") }
            else { UserDefaults.standard.removeObject(forKey: "viewMode") }
            return log("done")
        }

        try? await Task.sleep(for: .seconds(4))

        for (name, selection) in [("All", SidebarSelection.all), ("Wishlist", .wishlist), ("Inbox", .inbox), ("All", .all)] {
            let lag = await measure { NotificationCenter.default.post(name: selectNotification, object: selection) }
            log("switch to \(name): \(ms(lag))")
            try? await Task.sleep(for: .seconds(2))
        }

        // Selecting cards one after another (a click, or holding an arrow key).
        let visible = bookmarks.sorted { $0.dateAdded > $1.dateAdded }.prefix(25)
        var selecting: [Double] = []
        log("selecting cards…")
        for bookmark in Array(visible) + Array(visible) + Array(visible) + Array(visible) {
            selecting.append(await measure { NotificationCenter.default.post(name: selectCardsNotification, object: Set([bookmark.id])) })
        }
        NotificationCenter.default.post(name: selectCardsNotification, object: Set<UUID>())
        log("selecting a card \(selecting.count)×: \(summary(selecting))")

        // Typing a search, then clearing it.
        if let field = searchField() {
            field.window?.makeFirstResponder(field)
            try? await Task.sleep(for: .milliseconds(300))
            var searching: [Double] = []
            for character in "kitchen lamp" {
                searching.append(await measure {
                    (field.currentEditor() as? NSTextView)?.insertText(String(character), replacementRange: NSRange(location: field.stringValue.utf16.count, length: 0))
                })
            }
            log("typing a search \(searching.count) characters: \(summary(searching))")
            log("showing the search results (next 1 s): blocked \(ms(await blockedTime(over: 1)))")
            let clear = await measure {
                (field.currentEditor() as? NSTextView)?.selectAll(nil)
                (field.currentEditor() as? NSTextView)?.insertText("", replacementRange: NSRange(location: 0, length: field.stringValue.utf16.count))
            }
            log("clearing the search: \(ms(clear))")
            try? await Task.sleep(for: .seconds(1))
        } else {
            log("no search field")
        }

        // The edit panel on the item with the most candidate images, like a shop product.
        guard let target = bookmarks.filter({ $0.itemType == .wishlistItem }).max(by: { $0.imageURLs.count < $1.imageURLs.count })
        else { return log("no wishlist item") }
        let open = await measure { NotificationCenter.default.post(name: manageNotification, object: target.id) }
        log("open edit panel (\(target.imageURLs.count) candidate images): \(ms(open))")
        try? await Task.sleep(for: .seconds(3))
        var typing: [Double] = []
        for character in "The quick brown fox jumps over the lazy dog, twice over" {
            typing.append(await measure { type(character, fallback: target) })
        }
        log("typing \(typing.count) characters (\(noteTextView() == nil ? "model" : "text view")): \(summary(typing))")
        log("saving the typed note (next 1.5 s): blocked \(ms(await blockedTime(over: 1.5)))")

        var picking: [Double] = []
        for url in target.imageURLs.prefix(20) {
            picking.append(await measure { target.selectedImageURL = url })
            try? await Task.sleep(for: .milliseconds(300))
        }
        log("writing thumbnail straight to the bookmark \(picking.count)× (old path): \(summary(picking))")

        // Opening and closing the edit panel a few times.
        NSApp.keyWindow?.sheets.forEach { NSApp.keyWindow?.endSheet($0) }
        try? await Task.sleep(for: .seconds(1))
        var opening: [Double] = [], closing: [Double] = []
        for bookmark in visible.prefix(5) {
            opening.append(await measure { NotificationCenter.default.post(name: manageNotification, object: bookmark.id) })
            try? await Task.sleep(for: .seconds(1))
            closing.append(await measure { NSApp.windows.forEach { window in window.sheets.forEach { window.endSheet($0) } } })
            try? await Task.sleep(for: .milliseconds(500))
        }
        log("opening the edit panel 5×: \(summary(opening)); closing: \(summary(closing))")

        // Close the panel, then scroll All from top to bottom in masonry and in the list.
        NSApp.keyWindow?.sheets.forEach { NSApp.keyWindow?.endSheet($0) }
        NotificationCenter.default.post(name: selectNotification, object: SidebarSelection.all)
        try? await Task.sleep(for: .seconds(2))
        let savedViewMode = UserDefaults.standard.string(forKey: "viewMode")
        for mode in [ViewMode.masonry.rawValue, ViewMode.list.rawValue] {
            UserDefaults.standard.set(mode, forKey: "viewMode")
            try? await Task.sleep(for: .seconds(2))
            log("scroll \(mode): \(summary(await scrollToBottom()))")
        }
        // Typing again after scrolling masonry to the bottom (every card loaded into the layout).
        UserDefaults.standard.set(ViewMode.masonry.rawValue, forKey: "viewMode")
        try? await Task.sleep(for: .seconds(2))
        _ = await scrollToBottom()
        NotificationCenter.default.post(name: manageNotification, object: target.id)
        try? await Task.sleep(for: .seconds(2))
        var typingAfterScroll: [Double] = []
        for character in "after scrolling to the bottom" {
            typingAfterScroll.append(await measure { type(character, fallback: target) })
        }
        log("typing after scrolling \(typingAfterScroll.count) characters: \(summary(typingAfterScroll))")
        NSApp.windows.forEach { window in window.sheets.forEach { window.endSheet($0) } }
        try? await Task.sleep(for: .seconds(1))
        var selectingAfterScroll: [Double] = []
        for bookmark in visible {
            selectingAfterScroll.append(await measure { NotificationCenter.default.post(name: selectCardsNotification, object: Set([bookmark.id])) })
        }
        NotificationCenter.default.post(name: selectCardsNotification, object: Set<UUID>())
        log("selecting a card after scrolling \(selectingAfterScroll.count)×: \(summary(selectingAfterScroll))")

        // Soak (`-profileSoak N`): repeat the heavy steps to show memory levels off instead of growing.
        let rounds = UserDefaults.standard.integer(forKey: "profileSoak")
        for round in 0..<rounds {
            for selection in [SidebarSelection.wishlist, .inbox, .all] {
                NotificationCenter.default.post(name: selectNotification, object: selection)
                try? await Task.sleep(for: .seconds(1))
            }
            var lags: [Double] = []
            for mode in [ViewMode.masonry, .list] {
                UserDefaults.standard.set(mode.rawValue, forKey: "viewMode")
                try? await Task.sleep(for: .seconds(1))
                lags += await scrollToBottom()
            }
            for bookmark in visible.prefix(3) {
                NotificationCenter.default.post(name: manageNotification, object: bookmark.id)
                try? await Task.sleep(for: .seconds(1))
                NSApp.windows.forEach { window in window.sheets.forEach { window.endSheet($0) } }
                try? await Task.sleep(for: .milliseconds(500))
            }
            log("soak round \(round + 1)/\(rounds): scrolling \(summary(lags)), resident \(residentMB()) MB")
        }

        if let savedViewMode { UserDefaults.standard.set(savedViewMode, forKey: "viewMode") }
        else { UserDefaults.standard.removeObject(forKey: "viewMode") }
        log("done")
    }

    /// Scrolls back up in 600 pt steps until the top.
    @MainActor
    private static func scrollToTop() async -> [Double] {
        guard let content = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true })?.contentView,
              let scrollView = largestScrollView(in: content) else { return [] }
        var lags: [Double] = []
        while scrollView.contentView.bounds.origin.y > 0 && lags.count < 400 {
            let clip = scrollView.contentView
            lags.append(await measure {
                clip.scroll(to: NSPoint(x: 0, y: max(0, clip.bounds.origin.y - 600)))
                scrollView.reflectScrolledClipView(clip)
            })
        }
        return lags
    }

    /// Scrolls down `steps` times by `by` points with a pause in between; returns the lag of each step.
    @MainActor
    private static func scrollDown(steps: Int, by distance: CGFloat, pause: Duration) async -> [Double] {
        guard let content = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true })?.contentView,
              let scrollView = largestScrollView(in: content) else { log("no scroll view"); return [] }
        var lags: [Double] = []
        for _ in 0..<steps {
            let clip = scrollView.contentView
            let maxY = (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
            lags.append(await measure {
                clip.scroll(to: NSPoint(x: 0, y: min(maxY, clip.bounds.origin.y + distance)))
                scrollView.reflectScrolledClipView(clip)
            })
            try? await Task.sleep(for: pause)
        }
        return lags
    }

    /// Scrolls the main content scroll view down in 600 pt steps, like a fast trackpad scroll,
    /// until it stops growing (masonry loads more cards near the bottom).
    @MainActor
    private static func scrollToBottom() async -> [Double] {
        guard let content = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true })?.contentView,
              let scrollView = largestScrollView(in: content) else { log("no scroll view"); return [] }
        var lags: [Double] = []
        var stepsAtBottom = 0
        while stepsAtBottom < 5 && lags.count < 400 {
            let clip = scrollView.contentView
            let maxY = (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
            let nextY = min(maxY, clip.bounds.origin.y + 600)
            stepsAtBottom = nextY >= maxY - 1 ? stepsAtBottom + 1 : 0
            lags.append(await measure {
                clip.scroll(to: NSPoint(x: 0, y: nextY))
                scrollView.reflectScrolledClipView(clip)
            })
        }
        return lags
    }

    @MainActor
    private static func searchField() -> NSSearchField? {
        var found: NSSearchField?
        func visit(_ view: NSView) {
            if found == nil, let field = view as? NSSearchField { found = field }
            view.subviews.forEach(visit)
        }
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true {
            if let frame = window.contentView?.superview { visit(frame) }
        }
        return found
    }

    @MainActor
    private static func largestScrollView(in view: NSView) -> NSScrollView? {
        var best: NSScrollView?
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView,
               (scroll.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) { best = scroll }
            view.subviews.forEach(visit)
        }
        visit(view)
        return best
    }

    /// Types into the edit panel's note field the way the keyboard does (NSTextView.insertText),
    /// so the panel's own binding path is what's measured.
    @MainActor
    private static func type(_ character: Character, fallback bookmark: Bookmark) {
        if let textView = noteTextView() {
            textView.insertText(String(character), replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        } else {
            bookmark.note = (bookmark.note ?? "") + String(character)
        }
    }

    @MainActor
    private static func noteTextView() -> NSTextView? {
        for window in NSApp.windows {
            for sheet in window.sheets {
                var found: NSTextView?
                func visit(_ view: NSView) {
                    if found == nil, let text = view as? NSTextView, text.isEditable, text.enclosingScrollView != nil,
                       text.frame.height >= 40 { found = text }
                    view.subviews.forEach(visit)
                }
                if let content = sheet.contentView { visit(content) }
                if let found { return found }
            }
        }
        return nil
    }

    /// Runs `change`, then measures how much longer than the expected 20 ms the main thread took to
    /// come back — i.e. how long the app was unresponsive because of the change.
    @MainActor
    private static func measure(_ change: () -> Void) async -> Double {
        let start = ContinuousClock.now
        change()
        try? await Task.sleep(for: .milliseconds(20))
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return max(0, seconds - 0.020)
    }

    /// Total time the main thread was blocked over `seconds`, measured in 20 ms ticks.
    @MainActor
    private static func blockedTime(over seconds: Double) async -> Double {
        var blocked = 0.0
        for _ in 0..<Int(seconds / 0.02) { blocked += await measure {} }
        return blocked
    }

    private static func ms(_ seconds: Double) -> String { String(format: "%.0f ms", seconds * 1000) }

    /// Physical footprint, the number Activity Monitor shows as Memory.
    private static func residentMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    private static func summary(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return "-" }
        return "median \(ms(sorted[sorted.count / 2])), p90 \(ms(sorted[sorted.count * 9 / 10])), max \(ms(sorted.last ?? 0)), total \(ms(values.reduce(0, +)))"
    }

    private static func log(_ message: String) { NSLog("PROFILE %@", message) }
}
#endif
