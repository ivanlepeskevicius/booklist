import AppKit

/// Minimal Share Extension entry point.
///
/// Data flow:
///   1. Writes the shared URL to the App Group UserDefaults (the reliable channel).
///   2. Sends a `booklist://capture` ping to wake the main app (best-effort).
///   3. If the ping is blocked by the sandbox, the URL waits in UserDefaults until
///      the user switches to booklist, at which point the app reads it on activation.
final class ShareViewController: NSViewController {

    private static let appGroupID   = "group.lepi.booklist"
    private static let urlKey       = "pendingCaptureURL"
    private static let titleKey     = "pendingCaptureTitle"

    // MARK: - View (programmatic — no XIB needed)

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 64))

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Saved to booklist")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
    }

    // MARK: - Share handling

    override func viewDidLoad() {
        super.viewDidLoad()
        handleShare()
    }

    private func handleShare() {
        guard
            let item     = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier("public.url")
            })
        else {
            complete(launchApp: false)
            return
        }

        provider.loadObject(ofClass: NSURL.self) { [weak self] result, _ in
            guard let url = result as? URL else {
                self?.complete(launchApp: false)
                return
            }

            let title = (self?.extensionContext?.inputItems.first as? NSExtensionItem)?
                .attributedContentText?.string ?? ""

            // ── Primary channel: write to shared App Group UserDefaults ──
            let defaults = UserDefaults(suiteName: ShareViewController.appGroupID)
            defaults?.set(url.absoluteString, forKey: ShareViewController.urlKey)
            defaults?.set(title.isEmpty ? nil : title, forKey: ShareViewController.titleKey)
            defaults?.synchronize()

            // Dismiss the share sheet first; activate booklist in the completion handler
            // so macOS doesn't return focus to the originating app after sheet dismissal.
            self?.complete(launchApp: true)
        }
    }

    /// Completes the extension request. If `launchApp` is true, activates (or launches)
    /// booklist inside the completion handler — i.e. after the share sheet is fully gone.
    private func complete(launchApp: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: []) { _ in
                guard launchApp else { return }
                let bundleID = "lepi.booklist"
                if let running = NSRunningApplication
                    .runningApplications(withBundleIdentifier: bundleID).first {
                    running.activate(options: [])
                } else if let ping = URL(string: "booklist://capture") {
                    NSWorkspace.shared.open(ping)
                }
            }
        }
    }
}
