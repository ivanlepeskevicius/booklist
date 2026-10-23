import Foundation
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

struct ExportService {

    // MARK: - Codable snapshot (shared with ImportService for round-trip fidelity)

    struct ExportItem: Codable {
        let title: String
        let url: String
        let note: String?
        let price: String?
        let isWishlistItem: Bool
        let imageURL: String?
        let tags: [String]
        let folderPath: String?
    }

    static func makeExportItems(from bookmarks: [Bookmark]) -> [ExportItem] {
        bookmarks.map { bm in
            ExportItem(
                title: bm.title,
                url: bm.url,
                note: bm.note,
                price: bm.price,
                isWishlistItem: bm.itemType == .wishlistItem,
                imageURL: bm.selectedImageURL,
                tags: bm.tags.map(\.name),
                folderPath: bm.collection?.name
            )
        }
    }

    nonisolated static func generateHTML(items: [ExportItem], title: String) -> String {
        let jsonData  = (try? JSONEncoder().encode(items)) ?? Data()
        let jsonStr   = String(data: jsonData, encoding: .utf8) ?? "[]"
        let itemCount = items.count
        let cards     = items.map(cardHTML).joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(esc(title))</title>
            <script id="__BOOKLIST_DATA__" type="application/json">\(jsonStr)</script>
            <style>\(css)</style>
        </head>
        <body>
            <header>
                <h1>\(esc(title))</h1>
                <p class="subtitle">\(itemCount) item\(itemCount == 1 ? "" : "s")</p>
            </header>
            <main class="grid">
        \(cards)
            </main>
            <footer><p>Shared via booklist</p></footer>
        </body>
        </html>
        """
    }

    // MARK: - Private helpers

    private nonisolated static func cardHTML(_ item: ExportItem) -> String {
        let imgTag   = item.imageURL.map {
            "<img src=\"\(esc($0))\" alt=\"\" class=\"card-img\" loading=\"lazy\">"
        } ?? ""
        let noteTag  = item.note.map { "<p class=\"card-note\">\(esc($0))</p>" } ?? ""
        let priceTag = item.price.map { "<span class=\"card-price\">\(esc($0))</span>" } ?? ""
        let tagsHTML = item.tags.map { "<span class=\"tag\">#\(esc($0))</span>" }.joined()
        let tagDiv   = tagsHTML.isEmpty ? "" : "<div class=\"tags\">\(tagsHTML)</div>"
        let extraClass = item.isWishlistItem ? " wishlist" : ""

        return """
            <a href="\(esc(item.url))" class="card\(extraClass)" target="_blank" rel="noopener noreferrer">
                \(imgTag)
                <div class="card-body">
                    <div class="card-title">\(esc(item.title))</div>
                    \(noteTag)
                    \(priceTag)
                    \(tagDiv)
                    <div class="card-url">\(esc(item.url))</div>
                </div>
            </a>
        """
    }

    private nonisolated static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // Minified CSS for the exported HTML page
    private nonisolated static let css = """
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#f5f5f7;color:#1d1d1f;-webkit-font-smoothing:antialiased}
        header{padding:48px 24px 24px;text-align:center}
        h1{font-size:28px;font-weight:700;letter-spacing:-.5px}
        .subtitle{color:#6e6e73;margin-top:6px;font-size:15px}
        .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px;padding:24px;max-width:1200px;margin:0 auto}
        .card{background:#fff;border-radius:14px;overflow:hidden;text-decoration:none;color:inherit;display:flex;flex-direction:column;box-shadow:0 2px 8px rgba(0,0,0,.08);transition:transform .15s,box-shadow .15s}
        .card:hover{transform:translateY(-3px);box-shadow:0 8px 24px rgba(0,0,0,.12)}
        .card-img{width:100%;aspect-ratio:16/9;object-fit:cover}
        .card-body{padding:14px;flex:1;display:flex;flex-direction:column;gap:6px}
        .card-title{font-weight:600;font-size:14px;line-height:1.4}
        .card-note{font-size:13px;color:#6e6e73;line-height:1.5}
        .card-url{font-size:11px;color:#aeaeb2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:auto;padding-top:6px}
        .card-price{font-size:16px;font-weight:700;color:#0071e3}
        .tags{display:flex;flex-wrap:wrap;gap:4px}
        .tag{font-size:11px;background:#e8f0fe;color:#1a73e8;padding:2px 8px;border-radius:100px;font-weight:500}
        footer{text-align:center;padding:40px;color:#aeaeb2;font-size:13px}
    """
}

// MARK: - Transferable wrapper for ShareLink

struct BookmarksExport: Transferable {
    let ids: [PersistentIdentifier]
    let container: ModelContainer?
    let title: String

    /// Keeps only the bookmarks' IDs; the export itself is built when the user actually shares.
    /// Building it here made every redraw of a share button walk the whole visible list
    /// (measured: a large share of each update on a 1,027-item library). The models are read on
    /// the main actor inside the export closure, so SwiftData is never touched off it.
    init(bookmarks: [Bookmark], title: String) {
        self.ids = bookmarks.map(\.persistentModelID)
        self.container = bookmarks.first?.modelContext?.container
        self.title = title
    }

    @MainActor
    func makeItems() -> [ExportService.ExportItem] {
        guard let context = container?.mainContext else { return [] }
        let bookmarks = ids.compactMap { context.model(for: $0) as? Bookmark }
        return ExportService.makeExportItems(from: bookmarks)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .html) { export in
            let items = await export.makeItems()
            let html = ExportService.generateHTML(items: items, title: export.title)
            return Data(html.utf8)
        }
    }
}
