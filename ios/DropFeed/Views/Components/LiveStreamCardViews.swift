import SwiftUI

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

// MARK: - Live event variant (Quiet Curator stream)

/// One card = one detectable moment (just dropped / table spotted) — distinct from editorial “open row” tiles.
struct LiveStreamEventCard: View {
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

    private var eventBadge: String {
        if drop.brandNewDrop == true || drop.showNewBadge == true { return "JUST DROPPED" }
        if let t = drop.exploreStatusTag, !t.isEmpty {
            let u = t.uppercased()
            return u.count <= 20 ? u : String(u.prefix(18)) + "…"
        }
        if drop.velocityUrgent == true { return "HOT OPENING" }
        return "LIVE SPOT"
    }

    private var eventSubtitle: String {
        if let ds = drop.dateStr, !ds.isEmpty, ds == todayDateStr {
            return "New bookable window · tonight"
        }
        return "New bookable slot on the feed"
    }

    private var neighborhoodLine: String {
        var parts: [String] = []
        if let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines), !nb.isEmpty {
            parts.append(nb)
        }
        parts.append("\(preferredParty) guests")
        if let slot = drop.slots.first?.time, !slot.isEmpty {
            parts.append(LiveStreamCardFormatting.slotTimeShort(drop))
        }
        return parts.joined(separator: " · ")
    }

    private var hasURL: Bool { drop.effectiveResyBookingURL != nil }

    private var urgencyProgress: CGFloat {
        guard let avg = drop.avgDropDurationSeconds, avg > 0 else {
            return min(1, CGFloat(drop.secondsSinceDetected) / 120.0)
        }
        return CGFloat(min(1, max(0, Double(drop.secondsSinceDetected) / avg)))
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                // Timeline rail (event node + stem — fixed height avoids ScrollView layout blow-up)
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.25, blue: 0.22))
                            .frame(width: 11, height: 11)
                        TimelineView(.periodic(from: .now, by: 0.9)) { ctx in
                            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
                            Circle()
                                .stroke(Color(red: 0.95, green: 0.25, blue: 0.22).opacity(0.35 + 0.4 * phase), lineWidth: 2)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .padding(.top, 6)
                    Rectangle()
                        .fill(Color(red: 0.95, green: 0.25, blue: 0.22).opacity(0.22))
                        .frame(width: 2, height: 112)
                }
                .frame(width: 22)

                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 0) {
                        Group {
                            if let u = imageURL {
                                CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                                    Color(red: 0.93, green: 0.93, blue: 0.95)
                                }
                            } else {
                                Color(red: 0.93, green: 0.93, blue: 0.95)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipped()
                        Rectangle()
                            .fill(Color(red: 0.95, green: 0.25, blue: 0.22))
                            .frame(width: 3)
                            .frame(height: 64)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(eventBadge)
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(Color(red: 0.95, green: 0.25, blue: 0.22))
                                .tracking(0.65)
                            Spacer(minLength: 4)
                            Text(agoLabel.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.95, green: 0.25, blue: 0.22))
                                .tracking(0.4)
                        }

                        Text(eventSubtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(red: 0.48, green: 0.48, blue: 0.52))

                        Text(drop.name)
                            .font(.system(size: 17, weight: .bold, design: .serif))
                            .foregroundColor(Color(red: 0.06, green: 0.06, blue: 0.08))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.88)

                        if !neighborhoodLine.isEmpty {
                            Text(neighborhoodLine)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 0.52, green: 0.52, blue: 0.56))
                                .lineLimit(1)
                        }

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.black.opacity(0.06))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.95, green: 0.35, blue: 0.28),
                                            Color(red: 0.85, green: 0.2, blue: 0.22),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(maxWidth: .infinity)
                                .scaleEffect(x: max(0.08, min(1, urgencyProgress)), y: 1, anchor: .leading)
                        }
                        .frame(height: 3)
                        .padding(.top, 2)

                        HStack {
                            Text(LiveStreamCardFormatting.slotTimeShort(drop))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(hasURL ? .white : Color(red: 0.55, green: 0.55, blue: 0.58))
                                .tracking(1.1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(hasURL ? Color(red: 0.08, green: 0.08, blue: 0.10) : Color(red: 0.90, green: 0.90, blue: 0.92))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 4)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 6)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.35, blue: 0.28).opacity(0.45),
                                Color.black.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}
