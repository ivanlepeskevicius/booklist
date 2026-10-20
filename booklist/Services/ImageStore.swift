import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Persists user-provided images to the app's Application Support folder and returns
/// a `file://` URL string that can be stored in `Bookmark.selectedImageURL`.
struct ImageStore {

    /// Longest side, in pixels, of images written to disk. Cards never display larger than this.
    private static let maxStoredPixelSize = 1600

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("lepi.booklist/Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downloads a remote image and saves it to disk.  Returns the `file://` URL string.
    static func download(from url: URL) async throws -> String {
        guard let data = try await fetchRemote(url) else { throw StoreError.conversionFailed }
        let maxSize = maxStoredPixelSize
        guard let image = await Task.detached(operation: { downsample(data, maxPixelSize: maxSize) }).value
        else { throw StoreError.conversionFailed }
        return try save(image)
    }

    /// Converts `image` to JPEG and writes it to disk.  Returns the `file://` URL string.
    static func save(_ image: NSImage) throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw StoreError.conversionFailed }
        return try save(cgImage)
    }

    /// Writes JPEG straight from the CGImage, scaling down oversized images on the way.
    /// Avoids `tiffRepresentation`, which makes a full uncompressed copy in memory.
    private static func save(_ cgImage: CGImage) throws -> String {
        let fileURL = directory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw StoreError.conversionFailed }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
            kCGImageDestinationImageMaxPixelSize: maxStoredPixelSize,
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.conversionFailed }
        return fileURL.absoluteString
    }

    // MARK: - Thumbnails

    /// Decoded thumbnails shared by all cards, so re-renders and scrolling don't re-decode images.
    /// NSCache evicts automatically under memory pressure.
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 150 * 1024 * 1024
        return cache
    }()

    /// Remote images that failed this session (404, error page, undecodable). Cards re-request
    /// their image every time they scroll back on screen, so without this a dead link would be
    /// re-downloaded over and over.
    private static var failedRemoteURLs: Set<URL> = []

    /// Loads a local or remote image decoded at no more than `maxPixelSize` on its longest side.
    /// Decoding at display size instead of full resolution is what keeps memory low.
    static func thumbnail(for url: URL, maxPixelSize: Int) async -> NSImage? {
        let key = "\(maxPixelSize)|\(url.absoluteString)" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard !failedRemoteURLs.contains(url) else { return nil }

        let data: Data?
        if url.isFileURL {
            data = await Task.detached { try? Data(contentsOf: url) }.value
        } else {
            data = try? await fetchRemote(url)
        }
        guard let data,
              let cgImage = await Task.detached(operation: { downsample(data, maxPixelSize: maxPixelSize) }).value
        else {
            if !url.isFileURL { failedRemoteURLs.insert(url) }
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailCache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    private static var aspectCache: [String: CGFloat] = [:]

    /// Width ÷ height of a saved (local) image, read from the file header without decoding the
    /// pixels — masonry uses it to place cards before they're built. nil for remote images.
    static func aspectRatio(ofLocalImage urlString: String) -> CGFloat? {
        if let cached = aspectCache[urlString] { return cached }
        guard let url = URL(string: urlString), url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0 else { return nil }
        // EXIF orientations 5–8 are rotated 90°, so the displayed width is the stored height.
        let rotated = ((properties[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
        let aspect = rotated ? height / width : width / height
        aspectCache[urlString] = aspect
        return aspect
    }

    /// Fetches a remote URL, returning nil for non-2xx responses — a 404 page is HTML, not an
    /// image, and handing it to ImageIO only produces decode errors.
    private static func fetchRemote(_ url: URL) async throws -> Data? {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return data
    }

    /// Decodes image data directly at a reduced size without ever holding the full-resolution bitmap.
    /// Images smaller than `maxPixelSize` are left at their original size.
    nonisolated private static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    enum StoreError: LocalizedError {
        case conversionFailed
        var errorDescription: String? { "Couldn't process the image." }
    }
}
