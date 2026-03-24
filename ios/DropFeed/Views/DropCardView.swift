import SwiftUI

/// Scarcity-first card for the ranked feed.
struct DropCardView: View {
    let drop: Drop
    var isWatched: Bool = false
    var onToggleWatch: ((String) -> Void)?
    
    private var slots: [DropSlot] { Array(drop.slots.prefix(4)) }
    
    private var firstResyURL: URL? {
        if let url = drop.resyUrl ?? drop.slots.first?.resyUrl, !url.isEmpty {
            return URL(string: url)
        }
        return nil
    }
    
    private var partyLabel: String? {
        let sizes = drop.partySizesAvailable.sorted()
        guard !sizes.isEmpty else { return nil }
        if sizes.count == 1 { return "\(sizes[0]) guests" }
        return "\(sizes.first!)–\(sizes.last!) guests"
    }
    
    private var dateLabel: String {
        guard let ds = drop.dateStr ?? drop.slots.first?.dateStr else { return "" }
        let cal = Calendar.current
        let today = Date()
        let todayStr = String(format: "%04d-%02d-%02d",
                              cal.component(.year, from: today),
                              cal.component(.month, from: today),
                              cal.component(.day, from: today))
        if ds == todayStr { return "Today" }
        if let tom = cal.date(byAdding: .day, value: 1, to: today) {
            let tomStr = String(format: "%04d-%02d-%02d",
                                cal.component(.year, from: tom),
                                cal.component(.month, from: tom),
                                cal.component(.day, from: tom))
            if ds == tomStr { return "Tomorrow" }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let d = fmt.date(from: ds) {
            let display = DateFormatter()
            display.dateFormat = "EEE, MMM d"
            return display.string(from: d)
        }
        return ds
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Image
            ZStack {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                        imageFallback
                    }
                } else {
                    imageFallback
                }
            }
            .frame(width: 72, height: 72)
            .clipped()
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Name + bookmark
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(drop.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            if drop.feedHot == true || drop.isHotspot == true {
                                Text("HOT")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(AppTheme.scarcityRare)
                            }
                        }
                        
                        HStack(spacing: 4) {
                            if let loc = drop.neighborhood ?? drop.location, !loc.isEmpty {
                                Text(loc)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            if !dateLabel.isEmpty {
                                Text("·")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text(dateLabel)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                    
                    if let onToggleWatch {
                        Button { onToggleWatch(drop.name) } label: {
                            Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 14))
                                .foregroundColor(isWatched ? AppTheme.accentRed : AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Scarcity + trend + freshness
                HStack(spacing: 8) {
                    if let label = drop.scarcityLabel {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.scarcityColor(for: drop.scarcityTier))
                                .frame(width: 6, height: 6)
                            Text(label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.scarcityColor(for: drop.scarcityTier))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.scarcityBackground(for: drop.scarcityTier))
                    }
                    
                    if let trend = drop.trendLabel, let up = drop.trendUp {
                        HStack(spacing: 3) {
                            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text(trend)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(up ? AppTheme.accent : AppTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.surfaceElevated)
                    }
                    
                    if let freshness = drop.serverFreshnessLabel {
                        Text(freshness)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    if let party = partyLabel {
                        Text(party)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                // Time slot pills
                if !slots.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                            slotButton(slot)
                        }
                        if drop.slots.count > 4 {
                            Text("+\(drop.slots.count - 4)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipped()
        .overlay(
            Rectangle()
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
    
    private func slotButton(_ slot: DropSlot) -> some View {
        Group {
            if let urlStr = slot.resyUrl, let url = URL(string: urlStr) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    slotLabel(slot, hasLink: true)
                }
                .buttonStyle(.plain)
            } else {
                slotLabel(slot, hasLink: false)
            }
        }
    }
    
    private func slotLabel(_ slot: DropSlot, hasLink: Bool) -> some View {
        HStack(spacing: 3) {
            Text(formatTime(slot.time ?? ""))
                .font(.system(size: 12, weight: .semibold))
            if hasLink {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.5)
            }
        }
        .foregroundColor(hasLink ? AppTheme.textPrimary : AppTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hasLink ? AppTheme.surfaceElevated : AppTheme.surfaceElevated.opacity(0.5))
    }
    
    private var imageFallback: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.surfaceElevated, AppTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String(drop.name.prefix(1)))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
        }
    }
    
    private func formatTime(_ time: String) -> String {
        let t = time.split(separator: "–").first.map(String.init) ?? time
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return String(t.prefix(8)) }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "am" : "pm"
        return m > 0 ? "\(hour12):\(String(format: "%02d", m))\(ampm)" : "\(hour12)\(ampm)"
    }
}

#Preview("Hot card") {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        DropCardView(drop: .preview, isWatched: true)
            .padding()
    }
}

#Preview("Trending card") {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        DropCardView(drop: .previewTrending)
            .padding()
    }
}
