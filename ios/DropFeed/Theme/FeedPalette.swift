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

    /// Light palette — white / #F5F5F5 surfaces, primary red accent (#DC2626).
    static let liveFeedLight: FeedPalette = FeedPalette(
        pageBackground:  SnagDesignSystem.pageWhite,
        surface:         SnagDesignSystem.pageWhite,
        surfaceElevated: SnagDesignSystem.cardGray,
        textPrimary:     SnagDesignSystem.textDark,
        textSecondary:   SnagDesignSystem.textMuted,
        textTertiary:    SnagDesignSystem.textSection,
        border:          Color.black.opacity(0.06),
        accent:          SnagDesignSystem.coral,
        accentRed:       SnagDesignSystem.coral,
        pillUnselected:  SnagDesignSystem.cardGray,
        pillSelected:    SnagDesignSystem.coral
    )
}

