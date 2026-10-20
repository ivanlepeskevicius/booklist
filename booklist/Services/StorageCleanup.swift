import Foundation

/// Launch-time housekeeping so booklist's disk use doesn't creep up over time.
///
/// Found by measuring a real install: 705 MB of `CFNetworkDownload_*.tmp` files left in the
/// app's temporary folder by older builds (image downloads whose temp files were never
/// removed), and saved images that no bookmark used any more (deleted bookmarks, unchosen
/// capture candidates).
nonisolated enum StorageCleanup {

    /// Files younger than this are left alone — a capture or import may still be using them.
    static let gracePeriod: TimeInterval = 24 * 60 * 60

    /// `referencedImageFiles`: file names (e.g. "<uuid>.jpg") of every image a bookmark points at.
    /// Runs off the main thread; returns the bytes freed.
    @discardableResult
    static func run(referencedImageFiles: Set<String>, now: Date = Date()) async -> Int {
        await Task.detached(priority: .background) {
            removeStaleDownloads(in: FileManager.default.temporaryDirectory, now: now)
                + removeOrphanedImages(in: ImageStore.directory, keeping: referencedImageFiles, now: now)
        }.value
    }

    /// File names of the local images the given bookmark image URLs point at.
    static func referencedFiles(_ imageURLs: [String]) -> Set<String> {
        Set(imageURLs.compactMap { URL(string: $0) }.filter(\.isFileURL).map(\.lastPathComponent))
    }

    static func removeStaleDownloads(in directory: URL, now: Date) -> Int {
        remove(in: directory, now: now) { $0.hasPrefix("CFNetworkDownload_") && $0.hasSuffix(".tmp") }
    }

    static func removeOrphanedImages(in directory: URL, keeping referenced: Set<String>, now: Date) -> Int {
        remove(in: directory, now: now) { !referenced.contains($0) }
    }

    private static func remove(in directory: URL, now: Date, where shouldRemove: (String) -> Bool) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .totalFileAllocatedSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        var freed = 0
        for file in files where shouldRemove(file.lastPathComponent) {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, now.timeIntervalSince(modified) > gracePeriod
            else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil {
                freed += values.totalFileAllocatedSize ?? 0
            }
        }
        return freed
    }
}
