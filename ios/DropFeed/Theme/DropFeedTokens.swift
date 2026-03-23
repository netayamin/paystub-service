import SwiftUI

// MARK: - Design system overview
//
// **Drop Feed** app chrome is **light / editorial** (Quiet Curator). Use:
// - ``DropFeedTokens`` — spacing, radii, semantic one-offs (avoid magic numbers in views).
// - ``CreamEditorialTheme`` — primary colors, hairlines, burgundy accent, cards.
// - ``SnagDesignSystem`` — legacy / shared accents (e.g. tab badge red); prefer Cream for new UI.
//
// Reusable building blocks live under `Views/Components/` (`DS*` + ``AppTabBar``).

/// Layout and semantic values shared across screens.
enum DropFeedTokens {

    enum Layout {
        /// Standard horizontal inset for screen edges (headers, scroll content).
        static let screenPadding: CGFloat = 16
        static let gridColumnSpacing: CGFloat = 14
        static let gridRowSpacing: CGFloat = 20
        static let exploreCardImageHeight: CGFloat = 178
        static let exploreCardCornerRadius: CGFloat = 8
    }

    /// Named fills that are not yet on ``CreamEditorialTheme``.
    enum Semantic {
        static let exploreInventoryPillFill = Color(red: 0.97, green: 0.96, blue: 0.94)
        /// Dark red hero badge (premium drop) — aligns with reference hero cards.
        static let premiumHeroBadgeFill = Color(red: 74 / 255, green: 14 / 255, blue: 14 / 255)
        /// Pax chip on dark hero — warm grey fill.
        static let premiumHeroPaxFill = Color(red: 0.90, green: 0.88, blue: 0.84)
    }
}
