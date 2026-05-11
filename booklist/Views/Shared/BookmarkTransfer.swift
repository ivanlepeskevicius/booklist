import SwiftUI
import UniformTypeIdentifiers

/// Draggable payload carrying one or more bookmark UUIDs.
/// Uses ProxyRepresentation with String so the payload transfers as plain text —
/// no Info.plist UTType declaration needed and works reliably inside macOS List rows.
struct BookmarkTransfer: Transferable {
    let ids: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(
            exporting:  { $0.ids.map(\.uuidString).joined(separator: ",") },
            importing:  {
                BookmarkTransfer(ids: $0.split(separator: ",")
                    .compactMap { UUID(uuidString: String($0)) })
            }
        )
    }
}
