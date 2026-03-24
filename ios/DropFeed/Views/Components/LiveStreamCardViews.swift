import SwiftUI

// MARK: - Formatting

enum LiveStreamCardFormatting {
    /// `HH:mm` from first slot (reference detail line).
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
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(trimmed.prefix(2)).uppercased()
    }

    static func dropAgoLabel(seconds: Int) -> String {
        if seconds < 90 { return "\(max(1, seconds))s ago" }
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Live stream row

/// Full-width flat row — used for both JUST OPENED (isTaken=false) and JUST MISSED (isTaken=true).
struct LiveStreamOpenCard: View {
    let drop: Drop
    let preferredParty: Int
    let todayDateStr: String
    var isTaken: Bool = false
    var onTap: () -> Void

    private static let amber   = Color(red: 1.0, green: 0.72, blue: 0.0)
    private static let mutedFg = Color(red: 0.60, green: 0.60, blue: 0.62)
    private static let mutedBg = Color(red: 0.96, green: 0.96, blue: 0.97)

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

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {

                // Thumbnail — 52×52, desaturated when taken
                Group {
                    if let u = imageURL {
                        CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                            Color(red: 0.91, green: 0.91, blue: 0.93)
                        }
                        .saturation(isTaken ? 0 : 1)
                        .opacity(isTaken ? 0.55 : 1)
                    } else {
                        Color(red: 0.91, green: 0.91, blue: 0.93)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    // Badge row
                    HStack(spacing: 5) {
                        Text(isTaken ? "JUST MISSED" : "JUST OPENED")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(isTaken ? Self.mutedFg : CreamEditorialTheme.burgundy)
                            .tracking(0.3)
                        Text(agoLabel)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(CreamEditorialTheme.textTertiary)
                    }

                    // Venue name
                    Text(drop.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isTaken ? Self.mutedFg : CreamEditorialTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    // Detail row
                    if isTaken {
                        Text("Sold Out")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(CreamEditorialTheme.textTertiary)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Self.amber)
                            Text(claimTimeLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Self.amber)
                            Text(detailLine)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(CreamEditorialTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                // Action button
                if isTaken {
                    Text("TAKEN")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Self.mutedFg)
                        .tracking(0.4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Self.mutedFg.opacity(0.45), lineWidth: 1.5)
                        )
                } else {
                    let hasURL = drop.effectiveResyBookingURL != nil
                    Text("BOOK")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(hasURL ? .white : Self.mutedFg)
                        .tracking(0.5)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(hasURL ? Color.black : Self.mutedBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isTaken ? Self.mutedBg : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
