import SwiftUI

// MARK: - Copy + formatting (Explore rows)

enum ExploreCardFormatting {
    /// "TONIGHT" when slot date matches selected explore day; else "FRI OCT 18" style.
    static func imageNightLabel(drop: Drop, selectedDateStr: String?) -> String {
        let slotDateOpt = drop.slots.first?.dateStr ?? drop.dateStr
        guard let slotDate = slotDateOpt, !slotDate.isEmpty else { return "TONIGHT" }
        if let selected = selectedDateStr, slotDate == selected { return "TONIGHT" }
        return formatSlotHeaderDate(slotDate) ?? "TONIGHT"
    }

    static func formatSlotHeaderDate(_ dateStr: String) -> String? {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var c = DateComponents()
        c.year = y
        c.month = mo
        c.day = d
        guard let date = Calendar.current.date(from: c) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE MMM d"
        return df.string(from: date).uppercased()
    }

    static func paxParts(drop: Drop, partySegment: ExplorePartySegment) -> (number: String, suffix: String) {
        switch partySegment {
        case .two:
            return ("2", " PAX")
        case .four:
            return ("4", " PAX")
        case .anyParty:
            if let p = drop.partySizesAvailable.sorted().first, p > 0 {
                return ("\(p)", " PAX")
            }
            return ("2", " PAX")
        }
    }

    /// Cuisine / descriptor • neighborhood (reference description line).
    static func cuisineLine(drop: Drop) -> String {
        let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let s = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            if !nb.isEmpty, s.count < 36 {
                return "\(s) • \(nb)"
            }
            return s
        }
        if let line = drop.topOpportunitySubtitleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty, line.count < 42 {
            if !nb.isEmpty { return "\(line) • \(nb)" }
            return line
        }
        if !nb.isEmpty {
            return "Prime tables • \(nb)"
        }
        if let loc = drop.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            return "Tonight • \(loc)"
        }
        return "Tonight's inventory"
    }

    /// First slot time as `8:30 PM`; fallback when missing.
    static func slotTime12h(drop: Drop) -> String {
        guard let t = drop.slots.first?.time, !t.isEmpty else { return "Evening" }
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t }
        let mm = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        if mm > 0 { return String(format: "%d:%02d %@", h12, mm, ap) }
        return "\(h12) \(ap)"
    }
}

// MARK: - Row card

/// Full-width horizontal row: fixed thumbnail on the left, venue details on the right.
struct DSExploreInventoryCard: View {
    let drop: Drop
    var selectedDateStr: String?
    var partySegment: ExplorePartySegment
    var cornerRadius: CGFloat = 0   // kept for call-site compatibility, unused
    var onTap: () -> Void

    private static let thumbSize: CGFloat = 86

    private var pax: (number: String, suffix: String) {
        ExploreCardFormatting.paxParts(drop: drop, partySegment: partySegment)
    }
    private var nightLabel: String {
        ExploreCardFormatting.imageNightLabel(drop: drop, selectedDateStr: selectedDateStr)
    }
    private var timeLabel: String {
        ExploreCardFormatting.slotTime12h(drop: drop)
    }
    private var cuisineText: String? { cuisineLineIfMeaningful }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                thumbnail
                details
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CreamEditorialTheme.canvas)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CreamEditorialTheme.hairline)
                .frame(height: 1)
        }
    }

    // MARK: Thumbnail

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailImage

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.15),
                    .init(color: .black.opacity(0.22), location: 0.5),
                    .init(color: .black.opacity(0.72), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 1) {
                Text(nightLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                    .tracking(0.4)
                    .lineLimit(1)

                Text(timeLabel)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                (Text(pax.number).fontWeight(.semibold) + Text(pax.suffix).fontWeight(.regular))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: Self.thumbSize, height: Self.thumbSize)
        .clipped()
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let s = drop.imageUrl, let u = URL(string: s) {
            CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                Color(white: 0.91)
            }
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .clipped()
        } else {
            Color(white: 0.91)
                .frame(width: Self.thumbSize, height: Self.thumbSize)
        }
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(drop.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.88)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .thin))
                    .foregroundColor(Color(white: 0.55))
                    .layoutPriority(1)
            }

            if let cuisine = cuisineText {
                Text(cuisine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var cuisineLineIfMeaningful: String? {
        let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let s = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            if !nb.isEmpty, s.count < 36 { return "\(s) • \(nb)" }
            return s
        }
        if let line = drop.topOpportunitySubtitleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty, line.count < 42 {
            if !nb.isEmpty { return "\(line) • \(nb)" }
            return line
        }
        if !nb.isEmpty { return nb }
        return nil
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            DSExploreInventoryCard(drop: .preview, selectedDateStr: nil, partySegment: .two, onTap: {})
            DSExploreInventoryCard(drop: .previewTrending, selectedDateStr: nil, partySegment: .four, onTap: {})
        }
        .padding(.horizontal, 16)
    }
    .background(CreamEditorialTheme.canvas)
}
