import SwiftUI

/// Dark, premium palette inspired by modern apps (e.g. character.ai).
enum AppTheme {
    // MARK: - Backgrounds
    static let background = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let surface = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.18)

    // MARK: - Text
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.50)

    // MARK: - Core Accents
    static let accent = Color(red: 0.23, green: 0.51, blue: 0.96)        // Blue — pills, links
    static let accentRed = Color(red: 0.95, green: 0.35, blue: 0.25)     // Live / alert
    static let accentOrange = Color(red: 1.0, green: 0.55, blue: 0.15)   // Primary CTAs, market
    static let liveDot = Color(red: 0.40, green: 0.90, blue: 0.50)       // Animated live dot

    // MARK: - Trend indicators
    /// Trending up — green freshness, positive trend badge
    static let trendUp = Color(red: 0.20, green: 0.78, blue: 0.45)
    /// Trending down / cooling — same as accentRed, aliased for semantics
    static let trendDown = Color(red: 0.95, green: 0.35, blue: 0.25)
    /// Neutral / stable
    static let trendNeutral = Color(white: 0.50)

    // MARK: - Pills / chips
    static let pillUnselected = Color(red: 0.18, green: 0.18, blue: 0.22)
    static let pillSelected = accent

    // MARK: - Borders / dividers
    static let border = Color(white: 0.20).opacity(0.5)

    // MARK: - Scarcity tier colors
    static let scarcityRare = Color(red: 0.90, green: 0.30, blue: 0.30)
    static let scarcityRareBg = Color(red: 0.35, green: 0.15, blue: 0.15)
    static let scarcityUncommon = Color(red: 0.95, green: 0.70, blue: 0.25)
    static let scarcityUncommonBg = Color(red: 0.35, green: 0.28, blue: 0.12)
    static let scarcityAvailable = Color(red: 0.30, green: 0.85, blue: 0.50)
    static let scarcityAvailableBg = Color(red: 0.12, green: 0.28, blue: 0.18)

    // MARK: - Premium
    static let premiumGold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let premiumGoldBg = Color(red: 0.25, green: 0.22, blue: 0.08)

    // MARK: - Tab bar (frosted glass, pill for selected)
    static let tabBarPillSelected = Color.white.opacity(0.28)
    static let tabBarSelected = Color.white
    static let tabBarUnselected = Color.white.opacity(0.70)

    // MARK: - Spacing system (16-pt grid)
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24

    // MARK: - Scarcity helpers

    static func scarcityColor(for tier: Drop.ScarcityTier) -> Color {
        switch tier {
        case .rare:      return scarcityRare
        case .uncommon:  return scarcityUncommon
        case .available: return scarcityAvailable
        case .unknown:   return textTertiary
        }
    }

    static func scarcityBackground(for tier: Drop.ScarcityTier) -> Color {
        switch tier {
        case .rare:      return scarcityRareBg
        case .uncommon:  return scarcityUncommonBg
        case .available: return scarcityAvailableBg
        case .unknown:   return surfaceElevated
        }
    }

    // MARK: - Trend helpers

    static func trendColor(for trendPct: Double?) -> Color {
        guard let pct = trendPct else { return trendNeutral }
        if pct > 5  { return trendUp }
        if pct < -5 { return trendDown }
        return trendNeutral
    }
}
