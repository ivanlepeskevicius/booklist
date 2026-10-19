import WebKit
import AppKit

@MainActor
enum ScreenshotService {

    fileprivate static var _active: [_Capturer] = []

    /// Loads `urlString` in an off-screen WKWebView, waits for it to render,
    /// saves a screenshot via ImageStore, and returns the local file:// URL string.
    /// Returns nil on failure, timeout (15 s), or if the caller's Task was cancelled.
    static func capture(urlString: String) async -> String? {
        guard let url = URL(string: urlString), !Task.isCancelled else { return nil }

        return await withCheckedContinuation { continuation in
            var resumed = false
            let resume: (String?) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            let capturer = _Capturer(url: url, completion: resume)
            _active.append(capturer)
            capturer.start()

            // Safety timeout: abort after 15 seconds. Tearing down the capturer matters —
            // otherwise its web view (and WebKit process) stays alive forever.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                capturer.cancel()
            }
        }
    }
}

@MainActor
private final class _Capturer: NSObject, WKNavigationDelegate {

    private let url:        URL
    private let completion: (String?) -> Void
    private var webView:    WKWebView?

    init(url: URL, completion: @escaping (String?) -> Void) {
        self.url        = url
        self.completion = completion
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                           configuration: config)
        wv.navigationDelegate = self
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView = wv
        wv.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Brief delay for JS and lazy-loaded images to settle
            try? await Task.sleep(for: .milliseconds(800))
            guard let wv = self.webView else { finish(nil); return }

            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.rect = CGRect(x: 0, y: 0, width: 1280, height: 800)

            // Strong capture is fine: `_active` keeps the capturer alive until finish(),
            // and the closure runs once — no retain cycle.
            wv.takeSnapshot(with: snapshotConfig) { image, _ in
                let saved = image.flatMap { try? ImageStore.save($0) }
                self.finish(saved)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finish(nil)
    }

    /// Stops loading and releases the web view. Safe to call after the capture already finished.
    func cancel() {
        finish(nil)
    }

    private func finish(_ result: String?) {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        ScreenshotService._active.removeAll { $0 === self }
        completion(result)
    }
}
