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

/// Reference: padded gray card, inset rounded image, **PAX** badge on image, bold name, gray detail line.
struct LiveStreamOpenCard: View {
    let drop: Drop
    let preferredParty: Int
    var onTap: () -> Void

    private let cardFill = Color(red: 0.94, green: 0.94, blue: 0.96)
    private let imagePlaceholder = Color(red: 0.92, green: 0.92, blue: 0.94)

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(1.08, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        ZStack(alignment: .topTrailing) {
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

                            Text("\(preferredParty) PAX")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .tracking(0.2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.58))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .padding(8)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                Text(drop.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                Text(LiveStreamCardFormatting.detailLine(drop: drop))
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

// MARK: - JUST MISSED subsection

struct LiveStreamMissedSectionHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(CreamEditorialTheme.textTertiary.opacity(0.55))
                .frame(width: 6, height: 6)
            Text("JUST MISSED")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textTertiary)
                .tracking(0.35)
            Spacer(minLength: 12)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Self.clockString(for: context.date))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private static func clockString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm zzz"
        return f.string(from: date).uppercased()
    }
}

// MARK: - Full-width inactive rows

struct LiveStreamJustMissedCard: View {
    let venue: JustMissedVenue

    private let cardFill = Color(red: 0.94, green: 0.94, blue: 0.96)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(LiveStreamCardFormatting.venueInitials(venue.name))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textSecondary)
                .frame(width: 48, height: 48)
                .background(Color(red: 0.90, green: 0.90, blue: 0.93))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(CreamEditorialTheme.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
        )
    }

    private var subtitle: String {
        let time = venue.slotTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timePart = (time?.isEmpty == false) ? time! : "—"
        let ago = LiveStreamCardFormatting.missedAgoLabel(iso: venue.goneAt)
        return "Table for 2 • \(timePart) · \(ago)"
    }
}

/// Sold-out / booked live row (same chrome as just-missed reference).
struct LiveStreamSoldOutDropCard: View {
    let drop: Drop
    let preferredParty: Int

    private let cardFill = Color(red: 0.94, green: 0.94, blue: 0.96)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(LiveStreamCardFormatting.venueInitials(drop.name))
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textSecondary)
                .frame(width: 48, height: 48)
                .background(Color(red: 0.90, green: 0.90, blue: 0.93))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(CreamEditorialTheme.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
        )
    }

    private var subtitle: String {
        let ago = LiveStreamCardFormatting.dropAgoLabel(seconds: drop.secondsSinceDetected)
        return "Table for \(preferredParty) • Booked · \(ago)"
    }
}
