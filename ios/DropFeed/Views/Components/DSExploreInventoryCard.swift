import SwiftUI

// MARK: - Copy + formatting (Explore rows)

enum ExploreCardFormatting {
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
        c.year = y; c.month = mo; c.day = d
        guard let date = Calendar.current.date(from: c) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE MMM d"
        return df.string(from: date).uppercased()
    }

    static func paxParts(drop: Drop, partySegment: ExplorePartySegment) -> (number: String, suffix: String) {
        switch partySegment {
        case .two:   return ("2", " PAX")
        case .four:  return ("4", " PAX")
        case .anyParty:
            if let p = drop.partySizesAvailable.sorted().first, p > 0 { return ("\(p)", " PAX") }
            return ("2", " PAX")
        }
    }

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

/// Full-width row: square thumbnail on the left with a time badge overlay,
/// restaurant name + description + PAX info on the white right panel.
struct DSExploreInventoryCard: View {
    let drop: Drop
    var selectedDateStr: String?
    var partySegment: ExplorePartySegment
    var cornerRadius: CGFloat = 0   // kept for call-site compat
    var onTap: () -> Void

    private static let thumbSize: CGFloat = 110

    private var pax: (number: String, suffix: String) {
        ExploreCardFormatting.paxParts(drop: drop, partySegment: partySegment)
    }
    private var nightLabel: String {
        ExploreCardFormatting.imageNightLabel(drop: drop, selectedDateStr: selectedDateStr)
    }
    private var timeLabel: String { ExploreCardFormatting.slotTime12h(drop: drop) }
    private var cuisineText: String? { cuisineLineIfMeaningful }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                thumbnail
                rightPanel
            }
            .frame(maxWidth: .infinity, minHeight: Self.thumbSize)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: Thumbnail

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailImage
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Dark time badge at bottom-left of image
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                Text(timeLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)
        }
        .padding(10)
        .frame(width: Self.thumbSize + 20, height: Self.thumbSize + 20)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let s = drop.imageUrl, let u = URL(string: s) {
            CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                Color(white: 0.91)
            }
            .frame(width: Self.thumbSize, height: Self.thumbSize)
        } else {
            Color(white: 0.91)
                .frame(width: Self.thumbSize, height: Self.thumbSize)
        }
    }

    // MARK: Right panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Name
            Text(drop.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.88)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Cuisine / neighborhood
            if let cuisine = cuisineText {
                Text(cuisine)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }

            Spacer(minLength: 10)

            // Night label + PAX — bottom-right, mimics "price" position
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(nightLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(1)

                Spacer()

                Text(pax.number)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                + Text(pax.suffix)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: Self.thumbSize, alignment: .topLeading)
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
        VStack(spacing: 12) {
            DSExploreInventoryCard(drop: .preview, selectedDateStr: nil, partySegment: .two, onTap: {})
            DSExploreInventoryCard(drop: .previewTrending, selectedDateStr: nil, partySegment: .four, onTap: {})
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    .background(CreamEditorialTheme.canvas)
}
