import SwiftUI

// MARK: - Formatting helpers

enum ExploreCardFormatting {
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

    // kept for any external callers
    static func imageNightLabel(drop: Drop, selectedDateStr: String?) -> String { "TONIGHT" }
    static func cuisineLine(drop: Drop) -> String {
        let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let s = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return !nb.isEmpty && s.count < 36 ? "\(s) • \(nb)" : s
        }
        if let line = drop.topOpportunitySubtitleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty, line.count < 42 {
            return !nb.isEmpty ? "\(line) • \(nb)" : line
        }
        return !nb.isEmpty ? "Prime tables • \(nb)" : "Tonight's inventory"
    }
}

// MARK: - Card

struct DSExploreInventoryCard: View {
    let drop: Drop
    var selectedDateStr: String?
    var partySegment: ExplorePartySegment
    var cornerRadius: CGFloat = 0   // kept for call-site compat
    var onTap: () -> Void

    private static let thumbSize: CGFloat = 80
    private static let imgPad:    CGFloat = 10

    private var pax: (number: String, suffix: String) {
        ExploreCardFormatting.paxParts(drop: drop, partySegment: partySegment)
    }
    private var timeLabel: String { ExploreCardFormatting.slotTime12h(drop: drop) }
    private var cuisineText: String? { cuisineLineIfMeaningful }
    private var isHot: Bool { drop.feedHot == true || drop.isHotspot == true }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                thumbnail
                rightPanel
            }
            .frame(maxWidth: .infinity)
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
        ZStack(alignment: .topTrailing) {
            thumbnailImage
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // HOT badge — only shown when feedHot or on hotspot list
            if isHot {
                Text("HOT")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
                    .tracking(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(CreamEditorialTheme.burgundy)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
        .padding(Self.imgPad)
        .frame(width: Self.thumbSize + Self.imgPad * 2,
               height: Self.thumbSize + Self.imgPad * 2)
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
        VStack(alignment: .leading, spacing: 5) {
            // Name
            Text(drop.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Cuisine / neighborhood
            if let cuisine = cuisineText {
                Text(cuisine)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Time button + PAX
            HStack(spacing: 8) {
                // Time pill — tappable feel, same action as the card
                Text(timeLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.burgundy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CreamEditorialTheme.peachBadgeFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // PAX
                (Text(pax.number).fontWeight(.bold) + Text(pax.suffix).fontWeight(.regular))
                    .font(.system(size: 12))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
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
        VStack(spacing: 12) {
            DSExploreInventoryCard(drop: .preview, selectedDateStr: nil, partySegment: .two, onTap: {})
            DSExploreInventoryCard(drop: .previewTrending, selectedDateStr: nil, partySegment: .four, onTap: {})
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    .background(CreamEditorialTheme.canvas)
}
