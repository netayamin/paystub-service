import SwiftUI

/// Snag reference UI — primary red accent, white canvas, mint success, soft gray cards.
enum SnagDesignSystem {

    // MARK: - Colors (mockup)

    /// Primary red — buttons, badges, links (not orange/coral)
    static let coral = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255) // #DC2626

    /// Deeper editorial red (reference UI / hero CTAs)
    static let epicureanRed = Color(red: 178 / 255, green: 34 / 255, blue: 34 / 255) // #B22222

    /// Velocity “pending” / warm accent
    static let velocityAmber = Color(red: 230 / 255, green: 126 / 255, blue: 34 / 255)

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

    /// Large display titles (hero + section headers) — New York / serif feel on iOS.
    static var displaySerif: Font {
        .system(size: 28, weight: .bold, design: .serif)
    }

    static var sectionSerif: Font {
        .system(size: 22, weight: .bold, design: .serif)
    }

    // MARK: - Dark feed (reference mockup)

    /// Near-black canvas (#121212).
    static let darkCanvas = Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255)
    static let darkElevated = Color(red: 30 / 255, green: 30 / 255, blue: 32 / 255)
    static let darkTextPrimary = Color.white
    static let darkTextSecondary = Color(red: 180 / 255, green: 180 / 255, blue: 186 / 255)
    static let darkTextMuted = Color(red: 120 / 255, green: 120 / 255, blue: 128 / 255)
    /// Salmon / coral accent from mock (~#C23B34).
    static let salmonAccent = Color(red: 194 / 255, green: 59 / 255, blue: 52 / 255)
    static let livePillBackground = Color(red: 48 / 255, green: 22 / 255, blue: 24 / 255)
    static let activePillBackground = Color(red: 72 / 255, green: 26 / 255, blue: 30 / 255)
    static let tabBarDarkSurface = Color(red: 22 / 255, green: 22 / 255, blue: 24 / 255)
    static let tabBarDarkSelectedWell = Color(red: 40 / 255, green: 18 / 255, blue: 20 / 255)

    /// Explore mock — salmon CTA / accents (~#FFA08C).
    static let exploreCoral = Color(red: 255 / 255, green: 160 / 255, blue: 140 / 255)
    /// Explore mock — brand red / active tab (~#FF4B3A).
    static let exploreRed = Color(red: 255 / 255, green: 75 / 255, blue: 58 / 255)
    /// Explore discovery canvas (~#0A0A0A).
    static let exploreCanvas = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    /// Solid coral for filled pills / underlines (~#D1453B).
    static let exploreCoralSolid = Color(red: 209 / 255, green: 69 / 255, blue: 59 / 255)
    /// Secondary labels (~#8E8E93).
    static let exploreSecondaryLabel = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
}

// MARK: - Cream editorial home (light mockup: warm canvas + serif + soft cards)

enum CreamEditorialTheme {
    /// Quiet Curator–style canvas (~#F7F7F7).
    static let canvas = Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
    static let cardWhite = Color.white
    static let textPrimary = Color.black
    static let textSecondary = Color(red: 100 / 255, green: 100 / 255, blue: 108 / 255)
    static let textTertiary = Color(red: 140 / 255, green: 140 / 255, blue: 148 / 255)
    static let hairline = Color.black.opacity(0.09)
    static let peachBadgeFill = Color(red: 255 / 255, green: 236 / 255, blue: 228 / 255)
    static let peachBadgeText = Color(red: 180 / 255, green: 72 / 255, blue: 48 / 255)
    static let streamRed = Color(red: 178 / 255, green: 28 / 255, blue: 42 / 255)
    static let liveDot = Color(red: 200 / 255, green: 32 / 255, blue: 48 / 255)
    /// Live stream divider header — pulse dot + “JUST OPENED” (reference UI).
    static let liveStreamPulseGreen = Color(red: 31 / 255, green: 138 / 255, blue: 88 / 255)
    static let cardShadow = Color.black.opacity(0.06)
    /// Deep burgundy — HIGH DEMAND, live labels, forecast bars.
    static let burgundy = Color(red: 118 / 255, green: 26 / 255, blue: 34 / 255)
    static let burgundyMuted = Color(red: 92 / 255, green: 22 / 255, blue: 30 / 255)
    /// Tactical forecast panel fill.
    static let tacticalPanelFill = Color(red: 238 / 255, green: 238 / 255, blue: 240 / 255)
    static let heroNeighborhoodRed = Color(red: 200 / 255, green: 40 / 255, blue: 52 / 255)

    /// Brutalist QC — no rounded corners on feed chrome.
    static let qcCornerRadius: CGFloat = 0
    /// Dark tactical forecast card (reference UI).
    static let tacticalDarkSurface = Color(red: 22 / 255, green: 22 / 255, blue: 24 / 255)
    static let tacticalDarkDivider = Color.white.opacity(0.07)
    static let tacticalDarkMeta = Color(red: 150 / 255, green: 150 / 255, blue: 158 / 255)
    /// TAKEN / secondary chips.
    static let takenFill = Color(red: 237 / 255, green: 237 / 255, blue: 240 / 255)
    static let takenText = Color(red: 88 / 255, green: 88 / 255, blue: 94 / 255)
    /// Ghost CTA on cream.
    static let exploreMutedLabel = Color(red: 58 / 255, green: 58 / 255, blue: 62 / 255)
    static let exploreHairline = Color(red: 200 / 255, green: 200 / 255, blue: 204 / 255)

    static var sectionSans: Font { .system(size: 11, weight: .bold) }
    static var titleSerif: Font { .system(size: 22, weight: .bold, design: .serif) }
    static var heroSerif: Font { .system(size: 26, weight: .bold, design: .serif) }
    static var bodySans: Font { .system(size: 14, weight: .semibold) }
    static var metaSans: Font { .system(size: 12, weight: .medium) }
    /// All-caps display (mock: no serif on hero title).
    static var heroDisplayCaps: Font { .system(size: 28, weight: .heavy) }

    static let cardRadius: CGFloat = 22
    static let cardRadiusSm: CGFloat = 18
}
