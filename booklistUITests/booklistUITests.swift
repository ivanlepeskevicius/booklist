import XCTest

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

    /// Launches the freshly built booklist.app from the build products folder.
    private func launchBooklist() -> XCUIApplication {
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
        app.launchArguments = ["-uiTesting", "-ApplePersistenceIgnoreState", "YES", "-showInDock", "YES"]
        app.launch()
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 5) {
            // Fallback: open it from the menu bar icon, like a user would.
            app.statusItems.firstMatch.click()
            app.menuItems["Open booklist"].click()
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "No booklist window\n\(app.debugDescription)")
        return app
    }

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
