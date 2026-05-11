import SwiftUI
import SwiftData

/// Sheet that lets the user view and edit all details of a saved bookmark.
struct ManagePanelView: View {
    @Bindable var bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

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
            Form {
                // ── Core details ─────────────────────────────────
                Section("Details") {
                    LabeledContent("Title") {
                        TextField("", text: $bookmark.title)
                    }

                    if let desc = bookmark.pageDescription, !desc.isEmpty {
                        LabeledContent("Description") {
                            Text(desc)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .lineLimit(4)
                        }
                    }

                    LabeledContent("URL") {
                        TextField("", text: $bookmark.url)
                            .textContentType(.URL)
                    }

                    LabeledContent("Note") {
                        TextField(
                            "",
                            text: Binding(
                                get: { bookmark.note ?? "" },
                                set: { bookmark.note = $0.isEmpty ? nil : $0 }
                            ),
                            axis: .vertical
                        )
                        .lineLimit(3...8)
                    }
                }

                // ── Tags ──────────────────────────────────────────
                Section("Tags") {
                    TagPickerField(selectedTags: $bookmark.tags)
                }

                // ── Location ──────────────────────────────────────
                Section("Location") {
                    Picker("Folder", selection: Binding<UUID?>(
                        get: { bookmark.collection?.id },
                        set: { id in
                            bookmark.collection = id.flatMap { uuid in
                                allFolders.first { $0.id == uuid }
                            }
                        }
                    )) {
                        Label("Inbox", systemImage: "tray")
                            .tag(nil as UUID?)
                        Divider()
                        ForEach(allFolders) { folder in
                            Label(folderDisplayPath(folder), systemImage: folder.icon)
                                .tag(folder.id as UUID?)
                        }
                    }
                }

                // ── Item type ─────────────────────────────────────
                Section("Type") {
                    Picker("", selection: $bookmark.itemType) {
                        Text("Bookmark").tag(ItemType.bookmark)
                        Text("Wishlist item").tag(ItemType.wishlistItem)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if bookmark.itemType == .wishlistItem {
                        LabeledContent("Price") {
                            TextField(
                                "",
                                text: Binding(
                                    get: { bookmark.price ?? "" },
                                    set: { bookmark.price = $0.isEmpty ? nil : $0 }
                                )
                            )
                        }
                    }
                }

                // ── Thumbnail ─────────────────────────────────────
                Section("Thumbnail") {
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
                }

                // ── Save date / activity ─────────────────────────
                Section {
                    LabeledContent("Saved") {
                        Text(bookmark.dateAdded.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Last Opened") {
                        if let date = bookmark.lastOpenedDate {
                            Text(date.formatted(date: .long, time: .shortened))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Bookmark")
            .navigationSubtitle(URL(string: bookmark.url)?.host ?? "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Prepend currency symbol if the user typed a bare number
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
    }

    /// Builds a full breadcrumb path like "Design › UI Components" for nested folders.
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
