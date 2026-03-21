import SwiftUI

/// Forecast cards: uses backend `probability`, `reason`, `predicted_drop_time`, `confidence`, and scan metrics.
struct LikelyToOpenSection: View {
    let venues: [LikelyToOpenVenue]
    @ObservedObject var premium: PremiumManager
    var onNotifyMe: ((String) -> Void)? = nil
    var isWatched: ((String) -> Bool)? = nil

    @State private var showPaywall = false

    private var freeLimit: Int { PremiumManager.freeLikelyToOpenLimit }
    private var freeVenues: [LikelyToOpenVenue] { Array(venues.prefix(freeLimit)) }
    private var lockedVenues: [LikelyToOpenVenue] { premium.isPremium ? [] : Array(venues.dropFirst(freeLimit)) }
    private var allVisible: [LikelyToOpenVenue] { premium.isPremium ? venues : freeVenues }

    var body: some View {
        if venues.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIKELY TO OPEN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SnagDesignSystem.textSection)
                        .tracking(1.0)
                    Text("From your live Resy scans: how often tables appear, typical timing, and this week’s pace.")
                        .font(.system(size: 12))
                        .foregroundColor(SnagDesignSystem.textMuted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(allVisible) { venue in
                            likelyToOpenSnagCard(venue)
                        }
                        if !lockedVenues.isEmpty {
                            Button {
                                showPaywall = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 20))
                                    Text("\(lockedVenues.count) more")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(SnagDesignSystem.coral)
                                .frame(width: 172, height: 188)
                                .background(SnagDesignSystem.cardGray)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView(premium: premium)
            }
        }
    }

    private func likelyToOpenSnagCard(_ venue: LikelyToOpenVenue) -> some View {
        let forecastScore = venue.probability ?? forecastFallbackScore(venue)
        let conf = (venue.confidence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let confColor: Color = {
            switch conf.lowercased() {
            case "high": return SnagDesignSystem.mint
            case "low": return SnagDesignSystem.textMuted
            default: return SnagDesignSystem.textSection
            }
        }()

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(SnagDesignSystem.cardGray)

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(Color.black.opacity(0.06))
                .padding(12)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(SnagDesignSystem.mint.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(SnagDesignSystem.mint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("FORECAST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(SnagDesignSystem.textMuted)
                            .tracking(0.6)
                        Text("\(min(99, max(1, forecastScore)))")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(SnagDesignSystem.mint)
                    }
                }
                .padding(.bottom, 8)

                if !conf.isEmpty {
                    Text(conf.uppercased() + " CONFIDENCE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(confColor)
                        .padding(.bottom, 6)
                }

                Spacer(minLength: 0)

                Text(venue.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textDark)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(likelyTimeLine(venue))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.textMuted)
                    .padding(.top, 4)

                if let ml = metricsLineString(venue) {
                    Text(ml)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SnagDesignSystem.textMuted)
                        .padding(.top, 3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if let reason = venue.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(SnagDesignSystem.textSection)
                        .lineLimit(2)
                        .padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(width: 172, height: 188, alignment: .topLeading)
        }
        .frame(width: 172, height: 188)
    }

    /// When API omits `probability`, derive a rough display score from availability + trend (not a real probability).
    private func forecastFallbackScore(_ venue: LikelyToOpenVenue) -> Int {
        let base = Int(round((venue.availabilityRate14d ?? 0) * 55))
        let trendBoost: Int = {
            guard let t = venue.trendPct else { return 0 }
            let pts = abs(t) <= 1 ? t * 100 : t
            return pts > 5 ? min(25, Int(pts / 4)) : 0
        }()
        return min(99, max(12, base + trendBoost))
    }

    private func metricsLineString(_ venue: LikelyToOpenVenue) -> String? {
        var parts: [String] = []
        if let d = venue.daysWithDrops, d > 0 {
            parts.append("\(d)/14d active")
        }
        if let r = FeedMetricLabels.rarityPoints(score: venue.rarityScore) {
            parts.append("rarity \(r)")
        }
        if let t = FeedMetricLabels.trendShortLabel(trendPct: venue.trendPct) {
            parts.append(t)
        }
        let s = parts.joined(separator: " · ")
        return s.isEmpty ? nil : s
    }

    private func likelyTimeLine(_ venue: LikelyToOpenVenue) -> String {
        if let t = venue.predictedDropTime, !t.isEmpty {
            return "Often drops: \(t)"
        }
        if let d = venue.daysWithDrops {
            return "Tables appeared \(d)× in last 14 days"
        }
        return "Watch for next release"
    }
}

#Preview {
    ZStack {
        SnagDesignSystem.pageCanvas.ignoresSafeArea()
        LikelyToOpenSection(
            venues: [
                LikelyToOpenVenue(
                    name: "Minetta Tavern",
                    imageUrl: nil,
                    availabilityRate14d: 0.2,
                    daysWithDrops: 4,
                    rarityScore: 78,
                    lastSeenDescription: nil,
                    neighborhood: "Village",
                    confidence: "High",
                    predictedDropTime: "Evening",
                    trendPct: 0.12,
                    probability: 84,
                    reason: "Last release within the last day; still empty on the feed."
                ),
            ],
            premium: PremiumManager()
        )
        .padding()
    }
}
