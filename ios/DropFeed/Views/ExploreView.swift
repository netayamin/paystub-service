import SwiftUI

/// Explore tab — discovery layout: swipeable date header, likely-to-drop, hot areas, time tabs, two-column grid.
struct ExploreView: View {
    @ObservedObject var vm: SearchViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager

    @State private var gridTimeTab: ExploreGridTimeTab = .evening
    @State private var hypeSortReversed = false
    /// Page index aligned with `SearchViewModel.dateOptions` (next 14 days).
    @State private var exploreDatePageIndex: Int = 0

    /// Fixed grid cell geometry so every card matches; spacing is gap between cells.
    private let gridColumnSpacing: CGFloat = 14
    private let gridRowSpacing: CGFloat = 20
    /// Single card height: image + title/meta overlaid (no text outside the rounded rect).
    private let gridCardHeight: CGFloat = 248

    var body: some View {
        // Date pager sits OUTSIDE the vertical ScrollView so horizontal swipes are not
        // stolen by the parent scroll view (TabView + ScrollView gesture conflict).
        VStack(alignment: .leading, spacing: 0) {
            exploreDateStrip
                .padding(.top, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let err = vm.error {
                        errorBanner(err).padding(.top, 12)
                    }
                    likelyToDropCard
                        .padding(.top, 14)
                    hotAreasCard
                        .padding(.top, 12)
                    gridChrome
                        .padding(.top, 20)
                    gridSection
                        .padding(.top, 16)
                        .padding(.horizontal, 4)
                    Color.clear.frame(height: 88)
                }
                .padding(.horizontal, 18)
            }
        }
        .background(SnagDesignSystem.exploreCanvas.ignoresSafeArea())
        .onAppear {
            vm.exploreTabActive = true
            vm.selectedMealPreset = nil
            vm.isSearchActive = true
            normalizeExploreSelectedDateIfNeeded()
            syncExploreDatePageWithSelection()
            vm.startPolling()
        }
        .onDisappear {
            vm.exploreTabActive = false
            vm.stopPolling()
        }
        .onChange(of: vm.selectedDates) { _, _ in
            syncExploreDatePageWithSelection()
        }
    }

    /// Drives the date pager; setter runs on every swipe so we always sync `selectedDates` and refetch (TabView + `onChange` is unreliable).
    private var exploreDatePageSelection: Binding<Int> {
        Binding(
            get: { exploreDatePageIndex },
            set: { newIdx in
                exploreDatePageIndex = newIdx
                exploreApplyPageIndex(newIdx)
            }
        )
    }

    // MARK: - Swipeable date header

    private var exploreDateStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                if vm.dateOptions.isEmpty {
                    Text("Select a day")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                } else {
                    TabView(selection: exploreDatePageSelection) {
                        ForEach(Array(vm.dateOptions.enumerated()), id: \.element.dateStr) { idx, opt in
                            Text(exploreSwipeDateTitle(for: opt))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                                .lineLimit(1)
                                .minimumScaleFactor(0.88)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    // One line of headline; avoid minHeight + maxHeight filling extra black space.
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)

                    exploreDatePageDots
                }
            }
            .padding(.horizontal, 18)

            HStack {
                Text("LIVE NOW")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(SnagDesignSystem.exploreCoralSolid.opacity(0.95))
                    .tracking(0.55)
                Spacer()
                Text("• REAL-TIME")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                    .tracking(0.35)
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background(SnagDesignSystem.exploreCanvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.55), radius: 16, x: 0, y: 10)
    }

    private var exploreDatePageDots: some View {
        let n = vm.dateOptions.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { i in
                    Circle()
                        .fill(i == exploreDatePageIndex ? SnagDesignSystem.exploreCoralSolid : Color.white.opacity(0.22))
                        .frame(width: i == exploreDatePageIndex ? 7 : 5, height: i == exploreDatePageIndex ? 7 : 5)
                }
            }
        }
        .frame(maxWidth: 96)
    }

    /// e.g. "TODAY • OCT 24" or "WED • NOV 02"
    private func exploreSwipeDateTitle(for opt: (dateStr: String, monthAbbrev: String, dayNum: String)) -> String {
        let cal = Calendar.current
        let parts = opt.dateStr.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else {
            return "\(opt.monthAbbrev) \(opt.dayNum)"
        }
        var c = DateComponents()
        c.year = y
        c.month = mo
        c.day = d
        guard let date = cal.date(from: c) else { return "\(opt.monthAbbrev) \(opt.dayNum)" }
        let prefix: String
        if cal.isDateInToday(date) {
            prefix = "TODAY"
        } else if cal.isDateInTomorrow(date) {
            prefix = "TOMORROW"
        } else {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "EEE"
            prefix = df.string(from: date).uppercased()
        }
        return "\(prefix) • \(opt.monthAbbrev) \(opt.dayNum)"
    }

    private func syncExploreDatePageWithSelection() {
        guard let sel = vm.selectedDates.first,
              let idx = vm.dateOptions.firstIndex(where: { $0.dateStr == sel }) else { return }
        if idx != exploreDatePageIndex {
            exploreDatePageIndex = idx
        }
    }

    private func exploreApplyPageIndex(_ idx: Int) {
        guard vm.dateOptions.indices.contains(idx) else { return }
        let ds = vm.dateOptions[idx].dateStr
        if vm.selectedDates == Set([ds]) { return }
        vm.selectedDates = Set([ds])
        Task { await vm.loadResults() }
    }

    /// Keep one day selected and inside the strip’s range (e.g. after midnight or legacy multi-day state).
    private func normalizeExploreSelectedDateIfNeeded() {
        let valid = Set(vm.dateOptions.map(\.dateStr))
        let hit = vm.selectedDates.filter { valid.contains($0) }
        if hit.isEmpty, let first = vm.dateOptions.first?.dateStr {
            vm.selectedDates = [first]
        } else if vm.selectedDates.count > 1, let one = hit.sorted().first {
            vm.selectedDates = [one]
        } else if hit.count == 1, vm.selectedDates != Set(hit) {
            vm.selectedDates = Set(hit)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.system(size: 13))
        }
        .foregroundColor(SnagDesignSystem.exploreCoralSolid)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SnagDesignSystem.exploreCoralSolid.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Likely to drop

    @ViewBuilder
    private var likelyToDropCard: some View {
        if let venue = vm.likelyToOpen.first {
            let imgURL: URL? = {
                guard let s = venue.imageUrl, !s.isEmpty else { return nil }
                return URL(dropFeedMediaString: s) ?? URL(string: s)
            }()
            let score = venue.probability.map { min(99, max(1, $0)) }
            let primaryWhen = exploreLikelyTimingPrimary(venue)
            let secondaryWhen = exploreLikelyTimingSecondary(venue)

            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let url = imgURL {
                            CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .darkCard) {
                                Color(white: 0.14)
                            }
                        } else {
                            Color(white: 0.14)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 152)
                    .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.0), location: 0.25),
                            .init(color: .black.opacity(0.55), location: 0.72),
                            .init(color: .black.opacity(0.88), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 152)
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center) {
                            HStack(spacing: 6) {
                                Image(systemName: "eye")
                                    .font(.system(size: 11))
                                Text("LIKELY TO DROP")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.6)
                            }
                            .foregroundColor(Color.white.opacity(0.65))
                            Spacer()
                            if let s = score {
                                VStack(alignment: .trailing, spacing: 0) {
                                    Text("SCORE")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(Color.white.opacity(0.5))
                                    Text("\(s)")
                                        .font(.system(size: 18, weight: .black))
                                        .foregroundColor(SnagDesignSystem.mint)
                                }
                            }
                        }
                        Text(venue.name)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                        if let nb = venue.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines), !nb.isEmpty {
                            Text(nb.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.72))
                        }
                    }
                    .padding(14)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("When")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                        .tracking(0.5)

                    Text(primaryWhen)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.mint)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sec = secondaryWhen {
                        Text(sec)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    exploreLikelyMetricsRow(venue)

                    if let compact = venue.forecastMetricsCompact?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !compact.isEmpty {
                        Text(compact)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                            .lineLimit(2)
                    }

                    if let r = venue.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
                        Text(r)
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.72))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .center) {
                        Text(exploreLikelyLastUpdatedLine())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                        Spacer()
                        Button {
                            savedVM.toggleWatch(venue.name)
                        } label: {
                            Text(savedVM.isWatched(venue.name) ? "Watching" : "Watch")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(SnagDesignSystem.exploreCoralSolid)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    private func exploreLikelyTimingPrimary(_ venue: LikelyToOpenVenue) -> String {
        if let h = venue.predictedDropHint?.trimmingCharacters(in: .whitespacesAndNewlines), !h.isEmpty {
            return h
        }
        if let t = venue.predictedDropTime?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return "We’re learning timing from live scans — check back as we collect more drops."
    }

    private func exploreLikelyTimingSecondary(_ venue: LikelyToOpenVenue) -> String? {
        let h = venue.predictedDropHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let t = venue.predictedDropTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !h.isEmpty && !t.isEmpty && h.caseInsensitiveCompare(t) != .orderedSame {
            return t
        }
        return nil
    }

    private func exploreLikelyLastUpdatedLine() -> String {
        guard let d = vm.lastUpdated else {
            return vm.isRefreshing ? "Updating…" : "Live scans"
        }
        let s = Int(-d.timeIntervalSinceNow)
        if s < 8 { return "Updated just now" }
        if s < 120 { return "Updated \(s)s ago" }
        if s < 3600 { return "Updated \(s / 60)m ago" }
        return "Updated \(s / 3600)h ago"
    }

    @ViewBuilder
    private func exploreLikelyMetricsRow(_ venue: LikelyToOpenVenue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let c = venue.confidence?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                    Text(c.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(exploreConfidenceColor(c))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                if let d = venue.daysWithDrops {
                    Text("\(d) active days / 14")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text(FeedMetricLabels.scarcityStatus(rate: venue.availabilityRate14d))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                if venue.rarityScore != nil {
                    Text(FeedMetricLabels.rarityHeadline(score: venue.rarityScore))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.7))
                }
                if let tp = venue.trendPct {
                    let normalized = (tp >= -1 && tp <= 1) ? tp * 100 : tp
                    Text(String(format: "%+.0f%% vs last week", normalized))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(normalized >= 1 ? SnagDesignSystem.mint : SnagDesignSystem.exploreSecondaryLabel)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func exploreConfidenceColor(_ raw: String) -> Color {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return SnagDesignSystem.mint
        case "low": return SnagDesignSystem.exploreSecondaryLabel
        default: return Color.white.opacity(0.85)
        }
    }

    // MARK: - Hot areas

    private var hotAreasCard: some View {
        let areas = topNeighborhoods
        return Group {
            if !areas.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                        Text("HOT AREAS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                    }
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)

                    HStack(spacing: 10) {
                        ForEach(areas, id: \.self) { n in
                            Text(n.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(white: 0.16))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var topNeighborhoods: [String] {
        let names = vm.rankedResults.compactMap { $0.neighborhood?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value > $1.value }.prefix(2).map(\.key)
    }

    // MARK: - Grid chrome

    private var gridChrome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(ExploreGridTimeTab.allCases, id: \.self) { tab in
                    let on = gridTimeTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { gridTimeTab = tab }
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.title)
                                .font(.system(size: 11, weight: on ? .bold : .semibold))
                                .foregroundColor(on ? .white : SnagDesignSystem.exploreSecondaryLabel)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Rectangle()
                                .fill(on ? SnagDesignSystem.exploreCoralSolid : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Spacer()
                Text("RANKED BY HYPE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                    .tracking(0.6)
                Button {
                    hypeSortReversed.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var gridSection: some View {
        let items = gridDrops
        if items.isEmpty, !vm.rankedResults.isEmpty {
            Text("No tables in this time band. Try the other tab or another day.")
                .font(.system(size: 13))
                .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if !items.isEmpty {
            // Explicit 2-column rows avoid LazyVGrid + AsyncImage measuring bugs that overlap cells.
            VStack(alignment: .leading, spacing: gridRowSpacing) {
                ForEach(Array(pairedGridDrops(items).enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: gridColumnSpacing) {
                        ForEach(pair) { drop in
                            exploreGridCell(drop)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        if pair.count == 1 {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    /// Pairs drops for a 2-column layout (last row may be a single item).
    private func pairedGridDrops(_ items: [Drop]) -> [[Drop]] {
        stride(from: 0, to: items.count, by: 2).map { i in
            if i + 1 < items.count {
                return [items[i], items[i + 1]]
            }
            return [items[i]]
        }
    }

    private var gridDrops: [Drop] {
        var list = vm.rankedResults
        list = list.filter { dropMatchesGridTab($0, tab: gridTimeTab) }
        if hypeSortReversed {
            list.reverse()
        }
        return list
    }

    private func exploreGridCell(_ drop: Drop) -> some View {
        let url = resyURL(for: drop)
        return Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: gridCardHeight)
                    .overlay {
                        gridThumb(drop)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.28), .black.opacity(0.9)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity)
                .frame(height: gridCardHeight)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 5) {
                    Text(gridTimeOverlay(drop))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(drop.name)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.88)
                    Text((drop.neighborhood ?? drop.location ?? "").uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.68))
                        .tracking(0.4)
                        .lineLimit(1)
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: insightIcon(for: drop))
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.72))
                            .padding(.top, 2)
                        Text(insightLine(for: drop))
                            .font(.system(size: 10))
                            .foregroundColor(Color.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: gridCardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if let badge = gridImageBadge(drop) {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(white: 0.32), lineWidth: 1))
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gridThumb(_ drop: Drop) -> some View {
        if let s = drop.imageUrl, let u = URL(string: s) {
            CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .darkCard) {
                Color(white: 0.2)
            }
        } else {
            Color(white: 0.2)
        }
    }

    private func gridImageBadge(_ drop: Drop) -> String? {
        if let h = hypeBadgeText(drop) { return h }
        if drop.brandNewDrop == true { return "New Drop" }
        if drop.exploreStatusTag == "JUST DROPPED" { return "New Drop" }
        if let t = drop.exploreStatusTag, !t.isEmpty { return t }
        if drop.velocityUrgent == true { return "Fast Drop" }
        return nil
    }

    private func hypeBadgeText(_ drop: Drop) -> String? {
        if let s = drop.snagScore { return "\(s)% Hype" }
        if let r = drop.rarityPoints, r > 0 { return "\(r)% Hype" }
        return nil
    }

    private func gridTimeOverlay(_ drop: Drop) -> String {
        let t = formatFirstSlotTime(drop)
        let seats = seatsLabelShort
        if t.isEmpty { return seats }
        return "\(t) • \(seats)"
    }

    private var seatsLabelShort: String {
        switch vm.explorePartySegment {
        case .two: return "2 Seats"
        case .four: return "4 Seats"
        case .anyParty: return "Open seats"
        }
    }

    private func insightIcon(for drop: Drop) -> String {
        if (drop.ratingAverage ?? 0) >= 4.5 { return "star.fill" }
        if drop.velocityPrimaryLabel != nil { return "clock.fill" }
        return "fork.knife"
    }

    private func insightLine(for drop: Drop) -> String {
        let sorted = savedVM.watchedVenues.sorted()
        if !sorted.isEmpty {
            let idx = abs(drop.id.hashValue) % sorted.count
            let w = sorted[idx]
            return "Similar to your \(w.capitalized) watch"
        }
        if let m = drop.topOpportunitySubtitleLine, !m.isEmpty, m.count < 52 { return m }
        if let r = drop.rareDropDetailLine, !r.isEmpty, r.count < 52 { return r }
        if (drop.ratingAverage ?? 0) >= 4.5 { return "Highly rated" }
        return "Prime-time demand"
    }

    // MARK: - Time tab + slots

    private func dropMatchesGridTab(_ drop: Drop, tab: ExploreGridTimeTab) -> Bool {
        guard let mins = primarySlotMinutes(drop) else { return tab == .evening }
        let eveningStart = 17 * 60 + 30
        let eveningEnd = 21 * 60 + 30
        let lateStart = 21 * 60 + 45
        switch tab {
        case .evening:
            return mins >= eveningStart && mins <= eveningEnd
        case .lateNight:
            return mins >= lateStart || mins < eveningStart
        }
    }

    private func primarySlotMinutes(_ drop: Drop) -> Int? {
        guard let t = drop.slots.first?.time, !t.isEmpty else { return nil }
        let parts = t.split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return nil }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        return h * 60 + m
    }

    private func formatFirstSlotTime(_ drop: Drop) -> String {
        guard let t = drop.slots.first?.time, !t.isEmpty else { return "" }
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t }
        let mm = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        if mm > 0 { return String(format: "%d:%02d %@", h12, mm, ap) }
        return "\(h12) \(ap)"
    }

    private func resyURL(for drop: Drop) -> URL? {
        let s = drop.resyUrl ?? drop.slots.first?.resyUrl ?? ""
        return URL(string: s)
    }
}

// MARK: - Grid time tabs

private enum ExploreGridTimeTab: CaseIterable {
    case evening
    case lateNight

    var title: String {
        switch self {
        case .evening: return "EVENING (5:30-9:30)"
        case .lateNight: return "LATE NIGHT (9:45+)"
        }
    }
}

#Preview {
    ExploreView(
        vm: SearchViewModel(),
        savedVM: SavedViewModel(),
        premium: PremiumManager()
    )
}
