import SwiftUI

// MARK: - Root container

struct ContentView: View {
    @StateObject private var feedVM  = FeedViewModel()
    @StateObject private var savedVM = SavedViewModel()
    @StateObject private var premium = PremiumManager()
    @State private var selectedTab = 0

    var body: some View {
        // VStack: content fills remaining space, tab bar sits at the safe-area bottom.
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 0:
                    FeedView(feedVM: feedVM, savedVM: savedVM, premium: premium)
                default:
                    SearchView(savedVM: savedVM)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selectedTab: $selectedTab)
        }
        .task {
            await savedVM.loadAll()
            await premium.checkEntitlements()
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
        ZStack {
            Color.white

            HStack {
                // Leading: back/edit in results view, blank in setup
                if vm.isSearchActive {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { vm.isSearchActive = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Edit")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(palette.accentRed)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 52)
                }

                Spacer()

                Text(vm.isSearchActive ? "Live Search" : "Set up a search")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(palette.textPrimary)

                Spacer()

                // Trailing: live dot when active
                if vm.isSearchActive {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 0.25, green: 0.85, blue: 0.48))
                            .frame(width: 7, height: 7)
                        if vm.isRefreshing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: palette.textTertiary))
                                .scaleEffect(0.6)
                        }
                    }
                    .frame(width: 52, alignment: .trailing)
                } else {
                    Color.clear.frame(width: 52)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
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
            Text("Likely to Open")
                .font(.system(size: 22, weight: .black))
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 16)

            VStack(spacing: 10) {
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
        let drops = vm.filteredResults
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
                // Count + last-updated
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.25, green: 0.85, blue: 0.48))
                        .frame(width: 7, height: 7)
                    Text("\(drops.count) table\(drops.count == 1 ? "" : "s") available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.textSecondary)
                    Spacer()
                    if let ts = vm.lastUpdated {
                        Text(relativeTime(ts))
                            .font(.system(size: 11))
                            .foregroundColor(palette.textTertiary)
                    }
                }

                ForEach(drops) { drop in
                    SearchResultCard(
                        drop: drop,
                        isWatched: savedVM.isWatched(drop.name)
                    ) {
                        savedVM.toggleWatch(drop.name)
                    }
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

    private var trendArrow: (icon: String, color: Color)? {
        if let pct = venue.trendPct {
            if pct > 0.05 { return ("arrow.up.right", Color(red: 0.18, green: 0.76, blue: 0.42)) }
            if pct < -0.05 { return ("arrow.down.right", .gray) }
            return ("arrow.right", .gray)
        }
        if let rarity = venue.rarityScore {
            if rarity > 60 { return ("arrow.up.right", Color(red: 0.18, green: 0.76, blue: 0.42)) }
            return ("arrow.right", .gray)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(venue.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    if let arrow = trendArrow {
                        Image(systemName: arrow.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(arrow.color)
                    }
                }
                if let nbhd = venue.neighborhood, !nbhd.isEmpty {
                    Text(nbhd)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textTertiary)
                }
            }

            Spacer(minLength: 8)

            Button {
                onTapNotify()
            } label: {
                Text(isWatched ? "Watching" : "Notify Me")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(isWatched ? Color.gray.opacity(0.6) : palette.accentRed)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
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

    private var slotsLabel: String {
        let count = drop.slots.count
        if count == 0 { return "Available" }
        if count == 1, let t = drop.slots.first?.time { return formatTime(t) }
        return "\(count) time slots"
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
        HStack(spacing: 14) {
            // Thumbnail
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color(white: 0.92) }
                    }
                } else {
                    Color(white: 0.92)
                }
            }
            .frame(width: 66, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    if drop.feedHot == true {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(palette.accentRed)
                    }
                }

                HStack(spacing: 5) {
                    if !dateLabel.isEmpty {
                        Label(dateLabel, systemImage: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(palette.textSecondary)
                        Text("·")
                            .foregroundColor(palette.textTertiary)
                            .font(.system(size: 12))
                    }
                    Text(slotsLabel)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSecondary)
                }
                .lineLimit(1)

                if let nb = drop.neighborhood ?? drop.location, !nb.isEmpty {
                    Text(nb)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textTertiary)
                }
            }

            Spacer(minLength: 4)

            // Actions
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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
