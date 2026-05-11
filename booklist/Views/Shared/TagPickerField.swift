import SwiftUI
import SwiftData

/// Type-to-filter-or-create tag picker.
///
/// Shows selected tags as dismissable colored pills.
/// While typing, a dropdown appears filtered to matching tags.
/// If no exact match exists, a "Create '#name'" option is shown first.
struct TagPickerField: View {
    @Binding var selectedTags: [Tag]

    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @FocusState private var isFieldFocused: Bool

    private let maxSuggestions = 6

    private var trimmed: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestions: [Tag] {
        guard !trimmed.isEmpty else { return [] }
        let selectedIDs = Set(selectedTags.map(\.id))
        return allTags
            .filter { !selectedIDs.contains($0.id) }
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .prefix(maxSuggestions)
            .map { $0 }
    }

    private var exactMatchExists: Bool {
        allTags.contains { $0.name.lowercased() == trimmed.lowercased() }
    }

    private var showDropdown: Bool {
        isFieldFocused && !trimmed.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Selected pills
            if !selectedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(selectedTags) { tag in
                            selectedPill(tag)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            // Search / create field
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField(selectedTags.isEmpty ? "Add a tag…" : "Add another…", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { handleSubmit() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .focusRing(when: isFieldFocused, cornerRadius: 7)

            // Inline dropdown
            if showDropdown {
                VStack(spacing: 0) {
                    if !exactMatchExists {
                        createRow
                        if !suggestions.isEmpty {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                    ForEach(suggestions) { tag in
                        existingRow(tag)
                    }
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(10)
            }
        }
        .zIndex(showDropdown ? 1 : 0)
        .animation(.easeInOut(duration: 0.12), value: showDropdown)
    }

    // MARK: - Selected pill

    private func selectedPill(_ tag: Tag) -> some View {
        HStack(spacing: 3) {
            Text("#\(tag.name)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Button {
                selectedTags.removeAll { $0.id == tag.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(hex: tag.color), in: Capsule())
    }

    // MARK: - Create row

    private var createRow: some View {
        Button { createAndSelect() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 11))
                HStack(spacing: 0) {
                    Text("Create ")
                        .foregroundStyle(.secondary)
                    Text("#\(trimmed)")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .font(.callout)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Existing tag row

    private func existingRow(_ tag: Tag) -> some View {
        Button { select(tag) } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: tag.color))
                    .frame(width: 8, height: 8)
                Text("#\(tag.name)")
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func handleSubmit() {
        if exactMatchExists {
            if let tag = allTags.first(where: { $0.name.lowercased() == trimmed.lowercased() }),
               !selectedTags.contains(where: { $0.id == tag.id }) {
                select(tag)
            }
        } else if !trimmed.isEmpty {
            createAndSelect()
        }
    }

    private func select(_ tag: Tag) {
        guard !selectedTags.contains(where: { $0.id == tag.id }) else { return }
        selectedTags.append(tag)
        searchText = ""
    }

    private func createAndSelect() {
        let name = trimmed
        guard !name.isEmpty else { return }
        let tag = Tag(name: name, color: Tag.randomColor())
        modelContext.insert(tag)
        selectedTags.append(tag)
        searchText = ""
    }
}
