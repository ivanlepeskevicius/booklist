import Foundation
import SwiftData

/// Populates the SwiftData store with realistic sample data for development.
/// Only runs if the store is empty, so it is safe to call on every launch in DEBUG builds.
struct SampleData {

    @MainActor
    static func populate(in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Bookmark>())) == 0 else { return }
        insertAll(into: context)
    }

    // MARK: - Private

    @MainActor
    private static func insertAll(into context: ModelContext) {

        // ── Tags ────────────────────────────────────────────────
        let tagDesign      = Tag(name: "design",       color: "#5B8BF5")
        let tagInspiration = Tag(name: "inspiration",  color: "#9B59B6")
        let tagTool        = Tag(name: "tool",         color: "#27AE60")
        let tagMusic       = Tag(name: "music",        color: "#E74C3C")
        let tagBuy         = Tag(name: "want-to-buy",  color: "#E67E22")
        [tagDesign, tagInspiration, tagTool, tagMusic, tagBuy].forEach { context.insert($0) }

        // ── Root folders ────────────────────────────────────────
        let folderDesign  = Folder(name: "Design",  icon: "paintbrush.fill", color: "#5B8BF5", sortOrder: 0)
        let folderMusic   = Folder(name: "Music",   icon: "music.note",      color: "#E74C3C", sortOrder: 1)
        let folderReading = Folder(name: "Reading", icon: "book.fill",       color: "#F39C12", sortOrder: 2)
        [folderDesign, folderMusic, folderReading].forEach { context.insert($0) }

        // ── Sub-folders ─────────────────────────────────────────
        let folderUI   = Folder(name: "UI Components", icon: "square.3.layers.3d", color: "#5B8BF5", sortOrder: 0, parent: folderDesign)
        let folderTypo = Folder(name: "Typography",    icon: "textformat",          color: "#7B68EE", sortOrder: 1, parent: folderDesign)
        let folderJazz = Folder(name: "Jazz",          icon: "music.mic",           color: "#E74C3C", sortOrder: 0, parent: folderMusic)
        [folderUI, folderTypo, folderJazz].forEach { context.insert($0) }

        // ── Bookmarks ───────────────────────────────────────────
        let items: [Bookmark] = [

            // Design › UI Components
            make(
                title: "shadcn/ui — Build your component library",
                url: "https://ui.shadcn.com",
                desc: "Beautifully designed components that you can copy and paste into your apps.",
                note: "Study their accessible-by-default approach. Could inform our own component decisions.",
                image: "https://picsum.photos/seed/shadcn/600/400",
                collection: folderUI, tags: [tagDesign, tagTool], daysAgo: 1
            ),
            make(
                title: "Radix Primitives — Unstyled, accessible components",
                url: "https://www.radix-ui.com",
                desc: "An open-source UI component library for building high-quality design systems.",
                note: "Perfect if you want full styling control with zero opinion on visuals.",
                image: "https://picsum.photos/seed/radix/600/400",
                collection: folderUI, tags: [tagDesign], daysAgo: 3
            ),
            make(
                title: "Tailwind CSS — A utility-first CSS framework",
                url: "https://tailwindcss.com",
                desc: "Rapidly build modern websites without ever leaving your HTML.",
                note: nil,
                image: "https://picsum.photos/seed/tailwind/600/320",
                collection: folderUI, tags: [tagDesign, tagTool], daysAgo: 5
            ),

            // Design › Typography
            make(
                title: "Fonts In Use — A public archive of typography",
                url: "https://fontsinuse.com",
                desc: "A searchable archive of typographic design cataloguing real-world use of typefaces.",
                note: "Incredible reference for type inspiration — filter by industry and era.",
                image: "https://picsum.photos/seed/fontsuse/600/380",
                collection: folderTypo, tags: [tagDesign, tagInspiration], daysAgo: 7
            ),
            make(
                title: "Practical Typography by Matthew Butterick",
                url: "https://practicaltypography.com",
                desc: "A guide to better typography for anyone who works with words.",
                note: nil,
                image: "https://picsum.photos/seed/typography/600/400",
                collection: folderTypo, tags: [tagDesign], daysAgo: 12
            ),

            // Design (root)
            make(
                title: "Figma — The collaborative interface design tool",
                url: "https://figma.com",
                desc: "Figma connects everyone in the design process so teams can deliver better products, faster.",
                note: "Re-evaluate for the team — their new AI features look promising for rapid iteration.",
                image: "https://picsum.photos/seed/figma/600/400",
                collection: folderDesign, tags: [tagDesign, tagTool], daysAgo: 2
            ),

            // Music › Jazz
            make(
                title: "Miles Davis — Kind of Blue (Full Album)",
                url: "https://www.youtube.com/watch?v=ylXk1LBvIqU",
                desc: "The best-selling jazz album of all time. Recorded in 1959.",
                note: "The album that got me into jazz. Come back to this on creative work days.",
                image: "https://picsum.photos/seed/miles/600/600",
                collection: folderJazz, tags: [tagMusic, tagInspiration], daysAgo: 14
            ),
            make(
                title: "Bill Evans Trio — Waltz for Debby",
                url: "https://www.youtube.com/watch?v=XpJahQjAiFo",
                desc: "One of the most celebrated piano trio albums in jazz history.",
                note: nil,
                image: "https://picsum.photos/seed/billevans/600/600",
                collection: folderJazz, tags: [tagMusic], daysAgo: 20
            ),

            // Reading
            make(
                title: "Deep Work by Cal Newport — Summary",
                url: "https://www.samuelthomasdavies.com/book-summaries/business/deep-work/",
                desc: "Rules for focused success in a distracted world.",
                note: "Buy the book. The section on rituals is exactly what I need to implement this week.",
                image: "https://picsum.photos/seed/deepwork/600/400",
                collection: folderReading, tags: [tagInspiration], daysAgo: 4
            ),
            make(
                title: "Getting Things Done — David Allen",
                url: "https://gettingthingsdone.com",
                desc: "GTD is a personal productivity methodology that reduces cognitive overhead.",
                note: nil,
                image: "https://picsum.photos/seed/gtd/600/420",
                collection: folderReading, tags: [], daysAgo: 20
            ),

            // Inbox (no collection — unclassified)
            make(
                title: "How ADHD Rewires Your Brain — ADDitude",
                url: "https://www.additudemag.com/adhd-brain-neuroscience/",
                desc: "Understanding the neuroscience behind attention deficit hyperactivity disorder.",
                note: "READ THIS. Finally explains why building the capture habit matters so much.",
                image: "https://picsum.photos/seed/adhd/600/400",
                collection: nil, tags: [], daysAgo: 0
            ),
            make(
                title: "SwiftUI by Example — Hacking with Swift",
                url: "https://www.hackingwithswift.com/quick-start/swiftui",
                desc: "The most complete guide to SwiftUI, with hundreds of tutorials.",
                note: "Bookmark for reference while building booklist.",
                image: "https://picsum.photos/seed/swiftui/600/400",
                collection: nil, tags: [tagTool], daysAgo: 0
            ),

            // Wishlist item
            makeWishlist(
                title: "Sony WH-1000XM5 Wireless Headphones",
                url: "https://www.sony.com/en/articles/wh-1000xm5",
                image: "https://picsum.photos/seed/sonyheadphones/600/600",
                price: "€349.00",
                collection: nil, tags: [tagBuy], daysAgo: 8
            ),
        ]

        items.forEach { context.insert($0) }
    }

    // MARK: - Factories

    private static func make(
        title: String,
        url: String,
        desc: String?,
        note: String?,
        image: String?,
        collection: Folder?,
        tags: [Tag],
        daysAgo: Int
    ) -> Bookmark {
        let b = Bookmark(
            title: title,
            url: url,
            pageDescription: desc,
            note: note,
            imageURLs: image.map { [$0] } ?? [],
            selectedImageURL: image,
            collection: collection,
            tags: tags
        )
        if daysAgo > 0 {
            b.dateAdded = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        }
        return b
    }

    private static func makeWishlist(
        title: String,
        url: String,
        image: String?,
        price: String,
        collection: Folder?,
        tags: [Tag],
        daysAgo: Int
    ) -> Bookmark {
        let b = Bookmark(
            title: title,
            url: url,
            imageURLs: image.map { [$0] } ?? [],
            selectedImageURL: image,
            itemType: .wishlistItem,
            price: price,
            collection: collection,
            tags: tags
        )
        if daysAgo > 0 {
            b.dateAdded = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        }
        return b
    }
}
