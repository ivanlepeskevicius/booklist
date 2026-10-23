import Foundation
import Testing
@testable import booklist

/// Launch-time cleanup. Runs against a scratch folder, never the app's real directories.
@Suite("StorageCleanup")
struct StorageCleanupTests {

    private let now = Date()
    private let old = Date(timeIntervalSinceNow: -3 * 24 * 60 * 60)

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func file(_ name: String, in dir: URL, modified: Date, bytes: Int = 4_096) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func exists(_ name: String, in dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    @Test("Old leftover download files are removed; recent ones and other files are kept")
    func staleDownloads() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        try file("CFNetworkDownload_old.tmp", in: dir, modified: old)
        try file("CFNetworkDownload_new.tmp", in: dir, modified: now)
        try file("something-else.tmp", in: dir, modified: old)

        let freed = StorageCleanup.removeStaleDownloads(in: dir, now: now)

        #expect(!exists("CFNetworkDownload_old.tmp", in: dir))
        #expect(exists("CFNetworkDownload_new.tmp", in: dir))
        #expect(exists("something-else.tmp", in: dir))
        #expect(freed >= 4_096)
    }

    @Test("Images no bookmark uses are removed after the grace period; referenced ones are kept")
    func orphanedImages() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let kept = try ["AAAA.jpg", "DDDD.jpg", "EEEE.jpg"].map { try file($0, in: dir, modified: old) }
        try file("BBBB.jpg", in: dir, modified: old)      // orphan, old → removed
        try file("CCCC.jpg", in: dir, modified: now)      // orphan, but maybe a capture in progress → kept

        let referenced = StorageCleanup.referencedFiles(kept.map(\.absoluteString) + ["https://example.com/remote.jpg"])
        StorageCleanup.removeOrphanedImages(in: dir, keeping: referenced, now: now)

        #expect(["AAAA.jpg", "DDDD.jpg", "EEEE.jpg"].allSatisfy { exists($0, in: dir) })
        #expect(!exists("BBBB.jpg", in: dir))
        #expect(exists("CCCC.jpg", in: dir))
    }

    @Test("Nothing is removed when the library is empty or most images look orphaned (moved/missing database)")
    func refusesMassDeletion() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let images = try (0..<10).map { try file("IMG\($0).jpg", in: dir, modified: old) }

        // Empty library: every image looks orphaned.
        #expect(StorageCleanup.removeOrphanedImages(in: dir, keeping: [], now: now) == 0)
        // Library that only knows 2 of 10 images (e.g. sample data in a fresh store).
        let few = StorageCleanup.referencedFiles(images.prefix(2).map(\.absoluteString))
        #expect(StorageCleanup.removeOrphanedImages(in: dir, keeping: few, now: now) == 0)
        #expect(images.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("Only local file URLs count as referenced images")
    func referencedFiles() {
        let files = StorageCleanup.referencedFiles([
            "file:///Users/me/Library/Application%20Support/lepi.booklist/Images/AAAA.jpg",
            "https://example.com/BBBB.jpg",
            "not a url",
        ])
        #expect(files == ["AAAA.jpg"])
    }
}
