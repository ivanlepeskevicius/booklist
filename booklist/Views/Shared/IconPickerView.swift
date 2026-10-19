import SwiftUI

// MARK: - Helper (module-internal so FolderRowView / FolderFormView can use it)

/// Returns true when `s` is an SF Symbol name (all-ASCII), false for emoji or other Unicode.
func isSFSymbolName(_ s: String) -> Bool {
    !s.isEmpty && s.unicodeScalars.allSatisfy(\.isASCII)
}

// MARK: - IconPickerView

/// A button that shows the current icon and opens a searchable symbol / emoji
/// picker popover when tapped.
struct IconPickerView: View {
    @Binding var selectedIcon: String

    @State private var isShowingPopover = false
    @State private var search = ""

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isShowingPopover.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        .frame(width: 48, height: 48)
                    iconView(selectedIcon.isEmpty ? "folder" : selectedIcon, size: 22, color: .accentColor)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPopover) {
                IconGridPopover(selectedIcon: $selectedIcon, search: $search) {
                    isShowingPopover = false
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedIcon.isEmpty ? "folder" : selectedIcon)
                    .font(.callout)
                Text("Tap the icon to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Folder-friendly picks shown first, above the full catalogue.
    static let suggestedSymbols = [
        "folder", "folder.fill", "tray", "archivebox", "document", "bookmark", "star", "heart",
        "tag", "flag", "pin", "house", "briefcase", "cart", "bag", "gift",
        "book", "graduationcap", "lightbulb", "sparkles", "globe", "airplane", "fork.knife", "cup.and.saucer",
        "music.note", "photo", "film", "gamecontroller", "paintpalette", "hammer", "leaf", "pawprint",
    ]
}

// MARK: - Shared icon rendering helper

/// Renders `icon` as an SF Symbol or as a Text emoji depending on its content.
@ViewBuilder
func iconView(_ icon: String, size: CGFloat, color: Color = .primary) -> some View {
    if isSFSymbolName(icon) {
        Image(systemName: icon)
            .font(.system(size: size))
            .foregroundStyle(color)
    } else {
        Text(icon)
            .font(.system(size: size))
    }
}

// MARK: - Picker mode

private enum PickerMode: String, CaseIterable {
    case symbols = "Symbols"
    case emoji   = "Emoji"
}

// MARK: - Grid cell identity

/// A grid cell keyed by section + value. The same symbol can sit in several sections
/// (Suggested, and Apple lists e.g. "camera.filters" under both Camera & Photos and Editing),
/// and a LazyVGrid needs IDs unique across *all* its sections, not just within one.
private struct GridCell<Value: Hashable>: Identifiable {
    let section: String
    let value: Value
    var id: some Hashable { [AnyHashable(section), AnyHashable(value)] }

    static func cells(_ values: [Value], in section: String) -> [GridCell] {
        values.map { GridCell(section: section, value: $0) }
    }
}

// MARK: - Popover

private struct IconGridPopover: View {
    @Binding var selectedIcon: String
    @Binding var search: String
    let onSelect: () -> Void

    @State private var mode = PickerMode.symbols
    @State private var customEmoji = ""
    @State private var category = Self.suggestedTitle

    private static let suggestedTitle = "Suggested"
    private let catalog = IconCatalog.shared
    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 6), count: 8)

    private var categoryTitles: [String] {
        [Self.suggestedTitle] + catalog.symbolSections.map(\.title)
    }

    /// One category at a time (or search results), never the whole catalogue in one scroll.
    /// macOS caches every SF Symbol it has drawn (~85 KB each) for the rest of the session and
    /// offers no way to purge it — scrolling all ~7,000 symbols cost ~500 MB. Showing a single
    /// category keeps a typical visit to a few dozen MB.
    private var symbolSections: [(title: String, items: [String])] {
        if !search.isEmpty {
            let results = catalog.searchSymbols(search)
            return results.isEmpty ? [] : [("Results", results)]
        }
        if category == Self.suggestedTitle {
            return [(category, IconPickerView.suggestedSymbols.filter(catalog.containsSymbol))]
        }
        return catalog.symbolSections
            .filter { $0.title == category }
            .map { ($0.title, $0.items) }
    }

    private var emojiSections: [(title: String, items: [IconCatalog.Emoji])] {
        if !search.isEmpty {
            let results = catalog.searchEmoji(search)
            return results.isEmpty ? [] : [("Results", results)]
        }
        return catalog.emojiSections.map { ($0.title, $0.items) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode segmented picker
            Picker("Mode", selection: $mode) {
                ForEach(PickerMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .onChange(of: mode) { search = "" }

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                TextField(mode == .symbols ? "Search symbols (e.g. money, heart, car)…" : "Search emoji (e.g. dog, pizza)…",
                          text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if mode == .symbols && search.isEmpty {
                categoryBar
            }

            Divider()
                .padding(.top, 8)

            switch mode {
            case .symbols:
                let sections = symbolSections
                if sections.isEmpty {
                    noResults("No symbols found")
                } else {
                    symbolsGrid(sections)
                        .id(category)   // start each category at the top
                }
            case .emoji:
                emojiGrid(emojiSections)
            }
        }
        .frame(width: 420, height: 500)
    }

    /// Horizontally scrolling category chips, like the tag filter bar.
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categoryTitles, id: \.self) { title in
                    let isSelected = category == title
                    Button {
                        category = title
                    } label: {
                        Text(title)
                            .font(.caption)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Capsule())
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    private func noResults(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Symbol grid

    /// One LazyVGrid with pinned section headers, so only visible cells of the ~7,000
    /// symbols are ever built.
    private func symbolsGrid(_ sections: [(title: String, items: [String])]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6, pinnedViews: [.sectionHeaders]) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(GridCell.cells(section.items, in: section.title)) { cell in
                            symbolCell(cell.value)
                        }
                    } header: {
                        sectionHeader(section.title)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func symbolCell(_ symbol: String) -> some View {
        // Folders saved with a renamed symbol ("doc") still highlight its current name ("document").
        let isSelected = catalog.canonicalSymbol(selectedIcon) == symbol
        return Button {
            selectedIcon = symbol
            search = ""
            onSelect()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(symbol)
    }

    // MARK: - Emoji grid

    private func emojiGrid(_ sections: [(title: String, items: [IconCatalog.Emoji])]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                customEmojiInput
                    .padding(.top, 12)

                if sections.isEmpty {
                    noResults("No emoji found")
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 6, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections, id: \.title) { section in
                            Section {
                                ForEach(GridCell.cells(section.items, in: section.title)) { cell in
                                    emojiCell(cell.value)
                                }
                            } header: {
                                sectionHeader(section.title)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    /// Custom emoji input — tap the field, then use ⌃⌘Space or paste any emoji.
    private var customEmojiInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            HStack(spacing: 8) {
                TextField("Type or paste any emoji…", text: $customEmoji)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customEmoji) {
                        let trimmed = customEmoji.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty && !isSFSymbolName(trimmed) else { return }
                        // Swift's Character type handles multi-scalar grapheme clusters,
                        // so prefix(1) correctly captures any single emoji including ZWJ sequences.
                        let first = String(trimmed.prefix(1))
                        if customEmoji != first { customEmoji = first }
                    }
                Button("Use") {
                    let trimmed = customEmoji.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        selectedIcon = trimmed
                        onSelect()
                    }
                }
                .disabled(customEmoji.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Tip: place cursor in the field and press ⌃⌘Space for the system emoji picker.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func emojiCell(_ item: IconCatalog.Emoji) -> some View {
        let isSelected = selectedIcon == item.emoji
        return Button {
            selectedIcon = item.emoji
            search = ""
            onSelect()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                Text(item.emoji)
                    .font(.system(size: 20))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(item.name)
    }

    // MARK: - Shared section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            .background(.bar)
    }
}
