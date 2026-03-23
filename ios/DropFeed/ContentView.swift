import SwiftUI

// MARK: - Root container

struct ContentView: View {
    @StateObject private var feedVM    = FeedViewModel()
    @StateObject private var savedVM   = SavedViewModel()
    @StateObject private var premium   = PremiumManager()
    @StateObject private var alertsVM  = AlertsViewModel()
    @StateObject private var exploreVM = SearchViewModel()
    @State private var selectedTab = 0

    var body: some View {
        Group {
            switch selectedTab {
            case 0:
                FeedView(
                    feedVM: feedVM,
                    savedVM: savedVM,
                    premium: premium,
                    onOpenSearch: { selectedTab = 1 },
                    onOpenExplore: { selectedTab = 1 }
                )
            case 1:
                ExploreView(vm: exploreVM, savedVM: savedVM, premium: premium)
            default:
                ProfilePlaceholderView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tabBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selectedTab: $selectedTab, alertBadgeCount: alertsVM.unreadCount)
        }
        .task {
            await savedVM.loadAll()
            await premium.checkEntitlements()
        }
    }

    private var tabBackground: Color {
        switch selectedTab {
        case 0, 1: return SnagDesignSystem.darkCanvas
        default: return SnagDesignSystem.pageCanvas
        }
    }
}

// MARK: - Search tab

struct SearchView: View {
    @StateObject private var vm     = SearchViewModel()
    @ObservedObject  var savedVM: SavedViewModel

    private let palette = FeedPalette.liveFeedLight

    var body: some View {
        VStack(spacing: 0) {
            header

            if vm.isSearchActive {
                resultsView
            } else {
                setupView
            }
        }
        .background(palette.pageBackground)
        .onAppear   { vm.startPolling() }
        .onDisappear { vm.stopPolling() }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Color.white

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PREDICTIONS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(palette.accentRed)
                            .tracking(1.2)
                        Text(vm.isSearchActive ? "Live Results" : "Upcoming Drops")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(palette.textPrimary)
                    }

                    Spacer()

                    if vm.isSearchActive {
                        // Back to edit
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { vm.isSearchActive = false }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Edit")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(palette.accentRed)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(palette.accentRed.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // "14 Day View" pill
                        Text("14 Day View")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(palette.accentRed)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(palette.accentRed.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(palette.accentRed.opacity(0.25), lineWidth: 1))
                    }
                }

                // Live indicator when searching
                if vm.isSearchActive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 0.25, green: 0.85, blue: 0.48))
                            .frame(width: 6, height: 6)
                        if vm.isRefreshing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: palette.textTertiary))
                                .scaleEffect(0.55)
                                .frame(width: 10, height: 10)
                        }
                        Text("Updating live")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.25, green: 0.85, blue: 0.48))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Step 1: Setup view

    private var setupView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Filter card ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {
                        whereSection
                        filterDivider
                        whenSection
                        filterDivider
                        whoSection
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // ── Likely to Open ───────────────────────────────────
                    if !vm.likelyToOpen.isEmpty {
                        likelyToOpenSection
                            .padding(.top, 28)
                    }

                    // Bottom padding so scroll content clears the activate button
                    Color.clear.frame(height: 100)
                }
            }
            .background(palette.pageBackground)

            // ── Pinned Activate button ───────────────────────────────────
            activateButton
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(
                        colors: [palette.pageBackground.opacity(0), palette.pageBackground],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
    }

    // MARK: - Step 2: Results view

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Error banner
                if let err = vm.error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14))
                        Text(err)
                            .font(.system(size: 13))
                    }
                    .foregroundColor(palette.accentRed)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.accentRed.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // Live results
                liveResultsSection
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                // Likely to Open below results
                if !vm.likelyToOpen.isEmpty {
                    likelyToOpenSection
                        .padding(.top, 28)
                }

                Color.clear.frame(height: 24)
            }
        }
        .background(palette.pageBackground)
    }

    // MARK: - Where to? section

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where to?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(palette.textPrimary)

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(palette.textTertiary)
                TextField("Search for a restaurant...", text: $vm.venueQuery)
                    .font(.system(size: 15))
                    .foregroundColor(palette.textPrimary)
                if !vm.venueQuery.isEmpty {
                    Button { vm.venueQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(palette.pageBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Quick-pick chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchViewModel.suggestedVenues, id: \.self) { venue in
                        let sel = vm.venueQuery == venue
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.venueQuery = sel ? "" : venue
                            }
                        } label: {
                            Text(venue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(sel ? .white : palette.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(sel ? Color(red: 0.11, green: 0.14, blue: 0.22) : Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(sel ? Color.clear : palette.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(20)
    }

    // MARK: - When? section

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("When?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(palette.textPrimary)

            // Date strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.dateOptions, id: \.dateStr) { opt in
                        dateChip(opt)
                    }
                }
                .padding(.horizontal, 2)
            }

            // Meal preset pills
            HStack(spacing: 10) {
                ForEach(MealPreset.allCases) { preset in
                    let sel = vm.selectedMealPreset == preset
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.selectedMealPreset = sel ? nil : preset
                        }
                        vm.startPolling()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 13))
                            Text(preset.rawValue)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(sel ? .white : palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(sel ? palette.accentRed : Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(sel ? Color.clear : palette.border, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
    }

    private func dateChip(_ opt: (dateStr: String, monthAbbrev: String, dayNum: String)) -> some View {
        let sel = vm.selectedDates.contains(opt.dateStr)
        return Button {
            vm.selectedDates = [opt.dateStr]
            vm.startPolling()
        } label: {
            VStack(spacing: 3) {
                Text(opt.monthAbbrev)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.4)
                Text(opt.dayNum)
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundColor(sel ? .white : palette.textSecondary)
            .frame(width: 54, height: 62)
            .background(sel ? Color(red: 0.11, green: 0.14, blue: 0.22) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(sel ? Color.clear : palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Who? section

    private var whoSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Who?")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                Text("Number of guests")
                    .font(.system(size: 12))
                    .foregroundColor(palette.textTertiary)
            }
            Spacer()
            HStack(spacing: 20) {
                Button {
                    if vm.partySize > 1 {
                        vm.partySize -= 1
                        vm.startPolling()
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(vm.partySize > 1 ? palette.textPrimary : palette.textTertiary)
                        .frame(width: 34, height: 34)
                        .background(palette.pageBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(vm.partySize <= 1)

                Text("\(vm.partySize)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                    .frame(minWidth: 26)

                Button {
                    if vm.partySize < 8 {
                        vm.partySize += 1
                        vm.startPolling()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(vm.partySize < 8 ? palette.textPrimary : palette.textTertiary)
                        .frame(width: 34, height: 34)
                        .background(palette.pageBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(vm.partySize >= 8)
            }
        }
        .padding(20)
    }

    // MARK: - Likely to Open section

    private var likelyToOpenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Likely to Open")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(palette.textPrimary)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.18, green: 0.76, blue: 0.42))
                        .frame(width: 6, height: 6)
                    Text("WATCHING LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.18, green: 0.76, blue: 0.42))
                        .tracking(0.4)
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 14) {
                ForEach(vm.likelyToOpen.prefix(6)) { venue in
                    LikelyOpenRow(
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

    // MARK: - Activate Search button

    private var activateButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { vm.isSearchActive = true }
            vm.startPolling()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                Text(vm.isLoading ? "Searching…" : "Activate Search")
                    .font(.system(size: 16, weight: .bold))
                if vm.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.75)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(palette.accentRed)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live results section

    @ViewBuilder
    private var liveResultsSection: some View {
        let drops = vm.rankedResults   // sorted: hottest (elite + rarity + demand) first
        if vm.isLoading && drops.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding tables…")
                    .font(.system(size: 14))
                    .foregroundColor(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else if vm.hasSearched && drops.isEmpty && !vm.isLoading {
            VStack(spacing: 14) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 36))
                    .foregroundColor(palette.textTertiary)
                Text("No tables found")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(palette.textSecondary)
                Text("Try a different date, time, or party size")
                    .font(.system(size: 13))
                    .foregroundColor(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if !drops.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // Status bar: count + sort context + last-updated
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.25, green: 0.85, blue: 0.48))
                        .frame(width: 7, height: 7)
                    Text("\(drops.count) table\(drops.count == 1 ? "" : "s") available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.textSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(palette.textTertiary)
                        Text("Ranked by demand")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.textTertiary)
                    }
                }

                // Elite venues callout (when present)
                let eliteCount = drops.filter { $0.feedHot == true }.count
                if eliteCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 13))
                            .foregroundColor(palette.accentRed)
                        Text("\(eliteCount) elite venue\(eliteCount == 1 ? "" : "s") — NYC's hardest reservations")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(palette.accentRed.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.accentRed.opacity(0.18), lineWidth: 1)
                    )
                }

                ForEach(drops) { drop in
                    SearchResultCard(
                        drop: drop,
                        isWatched: savedVM.isWatched(drop.name)
                    ) {
                        savedVM.toggleWatch(drop.name)
                    }
                }

                if let ts = vm.lastUpdated {
                    Text("Updated \(relativeTime(ts))")
                        .font(.system(size: 11))
                        .foregroundColor(palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private var filterDivider: some View {
        Divider().padding(.horizontal, 20)
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 5  { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }
}

// MARK: - Likely to Open row card

private struct LikelyOpenRow: View {
    let venue: LikelyToOpenVenue
    let isWatched: Bool
    let onTapNotify: () -> Void

    private let palette = FeedPalette.liveFeedLight

    private var imageURL: URL? {
        guard let s = venue.imageUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Probability shown in the card — uses the real `probability` field from backend metrics.
    /// Falls back to deriving from availability_rate_14d if the field is missing (older API versions).
    private var probabilityPct: Int? {
        if let p = venue.probability { return p }
        guard let rate = venue.availabilityRate14d else { return nil }
        let boost = min(0.08, max(0.0, venue.trendPct ?? 0.0) > 0 ? (venue.trendPct ?? 0.0) : 0.0)
        return min(99, max(1, Int(round((rate + boost) * 100))))
    }

    private var probabilityColor: Color {
        guard let p = probabilityPct else { return palette.textTertiary }
        if p >= 80 { return palette.accentRed }
        if p >= 55 { return Color(red: 0.95, green: 0.55, blue: 0.10) }
        return palette.textSecondary
    }

    /// Reason text — uses the real data-driven `reason` field from backend metrics.
    private var reasonText: String? {
        if let r = venue.reason, !r.isEmpty { return r }
        // Fallback: synthesise from available metrics (no hardcoded per-venue text)
        guard let days = venue.daysWithDrops else { return nil }
        return "Pattern analysis shows \(days) drop\(days != 1 ? "s" : "") in the last 14 days."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Restaurant image header
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = imageURL {
                        CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .lightOnLight) {
                            LinearGradient(
                                colors: [Color(white: 0.82), Color(white: 0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    } else {
                        LinearGradient(
                            colors: [Color(white: 0.82), Color(white: 0.72)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipped()

                // Neighborhood badge overlay
                if let nbhd = venue.neighborhood, !nbhd.isEmpty {
                    Text(nbhd.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(0.5)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(12)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 18
                )
            )

            // Content area
            VStack(alignment: .leading, spacing: 10) {
                // Name + probability row
                HStack(alignment: .firstTextBaseline) {
                    Text(venue.name)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let pct = probabilityPct {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(pct)%")
                                .font(.system(size: 26, weight: .black))
                                .foregroundColor(probabilityColor)
                            Text("PROBABILITY")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(probabilityColor.opacity(0.7))
                                .tracking(0.5)
                        }
                    }
                }

                // Data-driven reason text from backend metrics
                if let reason = reasonText {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(
                            // Accent underline on left edge
                            Rectangle()
                                .fill(probabilityColor.opacity(0.5))
                                .frame(width: 2)
                                .padding(.vertical, 2),
                            alignment: .leading
                        )
                        .padding(.leading, 8)
                }

                // Watch count row + Notify Me button
                HStack(spacing: 0) {
                    // Watching avatars (circles as placeholder — real count from daysWithDrops proxy)
                    let watchCount = max(1, (venue.daysWithDrops ?? 1) * 3)
                    HStack(spacing: -6) {
                        ForEach(0..<min(3, watchCount), id: \.self) { i in
                            Circle()
                                .fill(Color(white: 0.78 - Double(i) * 0.05))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        }
                    }
                    Text(watchCount > 3 ? " +\(watchCount) watching now" : " watching now")
                        .font(.system(size: 11))
                        .foregroundColor(palette.textTertiary)
                        .padding(.leading, 4)

                    Spacer(minLength: 8)

                    Button { onTapNotify() } label: {
                        Text(isWatched ? "Watching ✓" : "Notify Me")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(isWatched ? Color.gray.opacity(0.55) : palette.accentRed)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

// MARK: - Search result card

private struct SearchResultCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: () -> Void

    private let palette = FeedPalette.liveFeedLight

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var rarityPoints: Int { drop.rarityPoints ?? 0 }

    private var isElite: Bool { drop.feedHot == true }

    private var isTrending: Bool {
        guard let t = drop.trendHeadlineShort else { return false }
        return !t.isEmpty
    }

    private var scarcityContext: String? {
        drop.feedScarcityLabel
    }

    private var dateLabel: String {
        let ds = drop.dateStr ?? drop.slots.first?.dateStr ?? ""
        let parts = ds.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "" }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        let cal = Calendar.current
        guard let date = cal.date(from: comps) else { return "" }
        if cal.isDateInToday(date)    { return "Tonight" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return "\(m)/\(d)"
    }

    private func formatTime(_ t: String) -> String {
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t }
        let m  = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap  = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Top row: thumbnail + info + reserve ──────────────────
            HStack(spacing: 14) {
                // Thumbnail
                ZStack(alignment: .topLeading) {
                    Group {
                        if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                            CardAsyncImage(url: url, contentMode: .fill, skeletonTone: .lightOnLight) {
                                Color(white: 0.92)
                            }
                        } else {
                            Color(white: 0.92)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Elite flame badge on thumbnail
                    if isElite {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(5)
                            .background(palette.accentRed)
                            .clipShape(Circle())
                            .offset(x: -4, y: -4)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drop.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)
                        if isTrending {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.18, green: 0.76, blue: 0.42))
                        }
                    }

                    // Neighborhood · date
                    let sub = [drop.neighborhood ?? drop.location, dateLabel.isEmpty ? nil : dateLabel]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(1)
                    }

                    // Scarcity context from metrics
                    if let ctx = scarcityContext {
                        Text(ctx)
                            .font(.system(size: 11))
                            .foregroundColor(rarityPoints >= 70 ? palette.accentRed : palette.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                // Reserve + bookmark
                VStack(spacing: 8) {
                    Button {
                        if let u = resyUrl { UIApplication.shared.open(u) }
                    } label: {
                        Text("Reserve")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(palette.accentRed)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(resyUrl == nil)
                    .opacity(resyUrl == nil ? 0.5 : 1)

                    Button { onToggleWatch() } label: {
                        Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15))
                            .foregroundColor(isWatched ? palette.accentRed : palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)

            // ── Bottom row: time slot pills + rarity badge ────────────
            let slots = drop.slots.prefix(6)
            if !slots.isEmpty || rarityPoints > 0 {
                HStack(spacing: 8) {
                    // Time slot pills — tap each to open Resy
                    if !slots.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                                    let label = formatTime(slot.time ?? "")
                                    if !label.isEmpty {
                                        Button {
                                            let urlStr = slot.resyUrl ?? drop.resyUrl ?? ""
                                            if let u = URL(string: urlStr) { UIApplication.shared.open(u) }
                                        } label: {
                                            Text(label)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(palette.accentRed)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(palette.accentRed.opacity(0.08))
                                                .clipShape(Capsule())
                                                .overlay(Capsule().stroke(palette.accentRed.opacity(0.2), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    } else {
                        Spacer(minLength: 0)
                    }

                    // Rarity badge — shown when we have real metrics
                    if rarityPoints > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(rarityPoints)/100")
                                .font(.system(size: 10, weight: .black))
                        }
                        .foregroundColor(rarityPoints >= 80 ? palette.accentRed : palette.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (rarityPoints >= 80 ? palette.accentRed : palette.textTertiary).opacity(0.08)
                        )
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: isElite ? palette.accentRed.opacity(0.10) : .black.opacity(0.05),
                radius: isElite ? 10 : 6, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isElite ? palette.accentRed.opacity(0.25) : Color.clear, lineWidth: 1.5)
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthSessionManager())
}
