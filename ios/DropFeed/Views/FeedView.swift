import SwiftUI

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    var onOpenSearch: (() -> Void)? = nil
    var onOpenAlerts: (() -> Void)? = nil
    var alertBadgeCount: Int = 0
    
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
            // Top nav: search, DropFeed title, bell
            topNavBar
            
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
        .onChange(of: feedVM.selectedDates) { _, _ in Task { await vm.refresh() } }
        .onChange(of: feedVM.selectedPartySizes) { _, _ in Task { await vm.refresh() } }
        .onChange(of: feedVM.selectedTimeFilter) { _, _ in Task { await vm.refresh() } }
    }
    
    private static let timeFilterOptions: [(id: String, label: String)] = [
        ("all", "All"),
        ("lunch", "Lunch"),
        ("3pm", "Afternoon"),
        ("7pm", "Early"),
        ("dinner", "Dinner")
    ]
    
    // MARK: - Top nav bar (search, DropFeed, bell)
    
    private var topNavBar: some View {
        HStack(spacing: 0) {
            Button {
                onOpenSearch?()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            
            Spacer()
            Text("DropFeed")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            
            Button {
                onOpenAlerts?()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    if alertBadgeCount > 0 {
                        Text("\(min(alertBadgeCount, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(AppTheme.accentOrange))
                            .offset(x: 6, y: -6)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(AppTheme.background)
    }
    
    // MARK: - Feed content
    
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Hero: #1 TOP OPPORTUNITY
                if let hero = vm.heroCard {
                    HeroCardView(
                        drop: hero,
                        isWatched: savedVM.isWatched(hero.name),
                        onToggleWatch: { savedVM.toggleWatch($0) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                
                // Live Scan Status
                liveScanStatusBlock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                
                // Hot Right Now (horizontal, "See all")
                if let hot = vm.hotRightNow, !hot.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Hot Right Now")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Button("See all") { /* could expand or go to search */ }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.accentOrange)
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(hot.prefix(10), id: \.id) { drop in
                                    HotRightNowCard(drop: drop, isWatched: savedVM.isWatched(drop.name), onToggleWatch: { savedVM.toggleWatch($0) })
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 24)
                }
                
                // Latest Drops (list with RARE/NEW, timestamp)
                if !vm.feedCards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Latest Drops")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                            .padding(.horizontal, 16)
                        
                        ForEach(Array(vm.feedCards.enumerated()), id: \.element.id) { index, drop in
                            LatestDropRowView(
                                drop: drop,
                                isWatched: savedVM.isWatched(drop.name),
                                onToggleWatch: { savedVM.toggleWatch($0) }
                            )
                            .padding(.horizontal, 16)
                            .staggeredAppear(index: index, delayPerItem: 0.03)
                        }
                    }
                    .padding(.bottom, 24)
                }
                
                // Likely to Open (predictive, SET ALERT)
                if !vm.likelyToOpen.isEmpty {
                    LikelyToOpenSection(
                        venues: vm.likelyToOpen,
                        premium: premium,
                        onNotifyMe: { savedVM.toggleWatch($0) },
                        isWatched: { savedVM.isWatched($0) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                
                Spacer(minLength: 120)
            }
        }
        .background(AppTheme.background)
    }
    
    private var liveScanStatusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.accentOrange)
                    .frame(width: 8, height: 8)
                Text("Live Scan Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            Text("\(vm.totalVenuesScanned) VENUES")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text("Scanning Manhattan, Brooklyn & Queens...")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
            // Progress bar (indeterminate-style fill based on scan freshness)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.surface)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.accentOrange)
                        .frame(width: max(40, geo.size.width * 0.6), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    // MARK: - Party size pills
    
    private var filtersPanel: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("Date, party size, and time")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                Spacer()
                if hasActiveFilters {
                    Button("Clear all") {
                        feedVM.selectedDates.removeAll()
                        feedVM.selectedPartySizes.removeAll()
                        feedVM.selectedTimeFilter = "all"
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            DateStripView(
                dateOptions: vm.dateOptions,
                selectedDates: $feedVM.selectedDates,
                calendarCounts: vm.calendarCounts
            )
            partySizeFilters
            timeFilters
                .padding(.bottom, 10)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func sectionHeader(_ title: String, subtitle: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 16)
    }
    
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
    
    // MARK: - Time filter pills
    
    private var timeFilters: some View {
        HStack(spacing: 6) {
            Text("Time")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
            
            ForEach(Self.timeFilterOptions, id: \.id) { opt in
                let isActive = vm.selectedTimeFilter == opt.id
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        feedVM.selectedTimeFilter = opt.id
                    }
                } label: {
                    Text(opt.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isActive ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isActive ? AppTheme.accent : AppTheme.pillUnselected)
                        .cornerRadius(10)
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
    
    private var hasActiveFilters: Bool {
        !feedVM.selectedDates.isEmpty || !feedVM.selectedPartySizes.isEmpty || feedVM.selectedTimeFilter != "all"
    }
    
    private var emptyTitle: String {
        if !hasActiveFilters {
            return "No drops yet"
        }
        if let first = feedVM.selectedDates.sorted().first, let dateStr = formatDateForEmptyState(first) {
            return "No tables for \(dateStr)"
        }
        return "No tables match your filters"
    }
    
    private var emptySubtitle: String {
        if !hasActiveFilters {
            return "We're scanning \(vm.totalVenuesScanned > 0 ? "\(vm.totalVenuesScanned)" : "your") venues. New tables will appear here the moment they drop."
        }
        return "Try another date, time, or party size — or clear filters to see all drops."
    }
    
    private func formatDateForEmptyState(_ yyyyMMdd: String) -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: yyyyMMdd) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "EEEE, MMM d"
        return out.string(from: d)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: hasActiveFilters ? "calendar.badge.exclamationmark" : "fork.knife")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.textTertiary)
            Text(emptyTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text(emptySubtitle)
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

// MARK: - Latest Drop row (thumbnail, name, RARE/NEW badge, description, timestamp)

private struct LatestDropRowView: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void
    
    private var statusBadge: (text: String, color: Color)? {
        let sec = drop.secondsSinceDetected
        if sec >= 0 && sec < 300 { return ("NEW", Color(red: 0.4, green: 0.6, blue: 0.95)) }
        if drop.scarcityTier == .rare { return ("RARE", AppTheme.scarcityRare) }
        return nil
    }
    
    private var rowDescription: String {
        let count = drop.slots.count
        if count > 1 { return "\(count) new tables released \(drop.freshnessLabel ?? "just now")" }
        return drop.freshnessLabel ?? "Table available"
    }
    
    private var timestampLabel: String {
        let sec = drop.secondsSinceDetected
        if sec < 60 { return "JUST NOW" }
        if sec < 3600 { return "\(sec / 60)M AGO" }
        if sec < 86400 { return "\(sec / 3600)H AGO" }
        return "1D AGO"
    }
    
    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }
    
    var body: some View {
        Button {
            if let url = resyUrl { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                AppTheme.surface
                            }
                        }
                    } else {
                        AppTheme.surface
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drop.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        if let badge = statusBadge {
                            Text(badge.text)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(badge.color)
                                .cornerRadius(4)
                        }
                    }
                    Text(rowDescription)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 8)
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(timestampLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                    Button { onToggleWatch(drop.name) } label: {
                        Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 14))
                            .foregroundColor(isWatched ? AppTheme.accentOrange : AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hot Right Now compact card

private struct HotRightNowCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void
    
    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }
    
    /// e.g. +124% or +12% from trend_pct
    private var trendPercentLabel: String? {
        guard let pct = drop.trendPct else { return nil }
        let value = Int(pct * 100)
        if value > 0 { return "+\(value)%" }
        if value < 0 { return "\(value)%" }
        return nil
    }
    
    var body: some View {
        Button {
            if let url = resyUrl { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let trend = trendPercentLabel {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accentOrange)
                        Text(trend)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(drop.trendUp == true ? AppTheme.accentOrange : AppTheme.textTertiary)
                    }
                }
                Text(drop.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(drop.neighborhood ?? drop.location ?? "NYC")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
            .padding(14)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Feed") {
    FeedView(feedVM: FeedViewModel(), savedVM: SavedViewModel(), premium: PremiumManager())
}
