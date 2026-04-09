import SwiftUI
import UIKit

/// Single shared “reservation drop” card: Explore calendar, live stream, and Latest drops.
enum EditorialReservationCardTokens {
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

struct EditorialReservationCard: View {
    let drop: Drop
    /// Second line of each slot chip, e.g. "2 PEOPLE".
    let partyPeopleText: String
    var cornerRadius: CGFloat = DropFeedTokens.Layout.exploreCardCornerRadius
    var showBookmark: Bool = false
    var isWatched: Bool = false
    var onToggleWatch: ((String) -> Void)? = nil
    var statusBadge: (text: String, color: Color)? = nil
    let onHeroTap: () -> Void

    private var metaLine: String {
        ExploreCardFormatting.neighborhoodCuisineMeta(drop: drop)
    }

    private var droppedLine: String {
        ExploreCardFormatting.droppedAgoLine(drop: drop)
    }

    private var displaySlots: [DropSlot] {
        var seen = Set<String>()
        let sorted = drop.slots
            .sorted { ($0.time ?? "") < ($1.time ?? "") }
            .filter { seen.insert($0.time ?? "").inserted }
        if sorted.isEmpty, drop.dateStr != nil || drop.effectiveResyBookingURL != nil {
            return [DropSlot(dateStr: drop.dateStr, time: nil, resyUrl: drop.resyUrl)]
        }
        return Array(sorted.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                leadingThumbnail
                    .onTapGesture { onHeroTap() }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(drop.name)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(EditorialReservationCardTokens.title)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if showBookmark, let toggle = onToggleWatch {
                            Button { toggle(drop.name) } label: {
                                Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(isWatched ? EditorialReservationCardTokens.accentRed : EditorialReservationCardTokens.meta)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isWatched ? "Remove from saved" : "Save venue")
                        }
                    }

                    if let badge = statusBadge {
                        Text(badge.text)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badge.color)
                            .clipShape(Capsule())
                    }

                    metaAndDroppedRow
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onHeroTap() }
            }

            if !displaySlots.isEmpty {
                slotPillsRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EditorialReservationCardTokens.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(EditorialReservationCardTokens.slotBorder.opacity(0.95), lineWidth: 1)
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
            .frame(width: EditorialReservationCardTokens.thumb, height: EditorialReservationCardTokens.thumb)
            .clipped()

            Rectangle()
                .fill(EditorialReservationCardTokens.accentRed)
                .frame(width: EditorialReservationCardTokens.redBarWidth)
                .frame(height: EditorialReservationCardTokens.thumb)
        }
        .clipShape(RoundedRectangle(cornerRadius: EditorialReservationCardTokens.imageCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EditorialReservationCardTokens.imageCorner, style: .continuous)
                .stroke(EditorialReservationCardTokens.slotBorder.opacity(0.65), lineWidth: 0.5)
        )
    }

    private var metaAndDroppedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !metaLine.isEmpty {
                Text(metaLine)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(EditorialReservationCardTokens.meta)
                    .lineLimit(1)
                Text(" · ")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(EditorialReservationCardTokens.meta)
            }
            Text(droppedLine)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(EditorialReservationCardTokens.accentRed)
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
                onHeroTap()
                return
            }
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(spacing: 3) {
                Text(ExploreCardFormatting.slotTime12h(slot.time))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(EditorialReservationCardTokens.title)
                Text(partyPeopleText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(EditorialReservationCardTokens.meta)
            }
            .multilineTextAlignment(.center)
            .frame(minWidth: 56)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(EditorialReservationCardTokens.slotFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(EditorialReservationCardTokens.slotBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
