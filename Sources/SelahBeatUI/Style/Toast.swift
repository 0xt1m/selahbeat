import SwiftUI

/// Brief confirmation for actions whose result happens off-screen — adding a
/// song to a service you aren't currently looking at, for instance.
struct ToastOverlay: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.running.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            .padding(.bottom, 20)
    }
}

public extension View {
    /// Shows `message` briefly, then clears it.
    func toast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                ToastOverlay(text: text)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: text) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(.easeOut(duration: 0.2)) {
                            message.wrappedValue = nil
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.28), value: message.wrappedValue)
    }
}
