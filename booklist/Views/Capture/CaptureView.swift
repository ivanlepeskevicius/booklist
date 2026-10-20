import SwiftUI
import SwiftData

struct CaptureView: View {
    /// Pre-filled when the view is opened via a deep link or Share Extension.
    var initialURL:   String = ""
    var initialTitle: String = ""

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allBookmarks: [Bookmark]
    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    // ── Form state ───────────────────────────────────────────────
    @State private var urlString       = ""
    @State private var title           = ""
    @State private var note            = ""
    @State private var selectedImageURL: String?
    @State private var candidateImages: [String] = []
    @State private var pageDescription: String?
    @State private var faviconURL:      String?

    // ── Fetch state ──────────────────────────────────────────────
    @State private var isFetching  = false
    @State private var fetchError: String?
    @State private var hasFetched  = false

    // ── Selection state ──────────────────────────────────────────
    @State private var selectedFolderID: UUID?
    @State private var selectedTags: [Tag] = []
    @State private var isWishlistItem  = false
    /// Set once the user flips the wishlist toggle; automatic defaults never override it.
    @State private var wishlistChosenByUser = false
    @State private var price           = ""
    @State private var managingDuplicate: Bookmark? = nil
    @State private var showingNewFolder  = false

    @AppStorage("preferredCurrency") private var preferredCurrency = Locale.current.currency?.identifier ?? "USD"

    // ── Focus ────────────────────────────────────────────────────
    private enum Field { case url, title, note, price }
    @FocusState private var focused: Field?

    // ── Debounce ─────────────────────────────────────────────────
    @State private var fetchTask:      Task<Void, Never>?
    @State private var screenshotTask: Task<Void, Never>?

    // ── Computed ─────────────────────────────────────────────────

    /// The URL as it will actually be stored/fetched — adds https:// when the user omits the scheme.
    private var effectiveURL: String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://"))
            ? trimmed
            : "https://" + trimmed
    }

    // Title is optional — save() falls back to the URL when it's empty.
    private var canSave: Bool { !effectiveURL.isEmpty }

    private var currencySymbol: String {
        let symbols: [String: String] = [
            "AUD": "A$", "BRL": "R$", "CAD": "CA$", "CHF": "Fr",
            "CNY": "¥",  "DKK": "kr", "EUR": "€",   "GBP": "£",
            "INR": "₹",  "JPY": "¥",  "KRW": "₩",   "MXN": "MX$",
            "NOK": "kr", "PLN": "zł", "SEK": "kr",   "USD": "$",
        ]
        return symbols[preferredCurrency] ?? preferredCurrency
    }

    /// Stores the price in the preferred currency, whatever currency text was typed or scraped.
    private func formattedPrice(_ raw: String) -> String {
        PriceFormatter.normalized(raw, symbol: currencySymbol)
    }

    /// Strips scheme, trailing slash, and lowercases so "https://Example.com/" == "http://example.com".
    private func normalisedURL(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)); break }
        }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }

    /// Non-nil when the current URL already exists in the library.
    private var duplicateBookmark: Bookmark? {
        guard !effectiveURL.isEmpty else { return nil }
        let target = normalisedURL(effectiveURL)
        return allBookmarks.first { normalisedURL($0.url) == target }
    }

    private var selectedFolder: Folder? {
        allFolders.first { $0.id == selectedFolderID }
    }

    /// All folders flattened to "Parent › Child" labels, for the picker menu.
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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    urlField
                    organizationSection
                    if let dup = duplicateBookmark {
                        duplicateBanner(dup)
                    } else {
                        if let error = fetchError {
                            errorBanner(error)
                        }
                        if hasFetched {
                            titleField
                            if let desc = pageDescription, !desc.isEmpty {
                                pageDescriptionView(desc)
                            }
                            wishlistSection
                            noteField
                            tagsSection
                            thumbnailSection
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 480)
        .frame(minHeight: 300, maxHeight: 700)
        .sheet(item: $managingDuplicate) { bookmark in
            ManagePanelView(bookmark: bookmark)
        }
        .sheet(isPresented: $showingNewFolder) {
            FolderFormView(mode: .add(parentID: nil)) { newFolder in
                selectedFolderID = newFolder.id
            }
        }
        // When opened via deep link / Share Extension, pre-fill and fetch immediately.
        .task {
            guard !initialURL.isEmpty else {
                // Most captures start right after copying a link — pre-fill it.
                // Setting urlString triggers the debounced fetch via onChange.
                if let clip = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   clip.hasPrefix("https://") || clip.hasPrefix("http://"),
                   !clip.contains(where: \.isWhitespace) {
                    urlString = clip
                }
                return
            }
            urlString = initialURL
            if !initialTitle.isEmpty { title = initialTitle }
            // Yield one cycle so the URL field renders before the spinner appears.
            try? await Task.sleep(for: .milliseconds(50))
            await fetchMetadata(for: effectiveURL)
        }
        .onDisappear {
            screenshotTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "link.badge.plus")
                .font(.title3)
                .foregroundColor(.accentColor)
            Text("New Capture")
                .font(.headline)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("URL", systemImage: "link")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Paste a link…", text: $urlString)
                    .textFieldStyle(.plain)
                    .focused($focused, equals: .url)
                    .textContentType(.URL)
                    .onSubmit { triggerFetch(for: effectiveURL) }
                    .onChange(of: urlString) { _, _ in
                        // Require at least a partial domain (contains a dot) before fetching
                        let url = effectiveURL
                        guard url.contains("."), urlString.count >= 4 else { return }
                        scheduleFetch(for: url)
                    }

                if isFetching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .focusRing(when: focused == .url)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func duplicateBanner(_ existing: Bookmark) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.doc.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Already in your library")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(existing.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("View Item") {
                managingDuplicate = existing
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Title", systemImage: "textformat")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Page title", text: $title)
                .textFieldStyle(.plain)
                .focused($focused, equals: .title)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .focusRing(when: focused == .title)
        }
    }

    private func pageDescriptionView(_ desc: String) -> some View {
        Text(desc)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Note", systemImage: "note.text")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NoteEditor(text: $note, placeholder: "Why are you saving this? (optional)")
                .focused($focused, equals: .note)
                .frame(minHeight: 60, maxHeight: 110)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .focusRing(when: focused == .note)
        }
    }

    private var thumbnailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Thumbnail", systemImage: "photo.on.rectangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !candidateImages.isEmpty {
                ImagePickerGrid(imageURLs: candidateImages, selectedURL: $selectedImageURL)
            }

            ImageUploadZone { savedURL in
                if !candidateImages.contains(savedURL) {
                    candidateImages.append(savedURL)
                }
                selectedImageURL = savedURL
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tags", systemImage: "tag")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TagPickerField(selectedTags: $selectedTags)
        }
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Add to", systemImage: "folder")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Menu {
                // New Folder first — the folder list below grows, this should stay one click away.
                Button {
                    showingNewFolder = true
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }
                Divider()
                Button {
                    selectedFolderID = nil
                } label: {
                    Label("Inbox (no folder)", systemImage: "tray")
                }
                if !folderOptions.isEmpty { Divider() }
                ForEach(folderOptions, id: \.id) { option in
                    Button {
                        selectedFolderID = option.id
                    } label: {
                        Label(option.label, systemImage: option.icon)
                    }
                }
            } label: {
                HStack {
                    Label(
                        selectedFolder?.name ?? "Inbox",
                        systemImage: selectedFolder?.icon ?? "tray"
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

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { isWishlistItem },
                set: { isWishlistItem = $0; wishlistChosenByUser = true }
            )) {
                Label("Save as wishlist item", systemImage: "cart")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)

            // When a price was auto-detected but the toggle is off, show a hint
            // so the user knows the value is waiting for them.
            if !isWishlistItem && !price.isEmpty {
                Label("Price found: \(formattedPrice(price)) — turn on to save it", systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            // Full price field when wishlist is enabled
            if isWishlistItem {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Price", systemImage: "tag")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("", text: $price)
                            .textFieldStyle(.plain)
                            .focused($focused, equals: .price)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .focusRing(when: focused == .price)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isWishlistItem)
        .animation(.easeInOut(duration: 0.15), value: price.isEmpty)
    }

    private var footer: some View {
        HStack {
            if let folder = selectedFolder {
                Label(folder.name, systemImage: folder.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.escape)
            // ⌘Return, not plain Return — Return must insert a newline in the multi-line note field.
            Button(isWishlistItem ? "Save to Wishlist" : "Save Bookmark") { save() }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Save (⌘↩)")
                .buttonStyle(.borderedProminent)
                .disabled(!canSave || duplicateBookmark != nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Fetch logic

    private func scheduleFetch(for url: String) {
        hasFetched = false
        fetchError = nil
        fetchTask?.cancel()
        screenshotTask?.cancel()
        fetchTask = Task {
            // Debounce — wait for the user to stop typing
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            triggerFetch(for: url)
        }
    }

    @MainActor
    private func triggerFetch(for urlString: String) {
        guard !urlString.isEmpty, urlString.contains(".") else { return }
        fetchTask?.cancel()
        screenshotTask?.cancel()
        fetchTask = Task { await fetchMetadata(for: urlString) }
    }

    @MainActor
    private func fetchMetadata(for urlString: String) async {
        isFetching = true
        fetchError = nil
        // Shop links default to wishlist — decided before fetching so it applies even if the
        // shop blocks the request. Recomputed for every new URL (so a shop link followed by a
        // blog link turns it back off), unless the user has set the toggle themselves.
        if !wishlistChosenByUser {
            let isAmazon = URL(string: urlString).map(MetadataFetcher.isAmazonURL) ?? false
            let saved = allBookmarks.map { (url: $0.url, isWishlist: $0.itemType == .wishlistItem, dateAdded: $0.dateAdded) }
            isWishlistItem = isAmazon || WishlistSites.lastChoiceWasWishlist(for: urlString, savedItems: saved)
        }

        do {
            let meta = try await MetadataFetcher.fetch(urlString: urlString)
            if meta.isProductPage && !wishlistChosenByUser { isWishlistItem = true }
            title            = meta.title
            pageDescription  = meta.description
            faviconURL       = meta.faviconURL
            candidateImages  = meta.imageURLs
            selectedImageURL = meta.imageURLs.first
            // Pre-fill price if the page has structured pricing data. Only the amount is kept —
            // the field already shows the preferred currency symbol in front of it.
            if let extractedPrice = meta.price, !extractedPrice.isEmpty {
                price = PriceFormatter.amount(in: extractedPrice) ?? extractedPrice
            }
            // Synthesize a post card image for Reddit (text posts have no remote thumbnail)
            if let subreddit = meta.redditSubreddit {
                await generateRedditCard(
                    title: meta.title,
                    body: meta.description,
                    subreddit: subreddit,
                    author: meta.redditAuthor ?? ""
                )
            }
            hasFetched = true
            // If no images were found by any means, take a screenshot as fallback
            if candidateImages.isEmpty {
                screenshotTask = Task {
                    if let localURL = await ScreenshotService.capture(urlString: urlString),
                       !Task.isCancelled {
                        candidateImages = [localURL]
                        selectedImageURL = localURL
                    }
                }
            }
        } catch {
            fetchError = error.localizedDescription
            // Still let the user save manually
            hasFetched = true
        }

        isFetching = false
    }

    // MARK: - Reddit card

    @MainActor
    private func generateRedditCard(title: String, body: String?, subreddit: String, author: String) async {
        let card = RedditPostCard(title: title, postBody: body, subreddit: subreddit, author: author)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0
        guard let image = renderer.nsImage,
              let savedURL = try? ImageStore.save(image) else { return }
        // Posts with their own images keep those selected; the card stays available in the picker.
        if candidateImages.isEmpty {
            candidateImages = [savedURL]
            selectedImageURL = savedURL
        } else {
            candidateImages.append(savedURL)
        }
    }

    // MARK: - Save

    private func save() {
        let tags   = selectedTags
        let folder = selectedFolder
        let imageToDownload = selectedImageURL

        let bookmark = Bookmark(
            title: title.isEmpty ? effectiveURL : title,
            url: effectiveURL,
            pageDescription: pageDescription,
            note: note.isEmpty ? nil : note,
            faviconURL: faviconURL,
            imageURLs: candidateImages,
            selectedImageURL: selectedImageURL,
            itemType: isWishlistItem ? .wishlistItem : .bookmark,
            price: isWishlistItem && !price.isEmpty ? formattedPrice(price) : nil,
            collection: folder,
            tags: tags
        )
        modelContext.insert(bookmark)

        // Download the selected remote image to local storage so it survives app relaunches
        if let remote = imageToDownload,
           let remoteURL = URL(string: remote),
           remoteURL.scheme == "https" || remoteURL.scheme == "http" {
            Task {
                if let localURL = try? await ImageStore.download(from: remoteURL) {
                    bookmark.selectedImageURL = localURL
                }
            }
        }

        dismiss()
    }
}

// MARK: - Reddit post card (used by ImageRenderer to generate a thumbnail)

private struct RedditPostCard: View {
    let title: String
    let postBody: String?
    let subreddit: String
    let author: String

    private let redditOrange = Color(red: 1.0, green: 0.27, blue: 0.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(redditOrange)
                    .font(.system(size: 12))
                Text("r/\(subreddit)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(redditOrange)
                Spacer()
                if !author.isEmpty {
                    Text("u/\(author)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.45))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(white: 0.96))

            // Content
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.10))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let postBody, !postBody.isEmpty {
                    Text(postBody)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.35))
                        .lineLimit(7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .frame(width: 560)
    }
}
