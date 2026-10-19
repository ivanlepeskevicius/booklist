import SwiftUI

/// Multi-line note input. A TextEditor rather than `TextField(axis: .vertical)`: on macOS,
/// Return in a TextField commits the edit (and selects all the text) instead of inserting a
/// newline. TextEditor has no placeholder of its own, so one is overlaid while empty.
struct NoteEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)   // matches TextEditor's built-in text inset
                        .allowsHitTesting(false)
                }
            }
    }
}
