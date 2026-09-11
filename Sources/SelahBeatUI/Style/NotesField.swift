import SwiftUI

/// A multi-line notes field.
///
/// Uses TextEditor rather than `TextField(axis: .vertical)`, which does not
/// reliably accept focus inside a grouped Form on macOS - the field renders,
/// shows its placeholder, and silently refuses to be typed in.
public struct NotesField: View {
    private let placeholder: String
    @Binding private var text: String
    private let minHeight: CGFloat

    public init(_ placeholder: String, text: Binding<String>, minHeight: CGFloat = 72) {
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    // Must not swallow the tap that focuses the editor.
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(.leading, -1)
        }
        .font(.body)
    }
}
