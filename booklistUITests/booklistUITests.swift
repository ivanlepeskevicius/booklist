import AppKit
import XCTest

/// Launches the freshly built booklist.app from the build products folder with `-uiTesting`.
func launchBooklist(extraArguments: [String] = [], windowTimeout: TimeInterval = 10) -> XCUIApplication {
    var directory = Bundle(for: FolderDragUITests.self).bundleURL
    var appURL: URL?
    for _ in 0..<6 {
        directory.deleteLastPathComponent()
        let candidate = directory.appendingPathComponent("booklist.app")
        if FileManager.default.fileExists(atPath: candidate.path) {
            appURL = candidate
            break
        }
    }
    let app = appURL.map { XCUIApplication(url: $0) } ?? XCUIApplication(bundleIdentifier: "lepi.booklist")
    // Ignore restored window state: if the window was closed at the last quit, macOS would
    // otherwise relaunch with no window at all.
    // -showInDock YES (argument domain, this launch only): run as a regular app so the
    // window is shown — in menu-bar-only mode it can stay hidden under the test runner.
    app.launchArguments = ["-uiTesting", "-ApplePersistenceIgnoreState", "YES", "-showInDock", "YES"] + extraArguments
    app.launch()
    app.activate()
    if !app.windows.firstMatch.waitForExistence(timeout: 5) {
        // Fallback: open it from the menu bar icon, like a user would.
        app.statusItems.firstMatch.click()
        app.menuItems["Open booklist"].click()
    }
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: windowTimeout), "No booklist window\n\(app.debugDescription)")
    return app
}

/// Drags folders in the sidebar several times in a row — the bug was "first move works,
/// later ones don't". Runs the real app with `-uiTesting` (in-memory sample data, sync off),
/// so the user's library and sync file are never touched.
///
/// These tests take over the mouse, so they only run when explicitly requested:
/// `touch /tmp/booklist-run-ui-tests` before running, delete it afterwards. Otherwise they
/// are skipped, keeping routine full-suite runs hands-off.
final class FolderDragUITests: XCTestCase {

    private static let sampleFolders: Set<String> = ["Design", "Music", "Reading", "UI Components", "Typography", "Jazz"]
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/booklist-run-ui-tests"),
                          "UI tests drive the mouse; touch /tmp/booklist-run-ui-tests to run them.")
        continueAfterFailure = false
        app = launchBooklist()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    @MainActor
    func testRepeatedFolderMoves() throws {
        let sidebar = app.outlines.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10), app.debugDescription)
        waitForRootOrder(["Design", "Music", "Reading"])

        // 1. Reorder: Reading above Design.
        drag("Reading", to: "Design", zone: .above)
        waitForRootOrder(["Reading", "Design", "Music"])

        // 2. Reorder again: Design below Music.
        drag("Design", to: "Music", zone: .below)
        waitForRootOrder(["Reading", "Music", "Design"])

        // 3. Nest: Reading into Music (collapsed, so Reading disappears from view).
        drag("Reading", to: "Music", zone: .inside)
        waitForRootOrder(["Music", "Design"])

        // 4. Keep going after a nest: Design above Music.
        drag("Design", to: "Music", zone: .above)
        waitForRootOrder(["Design", "Music"])

        // 5–6. A few more, past the point where the old implementation gave up.
        drag("Music", to: "Design", zone: .above)
        waitForRootOrder(["Music", "Design"])
        drag("Music", to: "Design", zone: .below)
        waitForRootOrder(["Design", "Music"])
    }

    // MARK: - Helpers

    private enum Zone { case above, inside, below }

    /// Folder rows with subfolders expose their name as the label, leaf rows as the value.
    /// Found by position in the sidebar — predicate queries found the row but then failed to
    /// re-resolve it, while index-bound elements resolve reliably.
    private func folderText(_ name: String) -> XCUIElement? {
        let texts = app.outlines.firstMatch.staticTexts
        guard let index = texts.allElementsBoundByIndex.firstIndex(where: { displayedName($0) == name }) else { return nil }
        return texts.element(boundBy: index)
    }

    private func displayedName(_ element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    /// Drops at the top edge, centre or bottom edge of the target row's label — the drop
    /// zones are the top quarter / middle / bottom quarter of the row.
    private func drag(_ source: String, to target: String, zone: Zone) {
        guard let from = folderText(source) else {
            return XCTFail("\(source) not found in sidebar: \(visibleFolderOrder())")
        }
        guard let to = folderText(target) else {
            return XCTFail("\(target) not found in sidebar: \(visibleFolderOrder())")
        }
        // Offsets stay inside the label: the app's zones are measured on the label itself.
        let dy: CGFloat = switch zone {
        case .above:  0.08
        case .inside: 0.5
        case .below:  0.92
        }
        from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.4,
                   thenDragTo: to.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)))
    }

    /// Visible top-level-ish folder names in sidebar order (collapsed children aren't visible).
    /// Read from one snapshot: querying element by element fails if a row disappears mid-read
    /// (e.g. while the sidebar animates a move).
    private func visibleFolderOrder() -> [String] {
        guard let root = try? app.outlines.firstMatch.snapshot() else { return [] }
        var names: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText {
                let name = node.label.isEmpty ? (node.value as? String ?? "") : node.label
                if Self.sampleFolders.contains(name) { names.append(name) }
            }
            node.children.forEach(walk)
        }
        walk(root)
        return names
    }

    private func waitForRootOrder(_ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if visibleFolderOrder() == expected { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("Expected \(expected), got \(visibleFolderOrder())\n\(app.debugDescription)", file: file, line: line)
    }
}

/// Heavy-usage session on a large generated library (`-stressItems`): view switching,
/// scrolling, card sizes, search, select-all, bulk delete + undo, and opening capture —
/// repeated for several rounds. Checks the app stays alive and responsive throughout;
/// memory is sampled from outside the process while it runs.
///
/// Timings here are not user-facing timings: before every step XCUITest snapshots the whole
/// accessibility tree, which makes the List view's table create a row view for *every* row
/// (~80 s and +1.5 GB at 3,000 items, measured with `sample`). For real numbers, launch the
/// built app directly with `-uiTesting -stressItems N` and measure with `footprint`.
/// Opt-in like the other UI tests (`/tmp/booklist-run-ui-tests`).
final class StressUITests: XCTestCase {

    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/booklist-run-ui-tests"),
                          "UI tests drive the mouse; touch /tmp/booklist-run-ui-tests to run them.")
        continueAfterFailure = false
        let items = ProcessInfo.processInfo.environment["STRESS_ITEMS"] ?? "3000"
        // -captureShortcutKey t: argument domain, this launch only — ⌘T opens capture whatever
        // the user's own setting is.
        app = launchBooklist(extraArguments: ["-stressItems", items, "-captureShortcutKey", "t"], windowTimeout: 60)
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    @MainActor
    func testHeavyUsage() throws {
        XCTAssertTrue(app.outlines.firstMatch.waitForExistence(timeout: 60))
        let rounds = Int(ProcessInfo.processInfo.environment["STRESS_ROUNDS"] ?? "6") ?? 6

        for round in 0..<rounds {
            XCTContext.runActivity(named: "Round \(round)") { _ in
                // Big lists: All in masonry, then list, scrolled hard both ways.
                selectSidebar("All")
                app.typeKey("1", modifierFlags: .command)
                scrollContent(times: 8)
                app.typeKey("2", modifierFlags: .command)
                scrollContent(times: 8)
                app.typeKey("1", modifierFlags: .command)

                // Card sizes up and down (each change re-lays out every card).
                for _ in 0..<3 { app.typeKey("=", modifierFlags: .command) }
                scrollContent(times: 3)
                for _ in 0..<3 { app.typeKey("-", modifierFlags: .command) }

                // Jump between sidebar sections and nested folders.
                for name in ["Inbox", "Wishlist", "Folder \(round)", "Folder \(round).A", "Folder \(round).A.1", "Folder \(round + 1).B", "All"] {
                    selectSidebar(name)
                    scrollContent(times: 1)
                }

                // Search while typing, then clear.
                app.typeKey("f", modifierFlags: .command)
                app.typeText("lorem ips")
                app.typeKey("a", modifierFlags: .command)
                app.typeText("headphones")
                app.typeKey("a", modifierFlags: .command)
                app.typeKey(.delete, modifierFlags: [])
                app.typeKey(.escape, modifierFlags: [])

                // Select everything in a folder, bulk delete, undo.
                selectSidebar("Folder \(round + 2)")
                if let card = firstCardTitle() {
                    card.click()
                    app.typeKey("a", modifierFlags: .command)
                    app.typeKey(.delete, modifierFlags: .command)
                    app.typeKey("z", modifierFlags: .command)
                    app.typeKey(.escape, modifierFlags: [])
                }

                // Open capture and dismiss it.
                app.typeKey("t", modifierFlags: .command)
                app.typeKey(.escape, modifierFlags: [])

                XCTAssertEqual(app.state, .runningForeground, "booklist stopped running in round \(round)")
                XCTAssertTrue(window.exists, "Main window disappeared in round \(round)")
            }
        }
    }

    // MARK: - Helpers

    private func selectSidebar(_ name: String) {
        let sidebar = app.outlines.firstMatch
        let texts = sidebar.staticTexts
        guard let index = texts.allElementsBoundByIndex.firstIndex(where: {
            ($0.label.isEmpty ? ($0.value as? String ?? "") : $0.label) == name
        }) else { return }   // collapsed subfolder — skip rather than fail
        texts.element(boundBy: index).click()
    }

    private func scrollContent(times: Int) {
        let point = window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        for _ in 0..<times { point.scroll(byDeltaX: 0, deltaY: -1200) }
        for _ in 0..<times { point.scroll(byDeltaX: 0, deltaY: 1200) }
    }

    /// A card's title (stress items are titled "<number> …"). Clicking the title selects the
    /// card; the hover buttons (open link etc.) sit on the image, away from it.
    private func firstCardTitle() -> XCUIElement? {
        let title = window.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ .*")).firstMatch
        return title.exists && title.isHittable ? title : nil
    }
}

/// Everyday flows, the way a user would do them: capture (page + shop link), the wishlist
/// toggle respecting the user's choice, delete + undo, search, Settings, keyboard + reader,
/// and a long masonry list loading more cards. Uses the in-memory sample library
/// (`-uiTesting`); capture and the reader load real web pages.
/// Opt-in like the other UI tests (`/tmp/booklist-run-ui-tests`).
final class UserFlowUITests: XCTestCase {

    private var app: XCUIApplication!
    private var window: XCUIElement { app.windows.firstMatch }

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/booklist-run-ui-tests"),
                          "UI tests drive the mouse; touch /tmp/booklist-run-ui-tests to run them.")
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    private func launch(_ extra: [String] = []) {
        app = launchBooklist(extraArguments: ["-captureShortcutKey", "t"] + extra, windowTimeout: 30)
        XCTAssertTrue(app.outlines.firstMatch.waitForExistence(timeout: 30))
    }

    // MARK: - Capture

    @MainActor
    func testCaptureAPage() throws {
        launch()
        let sheet = openCapture()
        paste("https://en.wikipedia.org/wiki/Avatar:_The_Last_Airbender", into: sheet.textFields["Paste a link…"])
        XCTAssertTrue(waitForText(in: sheet, containing: "Avatar", timeout: 25), "Title wasn't fetched\n\(sheet.debugDescription)")
        XCTAssertTrue(sheet.buttons["Save Bookmark"].isEnabled)
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "Capture didn't close after ⌘Return")
        XCTAssertTrue(waitForText(in: window, containing: "Avatar", timeout: 10), "Saved page isn't in the Inbox")
    }

    @MainActor
    func testCaptureAShopLink() throws {
        launch()
        let sheet = openCapture()
        paste("https://www.amazon.es/gp/product/B0GT9F92N2?smid=A1PQIIO52BJNPL&psc=1", into: sheet.textFields["Paste a link…"])
        XCTAssertTrue(sheet.buttons["Save to Wishlist"].waitForExistence(timeout: 10), "Amazon link didn't default to wishlist\n\(sheet.debugDescription)")
        XCTAssertTrue(waitForText(in: sheet, containing: "Outsunny", timeout: 25), "Title wasn't fetched\n\(sheet.debugDescription)")
        let priceFilled = waitUntil(timeout: 10) {
            sheet.textFields.allElementsBoundByIndex.contains { ($0.value as? String)?.contains(where: \.isNumber) == true && ($0.value as? String)?.contains(".") == true }
        }
        XCTAssertTrue(priceFilled, "Price wasn't filled in\n\(sheet.debugDescription)")
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        selectSidebar("Wishlist")
        XCTAssertTrue(waitForText(in: window, containing: "Outsunny", timeout: 10), "Saved item isn't in the Wishlist")
    }

    @MainActor
    func testWishlistToggleRespectsUserChoice() throws {
        launch()
        let sheet = openCapture()
        paste("https://www.amazon.es/gp/product/B0GT9F92N2?smid=A1PQIIO52BJNPL&psc=1", into: sheet.textFields["Paste a link…"])
        XCTAssertTrue(sheet.buttons["Save to Wishlist"].waitForExistence(timeout: 10))
        // Turn it off right away — before the page has finished loading.
        sheet.switches.firstMatch.click()
        XCTAssertTrue(sheet.buttons["Save Bookmark"].waitForExistence(timeout: 5))
        // Let the fetch finish; product detection must not switch it back on.
        _ = waitForText(in: sheet, containing: "Outsunny", timeout: 25)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(sheet.buttons["Save Bookmark"].exists, "The fetch overrode the user's choice")
        XCTAssertFalse(sheet.buttons["Save to Wishlist"].exists)
        sheet.buttons["Cancel"].click()
    }

    // MARK: - Library

    @MainActor
    func testDeleteAndUndo() throws {
        launch()
        let title = window.staticTexts.matching(titlePredicate("SwiftUI by Example")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), window.debugDescription)
        title.click()
        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "⌘⌫ didn't delete the selected card")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(title.waitForExistence(timeout: 5), "⌘Z didn't bring the card back")
    }

    /// The edit panel edits a draft and saves it after a pause and on Done — the note must still
    /// end up on the bookmark, and typing must not be lost when Done is pressed right away.
    @MainActor
    func testEditNoteIsSaved() throws {
        launch()
        let title = window.staticTexts.matching(titlePredicate("SwiftUI by Example")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.rightClick()
        app.menuItems["Edit"].click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Edit panel didn't open")
        let note = sheet.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), sheet.debugDescription)
        note.click()
        app.typeKey("a", modifierFlags: .command)
        note.typeText("Saved from the draft")
        sheet.buttons["Done"].click()       // straight away — before the 0.6 s autosave
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForText(in: window, containing: "Saved from the draft", timeout: 5),
                      "The edited note isn't on the card")
    }

    @MainActor
    func testSearch() throws {
        launch()
        selectSidebar("All")
        app.typeKey("f", modifierFlags: .command)
        app.typeText("jazz")
        XCTAssertTrue(waitForText(in: window, containing: "Miles Davis", timeout: 5), "Search didn't find the jazz bookmark")
        XCTAssertTrue(waitUntil(timeout: 5) { !self.hasText(in: self.window, containing: "Figma") }, "Unrelated bookmarks still showing")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitForText(in: window, containing: "Figma", timeout: 5), "Clearing the search didn't bring everything back")
    }

    @MainActor
    func testSettingsTabs() throws {
        launch()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.matching(NSPredicate(format: "identifier CONTAINS[c] 'settings' OR title IN %@", ["General", "Display", "Tags", "Sync"])).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        for tab in ["Display", "Tags", "Sync", "General"] {
            let button = app.toolbars.buttons[tab].exists ? app.toolbars.buttons[tab] : app.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(tab) tab")
            button.click()
        }
        app.typeKey("w", modifierFlags: .command)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testKeyboardAndReader() throws {
        launch()
        selectSidebar("All")
        let title = window.staticTexts.matching(titlePredicate("Figma")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.click()
        for key in [XCUIKeyboardKey.downArrow, .rightArrow, .downArrow, .leftArrow, .upArrow] {
            app.typeKey(key, modifierFlags: [])
        }
        app.typeKey(.space, modifierFlags: [])        // reader for the selected bookmark
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        app.typeKey(.escape, modifierFlags: [])       // close the reader
        app.typeKey(.escape, modifierFlags: [])       // clear the selection
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(window.exists)
    }

    @MainActor
    func testLongMasonryLoadsMoreCards() throws {
        launch(["-stressItems", "1000"])
        selectSidebar("All")
        app.typeKey("1", modifierFlags: .command)
        // Without batch loading at most 150 different cards could ever appear (the first batch).
        let firstScreen = visibleItems()
        XCTAssertFalse(firstScreen.isEmpty, window.debugDescription)
        var seen = firstScreen
        let point = window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        var scrolls = 0
        while seen.count < 400 && scrolls < 80 {
            point.scroll(byDeltaX: 0, deltaY: -1500)
            seen.formUnion(visibleItems())
            scrolls += 1
        }
        XCTAssertGreaterThanOrEqual(seen.count, 400, "Only \(seen.count) different cards after \(scrolls) scrolls — batches didn't load")
        // Back to the top: the first cards are there again.
        for _ in 0..<(scrolls + 5) { point.scroll(byDeltaX: 0, deltaY: 6000) }
        XCTAssertFalse(visibleItems().isDisjoint(with: firstScreen), "Scrolling back up didn't return to the first cards")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Stress items are titled "<number> …"; card dates ("20 Oct 2026") are ignored. Read from
    /// one snapshot — lazy cards come and go while scrolling, so element-by-element reads race.
    private func visibleItems() -> Set<Int> {
        guard let root = try? window.snapshot() else { return [] }
        let date = try? NSRegularExpression(pattern: #"^\d+ [A-Z][a-z]{2} \d{4}$"#)
        var items = Set<Int>()
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText, let text = node.value as? String, let first = text.first, first.isNumber,
               date?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil,
               let number = Int(text.prefix(while: \.isNumber)) {
                items.insert(number)
            }
            node.children.forEach(walk)
        }
        walk(root)
        return items
    }

    // MARK: - Helpers

    /// Pastes like a user would (typing drops characters such as ":" on some keyboard layouts).
    /// The user's clipboard is restored afterwards.
    private func paste(_ text: String, into field: XCUIElement) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        field.click()
        app.typeKey("v", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }
    }

    /// Card titles expose their text as the element's value, not its label.
    private func titlePredicate(_ prefix: String) -> NSPredicate {
        NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix)
    }

    private func openCapture() -> XCUIElement {
        app.typeKey("t", modifierFlags: .command)
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "⌘T didn't open capture")
        return sheet
    }

    private func selectSidebar(_ name: String) {
        let texts = app.outlines.firstMatch.staticTexts
        guard let index = texts.allElementsBoundByIndex.firstIndex(where: {
            ($0.label.isEmpty ? ($0.value as? String ?? "") : $0.label) == name
        }) else { return XCTFail("\(name) not in the sidebar") }
        texts.element(boundBy: index).click()
    }

    private func hasText(in element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", text, text)
        return element.staticTexts.matching(predicate).firstMatch.exists
            || element.textFields.matching(predicate).firstMatch.exists
    }

    private func waitForText(in element: XCUIElement, containing text: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) { self.hasText(in: element, containing: text) }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return condition()
    }
}
