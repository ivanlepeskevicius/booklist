import SwiftUI
import SwiftData

enum FolderFormMode {
    case add(parent: Folder?)
    case edit(Folder)
}

/// Sheet for creating a new folder or editing an existing one.
struct FolderFormView: View {
    let mode: FolderFormMode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Folder.sortOrder) private var allFolders: [Folder]

    @State private var name = ""
    @State private var icon = "folder"
    @State private var color = Color(hex: "#8B8B8B")

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                // Live preview of the folder icon
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(color.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Image(systemName: icon.isEmpty ? "folder" : icon)
                                .font(.system(size: 28))
                                .foregroundStyle(color)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)

                Section("Name") {
                    TextField("e.g. Design", text: $name)
                }

                Section {
                    HStack {
                        TextField("SF Symbol name", text: $icon)
                        Image(systemName: icon.isEmpty ? "folder" : icon)
                            .foregroundStyle(color)
                            .frame(width: 24, height: 24)
                    }
                    Text("Type any SF Symbol name — e.g. \"music.note\", \"star\", \"book.fill\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Icon")
                }

                Section("Color") {
                    ColorPicker("Folder color", selection: $color, supportsOpacity: false)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Folder" : "New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 380)
        .onAppear { loadInitialValues() }
    }

    private func loadInitialValues() {
        if case .edit(let folder) = mode {
            name = folder.name
            icon = folder.icon
            color = Color(hex: folder.color)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let hexColor = color.toHex() ?? "#8B8B8B"
        let validIcon = icon.isEmpty ? "folder" : icon

        switch mode {
        case .add(let parent):
            let siblings = parent?.children ?? allFolders.filter { $0.parent == nil }
            let nextOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
            let folder = Folder(
                name: trimmedName,
                icon: validIcon,
                color: hexColor,
                sortOrder: nextOrder,
                parent: parent
            )
            modelContext.insert(folder)

        case .edit(let folder):
            folder.name = trimmedName
            folder.icon = validIcon
            folder.color = hexColor
        }

        dismiss()
    }
}
