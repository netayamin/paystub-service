import SwiftUI

/// App palette — primary red on clean white/light-gray surfaces.
enum AppTheme {
    // Backgrounds
    static let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.12, green: 0.11, blue: 0.13)
    static let surfaceElevated = Color(red: 0.16, green: 0.15, blue: 0.18)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.50)

    // ── Primary accent: true red (#DC2626) — buttons, badges, links ──
    static let accentRed    = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
    static let accent       = accentRed   // alias so existing code keeps working
    /// Slightly deeper red for pressed / emphasis
    static let accentOrange = Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255)
    static let liveDot      = Color(red: 0.25, green: 0.85, blue: 0.48)
    
    // Pills / chips
    static let pillUnselected = Color(red: 0.17, green: 0.17, blue: 0.20)
    static let pillSelected   = accentRed

    // Borders / dividers
    static let border = Color(white: 0.22).opacity(0.45)

    // Badges
    static let badgeNew       = accentRed.opacity(0.75)
    static let badgeHot       = accentRed.opacity(0.65)
    static let badgeTrending  = Color(red: 0.22, green: 0.22, blue: 0.26)
    static let badgeFreshness = Color.white.opacity(0.20)

    // Scarcity tier colors
    static let scarcityRare          = accentRed
    static let scarcityRareBg        = accentRed.opacity(0.20)
    static let scarcityUncommon      = Color(red: 0.95, green: 0.70, blue: 0.25)
    static let scarcityUncommonBg    = Color(red: 0.35, green: 0.28, blue: 0.12)
    static let scarcityAvailable     = Color(red: 0.30, green: 0.85, blue: 0.50)
    static let scarcityAvailableBg   = Color(red: 0.12, green: 0.28, blue: 0.18)

    // Premium
    static let premiumGold   = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let premiumGoldBg = Color(red: 0.25, green: 0.22, blue: 0.08)

    // Tab bar
    static let tabBarPillSelected = Color.white.opacity(0.26)
    static let tabBarSelected     = Color.white
    static let tabBarUnselected   = Color.white.opacity(0.65)
    
    // MARK: - Scarcity helpers
    
    static func scarcityColor(for tier: Drop.ScarcityTier) -> Color {
        switch tier {
        case .rare: return scarcityRare
        case .uncommon: return scarcityUncommon
        case .available: return scarcityAvailable
        case .unknown: return textTertiary
        }
    }
    
    static func scarcityBackground(for tier: Drop.ScarcityTier) -> Color {
        switch tier {
        case .rare: return scarcityRareBg
        case .uncommon: return scarcityUncommonBg
        case .available: return scarcityAvailableBg
        case .unknown: return surfaceElevated
        }
    }
}
