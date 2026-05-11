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

    // MARK: - Curated SF Symbol library

    static let symbolsByCategory: [(String, [String])] = [
        ("Folders & Files", [
            "folder", "folder.fill", "folder.badge.plus", "tray", "tray.fill",
            "archivebox", "doc", "doc.fill", "paperclip", "link", "externaldrive",
            "internaldrive", "doc.on.doc", "doc.text", "filemenu.and.selection"
        ]),
        ("Lists & Notes", [
            "list.bullet", "list.dash", "checklist", "note.text", "square.and.pencil",
            "pencil", "pencil.and.outline", "text.alignleft", "bookmark", "bookmark.fill",
            "pin", "pin.fill", "flag", "flag.fill", "tag", "tag.fill"
        ]),
        ("Media & Creative", [
            "photo", "photo.fill", "photo.on.rectangle", "film", "music.note",
            "headphones", "waveform", "camera", "camera.fill", "video", "mic",
            "paintbrush", "paintbrush.fill", "pencil.tip", "paintpalette", "scissors"
        ]),
        ("Shopping & Money", [
            "cart", "cart.fill", "bag", "bag.fill", "giftcard", "gift", "gift.fill",
            "dollarsign", "creditcard", "creditcard.fill", "eurosign", "sterlingsign"
        ]),
        ("Communication", [
            "envelope", "envelope.fill", "bubble.left", "bubble.left.fill",
            "phone", "globe", "wifi", "network", "at", "paperplane", "paperplane.fill"
        ]),
        ("People & Social", [
            "person", "person.fill", "person.2", "person.2.fill",
            "heart", "heart.fill", "hand.thumbsup", "hand.thumbsup.fill",
            "star", "star.fill", "rosette"
        ]),
        ("Technology", [
            "laptopcomputer", "desktopcomputer", "iphone", "ipad", "applewatch",
            "keyboard", "computermouse", "cpu", "server.rack", "memorychip",
            "terminal", "code", "chevron.left.forwardslash.chevron.right"
        ]),
        ("Nature & Places", [
            "leaf", "leaf.fill", "tree", "flame", "flame.fill", "drop", "drop.fill",
            "cloud", "sun.max", "sun.max.fill", "moon", "moon.fill",
            "globe.europe.africa", "map", "map.fill", "building.2", "house", "house.fill"
        ]),
        ("Activities & Sports", [
            "book", "book.fill", "books.vertical", "graduationcap",
            "figure.run", "bicycle", "sportscourt", "trophy", "trophy.fill",
            "gamecontroller", "gamecontroller.fill", "puzzlepiece", "wrench", "hammer"
        ]),
        ("Symbols & UI", [
            "checkmark.circle", "checkmark.circle.fill", "xmark.circle",
            "plus.circle", "minus.circle", "info.circle", "exclamationmark.triangle",
            "magnifyingglass", "lock", "lock.fill", "eye", "eye.slash",
            "bell", "bell.fill", "lightbulb", "lightbulb.fill", "sparkles"
        ]),
    ]

    // MARK: - Curated emoji library

    static let emojiByCategory: [(String, [String])] = [
        ("Folders & Files", [
            "📁", "📂", "🗂️", "📋", "📌", "📍", "📎", "🔗", "🔖",
            "📝", "✏️", "📄", "🗒️", "🗃️", "🗄️"
        ]),
        ("Shopping & Money", [
            "🛒", "🛍️", "💰", "💵", "💳", "💎", "🎁", "🎀", "🏷️", "⌚", "👜"
        ]),
        ("Technology", [
            "💻", "🖥️", "⌨️", "🖱️", "📱", "📡", "🔌", "🔋", "💡", "🔦", "📷", "🎥", "🖨️", "🕹️"
        ]),
        ("Media & Art", [
            "🎵", "🎶", "🎸", "🎹", "🎬", "🎭", "🎨", "🖼️", "🎤", "📻", "📺", "🎙️"
        ]),
        ("Nature", [
            "🌿", "🌱", "🌳", "🌸", "🌺", "🍀", "🌙", "☀️", "🌈", "🔥", "💧", "❄️"
        ]),
        ("Food & Travel", [
            "☕", "🍵", "🍕", "🍜", "✈️", "🚀", "🗺️", "🌍", "🏖️", "🏠", "🏢", "🚗", "🎒"
        ]),
        ("Symbols & Signals", [
            "❤️", "⭐", "🎯", "🏆", "🥇", "💪", "🧠", "👀", "✅", "⚡", "💫", "🔮", "🎉"
        ]),
        ("Activities", [
            "📚", "📖", "🎮", "⚽", "🏃", "🧘", "✍️", "🔬", "🔭", "🧪", "🏋️", "🚴", "🎲", "♟️"
        ]),
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

// MARK: - Popover

private struct IconGridPopover: View {
    @Binding var selectedIcon: String
    @Binding var search: String
    let onSelect: () -> Void

    @State private var mode = PickerMode.symbols

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 6), count: 6)

    private var filteredSymbols: [(String, [String])] {
        guard !search.isEmpty else { return IconPickerView.symbolsByCategory }
        let q = search.lowercased()
        return IconPickerView.symbolsByCategory.compactMap { (cat, symbols) in
            let matched = symbols.filter { $0.lowercased().contains(q) }
            return matched.isEmpty ? nil : (cat, matched)
        }
    }

    private var filteredEmoji: [(String, [String])] {
        guard !search.isEmpty else { return IconPickerView.emojiByCategory }
        let q = search.lowercased()
        return IconPickerView.emojiByCategory.filter { $0.0.lowercased().contains(q) }
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
                TextField(mode == .symbols ? "Search icons…" : "Search categories…", text: $search)
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

            Divider()
                .padding(.top, 8)

            switch mode {
            case .symbols:
                if filteredSymbols.isEmpty {
                    Text("No icons found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else {
                    symbolsGrid
                }
            case .emoji:
                if filteredEmoji.isEmpty {
                    Text("No categories found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else {
                    emojiGrid
                }
            }
        }
        .frame(width: 336, height: 460)
    }

    // MARK: - Symbol grid

    private var symbolsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(filteredSymbols, id: \.0) { (category, symbols) in
                    categorySection(title: category) {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(symbols, id: \.self) { symbol in
                                symbolCell(symbol)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func symbolCell(_ symbol: String) -> some View {
        let isSelected = selectedIcon == symbol
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

    private var emojiGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(filteredEmoji, id: \.0) { (category, emojis) in
                    categorySection(title: category) {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(emojis, id: \.self) { emoji in
                                emojiCell(emoji)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func emojiCell(_ emoji: String) -> some View {
        let isSelected = selectedIcon == emoji
        return Button {
            selectedIcon = emoji
            search = ""
            onSelect()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                Text(emoji)
                    .font(.system(size: 20))
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared section layout

    @ViewBuilder
    private func categorySection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            content()
        }
    }
}
