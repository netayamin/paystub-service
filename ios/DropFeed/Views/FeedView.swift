import SwiftUI

private enum QuietStreamEntry {
    /// Home stream: primary rows always offer **BOOK** when a Resy URL exists (Explore’s `explore_snag_available` is ignored there).
    case live(Drop, isPrimaryTier: Bool)
    case missed(JustMissedVenue)

    /// Stable list identity when the row set rotates (`liveListShuffleToken`).
    var streamRowIdentity: String {
        switch self {
        case .live(let d, let primary): return primary ? "live-p-\(d.id)" : "live-t-\(d.id)"
        case .missed(let v): return "missed-\(v.id)"
        }
    }
}

/// Hairline rule with centered **LIVE STREAM**, then status row (pulse + label / local clock).
private struct QuietCuratorLiveStreamDividerHeader: View {
    var hasBookableLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(CreamEditorialTheme.hairline)
                    .frame(height: 1)
                Text("LIVE STREAM")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .tracking(0.85)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .background(CreamEditorialTheme.canvas)
                Rectangle()
                    .fill(CreamEditorialTheme.hairline)
                    .frame(height: 1)
            }

            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(hasBookableLive ? CreamEditorialTheme.liveStreamPulseGreen : CreamEditorialTheme.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(hasBookableLive ? "JUST OPENED" : "LIVE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(hasBookableLive ? CreamEditorialTheme.liveStreamPulseGreen : CreamEditorialTheme.textTertiary)
                        .tracking(0.35)
                }
                Spacer(minLength: 12)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.clockString(for: context.date))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(CreamEditorialTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private static func clockString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm zzz"
        return f.string(from: date).uppercased()
    }
}

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    var onOpenSearch: (() -> Void)? = nil
    var onOpenExplore: (() -> Void)? = nil
    var onOpenProfile: (() -> Void)? = nil

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
        .background(CreamEditorialTheme.canvas)
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

    // MARK: - Feed home (live glance → trending carousel → meal list → Explore)

    private var trendingCardWidth: CGFloat {
        min(UIScreen.main.bounds.width - 48, 340)
    }

    /// Freshest-first pool for the auto-advancing live glance carousel.
    private var liveGlanceCarouselDrops: [Drop] {
        let sorted = vm.drops.sorted { a, b in
            if a.secondsSinceDetected != b.secondsSinceDetected {
                return a.secondsSinceDetected < b.secondsSinceDetected
            }
            return (a.snagScore ?? 0) > (b.snagScore ?? 0)
        }
        return Array(sorted.prefix(14))
    }

    /// Trending / hot / rare venues from the live board.
    private var trendingHotCarouselDrops: [Drop] {
        var out: [Drop] = []
        var seen = Set<String>()
        let scored = vm.drops.sorted { ($0.snagScore ?? 0) > ($1.snagScore ?? 0) }
        for d in scored {
            guard !seen.contains(d.id) else { continue }
            if d.feedHot == true
                || (d.snagScore ?? 0) >= 78
                || (d.trendPct ?? 0) > 12
                || d.feedsRareCarousel == true
            {
                out.append(d)
                seen.insert(d.id)
            }
            if out.count >= 10 { break }
        }
        if out.count < 3 {
            for d in vm.topDrops where out.count < 10 && !seen.contains(d.id) {
                out.append(d)
                seen.insert(d.id)
            }
        }
        return out
    }

    private var mealSectionTitle: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h >= 6 && h < 11 { return "Brunch & morning" }
        if h >= 11 && h < 15 { return "Lunch today" }
        if h >= 15 && h < 17 { return "Golden hour picks" }
        return "Tonight's restaurants"
    }

    /// Mix of still-bookable rows and claimed (`explore_snag_available == false`) so “Tonight” feels like real inventory churn.
    private var mealWindowDrops: [Drop] {
        let today = vm.todayDateStr
        func mentionsToday(_ d: Drop) -> Bool {
            if d.dateStr == today { return true }
            return d.slots.contains { $0.dateStr == today }
        }
        var pool = vm.drops.filter(mentionsToday)
        if pool.isEmpty { pool = vm.drops }

        func byScore(_ a: Drop, _ b: Drop) -> Bool {
            (a.snagScore ?? 0) > (b.snagScore ?? 0)
        }
        let claimed = pool.filter { $0.exploreSnagAvailable == false }.sorted(by: byScore)
        let open = pool.filter { $0.exploreSnagAvailable != false }.sorted(by: byScore)

        var out: [Drop] = []
        var seen = Set<String>()
        var oi = 0
        var ci = 0
        let limit = 8
        while out.count < limit {
            if oi < open.count {
                let d = open[oi]; oi += 1
                if !seen.contains(d.id) { out.append(d); seen.insert(d.id) }
            }
            guard out.count < limit else { break }
            if ci < claimed.count {
                let d = claimed[ci]; ci += 1
                if !seen.contains(d.id) { out.append(d); seen.insert(d.id) }
            }
            if oi >= open.count && ci >= claimed.count { break }
        }
        if out.count < limit {
            for d in open.dropFirst(oi) + claimed.dropFirst(ci) {
                guard out.count < limit else { break }
                if !seen.contains(d.id) { out.append(d); seen.insert(d.id) }
            }
        }
        return out
    }

    private var referenceFeedScroll: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CuratorTopBar(
                        lastRefreshed: vm.lastRefreshed,
                        lastScanFallback: vm.lastScanText,
                        onProfileTap: { onOpenProfile?() }
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                    if !quietCuratorHottestCarouselDrops.isEmpty {
                        quietCuratorHottestHeader
                        quietCuratorHottestCarousel(drops: quietCuratorHottestCarouselDrops)
                        Color.clear.frame(height: 24)
                    }

                    quietCuratorLiveStreamSection
                    quietCuratorExploreButton
                    quietCuratorTacticalForecast
                    Color.clear.frame(height: vm.newDropsCount > 0 ? 96 : 28)
                }
                // Critical: bounded width so HStacks/Text don't overflow past the viewport (clips leading).
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
        .background(CreamEditorialTheme.canvas)
    }

    /// Featured hero — left-mockup style single spotlight.
    private var editorialHeroDrop: Drop? {
        if let h = vm.heroCard, feedDropIsBookable(h) { return h }
        if let t = trendingHotCarouselDrops.first { return t }
        return liveGlanceCarouselDrops.first
    }

    private var editorialStreamDrops: [Drop] {
        let base = liveGlanceCarouselDrops.isEmpty ? vm.justDropped : liveGlanceCarouselDrops
        var seen = Set<String>()
        return base.filter { seen.insert($0.id).inserted }.prefix(18).map { $0 }
    }

    /// Full ranked board, deduped — live stream pulls **open** + **booked** from here so counts stay honest.
    private var quietCuratorStreamPool: [Drop] {
        var seen = Set<String>()
        return vm.drops.filter { seen.insert($0.id).inserted }
    }

    /// Live stream: **3 primary** rows from Resy-bookable drops (Explore “taken” can still appear here with a real **BOOK** CTA) + **1–2** true taken rows (`explore_snag_available == false` or missed).
    /// Depends on `liveListShuffleToken` and `lastRefreshed`.
    private var quietCuratorStreamEntries: [QuietStreamEntry] {
        _ = vm.liveListShuffleToken
        _ = vm.lastRefreshed

        let pool = quietCuratorStreamPool
        guard !pool.isEmpty else { return [] }

        let bookable = pool
            .filter { feedDropIsBookable($0) }
            .sorted { $0.secondsSinceDetected < $1.secondsSinceDetected }

        // Partition by Explore flag. `nil` is treated as open (API omitted field).
        let exploreOpen = bookable.filter { $0.exploreSnagAvailable != false }
        let exploreTaken = bookable.filter { $0.exploreSnagAvailable == false }

        let primaryTarget = 3
        let primaryTriple: [Drop] = {
            guard !bookable.isEmpty else { return [] }
            if exploreOpen.count >= primaryTarget {
                if exploreOpen.count == primaryTarget { return exploreOpen }
                let window = exploreOpen.count - primaryTarget
                let start = Int(vm.liveListShuffleToken % UInt64(window + 1))
                return Array(exploreOpen[start ..< (start + primaryTarget)])
            }
            var out = exploreOpen
            let need = primaryTarget - out.count
            if need > 0 {
                let used = Set(out.map(\.id))
                let fill = exploreTaken.filter { !used.contains($0.id) }
                if !fill.isEmpty {
                    if fill.count <= need {
                        out.append(contentsOf: fill)
                    } else {
                        let w = fill.count - need
                        let s = Int(vm.liveListShuffleToken % UInt64(w + 1))
                        out.append(contentsOf: fill[s ..< (s + need)])
                    }
                }
            }
            if out.count < primaryTarget {
                let used = Set(out.map(\.id))
                for d in bookable where !used.contains(d.id) {
                    out.append(d)
                    if out.count >= primaryTarget { break }
                }
            }
            return Array(out.prefix(primaryTarget))
        }()

        let primaryIds = Set(primaryTriple.map(\.id))

        var bookedEntries: [QuietStreamEntry] = []
        if let m = vm.justMissed.first {
            bookedEntries.append(.missed(m))
        }
        let takenSlots = max(0, 2 - bookedEntries.count)
        if takenSlots > 0 {
            let takenOnly = exploreTaken.filter { !primaryIds.contains($0.id) }
            if !takenOnly.isEmpty {
                if takenOnly.count <= takenSlots {
                    bookedEntries.append(contentsOf: takenOnly.map { .live($0, isPrimaryTier: false) })
                } else {
                    let w = takenOnly.count - takenSlots
                    let s = Int((vm.liveListShuffleToken >> 1) % UInt64(w + 1))
                    bookedEntries.append(contentsOf: takenOnly[s ..< (s + takenSlots)].map { .live($0, isPrimaryTier: false) })
                }
            }
        }

        var out: [QuietStreamEntry] = []
        out.append(contentsOf: primaryTriple.map { .live($0, isPrimaryTier: true) })

        if out.isEmpty {
            let raw = Array(pool.prefix(primaryTarget))
            if !raw.isEmpty {
                return raw.map { .live($0, isPrimaryTier: true) }
            }
            if let m = vm.justMissed.first { return [.missed(m)] }
            return []
        }

        out.append(contentsOf: bookedEntries)
        return out
    }

    /// Up to three hot / trending drops for the Quiet Curator hero carousel (“TOP 3 EXCLUSIVE”).
    private var quietCuratorHottestCarouselDrops: [Drop] {
        var out: [Drop] = []
        var seen = Set<String>()
        for d in trendingHotCarouselDrops {
            guard !seen.contains(d.id) else { continue }
            out.append(d)
            seen.insert(d.id)
            if out.count >= 3 { break }
        }
        if out.isEmpty {
            if let h = editorialHeroDrop { return [h] }
            if let f = vm.drops.first { return [f] }
            return []
        }
        if out.count < 3 {
            for d in vm.drops {
                guard !seen.contains(d.id) else { continue }
                out.append(d)
                seen.insert(d.id)
                if out.count >= 3 { break }
            }
        }
        return out
    }

    /// ~**4:5** portrait tiles; multi mode fits **~two cards + peek** (reference dimensions).
    private func quietCuratorHottestCarouselTileSize(trackWidth: CGFloat, dropCount: Int) -> (w: CGFloat, h: CGFloat) {
        let side: CGFloat = 18
        let gap: CGFloat = 12
        let peek: CGFloat = 14
        let inner = max(1, trackWidth) - 2 * side
        let aspect: CGFloat = 5.0 / 4.0
        if dropCount <= 1 {
            let w = min(max(168, inner * 0.58), inner - peek)
            return (w, w * aspect)
        }
        let w = max(132, (inner - gap - peek) / 2)
        return (w, w * aspect)
    }

    private func quietCuratorHottestCarouselCardChrome<V: View>(_ content: V) -> some View {
        let r: CGFloat = 10
        return content
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
    }

    @ViewBuilder
    private func quietCuratorHottestCarousel(drops: [Drop]) -> some View {
        let gap: CGFloat = 12
        let side: CGFloat = 18
        let outerH = quietCuratorHottestCarouselTileSize(
            trackWidth: UIScreen.main.bounds.width,
            dropCount: drops.count
        ).h

        GeometryReader { geo in
            let trackW = max(1, geo.size.width)
            let sz = quietCuratorHottestCarouselTileSize(trackWidth: trackW, dropCount: drops.count)

            if drops.count == 1, let only = drops.first {
                HStack {
                    Spacer(minLength: 0)
                    quietCuratorHottestCarouselCardChrome(
                        QuietCuratorHeroCard(
                            drop: only,
                            layoutHeight: sz.h,
                            useSharpRectangleBorder: false
                        )
                        .frame(width: sz.w, height: sz.h)
                    )
                    Spacer(minLength: 0)
                }
                .frame(width: trackW, height: sz.h, alignment: .top)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(drops, id: \.id) { drop in
                            quietCuratorHottestCarouselCardChrome(
                                QuietCuratorHeroCard(
                                    drop: drop,
                                    layoutHeight: sz.h,
                                    useSharpRectangleBorder: false
                                )
                                .frame(width: sz.w, height: sz.h)
                            )
                        }
                    }
                    .padding(.leading, side)
                    .padding(.trailing, side)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .frame(width: trackW, height: sz.h, alignment: .top)
            }
        }
        .frame(height: outerH)
        .frame(maxWidth: .infinity)
    }

    private var quietCuratorHottestHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("HOTTEST DROPS")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .tracking(0.15)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Text("TOP 3 EXCLUSIVE")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(CreamEditorialTheme.textTertiary)
                .tracking(0.55)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var quietCuratorLiveStreamSection: some View {
        let entries = quietCuratorStreamEntries
        return Group {
            if entries.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    QuietCuratorLiveStreamDividerHeader(
                        hasBookableLive: entries.contains {
                            if case .live(let d, let primary) = $0 {
                                return primary && feedDropIsBookable(d)
                            }
                            return false
                        }
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.streamRowIdentity) { idx, entry in
                            switch entry {
                            case .live(let drop, let isPrimaryTier):
                                let party = mockPreferredParty(for: drop)
                                QuietCuratorLiveStreamRow(
                                    drop: drop,
                                    preferredParty: party,
                                    available: isPrimaryTier ? feedDropIsBookable(drop) : feedMealRowIsAvailable(drop),
                                    waitMinutesLabel: quietCuratorWaitMinutesLabel(
                                        drop,
                                        requireExploreOpenForVanish: !isPrimaryTier
                                    ),
                                    seatingLabel: quietCuratorSeatingLabel(drop, party: party)
                                )
                                .staggeredAppear(index: idx, delayPerItem: 0.03)
                            case .missed(let venue):
                                QuietCuratorMissedStreamRow(venue: venue)
                                    .staggeredAppear(index: idx, delayPerItem: 0.03)
                            }
                        }
                    }
                    .background(CreamEditorialTheme.cardWhite)
                    .overlay(
                        Rectangle()
                            .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 20)
            }
        }
    }

    private var quietCuratorExploreButton: some View {
        Button {
            onOpenExplore?()
        } label: {
            Text("EXPLORE ALL LIVE DROPS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CreamEditorialTheme.exploreMutedLabel)
                .tracking(0.45)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(CreamEditorialTheme.cardWhite)
                .overlay(
                    Rectangle()
                        .stroke(CreamEditorialTheme.exploreHairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
    }

    private var quietCuratorTacticalForecast: some View {
        Group {
            if vm.likelyToOpen.isEmpty {
                EmptyView()
            } else {
                QuietCuratorTacticalForecastPanel(
                    venues: Array(vm.likelyToOpen.prefix(5)),
                    ctaTitle: quietCuratorForecastCTATitle,
                    onTapCTA: { quietCuratorOpenForecastCTA() }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
        }
    }

    private var quietCuratorForecastCTATitle: String {
        if let n = vm.drops.first?.name, !n.isEmpty {
            return "NEW DROP AT \(n.uppercased())"
        }
        return "NEW DROPS LIVE"
    }

    private func quietCuratorOpenForecastCTA() {
        guard let drop = vm.drops.first else {
            onOpenExplore?()
            return
        }
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else {
            onOpenExplore?()
            return
        }
        APIService.shared.trackBehaviorEvents(events: [
            BehaviorTrackEvent(
                eventType: "resy_opened",
                venueId: drop.venueKey,
                venueName: drop.name,
                notificationId: nil,
                market: drop.market
            )
        ])
        UIApplication.shared.open(url)
    }

    private func quietCuratorWaitMinutesLabel(_ drop: Drop, requireExploreOpenForVanish: Bool = true) -> String {
        if feedShouldShowVanishCountdown(drop, requireExploreOpen: requireExploreOpenForVanish) {
            let r = feedVanishSecondsRemaining(for: drop)
            let m = max(1, r / 60)
            return "\(m)m"
        }
        let s = drop.secondsSinceDetected
        if s < 120 { return "\(max(1, s))s" }
        return "\(max(1, s / 60))m"
    }

    private func quietCuratorSeatingLabel(_ drop: Drop, party: Int) -> String {
        let kind = drop.liveStreamVelocityBadge
            ?? drop.exploreVenuePill
            ?? drop.rowPrimaryMetric
            ?? "Table"
        return "\(kind) • \(party)ppl"
    }

    private func feedSectionHeader(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(SnagDesignSystem.darkTextMuted)
                .tracking(0.85)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundColor(.white)
        }
    }

    private var liveUpdatesCarouselSection: some View {
        Group {
            if liveGlanceCarouselDrops.isEmpty {
                EmptyView()
            } else {
                LiveDropsMarqueeTrain(drops: liveGlanceCarouselDrops)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var trendingHotCarouselSection: some View {
        Group {
            if trendingHotCarouselDrops.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    feedSectionHeader(eyebrow: "Trending now", title: "Hot & available")
                        .padding(.horizontal, 18)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(trendingHotCarouselDrops, id: \.id) { drop in
                                MarketLeaderHeroCard(drop: drop)
                                    .frame(width: trendingCardWidth, height: MarketLeaderHeroCard.cardHeight, alignment: .top)
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
        }
    }

    private var mealWindowSection: some View {
        Group {
            if mealWindowDrops.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 14) {
                   VStack(spacing: 12) {
                        ForEach(mealWindowDrops, id: \.id) { drop in
                            MockLiveNowRow(drop: drop, preferredParty: mockPreferredParty(for: drop))
                        }
                    }
                    .padding(.horizontal, 18)
                    .animation(.easeInOut(duration: 0.35), value: vm.lastRefreshed)
                }
            }
        }
    }

    private var viewAllExploreSection: some View {
        Button {
            onOpenExplore?()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("View all in Explore")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("Full grid, dates & neighborhoods")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SnagDesignSystem.darkTextMuted)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(SnagDesignSystem.coral)
            }
            .padding(16)
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
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

/// Hot hero CTA: show reservation window (first slot date + time) instead of generic “claim” copy.
private func feedHeroBookingCTALabel(for drop: Drop) -> String {
    let slot = drop.slots.first
    let ds = slot?.dateStr ?? drop.dateStr
    let datePart = friendlyDate(ds).map { $0.uppercased() }
    let timeRaw = (slot?.time ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let timePart = feedFormatTime12h(timeRaw)
    let hasTime = !timeRaw.isEmpty && timePart != "—"
    if let d = datePart, hasTime { return "\(d) · \(timePart)" }
    if let d = datePart { return d }
    if hasTime { return timePart }
    return "BOOK TABLE"
}

/// Live feed / TOP DROPS: ranked_board entries are current inventory; treat as bookable
/// whenever we still have a Resy URL. ``explore_snag_available`` is tuned for Explore
/// and can be false while the home feed card is still valid.
private func feedDropIsBookable(_ drop: Drop) -> Bool {
    let u = (drop.resyUrl ?? drop.slots.first?.resyUrl)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !u.isEmpty
}

/// Meal list + cards: respect Explore “taken” while still showing those rows in the mix.
private func feedMealRowIsAvailable(_ drop: Drop) -> Bool {
    feedDropIsBookable(drop) && drop.exploreSnagAvailable != false
}

/// Fast-vanish drops: show a live second countdown using server ``avg_drop_duration_seconds`` and age.
/// - Parameter requireExploreOpen: meal rows pass `true` so claimed inventory does not show a bogus timer; hero cards pass `false` while a Resy URL still works.
private func feedShouldShowVanishCountdown(_ drop: Drop, requireExploreOpen: Bool = true) -> Bool {
    if requireExploreOpen {
        guard feedMealRowIsAvailable(drop) else { return false }
    } else {
        guard feedDropIsBookable(drop) else { return false }
    }
    if drop.velocityUrgent == true { return true }
    if drop.speedTier == "fast" { return true }
    if let avg = drop.avgDropDurationSeconds, avg > 0, avg <= 240 { return true }
    return false
}

private func feedVanishWindowSeconds(for drop: Drop) -> Double {
    max(20, min(600, drop.avgDropDurationSeconds ?? 60))
}

private func feedVanishSecondsRemaining(for drop: Drop) -> Int {
    let w = feedVanishWindowSeconds(for: drop)
    return max(0, Int(w.rounded()) - drop.secondsSinceDetected)
}

private func feedTimeToClaimDisplay(for drop: Drop, requireExploreOpen: Bool = true) -> String {
    if feedShouldShowVanishCountdown(drop, requireExploreOpen: requireExploreOpen) {
        let r = feedVanishSecondsRemaining(for: drop)
        return r <= 0 ? "NOW" : "\(r)s"
    }
    return feedTimeToClaimLabel(for: drop)
}

/// Subtitle line for meal cards — prefer server display metrics, then composed fallback.
private func feedMealMetricsLine(for drop: Drop, preferredParty: Int) -> String {
    if let m = drop.latestDropSubtitleMetrics?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
        return m
    }
    if let m = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
        return m
    }
    if let m = drop.metricsSecondaryCompact?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
        return m
    }
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
    return "\(t) · \(party) · \(score)"
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
    let window = feedVanishWindowSeconds(for: drop)
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

// MARK: - Live glance strip + market leader hero

private func feedGlanceTopBadge(for drop: Drop) -> String {
    if drop.brandNewDrop == true || drop.showNewBadge == true { return "JUST DROPPED" }
    if let t = drop.exploreStatusTag, !t.isEmpty {
        let u = t.uppercased()
        return u.count <= 18 ? u : String(u.prefix(16)) + "…"
    }
    return "LIVE SIGNAL"
}

private func feedGlanceAgeLabel(for drop: Drop) -> String {
    let s = drop.secondsSinceDetected
    if s < 45 { return "just now" }
    if s < 3600 { return "\(max(1, s / 60))m ago" }
    return "\(s / 3600)h ago"
}

private func feedGlanceSeatPill(for drop: Drop) -> (text: String, emphasized: Bool) {
    if drop.slots.count == 1 { return ("1 LEFT", true) }
    let p = drop.partySizesAvailable.sorted()
    if let a = p.first, let b = p.last, a != b { return ("\(a)–\(b) SEATS", false) }
    if let a = p.first { return ("\(a) SEATS", false) }
    return ("OPEN", false)
}

/// Compact live-drop tile for the horizontal “train” marquee (~2.5 cards visible).
private struct LiveGlanceCompactCard: View {
    let drop: Drop

    private static let maroonPill = Color(red: 0.42, green: 0.14, blue: 0.16)

    private var pill: (text: String, emphasized: Bool) { feedGlanceSeatPill(for: drop) }

    private func openResy() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        Button(action: openResy) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(feedGlanceTopBadge(for: drop))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(SnagDesignSystem.salmonAccent)
                        .textCase(.uppercase)
                        .tracking(0.55)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(feedGlanceAgeLabel(for: drop))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.42))
                }
                Text(drop.name.uppercased())
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.8)
                Text(pill.text)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(pill.emphasized ? Color.white.opacity(0.95) : SnagDesignSystem.salmonAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(pill.emphasized ? Self.maroonPill : Color(white: 0.16))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Continuous horizontal scroll of compact live tiles (seamless loop).
private struct LiveDropsMarqueeTrain: View {
    let drops: [Drop]

    private let cardW: CGFloat = 152
    private let cardH: CGFloat = 108
    private let spacing: CGFloat = 10

    @State private var offset: CGFloat = 0

    private var loopItems: [(id: String, drop: Drop)] {
        var out: [(String, Drop)] = []
        for (i, d) in drops.enumerated() {
            out.append(("a-\(i)-\(d.id)", d))
        }
        for (i, d) in drops.enumerated() {
            out.append(("b-\(i)-\(d.id)", d))
        }
        return out
    }

    private var segmentWidth: CGFloat {
        guard !drops.isEmpty else { return 0 }
        return CGFloat(drops.count) * cardW + CGFloat(max(0, drops.count - 1)) * spacing
    }

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: spacing) {
                ForEach(loopItems, id: \.id) { item in
                    LiveGlanceCompactCard(drop: item.drop)
                        .frame(width: cardW, height: cardH)
                }
            }
            .offset(x: offset)
        }
        .frame(height: cardH)
        .clipped()
        .task(id: segmentWidth) {
            guard segmentWidth > 1 else { return }
            while !Task.isCancelled {
                offset = 0
                let pxPerSec: Double = 42
                let dur = max(14, min(48, Double(segmentWidth) / pxPerSec))
                withAnimation(.linear(duration: dur)) {
                    offset = -segmentWidth
                }
                try? await Task.sleep(nanoseconds: UInt64(dur * 1_000_000_000))
                var tr = Transaction()
                tr.disablesAnimations = true
                withTransaction(tr) {
                    offset = 0
                }
            }
        }
    }
}

/// Thin urgency meter — no `GeometryReader` (avoids flex/overflow glitches inside `ScrollView` rows).
private struct FeedClaimUrgencyBar: View {
    let progress: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.14))
            Capsule()
                .fill(SnagDesignSystem.coral)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: max(0.06, min(1, progress)), y: 1, anchor: .leading)
        }
        .frame(height: 2)
        .clipShape(Capsule())
    }
}

/// Only the numeric claim clock ticks — avoids relayouting the whole hero every second in `ScrollView`.
// MARK: - Quiet Curator home (reference layout)

private struct CuratorTopBar: View {
    let lastRefreshed: Date?
    let lastScanFallback: String
    var onProfileTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Wordmark — must shrink on narrow widths (single-line overflow was clipping the whole bar).
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.streamRed)
                Text("QUIET CURATOR")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .tracking(0.35)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(CreamEditorialTheme.liveDot)
                        .frame(width: 5, height: 5)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(CreamEditorialTheme.burgundy)
                        .tracking(0.45)
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(updatedLabel)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(CreamEditorialTheme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Button(action: onProfileTap) {
                Rectangle()
                    .fill(Color(white: 0.72))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updatedLabel: String {
        guard let d = lastRefreshed else { return "Updated —" }
        let s = Int(-d.timeIntervalSinceNow)
        if s < 2 { return "Updated just now" }
        if s < 60 { return "Updated \(s)s ago" }
        if s < 3600 { return "Updated \(s / 60)m ago" }
        let u = lastScanFallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? "Updated" : "Updated \(u)"
    }
}

private struct QuietCuratorHeroCard: View {
    let drop: Drop
    /// When set (carousel), drives card height and compact type; default tall hero for legacy layouts.
    var layoutHeight: CGFloat?
    /// Sharp 1pt `Rectangle` stroke; off when the carousel applies rounded chrome outside.
    var useSharpRectangleBorder: Bool = true

    /// Default height when `layoutHeight` is nil (single full-width hero elsewhere).
    fileprivate static let heroH: CGFloat = 372

    private var effectiveHeight: CGFloat { layoutHeight ?? Self.heroH }

    private var isCompactTile: Bool { (layoutHeight ?? .greatestFiniteMagnitude) < 280 }

    private var venueTitleSize: CGFloat {
        if isCompactTile { return 18 }
        if effectiveHeight < 340 { return 22 }
        return 28
    }

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var showHighDemand: Bool {
        drop.feedHot == true || (drop.snagScore ?? 0) >= 78 || (drop.trendPct ?? 0) > 12
    }

    private var neighborhoodCaps: String {
        (drop.neighborhood ?? drop.location ?? "NEW YORK").uppercased()
    }

    private var heroTimePill: String {
        let t = drop.slots.first?.time ?? ""
        let formatted = feedFormatTime12h(t)
        return formatted == "—" || formatted.isEmpty ? "EVENING" : formatted.uppercased()
    }

    private func openResy() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        APIService.shared.trackBehaviorEvents(events: [
            BehaviorTrackEvent(
                eventType: "resy_opened",
                venueId: drop.venueKey,
                venueName: drop.name,
                notificationId: nil,
                market: drop.market
            )
        ])
        UIApplication.shared.open(url)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .heroMuted) {
                        Color(white: 0.22)
                    }
                } else {
                    Color(white: 0.22)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.0),
                    .init(color: .black.opacity(0.15), location: 0.35),
                    .init(color: .black.opacity(0.72), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    if showHighDemand {
                        Text("HIGH DEMAND")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .tracking(0.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(CreamEditorialTheme.burgundy)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding(.top, isCompactTile ? 10 : 14)
                .padding(.horizontal, isCompactTile ? 10 : 14)

                Spacer(minLength: 0)

                Text(neighborhoodCaps)
                    .font(.system(size: isCompactTile ? 9 : 11, weight: .medium))
                    .foregroundColor(CreamEditorialTheme.heroNeighborhoodRed)
                    .tracking(0.55)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, isCompactTile ? 10 : 14)

                Text(drop.name.uppercased())
                    .font(.system(size: venueTitleSize, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .multilineTextAlignment(.leading)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, isCompactTile ? 10 : 14)
                    .padding(.top, 4)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)

                heroBottomChrome
                    .padding(.horizontal, isCompactTile ? 10 : 14)
                    .padding(.top, isCompactTile ? 10 : 14)
                    .padding(.bottom, isCompactTile ? 12 : 16)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Bounded box + clip so overlays (ZStack) cannot paint outside the card — fixes carousel edge bleed.
        .frame(maxWidth: .infinity, maxHeight: effectiveHeight)
        .clipped()
        .overlay {
            if useSharpRectangleBorder {
                Rectangle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
        }
    }

    /// Pills + BOOK: reflow when the carousel page is narrow so nothing clips past the card.
    @ViewBuilder
    private var heroBottomChrome: some View {
        let pills = HStack(alignment: .center, spacing: 6) {
            Text("TONIGHT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )
            Text(heroTimePill)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .overlay(
                    Rectangle()
                        .stroke(Color.white.opacity(0.45), lineWidth: 1)
                )
        }

        let book = Button(action: openResy) {
            Text("BOOK")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .tracking(0.55)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color.white)
        }
        .buttonStyle(.plain)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                pills
                Spacer(minLength: 6)
                book
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                pills
                book
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// Outlined **TAKEN** chip for inactive live-stream rows (no fill; brutalist sharp rect).
private struct QuietCuratorStreamTakenGhost: View {
    var body: some View {
        Text("TAKEN")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(CreamEditorialTheme.takenText)
            .tracking(0.4)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .stroke(CreamEditorialTheme.exploreHairline, lineWidth: 1)
            )
    }
}

private struct QuietCuratorLiveStreamRow: View {
    let drop: Drop
    let preferredParty: Int
    let available: Bool
    let waitMinutesLabel: String
    let seatingLabel: String

    private let accentBarWidth: CGFloat = 3

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private func openResy() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        APIService.shared.trackBehaviorEvents(events: [
            BehaviorTrackEvent(
                eventType: "resy_opened",
                venueId: drop.venueKey,
                venueName: drop.name,
                notificationId: nil,
                market: drop.market
            )
        ])
        UIApplication.shared.open(url)
    }

    /// Bookable rows: **JUST OPENED** (burgundy) vs **OPENED** (black). Claimed inventory: **BOOKED** (grey) — same inactive chrome as “just missed”.
    private var statusPrimary: String {
        if !available { return "BOOKED" }
        if drop.secondsSinceDetected < 120 { return "JUST OPENED" }
        return "OPENED"
    }

    private var statusPrimaryColor: Color {
        if !available { return CreamEditorialTheme.textTertiary }
        if drop.secondsSinceDetected < 120 { return CreamEditorialTheme.burgundy }
        return CreamEditorialTheme.textPrimary
    }

    private var agoLabel: String {
        let s = drop.secondsSinceDetected
        if s < 90 { return "\(max(1, s))s ago" }
        if s < 3600 { return "\(max(1, s / 60))m ago" }
        return "\(s / 3600)h ago"
    }

    private var agoLabelColor: Color {
        if available { return CreamEditorialTheme.textTertiary }
        return CreamEditorialTheme.textTertiary.opacity(0.75)
    }

    var body: some View {
        HStack(spacing: 0) {
            if available {
                Rectangle()
                    .fill(CreamEditorialTheme.burgundy)
                    .frame(width: accentBarWidth)
            }

            HStack(alignment: .center, spacing: 10) {
                Group {
                    if let url = imageURL {
                        CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .lightOnLight) {
                            Color(white: 0.9)
                        }
                    } else {
                        Color(white: 0.9)
                    }
                }
                .frame(width: 56, height: 56)
                .clipped()
                .grayscale(available ? 0 : 1)
                .opacity(available ? 1 : 0.72)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(statusPrimary)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(statusPrimaryColor)
                                .lineLimit(1)
                            Text(agoLabel)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(agoLabelColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        Text(drop.name.uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(available ? CreamEditorialTheme.textPrimary : CreamEditorialTheme.textSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if available {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("⚡️")
                                    .font(.system(size: 11))
                                Text(waitMinutesLabel)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(CreamEditorialTheme.burgundy)
                                Text(seatingLabel)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(CreamEditorialTheme.textSecondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)
                            }
                        } else {
                            Text("SOLD OUT")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(CreamEditorialTheme.textTertiary)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Group {
                    if available {
                        Button(action: openResy) {
                            Text("BOOK")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .tracking(0.45)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(CreamEditorialTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        QuietCuratorStreamTakenGhost()
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(available ? CreamEditorialTheme.cardWhite : CreamEditorialTheme.takenFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CreamEditorialTheme.hairline)
                .frame(height: 0.5)
        }
    }
}

private struct QuietCuratorMissedStreamRow: View {
    let venue: JustMissedVenue

    private var imageURL: URL? {
        guard let s = venue.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var agoLabel: String {
        guard let iso = venue.goneAt, let d = Drop.parseISO(iso) else { return "just now" }
        let sec = max(0, Int(-d.timeIntervalSinceNow))
        if sec < 90 { return "\(max(1, sec))s ago" }
        if sec < 3600 { return "\(max(1, sec / 60))m ago" }
        return "\(sec / 3600)h ago"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .lightOnLight) {
                        Color(white: 0.88)
                    }
                } else {
                    Color(white: 0.88)
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            .grayscale(1.0)
            .opacity(0.75)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text("JUST MISSED")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(CreamEditorialTheme.textTertiary)
                            .lineLimit(1)
                        Text(agoLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(CreamEditorialTheme.textTertiary.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Text(venue.name.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(CreamEditorialTheme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("SOLD OUT")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(CreamEditorialTheme.textTertiary)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            QuietCuratorStreamTakenGhost()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(CreamEditorialTheme.takenFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CreamEditorialTheme.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 14)
        }
    }
}

private struct QuietCuratorTacticalForecastPanel: View {
    let venues: [LikelyToOpenVenue]
    let ctaTitle: String
    var onTapCTA: () -> Void

    private var topVenues: [LikelyToOpenVenue] { Array(venues.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("TACTICAL FORECAST")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Text("HIGH PROBABILITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.streamRed)
                    .tracking(0.35)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(Array(topVenues.enumerated()), id: \.offset) { idx, v in
                    tacticalDarkRow(v)
                    if idx < topVenues.count - 1 {
                        Rectangle()
                            .fill(CreamEditorialTheme.tacticalDarkDivider)
                            .frame(height: 1)
                            .padding(.vertical, 12)
                    }
                }
            }

            Text("Forecast based on historical drop patterns and current cancellation velocity.")
                .font(.system(size: 10, weight: .regular))
                .italic()
                .foregroundColor(CreamEditorialTheme.tacticalDarkMeta)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onTapCTA) {
                Text(ctaTitle)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .tracking(0.35)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CreamEditorialTheme.burgundy)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CreamEditorialTheme.tacticalDarkSurface)
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func tacticalDarkRow(_ v: LikelyToOpenVenue) -> some View {
        let imgURL: URL? = {
            guard let s = v.imageUrl, !s.isEmpty else { return nil }
            return URL(dropFeedMediaString: s) ?? URL(string: s)
        }()

        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                if let url = imgURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                        Color(white: 0.28)
                    }
                } else {
                    Color(white: 0.28)
                }
            }
            .frame(width: 44, height: 44)
            .clipped()
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(CreamEditorialTheme.streamRed)
                    Text("SIGNAL: \(signalPhrase(for: v))")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(CreamEditorialTheme.tacticalDarkMeta)
                        .tracking(0.4)
                }
                Text(venueForecastHeadline(v))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.28))
        }
    }

    private func signalPhrase(for v: LikelyToOpenVenue) -> String {
        let p = v.probability ?? min(99, max(0, Int((v.availabilityRate14d ?? 0) * 100)))
        if p >= 70 { return "JUST NOW" }
        if p >= 45 { return "HIGH WATCH" }
        return "WATCHING"
    }

    private func venueForecastHeadline(_ v: LikelyToOpenVenue) -> String {
        let hint = (v.predictedDropTime ?? v.predictedDropHint ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let window = hint.isEmpty ? "TONIGHT" : hint.uppercased()
        return "\(v.name.uppercased()): 2PPL \(window)"
    }
}

private struct MarketLeaderTimeToClaimBadge: View {
    let drop: Drop

    var body: some View {
        HStack(spacing: 5) {
            Text(feedShouldShowVanishCountdown(drop, requireExploreOpen: false) ? "VANISHES" : "TIME TO CLAIM")
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.white.opacity(0.88))
                .tracking(0.45)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(feedTimeToClaimDisplay(for: drop, requireExploreOpen: false))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.48))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct MarketLeaderHeroCard: View {
    let drop: Drop

    /// Fixed height for horizontal carousel — parent must use the same value so `ScrollView` does not compress the card.
    static let cardHeight: CGFloat = 232

    private var imageURL: URL? {
        guard let s = drop.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var neighborhoodCaps: String {
        (drop.neighborhood ?? drop.location ?? "NYC").uppercased()
    }

    private var showVelocityBadge: Bool {
        drop.speedTier == "fast" || drop.velocityUrgent == true
    }

    private func executeClaim() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed photo (fixed bounds — never participates in text measurement).
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
            .frame(width: nil, height: Self.cardHeight)
            .frame(maxWidth: .infinity)
            .clipped()

            // Readable scrim: clear through ~upper half, then solid black toward bottom.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.0),
                    .init(color: .black.opacity(0.0), location: 0.48),
                    .init(color: .black.opacity(0.42), location: 0.52),
                    .init(color: .black.opacity(0.72), location: 0.7),
                    .init(color: .black.opacity(0.9), location: 0.88),
                    .init(color: .black.opacity(0.96), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: nil, height: Self.cardHeight)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)

            // Top badges — overlay only; does not squeeze the bottom stack.
            VStack {
                HStack(alignment: .top, spacing: 0) {
                    if showVelocityBadge {
                        Text("HIGH VELOCITY")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .tracking(0.5)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(SnagDesignSystem.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                    Spacer(minLength: 0)
                    MarketLeaderTimeToClaimBadge(drop: drop)
                }
                .padding(.top, 10)
                .padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Footer pinned to bottom — same baseline for every card in the carousel.
            VStack(alignment: .leading, spacing: 5) {
                Text(neighborhoodCaps)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.darkTextMuted)
                    .tracking(0.55)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(drop.name)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 2)

                FeedClaimUrgencyBar(progress: feedClaimUrgencyProgress(for: drop))

                Button(action: executeClaim) {
                    Text(feedHeroBookingCTALabel(for: drop))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(SnagDesignSystem.coral)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .tracking(0.3)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                        .padding(.horizontal, 6)
                        .background(SnagDesignSystem.darkElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Self.cardHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MockJustMissedCard: View {
    let venue: JustMissedVenue
    var editorialCream: Bool = false

    private var imageURL: URL? {
        guard let s = venue.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private let cardW: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(
                        url: url,
                        contentMode: .fill,
                        skeletonTone: editorialCream ? .lightOnLight : .darkCard
                    ) {
                        editorialCream ? CreamEditorialTheme.canvas : SnagDesignSystem.darkElevated
                    }
                } else {
                    editorialCream ? CreamEditorialTheme.canvas : SnagDesignSystem.darkElevated
                }
            }
            .frame(width: cardW, height: 86)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(editorialCream ? CreamEditorialTheme.textPrimary : SnagDesignSystem.darkTextPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(feedRelativeMissedLabel(venue.goneAt))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(editorialCream ? CreamEditorialTheme.textSecondary : SnagDesignSystem.darkTextMuted)
                    .tracking(0.35)
                if let nb = venue.neighborhood, !nb.isEmpty {
                    Text(nb.uppercased())
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(editorialCream ? CreamEditorialTheme.textTertiary : SnagDesignSystem.darkTextMuted)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(width: cardW, alignment: .leading)
            .background(editorialCream ? CreamEditorialTheme.cardWhite : Color(white: 0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    editorialCream ? CreamEditorialTheme.hairline : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(color: editorialCream ? CreamEditorialTheme.cardShadow : .clear, radius: 8, x: 0, y: 4)
    }
}

private struct FeedPredictWillOpenSection: View {
    let venues: [LikelyToOpenVenue]
    @ObservedObject var premium: PremiumManager
    var onNotify: (String) -> Void
    var isWatched: (String) -> Bool
    var editorialCream: Bool = false

    @State private var showPaywall = false

    private var freeLimit: Int { PremiumManager.freeLikelyToOpenLimit }
    private var freeVenues: [LikelyToOpenVenue] { Array(venues.prefix(freeLimit)) }
    private var lockedVenues: [LikelyToOpenVenue] { premium.isPremium ? [] : Array(venues.dropFirst(freeLimit)) }
    private var allVisible: [LikelyToOpenVenue] { premium.isPremium ? venues : freeVenues }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(editorialCream ? "PREDICTED TO OPEN" : "WE PREDICT WILL OPEN")
                    .font(editorialCream ? CreamEditorialTheme.sectionSans : .system(size: 13, weight: .heavy))
                    .foregroundColor(editorialCream ? CreamEditorialTheme.textPrimary : .white)
                    .tracking(editorialCream ? 0.85 : 0.6)
                Text("From live scans — tap the bell to get notified when we spot a table.")
                    .font(.system(size: 11))
                    .foregroundColor(editorialCream ? CreamEditorialTheme.textSecondary : SnagDesignSystem.darkTextMuted)
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
                            .foregroundColor(
                                editorialCream ? CreamEditorialTheme.peachBadgeText : SnagDesignSystem.salmonAccent
                            )
                            .frame(width: 148, height: 188)
                            .background(
                                editorialCream ? CreamEditorialTheme.cardWhite : Color(white: 0.14)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        editorialCream ? CreamEditorialTheme.hairline : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                            .shadow(
                                color: editorialCream ? CreamEditorialTheme.cardShadow : .clear,
                                radius: 10,
                                x: 0,
                                y: 4
                            )
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

    private func predictCard(_ venue: LikelyToOpenVenue) -> some View {
        let watched = isWatched(venue.name)
        let score = venue.probability.map { min(99, max(1, $0)) }
        let imgURL: URL? = {
            guard let s = venue.imageUrl, !s.isEmpty else { return nil }
            return URL(dropFeedMediaString: s) ?? URL(string: s)
        }()
        let hint = venue.predictedDropHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let window = venue.predictedDropTime?.trimmingCharacters(in: .whitespacesAndNewlines)

        return ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = imgURL {
                        CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                            Color(white: 0.16)
                        }
                    } else {
                        Color(white: 0.16)
                    }
                }
                .frame(width: 148, height: 188)
                .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.0), location: 0.0),
                        .init(color: .black.opacity(0.35), location: 0.45),
                        .init(color: .black.opacity(0.82), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 148, height: 188)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center) {
                        Text("FORECAST")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(Color.white.opacity(0.55))
                        Spacer()
                        if let s = score {
                            Text("\(s)")
                                .font(.system(size: 17, weight: .black))
                                .foregroundColor(SnagDesignSystem.mint)
                        }
                    }
                    Text(venue.name)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 1)
                    if let h = hint, !h.isEmpty {
                        Text(h)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(SnagDesignSystem.mint)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let w = window, !w.isEmpty, w != hint {
                        Text(w)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.78))
                            .lineLimit(2)
                    }
                    if (hint == nil || hint?.isEmpty == true), (window == nil || window?.isEmpty == true) {
                        if let d = venue.daysWithDrops {
                            Text("Tables \(d)× / 14d")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.72))
                        } else {
                            Text("Watch for releases")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.72))
                        }
                    }
                }
                .padding(10)
                .frame(width: 148, alignment: .leading)
            }
            .frame(width: 148, height: 188)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        editorialCream ? CreamEditorialTheme.hairline : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: editorialCream ? CreamEditorialTheme.cardShadow : .clear,
                radius: 12,
                x: 0,
                y: 6
            )

            Button {
                onNotify(venue.name)
            } label: {
                Image(systemName: watched ? "bell.fill" : "bell")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(
                        watched
                            ? (editorialCream ? CreamEditorialTheme.peachBadgeText : SnagDesignSystem.salmonAccent)
                            : .white
                    )
                    .padding(8)
                    .background(Color.black.opacity(editorialCream ? 0.38 : 0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .frame(width: 148, height: 188)
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

    /// Open slots vs server “taken” flag for the meal mix.
    private var available: Bool { feedMealRowIsAvailable(drop) }
    private var badges: [MockFeedBadge] { signalStreamRowTags(for: drop, bookable: available) }

    private let rowHeight: CGFloat = 122

    private func openResy() {
        let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl ?? ""
        guard !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let url = imageURL {
                    CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                        Color(white: 0.16)
                    }
                } else {
                    Color(white: 0.16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.0),
                    .init(color: .black.opacity(0.0), location: 0.5),
                    .init(color: .black.opacity(0.44), location: 0.64),
                    .init(color: .black.opacity(0.9), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if !available {
                            Text("CLAIMED")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundColor(.white)
                                .tracking(0.4)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Capsule())
                        }
                        if available, let v = drop.velocityPrimaryLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                            Text(v.uppercased())
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundColor(SnagDesignSystem.velocityAmber)
                                .lineLimit(1)
                        }
                    }

                    Text(drop.name)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                        .shadow(color: .black.opacity(0.55), radius: 6, x: 0, y: 2)

                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feedMealMetricsLine(for: drop, preferredParty: preferredParty))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.78))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                            if available && feedShouldShowVanishCountdown(drop) {
                                Text("Vanishes in \(feedVanishSecondsRemaining(for: drop))s")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(SnagDesignSystem.coral)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    if !badges.isEmpty {
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(Array(badges.prefix(2).enumerated()), id: \.offset) { _, badge in
                                MockBadgePill(badge: badge)
                            }
                        }
                    }
                    if available {
                        Button(action: openResy) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 46, height: 44)
                                .background(SnagDesignSystem.coral)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else if let fresh = drop.serverFreshnessLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !fresh.isEmpty {
                        Text(fresh.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(Color.white.opacity(0.6))
                            .multilineTextAlignment(.trailing)
                    } else {
                        let s = drop.secondsSinceDetected
                        Text(s < 90 ? "JUST NOW" : "\(max(1, s / 60))M AGO")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(Color.white.opacity(0.55))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .opacity(available ? 1 : 0.88)
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
        return URL(dropFeedMediaString: s) ?? URL(string: s)
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
        if let h = venue.predictedDropHint, !h.isEmpty {
            return h.uppercased()
        }
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
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.0),
                    .init(color: .black.opacity(0.0), location: 0.5),
                    .init(color: .black.opacity(0.32), location: 0.64),
                    .init(color: .black.opacity(0.82), location: 1.0)
                ],
                startPoint: .top,
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
