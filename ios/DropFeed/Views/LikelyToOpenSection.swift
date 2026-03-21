import SwiftUI

struct LikelyToOpenSection: View {
    let venues: [LikelyToOpenVenue]
    @ObservedObject var premium: PremiumManager
    var onNotifyMe: ((String) -> Void)? = nil
    var isWatched: ((String) -> Bool)? = nil
    @State private var expanded = false
    @State private var showPaywall = false
    
    private var freeLimit: Int { PremiumManager.freeLikelyToOpenLimit }
    private var freeVenues: [LikelyToOpenVenue] { Array(venues.prefix(freeLimit)) }
    private var lockedVenues: [LikelyToOpenVenue] { premium.isPremium ? [] : Array(venues.dropFirst(freeLimit)) }
    private var allVisible: [LikelyToOpenVenue] { premium.isPremium ? venues : freeVenues }
    
    var body: some View {
        if venues.isEmpty { EmptyView() } else {
            VStack(spacing: 0) {
                // Header
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Likely to Open")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("From 14-day table-release patterns — not cancellations")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Text("\(venues.count)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textTertiary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textTertiary)
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                
                if expanded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(allVisible) { venue in
                                likelyToOpenCard(venue)
                            }
                            if !lockedVenues.isEmpty {
                                Button {
                                    showPaywall = true
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 20))
                                        Text("\(lockedVenues.count) more")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(AppTheme.premiumGold)
                                    .frame(width: 140, height: 120)
                                    .background(AppTheme.premiumGoldBg)
                                    .cornerRadius(14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView(premium: premium)
            }
        }
    }
    
    private func likelyToOpenCard(_ venue: LikelyToOpenVenue) -> some View {
        // Backend `probability` is a composite pattern-strength index (1–99), not P(open).
        let score = min(99, max(1, venue.probability ?? Int(round((venue.availabilityRate14d ?? 0) * 100))))
        let watched = isWatched?(venue.name) ?? false
        let subtitle: String = {
            if let r = venue.reason, !r.isEmpty { return r }
            if let t = venue.predictedDropTime { return "Typical window: \(t)" }
            if let d = venue.daysWithDrops { return "Activity on \(d) of last 14 days" }
            return "Nothing open now — watch for releases"
        }()
        
        return VStack(alignment: .leading, spacing: 10) {
            Text(venue.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text("\(score)% pattern match")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.textTertiary)
                if let c = venue.confidence, !c.isEmpty {
                    Text(c.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.85))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.surfaceElevated)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppTheme.accentOrange)
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 4)
                }
            }
            .frame(height: 4)
            
            if let onNotify = onNotifyMe {
                Button {
                    onNotify(venue.name)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: watched ? "bell.fill" : "bell.badge")
                            .font(.system(size: 11))
                        Text(watched ? "Watching" : "SET ALERT")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(watched ? AppTheme.textTertiary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(watched ? AppTheme.surfaceElevated : AppTheme.accentOrange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 160, alignment: .leading)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
    
    private func venueRow(_ venue: LikelyToOpenVenue) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if let urlStr = venue.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { rowImageFallback(venue.name) }
                    }
                } else {
                    rowImageFallback(venue.name)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                if let days = venue.daysWithDrops {
                    Text("Open \(days) of last 14 days")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if let onNotify = onNotifyMe {
                let watched = isWatched?(venue.name) ?? false
                Button { onNotify(venue.name) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: watched ? "bell.fill" : "bell.badge").font(.system(size: 11))
                        Text(watched ? "Watching" : "SET ALERT").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(watched ? AppTheme.textTertiary : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(watched ? AppTheme.surfaceElevated : AppTheme.accentOrange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func rowImageFallback(_ name: String) -> some View {
        ZStack {
            AppTheme.surfaceElevated
            Text(String(name.prefix(1)))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
        }
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        LikelyToOpenSection(
            venues: [
                LikelyToOpenVenue(name: "Don Angie", imageUrl: nil, availabilityRate14d: 0.12, daysWithDrops: 2, rarityScore: 0.9, lastSeenDescription: "Last open yesterday at 7pm", neighborhood: "West Village"),
                LikelyToOpenVenue(name: "I Sodi", imageUrl: nil, availabilityRate14d: 0.15, daysWithDrops: 3, rarityScore: 0.85, lastSeenDescription: nil, neighborhood: "West Village"),
                LikelyToOpenVenue(name: "Via Carota", imageUrl: nil, availabilityRate14d: 0.20, daysWithDrops: 4, rarityScore: 0.75, lastSeenDescription: nil, neighborhood: "West Village"),
                LikelyToOpenVenue(name: "Lilia", imageUrl: nil, availabilityRate14d: 0.25, daysWithDrops: 5, rarityScore: 0.6, lastSeenDescription: nil, neighborhood: "Williamsburg"),
                LikelyToOpenVenue(name: "Tatiana", imageUrl: nil, availabilityRate14d: 0.10, daysWithDrops: 2, rarityScore: 0.92, lastSeenDescription: nil, neighborhood: "UWS"),
            ],
            premium: PremiumManager()
        )
        .padding()
    }
}
