import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// System-wide "save a link" hotkey — works while any app is in front. User-configurable in Settings.
    static let captureFromAnywhere = Self("captureFromAnywhere", initial: .init(.b, modifiers: [.control, .option, .command]))
}

/// Carries an incoming URL from the system (deep link or Share Extension)
/// to whichever part of the UI is responsible for showing the capture sheet.
///
/// Usage:
///   - Writer: `booklistApp.onOpenURL` sets `pendingURL` / `pendingTitle`.
///   - Reader: `ContentAreaView` observes changes and opens `CaptureView`.
///   - Cleanup: the sheet's `onDismiss` clears both fields.
///   - `requestCapture()` opens an empty capture sheet (e.g. from the menu bar).
@Observable
final class CaptureRouter {
    var pendingURL:   String? = nil
    var pendingTitle: String? = nil
    /// A pending request rather than an event, so a window created *after* the request
    /// (dock mode, window was closed) still sees it. ContentAreaView resets it once handled.
    var isCaptureRequested = false

    func requestCapture() {
        isCaptureRequested = true
    }

    static let shared = CaptureRouter()
    private init() {}
}
