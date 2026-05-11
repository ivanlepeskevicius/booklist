import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Upload controls for attaching a custom image to a bookmark.
/// Supports Browse (Finder), Paste (clipboard), and Drag & Drop.
/// Calls `onImageSaved` with the local `file://` URL string on success.
struct ImageUploadZone: View {
    let onImageSaved: (String) -> Void

    @State private var isTargeted  = false
    @State private var uploadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: browseFiles) {
                    Label("Browse Files", systemImage: "folder")
                }
                .controlSize(.small)

                Button(action: pasteFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .controlSize(.small)

                if let err = uploadError {
                    Spacer()
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            // Drag-and-drop target
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                )
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
                .overlay {
                    Label("Drop an image here", systemImage: "photo.badge.arrow.down")
                        .font(.callout)
                        .foregroundStyle(isTargeted ? Color.accentColor : .tertiary)
                }
                .onDrop(of: [UTType.image, UTType.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers)
                    return true
                }
                .animation(.easeOut(duration: 0.15), value: isTargeted)
        }
    }

    // MARK: - Actions

    private func browseFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .bmp, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories   = false
        panel.message = "Choose an image for this bookmark"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else {
            uploadError = "Couldn't read that file."
            return
        }
        storeAndReport(image)
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        // Try raw image data first
        if let image = NSImage(pasteboard: pb) {
            storeAndReport(image)
            return
        }
        // Fall back to file URLs copied from Finder
        if let items = pb.readObjects(forClasses: [NSURL.self],
                                      options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = items.first,
           let image = NSImage(contentsOf: url) {
            storeAndReport(image)
            return
        }
        uploadError = "No image found on clipboard."
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        // Prefer direct image data
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                DispatchQueue.main.async { storeAndReport(image) }
            }
            return
        }
        // Fall back to file URL drop (e.g. from Finder)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data  = item as? Data,
                      let url   = URL(dataRepresentation: data, relativeTo: nil),
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async { storeAndReport(image) }
            }
        }
    }

    private func storeAndReport(_ image: NSImage) {
        uploadError = nil
        do {
            let url = try ImageStore.save(image)
            onImageSaved(url)
        } catch {
            uploadError = error.localizedDescription
        }
    }
}
