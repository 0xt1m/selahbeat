import SwiftUI
import SelahBeatCore

/// A tempo entry field that lets you finish typing before it judges you.
///
/// A `TextField(value:format:)` bound straight to the tempo re-parses and
/// clamps on every keystroke: typing "156" goes 1 -> clamped to 20 -> "205".
/// It also refuses to be emptied, because the bound number always has a value.
///
/// This keeps the text as text while editing and only commits - parse, clamp,
/// write back - when you submit or move away.
public struct BPMField: View {
    @Binding private var bpm: Double
    private let width: CGFloat

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    public init(bpm: Binding<Double>, width: CGFloat = 92) {
        self._bpm = bpm
        self.width = width
    }

    public var body: some View {
        TextField("BPM", text: $text)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .focused($isFocused)
            .onSubmit(commit)
            .onAppear { text = Self.display(bpm) }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    // Select-all behaviour in spirit: start from the current
                    // value, but let it be cleared entirely.
                    text = Self.display(bpm)
                } else {
                    commit()
                }
            }
            .onChange(of: bpm) { _, newValue in
                // Keep in step when something else changes the tempo (the
                // stepper, tap tempo), but never while the user is mid-edit.
                if !isFocused { text = Self.display(newValue) }
            }
    }

    private func commit() {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)

        guard let parsed = Double(cleaned) else {
            text = Self.display(bpm)      // unparseable: put back what was there
            return
        }
        let clamped = Song.clampBPM(parsed)
        bpm = clamped
        text = Self.display(clamped)
    }

    private static func display(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
