import SwiftUI

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    
    private var vm: FeedViewModel { feedVM }
    
    private let partySizeOptions = [2, 3, 4, 5, 6]
    
    private var viewStateId: String {
        if vm.isLoading && vm.drops.isEmpty { return "loading" }
        if vm.error != nil { return "error" }
        if vm.drops.isEmpty { return "empty" }
        return "content"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar: LIVE + scan info
            topBar
            
            Group {
                if vm.isLoading && vm.drops.isEmpty {
                    FeedSkeletonView()
                } else if let err = vm.error {
                    errorView(err)
                } else if vm.drops.isEmpty {
                    emptyView
                } else {
                    feedContent
                }
            }
            // Animate content transitions without tying .task to the changing id
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewStateId)
        }
        .background(AppTheme.background)
        // task + refreshable live on the stable outer VStack so they never re-trigger on state change
        .refreshable {
            await vm.refresh()
        }
        .task {
            await vm.refresh()
            vm.startPolling()
        }
    }
    
    // MARK: - Top bar
    
    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                AnimatedLiveDot()
                Text("LIVE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            
            Spacer()
            
            if vm.totalVenuesScanned > 0 {
                Text("\(vm.totalVenuesScanned) venues")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            if vm.lastScanText != "—" {
                Text(vm.lastScanText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
    }
    
    // MARK: - Feed content
    
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Date strip
                DateStripView(
                    dateOptions: vm.dateOptions,
                    selectedDates: $feedVM.selectedDates,
                    calendarCounts: vm.calendarCounts
                )
                .padding(.bottom, 4)
                
                // Party size filter pills
                partySizeFilters
                    .padding(.bottom, 8)
                
                // Hero card (top-ranked drop)
                if let hero = vm.heroCard {
                    HeroCardView(
                        drop: hero,
                        isWatched: savedVM.isWatched(hero.name),
                        onToggleWatch: { savedVM.toggleWatch($0) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                
                // Ranked feed
                if !vm.feedCards.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LATEST DROPS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.textTertiary)
                            .tracking(1)
                            .padding(.horizontal, 16)
                        
                        ForEach(Array(vm.feedCards.enumerated()), id: \.element.id) { index, drop in
                            DropCardView(
                                drop: drop,
                                isWatched: savedVM.isWatched(drop.name),
                                onToggleWatch: { savedVM.toggleWatch($0) }
                            )
                            .padding(.horizontal, 16)
                            .staggeredAppear(index: index, delayPerItem: 0.03)
                        }
                    }
                    .padding(.bottom, 16)
                }
                
                // Likely to Open
                if !vm.likelyToOpen.isEmpty {
                    LikelyToOpenSection(
                        venues: vm.likelyToOpen,
                        premium: premium
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                
                Spacer(minLength: 120)
            }
        }
        .background(AppTheme.background)
    }
    
    // MARK: - Party size pills
    
    private var partySizeFilters: some View {
        HStack(spacing: 6) {
            Text("Party")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
            
            ForEach(partySizeOptions, id: \.self) { size in
                let isActive = vm.selectedPartySizes.contains(size)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isActive {
                            vm.selectedPartySizes.remove(size)
                        } else {
                            vm.selectedPartySizes.insert(size)
                        }
                    }
                } label: {
                    Text("\(size)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isActive ? .white : AppTheme.textSecondary)
                        .frame(width: 36, height: 32)
                        .background(isActive ? AppTheme.accent : AppTheme.pillUnselected)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            
            if !vm.selectedPartySizes.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vm.selectedPartySizes.removeAll()
                    }
                } label: {
                    Text("Clear")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Error / Empty states
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.textTertiary)
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") { Task { await vm.refresh() } }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppTheme.accent)
                .cornerRadius(12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.background)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.textTertiary)
            Text("No drops yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text("We're scanning \(vm.totalVenuesScanned > 0 ? "\(vm.totalVenuesScanned)" : "your") venues. New tables will appear here the moment they drop.")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.background)
    }
}

#Preview("Feed") {
    FeedView(feedVM: FeedViewModel(), savedVM: SavedViewModel(), premium: PremiumManager())
}
