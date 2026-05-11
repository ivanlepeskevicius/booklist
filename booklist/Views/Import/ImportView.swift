import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Query private var existingBookmarks: [Bookmark]
    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    // MARK: - State enums

    private enum Source { case browser, arc }

    private enum ViewState {
        case idle
        case loading(String)
        case preview([ImportService.ParsedBookmark])
        case reviewing
        case done(imported: Int, skipped: Int)
        case failed(String)
    }

    // MARK: - Navigation / source state

    @State private var source:         Source    = .browser
    @State private var state:          ViewState = .idle
    @State private var arcURL:         String    = ""
    @State private var isDropTargeted: Bool      = false

    // MARK: - Review flow state

    @State private var reviewItems: [ImportService.ParsedBookmark] = []
    @State private var reviewIndex: Int  = 0
    @State private var reviewSaved: Int  = 0
    @State private var fetchTask:   Task<Void, Never>? = nil

    // Per-item editable fields (reset when loading a new item)
    @State private var reviewTitle:         String    = ""
    @State private var reviewNote:          String    = ""
    @State private var reviewTags:          [Tag]     = []
    @State private var reviewIsWishlist:    Bool      = false
    @State private var reviewPrice:         String    = ""
    @State private var reviewFolderID:      UUID?     = nil
    @State private var reviewImages:        [String]  = []
    @State private var reviewSelectedImage: String?   = nil
    @State private var reviewFaviconURL:    String?   = nil
    @State private var reviewDescription:   String?   = nil
    @State private var reviewIsFetching:    Bool      = false

    @AppStorage("preferredCurrency") private var preferredCurrency = Locale.current.currency?.identifier ?? "USD"

    private enum ReviewField { case title, note, price }
    @FocusState private var reviewFocused: ReviewField?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if case .reviewing = state {
                reviewHeader
            } else {
                standardHeader
            }
            Divider()
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 580)
    }

    // MARK: - Headers

    private var standardHeader: some View {
        HStack {
            Text("Import Bookmarks")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var reviewHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Import")
                    .font(.headline)
                Spacer()
                Text("\(reviewIndex + 1) of \(reviewItems.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Cancel") { dismiss() }
                    .padding(.leading, 12)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(
                            width: geo.size.width
                                * CGFloat(reviewIndex + 1)
                                / CGFloat(max(reviewItems.count, 1))
                        )
                        .animation(.easeInOut(duration: 0.2), value: reviewIndex)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Main content switch

    @ViewBuilder
    private var mainContent: some View {
        switch state {
        case .idle:                idleView
        case .loading(let m):      loadingView(message: m)
        case .preview(let items):  previewView(bookmarks: items)
        case .reviewing:           reviewView
        case .done(let i, let s):  doneView(imported: i, skipped: s)
        case .failed(let m):       failedView(message: m)
        }
    }

    // MARK: - Idle (source picker)

    private var idleView: some View {
        VStack(spacing: 20) {
            Picker("Source", selection: $source) {
                Text("Browser").tag(Source.browser)
                Text("Arc Folder").tag(Source.arc)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)

            if source == .browser { browserInputView } else { arcInputView }

            Spacer()
        }
        .padding(20)
    }

    private var browserInputView: some View {
        VStack(spacing: 16) {
            Text("Export your bookmarks from Chrome, Firefox, Edge, or Safari as an HTML file, then drop it here or browse for it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [6])
                    )
                    .frame(height: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDropTargeted ? Color.accentColor.opacity(0.07) : Color.clear)
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDropTargeted)

                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Drop bookmarks.html here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Browse for File…") { browseForFile() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .onDrop(of: [UTType.html, UTType.fileURL, UTType.text], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
        }
    }

    private var arcInputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste an Arc shared folder link (e.g. arc.net/folder/…) and tap Fetch.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("https://arc.net/folder/…", text: $arcURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { fetchArc() }

                Button("Fetch") { fetchArc() }
                    .buttonStyle(.borderedProminent)
                    .disabled(arcURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("Arc lets you share a folder of pinned links from the sidebar. Open Arc → right-click a folder → Share.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Loading

    private func loadingView(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Preview

    private func previewView(bookmarks: [ImportService.ParsedBookmark]) -> some View {
        let existingURLs = Set(existingBookmarks.map(\.url))
        let newOnes  = bookmarks.filter { !existingURLs.contains($0.url) }
        let skipped  = bookmarks.count - newOnes.count

        return VStack(spacing: 0) {
            HStack {
                Text("\(bookmarks.count) found")
                    .font(.callout).fontWeight(.medium)
                if skipped > 0 {
                    Text("· \(skipped) already saved")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start over") { state = .idle }
                    .font(.callout)
                    .buttonStyle(.link)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            List(bookmarks) { bm in
                let isDuplicate = existingURLs.contains(bm.url)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bm.title)
                            .lineLimit(1)
                            .foregroundStyle(isDuplicate ? .secondary : .primary)
                        Text(bm.url)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        if let folder = bm.folderPath {
                            Text(folder)
                                .font(.caption2)
                                .foregroundStyle(.quaternary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if isDuplicate {
                        Text("Already saved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Spacer()
                Button("Review & Import \(newOnes.count) Bookmark\(newOnes.count == 1 ? "" : "s")") {
                    startReview(bookmarks)
                }
                .buttonStyle(.borderedProminent)
                .disabled(newOnes.isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: - Review (step-through)

    private var reviewView: some View {
        guard reviewItems.indices.contains(reviewIndex) else { return AnyView(EmptyView()) }
        let item = reviewItems[reviewIndex]
        let isLast = reviewIndex + 1 >= reviewItems.count

        return AnyView(
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // URL — read-only
                        VStack(alignment: .leading, spacing: 6) {
                            Label("URL", systemImage: "link")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(item.url)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Fetch spinner
                        if reviewIsFetching {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.8)
                                Text("Fetching page info…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Title
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Title", systemImage: "textformat")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("Title", text: $reviewTitle)
                                .textFieldStyle(.plain)
                                .focused($reviewFocused, equals: .title)
                                .padding(10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                .focusRing(when: reviewFocused == .title)
                        }

                        // Page description (auto-fetched)
                        if let desc = reviewDescription, !desc.isEmpty {
                            Text(desc)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Note
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Note", systemImage: "note.text")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("Why are you saving this? (optional)", text: $reviewNote, axis: .vertical)
                                .textFieldStyle(.plain)
                                .focused($reviewFocused, equals: .note)
                                .lineLimit(3...5)
                                .padding(10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                .focusRing(when: reviewFocused == .note)
                        }

                        // Tags
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Tags", systemImage: "tag")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TagPickerField(selectedTags: $reviewTags)
                        }

                        // Wishlist toggle + price
                        reviewWishlistSection

                        // Thumbnail picker (only shown when images are available)
                        if !reviewImages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Thumbnail", systemImage: "photo.on.rectangle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                ImagePickerGrid(imageURLs: reviewImages, selectedURL: $reviewSelectedImage)
                            }
                        }

                        // Custom image upload
                        ImageUploadZone { savedURL in
                            if !reviewImages.contains(savedURL) {
                                reviewImages.append(savedURL)
                            }
                            reviewSelectedImage = savedURL
                        }

                        // Folder picker
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Add to", systemImage: "folder")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Menu {
                                Button { reviewFolderID = nil } label: {
                                    Label("Inbox (no folder)", systemImage: "tray")
                                }
                                Divider()
                                ForEach(folderOptions, id: \.id) { option in
                                    Button { reviewFolderID = option.id } label: {
                                        Label(option.label, systemImage: option.icon)
                                    }
                                }
                            } label: {
                                HStack {
                                    let folder = reviewFolderID.flatMap { id in allFolders.first { $0.id == id } }
                                    Label(
                                        folder?.name ?? "Inbox",
                                        systemImage: folder?.icon ?? "tray"
                                    )
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                    .padding(20)
                }

                Divider()

                // Footer: Skip / Save
                HStack {
                    Button("Skip") { skipCurrentItem() }
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(isLast ? "Save & Finish" : "Save & Continue") {
                        saveCurrentItem()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        )
    }

    private var reviewWishlistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $reviewIsWishlist) {
                Label("Save as wishlist item", systemImage: "cart")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

            if reviewIsWishlist {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Price", systemImage: "tag")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("", text: $reviewPrice)
                            .textFieldStyle(.plain)
                            .focused($reviewFocused, equals: .price)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .focusRing(when: reviewFocused == .price)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: reviewIsWishlist)
    }

    // MARK: - Done

    private func doneView(imported: Int, skipped: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Import complete")
                .font(.title3).fontWeight(.semibold)
            if imported == 0 {
                Text("All items were skipped.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(imported) bookmark\(imported == 1 ? "" : "s") saved\(skipped > 0 ? ", \(skipped) skipped" : "").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title3).fontWeight(.semibold)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Try Again") { state = .idle }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File / Arc loading

    private func browseForFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.html, UTType.text]
        panel.allowsMultipleSelection = false
        panel.message = "Choose your browser bookmarks export file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(from: url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in loadFile(from: url) } }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier) { item, _ in
                if let data = item as? Data, let html = String(data: data, encoding: .utf8) {
                    Task { @MainActor in parseHTML(html) }
                }
            }
            return true
        }
        return false
    }

    private func loadFile(from url: URL) {
        state = .loading("Reading file…")
        Task {
            do {
                let html = try String(contentsOf: url, encoding: .utf8)
                parseHTML(html)
            } catch {
                state = .failed("Couldn't read the file: \(error.localizedDescription)")
            }
        }
    }

    private func parseHTML(_ html: String) {
        state = .loading("Parsing bookmarks…")
        Task.detached(priority: .userInitiated) {
            let parsed = ImportService.parseNetscapeHTML(html)
            await MainActor.run {
                if parsed.isEmpty {
                    state = .failed("No bookmarks found in that file. Make sure you exported in HTML format.")
                } else {
                    state = .preview(parsed)
                }
            }
        }
    }

    private func fetchArc() {
        let trimmed = arcURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        state = .loading("Fetching Arc folder…")
        Task {
            do {
                let parsed = try await ImportService.fetchArcFolder(urlString: trimmed)
                state = .preview(parsed)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Review actions

    private func startReview(_ bookmarks: [ImportService.ParsedBookmark]) {
        let existingURLs = Set(existingBookmarks.map(\.url))
        reviewItems = bookmarks.filter { !existingURLs.contains($0.url) }
        reviewIndex = 0
        reviewSaved = 0
        guard !reviewItems.isEmpty else {
            state = .done(imported: 0, skipped: bookmarks.count)
            return
        }
        state = .reviewing
        loadItem(at: 0)
    }

    private func loadItem(at index: Int) {
        guard reviewItems.indices.contains(index) else { return }
        let item = reviewItems[index]

        // Reset all per-item state
        reviewTitle         = item.title
        reviewNote          = ""
        reviewTags          = []
        reviewIsWishlist    = false
        reviewPrice         = ""
        reviewFolderID      = nil
        reviewImages        = []
        reviewSelectedImage = nil
        reviewFaviconURL    = nil
        reviewDescription   = nil
        reviewIsFetching    = true

        // Cancel any in-flight fetch from the previous item
        fetchTask?.cancel()
        fetchTask = Task {
            do {
                let meta = try await MetadataFetcher.fetch(urlString: item.url)
                guard !Task.isCancelled,
                      reviewItems.indices.contains(reviewIndex),
                      reviewItems[reviewIndex].url == item.url else { return }
                if !meta.title.isEmpty { reviewTitle = meta.title }
                reviewDescription   = meta.description
                reviewFaviconURL    = meta.faviconURL
                reviewImages        = meta.imageURLs
                reviewSelectedImage = meta.imageURLs.first
                if let price = meta.price, !price.isEmpty {
                    reviewIsWishlist = true
                    reviewPrice      = price
                }
            } catch {}
            reviewIsFetching = false
        }
    }

    private func saveCurrentItem() {
        guard reviewItems.indices.contains(reviewIndex) else { return }
        let item   = reviewItems[reviewIndex]
        let folder = reviewFolderID.flatMap { id in allFolders.first { $0.id == id } }

        let bookmark = Bookmark(
            title:            reviewTitle.isEmpty ? item.url : reviewTitle,
            url:              item.url,
            pageDescription:  reviewDescription,
            note:             reviewNote.isEmpty ? nil : reviewNote,
            faviconURL:       reviewFaviconURL,
            imageURLs:        reviewImages,
            selectedImageURL: reviewSelectedImage,
            itemType:         reviewIsWishlist ? .wishlistItem : .bookmark,
            price:            reviewIsWishlist && !reviewPrice.isEmpty ? reviewPrice : nil,
            collection:       folder,
            tags:             reviewTags
        )
        modelContext.insert(bookmark)
        reviewSaved += 1
        advance()
    }

    private func skipCurrentItem() {
        advance()
    }

    private func advance() {
        fetchTask?.cancel()
        let next = reviewIndex + 1
        if next < reviewItems.count {
            reviewIndex = next
            loadItem(at: next)
        } else {
            let skipped = reviewItems.count - reviewSaved
            state = .done(imported: reviewSaved, skipped: skipped)
        }
    }

    // MARK: - Helpers

    private var folderOptions: [(id: UUID, label: String, icon: String)] {
        var result: [(id: UUID, label: String, icon: String)] = []
        func walk(_ folder: Folder, prefix: String) {
            let label = prefix.isEmpty ? folder.name : "\(prefix) › \(folder.name)"
            result.append((id: folder.id, label: label, icon: folder.icon))
            for child in (folder.childrenIfAny ?? []) { walk(child, prefix: label) }
        }
        allFolders.filter { $0.parent == nil }.forEach { walk($0, prefix: "") }
        return result
    }

    private var currencySymbol: String {
        let symbols: [String: String] = [
            "AUD": "A$", "BRL": "R$", "CAD": "CA$", "CHF": "Fr",
            "CNY": "¥",  "DKK": "kr", "EUR": "€",   "GBP": "£",
            "INR": "₹",  "JPY": "¥",  "KRW": "₩",   "MXN": "MX$",
            "NOK": "kr", "PLN": "zł", "SEK": "kr",   "USD": "$",
        ]
        return symbols[preferredCurrency] ?? preferredCurrency
    }
}
