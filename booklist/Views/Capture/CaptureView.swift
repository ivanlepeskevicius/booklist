import SwiftUI
import SwiftData

struct CaptureView: View {
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]
    @Query(sort: \Tag.name)         private var allTags:    [Tag]

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
    @State private var selectedTagIDs = Set<UUID>()

    // ── Debounce ─────────────────────────────────────────────────
    @State private var fetchTask: Task<Void, Never>?

    // ── Computed ─────────────────────────────────────────────────
    private var canSave: Bool { !urlString.isEmpty && !title.isEmpty }

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
                    if let error = fetchError {
                        errorBanner(error)
                    }
                    if hasFetched {
                        titleField
                        noteField
                        if !candidateImages.isEmpty {
                            thumbnailSection
                        }
                        Divider()
                        organizationSection
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 480)
        .frame(minHeight: 300, maxHeight: 700)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "link.badge.plus")
                .font(.title3)
                .foregroundStyle(.accent)
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
                    .textContentType(.URL)
                    .onSubmit { triggerFetch(for: urlString) }
                    .onChange(of: urlString) { _, newValue in
                        guard newValue.starts(with: "http") else { return }
                        scheduleFetch(for: newValue)
                    }

                if isFetching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Title", systemImage: "textformat")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Page title", text: $title)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Note", systemImage: "note.text")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Why are you saving this? (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...5)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var thumbnailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Thumbnail — tap to choose", systemImage: "photo.on.rectangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ImagePickerGrid(imageURLs: candidateImages, selectedURL: $selectedImageURL)
        }
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Collection picker
            VStack(alignment: .leading, spacing: 6) {
                Label("Add to", systemImage: "folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Menu {
                    Button {
                        selectedFolderID = nil
                    } label: {
                        Label("Inbox (no folder)", systemImage: "tray")
                    }
                    Divider()
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

            // Tag picker
            if !allTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Tags", systemImage: "tag")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(allTags) { tag in
                                let isSelected = selectedTagIDs.contains(tag.id)
                                Button {
                                    if isSelected { selectedTagIDs.remove(tag.id) }
                                    else          { selectedTagIDs.insert(tag.id) }
                                } label: {
                                    Text("#\(tag.name)")
                                        .font(.caption)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            isSelected
                                                ? Color(hex: tag.color)
                                                : Color(hex: tag.color).opacity(0.15),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(isSelected ? .white : Color(hex: tag.color))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
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
            Button("Save Bookmark") { save() }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Fetch logic

    private func scheduleFetch(for url: String) {
        hasFetched = false
        fetchError = nil
        fetchTask?.cancel()
        fetchTask = Task {
            // Debounce — wait for the user to stop typing
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await triggerFetch(for: url)
        }
    }

    @MainActor
    private func triggerFetch(for urlString: String) {
        guard !urlString.isEmpty, urlString.starts(with: "http") else { return }
        fetchTask?.cancel()
        fetchTask = Task { await fetchMetadata(for: urlString) }
    }

    @MainActor
    private func fetchMetadata(for urlString: String) async {
        isFetching = true
        fetchError = nil

        do {
            let meta = try await MetadataFetcher.fetch(urlString: urlString)
            title            = meta.title
            pageDescription  = meta.description
            faviconURL       = meta.faviconURL
            candidateImages  = meta.imageURLs
            selectedImageURL = meta.imageURLs.first
            hasFetched       = true
        } catch {
            fetchError = error.localizedDescription
            // Still let the user save manually
            hasFetched = true
        }

        isFetching = false
    }

    // MARK: - Save

    private func save() {
        let tags   = allTags.filter { selectedTagIDs.contains($0.id) }
        let folder = selectedFolder

        let bookmark = Bookmark(
            title: title.isEmpty ? urlString : title,
            url: urlString,
            pageDescription: pageDescription,
            note: note.isEmpty ? nil : note,
            faviconURL: faviconURL,
            imageURLs: candidateImages,
            selectedImageURL: selectedImageURL,
            collection: folder,
            tags: tags
        )
        modelContext.insert(bookmark)
        dismiss()
    }
}
