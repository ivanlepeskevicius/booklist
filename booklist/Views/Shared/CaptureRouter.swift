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

    private static let appGroupID = "group.lepi.booklist"

    /// Reads a URL left by the Share Extension in the shared App Group UserDefaults
    /// and routes it into the capture sheet. Safe to call from anywhere.
    func checkPendingCapture() {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        guard
            let urlString = defaults?.string(forKey: "pendingCaptureURL"),
            !urlString.isEmpty
        else { return }

        pendingURL   = urlString
        pendingTitle = defaults?.string(forKey: "pendingCaptureTitle")

        defaults?.removeObject(forKey: "pendingCaptureURL")
        defaults?.removeObject(forKey: "pendingCaptureTitle")
    }
}
