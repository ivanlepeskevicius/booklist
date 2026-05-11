import SwiftUI
import SwiftData

/// Sheet that lets the user view and edit all details of a saved bookmark.
struct ManagePanelView: View {
    @Bindable var bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    var body: some View {
        NavigationStack {
            Form {
                // ── Core details ─────────────────────────────────
                Section("Details") {
                    LabeledContent("Title") {
                        TextField("", text: $bookmark.title)
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
                    Picker("Type", selection: $bookmark.itemType) {
                        Text("Bookmark").tag(ItemType.bookmark)
                        Text("Wishlist item").tag(ItemType.wishlistItem)
                    }
                    .pickerStyle(.segmented)

                    if bookmark.itemType == .wishlistItem {
                        LabeledContent("Price") {
                            TextField(
                                "e.g. €29.99",
                                text: Binding(
                                    get: { bookmark.price ?? "" },
                                    set: { bookmark.price = $0.isEmpty ? nil : $0 }
                                )
                            )
                        }
                    }
                }

                // ── Metadata (read-only) ──────────────────────────
                if let desc = bookmark.pageDescription, !desc.isEmpty {
                    Section("Page Description") {
                        Text(desc)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }

                // ── Save date ─────────────────────────────────────
                Section {
                    LabeledContent("Saved") {
                        Text(bookmark.dateAdded.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Bookmark")
            .navigationSubtitle(URL(string: bookmark.url)?.host ?? "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
