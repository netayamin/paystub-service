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

    static func missedAgoLabel(iso: String?) -> String {
        guard let iso, let d = Drop.parseISO(iso) else { return "just now" }
        let sec = max(0, Int(-d.timeIntervalSinceNow))
        if sec < 90 { return "\(max(1, sec))s ago" }
        if sec < 3600 { return "\(max(1, sec / 60))m ago" }
        return "\(sec / 3600)h ago"
    }

    static func dropAgoLabel(seconds: Int) -> String {
        if seconds < 90 { return "\(max(1, seconds))s ago" }
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Open tile (2-col grid)

/// Reference: top row (time + TODAY / date + PAX pill), square image, bold name + neighborhood line.
struct LiveStreamOpenCard: View {
    let drop: Drop
    let preferredParty: Int
    /// `YYYY-MM-DD` for “TODAY” vs other labels (from ``FeedViewModel/todayDateStr``).
    let todayDateStr: String
    var onTap: () -> Void

    private let cardFill = Color(red: 0.94, green: 0.94, blue: 0.96)
    private let imagePlaceholder = Color(red: 0.92, green: 0.92, blue: 0.94)

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var slotDateStr: String? {
        let s = drop.slots.first?.dateStr ?? drop.dateStr
        guard let u = s?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return nil }
        return u
    }

    private var dayChinLabel: String {
        guard let ds = slotDateStr else { return "SOON" }
        if ds == todayDateStr { return "TODAY" }
        let p = ds.split(separator: "-")
        guard p.count == 3,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return "UPCOMING" }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        guard let date = Calendar.current.date(from: c) else { return "UPCOMING" }
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date).uppercased()
    }

    private var footerDetailLine: String {
        let n = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let loc = drop.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !n.isEmpty, !loc.isEmpty { return "\(n) • \(loc)" }
        if !n.isEmpty { return n }
        if !loc.isEmpty { return loc }
        let kind = drop.liveStreamVelocityBadge ?? drop.exploreVenuePill ?? "Table"
        return "\(kind) • \(LiveStreamCardFormatting.slotTime24hColon(drop))"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LiveStreamCardFormatting.slotTime24hColon(drop))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(CreamEditorialTheme.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(dayChinLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(CreamEditorialTheme.textTertiary)
                            .tracking(0.35)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    Text("\(preferredParty) PAX")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(0.25)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Color.clear
                    .aspectRatio(1.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Group {
                            if let u = imageURL {
                                CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                                    imagePlaceholder
                                }
                            } else {
                                imagePlaceholder
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 10)

                Text(drop.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                Text(footerDetailLine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
            .background(cardFill)
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

struct LiveStreamJustMissedCard: View {
    let venue: JustMissedVenue

    private let cardFill = Color(red: 0.94, green: 0.94, blue: 0.96)

    private var timeColumn: String {
        let t = venue.slotTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if t.isEmpty { return "—" }
        let p = t.split(separator: ":")
        if let h = p.first.flatMap({ Int($0) }) {
            let mm = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
            return String(format: "%02d:%02d", h, mm)
        }
        return String(t.prefix(5))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeColumn)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .monospacedDigit()
                Text("2 PAX")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CreamEditorialTheme.textTertiary.opacity(0.9))
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.5))
                    .lineLimit(1)
                Text(claimedSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .italic()
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CreamEditorialTheme.textTertiary.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
        )
    }

    private var claimedSubtitle: String {
        let ago = LiveStreamCardFormatting.missedAgoLabel(iso: venue.goneAt)
        return "Claimed · \(ago)"
    }
}

/// Sold-out / booked live row (same chrome as just-missed reference).
struct LiveStreamSoldOutDropCard: View {
    let drop: Drop
    let preferredParty: Int

    private let cardFill = Color(red: 0.94, green: 0.94, blue: 0.96)

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LiveStreamCardFormatting.slotTime24hColon(drop))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .monospacedDigit()
                Text("\(preferredParty) PAX")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CreamEditorialTheme.textTertiary.opacity(0.9))
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.5))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .italic()
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CreamEditorialTheme.textTertiary.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
        )
    }

    private var subtitle: String {
        let ago = LiveStreamCardFormatting.dropAgoLabel(seconds: drop.secondsSinceDetected)
        return "Table for \(preferredParty) • Booked · \(ago)"
    }
}
