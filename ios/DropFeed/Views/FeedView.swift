import SwiftUI

private enum SignalStreamFilter: CaseIterable, Hashable {
    case all, drops, events

    var label: String {
        switch self {
        case .all: return "ALL"
        case .drops: return "DROPS"
        case .events: return "EVENTS"
        }
    }
}

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    var onOpenSearch: (() -> Void)? = nil
    var onOpenExplore: (() -> Void)? = nil

    private var vm: FeedViewModel { feedVM }

    private let palette: FeedPalette = .liveFeedLight

    private let partySizeOptions = [2, 3, 4, 5, 6]

    @State private var showFilterSheet = false
    @State private var signalStreamFilter: SignalStreamFilter = .all
    @State private var marketLeaderCarouselIndex: Int = 0

    private var viewStateId: String {
        if vm.isLoading && vm.drops.isEmpty { return "loading" }
        if vm.error != nil { return "error" }
        if vm.drops.isEmpty { return "empty" }
        return "content"
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if vm.isLoading && vm.drops.isEmpty {
                    FeedSkeletonView()
                } else if let err = vm.error {
                    errorView(err)
                } else if vm.drops.isEmpty {
                    emptyView
                } else {
                    referenceFeedScroll
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewStateId)
        }
        .background(SnagDesignSystem.darkCanvas)
        .refreshable { await vm.refresh() }
        .sheet(isPresented: $showFilterSheet) {
            DateTimeFilterSheet(vm: vm)
        }
        .task {
            await vm.refresh()
            vm.startPolling()
        }
    }

    // MARK: - Feed content

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {

                // ── Live scan bar (slim, always visible)
                liveScanBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // ── New drops banner (conditional)
                if vm.newDropsCount > 0 {
                    newDropsBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // ── Hero card — #1 ranked opportunity
                if let hero = vm.heroCard {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("🔥 TOP OPPORTUNITY", subtitle: "Most wanted table right now")
                        HeroCardView(
                            drop: hero,
                            isWatched: savedVM.isWatched(hero.name),
                            onToggleWatch: { savedVM.toggleWatch($0) }
                        )
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }

                // ── Rare Finds — drops with high rarity score
                let rares = vm.rareDrops.prefix(10)
                if !rares.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("💎 RARE FINDS", subtitle: "Open <15% of days — act fast")
                            .padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(rares), id: \.id) { drop in
                                    RareDropCard(drop: drop,
                                                 isWatched: savedVM.isWatched(drop.name),
                                                 onToggleWatch: { savedVM.toggleWatch($0) })
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 24)
                }

                // ── Trending — high trendPct drops
                let trending = vm.trendingDrops.prefix(8)
                if !trending.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("📈 TRENDING", subtitle: "Availability spiking vs last 14 days")
                            .padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(trending), id: \.id) { drop in
                                    TrendingDropCard(drop: drop,
                                                     isWatched: savedVM.isWatched(drop.name),
                                                     onToggleWatch: { savedVM.toggleWatch($0) })
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 24)
                }

                // ── All drops (rich rows with date + metrics)
                if !vm.feedCards.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionLabel("⚡ LATEST DROPS", subtitle: "\(vm.feedCards.count) tables spotted across 14 days")
                            .padding(.horizontal, 16)
                        ForEach(Array(vm.feedCards.enumerated()), id: \.element.id) { idx, drop in
                            LatestDropRowView(
                                drop: drop,
                                isWatched: savedVM.isWatched(drop.name),
                                onToggleWatch: { savedVM.toggleWatch($0) }
                            )
                            .padding(.horizontal, 16)
                            .staggeredAppear(index: idx, delayPerItem: 0.025)
                        }
                    }
                    .padding(.bottom, 24)
                }

                // ── Likely to Open (predictive)
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
            }
        }
        .background(AppTheme.background)
    }

    // MARK: - Reference layout (TOP DROPS + LIVE NOW mock)

    /// Prefer backend `hot_right_now`; otherwise the full ranked live board (not trimmed to “below carousel”).
    private var homeLiveDropsPool: [Drop] {
        if let hot = vm.hotRightNow, !hot.isEmpty {
            return hot
        }
        return vm.drops
    }

    /// Ranked by score and freshness, then rotated with `liveListShuffleToken` so the list shifts between polls.
    private var homeLiveDropsOrdered: [Drop] {
        let pool = homeLiveDropsPool
        let sorted = pool.sorted { a, b in
            let sa = a.snagScore ?? 0
            let sb = b.snagScore ?? 0
            if sa != sb { return sa > sb }
            if a.secondsSinceDetected != b.secondsSinceDetected {
                return a.secondsSinceDetected < b.secondsSinceDetected
            }
            return a.id < b.id
        }
        guard sorted.count > 1 else { return sorted }
        let n = sorted.count
        let r = Int(vm.liveListShuffleToken % UInt64(n))
        return Array(sorted[r...] + sorted[..<r])
    }

    /// Stream list after ALL / DROPS / EVENTS filter (client-side).
    private var signalStreamDisplayedDrops: [Drop] {
        let base = homeLiveDropsOrdered
        switch signalStreamFilter {
        case .all:
            return base
        case .drops:
            return base.filter { feedDropIsBookable($0) }
        case .events:
            return base.filter {
                $0.feedHot == true
                    || $0.brandNewDrop == true
                    || $0.feedsRareCarousel == true
                    || ($0.snagScore ?? 0) >= 85
                    || ($0.trendPct ?? 0) > 25
            }
        }
    }

    private var referenceFeedScroll: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    marketLeaderHeroSection
                        .padding(.top, 12)
                    mockLiveNowSection
                        .padding(.top, 28)
                    mockJustMissedSection
                    mockPredictWillOpenSection
                    Color.clear.frame(height: vm.newDropsCount > 0 ? 96 : 28)
                }
            }
            VStack(spacing: 8) {
                if vm.isRefreshing, !vm.drops.isEmpty {
                    feedSyncingPill
                }
                if vm.newDropsCount > 0 {
                    floatingNewDropsPill
                }
            }
            .padding(.bottom, 6)
        }
        .background(SnagDesignSystem.darkCanvas)
    }

    /// Up to six featured venues for the market-leader carousel (falls back to #1 drop).
    private var marketLeaderCarouselDrops: [Drop] {
        let top = Array(vm.topDrops.prefix(6))
        if !top.isEmpty { return top }
        if let h = vm.heroCard { return [h] }
        return []
    }

    private var marketLeaderFocusedDrop: Drop? {
        let arr = marketLeaderCarouselDrops
        guard !arr.isEmpty else { return nil }
        let i = min(max(0, marketLeaderCarouselIndex), arr.count - 1)
        return arr[i]
    }

    private var marketLeaderHeroSection: some View {
        Group {
            if let focused = marketLeaderFocusedDrop {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(marketLeaderLeftCaption(focused))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(SnagDesignSystem.darkTextMuted)
                            .tracking(0.85)
                        Spacer()
                        Text(marketLeaderRightCaption(focused))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(SnagDesignSystem.darkTextMuted)
                            .tracking(0.85)
                    }
                    .padding(.horizontal, 18)

                    TabView(selection: $marketLeaderCarouselIndex) {
                        ForEach(Array(marketLeaderCarouselDrops.enumerated()), id: \.element.id) { idx, drop in
                            MarketLeaderHeroCard(drop: drop)
                                .tag(idx)
                        }
                    }
                    .frame(height: 232)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .padding(.horizontal, 18)
                    .onChange(of: marketLeaderCarouselDrops.count) { _, newCount in
                        if marketLeaderCarouselIndex >= newCount {
                            marketLeaderCarouselIndex = max(0, newCount - 1)
                        }
                    }

                    if marketLeaderCarouselDrops.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(Array(marketLeaderCarouselDrops.enumerated()), id: \.element.id) { idx, _ in
                                Circle()
                                    .fill(idx == marketLeaderCarouselIndex ? Color.white : Color.white.opacity(0.28))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private var feedSyncingPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 6, height: 6)
            Text("SYNCING…")
                .font(.system(size: 12, weight: .heavy))
                .foregroundColor(.white)
                .tracking(0.6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(SnagDesignSystem.salmonAccent)
        .clipShape(Capsule())
        .shadow(color: SnagDesignSystem.salmonAccent.opacity(0.45), radius: 12, y: 3)
    }

    private var mockLiveNowSection: some View {
        Group {
            if homeLiveDropsPool.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Signal stream")
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundColor(.white)

                        HStack(alignment: .center, spacing: 10) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(SignalStreamFilter.allCases, id: \.self) { mode in
                                        Button {
                                            signalStreamFilter = mode
                                        } label: {
                                            Text(mode.label)
                                                .font(.system(size: 10, weight: .heavy))
                                                .foregroundColor(signalStreamFilter == mode ? .white : SnagDesignSystem.darkTextMuted)
                                                .tracking(0.5)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 8)
                                                .background(signalStreamFilter == mode ? Color(white: 0.26) : Color(white: 0.12))
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .stroke(Color.white.opacity(signalStreamFilter == mode ? 0 : 0.12), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach([2, 4], id: \.self) { size in
                                    Button {
                                        mockFeedPartySizeTap(size)
                                    } label: {
                                        Text("\(size)")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(vm.selectedPartySizes.contains(size) ? .white : SnagDesignSystem.darkTextMuted)
                                            .frame(width: 34, height: 30)
                                            .background(vm.selectedPartySizes.contains(size) ? Color(white: 0.22) : Color(white: 0.12))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 12) {
                        if signalStreamDisplayedDrops.isEmpty {
                            signalStreamEmptyFilterPlaceholder
                        } else {
                            ForEach(signalStreamDisplayedDrops, id: \.id) { drop in
                                MockLiveNowRow(drop: drop, preferredParty: mockPreferredParty(for: drop))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                    .animation(.easeInOut(duration: 0.4), value: vm.lastRefreshed)
                    .animation(.easeInOut(duration: 0.45), value: vm.liveListShuffleToken)
                    .animation(.easeInOut(duration: 0.25), value: signalStreamFilter)
                }
            }
        }
    }

    private var signalStreamEmptyFilterPlaceholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(SnagDesignSystem.darkTextMuted.opacity(0.5))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text("INCOMING SIGNAL")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(SnagDesignSystem.darkTextMuted)
                    .tracking(0.6)
                Text("Nothing in this channel right now — try ALL or DROPS.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SnagDesignSystem.darkTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(SnagDesignSystem.darkTextMuted)
        }
        .padding(14)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func marketLeaderLeftCaption(_ drop: Drop) -> String {
        if let s = drop.crownBadgeLabel, !s.isEmpty { return s.uppercased() }
        return "MARKET LEADER"
    }

    private func marketLeaderRightCaption(_ drop: Drop) -> String {
        if let s = drop.topOpportunityDemandLabel, !s.isEmpty { return s.uppercased() }
        if let sc = drop.snagScore { return "\(sc)% DEMAND" }
        if let rp = drop.rarityPoints { return "\(rp)% DEMAND" }
        return "LIVE DEMAND"
    }

    private func mockPreferredParty(for drop: Drop) -> Int {
        let avail = Set(drop.partySizesAvailable)
        for p in vm.selectedPartySizes.sorted() where avail.contains(p) {
            return p
        }
        return drop.partySizesAvailable.sorted().first ?? 2
    }

    private func mockFeedPartySizeTap(_ size: Int) {
        if vm.selectedPartySizes == [size] {
            vm.selectedPartySizes.removeAll()
        } else {
            vm.selectedPartySizes = [size]
        }
        vm.applyFiltersAndRefresh()
    }

    private var mockJustMissedSection: some View {
        let items = vm.justMissed
        return Group {
            if items.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("⏱ JUST MISSED")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                            .tracking(0.6)
                        Spacer()
                        Text("GONE")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(SnagDesignSystem.darkTextMuted)
                            .tracking(0.8)
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(items) { venue in
                                MockJustMissedCard(venue: venue)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 28)
            }
        }
    }

    private var mockPredictWillOpenSection: some View {
        Group {
            if vm.likelyToOpen.isEmpty {
                EmptyView()
            } else {
                FeedPredictWillOpenSection(
                    venues: vm.likelyToOpen,
                    premium: premium,
                    onNotify: { savedVM.toggleWatch($0) },
                    isWatched: { savedVM.isWatched($0) }
                )
                .padding(.top, 28)
            }
        }
    }

    private var floatingNewDropsPill: some View {
        Button {
            vm.acknowledgeNewDrops()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red.opacity(0.95))
                    .frame(width: 6, height: 6)
                Text("\(vm.newDropsCount) NEW DROPS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .tracking(0.5)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(SnagDesignSystem.salmonAccent)
            .clipShape(Capsule())
            .shadow(color: SnagDesignSystem.salmonAccent.opacity(0.5), radius: 14, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Snag layout: header + sections

    private var snagCrownDrops: [Drop] {
        Array(vm.topDrops.prefix(6))
    }

    private var snagTopOpportunityDrops: [Drop] {
        let crownIds = Set(snagCrownDrops.map(\.id))
        let pool = vm.hotRightNow ?? vm.justDropped
        let filtered = pool.filter { !crownIds.contains($0.id) }
        if !filtered.isEmpty {
            return Array(filtered.prefix(14))
        }
        return Array(vm.justDropped.filter { !crownIds.contains($0.id) }.prefix(14))
    }

    private var crownJewelsSection: some View {
        let top = snagCrownDrops
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TOP DROPS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textSection)
                    .tracking(1.0)
                Spacer()
                HStack(spacing: 6) {
                    Text("●")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SnagDesignSystem.coral)
                    Text("BOOK NOW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SnagDesignSystem.coral)
                        .tracking(0.6)
                }
            }
            .padding(.horizontal, 16)

            if top.isEmpty {
                Text("No tables match filters — open Search to adjust.")
                    .font(.system(size: 14))
                    .foregroundColor(SnagDesignSystem.textMuted)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(top, id: \.id) { drop in
                            CrownJewelCard(drop: drop)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var topOpportunitiesSnagSection: some View {
        let rows = snagTopOpportunityDrops
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MORE OPEN NOW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textSection)
                    .tracking(1.0)
                Text("Same live feed, ranked by desirability — grab these before they’re gone.")
                    .font(.system(size: 11))
                    .foregroundColor(SnagDesignSystem.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if rows.isEmpty {
                Text("No additional opportunities right now.")
                    .font(.system(size: 14))
                    .foregroundColor(SnagDesignSystem.textMuted)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, drop in
                        TopOpportunitySnagRow(drop: drop)
                        if idx < rows.count - 1 {
                            Divider()
                                .background(Color.black.opacity(0.06))
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    private var filterPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterPill(
                    title: partyGuestsLabel,
                    icon: "person.2.fill",
                    selected: !vm.selectedPartySizes.isEmpty
                ) {
                    cyclePartyFilter()
                }
                filterPill(
                    title: "TONIGHT",
                    icon: "calendar",
                    selected: vm.selectedDates.contains(vm.todayDateStr)
                ) {
                    if vm.selectedDates.contains(vm.todayDateStr) {
                        vm.selectedDates.remove(vm.todayDateStr)
                    } else {
                        vm.selectedDates = [vm.todayDateStr]
                    }
                    vm.applyFiltersAndRefresh()
                }
                filterPill(
                    title: "7–9PM",
                    icon: "clock",
                    selected: vm.selectedTimeFilter == "evening79"
                ) {
                    vm.selectedTimeFilter = vm.selectedTimeFilter == "evening79" ? "all" : "evening79"
                    vm.applyFiltersAndRefresh()
                }
                filterPill(
                    title: "NYC",
                    icon: "mappin.and.ellipse",
                    selected: false
                ) {
                    onOpenExplore?()
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var partyGuestsLabel: String {
        if vm.selectedPartySizes.isEmpty { return "ANY GUESTS" }
        let n = vm.selectedPartySizes.sorted().first ?? 2
        return "\(n) GUESTS"
    }

    private func cyclePartyFilter() {
        let order: [Int?] = [nil, 2, 3, 4, 5, 6]
        let current: Int? = vm.selectedPartySizes.count == 1 ? vm.selectedPartySizes.first : nil
        let idx = order.firstIndex { $0 == current } ?? 0
        let next = order[(idx + 1) % order.count]
        if let n = next {
            vm.selectedPartySizes = [n]
        } else {
            vm.selectedPartySizes = []
        }
        vm.applyFiltersAndRefresh()
    }

    private func filterPill(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(selected ? palette.accentRed : palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(selected ? palette.accentRed.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? palette.accentRed.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var bestRightNowSection: some View {
        let top = Array(vm.topDrops.prefix(6))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BEST RIGHT NOW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.textTertiary)
                    .tracking(0.8)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(palette.accentRed)
                        .frame(width: 5, height: 5)
                    Text("CRITICAL AVAILABILITY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(palette.accentRed)
                        .tracking(0.4)
                }
            }
            .padding(.horizontal, 16)

            if top.isEmpty {
                Text("No tables match filters — try adjusting chips above.")
                    .font(.system(size: 14))
                    .foregroundColor(palette.textTertiary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(top, id: \.id) { drop in
                            CrownJewelCard(drop: drop)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var liveStreamSection: some View {
        let visible: [Drop] = vm.tickerDrops.isEmpty
            ? Array(vm.justDropped.prefix(12))
            : vm.tickerDrops
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LIVE STREAM")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.textTertiary)
                    .tracking(0.8)
                Spacer()
                Text(vm.liveStreamActivityLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.textTertiary)
                    .tracking(0.3)
            }
            .padding(.horizontal, 16)

            if visible.isEmpty {
                Text("Scanning for live drops…")
                    .font(.system(size: 14))
                    .foregroundColor(palette.textTertiary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, drop in
                        LiveStreamRow(drop: drop)
                            .id(drop.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
                            .animation(.easeInOut(duration: 0.45), value: drop.id)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Lightweight UI helpers (light feed)

    @ViewBuilder
    private var emptySectionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No drops right now.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.textSecondary)
            Text("We scan continuously and update this feed live.")
                .font(.system(size: 12))
                .foregroundColor(palette.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    private var liveNowPill: some View {
        Text("LIVE NOW")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(palette.accentRed)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.accentRed.opacity(0.10))
            .clipShape(Capsule())
    }



    private func headerRow(title: String, rightText: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(palette.textPrimary)
            Spacer()
            Text(rightText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.accentRed)
        }
    }

    private func newDropPill(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.system(size: 10, weight: .bold))
            Text("\(count) New Drop\(count == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(palette.accentRed)
        .clipShape(Capsule())
        .shadow(color: palette.accentRed.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    private func headerRow<Right: View>(title: String, rightView: Right) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(palette.textPrimary)
            Spacer()
            rightView
        }
    }

    // MARK: - Live scan bar

    private var liveScanBar: some View {
        HStack(spacing: 10) {
            AnimatedLiveDot()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(AppTheme.liveDot)
                        .tracking(0.8)
                    Text("·")
                        .foregroundColor(AppTheme.textTertiary)
                    Text("\(vm.totalVenuesScanned > 0 ? "\(vm.totalVenuesScanned)" : "698") venues scanned")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Text(vm.secondsUntilNextScan > 0 ? vm.nextScanLabel : (vm.lastScanAt != nil ? "Last scan \(vm.lastScanText)" : "Scanning…"))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Spacer()
            if vm.totalVenuesScanned > 0 || vm.lastScanAt != nil {
                Text(vm.lastScanText == "—" ? "" : "Updated \(vm.lastScanText)")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.liveDot.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - New drops banner

    private var newDropsBanner: some View {
        Button {
            vm.acknowledgeNewDrops()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.accentOrange)
                Text("\(vm.newDropsCount) new drop\(vm.newDropsCount == 1 ? "" : "s") just detected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("Dismiss")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.accentOrange.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section label

    @ViewBuilder
    private func sectionLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
                .tracking(0.4)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
        }
    }

    // MARK: - Error / empty

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 44))
                .foregroundColor(SnagDesignSystem.darkTextMuted)
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(SnagDesignSystem.darkTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") { Task { await vm.refresh() } }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(SnagDesignSystem.salmonAccent)
                .cornerRadius(12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SnagDesignSystem.darkCanvas)
    }

    private var hasActiveFilters: Bool {
        !feedVM.selectedDates.isEmpty || !feedVM.selectedPartySizes.isEmpty || feedVM.selectedTimeFilter != "all"
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundColor(SnagDesignSystem.darkTextMuted)
            Text("No drops yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(SnagDesignSystem.darkTextPrimary)
            Text("We scan continuously. Check back soon.")
                .font(.system(size: 15))
                .foregroundColor(SnagDesignSystem.darkTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SnagDesignSystem.darkCanvas)
    }
}

// MARK: - Shared date helper

/// Returns "Today", "Tomorrow", or "3/14" for any date string "yyyy-MM-dd".
private func friendlyDate(_ dateStr: String?) -> String? {
    guard let ds = dateStr, !ds.isEmpty else { return nil }
    // Parse "yyyy-MM-dd" by splitting on "-" — locale-safe, no DateFormatter needed.
    let parts = ds.split(separator: "-")
    guard parts.count == 3,
          let year  = Int(parts[0]),
          let month = Int(parts[1]),
          let day   = Int(parts[2]) else { return nil }
    var comps = DateComponents()
    comps.year  = year
    comps.month = month
    comps.day   = day
    let cal = Calendar.current
    guard let d = cal.date(from: comps) else { return nil }
    if cal.isDateInToday(d)     { return "Today" }
    if cal.isDateInTomorrow(d)  { return "Tomorrow" }
    return "\(month)/\(day)"
}

// MARK: - Mock feed helpers (bookability, badges)

private enum MockFeedBadgeStyle {
    case hot, new, neutral
}

private struct MockFeedBadge: Identifiable {
    let text: String
    let style: MockFeedBadgeStyle

    var id: String { "\(text)-\(String(describing: style))" }
}

private func feedFormatTime12h(_ t: String) -> String {
    let p = t.split(separator: ":")
    guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "—" : String(t.prefix(5)) }
    let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
    let h12 = h % 12 == 0 ? 12 : h % 12
    let ap = h < 12 ? "AM" : "PM"
    return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
}

/// Live feed / TOP DROPS: ranked_board entries are current inventory; treat as bookable
/// whenever we still have a Resy URL. ``explore_snag_available`` is tuned for Explore
/// and can be false while the home feed card is still valid.
private func feedDropIsBookable(_ drop: Drop) -> Bool {
    let u = (drop.resyUrl ?? drop.slots.first?.resyUrl)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !u.isEmpty
}

private func feedRelativeMissedLabel(_ iso: String?) -> String {
    guard let iso, let d = Drop.parseISO(iso) else { return "JUST NOW" }
    let sec = max(0, Int(-d.timeIntervalSinceNow))
    if sec < 90 { return "JUST NOW" }
    if sec < 3600 { return "\(max(1, sec / 60))M AGO" }
    return "\(sec / 3600)H AGO"
}

private func feedTimeToClaimLabel(for drop: Drop) -> String {
    if let avg = drop.avgDropDurationSeconds, avg > 0 {
        let s = min(120, max(5, Int(avg.rounded())))
        return "< \(s)s"
    }
    let guess = max(8, 75 - min(70, drop.secondsSinceDetected))
    return "< \(guess)s"
}

/// 0…1 — fills as the drop ages vs typical vanish window.
private func feedClaimUrgencyProgress(for drop: Drop) -> CGFloat {
    let window = max(20.0, drop.avgDropDurationSeconds ?? 55.0)
    let p = Double(drop.secondsSinceDetected) / window
    return CGFloat(min(1, max(0.06, p)))
}

private func signalStreamRowTags(for drop: Drop, bookable: Bool) -> [MockFeedBadge] {
    var list: [MockFeedBadge] = []
    if drop.feedHot == true || (drop.snagScore ?? 0) >= 85 {
        list.append(MockFeedBadge(text: "HOT SIGNAL", style: .hot))
    }
    if drop.brandNewDrop == true || drop.showNewBadge == true {
        list.append(MockFeedBadge(text: "NEW SUPPLY", style: .new))
    }
    if bookable, list.count < 2 {
        list.append(MockFeedBadge(text: "ACTIVE SUPPLY", style: .neutral))
    }
    if list.isEmpty, bookable {
        list.append(MockFeedBadge(text: "ACTIVE SUPPLY", style: .neutral))
    }
    return Array(list.prefix(2))
}

// MARK: - Market leader hero + signal stream rows

private struct MarketLeaderHeroCard: View {
    let drop: Drop

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var bookable: Bool { feedDropIsBookable(drop) }

    private var neighborhoodCaps: String {
        (drop.neighborhood ?? drop.location ?? "NYC").uppercased()
    }

    private var showVelocityBadge: Bool {
        drop.speedTier == "fast" || drop.velocityUrgent == true
    }

    /// Matches Explore `heroCardHeight` / Tonight’s Highlights card.
    private let cardHeight: CGFloat = 232

    private func executeClaim() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .heroMuted) {
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.5), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    if showVelocityBadge {
                        Text("HIGH VELOCITY")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .tracking(0.5)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(SnagDesignSystem.salmonAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TIME TO CLAIM")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(SnagDesignSystem.darkTextMuted)
                            .tracking(0.6)
                        Text(feedTimeToClaimLabel(for: drop))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 12)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(neighborhoodCaps)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.darkTextMuted)
                        .tracking(0.55)
                    Text(drop.name)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 2)
                            Capsule()
                                .fill(SnagDesignSystem.salmonAccent)
                                .frame(width: max(6, geo.size.width * feedClaimUrgencyProgress(for: drop)), height: 2)
                        }
                    }
                    .frame(height: 2)

                    Button(action: executeClaim) {
                        Text("EXECUTE CLAIM")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(Color(white: 0.12))
                            .tracking(0.65)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(bookable ? SnagDesignSystem.salmonAccent : Color(white: 0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!bookable)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(bookable ? 1 : 0.88)
    }
}

private struct MockJustMissedCard: View {
    let venue: JustMissedVenue

    private var imageURL: URL? {
        guard let s = venue.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private let cardW: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                        SnagDesignSystem.darkElevated
                    }
                } else {
                    SnagDesignSystem.darkElevated
                }
            }
            .frame(width: cardW, height: 86)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(SnagDesignSystem.darkTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(feedRelativeMissedLabel(venue.goneAt))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(SnagDesignSystem.darkTextMuted)
                    .tracking(0.35)
                if let nb = venue.neighborhood, !nb.isEmpty {
                    Text(nb.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.darkTextMuted)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(width: cardW, alignment: .leading)
            .background(Color(white: 0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct FeedPredictWillOpenSection: View {
    let venues: [LikelyToOpenVenue]
    @ObservedObject var premium: PremiumManager
    var onNotify: (String) -> Void
    var isWatched: (String) -> Bool

    @State private var showPaywall = false

    private var freeLimit: Int { PremiumManager.freeLikelyToOpenLimit }
    private var freeVenues: [LikelyToOpenVenue] { Array(venues.prefix(freeLimit)) }
    private var lockedVenues: [LikelyToOpenVenue] { premium.isPremium ? [] : Array(venues.dropFirst(freeLimit)) }
    private var allVisible: [LikelyToOpenVenue] { premium.isPremium ? venues : freeVenues }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WE PREDICT WILL OPEN")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .tracking(0.6)
                Text("From live scans — tap the bell to get notified when we spot a table.")
                    .font(.system(size: 11))
                    .foregroundColor(SnagDesignSystem.darkTextMuted)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allVisible) { venue in
                        predictCard(venue)
                    }
                    if !lockedVenues.isEmpty {
                        Button {
                            showPaywall = true
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 18))
                                Text("\(lockedVenues.count) more")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(SnagDesignSystem.salmonAccent)
                            .frame(width: 148, height: 168)
                            .background(Color(white: 0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(premium: premium)
        }
    }

    private func predictSubtitle(_ venue: LikelyToOpenVenue) -> String {
        if let t = venue.predictedDropTime, !t.isEmpty {
            return "Often drops: \(t)"
        }
        if let d = venue.daysWithDrops {
            return "Tables \(d)× / 14d"
        }
        return "Watch for releases"
    }

    private func predictCard(_ venue: LikelyToOpenVenue) -> some View {
        let watched = isWatched(venue.name)
        let score = venue.probability.map { min(99, max(1, $0)) }
        let imgURL: URL? = {
            guard let s = venue.imageUrl, !s.isEmpty else { return nil }
            return URL(string: s)
        }()

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let url = imgURL {
                        CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                            SnagDesignSystem.darkElevated
                        }
                    } else {
                        SnagDesignSystem.darkElevated
                    }
                }
                .frame(width: 148, height: 72)
                .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("FORECAST")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(SnagDesignSystem.darkTextMuted)
                        Spacer()
                        if let s = score {
                            Text("\(s)")
                                .font(.system(size: 16, weight: .black))
                                .foregroundColor(SnagDesignSystem.mint)
                        }
                    }
                    Text(venue.name)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundColor(SnagDesignSystem.darkTextPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(predictSubtitle(venue))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SnagDesignSystem.darkTextMuted)
                        .lineLimit(2)
                }
                .padding(10)
                .frame(width: 148, alignment: .leading)
                .background(Color(white: 0.12))
            }
            .frame(width: 148, height: 168, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            Button {
                onNotify(venue.name)
            } label: {
                Image(systemName: watched ? "bell.fill" : "bell")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(watched ? SnagDesignSystem.salmonAccent : .white)
                    .padding(8)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(width: 148, height: 168)
    }
}

private struct MockBadgePill: View {
    let badge: MockFeedBadge

    private var border: Color {
        switch badge.style {
        case .hot: return SnagDesignSystem.salmonAccent
        case .new: return Color.red.opacity(0.85)
        case .neutral: return Color.white.opacity(0.28)
        }
    }

    var body: some View {
        Text(badge.text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(SnagDesignSystem.darkTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(white: 0.14))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
    }
}

private struct MockLiveNowRow: View {
    let drop: Drop
    let preferredParty: Int

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var bookable: Bool { feedDropIsBookable(drop) }
    private var badges: [MockFeedBadge] { signalStreamRowTags(for: drop, bookable: bookable) }

    private var signalMetaLine: String {
        let t = feedFormatTime12h(drop.slots.first?.time ?? "")
        let party = "\(preferredParty)P"
        let score: String
        if let s = drop.snagScore {
            score = "\(s) SCORE"
        } else if let r = drop.rarityPoints {
            score = "\(r) HYPE"
        } else {
            score = "LIVE"
        }
        return "\(t) • \(party) • \(score)"
    }

    private func openResy() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(bookable ? SnagDesignSystem.salmonAccent : SnagDesignSystem.darkTextMuted.opacity(0.45))
                .frame(width: 3)

            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let url = imageURL {
                        CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                            SnagDesignSystem.darkElevated
                        }
                    } else {
                        SnagDesignSystem.darkElevated
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(drop.name)
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(bookable ? SnagDesignSystem.darkTextPrimary : SnagDesignSystem.darkTextMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    Text(signalMetaLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SnagDesignSystem.darkTextMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    if bookable {
                        if !badges.isEmpty {
                            VStack(alignment: .trailing, spacing: 4) {
                                ForEach(Array(badges.prefix(2).enumerated()), id: \.offset) { _, badge in
                                    MockBadgePill(badge: badge)
                                }
                            }
                        }
                        Button(action: openResy) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(SnagDesignSystem.salmonAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        if !badges.isEmpty {
                            VStack(alignment: .trailing, spacing: 4) {
                                ForEach(Array(badges.prefix(2).enumerated()), id: \.offset) { _, badge in
                                    MockBadgePill(badge: badge)
                                }
                            }
                        }
                        Text("CLAIMED: \(min(599, drop.secondsSinceDetected))S")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(SnagDesignSystem.darkTextMuted)
                            .tracking(0.35)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .opacity(bookable ? 1 : 0.55)
        .saturation(bookable ? 1 : 0.4)
    }
}

/// List-style “inventory predictions” matching the reference layout (premium gating like `LikelyToOpenSection`).
private struct InventoryPredictionsSection: View {
    let venues: [LikelyToOpenVenue]
    @ObservedObject var premium: PremiumManager
    var onNotifyMe: ((String) -> Void)?

    @State private var showPaywall = false

    private var freeLimit: Int { PremiumManager.freeLikelyToOpenLimit }
    private var freeVenues: [LikelyToOpenVenue] { Array(venues.prefix(freeLimit)) }
    private var lockedVenues: [LikelyToOpenVenue] { premium.isPremium ? [] : Array(venues.dropFirst(freeLimit)) }
    private var allVisible: [LikelyToOpenVenue] { premium.isPremium ? venues : freeVenues }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inventory Predictions")
                        .font(SnagDesignSystem.sectionSerif)
                        .foregroundColor(SnagDesignSystem.textDark)
                    Text("Upcoming drop probabilities based on live traffic.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SnagDesignSystem.textMuted)
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(SnagDesignSystem.textMuted)
            }

            VStack(spacing: 0) {
                ForEach(Array(allVisible.enumerated()), id: \.element.id) { idx, venue in
                    InventoryPredictionRow(
                        venue: venue,
                        onNotify: { onNotifyMe?(venue.name) }
                    )
                    if idx < allVisible.count - 1 {
                        Divider()
                            .background(Color.black.opacity(0.08))
                    }
                }
            }
            .padding(.vertical, 4)

            if !lockedVenues.isEmpty {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Unlock \(lockedVenues.count) more predictions")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(SnagDesignSystem.epicureanRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SnagDesignSystem.coralSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(premium: premium)
        }
    }
}

private struct InventoryPredictionRow: View {
    let venue: LikelyToOpenVenue
    var onNotify: () -> Void

    private var imageURL: URL? {
        guard let s = venue.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var statusTag: (String, Color) {
        guard let p = venue.probability else {
            return ("EMERGING", SnagDesignSystem.textMuted)
        }
        switch p {
        case 80...: return ("ALMOST CERTAIN", SnagDesignSystem.mint)
        case 60..<80: return ("VERY LIKELY", Color(red: 0.92, green: 0.35, blue: 0.55))
        default: return ("EMERGING", SnagDesignSystem.velocityAmber)
        }
    }

    private var dropEst: String {
        if let t = venue.predictedDropTime, !t.isEmpty {
            return t.uppercased()
        }
        return "EVENING"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            CardAsyncImage(url: imageURL, contentMode: .fill, skeletonTone: .snagMuted) {
                SnagDesignSystem.cardGray
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textDark)
                    .lineLimit(1)
                Text(venue.neighborhood ?? "NYC")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SnagDesignSystem.textMuted)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(statusTag.0)
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(statusTag.1)
                    .tracking(0.4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DROP EST.")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(SnagDesignSystem.textMuted)
                    Text(dropEst)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SnagDesignSystem.textDark)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { onNotify() }
    }
}

// MARK: - Crown Jewels hero card (Snag mockup: full-bleed image + gradient + Book Now)

private struct CrownJewelCard: View {
    let drop: Drop

    private let cardWidth: CGFloat = min(UIScreen.main.bounds.width - 48, 340)
    /// Shorter than the original 1.28× portrait ratio so the carousel doesn’t dominate the feed.
    private var cardHeight: CGFloat { cardWidth * 0.92 }

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var rarityBadge: String {
        drop.crownBadgeLabel ?? "HOT"
    }

    private var metricsSubtitle: String? {
        drop.metricsSubtitle
    }

    private var partySize: Int { drop.partySizesAvailable.sorted().first ?? 2 }

    private func formatTime(_ t: String) -> String {
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "" : String(t.prefix(5)) }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
    }

    private var whenLabel: String {
        let ds = drop.dateStr ?? drop.slots.first?.dateStr
        guard let ds, !ds.isEmpty else { return "Tonight" }
        let parts = ds.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else { return "Tonight" }
        var c = DateComponents()
        c.year = y
        c.month = mo
        c.day = d
        guard let date = Calendar.current.date(from: c) else { return "Tonight" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Tonight" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        let thisYear = cal.component(.year, from: Date())
        if cal.component(.year, from: date) == thisYear {
            fmt.dateFormat = "EEE, MMM d"
        } else {
            fmt.dateFormat = "EEE, MMM d, yyyy"
        }
        return fmt.string(from: date)
    }

    private var detailLine: String {
        let t = drop.slots.first?.time ?? ""
        let timePart = t.isEmpty ? "" : formatTime(t)
        if timePart.isEmpty {
            return "\(whenLabel) · \(partySize) Guests"
        }
        return "\(whenLabel) · \(timePart) · \(partySize) Guests"
    }

    private var cityLine: String {
        (drop.neighborhood ?? drop.location ?? "New York City").uppercased()
    }

    private func book() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .heroMuted) {
                        LinearGradient(
                            colors: [Color(white: 0.35), Color(white: 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.35), Color(white: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.25),
                    .black.opacity(0.82),
                ],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: cardWidth, height: cardHeight)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(rarityBadge)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SnagDesignSystem.coral)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(cityLine)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .tracking(1.1)
                    Text(drop.name)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                    Text(detailLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    if let m = metricsSubtitle {
                        Text(m)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.78))
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                    }

                    Button(action: book) {
                        Text("Book Now")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(SnagDesignSystem.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .bottom)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Top opportunities row (Snag mockup)

private struct TopOpportunitySnagRow: View {
    let drop: Drop

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var time24: String {
        let t = drop.slots.first?.time ?? ""
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "—" : String(t.prefix(5)) }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        return String(format: "%02d:%02d", h, m)
    }

    private var dayCaps: String {
        let ds = drop.dateStr ?? drop.slots.first?.dateStr
        guard let ds, !ds.isEmpty else { return "TONIGHT" }
        let parts = ds.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else { return "TONIGHT" }
        var c = DateComponents()
        c.year = y
        c.month = mo
        c.day = d
        guard let date = Calendar.current.date(from: c) else { return "TONIGHT" }
        if Calendar.current.isDateInToday(date) { return "TONIGHT" }
        if Calendar.current.isDateInTomorrow(date) { return "TOMORROW" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: date).uppercased()
    }

    private var primaryMetricLine: String? {
        drop.rowPrimaryMetric
    }

    private var speedPair: (String, Color)? {
        switch drop.speedTier {
        case "fast": return ("FAST", SnagDesignSystem.mint)
        case "med": return ("MED", Color(red: 0.95, green: 0.75, blue: 0.22))
        case "slow": return ("SLOW", Color(red: 0.95, green: 0.75, blue: 0.22))
        default: return nil
        }
    }

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(time24)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textDark)
                Text(dayCaps)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textMuted)
                    .tracking(0.5)
            }
            .frame(width: 58, alignment: .leading)

            CardAsyncImage(url: imageURL, contentMode: .fill, skeletonTone: .snagMuted) {
                SnagDesignSystem.cardGray
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(drop.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(SnagDesignSystem.textDark)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    if let line = primaryMetricLine {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(SnagDesignSystem.coral)
                            Text(line)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(SnagDesignSystem.coral)
                                .lineLimit(1)
                        }
                    }
                    if let sp = speedPair {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(sp.1)
                            Text(sp.0)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(sp.1)
                        }
                    }
                    if let rr = drop.ratingReviewsCompact, !rr.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(SnagDesignSystem.textMuted)
                            Text(rr)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(SnagDesignSystem.textMuted)
                        }
                    }
                }
                if let m2 = drop.metricsSecondaryCompact, !m2.isEmpty {
                    Text(m2)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.textMuted)
                }
            }

            Spacer(minLength: 4)

            Button {
                guard let url = resyUrl else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("BOOK")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(SnagDesignSystem.coral)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(SnagDesignSystem.coralSoft)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(SnagDesignSystem.coral.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Live stream row (reference layout)

private struct LiveStreamRow: View {
    let drop: Drop

    private let palette: FeedPalette = .liveFeedLight

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var partySize: Int { drop.partySizesAvailable.sorted().first ?? 2 }

    /// Left column: reservation time (matches reference: "9:00").
    private var timeColumn: String {
        let t = drop.slots.first?.time ?? ""
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "—" : String(t.prefix(5)) }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        return m > 0 ? String(format: "%d:%02d", h12, m) : "\(h12):00"
    }

    private var velocityLabel: String {
        drop.liveStreamVelocityBadge ?? "—"
    }

    private var fireCount: Int {
        max(1, min(3, drop.flameCount ?? 1))
    }

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(timeColumn)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(palette.textPrimary)
                .frame(width: 52, alignment: .leading)

            CardAsyncImage(url: imageURL, contentMode: .fill, skeletonTone: .lightOnLight) {
                LinearGradient(
                    colors: [Color(white: 0.86), Color(white: 0.78)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("\(drop.name) (\(partySize)p)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.38))
                        Text(velocityLabel)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.38))
                    }

                    HStack(spacing: 2) {
                        ForEach(0..<fireCount, id: \.self) { _ in
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                                .foregroundColor(palette.accentRed.opacity(0.9))
                        }
                    }

                    if let rr = drop.ratingReviewsCompact, !rr.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                            Text(rr)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    if let m2 = drop.metricsSecondaryCompact, !m2.isEmpty {
                        Text(m2)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(palette.textTertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                guard let url = resyUrl else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("BOOK")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(palette.accentRed)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.accentRed.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Barebones Drop Row

private struct BarebonesDropRow: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var dateAndTimeText: String {
        let dateStr = drop.dateStr ?? drop.slots.first?.dateStr
        let timeStr = drop.slots.first?.time

        let dateText: String? = {
            guard let ds = dateStr, !ds.isEmpty else { return nil }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            guard let d = fmt.date(from: ds) else { return nil }
            let cal = Calendar.current
            if cal.isDateInToday(d) { return "Tonight" }
            if cal.isDateInTomorrow(d) { return "Tomorrow" }
            let out = DateFormatter()
            out.dateFormat = "EEE, MMM d"
            return out.string(from: d)
        }()

        let timeText: String? = {
            guard let t = timeStr, !t.isEmpty else { return nil }
            return formatTime(t)
        }()

        switch (dateText, timeText) {
        case let (d?, t?) : return "\(d), \(t)"
        case let (d?, nil): return d
        case let (nil, t?): return t
        default: return "Availability"
        }
    }

    private func formatTime(_ time: String) -> String {
        let parts = time.split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return String(time.prefix(5)) }
        let m = parts.count > 1 ? (Int(parts[1].prefix(2)) ?? 0) : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(hour12):\(String(format: "%02d", m)) \(ap)" : "\(hour12) \(ap)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CardAsyncImage(url: resyUrl, contentMode: .fill, skeletonTone: .darkCard) {
                LinearGradient(
                    colors: [AppTheme.surfaceElevated, AppTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                if let loc = drop.neighborhood ?? drop.location, !loc.isEmpty {
                    Text("\(loc) · \(dateAndTimeText)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(dateAndTimeText)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    guard let url = resyUrl else { return }
                    UIApplication.shared.open(url)
                } label: {
                    HStack(spacing: 8) {
                        Text("Secure")
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.accentRed)
                    .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(resyUrl == nil)
                .opacity(resyUrl == nil ? 0.6 : 1)

                Button {
                    onToggleWatch(drop.name)
                } label: {
                    Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isWatched ? AppTheme.accentOrange : AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Rare Drop Card (vertical card for horizontal scroll)

private struct RareDropCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var daysLabel: String {
        if let d = drop.daysWithDrops { return "\(d)/14 days" }
        return "Rare"
    }

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var dateLabel: String {
        guard let ds = drop.dateStr ?? drop.slots.first?.dateStr else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: ds) else { return ds }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        return out.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                        AppTheme.surface
                    }
                } else {
                    LinearGradient(colors: [Color(red: 0.18, green: 0.12, blue: 0.22),
                                            Color(red: 0.1, green: 0.08, blue: 0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 160, height: 100)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text("RARE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(AppTheme.scarcityRare)
                    .cornerRadius(6)
                    .padding(8)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                if !dateLabel.isEmpty {
                    Text(dateLabel)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let rh = drop.rarityHeadline, !rh.isEmpty {
                        Text(rh)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.scarcityRare)
                            .lineLimit(1)
                    }
                    Text(daysLabel)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                    if let rd = drop.rareDropDetailLine, !rd.isEmpty {
                        Text(rd)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(2)
                    }
                }

                Button {
                    if let u = resyUrl { UIApplication.shared.open(u) }
                } label: {
                    Text("Reserve")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(AppTheme.accentOrange)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(10)
        }
        .frame(width: 160)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.scarcityRare.opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Trending Drop Card

private struct TrendingDropCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var trendStr: String {
        drop.trendHeadlineShort ?? ""
    }

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var dateLabel: String {
        guard let ds = drop.dateStr ?? drop.slots.first?.dateStr else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: ds) else { return ds }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d"
        return out.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                        AppTheme.surface
                    }
                } else {
                    LinearGradient(colors: [Color(red: 0.12, green: 0.18, blue: 0.22),
                                            Color(red: 0.08, green: 0.1, blue: 0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 150, height: 95)
            .clipped()
            .overlay(alignment: .topLeading) {
                if !trendStr.isEmpty {
                    Text(trendStr)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(AppTheme.liveDot)
                        .cornerRadius(6)
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                if !dateLabel.isEmpty {
                    Text(dateLabel)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                if let nb = drop.neighborhood, !nb.isEmpty {
                    Text(nb)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                Button {
                    if let u = resyUrl { UIApplication.shared.open(u) }
                } label: {
                    Text("Reserve")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(AppTheme.accent)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
        .frame(width: 150)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.liveDot.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Latest Drop Row (with rich metrics)

struct LatestDropRowView: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var statusBadge: (text: String, color: Color)? {
        if drop.brandNewDrop == true {
            return ("NEW", Color(red: 0.4, green: 0.6, blue: 0.95))
        }
        if drop.feedsRareCarousel == true { return ("RARE", AppTheme.scarcityRare) }
        return nil
    }

    private var timestampLabel: String {
        drop.serverFreshnessLabel ?? "Live"
    }

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var dateLabel: String {
        guard let ds = drop.dateStr ?? drop.slots.first?.dateStr else { return "" }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: ds) else { return ds }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private var subLabel: String {
        var parts: [String] = []
        if !dateLabel.isEmpty { parts.append(dateLabel) }
        if let nb = drop.neighborhood, !nb.isEmpty { parts.append(nb) }
        if let tail = drop.latestDropSubtitleMetrics, !tail.isEmpty { parts.append(tail) }
        return parts.joined(separator: " · ")
    }

    private var trendBadge: String? {
        drop.trendHeadlineShort
    }

    var body: some View {
        Button {
            if let url = resyUrl { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                        CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                            AppTheme.surface
                        }
                    } else {
                        AppTheme.surface
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Name + badges + sublabel
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
                    if !subLabel.isEmpty {
                        Text(subLabel)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                    if let trend = trendBadge {
                        Text(trend)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.liveDot)
                    }
                }

                Spacer(minLength: 4)

                // Timestamp + bookmark
                VStack(alignment: .trailing, spacing: 6) {
                    Text(timestampLabel)
                        .font(.system(size: 10, weight: .semibold))
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

// MARK: - Hot Right Now compact card (kept for compatibility)

struct HotRightNowCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var trendStr: String {
        drop.trendHeadlineShort ?? ""
    }

    private var neighborhoodStr: String {
        drop.neighborhood ?? (drop.location ?? "")
    }

    private var metricsFootnote: String? {
        drop.footnoteMetricsCompact
    }

    var body: some View {
        Button {
            if let url = resyUrl { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                        CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                            AppTheme.surface
                        }
                    } else { AppTheme.surface }
                }
                .frame(width: 120, height: 80)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(drop.name).font(.system(size: 12, weight: .semibold)).foregroundColor(AppTheme.textPrimary).lineLimit(1)
                        Spacer(minLength: 0)
                        if !trendStr.isEmpty {
                            Text(trendStr).font(.system(size: 10, weight: .bold)).foregroundColor(AppTheme.liveDot)
                        }
                    }
                    if !neighborhoodStr.isEmpty {
                        Text(neighborhoodStr).font(.system(size: 10)).foregroundColor(AppTheme.textTertiary).lineLimit(1)
                    }
                    if let m = metricsFootnote {
                        Text(m).font(.system(size: 9, weight: .medium)).foregroundColor(AppTheme.textTertiary).lineLimit(1)
                    }
                }
                .frame(width: 120)
            }
        }
        .buttonStyle(.plain)
    }
}
