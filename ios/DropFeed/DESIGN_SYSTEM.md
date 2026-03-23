# Drop Feed — Design system

## Tokens

- **`DropFeedTokens`** (`Theme/DropFeedTokens.swift`) — screen padding, grid spacing, Explore card metrics, semantic fills. Use this instead of hard-coded `CGFloat`s in new UI.

## Colors

- **`CreamEditorialTheme`** — primary app palette (canvas, text, burgundy, hairlines, cards).
- **`SnagDesignSystem`** — legacy / accents (e.g. Explore tab badge red). Prefer Cream for surfaces and typography.

## Reusable components (`Views/Components/`)

| View | Use for |
|------|---------|
| **`AppTabBar`** | Sole bottom tab bar (light canvas, three SF Symbol tabs). |
| **`DSHairline`** | 1pt horizontal rules with optional horizontal inset. |
| **`DSSectionTitleRow`** | Bold left title + grey uppercase trailing (e.g. Availability + month). |
| **`DSLabeledRuleRow`** | Grey label + flex hairline + burgundy trailing (e.g. LIVE INVENTORY + city). |
| **`DSExploreDateChip`** | Calendar strip: weekday over date, maroon when selected. |

Prefix new shared primitives with **`DS`** and keep them **stateless** where possible (pass data + closures in).

## Tab bar

There is **one** tab bar implementation: **`AppTabBar`**. The previous dark dock variant was removed.
