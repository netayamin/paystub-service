import SwiftUI

/// Standard card for Hot Right Now and All Drops — clean iOS style.
struct DropCardView: View {
    let drop: Drop

    /// True if detected/created less than 5 minutes ago (show "New" badge)
    private var isJustReleased: Bool {
        guard let iso = drop.detectedAt ?? drop.createdAt else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return false }
        return d.timeIntervalSinceNow > -300  // 5 min, match web
    }
    
    /// Web-aligned: "Just now", "Last 30 mins", "Last hour", or nil
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
    
    private var firstSlot: DropSlot? { drop.slots.first }
    private var resyUrl: URL? {
        if let url = drop.resyUrl ?? firstSlot?.resyUrl, !url.isEmpty {
            return URL(string: url)
        }
        return nil
    }
    
    private var timeLabel: String {
        guard let slot = firstSlot, let time = slot.time, !time.isEmpty else { return "—" }
        return formatTime(time)
    }
    
    private var partyLabel: String {
        let sizes = drop.partySizesAvailable.sorted()
        if sizes.isEmpty { return "2 people" }
        if sizes.count == 1 { return "\(sizes[0]) people" }
        return sizes.map { "\($0)" }.joined(separator: ", ") + " people"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                cardBackground
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .clipped()
                
                HStack(alignment: .top, spacing: 6) {
                    if isJustReleased {
                        Text("New")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.badgeNew)
                            .cornerRadius(6)
                    } else {
                        Text(drop.feedHot == true ? "Hot" : "Trending")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(drop.feedHot == true ? AppTheme.badgeHot : AppTheme.badgeTrending)
                            .cornerRadius(6)
                    }
                    if let label = freshnessLabel {
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.badgeFreshness)
                            .cornerRadius(6)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            VStack(alignment: .leading, spacing: 8) {
                Text(drop.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                Text("\(drop.location ?? "NYC") · \(partyLabel)")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                
                HStack(spacing: 8) {
                    Text(timeLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Spacer()
                    
                    Button {
                        if let url = resyUrl {
                            UIApplication.shared.open(url)
                        } else if let slug = drop.venueKey, !slug.isEmpty {
                            if let url = URL(string: "https://resy.com/cities/ny/places/\(slug)") {
                                UIApplication.shared.open(url)
                            }
                        } else if let url = URL(string: "https://resy.com/cities/ny") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Reserve")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(14)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
    
    private var cardBackground: some View {
        Group {
            if let url = drop.imageUrl, let imageURL = URL(string: url), !url.isEmpty {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: gradientFallback
                    }
                }
            } else {
                gradientFallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
    
    private var gradientFallback: some View {
        LinearGradient(
            colors: [
                AppTheme.surfaceElevated,
                AppTheme.surface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func formatTime(_ time: String) -> String {
        let t = time.split(separator: "–").first.map(String.init) ?? time
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return String(t.prefix(8)) }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        if m > 0 {
            return String(format: "%d:%02d %@", hour12, m, ampm)
        }
        return String(format: "%d:00 %@", hour12, ampm)
    }
}

#Preview("Hot card") {
    DropCardView(drop: .preview)
        .padding()
}

#Preview("Trending card") {
    DropCardView(drop: .previewTrending)
        .padding()
}
