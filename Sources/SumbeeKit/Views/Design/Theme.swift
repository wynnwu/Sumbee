import SwiftUI

/// Visual language: orange accent, glass materials, restrained-futuristic spacing & motion.
/// Colors are defined to read well in both light and dark appearance.
public enum Theme {
    // MARK: Accent (orange)
    /// Primary brand orange (#FF7A1A).
    public static let accent = Color(red: 1.0, green: 0.478, blue: 0.102)
    /// Warmer amber used as the second gradient stop.
    public static let accentWarm = Color(red: 1.0, green: 0.62, blue: 0.20)
    /// Deeper ember used for pressed/active states.
    public static let accentDeep = Color(red: 0.92, green: 0.36, blue: 0.04)

    public static let accentGradient = LinearGradient(
        colors: [accentWarm, accent, accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A soft glow color for active drop zones / focused elements.
    public static func accentGlow(_ opacity: Double = 0.45) -> Color {
        accent.opacity(opacity)
    }

    // MARK: Geometry - square edges for a futuristic, minimal look (FR-027)
    public static let cornerRadius: CGFloat = 0
    public static let smallCorner: CGFloat = 0
    public static let cardPadding: CGFloat = 18
    public static let sectionSpacing: CGFloat = 22

    // MARK: Motion
    public static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    public static let quick = Animation.easeOut(duration: 0.18)

    // MARK: Typography (larger base sizes - FR-027)
    public static func title(_ text: String) -> Text {
        Text(text).font(.uiTitle)
    }

    public static func sectionLabel(_ text: String) -> Text {
        Text(text.uppercased())
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .kerning(1.6)
    }

    // MARK: Hairline / panel border
    public static var hairline: Color { Color.primary.opacity(0.10) }
    public static var panelStroke: Color { Color.white.opacity(0.10) }
}

/// Shared, deliberately-larger font tokens (macOS default text styles run small; FR-027).
public extension Font {
    static let uiTitle    = Font.system(size: 32, weight: .bold, design: .rounded)
    static let uiHeadline = Font.system(size: 19, weight: .semibold, design: .rounded)
    static let uiBody     = Font.system(size: 16, design: .rounded)
    static let uiCallout  = Font.system(size: 15, design: .rounded)
    static let uiCaption  = Font.system(size: 13, design: .rounded)
}

public extension View {
    /// Standard glass card surface used across panels.
    func glassCard(cornerRadius: CGFloat = Theme.cornerRadius,
                   strokeOpacity: Double = 0.10) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}
