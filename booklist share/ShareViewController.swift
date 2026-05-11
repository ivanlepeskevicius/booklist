import AppKit

/// Minimal Share Extension entry point.
///
/// Data flow:
///   1. Writes the shared URL to the App Group UserDefaults (the reliable channel).
///   2. Sends a `booklist://capture` ping to wake the main app (best-effort).
///   3. If the ping is blocked by the sandbox, the URL waits in UserDefaults until
///      the user switches to booklist, at which point the app reads it on activation.
final class ShareViewController: NSViewController {

    private static let appGroupID   = "group.com.ivanlepi.booklist"
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
            complete()
            return
        }

        provider.loadObject(ofClass: NSURL.self) { [weak self] result, _ in
            defer { self?.complete() }
            guard let url = result as? URL else { return }

            let title = (self?.extensionContext?.inputItems.first as? NSExtensionItem)?
                .attributedContentText?.string ?? ""

            // ── Primary channel: write to shared App Group UserDefaults ──
            let defaults = UserDefaults(suiteName: ShareViewController.appGroupID)
            defaults?.set(url.absoluteString, forKey: ShareViewController.urlKey)
            defaults?.set(title.isEmpty ? nil : title, forKey: ShareViewController.titleKey)
            defaults?.synchronize()

            // ── Best-effort: ping the main app to bring it forward ──
            // This may be blocked by the extension sandbox on some macOS versions;
            // if so, the user opens booklist manually and the URL is waiting in UserDefaults.
            if let ping = URL(string: "booklist://capture") {
                NSWorkspace.shared.open(ping)
            }
        }
    }

    private func complete() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
