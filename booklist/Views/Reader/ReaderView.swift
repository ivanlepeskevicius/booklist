import SwiftUI
import WebKit

/// Distraction-free reader, embedded as an inline right-hand panel inside ContentAreaView.
struct ReaderView: View {
    let bookmark: Bookmark
    let onClose: () -> Void

    @State private var loadState: LoadState = .loading
    @State private var showFontControls = false
    @State private var systemFonts: [String] = []

    @AppStorage("readerFontName")   private var readerFontName   = ""
    @AppStorage("readerFontSize")   private var readerFontSize   = 15
    @AppStorage("readerDefaultWeb") private var readerDefaultWeb = true

    @State private var showWebView          = true
    @State private var readerContentLoaded = false

    private enum LoadState {
        case loading
        case loaded(AttributedString)
        case webFallback(URL)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentArea
        }
        .task(id: bookmark.id) {
            showWebView = readerDefaultWeb
            readerContentLoaded = false
            loadState = .loading
            if !showWebView {
                await loadContent()
                readerContentLoaded = true
            }
        }
        .onChange(of: readerFontName) { _, _ in
            Task { await rebuildContent() }
        }
        .onChange(of: readerFontSize) { _, _ in
            Task { await rebuildContent() }
        }
        .onAppear {
            if systemFonts.isEmpty {
                systemFonts = NSFontManager.shared.availableFontFamilies.sorted()
            }
        }
    }

    // MARK: - Load / Rebuild

    private func loadContent() async {
        loadState = .loading
        do {
            let content = try await ReaderService.shared.fetchReadableContent(
                from: bookmark.url,
                fontName: readerFontName,
                baseFontSize: readerFontSize
            )
            // Fall back to the in-app web view when extracted text is too thin
            // (e.g. JS-rendered pages like Reddit that return a near-empty shell)
            if content.characters.count < 300, let url = URL(string: bookmark.url) {
                loadState = .webFallback(url)
            } else {
                loadState = .loaded(content)
            }
        } catch {
            if let url = URL(string: bookmark.url) {
                loadState = .webFallback(url)
            } else {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    /// Rebuilds from cached HTML — no network fetch, no loading flash.
    private func rebuildContent() async {
        guard case .loaded = loadState else { return }
        do {
            if let content = try await ReaderService.shared.rebuildFromCache(
                url: bookmark.url,
                fontName: readerFontName,
                baseFontSize: readerFontSize
            ) {
                loadState = .loaded(content)
            }
        } catch {
            // Keep existing content if rebuild fails
        }
    }

    private func toggleMode() {
        if showWebView {
            showWebView = false
            if !readerContentLoaded {
                readerContentLoaded = true
                Task { await loadContent() }
            }
        } else {
            showWebView = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close reader")

            Spacer()

            HStack(spacing: 6) {
                if let favStr = bookmark.faviconURL, let favURL = URL(string: favStr) {
                    AsyncImage(url: favURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "globe").foregroundStyle(.tertiary)
                    }
                    .frame(width: 14, height: 14)
                }
                Text(bookmark.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Spacer()

            // Font / size controls — only relevant in reader mode
            if !showWebView {
                Button {
                    showFontControls.toggle()
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reader settings")
                .popover(isPresented: $showFontControls, arrowEdge: .bottom) {
                    fontControlsPopover
                }
            }

            // Web preview / reader mode toggle
            Button { toggleMode() } label: {
                Image(systemName: showWebView ? "doc.plaintext" : "globe")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(showWebView ? "Switch to Reader" : "Switch to Web preview")

            Button {
                if let url = URL(string: bookmark.url) {
                    bookmark.lastOpenedDate = Date()
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "safari")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in browser")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Font controls popover

    private var fontControlsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Font", selection: $readerFontName) {
                Text("System Default").tag("")
                Divider()
                ForEach(systemFonts, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)

            LabeledContent("Size") {
                HStack(spacing: 8) {
                    Stepper("", value: $readerFontSize, in: 12...24, step: 1)
                        .labelsHidden()
                    Text("\(readerFontSize) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .leading)
                }
            }

            Text("The quick brown fox jumps over the lazy dog")
                .font(readerFontName.isEmpty
                      ? .system(size: CGFloat(readerFontSize))
                      : .custom(readerFontName, size: CGFloat(readerFontSize)))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .animation(.default, value: readerFontName)
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if showWebView {
            if let url = URL(string: bookmark.url) {
                ReaderWebView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            readerContent
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        switch loadState {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading article…")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let content):
            ScrollView(.vertical) {
                Text(content)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
            }
            .frame(maxWidth: .infinity)

        case .webFallback(let url):
            ReaderWebView(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Couldn't load article")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Button("Open in browser instead") {
                    if let url = URL(string: bookmark.url) {
                        NSWorkspace.shared.open(url)
                    }
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Web fallback view

/// Renders the full page inside a WKWebView with nav/header/footer suppressed via injected CSS.
private struct ReaderWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let css = """
            nav,header,footer,aside,
            [role=navigation],[role=banner],[role=complementary],
            .ad,.ads,.advertisement { display: none !important; }
            body { max-width: 800px; margin: 0 auto; padding: 24px; }
        """
        let js = """
            var s = document.createElement('style');
            s.textContent = `\(css)`;
            document.head.appendChild(s);
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(script)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
