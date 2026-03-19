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

