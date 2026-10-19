import AppKit

/// Minimal Share Extension entry point.
///
/// Builds a `booklist://capture?url=...&title=...` deep link and delivers it
/// via NSWorkspace.open — works whether booklist is already running or not.
/// No App Group required.
final class ShareViewController: NSViewController {

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
            complete(with: nil)
            return
        }

        provider.loadObject(ofClass: NSURL.self) { [weak self] result, _ in
            guard let url = result as? URL else {
                self?.complete(with: nil)
                return
            }

            let title = (self?.extensionContext?.inputItems.first as? NSExtensionItem)?
                .attributedContentText?.string ?? ""

            var components = URLComponents()
            components.scheme = "booklist"
            components.host = "capture"
            var queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
            if !title.isEmpty {
                queryItems.append(URLQueryItem(name: "title", value: title))
            }
            components.queryItems = queryItems

            self?.complete(with: components.url)
        }
    }

    private func complete(with deepLink: URL?) {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: []) { _ in
                guard let deepLink else { return }
                NSWorkspace.shared.open(deepLink)
            }
        }
    }
}
