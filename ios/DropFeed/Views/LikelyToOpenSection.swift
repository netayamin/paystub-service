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
                                .clipped()
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
        let forecastScore = venue.probability
        let conf = (venue.confidence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let confColor: Color = {
            switch conf.lowercased() {
            case "high": return SnagDesignSystem.mint
            case "low": return SnagDesignSystem.textMuted
            default: return SnagDesignSystem.textSection
            }
        }()
        let imgURL: URL? = {
            guard let s = venue.imageUrl, !s.isEmpty else { return nil }
            return URL(dropFeedMediaString: s) ?? URL(string: s)
        }()

        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if let url = imgURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                        ZStack {
                            SnagDesignSystem.cardGray
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(Color.black.opacity(0.08))
                        }
                    }
                } else {
                    ZStack {
                        SnagDesignSystem.cardGray
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 36, weight: .light))
                            .foregroundColor(Color.black.opacity(0.06))
                    }
                }
            }
            .frame(width: 172, height: 82)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(SnagDesignSystem.mint.opacity(0.2))
                            .frame(width: 28, height: 28)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SnagDesignSystem.mint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("FORECAST")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(SnagDesignSystem.textMuted)
                            .tracking(0.6)
                        Text(forecastScore.map { "\(min(99, max(1, $0)))" } ?? "—")
                            .font(.system(size: 18, weight: .black))
                            .foregroundColor(SnagDesignSystem.mint)
                    }
                }
                .padding(.bottom, 6)

                if !conf.isEmpty {
                    Text(conf.uppercased() + " CONFIDENCE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(confColor)
                        .padding(.bottom, 4)
                }

                Text(venue.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textDark)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(likelyTimeLine(venue))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.textMuted)
                    .padding(.top, 3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let ml = venue.forecastMetricsCompact, !ml.isEmpty {
                    Text(ml)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(SnagDesignSystem.textMuted)
                        .padding(.top, 2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if let reason = venue.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 9))
                        .foregroundColor(SnagDesignSystem.textSection)
                        .lineLimit(2)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .frame(width: 172, height: 106, alignment: .topLeading)
            .background(SnagDesignSystem.cardGray)
        }
        .frame(width: 172, height: 188, alignment: .top)
        .clipped()
    }

    private func likelyTimeLine(_ venue: LikelyToOpenVenue) -> String {
        if let h = venue.predictedDropHint, !h.isEmpty {
            return h
        }
        if let t = venue.predictedDropTime, !t.isEmpty {
            return t
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
                    venueId: "preview-1",
                    imageUrl: nil,
                    availabilityRate14d: 0.2,
                    daysWithDrops: 4,
                    rarityScore: 78,
                    lastSeenDescription: nil,
                    neighborhood: "Village",
                    confidence: "High",
                    predictedDropTime: "Typically 6pm–7pm ET",
                    predictedDropHint: "Often within the next few hours",
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
