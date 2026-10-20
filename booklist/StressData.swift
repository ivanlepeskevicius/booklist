#if DEBUG
import AppKit
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// A large, varied library for stress testing (`-uiTesting -stressItems 3000`). Only ever
/// used with the in-memory UI-test store; images are generated into the temporary folder,
/// never into the app's image store.
enum StressData {

    @MainActor
    static func populate(count: Int, in context: ModelContext) {
        var rng = SeededGenerator(seed: 42)
        let images = makeImagePool(size: 300)

        let tags = (0..<40).map { Tag(name: "tag-\($0)", color: Tag.randomColor()) }
        tags.forEach(context.insert)

        // 20 top-level folders, each with two subfolders — one of them nested a level deeper.
        var folders: [Folder] = []
        for i in 0..<20 {
            let root = Folder(name: "Folder \(i)", icon: "folder.fill", color: "#5B8BF5", sortOrder: i)
            let childA = Folder(name: "Folder \(i).A", icon: "star.fill", color: "#E67E22", sortOrder: 0, parent: root)
            let childB = Folder(name: "Folder \(i).B", icon: "😀", color: "#27AE60", sortOrder: 1, parent: root)
            let grandchild = Folder(name: "Folder \(i).A.1", icon: "leaf.fill", color: "#9B59B6", sortOrder: 0, parent: childA)
            [root, childA, childB, grandchild].forEach(context.insert)
            folders += [root, childA, childB, grandchild]
        }

        let words = ["design", "swift", "jazz", "reading", "lorem", "ipsum", "typography", "coffee",
                     "headphones", "travel", "recipe", "garden", "camera", "keyboard", "ADHD", "focus"]
        for i in 0..<count {
            let titleWords = (0..<Int.random(in: 2...14, using: &rng)).map { _ in words.randomElement(using: &rng) ?? "" }
            let isWishlist = Int.random(in: 0..<100, using: &rng) < 15
            let image: String? = switch Int.random(in: 0..<100, using: &rng) {
            case 0..<70: images.isEmpty ? nil : images[i % images.count]
            case 70..<75: "https://invalid.invalid/missing-\(i).jpg"   // dead image link
            default: nil
            }
            let note: String? = switch Int.random(in: 0..<10, using: &rng) {
            case 0..<5: nil
            case 5..<9: titleWords.joined(separator: " ")
            default: Array(repeating: titleWords.joined(separator: " "), count: 30).joined(separator: "\n")
            }
            let bookmark = Bookmark(
                title: "\(i) " + titleWords.joined(separator: " "),
                url: "https://example\(i % 97).com/item/\(i)",
                pageDescription: Int.random(in: 0..<2, using: &rng) == 0 ? nil : titleWords.reversed().joined(separator: " "),
                note: note,
                imageURLs: image.map { [$0] } ?? [],
                selectedImageURL: image,
                itemType: isWishlist ? .wishlistItem : .bookmark,
                price: isWishlist ? "€\(Int.random(in: 5...900, using: &rng)).99" : nil,
                collection: Int.random(in: 0..<100, using: &rng) < 20 ? nil : folders.randomElement(using: &rng),
                tags: (0..<Int.random(in: 0...3, using: &rng)).compactMap { _ in tags.randomElement(using: &rng) }
            )
            bookmark.dateAdded = Date(timeIntervalSinceNow: -Double(i) * 3_600)
            context.insert(bookmark)
        }
    }

    /// Full-size JPEGs in a mix of aspect ratios, so card thumbnails do real decode work.
    /// Generated once per machine and reused.
    private static func makeImagePool(size: Int) -> [String] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("booklist-stress-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dimensions = [(1600, 1200), (1200, 1600), (1600, 1600), (2400, 1000), (900, 1800)]
        var result: [String] = []
        for i in 0..<size {
            let fileURL = directory.appendingPathComponent("stress-\(i).jpg")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let (width, height) = dimensions[i % dimensions.count]
                guard let image = drawImage(width: width, height: height, hue: CGFloat(i) / CGFloat(size)),
                      let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
                else { continue }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { continue }
            }
            result.append(fileURL.absoluteString)
        }
        return result
    }

    private static func drawImage(width: Int, height: Int, hue: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(NSColor(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for band in 0..<12 {
            let shade = NSColor(hue: (hue + CGFloat(band) * 0.07).truncatingRemainder(dividingBy: 1),
                                saturation: 0.6, brightness: 0.7, alpha: 0.6)
            context.setFillColor(shade.cgColor)
            context.fillEllipse(in: CGRect(x: band * width / 12, y: (band * 37) % height,
                                           width: width / 4, height: height / 4))
        }
        return context.makeImage()
    }
}

/// Deterministic random numbers, so every stress run builds the same library.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
#endif
