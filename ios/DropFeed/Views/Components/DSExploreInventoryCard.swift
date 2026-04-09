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

    /// Slot row party label — calendar reference: "2 PEOPLE".
    static func peopleLabel(drop: Drop, partySegment: ExplorePartySegment) -> String {
        let (n, _) = paxParts(drop: drop, partySegment: partySegment)
        return "\(n) PEOPLE"
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

    /// "West Village • Italian" style for calendar cards (neighborhood • cuisine/secondary).
    static func neighborhoodCuisineMeta(drop: Drop) -> String {
        let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let loc = drop.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sub = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !nb.isEmpty && !loc.isEmpty && loc.lowercased() != nb.lowercased() {
            return "\(nb) • \(loc)"
        }
        if !nb.isEmpty && !sub.isEmpty {
            return "\(nb) • \(sub)"
        }
        if !nb.isEmpty { return nb }
        if !loc.isEmpty { return loc }
        return sub
    }

    /// Uppercased recency fragment, e.g. "2M AGO" / "NOW".
    static func freshnessMagnitudeAgo(drop: Drop) -> String {
        if let iso = drop.userFacingOpenedAt ?? drop.detectedAt ?? drop.createdAt,
           let d = Drop.parseISO(iso) {
            let sec = max(0, Int(-d.timeIntervalSinceNow))
            if sec < 50 { return "NOW" }
            if sec < 3600 { return "\(max(1, sec / 60))M AGO" }
            if sec < 86400 { return "\(max(1, sec / 3600))H AGO" }
            return "\(max(1, sec / 86400))D AGO"
        }
        if let f = drop.serverFreshnessLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
            return f.uppercased()
        }
        let s = drop.secondsSinceDetected
        if s < 90 { return "NOW" }
        if s < 3600 { return "\(max(1, s / 60))M AGO" }
        if s < 86400 { return "\(max(1, s / 3600))H AGO" }
        return "\(max(1, s / 86400))D AGO"
    }

    /// "DROPPED 2M AGO" (calendar reference).
    static func droppedAgoLine(drop: Drop) -> String {
        "DROPPED \(freshnessMagnitudeAgo(drop: drop))"
    }
}

// MARK: - Explore / calendar grid card (shared `EditorialReservationCard`)

struct DSExploreInventoryCard: View {
    let drop: Drop
    var selectedDateStr: String?
    var partySegment: ExplorePartySegment
    var cornerRadius: CGFloat = 0
    var onTap: () -> Void

    private var effectiveOuterRadius: CGFloat {
        cornerRadius > 0 ? cornerRadius : 22
    }

    var body: some View {
        EditorialReservationCard(
            drop: drop,
            partyPeopleText: ExploreCardFormatting.peopleLabel(drop: drop, partySegment: partySegment),
            cornerRadius: effectiveOuterRadius,
            onHeroTap: onTap
        )
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
