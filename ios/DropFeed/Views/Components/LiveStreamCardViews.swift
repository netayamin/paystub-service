import SwiftUI

// MARK: - Formatting

enum LiveStreamCardFormatting {
    static func slotTime24hColon(_ drop: Drop) -> String {
        let raw = drop.slots.first?.time?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !raw.isEmpty else { return "—" }
        let p = raw.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return String(raw.prefix(5)) }
        let mm = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        return String(format: "%02d:%02d", h, mm)
    }

    static func venueInitials(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "??" }
        let parts = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 { return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased() }
        return String(trimmed.prefix(2)).uppercased()
    }

    static func dropAgoLabel(seconds: Int) -> String {
        if seconds < 90 { return "\(max(1, seconds))s ago" }
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Open row

/// Full-width horizontal live-stream row using the Manrope typographic spec.
struct LiveStreamOpenCard: View {
    let drop: Drop
    let preferredParty: Int
    let todayDateStr: String
    var onTap: () -> Void

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var agoLabel: String {
        LiveStreamCardFormatting.dropAgoLabel(seconds: drop.secondsSinceDetected)
    }

    private var claimTimeLabel: String {
        if let avg = drop.avgDropDurationSeconds, avg > 0 {
            let s = min(120, max(5, Int(avg.rounded())))
            return s < 60 ? "< \(s)s" : "< \(max(1, s / 60))m"
        }
        let guess = max(8, 75 - min(70, drop.secondsSinceDetected))
        return "< \(guess)s"
    }

    private var detailLine: String {
        let kind = drop.liveStreamVelocityBadge
            ?? drop.exploreVenuePill
            ?? drop.rowPrimaryMetric
            ?? "Table"
        return "\(kind) • \(preferredParty)ppl"
    }

    private var hasURL: Bool { drop.effectiveResyBookingURL != nil }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {

                // Thumbnail — sharp square
                Group {
                    if let u = imageURL {
                        CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                            Color(red: 0.91, green: 0.91, blue: 0.93)
                        }
                    } else {
                        Color(red: 0.91, green: 0.91, blue: 0.93)
                    }
                }
                .frame(width: 72, height: 72)
                .clipped()

                // Text stack
                VStack(alignment: .leading, spacing: 3) {

                    // Signal label + time
                    HStack(spacing: 5) {
                        Text("JUST OPENED")
                            .font(Manrope.signalLabel(9))
                            .foregroundColor(CreamEditorialTheme.burgundy)
                            .tracking(0.6)
                        Text(agoLabel)
                            .font(Manrope.detail(10))
                            .foregroundColor(Color(red: 0.60, green: 0.60, blue: 0.62))
                    }

                    // Restaurant name — primary anchor
                    Text(drop.name.uppercased())
                        .font(Manrope.title(12))
                        .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)

                    // Secondary signals
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.0))
                        Text(claimTimeLabel)
                            .font(Manrope.detail(10))
                            .fontWeight(.semibold)
                            .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.0))
                        Text(detailLine)
                            .font(Manrope.detail(10))
                            .foregroundColor(Color(red: 0.60, green: 0.60, blue: 0.62))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                // BOOK button
                Text("BOOK")
                    .font(Manrope.button(11))
                    .foregroundColor(hasURL ? .white : Color(red: 0.60, green: 0.60, blue: 0.62))
                    .tracking(2.0)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(hasURL ? Color(red: 0.08, green: 0.08, blue: 0.10) : Color(red: 0.90, green: 0.90, blue: 0.92))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
