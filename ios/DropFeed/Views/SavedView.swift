import SwiftUI

struct SavedView: View {
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var premium: PremiumManager
    @State private var showPaywall = false
    
    private var watchedDrops: [Drop] {
        let ranked = feedVM.drops
        return ranked.filter { savedVM.isWatched($0.name) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.accentRed)
                        Text("Saved")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    Text("Restaurants you're watching. You'll get alerts when tables drop.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Search
                searchSection
                
                // Saved chips
                if !savedVM.watchedVenues.isEmpty {
                    savedChips
                }
                
                // Notification grid
                notifyGrid
                
                // Excluded
                if !savedVM.excludedVenues.isEmpty {
                    excludedGrid
                }
                
                // Active drops
                if !watchedDrops.isEmpty {
                    activeDropsSection
                } else if !savedVM.watchedVenues.isEmpty {
                    emptyDrops
                }
                
                Spacer(minLength: 120)
            }
        }
        .background(AppTheme.background)
        .task { await savedVM.loadAll() }
    }
    
    // MARK: - Search
    
    private var searchSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
                TextField("Search any restaurant to watch…", text: $savedVM.searchText)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
                    .autocorrectionDisabled()
                    .onSubmit {
                        let q = savedVM.searchText.trimmingCharacters(in: .whitespaces)
                        guard q.count >= 2 else { return }
                        if premium.watchlistLimitReached(currentCount: savedVM.watchedVenues.count) {
                            showPaywall = true
                        } else {
                            savedVM.toggleWatch(q)
                            savedVM.searchText = ""
                        }
                    }
                if !savedVM.searchText.isEmpty {
                    Button {
                        savedVM.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            
            // Suggestions dropdown
            if !savedVM.searchSuggestions.isEmpty || savedVM.showFreeTextAdd {
                VStack(spacing: 0) {
                    ForEach(savedVM.searchSuggestions, id: \.self) { name in
                        Button {
                            if premium.watchlistLimitReached(currentCount: savedVM.watchedVenues.count) {
                                showPaywall = true
                            } else {
                                savedVM.toggleWatch(name)
                                savedVM.searchText = ""
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text(name)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().background(AppTheme.border)
                    }
                    if savedVM.showFreeTextAdd {
                        Button {
                            if premium.watchlistLimitReached(currentCount: savedVM.watchedVenues.count) {
                                showPaywall = true
                            } else {
                                savedVM.toggleWatch(savedVM.searchText.trimmingCharacters(in: .whitespaces))
                                savedVM.searchText = ""
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppTheme.accentRed)
                                Text("Add \"\(savedVM.searchText.trimmingCharacters(in: .whitespaces))\"")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.accentRed)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(AppTheme.surfaceElevated)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 12)
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(premium: premium)
        }
    }
    
    // MARK: - Saved chips
    
    private var savedChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR SAVED")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(1)
            
            ChipFlowLayout(spacing: 6) {
                ForEach(savedVM.watchedVenues.sorted(), id: \.self) { name in
                    HStack(spacing: 4) {
                        Text(name.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                        Button {
                            savedVM.toggleWatch(name)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surfaceElevated)
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Notify grid
    
    private var notifyGrid: some View {
        let venues = savedVM.notifyVenues
        return VStack(alignment: .leading, spacing: 8) {
            Text("Getting alerts (\(venues.count) spots)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            
            if venues.isEmpty {
                Text("Search above to add restaurants.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(venues, id: \.name) { v in
                        HStack(spacing: 6) {
                            Text(v.name.capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                if v.isSaved {
                                    savedVM.toggleWatch(v.name)
                                } else {
                                    savedVM.addExclude(v.name)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(AppTheme.surface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Excluded
    
    private var excludedGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Removed (\(savedVM.excludedVenues.count))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(savedVM.excludedVenues.sorted(), id: \.self) { name in
                    HStack(spacing: 6) {
                        Text(name.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            savedVM.removeExclude(name)
                        } label: {
                            Text("Add back")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.liveDot)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(AppTheme.surfaceElevated.opacity(0.5))
                    .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Active drops
    
    private var activeDropsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVE DROPS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(1)
                .padding(.horizontal, 16)
            
            ForEach(watchedDrops) { drop in
                DropCardView(
                    drop: drop,
                    isWatched: true,
                    onToggleWatch: { savedVM.toggleWatch($0) }
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }
    
    private var emptyDrops: some View {
        VStack(spacing: 8) {
            Text("Nothing open right now")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            Text("Drops will appear here the moment they're detected for your saved restaurants.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}

// MARK: - ChipFlowLayout (horizontal wrapping for saved chips)

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        
        return (CGSize(width: maxWidth, height: y + lineHeight), frames)
    }
}

#Preview {
    SavedView(
        savedVM: SavedViewModel(),
        feedVM: FeedViewModel(),
        premium: PremiumManager()
    )
}
