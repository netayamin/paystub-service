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

    static func venueInitials(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "??" }
        let parts = trimmed.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 { return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased() }
        return String(trimmed.prefix(2)).uppercased()
    }

    static func dropAgoLabel(seconds: Int) -> String {
        if seconds < 90  { return "\(max(1, seconds))s ago" }
        if seconds < 3600 { return "\(max(1, seconds / 60))m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Live stream row

/// Full-width flat row inside the LIVE STREAM bordered container.
/// `isTaken = false` → JUST OPENED / black BOOK button.
/// `isTaken = true`  → JUST MISSED / gray outline TAKEN button (muted, desaturated).
struct LiveStreamOpenCard: View {
    let drop: Drop
    let preferredParty: Int
    let todayDateStr: String
    var isTaken: Bool = false
    var onTap: () -> Void

    // ── Design tokens ──────────────────────────────────────────────────────
    private let thumbSize: CGFloat  = 52
    private let thumbRadius: CGFloat = DropFeedTokens.Layout.exploreCardCornerRadius   // 10
    private let btnRadius: CGFloat   = DropFeedTokens.Layout.exploreCardCornerRadius   // 10

    // ── Computed content ───────────────────────────────────────────────────
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

    // ── View ───────────────────────────────────────────────────────────────
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                thumbnail
                textStack
                actionButton
            }
            .padding(.horizontal, DropFeedTokens.Layout.screenPadding)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Taken rows get a subtle fill so they visually recede
            .background(isTaken ? CreamEditorialTheme.takenFill : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // ── Subviews ───────────────────────────────────────────────────────────

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let u = imageURL {
                CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                    CreamEditorialTheme.canvas
                }
                .saturation(isTaken ? 0 : 1)
                .opacity(isTaken ? 0.55 : 1)
            } else {
                CreamEditorialTheme.canvas
            }
        }
        .frame(width: thumbSize, height: thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: thumbRadius, style: .continuous))
    }

    @ViewBuilder
    private var textStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Badge row — "JUST OPENED" in burgundy or "JUST MISSED" in takenText
            HStack(spacing: 5) {
                Text(isTaken ? "JUST MISSED" : "JUST OPENED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isTaken ? CreamEditorialTheme.takenText : CreamEditorialTheme.burgundy)
                    .tracking(0.35)
                Text(agoLabel)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
            }

            // Venue name
            Text(drop.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(isTaken ? CreamEditorialTheme.takenText : CreamEditorialTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            // Detail line — ⚡ claim time for open; "Sold Out" for taken
            if isTaken {
                Text("Sold Out")
                    .font(CreamEditorialTheme.metaSans)   // 12pt medium
                    .foregroundColor(CreamEditorialTheme.textTertiary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SnagDesignSystem.velocityAmber)
                    Text(claimTimeLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.velocityAmber)
                    Text(detailLine)
                        .font(CreamEditorialTheme.metaSans)   // 12pt medium
                        .foregroundColor(CreamEditorialTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isTaken {
            // Ghost outline — TAKEN
            Text("TAKEN")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(CreamEditorialTheme.takenText)
                .tracking(0.4)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: btnRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: btnRadius, style: .continuous)
                        .stroke(CreamEditorialTheme.takenText.opacity(0.4), lineWidth: 1.5)
                )
        } else {
            // Filled — BOOK (dims when no URL is available yet)
            let hasURL = drop.effectiveResyBookingURL != nil
            Text("BOOK")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(hasURL ? .white : CreamEditorialTheme.takenText)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(hasURL ? CreamEditorialTheme.textPrimary : CreamEditorialTheme.takenFill)
                .clipShape(RoundedRectangle(cornerRadius: btnRadius, style: .continuous))
        }
    }
}
