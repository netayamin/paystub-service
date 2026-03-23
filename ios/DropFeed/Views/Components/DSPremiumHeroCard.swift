import SwiftUI

// MARK: - Data → hero copy

enum PremiumHeroFormatting {
    /// 24h display with spaces, e.g. `19 : 45`.
    static func time24hSpaced(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else {
            return t.isEmpty ? "—" : String(t.prefix(5))
        }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        return String(format: "%02d : %02d", h, m)
    }

    /// Reference hero: `19:45` (no extra spaces).
    static func time24hCompact(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else {
            return t.isEmpty ? "—" : String(t.prefix(5))
        }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        return String(format: "%02d:%02d", h, m)
    }

    static func reservationSubtitle(for drop: Drop) -> String {
        let t = drop.slots.first?.time ?? ""
        let p = t.split(separator: ":")
        let h = p.first.flatMap { Int($0) }
        guard let hour = h else { return "DINNER RESERVATION" }
        switch hour {
        case 5 ..< 11: return "BREAKFAST RESERVATION"
        case 11 ..< 15: return "LUNCH RESERVATION"
        case 15 ..< 17: return "EARLY DINNER RESERVATION"
        default: return "DINNER RESERVATION"
        }
    }

    static func locationLine(for drop: Drop) -> String {
        if let loc = drop.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            return loc
        }
        let n = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !n.isEmpty {
            return "\(n), New York"
        }
        switch drop.market?.lowercased() {
        case "miami": return "Miami"
        case "la", "los_angeles": return "Los Angeles"
        default: return "New York"
        }
    }

    static func badgeText(for drop: Drop) -> String {
        if let c = drop.crownBadgeLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            return c.uppercased()
        }
        if drop.showExclusiveBadge == true || drop.feedsRareCarousel == true {
            return "PREMIUM DROP"
        }
        if drop.feedHot == true || (drop.snagScore ?? 0) >= 78 || (drop.trendPct ?? 0) > 12 {
            return "HIGH DEMAND"
        }
        return "LIVE DROP"
    }

    static func paxLabel(for drop: Drop) -> String {
        if let p = drop.partySizesAvailable.sorted().first {
            return "\(p) PAX"
        }
        return "2 PAX"
    }
}

// MARK: - View

/// Dark premium hero — TOP OPPORTUNITY + Hottest Drops carousel (reference layout).
///
/// **Layout:** Bounds come from `Color.clear.frame(height:)` + `overlay` so loaded `UIImage` sizes
/// cannot inflate past the card (same pattern as ``DSExploreInventoryCard``).
struct DSPremiumHeroCard: View {
    let drop: Drop
    /// Carousel / compact tiles pass height; main feed hero uses ``defaultHeroHeight``.
    var layoutHeight: CGFloat?
    /// When `true`, 1pt sharp rectangle stroke (main feed). Carousel sets `false` — chrome is outside.
    var useSharpRectangleBorder: Bool = true
    /// Optional inner clip to match carousel corner radius.
    var innerClipCornerRadius: CGFloat?
    var isWatched: Bool = false
    var onToggleWatch: ((String) -> Void)?

    static let defaultHeroHeight: CGFloat = 320

    private var effectiveHeight: CGFloat { layoutHeight ?? Self.defaultHeroHeight }
    private var isCompactTile: Bool { effectiveHeight < 270 }
    private var isVeryCompact: Bool { effectiveHeight < 248 }

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var timeRaw: String {
        (drop.slots.first?.time ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var timeDisplay: String {
        if isCarouselTile {
            let s = PremiumHeroFormatting.time24hSpaced(timeRaw)
            return (timeRaw.isEmpty || s == "—") ? "-- : --" : s
        }
        let s = PremiumHeroFormatting.time24hCompact(timeRaw)
        return (timeRaw.isEmpty || s == "—") ? "—" : s
    }

    private var titleSize: CGFloat {
        if isVeryCompact { return 20 }
        if isCompactTile { return 26 }
        if effectiveHeight < 340 { return 30 }
        return 34
    }

    private var timeSize: CGFloat {
        if isVeryCompact { return 22 }
        if isCompactTile { return 26 }
        if isCarouselTile { return 30 }
        return 36
    }

    private func openResy() {
        let urlStr = drop.effectiveResyBookingURL ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        APIService.shared.trackBehaviorEvents(events: [
            BehaviorTrackEvent(
                eventType: "resy_opened",
                venueId: drop.venueKey,
                venueName: drop.name,
                notificationId: nil,
                market: drop.market
            )
        ])
        UIApplication.shared.open(url)
    }

    /// Full-width TOP OPPORTUNITY hero only — carousel tiles omit this.
    private var isCarouselTile: Bool { layoutHeight != nil }

    var body: some View {
        let bounded = Color.clear
            .frame(maxWidth: .infinity, maxHeight: effectiveHeight)
            .overlay {
                heroLayers
                    .frame(maxWidth: .infinity, maxHeight: effectiveHeight, alignment: .bottom)
                    .clipped()
            }
            .clipped()

        Group {
            if let r = innerClipCornerRadius {
                bounded.clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            } else {
                bounded
            }
        }
        .compositingGroup()
        .overlay {
            if useSharpRectangleBorder {
                Rectangle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
        }
    }

    /// Image, gradient, labels — drawn inside a **fixed** overlay rect only.
    private var heroLayers: some View {
        ZStack(alignment: .bottom) {
            // Background image (cannot affect outer layout — overlay proposes fixed size)
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .heroMuted) {
                        gradientFallback
                    }
                } else {
                    gradientFallback
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.0),
                    .init(color: .black.opacity(0.2), location: 0.38),
                    .init(color: .black.opacity(0.88), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            if !isCarouselTile {
                Text("\(drop.name.uppercased()) · NYC")
                    .font(.system(size: isCompactTile ? 36 : 52, weight: .bold))
                    .foregroundColor(.white.opacity(0.05))
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: isCompactTile ? -8 : -18)
                    .allowsHitTesting(false)
                    .layoutPriority(-1)
            }

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: isCompactTile ? 6 : 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(PremiumHeroFormatting.badgeText(for: drop))
                            .font(.system(size: isCompactTile ? 8 : 9, weight: .bold))
                            .foregroundColor(.white)
                            .tracking(0.4)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, isCompactTile ? 8 : 10)
                            .padding(.vertical, isCompactTile ? 5 : 6)
                            .background(CreamEditorialTheme.streamRed)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)

                        Text(PremiumHeroFormatting.locationLine(for: drop))
                            .font(.system(size: isCompactTile ? 10 : 11, weight: .regular))
                            .italic()
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(drop.name)
                                .font(.system(size: titleSize, weight: .light, design: .serif))
                                .foregroundColor(.white)
                                .lineLimit(isVeryCompact ? 1 : 2)
                                .minimumScaleFactor(0.55)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(PremiumHeroFormatting.reservationSubtitle(for: drop))
                                .font(.system(size: isCompactTile ? 9 : 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                                .tracking(0.55)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 6) {
                            Text(timeDisplay)
                                .font(.system(size: timeSize, weight: .bold))
                                .foregroundColor(.white)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)

                            // Reference: light pill, burgundy/dark text, hairline border
                            Text(PremiumHeroFormatting.paxLabel(for: drop))
                                .font(.system(size: isCompactTile ? 9 : 10, weight: .bold))
                                .foregroundColor(.black)
                                .tracking(0.35)
                                .lineLimit(1)
                                .padding(.horizontal, isCompactTile ? 8 : 10)
                                .padding(.vertical, 5)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .layoutPriority(2)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    // Frosted glass bar (reference) — keeps CTAs inside card bounds
                    HStack(spacing: isCompactTile ? 8 : 10) {
                        let canBook = drop.effectiveResyBookingURL != nil
                        Button(action: openResy) {
                            Text("SECURE SEAT")
                                .font(.system(size: isCompactTile ? 11 : 13, weight: .bold))
                                .tracking(0.45)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: isCompactTile ? 44 : 50)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.black.opacity(canBook ? 0.08 : 0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(!canBook)
                        .opacity(canBook ? 1 : 0.55)

                        if let toggle = onToggleWatch {
                            Button {
                                toggle(drop.name)
                            } label: {
                                Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: isCompactTile ? 15 : 17, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: isCompactTile ? 44 : 52, height: isCompactTile ? 44 : 50)
                                    .background(Color.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, isCompactTile ? 4 : 8)
                    .padding(isCompactTile ? 10 : 12)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.32))
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                        .environment(\.colorScheme, .dark)
                    }
                }
                .padding(.horizontal, isCompactTile ? 12 : 16)
                .padding(.bottom, isCompactTile ? 12 : 16)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private var frostedCTAFill: some ShapeStyle {
        Color.white.opacity(0.18)
    }

    private var gradientFallback: some View {
        LinearGradient(
            colors: [Color(white: 0.22), Color(white: 0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview("Main hero") {
    ZStack {
        CreamEditorialTheme.canvas.ignoresSafeArea()
        DSPremiumHeroCard(
            drop: .previewRare,
            layoutHeight: nil,
            useSharpRectangleBorder: true,
            innerClipCornerRadius: nil,
            isWatched: false,
            onToggleWatch: { _ in }
        )
        .padding()
    }
}

#Preview("Carousel") {
    ZStack {
        CreamEditorialTheme.canvas.ignoresSafeArea()
        DSPremiumHeroCard(
            drop: .previewRare,
            layoutHeight: 240,
            useSharpRectangleBorder: false,
            innerClipCornerRadius: nil,
            isWatched: true,
            onToggleWatch: { _ in }
        )
        .frame(width: 280)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
