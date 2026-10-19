import Testing
import SwiftData
import Foundation
@testable import booklist

private typealias Tag = booklist.Tag

@Suite("FolderTree")
struct FolderTreeTests {

    // MARK: - FolderTree.subtreeIDs

    @Suite("subtreeIDs")
    struct SubtreeIDsTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Bookmark.self, Folder.self, Tag.self,
                configurations: config
            )
            return ModelContext(container)
        }

        @Test("single root with no children returns just root")
        func singleRoot() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            ctx.insert(root)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            let ids = FolderTree.subtreeIDs(rootID: root.id, in: folders)
            #expect(ids == [root.id])
        }

        @Test("root with one child returns both IDs")
        func rootWithOneChild() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let child = Folder(name: "Child", parent: root)
            ctx.insert(root)
            ctx.insert(child)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            let ids = FolderTree.subtreeIDs(rootID: root.id, in: folders)
            #expect(ids == [root.id, child.id])
        }

        @Test("three-level hierarchy returns all descendant IDs")
        func threeLevels() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let child = Folder(name: "Child", parent: root)
            let grandchild = Folder(name: "Grandchild", parent: child)
            ctx.insert(root)
            ctx.insert(child)
            ctx.insert(grandchild)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            let ids = FolderTree.subtreeIDs(rootID: root.id, in: folders)
            #expect(ids == [root.id, child.id, grandchild.id])
        }

        @Test("sibling branches are both included")
        func siblingBranches() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let left = Folder(name: "Left", parent: root)
            let right = Folder(name: "Right", parent: root)
            ctx.insert(root)
            ctx.insert(left)
            ctx.insert(right)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            let ids = FolderTree.subtreeIDs(rootID: root.id, in: folders)
            #expect(ids == [root.id, left.id, right.id])
        }

        @Test("unrelated folder is not included in subtree")
        func unrelatedFolderExcluded() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let child = Folder(name: "Child", parent: root)
            let unrelated = Folder(name: "Unrelated")
            ctx.insert(root)
            ctx.insert(child)
            ctx.insert(unrelated)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            let ids = FolderTree.subtreeIDs(rootID: root.id, in: folders)
            #expect(!ids.contains(unrelated.id))
        }

        @Test("circular reference terminates without stack overflow")
        func circularReference() throws {
            let ctx = try makeContext()
            let a = Folder(name: "A")
            let b = Folder(name: "B")
            ctx.insert(a)
            ctx.insert(b)
            try ctx.save()
            // Manually wire up a circular parent chain to simulate corrupt sync data
            a.parent = b
            b.parent = a
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            // Must return without infinite recursion; both nodes reachable before cycle detected
            let ids = FolderTree.subtreeIDs(rootID: a.id, in: folders)
            #expect(ids.contains(a.id))
        }
    }

    // MARK: - FolderTree.contains

    @Suite("contains")
    struct ContainsTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Bookmark.self, Folder.self, Tag.self,
                configurations: config
            )
            return ModelContext(container)
        }

        @Test("a folder contains itself")
        func containsSelf() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            ctx.insert(root)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            #expect(FolderTree.contains(targetID: root.id, in: root.id, folders: folders))
        }

        @Test("ancestor contains its direct child")
        func containsDirectChild() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let child = Folder(name: "Child", parent: root)
            ctx.insert(root)
            ctx.insert(child)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            #expect(FolderTree.contains(targetID: child.id, in: root.id, folders: folders))
        }

        @Test("child does not contain its parent")
        func childDoesNotContainParent() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let child = Folder(name: "Child", parent: root)
            ctx.insert(root)
            ctx.insert(child)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            #expect(!FolderTree.contains(targetID: root.id, in: child.id, folders: folders))
        }

        @Test("ancestor contains a grandchild")
        func containsGrandchild() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let child = Folder(name: "Child", parent: root)
            let grandchild = Folder(name: "Grandchild", parent: child)
            ctx.insert(root)
            ctx.insert(child)
            ctx.insert(grandchild)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            #expect(FolderTree.contains(targetID: grandchild.id, in: root.id, folders: folders))
        }

        @Test("unrelated folder is not contained")
        func unrelatedFolderNotContained() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let unrelated = Folder(name: "Other")
            ctx.insert(root)
            ctx.insert(unrelated)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            #expect(!FolderTree.contains(targetID: unrelated.id, in: root.id, folders: folders))
        }

        @Test("circular reference terminates without stack overflow")
        func circularReference() throws {
            let ctx = try makeContext()
            let a = Folder(name: "A")
            let b = Folder(name: "B")
            let c = Folder(name: "C")
            ctx.insert(a)
            ctx.insert(b)
            ctx.insert(c)
            try ctx.save()
            a.parent = b
            b.parent = a
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            // c is unrelated to the a↔b cycle; must return false without stack overflow
            #expect(!FolderTree.contains(targetID: c.id, in: a.id, folders: folders))
        }
    }

    // MARK: - FolderTree.move

    @Suite("move")
    struct MoveTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Bookmark.self, Folder.self, Tag.self,
                configurations: config
            )
            return ModelContext(container)
        }

        @Test("moving into another folder re-parents it and puts it last")
        func moveIntoFolder() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work", sortOrder: 0)
            let existing = Folder(name: "Existing", sortOrder: 4, parent: work)
            let ideas = Folder(name: "Ideas", sortOrder: 1)
            [work, existing, ideas].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(FolderTree.move(ideas, into: work, folders: folders))
            #expect(ideas.parent?.id == work.id)
            #expect(ideas.sortOrder == 5)
        }

        @Test("moving to nil makes it top-level")
        func moveToTopLevel() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work")
            let ideas = Folder(name: "Ideas", parent: work)
            [work, ideas].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(FolderTree.move(ideas, into: nil, folders: folders))
            #expect(ideas.parent == nil)
        }

        @Test("a folder can't move into itself")
        func notIntoItself() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work")
            ctx.insert(work)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(!FolderTree.move(work, into: work, folders: folders))
            #expect(work.parent == nil)
        }

        @Test("a folder can't move into its own descendant (would create a cycle)")
        func notIntoDescendant() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work")
            let design = Folder(name: "Design", parent: work)
            let ideas = Folder(name: "Ideas", parent: design)
            [work, design, ideas].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(!FolderTree.move(work, into: ideas, folders: folders))
            #expect(work.parent == nil)
        }

        @Test("moving to its current parent is a no-op")
        func notToCurrentParent() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work")
            let ideas = Folder(name: "Ideas", sortOrder: 3, parent: work)
            [work, ideas].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(!FolderTree.canMove(ideas, into: work, folders: folders))
            #expect(!FolderTree.canMove(work, into: nil, folders: folders))  // already top-level
            #expect(!FolderTree.move(ideas, into: work, folders: folders))
            #expect(ideas.sortOrder == 3)
        }
    }

    // MARK: - FolderTree.place (drag above/below a folder)

    @Suite("place")
    struct PlaceTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Bookmark.self, Folder.self, Tag.self,
                configurations: config
            )
            return ModelContext(container)
        }

        /// Top-level folders in sortOrder.
        private func order(_ folders: [Folder], parent: Folder? = nil) -> [String] {
            folders.filter { $0.parent?.id == parent?.id }.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
        }

        @Test("reorders siblings: drop C above A")
        func reorderBefore() throws {
            let ctx = try makeContext()
            let a = Folder(name: "A", sortOrder: 0), b = Folder(name: "B", sortOrder: 1), c = Folder(name: "C", sortOrder: 2)
            [a, b, c].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(FolderTree.place(c, besides: a, after: false, folders: folders))
            #expect(order(folders) == ["C", "A", "B"])
        }

        @Test("reorders siblings: drop A below B")
        func reorderAfter() throws {
            let ctx = try makeContext()
            let a = Folder(name: "A", sortOrder: 0), b = Folder(name: "B", sortOrder: 1), c = Folder(name: "C", sortOrder: 2)
            [a, b, c].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(FolderTree.place(a, besides: b, after: true, folders: folders))
            #expect(order(folders) == ["B", "A", "C"])
        }

        @Test("placing next to a nested folder moves it to that level")
        func placeIntoOtherLevel() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work", sortOrder: 0)
            let design = Folder(name: "Design", sortOrder: 0, parent: work)
            let home = Folder(name: "Home", sortOrder: 1)
            [work, design, home].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(FolderTree.place(home, besides: design, after: true, folders: folders))
            #expect(home.parent?.id == work.id)
            #expect(order(folders, parent: work) == ["Design", "Home"])
            #expect(order(folders) == ["Work"])
        }

        @Test("can't place a folder next to itself or inside its own subtree")
        func noCycles() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work")
            let design = Folder(name: "Design", parent: work)
            [work, design].forEach(ctx.insert)
            try ctx.save()
            let folders = try ctx.fetch(FetchDescriptor<Folder>())

            #expect(!FolderTree.place(work, besides: work, after: true, folders: folders))
            #expect(!FolderTree.place(work, besides: design, after: true, folders: folders))  // would nest Work in itself
            #expect(work.parent == nil)
        }
    }

    // MARK: - FolderDropZone (top quarter / middle / bottom quarter)

    @Suite("drop zone")
    struct DropZoneTests {
        @Test("top quarter is above, middle is inside, bottom quarter is below")
        func zones() {
            #expect(FolderDropZone(y: 2, rowHeight: 28) == .before)
            #expect(FolderDropZone(y: 14, rowHeight: 28) == .into)
            #expect(FolderDropZone(y: 26, rowHeight: 28) == .after)
        }

        @Test("unknown row height falls back to inside")
        func zeroHeight() {
            #expect(FolderDropZone(y: 0, rowHeight: 0) == .into)
        }
    }

    // MARK: - FolderTree.flattened

    @Suite("flattened")
    struct FlattenedTests {

        private func makeContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(
                for: Bookmark.self, Folder.self, Tag.self,
                configurations: config
            )
            return ModelContext(container)
        }

        @Test("empty input returns empty output")
        func empty() {
            #expect(FolderTree.flattened([]).isEmpty)
        }

        @Test("children follow their parent with a path label")
        func depthFirstWithPaths() throws {
            let ctx = try makeContext()
            let work = Folder(name: "Work", sortOrder: 0)
            let design = Folder(name: "Design", sortOrder: 0, parent: work)
            let home = Folder(name: "Home", sortOrder: 1)
            [work, design, home].forEach(ctx.insert)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            let paths = FolderTree.flattened(folders).map(\.path)
            #expect(paths == ["Work", "Work › Design", "Home"])
        }

        @Test("siblings are ordered by sortOrder")
        func siblingsBySortOrder() throws {
            let ctx = try makeContext()
            let b = Folder(name: "B", sortOrder: 1)
            let a = Folder(name: "A", sortOrder: 2)
            let c = Folder(name: "C", sortOrder: 0)
            [b, a, c].forEach(ctx.insert)
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            #expect(FolderTree.flattened(folders).map(\.path) == ["C", "B", "A"])
        }

        @Test("circular folders are skipped without stack overflow")
        func circularReference() throws {
            let ctx = try makeContext()
            let root = Folder(name: "Root")
            let a = Folder(name: "A")
            let b = Folder(name: "B")
            [root, a, b].forEach(ctx.insert)
            try ctx.save()
            a.parent = b
            b.parent = a
            try ctx.save()

            let folders = try ctx.fetch(FetchDescriptor<Folder>())
            // a↔b have no path to the root level, so only Root is reachable
            #expect(FolderTree.flattened(folders).map(\.path) == ["Root"])
        }
    }
}
