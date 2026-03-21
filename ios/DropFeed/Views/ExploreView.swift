import SwiftUI

/// Explore tab — discovery layout: hero highlight, likely-to-drop, hot areas, time tabs, two-column grid.
struct ExploreView: View {
    @ObservedObject var vm: SearchViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var alertsVM: AlertsViewModel
    @ObservedObject var premium: PremiumManager

    @State private var gridTimeTab: ExploreGridTimeTab = .evening
    @State private var hypeSortReversed = false
    @State private var showAlertsSheet = false

    /// Fixed grid cell geometry so every card matches; spacing is gap between cells.
    private let gridColumnSpacing: CGFloat = 14
    private let gridRowSpacing: CGFloat = 20
    private let gridImageHeight: CGFloat = 162
    private let gridTextBlockHeight: CGFloat = 92

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topChrome
                exploreDateStrip
                partyRowCompact
                if let err = vm.error {
                    errorBanner(err).padding(.top, 12)
                }
                tonightHighlightsSection
                    .padding(.top, 22)
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
        .background(SnagDesignSystem.exploreCanvas.ignoresSafeArea())
        .sheet(isPresented: $showAlertsSheet) {
            NavigationStack {
                AlertsView(alertsVM: alertsVM, savedVM: savedVM, premium: premium)
            }
        }
        .onAppear {
            vm.exploreTabActive = true
            vm.selectedMealPreset = nil
            vm.isSearchActive = true
            normalizeExploreSelectedDateIfNeeded()
            vm.startPolling()
        }
        .onDisappear {
            vm.exploreTabActive = false
            vm.stopPolling()
        }
    }

    // MARK: - Header

    private var topChrome: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                Text("SNAG")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .italic()
                    .foregroundColor(SnagDesignSystem.exploreCoralSolid)
            }
            Spacer()
            Button {
                showAlertsSheet = true
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topTrailing) {
                if alertsVM.unreadCount > 0 {
                    Circle()
                        .fill(SnagDesignSystem.exploreCoralSolid)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .padding(.top, 4)
    }

    /// Single-day selection from the next 14 days (`SearchViewModel.dateOptions`).
    private var exploreDateStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                .tracking(0.9)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.dateOptions, id: \.dateStr) { opt in
                        exploreDateChip(opt)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 16)
    }

    private func exploreDateChip(_ opt: (dateStr: String, monthAbbrev: String, dayNum: String)) -> some View {
        let selected = vm.selectedDates == Set([opt.dateStr])
        return Button {
            vm.selectedDates = [opt.dateStr]
            Task { await vm.loadResults() }
        } label: {
            VStack(spacing: 3) {
                Text(opt.monthAbbrev)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.35)
                Text(opt.dayNum)
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundColor(selected ? .white : SnagDesignSystem.exploreSecondaryLabel)
            .frame(width: 52, height: 60)
            .background(selected ? SnagDesignSystem.exploreCoralSolid : Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.clear : Color(white: 0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

    private var partyRowCompact: some View {
        HStack {
            Text("Guests")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
            Spacer()
            HStack(spacing: 6) {
                ForEach(ExplorePartySegment.allCases) { seg in
                    let on = vm.explorePartySegment == seg
                    Button {
                        vm.explorePartySegment = seg
                        Task { await vm.loadResults() }
                    } label: {
                        Text(seg.shortLabel)
                            .font(.system(size: 12, weight: on ? .bold : .medium))
                            .foregroundColor(on ? .white : SnagDesignSystem.exploreSecondaryLabel)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(on ? Color(white: 0.22) : Color(white: 0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
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

    // MARK: - Tonight's Highlights (hero)

    private var tonightHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tonight's Highlights")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                Spacer()
                Text("LIVE DATA")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                    .tracking(0.8)
            }

            if vm.isLoading && vm.rankedResults.isEmpty {
                ProgressView()
                    .tint(SnagDesignSystem.exploreCoralSolid)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let hero = highlightDrop {
                heroCard(hero)
            } else {
                Text("No featured tables for this window yet.")
                    .font(.system(size: 14))
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                    .padding(.vertical, 20)
            }
        }
    }

    private var highlightDrop: Drop? {
        vm.rankedResults.first
    }

    private func heroCard(_ drop: Drop) -> some View {
        let url = resyURL(for: drop)
        return Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    heroImage(drop)
                        .frame(height: 200)
                        .clipped()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if heroShowBestTonight(drop) {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 11))
                                    Text("BEST TONIGHT")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(0.4)
                                }
                                .foregroundColor(Color(red: 0.15, green: 0.12, blue: 0.11))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(SnagDesignSystem.exploreCoralSolid)
                                .clipShape(Capsule())
                            }
                            Text(habitPillText(for: drop))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(white: 0.22), in: Capsule())
                        }
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text(heroMetaLine(for: drop))
                            .font(.system(size: 13))
                    }
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                }
                .padding(.top, 12)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func heroImage(_ drop: Drop) -> some View {
        if let s = drop.imageUrl, let u = URL(string: s) {
            CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .heroMuted) {
                Color(white: 0.18)
            }
        } else {
            Color(white: 0.18)
        }
    }

    private func heroShowBestTonight(_ drop: Drop) -> Bool {
        if drop.feedHot == true { return true }
        if let s = drop.snagScore, s >= 85 { return true }
        return false
    }

    private func habitPillText(for drop: Drop) -> String {
        if let v = drop.velocityPrimaryLabel, !v.isEmpty, v.count <= 44 { return v }
        if let s = drop.metricsSubtitle, !s.isEmpty, s.count <= 44 { return s }
        if let h = drop.heroDescription, !h.isEmpty {
            let t = h.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count <= 44 { return t }
            return String(t.prefix(41)) + "…"
        }
        return "Fresh availability"
    }

    private func heroMetaLine(for drop: Drop) -> String {
        let table = tablePhrase
        let time = formatFirstSlotTime(drop)
        let area = (drop.neighborhood ?? drop.location ?? "NYC").trimmingCharacters(in: .whitespaces)
        if time.isEmpty { return "\(table) • \(area)" }
        return "\(table) • \(time) • \(area)"
    }

    private var tablePhrase: String {
        switch vm.explorePartySegment {
        case .two: return "Table for 2"
        case .four: return "Table for 4"
        case .anyParty: return "Table"
        }
    }

    // MARK: - Likely to drop

    @ViewBuilder
    private var likelyToDropCard: some View {
        if let venue = vm.likelyToOpen.first {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                    Text("LIKELY TO DROP")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                }
                .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)

                Text(venue.name)
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundColor(.white)

                Text(likelySubtext(venue))
                    .font(.system(size: 13))
                    .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    TimelineView(.animation(minimumInterval: 0.8)) { _ in
                        Text("Scanning…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                    }
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
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func likelySubtext(_ venue: LikelyToOpenVenue) -> String {
        if let r = venue.reason, !r.isEmpty { return r }
        if let d = venue.lastSeenDescription, !d.isEmpty { return d }
        return "Pattern watch — we’ll surface when slots appear."
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
        if items.isEmpty, vm.rankedResults.count > 1 {
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
        let heroId = highlightDrop?.id
        var list = vm.rankedResults.filter { $0.id != heroId }
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
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    // Fixed bounds first so resizable images cannot expand the layout pass.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: gridImageHeight)
                        .overlay {
                            gridThumb(drop)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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

                    VStack {
                        Spacer()
                        Text(gridTimeOverlay(drop))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(white: 0.18))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(white: 0.35), lineWidth: 1))
                            .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                .frame(height: gridImageHeight)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)

                    Text((drop.neighborhood ?? drop.location ?? "").uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                        .tracking(0.4)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)

                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: insightIcon(for: drop))
                            .font(.system(size: 10))
                            .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                            .padding(.top, 2)
                        Text(insightLine(for: drop))
                            .font(.system(size: 10))
                            .foregroundColor(SnagDesignSystem.exploreSecondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, minHeight: gridTextBlockHeight, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: gridImageHeight + 8 + gridTextBlockHeight, alignment: .topLeading)
            .clipped()
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
        alertsVM: AlertsViewModel(),
        premium: PremiumManager()
    )
}
