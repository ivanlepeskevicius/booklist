//
//  booklistApp.swift
//  booklist
//
//  Created by Ivan Lepeskevicius on 19/04/2026.
//

import SwiftUI
import SwiftData
import KeyboardShortcuts

// MARK: - Main window delegate

/// Intercepts the red close button so the main window is hidden rather than
/// destroyed. This is the standard pattern for menu-bar apps: the window always
/// exists in memory and can be shown again via makeKeyAndOrderFront.
@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    /// Called when the window really closes (dock mode), so AppDelegate can forget it.
    var onClose: () -> Void = {}

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        if showInDock {
            // Dock mode: let the window close normally.
            return true
        }
        // Menu-bar mode: hide instead of close.
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}

// MARK: - App delegate (needed to set activation policy before windows appear)

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Scene id of the main WindowGroup — also used with `openWindow(id:)`.
    static let mainWindowID = "main"

    /// Injected by booklistApp so we can export on quit without a SwiftUI environment.
    var modelContainer: ModelContainer?

    /// Strong reference so the delegate isn't deallocated.
    private var mainWindowDelegate: MainWindowDelegate?
    /// Weak reference to the main content window. Set when it first becomes key,
    /// cleared when it's closed (dock mode) so a newly opened window can be adopted.
    private(set) weak var mainWindow: NSWindow?

    /// SwiftUI names WindowGroup windows after the scene id (e.g. "main-AppWindow-1"),
    /// which tells the main window apart from Settings and other windows.
    private func isMainContentWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(Self.mainWindowID) == true && window !== closedWindow
    }

    /// The last main window that was really closed — excluded from adoption in case
    /// AppKit hasn't released it yet.
    private weak var closedWindow: NSWindow?

    /// Attaches MainWindowDelegate (close → hide in menu-bar mode) and remembers the window.
    @MainActor
    private func adopt(_ window: NSWindow) {
        let delegate = MainWindowDelegate()
        delegate.onClose = { [weak self, weak window] in
            self?.closedWindow = window
            self?.mainWindow = nil
            self?.mainWindowDelegate = nil
        }
        mainWindowDelegate = delegate
        window.delegate = delegate
        mainWindow = window
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyUp(for: .captureFromAnywhere) { [weak self] in
            self?.bringUpMainWindow(thenCapture: true)
        }

        // The first time the main content window becomes key:
        //   1. Attach MainWindowDelegate so close → hide instead of destroy.
        //   2. Promote to .regular so Cmd+Tab works while the window is open.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self,
                      let window = note.object as? NSWindow,
                      window.canBecomeMain else { return }

                if self.mainWindow == nil, self.isMainContentWindow(window) {
                    self.adopt(window)
                }

                let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
                guard !showInDock else { return }
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    /// Keep the process alive when the last window is closed so the menu bar
    /// icon can still reopen it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Called when the dock icon is clicked and there are no visible windows (e.g. window was
    /// hidden in menu-bar mode, or closed in dock mode). Show the main window explicitly so the
    /// app comes to the foreground instead of silently staying in the background.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A hidden window was shown → we handled it (false stops SwiftUI from also
        // creating a second window). No window at all → let SwiftUI create one (true).
        if !flag, showMainWindow() { return false }
        return true
    }

    /// Canonical helper — promotes the activation policy if needed, then brings the
    /// main window to front and activates the app. Deferred by one run-loop cycle so
    /// the policy change takes effect before activation fires (avoids the race that
    /// causes the window to appear in the background).
    /// Returns false when there's no main window (closed in dock mode) — the caller
    /// must then create one with `openWindow(id: AppDelegate.mainWindowID)`.
    @MainActor
    @discardableResult
    func showMainWindow() -> Bool {
        // The window may exist without ever having become key (e.g. launched in
        // menu-bar mode and never clicked) — find and adopt it rather than opening a second one.
        if mainWindow == nil, let existing = NSApp.windows.first(where: isMainContentWindow) {
            adopt(existing)
        }
        guard let window = mainWindow else { return false }
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        if !showInDock { NSApp.setActivationPolicy(.regular) }
        // Defer past the current run-loop turn so setActivationPolicy completes first.
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        return true
    }

    /// SwiftUI's `openWindow` is only reachable from views, so views that have it hand it
    /// over here — lets non-view code (the global hotkey) recreate a closed main window.
    var openMainWindow: (() -> Void)?

    /// Shows the main window, creating it if it was closed (dock mode), then optionally
    /// opens the capture sheet. Used by menu items and the global hotkey.
    @MainActor
    func bringUpMainWindow(thenCapture: Bool) {
        if !showMainWindow() {
            openMainWindow?()
            NSApp.activate()
        }
        if thenCapture { CaptureRouter.shared.requestCapture() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard SyncService.isEnabled, let container = modelContainer else { return }
        try? SyncService.export(context: container.mainContext)
    }
}

// MARK: - Menu commands

/// File › Import and the View menu's layout options. View mode and card size are
/// @AppStorage, so the menu and the toolbar stay in sync automatically.
private struct LibraryCommands: Commands {
    @FocusedBinding(\.showingImport) private var showingImport
    @AppStorage("viewMode")      private var viewMode      = ViewMode.masonry
    @AppStorage("cardSizeScale") private var cardSizeScale = 1.0

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Bookmarks…") { showingImport = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(showingImport == nil)
        }

        CommandGroup(before: .toolbar) {
            Picker("View As", selection: $viewMode) {
                Text("Masonry").tag(ViewMode.masonry)
                    .keyboardShortcut("1", modifiers: .command)
                Text("List").tag(ViewMode.list)
                    .keyboardShortcut("2", modifiers: .command)
            }
            .pickerStyle(.inline)

            Divider()

            // "=" rather than "+": on most layouts "+" needs Shift, so ⌘+ wouldn't fire reliably.
            Button("Larger Cards") {
                if let next = CardSize.step(from: cardSizeScale, larger: true) { cardSizeScale = next }
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(viewMode != .masonry || CardSize.step(from: cardSizeScale, larger: true) == nil)

            Button("Smaller Cards") {
                if let next = CardSize.step(from: cardSizeScale, larger: false) { cardSizeScale = next }
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(viewMode != .masonry || CardSize.step(from: cardSizeScale, larger: false) == nil)

            Divider()
        }
    }
}

// MARK: - Show-window menu item

/// A menu item that brings up the main window — creating it if it was closed in
/// dock mode — and optionally opens the capture sheet.
private struct ShowMainWindowButton: View {
    let title: String
    let appDelegate: AppDelegate
    var thenCapture = false

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) {
            appDelegate.openMainWindow = { openWindow(id: AppDelegate.mainWindowID) }
            appDelegate.bringUpMainWindow(thenCapture: thenCapture)
        }
    }
}

/// The menu bar icon. It's always on screen, so it's where AppDelegate gets its
/// `openWindow` hook at launch — before any menu has been used.
private struct MenuBarIcon: View {
    let appDelegate: AppDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "bookmark.fill")
            .onAppear {
                appDelegate.openMainWindow = { openWindow(id: AppDelegate.mainWindowID) }
                // UI tests launch the app in the background, where SwiftUI doesn't create the
                // initial window — open it explicitly so the test has something to drive.
                if LaunchMode.isUITesting {
                    appDelegate.bringUpMainWindow(thenCapture: false)
                }
            }
    }
}

// MARK: - App

// MARK: - Launch mode

/// UI tests launch with `-uiTesting`: an in-memory store filled with sample data and sync
/// switched off, so a test run can never touch the real library or overwrite the sync file.
nonisolated enum LaunchMode {
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    /// `-stressItems 3000` (UI tests only): fill the in-memory store with a large library.
    static let stressItems = isUITesting ? UserDefaults.standard.integer(forKey: "stressItems") : 0
}

@main
struct booklistApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static var didRunLaunchTasks = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Bookmark.self,
            Folder.self,
            Tag.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: LaunchMode.isUITesting)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup(id: AppDelegate.mainWindowID) {
            ContentView()
                .environment(CaptureRouter.shared)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    // The window can be closed and recreated (dock mode) — launch work runs once.
                    guard !Self.didRunLaunchTasks else { return }
                    Self.didRunLaunchTasks = true
                    // Give the delegate a reference so it can export on quit.
                    appDelegate.modelContainer = sharedModelContainer
                    // Import from sync file on launch if enabled and a newer snapshot exists.
                    if SyncService.isEnabled {
                        _ = try? SyncService.importIfNewer(context: sharedModelContainer.mainContext)
                    }
                    #if DEBUG
                    // Populate sample data only when sync isn't configured.
                    if LaunchMode.stressItems > 0 {
                        StressData.populate(count: LaunchMode.stressItems, in: sharedModelContainer.mainContext)
                    } else if !SyncService.isEnabled {
                        SampleData.populate(in: sharedModelContainer.mainContext)
                    }
                    #endif
                    // Launch-time imports aren't user actions — don't let ⌘Z revert them.
                    let context = sharedModelContainer.mainContext
                    try? context.save()
                    context.undoManager?.removeAllActions()
                    // Never with the UI-test store: its in-memory library doesn't reference the
                    // user's real images, which would all look orphaned.
                    if !LaunchMode.isUITesting,
                       let bookmarks = try? context.fetch(FetchDescriptor<Bookmark>()) {
                        let imageURLs = bookmarks.flatMap { $0.imageURLs + [$0.selectedImageURL].compactMap { $0 } }
                        await StorageCleanup.run(referencedImageFiles: StorageCleanup.referencedFiles(imageURLs))
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            // The app is single-window (AppDelegate tracks one main window), so drop
            // File › New Window. The capture shortcut itself lives on the toolbar button.
            CommandGroup(replacing: .newItem) {
                ShowMainWindowButton(title: "Save Link…", appDelegate: appDelegate, thenCapture: true)
            }
            LibraryCommands()
        }

        MenuBarExtra {
            ShowMainWindowButton(title: "Open booklist", appDelegate: appDelegate)
                .keyboardShortcut("o", modifiers: [])

            ShowMainWindowButton(title: "Save Link…", appDelegate: appDelegate, thenCapture: true)
                .keyboardShortcut("s", modifiers: [])

            Divider()
            SettingsLink()
            Divider()

            Button("Quit booklist") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [])
        } label: {
            MenuBarIcon(appDelegate: appDelegate)
        }

        Settings {
            AppSettingsView()
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Deep link handling

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "booklist" else { return }

        switch url.host {
        case "add":
            // Direct deep link from bookmarklet: booklist://add?url=...&title=...
            guard
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let urlValue   = components.queryItems?.first(where: { $0.name == "url" })?.value,
                !urlValue.isEmpty
            else { return }
            let title = components.queryItems?.first(where: { $0.name == "title" })?.value ?? ""
            CaptureRouter.shared.pendingURL   = urlValue
            CaptureRouter.shared.pendingTitle = title.isEmpty ? nil : title

        case "capture":
            // Deep link from Share Extension: booklist://capture?url=...&title=...
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let urlValue = components.queryItems?.first(where: { $0.name == "url" })?.value,
               !urlValue.isEmpty {
                CaptureRouter.shared.pendingURL   = urlValue
                CaptureRouter.shared.pendingTitle = components.queryItems?
                    .first(where: { $0.name == "title" })?.value
            }
            appDelegate.showMainWindow()

        default:
            break
        }
    }

}
