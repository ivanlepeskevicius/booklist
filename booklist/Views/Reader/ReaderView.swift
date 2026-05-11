import SwiftUI

/// Distraction-free reader, embedded as an inline right-hand panel inside ContentAreaView.
struct ReaderView: View {
    let bookmark: Bookmark
    let onClose: () -> Void

    @State private var loadState: LoadState = .loading
    @State private var showFontControls = false
    @State private var systemFonts: [String] = []

    @AppStorage("readerFontName") private var readerFontName = ""
    @AppStorage("readerFontSize") private var readerFontSize = 15

    private enum LoadState {
        case loading
        case loaded(AttributedString)
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            contentArea
        }
        .task(id: bookmark.id) {
            await loadContent()
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
            loadState = .loaded(content)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Rebuilds from cached HTML — no network fetch, no loading flash.
    private func rebuildContent() async {
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

            // Font / size controls
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
