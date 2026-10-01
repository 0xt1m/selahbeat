import SwiftUI

/// A text input with a small tag-style label above a clearly bordered box.
///
/// A plain `TextField("Title", ...)` in a grouped Form on macOS renders the
/// title as a row label with a borderless, empty field beside it, so the
/// only visible text is the part that does nothing when clicked. Here the
/// label sits above, the box looks like an input, and clicking either one
/// focuses it.
public struct LabeledTextField: View {
    private let label: String
    private let placeholder: String
    @Binding private var text: String
    @FocusState private var focused: Bool

    public init(_ label: String, placeholder: String = "", text: Binding<String>) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(focused ? Theme.accent : Theme.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill((focused ? Theme.accent : Theme.secondaryText).opacity(0.14))
                )
                .onTapGesture { focused = true }

            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.secondaryText.opacity(0.6)))
                .textFieldStyle(.plain)
                .labelsHidden()
                // The box is painted from the theme, so the text has to be as
                // well: left to the system it turns dark-on-dark the moment the
                // window is in light appearance.
                .foregroundStyle(Theme.primaryText)
                .focused($focused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(focused ? Theme.accent : Theme.secondaryText.opacity(0.35),
                                      lineWidth: focused ? 1.5 : 1)
                )
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
        }
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}
