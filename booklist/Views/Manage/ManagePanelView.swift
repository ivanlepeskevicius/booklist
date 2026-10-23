import SwiftUI
import SwiftData

/// Sheet that lets the user view and edit all details of a saved bookmark.
///
/// Text fields and the thumbnail choice edit a `Draft`, saved to the bookmark 0.6 s after the user
/// stops typing and when the panel closes. Writing to the bookmark on every keystroke made every
/// view that shows the library recompute (measured on a tester's 1,027-item library: 138 ms per
/// typed character, 274 ms after scrolling masonry to the end — the app fell behind and hung).
struct ManagePanelView: View {
    @Bindable var bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    @State private var showingNewFolder = false
    @State private var draft: Draft

    /// The fields edited by typing or picking — everything else (folder, tags, type) is a single
    /// click and is written straight to the bookmark.
    struct Draft: Equatable {
        var title: String
        var url: String
        var note: String
        var price: String
        var selectedImageURL: String?

        init(_ bookmark: Bookmark) {
            title = bookmark.title
            url = bookmark.url
            note = bookmark.note ?? ""
            price = bookmark.price ?? ""
            selectedImageURL = bookmark.selectedImageURL
        }
    }

    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        _draft = State(initialValue: Draft(bookmark))
    }

    @AppStorage("preferredCurrency") private var preferredCurrency = Locale.current.currency?.identifier ?? "USD"

    private var currencySymbol: String {
        let symbols: [String: String] = [
            "AUD": "A$", "BRL": "R$", "CAD": "CA$", "CHF": "Fr",
            "CNY": "¥",  "DKK": "kr", "EUR": "€",   "GBP": "£",
            "INR": "₹",  "JPY": "¥",  "KRW": "₩",   "MXN": "MX$",
            "NOK": "kr", "PLN": "zł", "SEK": "kr",   "USD": "$",
        ]
        return symbols[preferredCurrency] ?? preferredCurrency
    }

    var body: some View {
        NavigationStack {
            // Custom layout instead of Form — same reasoning as FolderFormView:
            // .formStyle(.grouped) forces right-aligned TextFields and clips the
            // TagPickerField dropdown, making notes and tags impossible to edit.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    locationGroup
                    detailsGroup
                    tagsGroup
                        .zIndex(2)   // lets the tag dropdown float above the section below
                    typeGroup
                    thumbnailGroup
                    infoGroup
                }
                .padding(20)
            }
            .navigationTitle(bookmark.itemType == .wishlistItem ? "Edit Wishlist Item" : "Edit Bookmark")
            .navigationSubtitle(URL(string: bookmark.url)?.host ?? "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !draft.price.isEmpty {
                            draft.price = PriceFormatter.normalized(draft.price, symbol: currencySymbol)
                        }
                        commit()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        // Save shortly after the last change (the task restarts on every edit), and always on close.
        .task(id: draft) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commit()
        }
        .onDisappear { commit() }
        .sheet(isPresented: $showingNewFolder) {
            FolderFormView(mode: .add(parentID: nil)) { newFolder in
                bookmark.collection = newFolder
            }
        }
    }

    // MARK: - Section groups

    private var detailsGroup: some View {
        formGroup(title: "Details") {
            VStack(spacing: 0) {
                rowField("Title", text: $draft.title)
                rowDivider
                rowField("URL", text: $draft.url)
                if let desc = bookmark.pageDescription, !desc.isEmpty {
                    rowDivider
                    stackedField(label: "Description") {
                        Text(desc)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                rowDivider
                stackedField(label: "Note") {
                    NoteEditor(text: $draft.note, placeholder: "Add a note…")
                    .frame(minHeight: 60, maxHeight: 160)
                }
            }
        }
    }

    private var tagsGroup: some View {
        formGroup(title: "Tags") {
            TagPickerField(selectedTags: $bookmark.tags)
                .padding(10)
        }
    }

    private var locationGroup: some View {
        formGroup(title: "Location") {
            Menu {
                // New Folder first — the folder list below grows, this should stay one click away.
                Button {
                    showingNewFolder = true
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }
                Divider()
                Button {
                    bookmark.collection = nil
                } label: {
                    Label("Inbox (no folder)", systemImage: "tray")
                }
                if !allFolders.isEmpty { Divider() }
                ForEach(FolderTree.flattened(allFolders), id: \.folder.id) { entry in
                    Button {
                        bookmark.collection = entry.folder
                    } label: {
                        Label(entry.path, systemImage: entry.folder.icon)
                    }
                }
            } label: {
                HStack {
                    Label(
                        bookmark.collection?.name ?? "Inbox",
                        systemImage: bookmark.collection?.icon ?? "tray"
                    )
                    .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.leading, 10)
        }
    }

    private var typeGroup: some View {
        formGroup(title: "Type") {
            VStack(spacing: 0) {
                Picker("", selection: $bookmark.itemType) {
                    Text("Bookmark").tag(ItemType.bookmark)
                    Text("Wishlist item").tag(ItemType.wishlistItem)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(10)

                if bookmark.itemType == .wishlistItem {
                    rowDivider
                    rowField("Price", text: $draft.price)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: bookmark.itemType)
        }
    }

    private var thumbnailGroup: some View {
        formGroup(title: "Thumbnail") {
            VStack(alignment: .leading, spacing: 10) {
                if !bookmark.imageURLs.isEmpty {
                    ImagePickerGrid(
                        imageURLs: bookmark.imageURLs,
                        selectedURL: $draft.selectedImageURL,
                        scrollable: false
                    )
                }
                ImageUploadZone { savedURL in
                    if !bookmark.imageURLs.contains(savedURL) {
                        bookmark.imageURLs.append(savedURL)
                    }
                    draft.selectedImageURL = savedURL
                }
            }
            .padding(10)
        }
    }

    private var infoGroup: some View {
        formGroup(title: "Info") {
            VStack(spacing: 0) {
                infoRow("Saved", value: bookmark.dateAdded.formatted(date: .long, time: .shortened))
                rowDivider
                infoRow(
                    "Last Opened",
                    value: bookmark.lastOpenedDate?.formatted(date: .long, time: .shortened) ?? "Never"
                )
            }
        }
    }

    // MARK: - Saving

    /// Writes only the fields that changed, so an unchanged draft doesn't touch the bookmark.
    private func commit() {
        guard bookmark.isAlive else { return }
        if bookmark.title != draft.title { bookmark.title = draft.title }
        if bookmark.url != draft.url { bookmark.url = draft.url }
        let note = draft.note.isEmpty ? nil : draft.note
        if bookmark.note != note { bookmark.note = note }
        let price = draft.price.isEmpty ? nil : draft.price
        if bookmark.price != price { bookmark.price = price }
        if bookmark.selectedImageURL != draft.selectedImageURL { bookmark.selectedImageURL = draft.selectedImageURL }
    }

    // MARK: - Row helpers

    /// Inline label + single-line TextField row.
    private func rowField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            TextField("", text: text)
                .textFieldStyle(.plain)
        }
        .padding(10)
    }

    /// Stacked label above arbitrary content (multiline text, read-only text, etc).
    @ViewBuilder
    private func stackedField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 10)
    }

    // MARK: - Section container

    @ViewBuilder
    private func formGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
