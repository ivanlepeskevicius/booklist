import Foundation

/// Carries an incoming URL from the system (deep link or Share Extension)
/// to whichever part of the UI is responsible for showing the capture sheet.
///
/// Usage:
///   - Writer: `booklistApp.onOpenURL` sets `pendingURL` / `pendingTitle`.
///   - Reader: `SidebarView` observes changes and opens `CaptureView`.
///   - Cleanup: the sheet's `onDismiss` clears both fields.
@Observable
final class CaptureRouter {
    var pendingURL:   String? = nil
    var pendingTitle: String? = nil

    static let shared = CaptureRouter()
    private init() {}
}
