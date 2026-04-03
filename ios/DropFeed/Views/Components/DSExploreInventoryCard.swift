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

// MARK: - Card (reference: left copy + metrics row, right square thumb, rounded card on gray canvas)

struct DSExploreInventoryCard: View {
    let drop: Drop
    var selectedDateStr: String?
    var partySegment: ExplorePartySegment
    var cornerRadius: CGFloat = 0
    var onTap: () -> Void

    private var effectiveOuterRadius: CGFloat {
        cornerRadius > 0 ? cornerRadius : AppTheme.cardCornerRadius
    }

    private static let thumbSize: CGFloat = 88

    private static let starGold = Color(red: 0.92, green: 0.72, blue: 0.12)

    private var isHot: Bool { drop.feedHot == true || drop.isHotspot == true }

    private var displaySlots: [DropSlot] {
        var seen = Set<String>()
        return drop.slots
            .sorted { ($0.time ?? "") < ($1.time ?? "") }
            .filter { seen.insert($0.time ?? "").inserted }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 14) {
                leftColumn
                thumbnail
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CreamEditorialTheme.cardWhite)
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

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(drop.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let cuisine = cuisineSubtitle {
                Text(cuisine)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            statsRow
                .padding(.top, 2)

            if !displaySlots.isEmpty {
                slotPillsRow
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Star · rating · clock · status · pin · area (matches reference hierarchy).
    private var statsRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Self.starGold)
                Text(ratingLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
            }
            .layoutPriority(1)

            metricDot

            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                Text(statusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            metricDot

            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                Text(areaLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(1)
            }
            .layoutPriority(0)

            Spacer(minLength: 0)
        }
        .minimumScaleFactor(0.78)
        .lineLimit(1)
    }

    private var metricDot: some View {
        Text("·")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(CreamEditorialTheme.textTertiary.opacity(0.55))
            .padding(.horizontal, 6)
    }

    private var ratingLabel: String {
        guard let r = drop.ratingAverage, r > 0 else { return "—" }
        return String(format: "%.1f", r)
    }

    private var statusLabel: String {
        if drop.exploreSnagAvailable == false {
            return "Taken"
        }
        if let tag = drop.exploreStatusTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            return tag
        }
        if !drop.slots.isEmpty {
            return "Open"
        }
        return drop.exploreCanSnag ? "Open" : "Check Resy"
    }

    private var statusColor: Color {
        if drop.exploreSnagAvailable == false {
            return CreamEditorialTheme.streamRed
        }
        return CreamEditorialTheme.textPrimary
    }

    private var areaLabel: String {
        let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nb.isEmpty { return nb }
        if let pill = drop.exploreVenuePill?.trimmingCharacters(in: .whitespacesAndNewlines), !pill.isEmpty {
            return pill
        }
        if let m = drop.market?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            return m.uppercased()
        }
        if let loc = drop.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            return loc
        }
        return "—"
    }

    private var cuisineSubtitle: String? {
        if let s = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        if let pill = drop.exploreVenuePill?.trimmingCharacters(in: .whitespacesAndNewlines), !pill.isEmpty {
            return pill
        }
        if let line = drop.topOpportunitySubtitleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty, line.count < 52 {
            return line
        }
        let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nb.isEmpty { return nb }
        return nil
    }

    // MARK: - Thumbnail (right)

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
        .overlay(alignment: .topLeading) {
            if drop.exploreShowDot == true {
                Circle()
                    .fill(CreamEditorialTheme.liveDot)
                    .frame(width: 8, height: 8)
                    .padding(6)
            }
        }
        .frame(width: Self.thumbSize, height: Self.thumbSize)
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

    // MARK: - Slot pills

    private var slotPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(displaySlots.enumerated()), id: \.offset) { _, slot in
                    slotPill(slot)
                }
            }
        }
    }

    private func slotPill(_ slot: DropSlot) -> some View {
        Button {
            let urlString: String
            if let raw = slot.resyUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(CreamEditorialTheme.burgundy)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(CreamEditorialTheme.peachBadgeFill)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
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
