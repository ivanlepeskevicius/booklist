//
//  booklistApp.swift
//  booklist
//
//  Created by Ivan Lepeskevicius on 19/04/2026.
//

import SwiftUI
import SwiftData

// MARK: - Main window delegate

/// Intercepts the red close button so the main window is hidden rather than
/// destroyed. This is the standard pattern for menu-bar apps: the window always
/// exists in memory and can be shown again via makeKeyAndOrderFront.
@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
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
    /// Injected by booklistApp so we can export on quit without a SwiftUI environment.
    var modelContainer: ModelContainer?

    /// Strong reference so the delegate isn't deallocated.
    private var mainWindowDelegate: MainWindowDelegate?
    /// Weak reference to the main content window (set once, on first key event).
    private(set) weak var mainWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? false
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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

                // Attach our delegate once — skip the settings window and any
                // window that already has a delegate.
                if self.mainWindow == nil && !(window.delegate is MainWindowDelegate) {
                    let delegate = MainWindowDelegate()
                    self.mainWindowDelegate = delegate
                    window.delegate = delegate
                    self.mainWindow = window
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
        if !flag { showMainWindow() }
        return true
    }

    /// Canonical helper — promotes the activation policy if needed, then brings the
    /// main window to front and activates the app. Deferred by one run-loop cycle so
    /// the policy change takes effect before activation fires (avoids the race that
    /// causes the window to appear in the background).
    @MainActor
    func showMainWindow() {
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        if !showInDock { NSApp.setActivationPolicy(.regular) }
        // Defer past the current run-loop turn so setActivationPolicy completes first.
        DispatchQueue.main.async {
            self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard SyncService.isEnabled, let container = modelContainer else { return }
        try? SyncService.export(context: container.mainContext)
    }
}

// MARK: - App

@main
struct booklistApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Bookmark.self,
            Folder.self,
            Tag.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(CaptureRouter.shared)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    // Give the delegate a reference so it can export on quit.
                    appDelegate.modelContainer = sharedModelContainer
                    // Import from sync file on launch if enabled and a newer snapshot exists.
                    if SyncService.isEnabled {
                        _ = try? SyncService.importIfNewer(context: sharedModelContainer.mainContext)
                    }
                    #if DEBUG
                    // Populate sample data only when sync isn't configured.
                    if !SyncService.isEnabled {
                        SampleData.populate(in: sharedModelContainer.mainContext)
                    }
                    #endif
                }
        }
        .modelContainer(sharedModelContainer)

        MenuBarExtra {
            Button("Open booklist") {
                appDelegate.showMainWindow()
            }
            .keyboardShortcut("o", modifiers: [])

            Divider()
            SettingsLink()
            Divider()

            Button("Quit booklist") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [])
        } label: {
            Image(systemName: "bookmark.fill")
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
            // Wake ping from Share Extension — actual URL is in App Group UserDefaults.
            // Bring the app window to front in case it was backgrounded when the share fired.
            appDelegate.showMainWindow()
            checkPendingCapture()

        default:
            break
        }
    }

    // MARK: - App Group handoff (Share Extension → main app)

    /// Called on URL-scheme wake. Delegates to the shared router.
    func checkPendingCapture() {
        CaptureRouter.shared.checkPendingCapture()
    }
}
