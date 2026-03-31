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

    static func slotTime12h(_ timeStr: String?) -> String {
        guard let t = timeStr, !t.isEmpty else { return "Evening" }
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t }
        let mm = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        if mm > 0 { return String(format: "%d:%02d %@", h12, mm, ap) }
        return "\(h12) \(ap)"
    }

    // kept for external callers
    static func slotTime12h(drop: Drop) -> String { slotTime12h(drop.slots.first?.time) }
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

    /// When `cornerRadius` is 0, use shared app card radius.
    private var effectiveOuterRadius: CGFloat {
        cornerRadius > 0 ? cornerRadius : AppTheme.cardCornerRadius
    }

    private static let thumbSize: CGFloat = 80
    private static let imgPad:    CGFloat = 10

    private var pax: (number: String, suffix: String) {
        ExploreCardFormatting.paxParts(drop: drop, partySegment: partySegment)
    }
    private var cuisineText: String? { cuisineLineIfMeaningful }
    private var isHot: Bool { drop.feedHot == true || drop.isHotspot == true }

    /// Deduplicated slots sorted by time, capped at 6.
    private var displaySlots: [DropSlot] {
        var seen = Set<String>()
        return drop.slots
            .sorted { ($0.time ?? "") < ($1.time ?? "") }
            .filter { seen.insert($0.time ?? "").inserted }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        // Outer tap = open best booking URL (fallback for tapping image / name area)
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 0) {
                thumbnail
                rightPanel
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: effectiveOuterRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: effectiveOuterRadius, style: .continuous)
                    .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: effectiveOuterRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Thumbnail

    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailImage
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardImageCornerRadius, style: .continuous))

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
        VStack(alignment: .leading, spacing: 6) {
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

            // Time slot pills (scrollable) + PAX
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(displaySlots.enumerated()), id: \.offset) { _, slot in
                            slotPill(slot)
                        }
                    }
                }

                Spacer(minLength: 8)

                (Text(pax.number).fontWeight(.bold) + Text(pax.suffix).fontWeight(.regular))
                    .font(.system(size: 11))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // Each time pill is its own Button so it can open a slot-specific URL.
    // Inner .plain buttons within an outer .plain button correctly intercept
    // their own taps without triggering the outer action.
    private func slotPill(_ slot: DropSlot) -> some View {
        Button {
            let urlString: String
            if let raw = slot.resyUrl, let url = URL(string: raw), !raw.isEmpty {
                urlString = raw
            } else if let best = drop.effectiveResyBookingURL {
                urlString = best
            } else {
                return
            }
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Text(ExploreCardFormatting.slotTime12h(slot.time))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CreamEditorialTheme.burgundy)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(CreamEditorialTheme.peachBadgeFill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
