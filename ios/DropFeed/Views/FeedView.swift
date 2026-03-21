import SwiftUI

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    var onOpenSearch: (() -> Void)? = nil
    var onOpenAlerts: (() -> Void)? = nil
    var alertBadgeCount: Int = 0

    private var vm: FeedViewModel { feedVM }

    private let palette: FeedPalette = .liveFeedLight

    private let partySizeOptions = [2, 3, 4, 5, 6]

    @State private var crownPage = 0

    private var viewStateId: String {
        if vm.isLoading && vm.drops.isEmpty { return "loading" }
        if vm.error != nil { return "error" }
        if vm.drops.isEmpty { return "empty" }
        return "content"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Extend the Top Drops dark background into the top safe area (status bar region).
            FeedPalette.liveFeedDark.pageBackground
                .frame(height: 0)
                .ignoresSafeArea(edges: .top)

            Group {
                if vm.isLoading && vm.drops.isEmpty {
                    FeedSkeletonView()
                } else if let err = vm.error {
                    errorView(err)
                } else if vm.drops.isEmpty {
                    emptyView
                } else {
                    barebonesFeedContent
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewStateId)
        }
        .refreshable { await vm.refresh() }
        .task {
            await vm.refresh()
            vm.startPolling()
        }
    }

    // MARK: - Top nav bar

    private var topNavBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.orange.opacity(0.20))
                .frame(width: 34, height: 34)
                .overlay(
                    Text("S")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.orange.opacity(0.9))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Snag")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(palette.textPrimary)
                    Circle()
                        .fill(palette.accentRed)
                        .frame(width: 6, height: 6)
                }
                Text("LIVE FEED")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.textTertiary)
                    .tracking(0.6)
            }

            Spacer(minLength: 0)

            Button { onOpenAlerts?() } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.black.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(palette.pageBackground)
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

    // MARK: - Main feed layout

    private var barebonesFeedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                snagAppHeader

                if vm.newDropsCount > 0 {
                    HStack {
                        Spacer(minLength: 0)
                        newDropPill(count: vm.newDropsCount)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                crownJewelsSection
                    .padding(.bottom, 32)

                if !vm.forecastVenues.isEmpty {
                    dropForecastSection
                        .padding(.bottom, 32)
                }

                velocityFeedSection
                    .padding(.bottom, 32)

                if !vm.hotZones.isEmpty {
                    hotZonesSection
                        .padding(.bottom, 28)
                }
            }
            .padding(.bottom, 24)
        }
    }

    // MARK: - App header

    private var snagAppHeader: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(palette.accentRed)
                        .frame(width: 32, height: 32)
                    Text("S")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                }
                Text("Snag")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(palette.textPrimary)
            }
            Spacer()
            Button { onOpenSearch?() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color(white: 0.93))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Crown Jewels (paginated hero cards)

    private var crownJewelsSection: some View {
        let top = Array(vm.topDrops)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("THE CROWN JEWELS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(palette.accentRed)
                        .tracking(1.2)
                    Text("Rare Finds")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(palette.textPrimary)
                }
                Spacer()
                if top.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<min(top.count, 4), id: \.self) { i in
                            Circle()
                                .fill(i == crownPage ? palette.accentRed : Color(white: 0.80))
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: crownPage)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            if top.isEmpty {
                Text("Scanning for top drops…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(palette.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
            } else if top.count == 1 {
                TopDropCard(
                    drop: top[0],
                    isWatched: savedVM.isWatched(top[0].name),
                    onToggleWatch: { savedVM.toggleWatch($0) }
                )
                .padding(.horizontal, 16)
            } else {
                TabView(selection: $crownPage) {
                    ForEach(top.indices, id: \.self) { i in
                        TopDropCard(
                            drop: top[i],
                            isWatched: savedVM.isWatched(top[i].name),
                            onToggleWatch: { savedVM.toggleWatch($0) }
                        )
                        .padding(.horizontal, 16)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 340)
            }

            HStack(spacing: 6) {
                if let refreshed = vm.lastRefreshed {
                    if vm.isRefreshing {
                        ProgressView().scaleEffect(0.55).frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(Color(red: 0.22, green: 0.75, blue: 0.40))
                            .frame(width: 5, height: 5)
                    }
                    Text(topDropsUpdatedLabel(refreshed))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(palette.textTertiary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill").font(.system(size: 9))
                    Text("NYC'S HARDEST RESERVATIONS · LIVE EVERY 20S")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                }
                .foregroundColor(palette.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - Velocity Feed

    private var velocityFeedSection: some View {
        let visible: [Drop] = vm.tickerDrops.isEmpty
            ? Array(vm.justDropped.prefix(5))
            : vm.tickerDrops
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Velocity Feed")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(palette.textPrimary)
                    Text("Live drops happening right now")
                        .font(.system(size: 12))
                        .foregroundColor(palette.textTertiary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(palette.accentRed)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(palette.accentRed)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(palette.accentRed.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(palette.accentRed.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 16)

            if visible.isEmpty {
                Text("Scanning for live drops…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(palette.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, drop in
                        VelocityFeedRow(drop: drop)
                            .id(drop.id)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
                            .animation(.easeInOut(duration: 0.55), value: drop.id)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Drop Forecast

    private var dropForecastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DROP FORECAST")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(palette.accentRed)
                        .tracking(1.2)
                    Text("Predictions")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(palette.textPrimary)
                }
                Spacer()
                Text("Based on 14-day history")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.horizontal, 16)

            // Urgency callout — from avgDropDurationSeconds (real venue_metrics data)
            let fast = vm.fastVanishDrops.prefix(2)
            if !fast.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(fast), id: \.id) { drop in
                        urgencyRow(drop)
                    }
                }
                .padding(.horizontal, 16)
            }

            // Forecast cards — horizontal scroll sorted by probability desc
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.forecastVenues.prefix(8)) { venue in
                        ForecastCard(
                            venue: venue,
                            isWatched: savedVM.isWatched(venue.name)
                        ) {
                            savedVM.toggleWatch(venue.name)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Urgency banner for a currently-live drop where tables historically vanish fast.
    private func urgencyRow(_ drop: Drop) -> some View {
        let secs = drop.avgDropDurationSeconds ?? 0
        let label: String = {
            if secs < 60 { return "~\(Int(secs))s avg" }
            return "~\(Int(secs / 60))m \(Int(secs) % 60)s avg"
        }()

        return HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(palette.accentRed)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(drop.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Text("Tables vanish in \(label) — open now")
                    .font(.system(size: 11))
                    .foregroundColor(palette.textTertiary)
            }

            Spacer(minLength: 4)

            if let url = (drop.resyUrl ?? drop.slots.first?.resyUrl).flatMap(URL.init) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    Text("Go")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(palette.accentRed)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.accentRed.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.accentRed.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Hot Zones

    private var hotZonesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Hot Zones")
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(palette.textPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .fill(palette.accentRed.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(palette.accentRed)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.hotZones, id: \.name) { zone in
                        HotZoneCard(name: zone.name, activeCount: zone.activeCount)
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
        .background(palette.surface)
        .cornerRadius(14)
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
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.liveDot.opacity(0.3), lineWidth: 0.5)
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
            .background(AppTheme.accentOrange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.accentOrange.opacity(0.4), lineWidth: 0.5)
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
        .background(palette.pageBackground)
    }

    private var hasActiveFilters: Bool {
        !feedVM.selectedDates.isEmpty || !feedVM.selectedPartySizes.isEmpty || feedVM.selectedTimeFilter != "all"
    }

    /// "updated just now" / "updated 14s ago" / "updated 2m ago" shown in Top Drops header.
    private func topDropsUpdatedLabel(_ date: Date) -> String {
        let s = max(0, Int(-date.timeIntervalSinceNow))
        if s < 5  { return "updated just now" }
        if s < 60 { return "updated \(s)s ago" }
        return "updated \(s / 60)m ago"
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
        .background(palette.pageBackground)
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

// MARK: - Top drop card (hero, full-bleed image)

private struct TopDropCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private let palette: FeedPalette = .liveFeedLight
    private let cardWidth: CGFloat = UIScreen.main.bounds.width - 48

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var rarityScore: Int {
        max(0, min(100, Int((drop.rarityScore ?? 0).rounded())))
    }

    private var isTrending: Bool { (drop.trendPct ?? 0) > 10 || drop.feedHot == true }

    private var partySize: Int { drop.partySizesAvailable.sorted().first ?? 2 }

    private func formatTime(_ t: String) -> String {
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "" : String(t.prefix(5)) }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
    }

    private func slotLabel(_ slot: DropSlot) -> String {
        let date = friendlyDate(slot.dateStr ?? drop.dateStr) ?? ""
        let time = formatTime(slot.time ?? "")
        guard !time.isEmpty else { return date.isEmpty ? "Reserve" : date }
        return date.isEmpty ? time : "\(date)  \(time)"
    }

    private func openSlot(_ slot: DropSlot) {
        let urlStr = slot.resyUrl ?? drop.resyUrl ?? drop.slots.first?.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Image
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    LinearGradient(
                        colors: [Color(white: 0.18), Color(white: 0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: cardWidth, height: 320)
            .clipped()

            // Bottom gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Bottom content
            VStack(alignment: .leading, spacing: 10) {
                Text(drop.name)
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Text("Party of \(partySize)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))

                // Time slot pills — one per available slot
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(drop.slots.prefix(8).enumerated()), id: \.offset) { _, slot in
                            Button { openSlot(slot) } label: {
                                Text(slotLabel(slot))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(palette.accentRed)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if drop.slots.isEmpty {
                            Button { openSlot(DropSlot(dateStr: drop.dateStr, time: nil, resyUrl: drop.resyUrl)) } label: {
                                Text("Reserve")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(palette.accentRed)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)

            // Top badges
            VStack {
                HStack {
                    if isTrending {
                        Text("TRENDING")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if rarityScore > 0 {
                        Text("\(rarityScore)/100\nRARITY")
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineSpacing(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(palette.accentRed)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
                Spacer()
            }
        }
        .frame(width: cardWidth, height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
    }
}

// MARK: - Real-time ticker card

private struct RealTimeTickerCard: View {
    let drop: Drop

    private let palette: FeedPalette = .liveFeedLight

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var isJustNow: Bool { drop.secondsSinceDetected <= 120 }

    private var freshnessBadge: String {
        let s = max(0, drop.secondsSinceDetected)
        if s <= 120 { return "JUST NOW" }
        let m = s / 60
        if m < 60 { return "\(m) MIN AGO" }
        return "\(m / 60)H AGO"
    }

    private var compactTime: String {
        let t = drop.slots.first?.time ?? ""
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "—" : String(t.prefix(5)) }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "A" : "P"
        return m > 0 ? "\(h12):\(String(format: "%02d", m))\(ap)" : "\(h12):00\(ap)"
    }

    private var dateLabel: String {
        friendlyDate(drop.dateStr ?? drop.slots.first?.dateStr) ?? ""
    }

    private var partySize: Int { drop.partySizesAvailable.sorted().first ?? 2 }
    private var rarityScore: Int { max(0, min(100, Int((drop.rarityScore ?? 0).rounded()))) }
    private var showRarity: Bool { rarityScore > 0 }

    private func categoryBadge(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(0.3)
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    var body: some View {
        HStack(spacing: 12) {

            // Circular thumbnail
            ZStack {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        LinearGradient(
                            colors: [Color(white: 0.82), Color(white: 0.72)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
            }

            // Middle content
            VStack(alignment: .leading, spacing: 5) {
                // Name + freshness badge
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(drop.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(freshnessBadge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isJustNow ? palette.accentRed : palette.textTertiary)
                        .fixedSize()
                }

                // Category badge row — explains WHY this venue is notable
                HStack(spacing: 6) {
                    if drop.feedHot == true {
                        categoryBadge("ELITE", icon: "flame.fill", color: palette.accentRed)
                    } else if rarityScore >= 70 {
                        categoryBadge("RARE", icon: "bolt.fill", color: Color(red: 0.95, green: 0.55, blue: 0.10))
                    } else if (drop.trendPct ?? 0) > 15 {
                        categoryBadge("TRENDING", icon: "arrow.up.right", color: Color(red: 0.22, green: 0.75, blue: 0.40))
                    } else {
                        categoryBadge("OPEN NOW", icon: "checkmark.circle.fill", color: palette.textTertiary)
                    }

                    // Neighborhood
                    if let nb = drop.neighborhood ?? drop.location, !nb.isEmpty {
                        Text(nb)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(1)
                    }
                }

                // Chips row: date/time · party size · days-seen context
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 11))
                        Text(dateLabel.isEmpty ? compactTime : "\(dateLabel) \(compactTime)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(palette.textSecondary)

                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                        Text("P\(partySize)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(palette.textSecondary)

                    // Metrics context: days seen or rarity score
                    if let days = drop.daysWithDrops {
                        Text("\(days)/14 days")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(days <= 3 ? palette.accentRed : palette.textTertiary)
                    } else if showRarity {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(rarityScore)/100")
                                .font(.system(size: 11, weight: .black))
                        }
                        .foregroundColor(rarityScore >= 70 ? palette.accentRed : palette.textTertiary)
                    }
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    drop.feedHot == true ? palette.accentRed.opacity(0.7) : palette.border,
                    lineWidth: drop.feedHot == true ? 1.5 : 1
                )
        )
        .shadow(
            color: drop.feedHot == true ? palette.accentRed.opacity(0.20) : Color.black.opacity(0.04),
            radius: drop.feedHot == true ? 10 : 6,
            x: 0, y: drop.feedHot == true ? 3 : 2
        )
    }
}

// MARK: - Velocity Feed Row

private struct VelocityFeedRow: View {
    let drop: Drop

    private let palette: FeedPalette = .liveFeedLight

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var statusBadge: (label: String, color: Color) {
        if drop.feedHot == true {
            return ("HOT DROP", Color(red: 0.10, green: 0.72, blue: 0.40))
        }
        let secs = drop.secondsSinceDetected
        if secs <= 300 {
            return ("NEW", Color(red: 0.20, green: 0.55, blue: 0.95))
        }
        return ("PRIME", Color(red: 0.95, green: 0.60, blue: 0.10))
    }

    private var rarityScore: Int { max(0, min(100, Int((drop.rarityScore ?? 0).rounded()))) }
    private var partySize: Int { drop.partySizesAvailable.sorted().first ?? 2 }
    private var compactTime: String {
        let t = drop.slots.first?.time ?? ""
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t.isEmpty ? "—" : String(t.prefix(5)) }
        let m = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
    }
    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    LinearGradient(
                        colors: [Color(white: 0.82), Color(white: 0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                    let badge = statusBadge
                    Text(badge.label)
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .tracking(0.3)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(badge.color)
                        .clipShape(Capsule())
                }

                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.system(size: 11))
                        Text(compactTime).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(palette.textSecondary)

                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill").font(.system(size: 11))
                        Text("\(partySize)p").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(palette.textSecondary)
                }

                HStack(spacing: 8) {
                    // Rarity score from rolling metrics
                    if rarityScore > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill").font(.system(size: 10, weight: .bold))
                            Text("\(rarityScore)/100").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(rarityScore >= 70 ? palette.accentRed : palette.textTertiary)
                    }

                    // Urgency: how fast tables historically vanish (from venue_metrics)
                    if let dur = drop.avgDropDurationSeconds, dur < 120 {
                        let label = dur < 60 ? "~\(Int(dur))s" : "~\(Int(dur / 60))m\(Int(dur) % 60 > 0 ? "\(Int(dur) % 60)s" : "")"
                        HStack(spacing: 3) {
                            Image(systemName: "timer").font(.system(size: 10, weight: .bold))
                            Text("Vanishes in \(label)").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(palette.accentRed)
                    }
                }
            }

            Button {
                guard let url = resyUrl else { return }
                UIApplication.shared.open(url)
            } label: {
                Text("Snag")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(palette.accentRed)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.accentRed.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(palette.accentRed.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    drop.feedHot == true ? palette.accentRed.opacity(0.5) : palette.border,
                    lineWidth: 1
                )
        )
        .shadow(
            color: drop.feedHot == true ? palette.accentRed.opacity(0.15) : Color.black.opacity(0.04),
            radius: drop.feedHot == true ? 8 : 5,
            x: 0, y: 2
        )
    }
}

// MARK: - Hot Zone Card

private struct HotZoneCard: View {
    let name: String
    let activeCount: Int

    private let gradientPairs: [[Color]] = [
        [Color(red: 0.12, green: 0.12, blue: 0.18), Color(red: 0.22, green: 0.16, blue: 0.20)],
        [Color(red: 0.10, green: 0.16, blue: 0.24), Color(red: 0.16, green: 0.12, blue: 0.20)],
        [Color(red: 0.20, green: 0.10, blue: 0.10), Color(red: 0.26, green: 0.16, blue: 0.10)],
        [Color(red: 0.08, green: 0.18, blue: 0.16), Color(red: 0.16, green: 0.20, blue: 0.14)],
        [Color(red: 0.16, green: 0.10, blue: 0.22), Color(red: 0.22, green: 0.14, blue: 0.18)],
    ]

    private var gradient: [Color] {
        gradientPairs[abs(name.hashValue) % gradientPairs.count]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(name.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
                    .tracking(0.5)
                    .lineLimit(2)
                Text("\(activeCount) Active")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 150, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Forecast Card

private struct ForecastCard: View {
    let venue: LikelyToOpenVenue
    let isWatched: Bool
    let onTapNotify: () -> Void

    private let palette = FeedPalette.liveFeedLight
    private let cardWidth: CGFloat = 200

    private var imageURL: URL? {
        guard let s = venue.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Probability from real backend metrics (availability_rate_14d × 100 + trend boost).
    private var pct: Int {
        if let p = venue.probability { return p }
        let r = venue.availabilityRate14d ?? 0
        let t = max(0, venue.trendPct ?? 0)
        return min(99, max(1, Int(round((r + min(0.08, t)) * 100))))
    }

    private var pctColor: Color {
        if pct >= 80 { return palette.accentRed }
        if pct >= 55 { return Color(red: 0.95, green: 0.55, blue: 0.10) }
        return palette.textSecondary
    }

    private var trendIcon: String? {
        guard let t = venue.trendPct else { return nil }
        if t > 0.05  { return "arrow.up.right" }
        if t < -0.05 { return "arrow.down.right" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = imageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Color(white: 0.86)
                            }
                        }
                    } else {
                        LinearGradient(
                            colors: [Color(white: 0.78), Color(white: 0.68)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: cardWidth, height: 120)
                .clipped()

                // Probability badge
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(pct)%")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                    Text("chance")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .tracking(0.3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(pctColor)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: 12,
                        bottomTrailingRadius: 0, topTrailingRadius: 0
                    )
                )
            }

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(venue.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    if let icon = trendIcon {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(icon.contains("up") ? Color(red: 0.18, green: 0.76, blue: 0.42) : palette.textTertiary)
                    }
                }

                // Data-driven reason (2 lines max)
                if let reason = venue.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundColor(palette.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Days context from rolling metrics
                if let days = venue.daysWithDrops {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(.system(size: 10))
                        Text("\(days)/14 days")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(days <= 3 ? palette.accentRed : palette.textTertiary)
                }

                Button { onTapNotify() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isWatched ? "checkmark" : "bell")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isWatched ? "Watching" : "Notify Me")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(isWatched ? palette.textTertiary : palette.accentRed)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background((isWatched ? Color.gray : palette.accentRed).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke((isWatched ? Color.gray : palette.accentRed).opacity(0.20), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.white)
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
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
            AsyncImage(url: resyUrl) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    LinearGradient(
                        colors: [AppTheme.surfaceElevated, AppTheme.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
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

    private var rarityInt: Int {
        guard let r = drop.rarityScore else { return 0 }
        return min(100, max(0, r <= 1 ? Int(r * 100) : Int(r.rounded())))
    }

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
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { AppTheme.surface }
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
                HStack(spacing: 4) {
                    if rarityInt > 0 {
                        Text("\(rarityInt)/100")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppTheme.scarcityRare)
                    }
                    Text(daysLabel)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
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
        guard let t = drop.trendPct, t != 0 else { return "" }
        return t > 0 ? "+\(Int(t))%" : "\(Int(t))%"
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
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { AppTheme.surface }
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
        return parts.joined(separator: " · ")
    }

    private var trendBadge: String? {
        guard let t = drop.trendPct, t > 15 else { return nil }
        return "+\(Int(t))% trend"
    }

    var body: some View {
        Button {
            if let url = resyUrl { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail
                Group {
                    if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                            else { AppTheme.surface }
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
        guard let t = drop.trendPct, t > 0 else { return "" }
        return "+\(Int(t))%"
    }

    private var neighborhoodStr: String {
        drop.neighborhood ?? (drop.location ?? "")
    }

    var body: some View {
        Button {
            if let url = resyUrl { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                            else { AppTheme.surface }
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
                }
                .frame(width: 120)
            }
        }
        .buttonStyle(.plain)
    }
}
