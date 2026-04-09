import SwiftUI
import UIKit

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

// MARK: - Calendar / Explore card chrome (reference: white, #E3524F accent)

private enum ExploreCalendarCardChrome {
    static let cardFill = Color.white
    static let title = Color.black
    static let meta = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let accentRed = Color(red: 227 / 255, green: 82 / 255, blue: 79 / 255)
    static let slotBorder = Color(red: 0.78, green: 0.78, blue: 0.80)
    static let slotFill = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let imageCorner: CGFloat = 12
    static let redBarWidth: CGFloat = 3
    static let thumb: CGFloat = 76
}

// MARK: - Card (calendar reference: left image + red bar, serif name, meta · DROPPED, slot grid)

struct DSExploreInventoryCard: View {
    let drop: Drop
    var selectedDateStr: String?
    var partySegment: ExplorePartySegment
    var cornerRadius: CGFloat = 0
    var onTap: () -> Void

    private var effectiveOuterRadius: CGFloat {
        cornerRadius > 0 ? cornerRadius : 22
    }

    private var displaySlots: [DropSlot] {
        var seen = Set<String>()
        return drop.slots
            .sorted { ($0.time ?? "") < ($1.time ?? "") }
            .filter { seen.insert($0.time ?? "").inserted }
            .prefix(8)
            .map { $0 }
    }

    private var metaLine: String {
        ExploreCardFormatting.neighborhoodCuisineMeta(drop: drop)
    }

    private var droppedLine: String {
        ExploreCardFormatting.droppedAgoLine(drop: drop)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                leadingThumbnail
                    .onTapGesture { onTap() }

                VStack(alignment: .leading, spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(ExploreCalendarCardChrome.title)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    metaAndDroppedRow
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
            }

            if !displaySlots.isEmpty {
                slotPillsRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ExploreCalendarCardChrome.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: effectiveOuterRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: effectiveOuterRadius, style: .continuous)
                .stroke(ExploreCalendarCardChrome.slotBorder.opacity(0.95), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }

    private var leadingThumbnail: some View {
        HStack(spacing: 0) {
            Group {
                if let s = drop.imageUrl, let u = URL(string: s) {
                    CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                        Color(white: 0.94)
                    }
                } else {
                    Color(white: 0.94)
                }
            }
            .frame(width: ExploreCalendarCardChrome.thumb, height: ExploreCalendarCardChrome.thumb)
            .clipped()

            Rectangle()
                .fill(ExploreCalendarCardChrome.accentRed)
                .frame(width: ExploreCalendarCardChrome.redBarWidth)
                .frame(height: ExploreCalendarCardChrome.thumb)
        }
        .clipShape(RoundedRectangle(cornerRadius: ExploreCalendarCardChrome.imageCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ExploreCalendarCardChrome.imageCorner, style: .continuous)
                .stroke(ExploreCalendarCardChrome.slotBorder.opacity(0.65), lineWidth: 0.5)
        )
    }

    /// "West Village • Italian · DROPPED 2M AGO" — gray meta, dot, red dropped label.
    private var metaAndDroppedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(ExploreCalendarCardChrome.meta)
                    .lineLimit(1)
                Text(" · ")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(ExploreCalendarCardChrome.meta)
            }
            Text(droppedLine)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(ExploreCalendarCardChrome.accentRed)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .minimumScaleFactor(0.75)
        .lineLimit(1)
    }

    private var slotPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            VStack(spacing: 3) {
                Text(ExploreCardFormatting.slotTime12h(slot.time))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(ExploreCalendarCardChrome.title)
                Text(ExploreCardFormatting.peopleLabel(drop: drop, partySegment: partySegment))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ExploreCalendarCardChrome.meta)
            }
            .multilineTextAlignment(.center)
            .frame(minWidth: 56)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ExploreCalendarCardChrome.slotFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(ExploreCalendarCardChrome.slotBorder, lineWidth: 1)
            )
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
