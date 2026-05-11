import AppKit
import Foundation

/// Persists user-provided images to the app's Application Support folder and returns
/// a `file://` URL string that can be stored in `Bookmark.selectedImageURL`.
struct ImageStore {

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("lepi.booklist/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Converts `image` to JPEG and writes it to disk.  Returns the `file://` URL string.
    static func save(_ image: NSImage) throws -> String {
        guard let tiff   = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg   = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { throw StoreError.conversionFailed }

        let fileURL = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        try jpeg.write(to: fileURL)
        return fileURL.absoluteString
    }

    enum StoreError: LocalizedError {
        case conversionFailed
        var errorDescription: String? { "Couldn't process the image." }
    }
}
