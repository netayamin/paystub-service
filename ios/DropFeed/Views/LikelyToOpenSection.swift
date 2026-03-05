import SwiftUI

struct LikelyToOpenSection: View {
    let venues: [LikelyToOpenVenue]
    @ObservedObject var premium: PremiumManager
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
                            Text("Likely to Open Soon")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Based on 14-day drop patterns")
                                .font(.system(size: 11))
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
                    VStack(spacing: 0) {
                        ForEach(allVisible) { venue in
                            venueRow(venue)
                        }
                        
                        // Premium gate
                        if !lockedVenues.isEmpty {
                            ZStack {
                                VStack(spacing: 0) {
                                    ForEach(lockedVenues.prefix(2)) { venue in
                                        venueRow(venue)
                                            .opacity(0.3)
                                            .blur(radius: 2)
                                    }
                                }
                                
                                Button {
                                    showPaywall = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 14))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(lockedVenues.count) more — Unlock with Premium")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Get instant alerts the second these tables drop")
                                                .font(.system(size: 11))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                    }
                                    .foregroundColor(AppTheme.premiumGold)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(AppTheme.premiumGoldBg)
                                    .cornerRadius(12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
    
    private func venueRow(_ venue: LikelyToOpenVenue) -> some View {
        HStack(spacing: 12) {
            // Image
            ZStack {
                if let urlStr = venue.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: rowImageFallback(venue.name)
                        }
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
                if let desc = venue.lastSeenDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                } else if let days = venue.daysWithDrops {
                    Text("Had tables \(days) of last 14 days")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer(minLength: 0)
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
