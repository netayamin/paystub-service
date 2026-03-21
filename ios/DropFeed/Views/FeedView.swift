import SwiftUI

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    var onOpenSearch: (() -> Void)? = nil
    var onOpenAlerts: (() -> Void)? = nil
    var onOpenExplore: (() -> Void)? = nil
    var alertBadgeCount: Int = 0

    private var vm: FeedViewModel { feedVM }

    private let palette: FeedPalette = .liveFeedLight

    private let partySizeOptions = [2, 3, 4, 5, 6]

    @State private var showFilterSheet = false

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
        .background(SnagDesignSystem.pageCanvas)
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

    // MARK: - Reference layout (BEST RIGHT NOW + LIVE STREAM)

    private var referenceFeedScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                epicureanNavBar

                if vm.newDropsCount > 0 {
                    HStack {
                        Spacer(minLength: 0)
                        newDropPill(count: vm.newDropsCount)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                if let hero = epicureanFeaturedHeroDrop {
                    EpicureanFeaturedHeroCard(drop: hero)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }

                VelocityFeedSection(
                    drops: velocityCarouselDrops,
                    onViewAll: { showFilterSheet = true }
                )
                .padding(.top, 28)

                HottestOpeningsSection(drops: hottestVerticalDrops)
                    .padding(.top, 28)

                if !vm.likelyToOpen.isEmpty {
                    InventoryPredictionsSection(
                        venues: vm.likelyToOpen,
                        premium: premium,
                        onNotifyMe: { savedVM.toggleWatch($0) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                }

                filterPillsRow
                    .padding(.top, 20)

                Button {
                    showFilterSheet = true
                } label: {
                    Text("More filters")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.epicureanRed)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .background(SnagDesignSystem.pageCanvas)
    }

    /// #1 curated top drop, else first live card.
    private var epicureanFeaturedHeroDrop: Drop? {
        vm.topDrops.first ?? vm.drops.first
    }

    /// Horizontal “velocity” strip: top picks after the hero, then other live drops (deduped).
    private var velocityCarouselDrops: [Drop] {
        let heroId = epicureanFeaturedHeroDrop?.id
        var seen = Set<String>()
        var out: [Drop] = []
        for d in vm.topDrops.dropFirst() + vm.justDropped {
            if d.id == heroId { continue }
            if seen.insert(d.id).inserted {
                out.append(d)
            }
            if out.count >= 12 { break }
        }
        return out
    }

    /// Vertical “hottest” list: strong opportunities not already in hero or velocity strip.
    private var hottestVerticalDrops: [Drop] {
        let exclude = Set(
            [epicureanFeaturedHeroDrop?.id].compactMap { $0 } + velocityCarouselDrops.map(\.id)
        )
        let primary = snagTopOpportunityDrops.filter { !exclude.contains($0.id) }
        if primary.count >= 4 { return Array(primary.prefix(12)) }
        let fill = vm.justDropped.filter { !exclude.contains($0.id) && !primary.map(\.id).contains($0.id) }
        return Array((primary + fill).prefix(12))
    }

    private var epicureanNavBar: some View {
        ZStack {
            Text("SNAG")
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .tracking(3)
                .foregroundColor(SnagDesignSystem.textDark)

            HStack(alignment: .center) {
                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(SnagDesignSystem.textDark)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    TimelineView(.animation(minimumInterval: 0.8)) { _ in
                        Circle()
                            .fill(SnagDesignSystem.epicureanRed)
                            .frame(width: 7, height: 7)
                            .opacity(0.45)
                            .overlay(
                                Circle()
                                    .fill(SnagDesignSystem.epicureanRed)
                                    .frame(width: 5, height: 5)
                            )
                    }
                    Text("LIVE SCAN ACTIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(SnagDesignSystem.epicureanRed)
                        .tracking(0.4)
                }

                Button {
                    onOpenAlerts?()
                } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(SnagDesignSystem.textDark)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SnagDesignSystem.pageWhite)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
        }
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
                .foregroundColor(palette.textTertiary)
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") { Task { await vm.refresh() } }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(palette.accentRed)
                .cornerRadius(12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SnagDesignSystem.pageCanvas)
    }

    private var hasActiveFilters: Bool {
        !feedVM.selectedDates.isEmpty || !feedVM.selectedPartySizes.isEmpty || feedVM.selectedTimeFilter != "all"
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundColor(palette.textTertiary)
            Text("No drops yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(palette.textPrimary)
            Text("We scan continuously. Check back soon.")
                .font(.system(size: 15))
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(SnagDesignSystem.pageCanvas)
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

// MARK: - Epicurean reference layout (hero + velocity + hottest + inventory)

private struct EpicureanFeaturedHeroCard: View {
    let drop: Drop

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var cityScanLine: String {
        let nb = (drop.neighborhood ?? drop.location ?? "Manhattan").uppercased()
        return "LIVE SCANNING \(nb)"
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

    private var availabilityLine: String {
        let ds = drop.dateStr ?? drop.slots.first?.dateStr
        let when: String = {
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
            fmt.dateFormat = "EEE, MMM d"
            return fmt.string(from: date)
        }()
        let t = drop.slots.first?.time ?? ""
        let timePart = t.isEmpty ? "" : formatTime(t)
        if timePart.isEmpty {
            return "AVAILABILITY / \(when) · (\(partySize))"
        }
        return "AVAILABILITY / \(when), \(timePart) (\(partySize))"
    }

    private func book() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    private var cardWidth: CGFloat { min(UIScreen.main.bounds.width - 32, 400) }
    private var cardHeight: CGFloat { cardWidth * 0.95 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .heroMuted) {
                        LinearGradient(
                            colors: [Color(white: 0.32), Color(white: 0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                } else {
                    LinearGradient(
                        colors: [Color(white: 0.32), Color(white: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.2), .black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: cardWidth, height: cardHeight)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SnagDesignSystem.epicureanRed)
                            .frame(width: 6, height: 6)
                        Text(cityScanLine)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .tracking(0.6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45))
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding(14)

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(drop.name)
                            .font(.system(size: 26, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                        Text(availabilityLine)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button(action: book) {
                        HStack(spacing: 6) {
                            Text("SNAG SEAT")
                                .font(.system(size: 12, weight: .heavy))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(SnagDesignSystem.epicureanRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .bottom)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 10)
    }
}

private struct VelocityFeedSection: View {
    let drops: [Drop]
    var onViewAll: () -> Void

    var body: some View {
        if drops.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THE VELOCITY FEED")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(SnagDesignSystem.epicureanRed)
                            .tracking(0.9)
                        Text("Velvet drops")
                            .font(SnagDesignSystem.sectionSerif)
                            .foregroundColor(SnagDesignSystem.textDark)
                    }
                    Spacer()
                    Button(action: onViewAll) {
                        Text("VIEW ALL")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(SnagDesignSystem.textMuted)
                            .tracking(0.5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(drops, id: \.id) { VelocityDropCard(drop: $0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct VelocityDropCard: View {
    let drop: Drop

    private var partySize: Int { drop.partySizesAvailable.sorted().first ?? 2 }

    private var urgent: Bool { drop.secondsSinceDetected < 600 }

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private func book() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let window = max(120, Int(drop.avgDropDurationSeconds ?? 300))
            let left = max(0, window - drop.secondsSinceDetected)
            let mm = left / 60
            let ss = left % 60
            let clock = String(format: "%02d:%02d", mm, ss)

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    CardAsyncImage(url: imageURL, contentMode: .fill, skeletonTone: .heroMuted) {
                        (urgent ? SnagDesignSystem.epicureanRed : SnagDesignSystem.velocityAmber).opacity(0.35)
                    }
                    .frame(height: 112)
                    .clipped()

                    Text(urgent ? "URGENT" : "PENDING")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(urgent ? SnagDesignSystem.epicureanRed : SnagDesignSystem.velocityAmber)
                        .clipShape(Capsule())
                        .padding(10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(clock)
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(urgent ? SnagDesignSystem.epicureanRed : SnagDesignSystem.textDark)
                        Spacer()
                    }
                    Text(drop.name)
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(SnagDesignSystem.textDark)
                        .lineLimit(2)
                    Text("Table · \(partySize) guests")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(SnagDesignSystem.textMuted)

                    Button(action: book) {
                        Text("CLAIM NOW")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                urgent ? SnagDesignSystem.epicureanRed : SnagDesignSystem.textDark
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
            .frame(width: 252)
            .background(SnagDesignSystem.pageWhite)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(urgent ? 0 : 0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        }
    }
}

private struct HottestOpeningsSection: View {
    let drops: [Drop]

    var body: some View {
        if drops.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Hottest Openings")
                        .font(SnagDesignSystem.sectionSerif)
                        .foregroundColor(SnagDesignSystem.textDark)
                    Text("NEW RELEASES")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(SnagDesignSystem.textMuted)
                        .tracking(0.6)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(SnagDesignSystem.cardGray)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.horizontal, 16)

                VStack(spacing: 22) {
                    ForEach(drops, id: \.id) { HottestOpeningCard(drop: $0) }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct HottestOpeningCard: View {
    let drop: Drop

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var subtitleLine: String {
        let nb = drop.neighborhood ?? drop.location ?? "NYC"
        return "\(nb) · Live availability"
    }

    private var score: Int {
        let r = drop.rarityScore ?? 0
        let p = (drop.resyPopularityScore ?? 0) * 38
        let rat = ((drop.ratingAverage ?? 0) / 5.0) * 22
        let hot: Double = drop.feedHot == true ? 14 : 0
        return min(99, max(55, Int(r * 0.28 + p + rat + hot)))
    }

    private var showExclusive: Bool {
        drop.feedHot == true || (drop.rarityScore ?? 0) >= 65
    }

    private func book() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                CardAsyncImage(url: imageURL, contentMode: .fill, skeletonTone: .snagMuted) {
                    SnagDesignSystem.cardGray
                }
                .frame(height: 200)
                .clipped()

                if showExclusive {
                    Text("EXCLUSIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(SnagDesignSystem.epicureanRed)
                        .clipShape(Capsule())
                        .padding(12)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundColor(SnagDesignSystem.textDark)
                        .lineLimit(2)
                    Text(subtitleLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SnagDesignSystem.textMuted)
                }
                Spacer(minLength: 8)
                VStack(spacing: 4) {
                    Text("SCORE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(SnagDesignSystem.textMuted)
                    Text("\(score)")
                        .font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundColor(SnagDesignSystem.textDark)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(SnagDesignSystem.cardGray)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(16)
            .background(SnagDesignSystem.pageWhite)

            Button(action: book) {
                Text("View on Resy")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(SnagDesignSystem.epicureanRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SnagDesignSystem.pageWhite)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 1)
            }
        }
        .background(SnagDesignSystem.pageWhite)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 8)
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
        let p = venue.probability ?? 50
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

    private var rarityInt: Int { max(0, min(100, Int((drop.rarityScore ?? 0).rounded()))) }
    private var rarityBadge: String {
        if drop.feedHot == true || rarityInt >= 88 { return "LEGENDARY" }
        if rarityInt >= 70 || drop.scarcityTier == .rare { return "ULTRA RARE" }
        if rarityInt >= 50 { return "RARE" }
        return "HOT"
    }

    /// Subtitle from live-scan metrics (vanish speed, cadence, week trend).
    private var metricsSubtitle: String? {
        var parts: [String] = []
        if let v = FeedMetricLabels.vanishShort(avgDurationSeconds: drop.avgDropDurationSeconds) {
            parts.append("Gone in \(v)")
        }
        if let d = FeedMetricLabels.activeDaysShort(daysWithDrops: drop.daysWithDrops) {
            parts.append("Open \(d)")
        }
        if let t = FeedMetricLabels.trendShortLabel(trendPct: drop.trendPct) {
            parts.append(t)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    /// Primary metric line: rarity tier + score from rolling scan data.
    private var rarityLine: String? {
        if drop.rarityScore != nil, drop.rarityScore! > 0 {
            return FeedMetricLabels.rarityHeadline(score: drop.rarityScore)
        }
        if let pop = drop.resyPopularityScore, pop > 0 {
            let pct = Int(min(0.99, pop) * 100)
            return "Demand \(pct)%"
        }
        return nil
    }

    private var speedPair: (String, Color)? {
        guard let sec = drop.avgDropDurationSeconds, sec > 0 else { return nil }
        if sec < 180 { return ("FAST", SnagDesignSystem.mint) }
        if sec < 900 { return ("MED", Color(red: 0.95, green: 0.75, blue: 0.22)) }
        return ("SLOW", Color(red: 0.95, green: 0.75, blue: 0.22))
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
                    if let line = rarityLine {
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
                    if let rc = drop.ratingCount, rc > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(SnagDesignSystem.textMuted)
                            Text(rc >= 1000 ? String(format: "%.1fk", Double(rc) / 1000.0) : "\(rc)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(SnagDesignSystem.textMuted)
                        }
                    }
                }
                HStack(spacing: 8) {
                    if let days = FeedMetricLabels.activeDaysShort(daysWithDrops: drop.daysWithDrops) {
                        Text(days)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(SnagDesignSystem.textMuted)
                    }
                    if let t = FeedMetricLabels.trendShortLabel(trendPct: drop.trendPct) {
                        Text(t)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(SnagDesignSystem.mint)
                    } else if drop.trendPct != nil {
                        Text(FeedMetricLabels.heatLabel(trendPct: drop.trendPct))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(SnagDesignSystem.textMuted)
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

    /// Lightning metric: historical vanish speed, else freshness since detected.
    private var velocityLabel: String {
        if let d = drop.avgDropDurationSeconds, d > 0 {
            if d < 60 { return "\(Int(d))S" }
            return "\(Int(d / 60))M"
        }
        let s = drop.secondsSinceDetected
        if s < 60 { return "\(s)S" }
        return "\(s / 60)M"
    }

    private var fireCount: Int {
        if drop.feedHot == true { return 3 }
        let r = Int((drop.rarityScore ?? 0).rounded())
        if r >= 75 { return 3 }
        if r >= 45 { return 2 }
        return 1
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

                    if let rc = drop.ratingCount, rc > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                            Text(rc > 999 ? String(format: "%.1fK", Double(rc) / 1000.0) : "\(rc)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    if let tr = FeedMetricLabels.trendShortLabel(trendPct: drop.trendPct) {
                        Text(tr)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.liveDot)
                    }
                    if let d = FeedMetricLabels.activeDaysShort(daysWithDrops: drop.daysWithDrops) {
                        Text(d)
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
                    Text(FeedMetricLabels.rarityHeadline(score: drop.rarityScore))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.scarcityRare)
                        .lineLimit(1)
                    Text(daysLabel)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                    HStack(spacing: 6) {
                        if let v = FeedMetricLabels.vanishShort(avgDurationSeconds: drop.avgDropDurationSeconds) {
                            Text("~\(v) open")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        if let t = FeedMetricLabels.trendShortLabel(trendPct: drop.trendPct) {
                            Text(t)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(AppTheme.liveDot)
                        }
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
        FeedMetricLabels.trendShortLabel(trendPct: drop.trendPct) ?? ""
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
        let sec = drop.secondsSinceDetected
        if sec >= 0 && sec < 300 { return ("NEW", Color(red: 0.4, green: 0.6, blue: 0.95)) }
        if drop.scarcityTier == .rare { return ("RARE", AppTheme.scarcityRare) }
        return nil
    }

    private var timestampLabel: String {
        let sec = drop.secondsSinceDetected
        if sec < 60 { return "JUST NOW" }
        if sec < 3600 { return "\(sec / 60)M AGO" }
        if sec < 86400 { return "\(sec / 3600)H AGO" }
        return "1D+ AGO"
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
        if let sl = drop.scarcityLabel { parts.append(sl) }
        if let v = FeedMetricLabels.vanishShort(avgDurationSeconds: drop.avgDropDurationSeconds) {
            parts.append("Gone in \(v)")
        }
        return parts.joined(separator: " · ")
    }

    private var trendBadge: String? {
        FeedMetricLabels.trendShortLabel(trendPct: drop.trendPct)
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
        FeedMetricLabels.trendShortLabel(trendPct: drop.trendPct) ?? ""
    }

    private var neighborhoodStr: String {
        drop.neighborhood ?? (drop.location ?? "")
    }

    private var metricsFootnote: String? {
        var parts: [String] = []
        if let d = FeedMetricLabels.activeDaysShort(daysWithDrops: drop.daysWithDrops) { parts.append(d) }
        if let v = FeedMetricLabels.vanishShort(avgDurationSeconds: drop.avgDropDurationSeconds) { parts.append("~\(v)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
