import SwiftUI
import SwiftData

/// Sheet that lets the user view and edit all details of a saved bookmark.
struct ManagePanelView: View {
    @Bindable var bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    @State private var showingNewFolder = false

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
                    detailsGroup
                    tagsGroup
                        .zIndex(2)   // lets the tag dropdown float above the section below
                    locationGroup
                    typeGroup
                    thumbnailGroup
                    infoGroup
                }
                .padding(20)
            }
            .navigationTitle("Edit Bookmark")
            .navigationSubtitle(URL(string: bookmark.url)?.host ?? "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let raw = bookmark.price, !raw.isEmpty,
                           let first = raw.first, first.isNumber {
                            bookmark.price = currencySymbol + raw
                        }
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
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
                rowField("Title", text: $bookmark.title)
                rowDivider
                rowField("URL", text: $bookmark.url)
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
                    TextField(
                        "Add a note…",
                        text: Binding(
                            get: { bookmark.note ?? "" },
                            set: { bookmark.note = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .lineLimit(3...8)
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
                Button {
                    bookmark.collection = nil
                } label: {
                    Label("Inbox (no folder)", systemImage: "tray")
                }
                Divider()
                ForEach(allFolders) { folder in
                    Button {
                        bookmark.collection = folder
                    } label: {
                        Label(folderDisplayPath(folder), systemImage: folder.icon)
                    }
                }
                if !allFolders.isEmpty { Divider() }
                Button {
                    showingNewFolder = true
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
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
                    rowField("Price", text: Binding(
                        get: { bookmark.price ?? "" },
                        set: { bookmark.price = $0.isEmpty ? nil : $0 }
                    ))
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
                        selectedURL: Binding(
                            get: { bookmark.selectedImageURL },
                            set: { bookmark.selectedImageURL = $0 }
                        ),
                        scrollable: false
                    )
                }
                ImageUploadZone { savedURL in
                    if !bookmark.imageURLs.contains(savedURL) {
                        bookmark.imageURLs.append(savedURL)
                    }
                    bookmark.selectedImageURL = savedURL
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

    // MARK: - Helpers

    private func folderDisplayPath(_ folder: Folder) -> String {
        var parts = [folder.name]
        var current = folder
        while let parent = current.parent {
            parts.insert(parent.name, at: 0)
            current = parent
        }
        return parts.joined(separator: " › ")
    }
}
