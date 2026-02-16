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
    static let liveDot = Color(red: 0.4, green: 0.9, blue: 0.5)
    
    // Pills / chips
    static let pillUnselected = Color(red: 0.18, green: 0.18, blue: 0.22)
    static let pillSelected = accent
    
    // Borders / dividers
    static let border = Color(white: 0.2).opacity(0.5)
    
    // Badges (web-aligned: muted, not bright)
    /// "New" and hot demand — dark red-brown, not bright red
    static let badgeNew = Color(red: 0.48, green: 0.28, blue: 0.24)
    static let badgeHot = Color(red: 0.42, green: 0.24, blue: 0.20)
    /// Trending / neutral
    static let badgeTrending = Color(red: 0.22, green: 0.22, blue: 0.26)
    /// Freshness: "Just now", "Last 30 mins", "Last hour" — subtle overlay like web bg-white/20
    static let badgeFreshness = Color.white.opacity(0.22)
    
    // Tab bar (frosted glass: blur + dark tint, pill for selected)
    static let tabBarPillSelected = Color.white.opacity(0.28)
    static let tabBarSelected = Color.white
    static let tabBarUnselected = Color.white.opacity(0.7)
}
