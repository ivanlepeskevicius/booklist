import Testing
import Foundation
@testable import booklist

@Suite("ViewModeMemory")
struct ViewModeMemoryTests {

    @Test("Unknown items have no saved mode")
    func emptyByDefault() {
        #expect(ViewModeMemory().mode(for: .inbox) == nil)
    }

    @Test("Each sidebar item remembers its own mode")
    func perItem() {
        let folderA = UUID(), folderB = UUID()
        var memory = ViewModeMemory()
        memory.remember(.list, for: .folder(folderA))
        memory.remember(.masonry, for: .folder(folderB))
        memory.remember(.list, for: .inbox)

        #expect(memory.mode(for: .folder(folderA)) == .list)
        #expect(memory.mode(for: .folder(folderB)) == .masonry)
        #expect(memory.mode(for: .inbox) == .list)
        #expect(memory.mode(for: .all) == nil)
    }

    @Test("Remembering again overwrites the previous mode")
    func overwrite() {
        var memory = ViewModeMemory()
        memory.remember(.list, for: .wishlist)
        memory.remember(.masonry, for: .wishlist)
        #expect(memory.mode(for: .wishlist) == .masonry)
    }

    @Test("Survives a round-trip through Data (UserDefaults storage)")
    func dataRoundTrip() {
        let folder = UUID()
        var memory = ViewModeMemory()
        memory.remember(.list, for: .folder(folder))

        let restored = ViewModeMemory(data: memory.data)
        #expect(restored == memory)
        #expect(restored.mode(for: .folder(folder)) == .list)
    }

    @Test("Empty or corrupt data falls back to an empty memory")
    func corruptData() {
        #expect(ViewModeMemory(data: Data()) == ViewModeMemory())
        #expect(ViewModeMemory(data: Data("not json".utf8)) == ViewModeMemory())
    }

    @Test("Storage keys are distinct for every kind of sidebar item")
    func distinctKeys() {
        let keys = [SidebarSelection.inbox, .wishlist, .all, .folder(UUID()), .folder(UUID())].map(\.storageKey)
        #expect(Set(keys).count == keys.count)
    }
}
