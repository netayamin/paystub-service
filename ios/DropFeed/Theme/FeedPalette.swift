import SwiftUI

/// Color palette used for the main feed screen so we can match light-mode design
/// without changing the rest of the app's `AppTheme` (Search/Alerts/Profile).
struct FeedPalette {
    let pageBackground: Color
    let surface: Color
    let surfaceElevated: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let border: Color

    let accent: Color
    let accentRed: Color

    let pillUnselected: Color
    let pillSelected: Color

    static let dark: FeedPalette = FeedPalette(
        pageBackground: AppTheme.background,
        surface: AppTheme.surface,
        surfaceElevated: AppTheme.surfaceElevated,
        textPrimary: AppTheme.textPrimary,
        textSecondary: AppTheme.textSecondary,
        textTertiary: AppTheme.textTertiary,
        border: AppTheme.border,
        accent: AppTheme.accent,
        accentRed: AppTheme.accentRed,
        pillUnselected: AppTheme.pillUnselected,
        pillSelected: AppTheme.pillSelected
    )

    /// Deep-black palette for the Real-Time Ticker section.
    static let liveFeedDark: FeedPalette = FeedPalette(
        pageBackground: Color(red: 0.07, green: 0.07, blue: 0.09),
        surface:        Color(red: 0.13, green: 0.12, blue: 0.16),
        surfaceElevated: Color(red: 0.18, green: 0.17, blue: 0.21),
        textPrimary:    Color.white,
        textSecondary:  Color(white: 0.65),
        textTertiary:   Color(white: 0.42),
        border:         Color.white.opacity(0.09),
        accent:         AppTheme.accentRed,
        accentRed:      AppTheme.accentRed,
        pillUnselected: Color.white.opacity(0.09),
        pillSelected:   AppTheme.accentRed
    )

    static let liveFeedLight: FeedPalette = FeedPalette(
        pageBackground: Color(red: 0.97, green: 0.97, blue: 0.98),
        surface: Color.white,
        surfaceElevated: Color.white,
        textPrimary: Color(red: 0.12, green: 0.13, blue: 0.17),
        textSecondary: Color(red: 0.35, green: 0.37, blue: 0.43),
        textTertiary: Color(red: 0.56, green: 0.58, blue: 0.63),
        border: Color.black.opacity(0.08),
        accent: AppTheme.accentRed,
        accentRed: AppTheme.accentRed,
        pillUnselected: Color.black.opacity(0.05),
        pillSelected: AppTheme.accentRed
    )
}

