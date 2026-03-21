import SwiftUI

/// Snag reference UI — primary red accent, white canvas, mint success, soft gray cards.
enum SnagDesignSystem {

    // MARK: - Colors (mockup)

    /// Primary red — buttons, badges, links (not orange/coral)
    static let coral = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255) // #DC2626

    /// Light tint for pill backgrounds
    static let coralSoft = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255).opacity(0.12)

    /// Main screens behind content (off-white canvas).
    static let pageCanvas = Color(red: 247 / 255, green: 247 / 255, blue: 246 / 255) // ~#F7F7F6
    /// Pure white — tab bar dock, list stripes, cards that sit on `pageCanvas`.
    static let pageWhite = Color.white
    static let cardGray = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255) // #F5F5F5

    static let textDark = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let textMuted = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255)
    static let textSection = Color(red: 100 / 255, green: 100 / 255, blue: 108 / 255)

    /// Probability / FAST — mint green
    static let mint = Color(red: 52 / 255, green: 199 / 255, blue: 147 / 255)

    /// SORT BY SCORE link
    static let linkBlue = Color(red: 64 / 255, green: 156 / 255, blue: 255 / 255)

    static let bannerPeach = Color(red: 255 / 255, green: 236 / 255, blue: 230 / 255)
    static let blackCTA = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)

    static let tabInactive = Color(red: 140 / 255, green: 140 / 255, blue: 145 / 255)
    static let tabPillFill = coral.opacity(0.14)

    /// Floating tab bar: light gray shell, charcoal labels, featured red FAB
    static let tabBarSurface = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let tabBarCharcoal = Color(red: 74 / 255, green: 74 / 255, blue: 74 / 255)
    static let tabBarFeaturedCoral = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)

    // MARK: - Typography

    static func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(textSection)
            .tracking(1.0)
    }

    static var venueSerifTitle: Font {
        .system(size: 26, weight: .bold, design: .serif)
    }
}
