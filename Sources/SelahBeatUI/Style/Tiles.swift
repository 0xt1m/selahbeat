import SwiftUI

/// Shared tile chrome, so service tiles and song tiles read as one family.
public struct TileCard<Content: View>: View {
    private let isHighlighted: Bool
    private let content: Content

    public init(isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 108, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(isHighlighted ? Theme.accentDim.opacity(0.35) : Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(isHighlighted ? Theme.accent : Color.white.opacity(0.06), lineWidth: isHighlighted ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}

/// The trailing "add" tile. Dashed so it reads as an empty slot rather than an
/// item that already exists.
public struct AddTile: View {
    private let title: String
    private let action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 108)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surfaceRaised.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(
                        Theme.accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A small pill used for key / meter / tempo on a tile.
public struct TileChip: View {
    private let text: String
    private let tint: Color

    public init(_ text: String, tint: Color = Theme.secondaryText) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.07), in: Capsule())
    }
}

public enum TileGrid {
    /// Adaptive so the same grid works on an iPhone (2 columns) and a wide
    /// Mac window (as many as fit) without a size-class branch.
    public static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 14)]
    }
    public static let spacing: CGFloat = 14
}
