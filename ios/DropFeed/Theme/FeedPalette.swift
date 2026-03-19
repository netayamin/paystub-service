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

    /// Near-black palette for premium dark sections (Top Drops).
    static let liveFeedDark: FeedPalette = FeedPalette(
        pageBackground:  Color(red: 0.07, green: 0.07, blue: 0.08),
        surface:         Color(red: 0.12, green: 0.11, blue: 0.13),
        surfaceElevated: Color(red: 0.17, green: 0.16, blue: 0.18),
        textPrimary:     Color.white,
        textSecondary:   Color(white: 0.62),
        textTertiary:    Color(white: 0.40),
        border:          Color.white.opacity(0.08),
        accent:          AppTheme.accentRed,
        accentRed:       AppTheme.accentRed,
        pillUnselected:  Color.white.opacity(0.10),
        pillSelected:    AppTheme.accentRed
    )

    /// Light palette — warm white cards on a soft gray background,
    /// coral accent — matches the DropTable reference design.
    static let liveFeedLight: FeedPalette = FeedPalette(
        pageBackground:  Color(red: 0.96, green: 0.95, blue: 0.95),   // warm off-white
        surface:         Color.white,
        surfaceElevated: Color.white,
        textPrimary:     Color(red: 0.11, green: 0.11, blue: 0.13),   // near-black
        textSecondary:   Color(red: 0.38, green: 0.38, blue: 0.42),
        textTertiary:    Color(red: 0.58, green: 0.58, blue: 0.62),
        border:          Color.black.opacity(0.07),
        accent:          AppTheme.accentRed,
        accentRed:       AppTheme.accentRed,
        pillUnselected:  Color.black.opacity(0.05),
        pillSelected:    AppTheme.accentRed
    )
}

