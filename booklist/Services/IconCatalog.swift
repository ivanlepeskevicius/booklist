import Foundation

/// Every SF Symbol (available on the deployment target) and every emoji, loaded from
/// `Resources/IconCatalog.json`. The file is generated from Apple's system symbol catalogue
/// and the Unicode emoji list by `scripts/generate_icon_catalog.py` — re-run it after a
/// macOS/Xcode update to pick up new symbols.
nonisolated struct IconCatalog: Decodable {
    struct SymbolSection: Decodable {
        let title: String
        let items: [String]
    }

    struct Emoji: Decodable, Hashable {
        let emoji: String
        let name: String
    }

    struct EmojiSection: Decodable {
        let title: String
        let items: [Emoji]
    }

    let symbolSections: [SymbolSection]
    /// Apple's search keywords per symbol ("dollarsign" → ["currency", …]).
    let symbolKeywords: [String: [String]]
    /// Renamed symbols, old name → current name ("doc" → "document").
    let symbolAliases: [String: String]
    let emojiSections: [EmojiSection]

    /// Decoded on first use (static lets are lazy), so app launch doesn't pay for it.
    static let shared = load()

    static func load(from bundle: Bundle = .main) -> IconCatalog {
        guard let url = bundle.url(forResource: "IconCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(IconCatalog.self, from: data)
        else {
            return IconCatalog(symbolSections: [], symbolKeywords: [:], symbolAliases: [:], emojiSections: [])
        }
        return catalog
    }

    /// The current name for a symbol saved under an old name, so it matches in the picker.
    func canonicalSymbol(_ name: String) -> String {
        symbolAliases[name] ?? name
    }

    func containsSymbol(_ name: String) -> Bool {
        symbolSections.contains { $0.items.contains(name) }
    }

    /// Symbols whose name, keywords or old (renamed) name contain `query`, in catalogue order.
    func searchSymbols(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let renamedMatches = Set(symbolAliases.filter { $0.key.contains(q) }.values)
        var seen = Set<String>()
        var results: [String] = []
        for name in symbolSections.lazy.flatMap(\.items) where !seen.contains(name) {
            seen.insert(name)
            if name.contains(q)
                || renamedMatches.contains(name)
                || symbolKeywords[name, default: []].contains(where: { $0.contains(q) }) {
                results.append(name)
            }
        }
        return results
    }

    /// Emoji whose Unicode name contains `query` ("dog" → 🐶 dog face, 🐕 dog, 🌭 hot dog…).
    func searchEmoji(_ query: String) -> [Emoji] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return emojiSections.flatMap(\.items).filter { $0.name.contains(q) || $0.emoji == q }
    }
}
