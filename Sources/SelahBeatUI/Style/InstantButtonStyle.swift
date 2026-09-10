import SwiftUI

/// Fires on press-DOWN, not press-up.
///
/// SwiftUI's Button action runs on mouse-up / touch-up, which means the click
/// would sound when the finger leaves rather than when it lands — tens of
/// milliseconds of avoidable latency on the two controls where latency matters
/// most: Start/Stop and Tap Tempo.
public struct InstantButtonStyle: ButtonStyle {
    private let onPress: () -> Void
    private let scaleWhenPressed: CGFloat

    public init(scaleWhenPressed: CGFloat = 0.97, onPress: @escaping () -> Void) {
        self.onPress = onPress
        self.scaleWhenPressed = scaleWhenPressed
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleWhenPressed : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onPress() }
            }
    }
}

/// A button whose action runs the instant it is pressed.
public struct InstantButton<Label: View>: View {
    private let action: () -> Void
    private let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    public var body: some View {
        // The Button's own action stays empty; the style drives it on press.
        Button(action: {}) { label }
            .buttonStyle(InstantButtonStyle(onPress: action))
    }
}
