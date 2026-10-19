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
            "folder.badge.questionmark", "folder.badge.gearshape",
            "tray", "tray.fill", "tray.2", "tray.full", "tray.full.fill",
            "tray.and.arrow.down", "tray.and.arrow.up", "tray.and.arrow.up.fill",
            "archivebox", "archivebox.fill",
            "doc", "doc.fill", "doc.richtext", "doc.plaintext",
            "doc.text", "doc.on.doc", "doc.badge.plus", "doc.badge.arrow.up",
            "doc.on.clipboard", "doc.on.clipboard.fill", "doc.text.magnifyingglass",
            "paperclip", "rectangle.and.paperclip", "link",
            "externaldrive", "externaldrive.fill", "internaldrive",
            "briefcase", "briefcase.fill",
            "square.and.arrow.down", "square.and.arrow.up",
            "shippingbox", "shippingbox.fill",
            "filemenu.and.selection",
        ]),
        ("Lists & Notes", [
            "list.bullet", "list.dash", "list.number", "list.triangle",
            "list.bullet.clipboard", "list.bullet.clipboard.fill",
            "checklist", "checklist.checked", "checklist.unchecked",
            "table", "table.fill",
            "note", "note.text", "note.text.badge.plus", "square.and.pencil",
            "pencil", "pencil.circle", "pencil.tip", "pencil.tip.crop.circle",
            "pencil.and.outline", "highlighter", "signature",
            "text.alignleft", "text.aligncenter",
            "line.3.horizontal", "line.3.horizontal.decrease",
            "bookmark", "bookmark.fill", "bookmark.circle", "bookmark.slash",
            "pin", "pin.fill", "pin.circle",
            "flag", "flag.fill", "flag.circle", "flag.2.crossed", "flag.slash",
            "tag", "tag.fill", "tag.circle", "tag.slash",
            "calendar", "calendar.badge.plus", "calendar.badge.minus", "calendar.circle",
            "clock", "clock.fill", "timer", "alarm", "alarm.fill",
        ]),
        ("Media & Creative", [
            "photo", "photo.fill", "photo.on.rectangle", "photo.stack", "photo.artframe", "photo.badge.plus",
            "film", "film.fill",
            "music.note", "music.note.list", "music.quarternote.3", "music.note.tv",
            "headphones", "headphones.circle",
            "speaker", "speaker.fill", "speaker.wave.2",
            "waveform",
            "radio", "radio.fill", "airplayaudio",
            "camera", "camera.fill", "camera.circle",
            "video", "video.fill",
            "mic", "mic.fill", "mic.circle",
            "paintbrush", "paintbrush.fill", "paintbrush.pointed",
            "paintpalette", "paintpalette.fill",
            "scissors", "lasso",
            "wand.and.stars", "wand.and.rays", "wand.and.sparkles",
            "eyedropper", "eyedropper.full", "crop",
        ]),
        ("Shopping & Money", [
            "cart", "cart.fill", "cart.badge.plus",
            "bag", "bag.fill", "bag.circle", "bag.badge.plus", "bag.badge.minus",
            "handbag", "handbag.fill",
            "backpack", "backpack.fill",
            "gift", "gift.fill", "gift.circle",
            "giftcard", "giftcard.fill",
            "dollarsign", "dollarsign.circle", "dollarsign.circle.fill",
            "creditcard", "creditcard.fill",
            "eurosign", "sterlingsign", "yensign",
            "banknote", "banknote.fill", "percent", "tag.slash",
            "purchased", "purchased.circle",
            "chart.bar", "chart.bar.xaxis", "chart.line.uptrend.xyaxis",
            "chart.pie", "chart.pie.fill",
        ]),
        ("Communication", [
            "envelope", "envelope.fill", "envelope.circle", "envelope.badge",
            "envelope.open", "envelope.open.fill",
            "bubble.left", "bubble.left.fill",
            "bubble.right", "bubble.right.fill",
            "bubble.left.and.bubble.right",
            "bubble.middle.bottom", "bubble.middle.bottom.fill",
            "message", "message.fill",
            "phone", "phone.fill", "phone.circle", "phone.bubble", "phone.badge.plus",
            "globe", "wifi", "network",
            "antenna.radiowaves.left.and.right", "dot.radiowaves.left.and.right",
            "at", "paperplane", "paperplane.fill",
            "megaphone", "megaphone.fill",
            "bell", "bell.fill", "bell.badge", "bell.and.waves.left.and.right",
            "shareplay", "quote.bubble",
        ]),
        ("People & Social", [
            "person", "person.fill", "person.circle", "person.circle.fill",
            "person.badge.plus", "person.badge.minus",
            "person.crop.circle", "person.crop.circle.badge.checkmark",
            "person.2", "person.2.fill", "person.2.wave.2",
            "person.3", "person.3.fill",
            "figure.2",
            "face.smiling", "face.smiling.fill",
            "heart", "heart.fill", "heart.circle", "heart.circle.fill",
            "hand.thumbsup", "hand.thumbsup.fill",
            "hand.thumbsdown", "hand.thumbsdown.fill",
            "hand.wave", "hand.raised", "hands.clap",
            "hands.sparkles", "hands.sparkles.fill",
            "star", "star.fill", "star.circle", "rosette",
            "brain", "brain.head.profile",
            "figure.walk", "figure.run", "figure.stand",
        ]),
        ("Technology", [
            "laptopcomputer", "desktopcomputer", "iphone", "ipad", "applewatch",
            "keyboard", "computermouse",
            "cpu", "memorychip", "server.rack",
            "externaldrive", "externaldrive.fill", "internaldrive",
            "terminal", "curlybraces", "chevron.left.forwardslash.chevron.right",
            "square.grid.2x2", "square.grid.3x3", "square.grid.4x3.fill",
            "wifi", "dot.radiowaves.left.and.right", "network",
            "gear", "gearshape", "gearshape.fill", "gearshape.2",
            "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
            "hammer", "hammer.fill",
            "puzzlepiece", "puzzlepiece.fill", "puzzlepiece.extension", "puzzlepiece.extension.fill",
            "power", "power.circle", "power.circle.fill",
            "stethoscope", "printer", "tv", "tv.fill",
        ]),
        ("Nature & Places", [
            "leaf", "leaf.fill", "leaf.circle",
            "tree", "tree.fill",
            "flame", "flame.fill", "drop", "drop.fill",
            "cloud", "cloud.fill", "cloud.rain", "cloud.bolt", "cloud.sun",
            "sun.max", "sun.max.fill", "sun.horizon", "sun.horizon.fill",
            "moon", "moon.fill", "moon.stars",
            "snowflake", "wind",
            "globe.europe.africa", "globe.europe.africa.fill",
            "globe.americas", "globe.americas.fill",
            "map", "map.fill",
            "building.2", "building.2.fill",
            "building.columns", "building.columns.fill",
            "house", "house.fill",
            "mountain.2", "mountain.2.fill",
            "tortoise", "hare", "bird", "fish", "ant", "ladybug",
            "dog", "dog.fill", "cat", "cat.fill", "lizard",
            "pawprint", "pawprint.fill",
            "beach.umbrella",
        ]),
        ("Activities & Sports", [
            "book", "book.fill", "books.vertical", "books.vertical.fill",
            "graduationcap", "graduationcap.fill",
            "figure.run", "figure.walk", "figure.hiking",
            "figure.yoga", "figure.basketball",
            "figure.dance", "figure.american.football",
            "figure.open.water.swim", "figure.pool.swim",
            "figure.strengthtraining.traditional", "figure.mind.and.body",
            "bicycle", "bicycle.circle", "bicycle.circle.fill",
            "sportscourt", "sportscourt.fill",
            "trophy", "trophy.fill", "medal", "medal.fill",
            "dumbbell", "dumbbell.fill",
            "soccerball", "baseball", "basketball", "tennis.racket",
            "gamecontroller", "gamecontroller.fill",
            "guitars", "pianokeys", "music.mic",
            "ticket", "ticket.fill",
            "theatermasks", "theatermasks.fill",
        ]),
        ("Food & Drink", [
            "fork.knife", "fork.knife.circle",
            "cup.and.saucer", "cup.and.saucer.fill",
            "mug", "mug.fill",
            "wineglass", "wineglass.fill",
            "birthday.cake", "birthday.cake.fill",
            "carrot",
            "popcorn", "popcorn.fill",
            "takeoutbag.and.cup.and.straw",
            "cart", "bag",
        ]),
        ("Travel & Transport", [
            "airplane", "airplane.departure", "airplane.arrival",
            "car", "car.fill", "car.circle",
            "bus", "tram",
            "ferry", "ferry.fill",
            "bicycle", "bicycle.circle",
            "fuelpump", "fuelpump.fill",
            "parkingsign", "parkingsign.circle",
            "map", "map.fill",
            "location", "location.fill", "location.circle",
            "building.2.fill",
            "signpost.right", "signpost.right.fill",
            "figure.walk", "figure.hiking",
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
            "lightbulb", "lightbulb.fill",
            "sparkles", "sparkle", "wand.and.sparkles", "infinity",
            "shield", "shield.fill",
            "arrow.clockwise", "arrow.counterclockwise",
            "arrow.up", "arrow.down", "arrow.left", "arrow.right", "arrow.up.right",
            "chevron.up", "chevron.down",
            "power", "slider.horizontal.3",
        ]),
    ]

    // MARK: - Curated emoji library

    static let emojiByCategory: [(String, [String])] = [
        ("Folders & Files", [
            "📁", "📂", "🗂️", "📋", "📌", "📍", "📎", "🖇️", "🔗", "🔖",
            "📝", "✏️", "📄", "📃", "🗒️", "🗃️", "🗄️", "📦", "💾", "💿",
            "📊", "📈", "📉", "🗑️", "📜",
        ]),
        ("Shopping & Money", [
            "🛒", "🛍️", "👜", "👛", "👝", "💰", "💵", "💴", "💶", "💷", "🪙",
            "💳", "🧾", "💎", "🎁", "🎀", "🏷️", "⌚", "💍", "💸", "🤑",
            "📦", "🏪", "🏬",
        ]),
        ("Technology", [
            "💻", "🖥️", "⌨️", "🖱️", "📱", "📲", "📡", "🔌", "🔋", "🪫",
            "💡", "🔦", "📷", "📸", "🎥", "🖨️", "🖲️", "🕹️", "🤖",
            "⚙️", "🔬", "🔭", "🧬", "📟", "📠",
        ]),
        ("Media & Art", [
            "🎵", "🎶", "🎸", "🎹", "🥁", "🪘", "🎷", "🎺", "🎻", "🪗",
            "🎬", "🎭", "🎨", "🖼️", "🖌️", "🎤", "🎙️",
            "📻", "📺", "🎞️", "📽️", "🎮",
        ]),
        ("Nature", [
            "🌿", "🌱", "🌳", "🌲", "🌴", "🌵", "🍀", "🌸", "🌺", "🌻",
            "🌹", "🌷", "🍃", "🍂", "🍁", "🍄", "🌾", "🪸",
            "🌙", "⭐", "🌟", "☀️", "🌈", "🔥", "💧", "🌊", "❄️", "⛅",
            "🦁", "🐘", "🦊", "🐺", "🦋", "🐝", "🐠", "🦜",
        ]),
        ("Food & Drink", [
            "☕", "🍵", "🧃", "🥤", "🧋", "🍺", "🍷", "🥂", "🍾",
            "🍕", "🍔", "🌮", "🌯", "🍜", "🍣", "🍱", "🥗", "🥘", "🍰", "🎂",
            "🥩", "🧁", "🍩", "🍪", "🥐", "🍎", "🍊", "🍋", "🍇", "🫐",
        ]),
        ("Travel & Places", [
            "✈️", "🚀", "🛸", "🚗", "🚙", "🚂", "🚢", "🛳️", "🚲",
            "🗺️", "🌍", "🌎", "🌏", "🧭",
            "🏖️", "🏔️", "🏕️", "🗼", "🗽", "🏯", "🏰",
            "🏠", "🏢", "🏨", "⛪", "🎒", "🧳",
        ]),
        ("People & Social", [
            "🧑", "👩", "👨", "👶", "🧓", "👥", "🤝", "🫂",
            "🥰", "😊", "😎", "🤩", "🙌", "👏", "💪", "🫶",
            "❤️", "🧡", "💛", "💚", "💙", "💜",
        ]),
        ("Symbols & Signals", [
            "⭐", "🌟", "💫", "✨", "🎯", "🏆", "🥇", "🥈", "🥉", "🏅", "🎖️",
            "🧠", "👀", "✅", "❌", "⚡", "🔮", "🎉", "🎊", "🧩",
            "🔑", "🗝️", "🔓", "🔐", "⚠️", "🚫", "♾️",
        ]),
        ("Activities", [
            "📚", "📖", "🎮", "⚽", "🏀", "🎾", "🏈", "⚾", "🏓", "🎯",
            "🏃", "🧘", "🏋️", "🚴", "🤸", "🏊", "⛷️", "🏄", "🧗", "🤿",
            "✍️", "🎲", "♟️", "🎳", "🎸", "🎻",
            "🔬", "🔭", "🧪", "🧬",
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
