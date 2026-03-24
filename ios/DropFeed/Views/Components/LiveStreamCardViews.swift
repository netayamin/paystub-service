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

    static func detailLine(drop: Drop) -> String {
        let kind = drop.liveStreamVelocityBadge
            ?? drop.exploreVenuePill
            ?? drop.rowPrimaryMetric
            ?? "Table"
        let time = slotTime24hColon(drop)
        return "\(kind) • \(time)"
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

// MARK: - Open row (full-width horizontal)

/// Full-width horizontal card: thumbnail | JUST OPENED · ago / name / ⚡ claim time · detail | BOOK
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

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                // Thumbnail
                Group {
                    if let u = imageURL {
                        CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                            Color(red: 0.91, green: 0.91, blue: 0.93)
                        }
                    } else {
                        Color(red: 0.91, green: 0.91, blue: 0.93)
                    }
                }
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Text stack
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("JUST OPENED")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(CreamEditorialTheme.burgundy)
                            .tracking(0.4)
                        Text(agoLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(CreamEditorialTheme.textTertiary)
                    }

                    Text(drop.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(CreamEditorialTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)

                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.0))
                        Text(claimTimeLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.0))
                        Text(detailLine)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(CreamEditorialTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                // BOOK button
                Text("BOOK")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(0.6)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CreamEditorialTheme.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-width inactive rows

/// Sold-out / booked live row — mirrors LiveStreamOpenCard layout but muted.
struct LiveStreamSoldOutDropCard: View {
    let drop: Drop
    let preferredParty: Int

    private let mutedText = Color(red: 0.55, green: 0.55, blue: 0.58)
    private let cardFill = Color(red: 0.96, green: 0.96, blue: 0.97)

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var agoLabel: String {
        LiveStreamCardFormatting.dropAgoLabel(seconds: drop.secondsSinceDetected)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Thumbnail — desaturated
            Group {
                if let u = imageURL {
                    CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                        Color(red: 0.88, green: 0.88, blue: 0.90)
                    }
                    .saturation(0.0)
                    .opacity(0.6)
                } else {
                    Color(red: 0.88, green: 0.88, blue: 0.90)
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Text stack
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("JUST DROPPED")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(mutedText)
                        .tracking(0.4)
                    Text(agoLabel)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(CreamEditorialTheme.textTertiary)
                }

                Text(drop.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                Text("Sold Out")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            // TAKEN button (outline)
            Text("TAKEN")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(mutedText)
                .tracking(0.6)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(mutedText.opacity(0.4), lineWidth: 1.5)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
        )
    }
}
