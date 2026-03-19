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
        guard let iso = drop.detectedAt ?? drop.createdAt else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return false }
        return d.timeIntervalSinceNow > -600  // within last 10 mins
    }
    
    /// Web-aligned: "Just now" (0–5 min), "Last 30 mins", "Last hour", or nil after 60 min
    private var freshnessLabel: String? {
        guard let iso = drop.detectedAt ?? drop.createdAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let sec = Int(-d.timeIntervalSinceNow)
        if sec < 5 * 60 { return "Just now" }
        if sec < 30 * 60 { return "Last 30 mins" }
        if sec < 60 * 60 { return "Last hour" }
        return nil
    }
    
    private var demandLabel: String {
        if drop.feedHot == true { return "HIGH DEMAND" }
        return "TRENDING"
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
                    .cornerRadius(8)

                    if isJustReleased {
                        Text("New")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppTheme.badgeNew)
                            .cornerRadius(8)
                    }
                    if let label = freshnessLabel {
                        Text(label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(AppTheme.badgeFreshness)
                            .cornerRadius(8)
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
                                UIApplication.shared.open(url)
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
                    .cornerRadius(12)

                    if resyUrl != nil {
                        Button {
                            UIApplication.shared.open(resyUrl!)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(AppTheme.surfaceElevated)
                                .cornerRadius(12)
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
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
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
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    default:
                        gradientFallback
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    }
                }
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
        if (drop.ratingCount ?? 0) > 500 { return "Usually fully booked" }
        if drop.feedHot == true { return "Usually fully booked" }
        return "New opening"
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
