import Testing
import AppKit
@testable import booklist

/// Runs against the real bundled IconCatalog.json (tests are hosted in the app).
@Suite("IconCatalog")
struct IconCatalogTests {
    let catalog = IconCatalog.shared

    @Test("The bundled catalogue loads with thousands of symbols and emoji")
    func loads() {
        let symbolCount = Set(catalog.symbolSections.flatMap(\.items)).count
        let emojiCount = catalog.emojiSections.flatMap(\.items).count
        #expect(symbolCount > 5000)
        #expect(emojiCount > 1500)
    }

    @Test("No section lists the same icon twice (duplicate grid IDs break SwiftUI)")
    func noDuplicatesWithinSections() {
        // Apple's data once listed camera.filters under "editing" twice; the generator must
        // de-duplicate, or the picker's LazyVGrid gets duplicate IDs.
        for section in catalog.symbolSections {
            let dupes = Dictionary(grouping: section.items, by: { $0 }).filter { $0.value.count > 1 }.keys
            #expect(dupes.isEmpty, "\(section.title) repeats: \(dupes.sorted())")
        }
        for section in catalog.emojiSections {
            let dupes = Dictionary(grouping: section.items, by: \.emoji).filter { $0.value.count > 1 }.keys
            #expect(dupes.isEmpty, "\(section.title) repeats: \(dupes.sorted())")
        }
    }

    @Test("Every suggested symbol exists in the catalogue")
    func suggestedSymbolsExist() {
        let missing = IconPickerView.suggestedSymbols.filter { !catalog.containsSymbol($0) }
        #expect(missing.isEmpty, "Missing: \(missing)")
    }

    @Test("Every symbol in the catalogue renders on this macOS (no blank cells in the picker)")
    func symbolsRender() {
        let all = Set(catalog.symbolSections.flatMap(\.items))
        let blank = all.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(blank.isEmpty, "\(blank.count) don't render, e.g. \(blank.sorted().prefix(10))")
    }

    @Test("Localized duplicates (.ar, .hi, .rtl…) are filtered out")
    func noLocalizedVariants() {
        let all = Set(catalog.symbolSections.flatMap(\.items))
        #expect(!all.contains("0.circle.ar"))
        #expect(all.contains("0.circle"))
    }

    @Test("Search matches symbol names")
    func searchByName() {
        #expect(catalog.searchSymbols("folder").contains("folder"))
    }

    @Test("Search matches Apple's keywords (currency → dollarsign)")
    func searchByKeyword() {
        #expect(catalog.searchSymbols("currency").contains("dollarsign"))
    }

    @Test("Search by an old, renamed name finds the current symbol (doc → document)")
    func searchByAlias() {
        #expect(catalog.searchSymbols("doc").contains("document"))
        #expect(catalog.canonicalSymbol("doc") == "document")
        #expect(catalog.canonicalSymbol("folder") == "folder")
    }

    @Test("Search results have no duplicates even though symbols sit in several categories")
    func searchNoDuplicates() {
        let results = catalog.searchSymbols("arrow")
        #expect(results.count == Set(results).count)
    }

    @Test("Emoji are searchable by name")
    func emojiSearch() {
        let results = catalog.searchEmoji("dog").map(\.emoji)
        #expect(results.contains("🐶"))
        #expect(catalog.searchEmoji("pizza").map(\.emoji).contains("🍕"))
    }

    @Test("Skin-tone variants are skipped to keep the grid manageable")
    func noSkinTones() {
        #expect(!catalog.emojiSections.flatMap(\.items).contains { $0.name.contains("skin tone") })
    }

    @Test("Empty search returns nothing (the full catalogue is shown instead)")
    func emptySearch() {
        #expect(catalog.searchSymbols("   ").isEmpty)
        #expect(catalog.searchEmoji("").isEmpty)
    }
}
