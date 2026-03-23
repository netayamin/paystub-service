import SwiftUI

// MARK: - Copy + formatting (Explore grid)

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
        return "Tonight’s inventory"
    }

    /// Lightning pill: opening chance, liquidity, or server tags.
    static func inventoryStatusLine(drop: Drop) -> String {
        if let tag = drop.exploreStatusTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            return tag.uppercased()
        }
        if let sc = drop.feedScarcityLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !sc.isEmpty {
            return sc.uppercased()
        }
        if let s = drop.snagScore {
            return "\(min(99, max(1, s)))% OPENING CHANCE"
        }
        if drop.velocityUrgent == true || drop.speedTier == "fast" {
            return "HIGH LIQUIDITY"
        }
        if let r = drop.rarityPoints, r > 0, r <= 12 {
            return "\(r) TABLES LEFT"
        }
        if drop.exploreSnagAvailable != false, drop.effectiveResyBookingURL != nil {
            return "INSTANT CONFIRM"
        }
        return "LIVE SLOT"
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

// MARK: - Card (reference: image + overlay copy, then title / arrow / line / pill)

/// Live inventory tile — square photo area, date + time + PAX on image; metadata + status pill below.
///
/// **Layout:** `Color.clear` + `aspectRatio` defines the square; the image lives in an `overlay` so a loaded
/// `UIImage`’s pixel size cannot inflate the card (avoids full-screen blow-up in `ScrollView`).
struct DSExploreInventoryCard: View {
    let drop: Drop
    var selectedDateStr: String?
    var partySegment: ExplorePartySegment
    var cornerRadius: CGFloat = DropFeedTokens.Layout.exploreCardCornerRadius
    var onTap: () -> Void

    private var pax: (number: String, suffix: String) {
        ExploreCardFormatting.paxParts(drop: drop, partySegment: partySegment)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                imageSection
                infoSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CreamEditorialTheme.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var imageSection: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    exploreImageLayer
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.0), location: 0.2),
                            .init(color: .black.opacity(0.25), location: 0.55),
                            .init(color: .black.opacity(0.72), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ExploreCardFormatting.imageNightLabel(drop: drop, selectedDateStr: selectedDateStr))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.95))
                            .tracking(0.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(ExploreCardFormatting.slotTime12h(drop: drop))
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)

                            (Text(pax.number).fontWeight(.semibold) + Text(pax.suffix).fontWeight(.regular))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .clipped()
            }
            .clipped()
    }

    @ViewBuilder
    private var exploreImageLayer: some View {
        if let s = drop.imageUrl, let u = URL(string: s) {
            CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                Color(white: 0.93)
            }
        } else {
            Color(white: 0.93)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(drop.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.88)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .thin))
                    .foregroundColor(Color(white: 0.55))
                    .layoutPriority(1)
            }

            Text(ExploreCardFormatting.cuisineLine(drop: drop))
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(CreamEditorialTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.88)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.burgundy)
                Text(ExploreCardFormatting.inventoryStatusLine(drop: drop))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.burgundy)
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DropFeedTokens.Semantic.exploreInventoryPillFill)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ScrollView {
        HStack(alignment: .top, spacing: 14) {
            DSExploreInventoryCard(
                drop: .preview,
                selectedDateStr: nil,
                partySegment: .two,
                onTap: {}
            )
            .frame(maxWidth: .infinity)
            DSExploreInventoryCard(
                drop: .previewTrending,
                selectedDateStr: nil,
                partySegment: .four,
                onTap: {}
            )
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    .background(CreamEditorialTheme.canvas)
}
