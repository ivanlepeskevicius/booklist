import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTExportedTypeDeclarations). Distinct from BookmarkTransfer's
    /// type so folder rows can accept folders and bookmarks with separate handlers.
    static let folderTransfer = UTType(exportedAs: "com.booklist.folder-transfer")
}

// MARK: - Drag state

/// The folder currently being dragged in the sidebar. Set when the drag starts so drop targets
/// can read it synchronously — folder drags never leave the app, so there's nothing to decode.
@MainActor
enum FolderDrag {
    static var draggedID: UUID?

    static func itemProvider(for folder: Folder) -> NSItemProvider {
        draggedID = folder.id
        let id = folder.id
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.folderTransfer.identifier,
                                            visibility: .ownProcess) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        return provider
    }
}

// MARK: - Drop zones

/// Where a dragged folder lands relative to the row under the pointer — like the Finder
/// sidebar: top quarter = above (same level), middle = inside, bottom quarter = below.
nonisolated enum FolderDropZone: Equatable {
    case before, into, after

    init(y: CGFloat, rowHeight: CGFloat) {
        guard rowHeight > 0 else { self = .into; return }
        if y < rowHeight * 0.25 {
            self = .before
        } else if y > rowHeight * 0.75 {
            self = .after
        } else {
            self = .into
        }
    }
}

// MARK: - Drop handling

/// Handles folder drops on a sidebar row (`target`), or on the "Library" header (`target == nil`,
/// always "into" = make top-level). Uses DropDelegate because it reports the pointer position
/// while dragging, which drives the before/into/after indicator.
struct FolderDropDelegate: DropDelegate {
    let target: Folder?
    let allFolders: [Folder]
    let rowHeight: CGFloat
    @Binding var zone: FolderDropZone?

    private var dragged: Folder? {
        FolderDrag.draggedID.flatMap { id in allFolders.first { $0.id == id } }
    }

    private func zone(for info: DropInfo) -> FolderDropZone {
        target == nil ? .into : FolderDropZone(y: info.location.y, rowHeight: rowHeight)
    }

    private func isAllowed(_ folder: Folder, _ zone: FolderDropZone) -> Bool {
        switch (zone, target) {
        case (.into, let target):         FolderTree.canMove(folder, into: target, folders: allFolders)
        case (_, let target?):            FolderTree.canPlace(folder, besides: target, folders: allFolders)
        case (_, nil):                    false
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.folderTransfer])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let newZone = zone(for: info)
        guard let dragged, isAllowed(dragged, newZone) else {
            zone = nil
            return DropProposal(operation: .forbidden)
        }
        zone = newZone
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        zone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let dropZone = zone(for: info)
        zone = nil
        defer { FolderDrag.draggedID = nil }
        guard let dragged, isAllowed(dragged, dropZone) else { return false }
        switch (dropZone, target) {
        case (.into, let target):
            return FolderTree.move(dragged, into: target, folders: allFolders)
        case (.before, let target?):
            return FolderTree.place(dragged, besides: target, after: false, folders: allFolders)
        case (.after, let target?):
            return FolderTree.place(dragged, besides: target, after: true, folders: allFolders)
        case (_, nil):
            return false
        }
    }
}

// MARK: - Indicator

extension View {
    /// Accent line above/below the row, or an outline around it, for the current drop zone.
    func folderDropIndicator(_ zone: FolderDropZone?) -> some View {
        overlay(alignment: zone == .after ? .bottom : .top) {
            if zone == .before || zone == .after {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if zone == .into {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }
}
