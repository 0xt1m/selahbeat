import SwiftUI

/// Puts a Done button on the bar above the keyboard.
///
/// A numeric keypad has no return key, so without this a tempo field can be
/// typed into and then not dismissed - and even on a full keyboard, tapping
/// away is not obvious when the keyboard covers half the screen.
public extension View {
    func keyboardDoneButton() -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        #else
        self
        #endif
    }
}

/// A button that puts the keyboard away, and that exists only while there is
/// a keyboard to put away.
///
/// Watching the system notifications rather than a `@FocusState` binding: the
/// fields on a form each own their own focus, and what matters here is simply
/// whether the keyboard is covering the screen.
public struct KeyboardDismissButton: View {
    @State private var isKeyboardVisible = false

    public init() {}

    public var body: some View {
        #if os(iOS)
        Group {
            if isKeyboardVisible {
                Button {
                    dismissKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Hide keyboard")
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .animation(.easeOut(duration: 0.15), value: isKeyboardVisible)
        #endif
    }
}

/// Resigns whatever is first responder, without each call site having to own
/// a `@FocusState` binding.
@MainActor
public func dismissKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
    #endif
}
