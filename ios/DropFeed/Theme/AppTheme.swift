import SwiftUI

/// Dark, premium palette inspired by modern apps (e.g. character.ai).
enum AppTheme {
    // Backgrounds
    static let background = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.18)
    
    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.5)
    
    // Accents
    static let accent = Color(red: 0.23, green: 0.51, blue: 0.96)   // Blue
    static let accentRed = Color(red: 0.95, green: 0.35, blue: 0.25)
    /// Orange for primary CTAs (Reserve, SET ALERT, EXCLUSIVE badge) — matches screenshot
    static let accentOrange = Color(red: 1.0, green: 0.55, blue: 0.15)
    static let liveDot = Color(red: 0.4, green: 0.9, blue: 0.5)
    
    // Pills / chips
    static let pillUnselected = Color(red: 0.18, green: 0.18, blue: 0.22)
    static let pillSelected = accent
    
    // Borders / dividers
    static let border = Color(white: 0.2).opacity(0.5)
    
    // Badges (web-aligned: muted, not bright)
    static let badgeNew = Color(red: 0.48, green: 0.28, blue: 0.24)
    static let badgeHot = Color(red: 0.42, green: 0.24, blue: 0.20)
    static let badgeTrending = Color(red: 0.22, green: 0.22, blue: 0.26)
    static let badgeFreshness = Color.white.opacity(0.22)
    
    // Scarcity tier colors
    static let scarcityRare = Color(red: 0.90, green: 0.30, blue: 0.30)
    static let scarcityRareBg = Color(red: 0.35, green: 0.15, blue: 0.15)
    static let scarcityUncommon = Color(red: 0.95, green: 0.70, blue: 0.25)
    static let scarcityUncommonBg = Color(red: 0.35, green: 0.28, blue: 0.12)
    static let scarcityAvailable = Color(red: 0.30, green: 0.85, blue: 0.50)
    static let scarcityAvailableBg = Color(red: 0.12, green: 0.28, blue: 0.18)
    
    // Premium
    static let premiumGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let premiumGoldBg = Color(red: 0.25, green: 0.22, blue: 0.08)
    
    // Tab bar (frosted glass: blur + dark tint, pill for selected)
    static let tabBarPillSelected = Color.white.opacity(0.28)
    static let tabBarSelected = Color.white
    static let tabBarUnselected = Color.white.opacity(0.7)
    
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
