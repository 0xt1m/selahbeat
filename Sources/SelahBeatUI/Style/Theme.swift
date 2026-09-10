import SwiftUI

extension Color {
    /// 0xRRGGBB, so palette values stay readable against the design spec.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

/// Stage-first visual language: dark by default, high contrast, no pure white
/// surfaces (blinding in a dark auditorium), and generous hit targets.
///
/// Palette is "Midnight Blue + Sky". Greys are blue-tinted rather than neutral
/// so the accent doesn't look pasted onto a flat background. Colour is
/// reserved for meaning: sky for interactive accents, green only for the
/// running transport, amber only for the latency warning.
public enum Theme {
    public static let accent = Color(hex: 0x38BDF8)
    public static let accentDim = Color(hex: 0x1E5F82)
    public static let running = Color(hex: 0x34D399)
    public static let danger = Color(hex: 0xF87171)
    public static let warning = Color(hex: 0xFBBF24)

    public static let surface = Color(hex: 0x0F141A)
    public static let surfaceRaised = Color(hex: 0x1A222C)
    public static let stageBackground = Color(hex: 0x06090D)

    public static let primaryText = Color(hex: 0xEAF0F6)
    public static let secondaryText = Color(hex: 0x93A2B4)

    #if os(macOS)
    public static let primaryButtonHeight: CGFloat = 64
    public static let minHitTarget: CGFloat = 44
    public static let transportHeight: CGFloat = 104
    #else
    public static let primaryButtonHeight: CGFloat = 76
    public static let minHitTarget: CGFloat = 60
    public static let transportHeight: CGFloat = 128
    #endif

    public static let corner: CGFloat = 14

    /// Tempo readouts must not reflow as digits change.
    public static func tempoFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// Sheets need an explicit size on macOS, where a window has no intrinsic
    /// one. On iOS the sheet already fills the screen, and forcing a macOS
    /// width there pushes content wider than the display and clips it at both
    /// edges.
    @ViewBuilder
    func sheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, minHeight: height)
        #else
        self
        #endif
    }

    func cardBackground() -> some View {
        background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}
