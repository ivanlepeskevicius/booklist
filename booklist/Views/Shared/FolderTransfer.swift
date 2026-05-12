import SwiftUI
import UniformTypeIdentifiers

/// Draggable payload carrying a single folder UUID for reparenting in the sidebar.
/// Uses a custom UTType (CodableRepresentation) so it doesn't conflict with
/// BookmarkTransfer, which uses ProxyRepresentation/.plainText.
struct FolderTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .folderTransfer)
    }
}

extension UTType {
    static let folderTransfer = UTType(exportedAs: "com.booklist.folder-transfer")
}
