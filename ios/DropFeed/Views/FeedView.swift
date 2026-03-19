import SwiftUI

// MARK: - FeedView

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    var onOpenSearch: (() -> Void)? = nil
    var onOpenAlerts: (() -> Void)? = nil
    var alertBadgeCount: Int = 0

    private var vm: FeedViewModel { feedVM }

    /// Maps internal key → display label for time filter pills
    private let timeFilters: [(key: String, label: String)] = [
        ("all",    "Any Time"),
        ("lunch",  "Lunch"),
        ("3pm",    "3–5 PM"),
        ("7pm",    "7–9 PM"),
        ("dinner", "Late Night"),
    ]

    private var viewStateId: String {
        if vm.isLoading && vm.drops.isEmpty { return "loading" }
        if vm.error != nil && vm.drops.isEmpty { return "error" }
        if vm.drops.isEmpty { return "empty" }
        return "content"
    }

    private var hasActiveFilters: Bool {
        !vm.selectedDates.isEmpty || vm.selectedTimeFilter != "all" || !vm.selectedPartySizes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            topNavBar
            filterBar
            Group {
                if vm.isLoading && vm.drops.isEmpty {
                    FeedSkeletonView()
                        .transition(.opacity)
                } else if let err = vm.error, vm.drops.isEmpty {
                    inlineErrorView(err)
                } else {
                    mainFeedContent
                }
            }
            .animation(.easeInOut(duration: 0.28), value: viewStateId)
        }
        .background(AppTheme.background)
        .refreshable { await vm.refresh() }
        .task {
            await vm.refresh()
            vm.startPolling()
        }
        .onChange(of: feedVM.selectedDates)      { _, _ in Task { await vm.refresh() } }
        .onChange(of: feedVM.selectedPartySizes) { _, _ in Task { await vm.refresh() } }
        .onChange(of: feedVM.selectedTimeFilter) { _, _ in Task { await vm.refresh() } }
        .onChange(of: feedVM.selectedMarket)     { _, _ in Task { await vm.refresh() } }
    }

    // MARK: - Top Nav Bar

    private var topNavBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live Market")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    HStack(spacing: 5) {
                        AnimatedLiveDot()
                        Text(vm.tablesDroppedLastHour > 0
                             ? "\(vm.tablesDroppedLastHour) tables dropped this hour"
                             : "Scanning now…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                Spacer()
                alertBellButton
            }
            .padding(.horizontal, AppTheme.spacingLG)

            // Market selector pills
            HStack(spacing: AppTheme.spacingSM) {
                marketPill("New York", marketId: "nyc")
                marketPill("Miami",    marketId: "miami")
            }
            .padding(.horizontal, AppTheme.spacingLG)
        }
        .padding(.top, AppTheme.spacingSM)
        .padding(.bottom, AppTheme.spacingSM)
        .background(AppTheme.background)
    }

    private var alertBellButton: some View {
        Button { onOpenAlerts?() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: alertBadgeCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(alertBadgeCount > 0 ? AppTheme.accentOrange : AppTheme.textSecondary)
                if alertBadgeCount > 0 {
                    Text("\(min(alertBadgeCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(AppTheme.accentRed))
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private func marketPill(_ label: String, marketId: String) -> some View {
        let isSelected = vm.selectedMarket == marketId
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                feedVM.selectedMarket = marketId
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.vertical, AppTheme.spacingSM)
                .background(isSelected ? AppTheme.accentOrange : AppTheme.pillUnselected)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Filter Bar (sticky below nav)

    private var filterBar: some View {
        VStack(spacing: 0) {
            // Date strip — shows availability dots per date
            DateStripView(
                dateOptions: vm.dateOptions,
                selectedDates: $feedVM.selectedDates,
                calendarCounts: vm.calendarCounts
            )

            // Time + party size pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.spacingSM) {
                    ForEach(timeFilters, id: \.key) { filter in
                        timeFilterPill(filter)
                    }

                    Rectangle()
                        .fill(AppTheme.border)
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)

                    ForEach([2, 4, 6], id: \.self) { size in
                        partySizePill(size)
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
            }
            .padding(.vertical, 6)

            // Active filter chips — appear when any filter is set
            if hasActiveFilters {
                activeFilterChipBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 0.5)
        }
        .background(AppTheme.background)
        .animation(.easeInOut(duration: 0.2), value: hasActiveFilters)
    }

    private func timeFilterPill(_ filter: (key: String, label: String)) -> some View {
        let isSelected = vm.selectedTimeFilter == filter.key
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                feedVM.selectedTimeFilter = filter.key
            }
        } label: {
            Text(filter.label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.accent : AppTheme.pillUnselected)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func partySizePill(_ size: Int) -> some View {
        let isSelected = vm.selectedPartySizes.contains(size)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if isSelected {
                    feedVM.selectedPartySizes.remove(size)
                } else {
                    feedVM.selectedPartySizes.insert(size)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: size > 2 ? "person.2" : "person")
                    .font(.system(size: 10, weight: .medium))
                Text("\(size)")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.accent : AppTheme.pillUnselected)
            .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var activeTimeFilterLabel: String {
        timeFilters.first(where: { $0.key == vm.selectedTimeFilter })?.label ?? vm.selectedTimeFilter
    }

    /// Build a flat Identifiable array of chips — avoids ForEach(_:id:) overload ambiguity
    private var activeChips: [FilterChipData] {
        var chips: [FilterChipData] = []
        for dateStr in Array(vm.selectedDates).sorted() {
            let d = dateStr
            chips.append(FilterChipData(id: "date_\(d)", label: dateChipLabel(d), onRemove: {
                withAnimation { _ = self.feedVM.selectedDates.remove(d) }
            }))
        }
        if vm.selectedTimeFilter != "all" {
            let key = vm.selectedTimeFilter
            let label = activeTimeFilterLabel
            chips.append(FilterChipData(id: "time_\(key)", label: label, onRemove: {
                withAnimation { self.feedVM.selectedTimeFilter = "all" }
            }))
        }
        for size in Array(vm.selectedPartySizes).sorted() {
            let s = size
            chips.append(FilterChipData(id: "size_\(s)", label: "\(s) guests", onRemove: {
                withAnimation { _ = self.feedVM.selectedPartySizes.remove(s) }
            }))
        }
        return chips
    }

    private var activeFilterChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacingSM) {
                Text("Filters:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                // Identifiable data → ForEach(_:content:) has no overload ambiguity
                ForEach(activeChips) { chip in
                    ActiveChipView(label: chip.label, onRemove: chip.onRemove)
                }
                Button {
                    withAnimation {
                        feedVM.selectedDates = []
                        feedVM.selectedTimeFilter = "all"
                        feedVM.selectedPartySizes = []
                    }
                } label: {
                    Text("Clear all")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.accentRed)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.vertical, 6)
        }
    }

    private func dateChipLabel(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: dateStr) else { return dateStr }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        let out = DateFormatter()
        out.dateFormat = "EEE d"
        return out.string(from: d)
    }

    // MARK: - Main feed content

    private var mainFeedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let topOpps = vm.carouselDrops
                if !topOpps.isEmpty {
                    FeedTopOpportunitiesSection(drops: Array(topOpps.prefix(6)))
                        .padding(.bottom, AppTheme.spacingXL)
                }

                let hotDrops = vm.hottestDrops
                if !hotDrops.isEmpty {
                    FeedHotRightNowSection(
                        drops: Array(hotDrops.prefix(8)),
                        isWatched: { savedVM.isWatched($0) },
                        onToggleWatch: { savedVM.toggleWatch($0) }
                    )
                    .padding(.bottom, AppTheme.spacingXL)
                }

                let justDropped = Array(vm.justDropped.prefix(10))
                if !justDropped.isEmpty {
                    FeedJustDroppedSection(drops: justDropped)
                        .padding(.bottom, AppTheme.spacingXL)
                } else if vm.drops.isEmpty {
                    contextualEmptyView
                        .padding(.bottom, AppTheme.spacingXL)
                }

                if !vm.likelyToOpen.isEmpty {
                    FeedLikelyToOpenSection(
                        venues: vm.likelyToOpen,
                        isPremium: premium.isPremium,
                        onPurchase: { Task { try? await premium.purchase() } },
                        onOpenAlerts: onOpenAlerts
                    )
                    .padding(.bottom, AppTheme.spacingXL)
                }

                FeedWatchlistSection(
                    watchedNames: Array(savedVM.watchedVenues).sorted(),
                    onOpenAlerts: onOpenAlerts
                )

                Spacer(minLength: 120)
            }
            .animation(
                .spring(response: 0.4, dampingFraction: 0.85),
                value: vm.drops.count
            )
        }
        .background(AppTheme.background)
    }

    // MARK: - Contextual empty state

    private var contextualEmptyView: some View {
        VStack(spacing: AppTheme.spacingXL) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 80, height: 80)
                Image(systemName: contextualIcon)
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.textTertiary)
            }
            VStack(spacing: AppTheme.spacingSM) {
                Text(contextualTitle)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(contextualMessage)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            if hasActiveFilters {
                Button {
                    withAnimation {
                        feedVM.selectedDates = []
                        feedVM.selectedTimeFilter = "all"
                        feedVM.selectedPartySizes = []
                    }
                } label: {
                    Text("Clear filters")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.spacingXL)
                        .padding(.vertical, 12)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }

    private var contextualIcon: String {
        if !vm.selectedDates.isEmpty        { return "calendar.badge.exclamationmark" }
        if vm.selectedTimeFilter != "all"   { return "clock.badge.exclamationmark" }
        if !vm.selectedPartySizes.isEmpty   { return "person.2.slash" }
        return "fork.knife"
    }

    private var contextualTitle: String {
        hasActiveFilters ? "No tables match" : "No drops yet"
    }

    private var contextualMessage: String {
        if !vm.selectedDates.isEmpty {
            let label = vm.selectedDates.sorted().first.map { dateChipLabel($0) } ?? "that date"
            return "No tables for \(label). Try another date or remove the filter."
        }
        if vm.selectedTimeFilter != "all" {
            let label = timeFilters.first(where: { $0.key == vm.selectedTimeFilter })?.label ?? "that time"
            return "No tables for \(label). Try a different time window."
        }
        if !vm.selectedPartySizes.isEmpty {
            return "No tables for that party size right now. Try a different size."
        }
        return "We're scanning 698+ venues. New tables appear here the moment they drop."
    }

    // MARK: - Inline error view

    private func inlineErrorView(_ message: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.accentRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection issue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Button { Task { await vm.refresh() } } label: {
                    Text("Retry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(AppTheme.spacingLG)
            .background(AppTheme.accentRed.opacity(0.10))
            .overlay(
                Rectangle()
                    .fill(AppTheme.accentRed)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity),
                alignment: .leading
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}

// MARK: - TOP OPPORTUNITIES (hero carousel)

private struct FeedTopOpportunitiesSection: View {
    let drops: [Drop]

    private var cardWidth: CGFloat { UIScreen.main.bounds.width * 0.82 }
    private let cardHeight: CGFloat = 284

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            feedSectionHeader("TOP OPPORTUNITIES", count: drops.count,
                              icon: "star.fill", iconColor: AppTheme.premiumGold)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(drops.enumerated()), id: \.element.id) { idx, drop in
                        TopOpportunityHeroCard(drop: drop, rank: idx + 1)
                            .frame(width: cardWidth, height: cardHeight)
                            .staggeredAppear(index: idx, delayPerItem: 0.05)
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct TopOpportunityHeroCard: View {
    let drop: Drop
    let rank: Int

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var availabilityText: String {
        if let days = drop.daysWithDrops { return "Open \(days) of last 14 days" }
        if let rate = drop.availabilityRate14d {
            let pct = Int(rate * 100)
            return pct < 20 ? "Very rare — \(pct)% avail." : "\(pct)% availability"
        }
        return ""
    }

    private var detailLine: String {
        var parts: [String] = []
        if let ds = drop.dateStr {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: ds) {
                if Calendar.current.isDateInToday(d)     { parts.append("Tonight") }
                else if Calendar.current.isDateInTomorrow(d) { parts.append("Tomorrow") }
                else { let o = DateFormatter(); o.dateFormat = "EEE MMM d"; parts.append(o.string(from: d)) }
            }
        }
        if let t = drop.slots.first?.time, !t.isEmpty { parts.append(formatTime(t)) }
        if let nb = drop.neighborhood, !nb.isEmpty    { parts.append(nb) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Photo
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: heroFallback
                        }
                    }
                } else { heroFallback }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            // Gradient
            LinearGradient(
                stops: [
                    .init(color: .clear,               location: 0),
                    .init(color: .black.opacity(0.25), location: 0.42),
                    .init(color: .black.opacity(0.88), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Top badges
            VStack {
                HStack(alignment: .top) {
                    Text("#\(rank) TOP PICK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, AppTheme.spacingSM)
                        .padding(.vertical, 5)
                        .background(AppTheme.premiumGold)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Spacer()
                    ScarcityBadge(tier: drop.scarcityTier)
                }
                .padding(12)
                Spacer()
            }

            // Bottom content
            VStack(alignment: .leading, spacing: 6) {
                if !availabilityText.isEmpty {
                    HStack(spacing: 4) {
                        TrendIndicator(trendPct: drop.trendPct)
                        Text(availabilityText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                Text(drop.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(1)
                }
                if let url = resyUrl {
                    Button { UIApplication.shared.open(url) } label: {
                        HStack {
                            Text("Reserve on Resy")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, AppTheme.spacingLG)
                        .padding(.vertical, 12)
                        .background(AppTheme.premiumGold)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 4)
    }

    private var heroFallback: some View {
        LinearGradient(
            colors: [Color(red: 0.14, green: 0.12, blue: 0.20),
                     Color(red: 0.08, green: 0.06, blue: 0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func formatTime(_ t: String) -> String {
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return t }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
    }
}

// MARK: - HOT RIGHT NOW (2-column grid)

private struct FeedHotRightNowSection: View {
    let drops: [Drop]
    let isWatched: (String) -> Bool
    let onToggleWatch: (String) -> Void

    // Pre-compute pairs to avoid compiler type-check timeout in body
    private var pairs: [(Drop, Drop?)] {
        stride(from: 0, to: drops.count, by: 2).map { i in
            (drops[i], i + 1 < drops.count ? drops[i + 1] : nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            feedSectionHeader("HOT RIGHT NOW", count: drops.count,
                              icon: "flame.fill", iconColor: AppTheme.accentOrange)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { pairIdx, pair in
                    hotRow(pairIdx: pairIdx, pair: pair)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
        }
    }

    @ViewBuilder
    private func hotRow(pairIdx: Int, pair: (Drop, Drop?)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            HotRightNowGridCard(
                drop: pair.0,
                isWatched: isWatched(pair.0.name),
                onToggleWatch: { onToggleWatch(pair.0.name) }
            )
            .staggeredAppear(index: pairIdx * 2, delayPerItem: 0.03)

            if let second = pair.1 {
                HotRightNowGridCard(
                    drop: second,
                    isWatched: isWatched(second.name),
                    onToggleWatch: { onToggleWatch(second.name) }
                )
                .staggeredAppear(index: pairIdx * 2 + 1, delayPerItem: 0.03)
            } else {
                Spacer().frame(maxWidth: .infinity)
            }
        }
    }
}

private struct HotRightNowGridCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: () -> Void

    private var freshnessColor: Color {
        AppTheme.trendColor(for: drop.trendPct)
    }

    private var heatBadge: String {
        FeedMetricLabels.heatLabel(trendPct: drop.trendPct)
    }

    private var freshnessLabel: String {
        FeedMetricLabels.freshnessText(secondsSinceDetected: drop.secondsSinceDetected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                            else { AppTheme.surfaceElevated }
                        }
                    } else { AppTheme.surfaceElevated }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .clipped()

                Text(heatBadge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(freshnessColor.opacity(0.88))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(7)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(drop.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(freshnessColor)
                        .frame(width: 5, height: 5)
                    Text(freshnessLabel)
                        .font(.system(size: 10))
                        .foregroundColor(freshnessColor)
                        .lineLimit(1)
                }

                if let nb = drop.neighborhood, !nb.isEmpty {
                    Text(nb)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }

                Button { onToggleWatch() } label: {
                    Text(isWatched ? "Watching ✓" : "Set Alert")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isWatched ? AppTheme.accentOrange : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isWatched ? AppTheme.accentOrange.opacity(0.14) : AppTheme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(isWatched ? AppTheme.accentOrange.opacity(0.4) : Color.clear, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.top, 2)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - JUST DROPPED (vertical list, thumbnails + badges)

private struct FeedJustDroppedSection: View {
    let drops: [Drop]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                feedSectionHeader("JUST DROPPED", count: drops.count, icon: nil, iconColor: .clear)
                AnimatedLiveDot()
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.bottom, 12)

            VStack(spacing: AppTheme.spacingSM) {
                ForEach(Array(drops.enumerated()), id: \.element.id) { idx, drop in
                    JustDroppedRowView(drop: drop)
                        .staggeredAppear(index: idx, delayPerItem: 0.03)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
        }
    }
}

private struct JustDroppedRowView: View {
    let drop: Drop

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var detailLine: String {
        var parts: [String] = []
        if let ds = drop.dateStr {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: ds) {
                if Calendar.current.isDateInToday(d)         { parts.append("Tonight") }
                else if Calendar.current.isDateInTomorrow(d) { parts.append("Tomorrow") }
                else { let o = DateFormatter(); o.dateFormat = "EEE"; parts.append(o.string(from: d)) }
            }
        }
        if let t = drop.slots.first?.time, !t.isEmpty { parts.append(formatTime(t)) }
        if let first = drop.partySizesAvailable.sorted().first {
            parts.append(first > 8 ? "8+ Guests" : "\(first) Guests")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { AppTheme.surfaceElevated }
                    }
                } else { AppTheme.surfaceElevated }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    if drop.secondsSinceDetected < 600 {
                        Text("JUST NOW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppTheme.accentRed)
                            .clipShape(Capsule())
                    }
                }
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    ScarcityBadge(tier: drop.scarcityTier)
                    TrendIndicator(trendPct: drop.trendPct)
                    if let nb = drop.neighborhood, !nb.isEmpty {
                        Text(nb)
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            if let url = resyUrl {
                Button { UIApplication.shared.open(url) } label: {
                    Text("Book")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.premiumGold)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }

    private func formatTime(_ t: String) -> String {
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return t }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
    }
}

// MARK: - LIKELY TO OPEN TODAY (predictive, premium gated)

private struct FeedLikelyToOpenSection: View {
    let venues: [LikelyToOpenVenue]
    let isPremium: Bool
    let onPurchase: () -> Void
    var onOpenAlerts: (() -> Void)?

    private let freeLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            feedSectionHeader("LIKELY TO OPEN TODAY", count: venues.count,
                              icon: "chart.line.uptrend.xyaxis", iconColor: AppTheme.accent)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, 12)

            VStack(spacing: AppTheme.spacingSM) {
                let visibleVenues = isPremium ? venues : Array(venues.prefix(freeLimit))
                ForEach(Array(visibleVenues.enumerated()), id: \.element.id) { idx, venue in
                    LikelyToOpenRow(venue: venue, onNotify: onOpenAlerts)
                        .staggeredAppear(index: idx, delayPerItem: 0.04)
                }

                if !isPremium && venues.count > freeLimit {
                    premiumGateRow(hiddenCount: venues.count - freeLimit)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
        }
    }

    private func premiumGateRow(hiddenCount: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: AppTheme.spacingSM) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.premiumGold)
                Text("+\(hiddenCount) more predicted venues")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            Text("Upgrade to see all predicted drops and get ahead of everyone else.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button { onPurchase() } label: {
                Text("Unlock Premium")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.premiumGold)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(AppTheme.spacingLG)
        .background(AppTheme.premiumGoldBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.premiumGold.opacity(0.3), lineWidth: 0.5)
        )
    }
}

private struct LikelyToOpenRow: View {
    let venue: LikelyToOpenVenue
    var onNotify: (() -> Void)?

    private var confidenceInt: Int {
        let rarity = min(max(venue.rarityScore ?? 0, 0), 1)
        let scarcity = 1 - min(max(venue.availabilityRate14d ?? 1, 0), 1)
        return Int(((rarity * 0.65) + (scarcity * 0.35)) * 100)
    }

    private var daysText: String {
        if let days = venue.daysWithDrops { return "Open \(days)/14 days" }
        if let rate = venue.availabilityRate14d { return "\(Int(rate * 100))% avail." }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            // Venue icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.surfaceElevated)
                    .frame(width: 52, height: 52)
                Image(systemName: "fork.knife")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: AppTheme.spacingSM) {
                    if let nb = venue.neighborhood, !nb.isEmpty {
                        Text(nb)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    if !daysText.isEmpty {
                        Text(daysText)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }

                if let predicted = venue.predictedDropTime, !predicted.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text("Expected around \(predicted)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppTheme.accent)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(confidenceInt)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.liveDot)
                    .padding(.horizontal, AppTheme.spacingSM)
                    .padding(.vertical, 4)
                    .background(AppTheme.liveDot.opacity(0.15))
                    .clipShape(Capsule())

                Button { onNotify?() } label: {
                    Text("Notify Me")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(12)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - YOUR WATCHLIST

private struct FeedWatchlistSection: View {
    let watchedNames: [String]
    var onOpenAlerts: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            feedSectionHeader("YOUR WATCHLIST", count: watchedNames.count,
                              icon: "bookmark.fill", iconColor: AppTheme.accentOrange)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.bottom, 12)

            if watchedNames.isEmpty {
                Text("Add venues from the Alerts tab to track when they drop.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(AppTheme.spacingLG)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, AppTheme.spacingLG)
            } else {
                VStack(spacing: AppTheme.spacingSM) {
                    ForEach(watchedNames, id: \.self) { name in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Watching next 14 days")
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            Spacer()
                            Button { onOpenAlerts?() } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 17))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
            }
        }
    }
}

// MARK: - Reusable badge components (module-level for use in other views)

/// Color-coded scarcity pill: Rare / Scarce / Available
struct ScarcityBadge: View {
    let tier: Drop.ScarcityTier

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityLabel(label)
    }

    private var color: Color { AppTheme.scarcityColor(for: tier) }

    private var label: String {
        switch tier {
        case .rare:      return "Rare"
        case .uncommon:  return "Scarce"
        case .available: return "Available"
        case .unknown:   return "Limited"
        }
    }
}

/// Trend arrow + percentage (only shown when significant)
struct TrendIndicator: View {
    let trendPct: Double?

    var body: some View {
        if let pct = trendPct, abs(pct) > 5 {
            HStack(spacing: 2) {
                Image(systemName: pct > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("\(Int(abs(pct)))%")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(pct > 0 ? AppTheme.trendUp : AppTheme.trendDown)
            .accessibilityLabel(pct > 0 ? "Trending up \(Int(abs(pct)))%" : "Trending down \(Int(abs(pct)))%")
        }
    }
}

// MARK: - Section header helper

private func feedSectionHeader(_ title: String, count: Int, icon: String?, iconColor: Color) -> some View {
    HStack(spacing: 6) {
        if let icon {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(iconColor)
        }
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(AppTheme.textPrimary)
            .tracking(0.4)
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(AppTheme.pillUnselected)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Filter chip data model (Identifiable → ForEach(_:content:) is unambiguous)

struct FilterChipData: Identifiable {
    let id: String
    let label: String
    let onRemove: () -> Void
}

// MARK: - Active filter chip view

struct ActiveChipView: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(AppTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.accent.opacity(0.18))
        .overlay(Capsule().stroke(AppTheme.accent.opacity(0.4), lineWidth: 0.5))
        .clipShape(Capsule())
    }
}

// MARK: - Legacy public view (kept for external use)

struct LatestDropRowView: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

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
                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                            else { AppTheme.surface }
                        }
                    } else { AppTheme.surface }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    if let sl = drop.scarcityLabel {
                        Text(sl)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                Spacer(minLength: 4)
                Button { onToggleWatch(drop.name) } label: {
                    Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundColor(isWatched ? AppTheme.accentOrange : AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
