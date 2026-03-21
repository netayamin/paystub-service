import SwiftUI

/// Snag mock: horizontal cards — mint uptrend + % PROB, venue, predicted time, faint chart watermark.
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
                    Text("Based on historical drop patterns for this week.")
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
                                .frame(width: 148, height: 148)
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
        let score = min(99, max(1, venue.probability ?? Int(round((venue.availabilityRate14d ?? 0) * 100))))
        let timeLine = likelyTimeLine(venue)

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
                    Text("\(score)% PROB")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(SnagDesignSystem.mint)
                }
                .padding(.bottom, 10)

                Spacer(minLength: 0)

                Text(venue.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textDark)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(timeLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.textMuted)
                    .padding(.top, 6)
            }
            .padding(14)
            .frame(width: 158, height: 158, alignment: .topLeading)
        }
        .frame(width: 158, height: 158)
    }

    private func likelyTimeLine(_ venue: LikelyToOpenVenue) -> String {
        if let t = venue.predictedDropTime, !t.isEmpty {
            return "TONIGHT @ \(t.uppercased())"
        }
        if let d = venue.daysWithDrops {
            return "ACTIVE \(d)/14 DAYS"
        }
        return "WATCH FOR DROP"
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
                    rarityScore: 0.75,
                    lastSeenDescription: nil,
                    neighborhood: "Village",
                    confidence: "High",
                    predictedDropTime: "9:30 PM",
                    trendPct: 0.1,
                    probability: 84,
                    reason: nil
                ),
            ],
            premium: PremiumManager()
        )
        .padding()
    }
}
