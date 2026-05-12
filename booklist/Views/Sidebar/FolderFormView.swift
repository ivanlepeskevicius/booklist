import SwiftUI
import SwiftData

enum FolderFormMode {
    case add(parentID: UUID?)
    case edit(Folder)
}

/// Sheet for creating a new folder or editing an existing one.
struct FolderFormView: View {
    let mode: FolderFormMode
    /// Called with the newly created folder immediately before dismissal.
    /// Only fires in `.add` mode; ignored when editing.
    var onAdd: ((Folder) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    @State private var name     = ""
    @State private var icon     = "folder"
    @State private var colorHex = "#8B8B8B"

    @FocusState private var isNameFocused: Bool

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// True when another sibling folder at the same level already uses this name.
    private var hasDuplicateName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let parentID: UUID? = {
            switch mode {
            case .add(let pid): return pid
            case .edit(let folder): return folder.parent?.id
            }
        }()
        let editingID: UUID? = {
            if case .edit(let folder) = mode { return folder.id }
            return nil
        }()
        return allFolders.contains { folder in
            folder.parent?.id == parentID
                && folder.name.lowercased() == trimmed.lowercased()
                && folder.id != editingID
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add(let parentID): return parentID == nil ? "New Folder" : "New Subfolder"
        case .edit: return "Edit Folder"
        }
    }

    var body: some View {
        NavigationStack {
            // Custom layout instead of Form so TextFields are reliably left-aligned.
            // macOS .formStyle(.grouped) forces trailing text alignment on TextFields
            // and overrides multilineTextAlignment — a plain ScrollView avoids this.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    iconPreview

                    formGroup(title: "Name") {
                        TextField("", text: $name)
                            .focused($isNameFocused)
                            .textFieldStyle(.plain)
                            .padding(10)
                    }

                    formGroup(title: "Icon") {
                        IconPickerView(selectedIcon: $icon)
                    }

                    formGroup(title: "Color") {
                        ColorSwatchPicker(colorHex: $colorHex)
                            .padding(.vertical, 4)
                    }
                }
                .padding(20)
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || hasDuplicateName)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 380)
        .onAppear {
            loadInitialValues()
            if case .add = mode { isNameFocused = true }
        }
    }

    // MARK: - Subviews

    private var iconPreview: some View {
        HStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: colorHex).opacity(0.15))
                    .frame(width: 64, height: 64)
                if icon.isEmpty || isSFSymbolName(icon) {
                    Image(systemName: icon.isEmpty ? "folder" : icon)
                        .font(.system(size: 28))
                        .foregroundStyle(Color(hex: colorHex))
                } else {
                    Text(icon)
                        .font(.system(size: 28))
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func formGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Data

    private func loadInitialValues() {
        if case .edit(let folder) = mode {
            name     = folder.name
            icon     = folder.icon
            colorHex = folder.color
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let hexColor    = colorHex
        let validIcon   = icon.isEmpty ? "folder" : icon

        switch mode {
        case .add(let parentID):
            let parent = parentID.flatMap { id in allFolders.first { $0.id == id } }
            let siblings = allFolders.filter { $0.parent?.id == parentID }
            let nextOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
            let folder = Folder(
                name: trimmedName,
                icon: validIcon,
                color: hexColor,
                sortOrder: nextOrder,
                parent: parent
            )
            modelContext.insert(folder)
            onAdd?(folder)

        case .edit(let folder):
            folder.name = trimmedName
            folder.icon = validIcon
            folder.color = hexColor
        }

        dismiss()
    }
}
