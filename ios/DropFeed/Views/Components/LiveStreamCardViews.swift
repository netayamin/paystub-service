import SwiftUI
import UIKit

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

    /// Slot time formatted as "7:30P" / "11:15A" for the availability button.
    static func slotTimeShort(_ drop: Drop) -> String {
        let raw = drop.slots.first?.time?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !raw.isEmpty else { return "BOOK" }
        let p = raw.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return "BOOK" }
        let mm = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let suffix = h >= 12 ? "P" : "A"
        let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return mm == 0 ? "\(h12)\(suffix)" : "\(h12):\(String(format: "%02d", mm))\(suffix)"
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

    /// Compact clock for slot pills (e.g. 7:15) — matches editorial feed cards.
    static func slotTimeCompact(_ t: String) -> String {
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "—" : String(t.prefix(5)) }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        return m > 0 ? "\(h12):\(String(format: "%02d", m))" : "\(h12)"
    }
}

// MARK: - Editorial reservation card (live stream — same spec as Latest drops reference)

private enum EditorialReservationCardChrome {
    static let cardFill = Color.white
    static let title = Color.black
    static let meta = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)
    static let slotBorder = Color(red: 0.78, green: 0.78, blue: 0.80)
    static let slotTime = Color.black
    static let slotParty = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let imageCorner: CGFloat = 12
    static let cardCorner: CGFloat = 22
    static let redBarWidth: CGFloat = 3
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
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardImageCornerRadius, style: .continuous))

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
                        .font(Manrope.title(14))
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

                // Availability time button — tapping opens Resy URL
                Text(LiveStreamCardFormatting.slotTimeShort(drop))
                    .font(Manrope.button(11))
                    .foregroundColor(hasURL ? .white : Color(red: 0.60, green: 0.60, blue: 0.62))
                    .tracking(1.5)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(hasURL ? Color(red: 0.08, green: 0.08, blue: 0.10) : Color(red: 0.90, green: 0.90, blue: 0.92))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .fill(Color(red: 0.99, green: 0.99, blue: 0.99))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live stream card (Quiet Curator — matches editorial reservation reference)

/// Same layout as the “L’Artusi” reference: white card, image + red bar, serif name, red freshness,
/// caps meta row, horizontal time / party pills; thin border, minimal shadow.
struct LiveStreamEventCard: View {
    let drop: Drop
    let preferredParty: Int
    var onTap: () -> Void

    /// Uppercased relative freshness, e.g. "1M AGO" (aligned with Latest drops cards).
    private var freshnessUppercased: String {
        if let iso = drop.userFacingOpenedAt ?? drop.detectedAt ?? drop.createdAt,
           let d = Drop.parseISO(iso) {
            let sec = max(0, Int(-d.timeIntervalSinceNow))
            if sec < 50 { return "NOW" }
            if sec < 3600 {
                let m = max(1, sec / 60)
                return "\(m)M AGO"
            }
            if sec < 86400 {
                let h = max(1, sec / 3600)
                return "\(h)H AGO"
            }
            let days = max(1, sec / 86400)
            return "\(days)D AGO"
        }
        let fallback = drop.serverFreshnessLabel ?? LiveStreamCardFormatting.dropAgoLabel(seconds: drop.secondsSinceDetected)
        return fallback.uppercased()
    }

    private var metaCapsLine: String {
        var parts: [String] = []
        if let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines), !nb.isEmpty {
            parts.append(nb.uppercased())
        }
        if let loc = drop.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            let nbl = (drop.neighborhood ?? "").lowercased()
            if loc.lowercased() != nbl { parts.append(loc.uppercased()) }
        }
        if !parts.isEmpty { return parts.joined(separator: " • ") }
        if let m = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            return m.uppercased()
        }
        return ""
    }

    private var slotChips: [DropSlot] {
        let raw = drop.slots
        if raw.isEmpty, drop.dateStr != nil || drop.effectiveResyBookingURL != nil {
            return [DropSlot(dateStr: drop.dateStr, time: nil, resyUrl: drop.resyUrl)]
        }
        return Array(raw.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    onTap()
                } label: {
                    HStack(spacing: 0) {
                        Group {
                            if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                                CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .lightOnLight) {
                                    Color(white: 0.94)
                                }
                            } else {
                                Color(white: 0.94)
                            }
                        }
                        .frame(width: 76, height: 76)
                        .clipped()

                        Rectangle()
                            .fill(EditorialReservationCardChrome.accentRed)
                            .frame(width: EditorialReservationCardChrome.redBarWidth)
                            .frame(height: 76)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: EditorialReservationCardChrome.imageCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: EditorialReservationCardChrome.imageCorner, style: .continuous)
                            .stroke(EditorialReservationCardChrome.slotBorder.opacity(0.6), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(drop.name)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(EditorialReservationCardChrome.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 4)

                        Text(freshnessUppercased)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(EditorialReservationCardChrome.accentRed)
                    }

                    if !metaCapsLine.isEmpty {
                        Text(metaCapsLine)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(EditorialReservationCardChrome.meta)
                            .lineLimit(2)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
            }

            if !slotChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(slotChips.enumerated()), id: \.offset) { _, slot in
                            let timeRaw = (slot.time ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let timeLabel = timeRaw.isEmpty ? "Book" : LiveStreamCardFormatting.slotTimeCompact(timeRaw)
                            let urlStr = slot.resyUrl ?? drop.effectiveResyBookingURL
                            Button {
                                if let s = urlStr, let u = URL(string: s) {
                                    UIApplication.shared.open(u)
                                } else {
                                    onTap()
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(timeLabel)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(EditorialReservationCardChrome.slotTime)
                                    Text("\(preferredParty)P")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(EditorialReservationCardChrome.slotParty)
                                }
                                .frame(minWidth: 52)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(EditorialReservationCardChrome.cardFill)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(EditorialReservationCardChrome.slotBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(urlStr == nil && drop.effectiveResyBookingURL == nil)
                            .opacity((urlStr == nil && drop.effectiveResyBookingURL == nil) ? 0.45 : 1)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(EditorialReservationCardChrome.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: EditorialReservationCardChrome.cardCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EditorialReservationCardChrome.cardCorner, style: .continuous)
                .stroke(EditorialReservationCardChrome.slotBorder.opacity(0.9), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}
