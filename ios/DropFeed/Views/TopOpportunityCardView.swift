import SwiftUI

/// Premium horizontal card for Top Opportunities — image/gradient, badges, time slot CTA.
struct TopOpportunityCardView: View {
    let drop: Drop
    
    private var firstSlot: DropSlot? { drop.slots.first }
    private var resyUrl: URL? {
        if let url = drop.resyUrl ?? firstSlot?.resyUrl, !url.isEmpty {
            return URL(string: url)
        }
        return nil
    }
    
    /// Slot always has a time (e.g. 7:30 or 19:30), not a date.
    private var primaryTimeLabel: String {
        guard let slot = firstSlot, let time = slot.time, !time.isEmpty else { return "Reserve" }
        return formatTimeForSlot(time)
    }
    
    private var isJustReleased: Bool {
        drop.showNewBadge == true
    }
    
    private var freshnessLabel: String? {
        drop.topOpportunityFreshnessBadge
    }
    
    private var demandLabel: String {
        drop.topOpportunityDemandLabel ?? "POPULAR"
    }

    private func openResy(_ url: URL) {
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
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            AppTheme.background
            // Image fills entire card edge-to-edge
            cardBackground
                .frame(width: 300, height: 280)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                        Text(demandLabel)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(drop.feedHot == true ? AppTheme.badgeHot : AppTheme.badgeTrending)

                    if isJustReleased {
                        Text("New")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppTheme.badgeNew)
                    }
                    if let label = freshnessLabel {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppTheme.badgeFreshness)
                    }
                    Spacer()
                }
                .padding(12)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(drop.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                    Text("\(drop.location ?? "NYC") • \(subtitleSuffix)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

                // Time + ellipsis on top of card bg (no white strip)
                HStack(alignment: .center, spacing: 10) {
                    Group {
                        if let url = resyUrl {
                            Button {
                                openResy(url)
                            } label: {
                                timeLabelContent
                            }
                            .buttonStyle(ScaleButtonStyle())
                        } else {
                            timeLabelContent
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppTheme.textPrimary)

                    if resyUrl != nil {
                        Button {
                            openResy(resyUrl!)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(AppTheme.surfaceElevated)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 300, height: 280)
        .clipped()
        .overlay(
            Rectangle()
                .strokeBorder(AppTheme.border, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: drop.id)
    }
    
    private var timeLabelContent: some View {
        Text(primaryTimeLabel)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(AppTheme.background)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
    
    private var cardBackground: some View {
        Group {
            if let url = drop.imageUrl, let imageURL = URL(string: url), !url.isEmpty {
                CardAsyncImage(url: imageURL, contentMode: .fill, skeletonTone: .warmPlaceholder) {
                    gradientFallback
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            } else {
                gradientFallback
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
        )
    }
    
    private var gradientFallback: some View {
        LinearGradient(
            colors: [
                Color(red: 0.85, green: 0.5, blue: 0.35),
                Color(red: 0.7, green: 0.4, blue: 0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var subtitleSuffix: String {
        drop.topOpportunitySubtitleLine ?? "Popular"
    }
    
    /// Parses slot time (e.g. "19:30" or "7:30") and returns "7:30 PM". Fallback "Reserve" if missing/invalid.
    private func formatTimeForSlot(_ time: String) -> String {
        let t = time.split(separator: "–").first.map(String.init) ?? time
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 1, let h = Int(parts[0]), (0...23).contains(h) else { return "Reserve" }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        if m > 0 {
            return String(format: "%d:%02d %@", hour12, m, ampm)
        }
        return String(format: "%d:00 %@", hour12, ampm)
    }
}

#Preview("Top Opportunity – Hot") {
    ScrollView(.horizontal) {
        HStack {
            TopOpportunityCardView(drop: .preview)
            TopOpportunityCardView(drop: .previewTrending)
        }
        .padding()
    }
    .background(Color(red: 0.12, green: 0.12, blue: 0.14))
}

#Preview("Single card") {
    TopOpportunityCardView(drop: .preview)
        .padding()
}
