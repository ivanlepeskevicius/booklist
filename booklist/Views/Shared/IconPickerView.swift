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
            "folder", "folder.fill", "folder.badge.plus", "folder.badge.minus",
            "tray", "tray.fill", "tray.2", "tray.and.arrow.down",
            "archivebox", "archivebox.fill",
            "doc", "doc.fill", "doc.richtext", "doc.plaintext",
            "doc.text", "doc.on.doc", "doc.badge.plus", "doc.text.magnifyingglass",
            "paperclip", "link",
            "externaldrive", "externaldrive.fill", "internaldrive",
            "briefcase", "briefcase.fill",
            "square.and.arrow.down", "square.and.arrow.up",
            "shippingbox", "shippingbox.fill",
            "filemenu.and.selection"
        ]),
        ("Lists & Notes", [
            "list.bullet", "list.dash", "list.number",
            "checklist", "checklist.checked", "checklist.unchecked",
            "note.text", "square.and.pencil",
            "pencil", "pencil.and.outline", "highlighter", "signature",
            "text.alignleft", "text.aligncenter",
            "bookmark", "bookmark.fill", "bookmark.circle",
            "pin", "pin.fill",
            "flag", "flag.fill", "flag.circle",
            "tag", "tag.fill",
            "calendar", "calendar.badge.plus",
            "clock", "clock.fill", "timer", "alarm", "alarm.fill"
        ]),
        ("Media & Creative", [
            "photo", "photo.fill", "photo.on.rectangle", "photo.stack", "photo.artframe",
            "film", "film.fill",
            "music.note", "music.note.list",
            "headphones",
            "waveform",
            "camera", "camera.fill", "camera.circle",
            "video", "video.fill",
            "mic", "mic.fill",
            "paintbrush", "paintbrush.fill", "paintbrush.pointed",
            "paintpalette", "paintpalette.fill",
            "scissors", "lasso",
            "wand.and.stars", "wand.and.rays",
            "eyedropper", "eyedropper.full", "crop"
        ]),
        ("Shopping & Money", [
            "cart", "cart.fill", "cart.badge.plus",
            "bag", "bag.fill",
            "handbag", "handbag.fill",
            "backpack", "backpack.fill",
            "gift", "gift.fill",
            "giftcard", "giftcard.fill",
            "dollarsign", "dollarsign.circle", "dollarsign.circle.fill",
            "creditcard", "creditcard.fill",
            "eurosign", "sterlingsign", "yensign",
            "banknote", "percent", "tag.slash",
            "purchased", "purchased.circle"
        ]),
        ("Communication", [
            "envelope", "envelope.fill", "envelope.circle", "envelope.badge",
            "bubble.left", "bubble.left.fill",
            "bubble.right", "bubble.right.fill",
            "bubble.left.and.bubble.right",
            "phone", "phone.fill", "phone.circle",
            "globe", "wifi", "network",
            "antenna.radiowaves.left.and.right",
            "at", "paperplane", "paperplane.fill",
            "megaphone", "megaphone.fill",
            "shareplay", "quote.bubble"
        ]),
        ("People & Social", [
            "person", "person.fill", "person.circle", "person.circle.fill",
            "person.badge.plus", "person.badge.minus",
            "person.2", "person.2.fill",
            "person.3", "person.3.fill",
            "person.crop.circle",
            "heart", "heart.fill", "heart.circle",
            "hand.thumbsup", "hand.thumbsup.fill",
            "hand.thumbsdown", "hand.thumbsdown.fill",
            "hand.wave", "hand.raised", "hands.clap",
            "star", "star.fill", "rosette",
            "brain", "brain.head.profile",
            "figure.walk", "figure.run", "figure.stand"
        ]),
        ("Technology", [
            "laptopcomputer", "desktopcomputer", "iphone", "ipad", "applewatch",
            "keyboard", "computermouse",
            "cpu", "memorychip", "server.rack",
            "externaldrive", "internaldrive",
            "terminal", "code", "chevron.left.forwardslash.chevron.right",
            "wifi", "bluetooth", "network",
            "gear", "gearshape", "gearshape.fill",
            "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
            "hammer", "hammer.fill",
            "chart.bar", "chart.line.uptrend.xyaxis",
            "stethoscope", "printer", "tv", "tv.fill"
        ]),
        ("Nature & Places", [
            "leaf", "leaf.fill",
            "tree", "tree.fill",
            "flame", "flame.fill", "drop", "drop.fill",
            "cloud", "cloud.fill", "cloud.rain", "cloud.bolt",
            "sun.max", "sun.max.fill",
            "moon", "moon.fill", "moon.stars",
            "snowflake", "wind",
            "globe.europe.africa", "globe.americas",
            "map", "map.fill",
            "building.2", "building.2.fill",
            "building.columns", "house", "house.fill",
            "mountain.2",
            "tortoise", "hare", "bird", "fish", "ant", "ladybug",
            "pawprint", "pawprint.fill",
            "beach.umbrella"
        ]),
        ("Activities & Sports", [
            "book", "book.fill", "books.vertical", "books.vertical.fill",
            "graduationcap", "graduationcap.fill",
            "figure.run", "figure.walk", "figure.hiking",
            "figure.yoga", "figure.basketball",
            "figure.surfing", "figure.swimming",
            "bicycle", "sportscourt", "sportscourt.fill",
            "trophy", "trophy.fill",
            "gamecontroller", "gamecontroller.fill",
            "puzzlepiece", "puzzlepiece.fill",
            "guitar", "pianokeys", "music.mic",
            "ticket", "ticket.fill",
            "theatermasks", "theatermasks.fill"
        ]),
        ("Food & Drink", [
            "fork.knife", "fork.knife.circle",
            "cup.and.saucer", "cup.and.saucer.fill",
            "mug", "mug.fill",
            "wineglass",
            "birthday.cake",
            "carrot",
            "cart", "bag"
        ]),
        ("Travel & Transport", [
            "airplane", "airplane.departure", "airplane.arrival",
            "car.fill", "car.circle",
            "bus", "tram",
            "figure.walk", "figure.hiking",
            "map", "map.fill",
            "location", "location.fill", "location.circle",
            "building.2.fill",
            "signpost.right", "signpost.right.fill"
        ]),
        ("Symbols & UI", [
            "checkmark.circle", "checkmark.circle.fill",
            "checkmark.seal", "checkmark.seal.fill",
            "xmark.circle", "xmark.circle.fill",
            "plus.circle", "plus.circle.fill",
            "minus.circle",
            "info.circle", "info.circle.fill",
            "questionmark.circle", "questionmark.circle.fill",
            "exclamationmark.triangle", "exclamationmark.circle",
            "magnifyingglass",
            "lock", "lock.fill", "lock.open",
            "eye", "eye.slash",
            "bell", "bell.fill", "bell.badge",
            "lightbulb", "lightbulb.fill",
            "sparkles", "infinity",
            "shield", "shield.fill",
            "arrow.clockwise", "arrow.counterclockwise",
            "power", "slider.horizontal.3"
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

    @State private var customEmoji = ""

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
                // Custom emoji input — tap the field, then use ⌃⌘Space or paste any emoji
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
                                // Accept the first emoji-like character typed
                                let trimmed = customEmoji.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty && !isSFSymbolName(trimmed) {
                                    // Keep only the first "character" (emoji can be multi-scalar)
                                    let first = String(trimmed.prefix(2))
                                    customEmoji = first
                                }
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
