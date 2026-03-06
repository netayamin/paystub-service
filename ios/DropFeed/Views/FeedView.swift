import SwiftUI

struct FeedView: View {
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    var onOpenSearch: (() -> Void)? = nil
    var onOpenAlerts: (() -> Void)? = nil
    var alertBadgeCount: Int = 0

    private var vm: FeedViewModel { feedVM }

    private var viewStateId: String {
        if vm.isLoading && vm.drops.isEmpty { return "loading" }
        if vm.error != nil { return "error" }
        if vm.drops.isEmpty { return "empty" }
        return "content"
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewStateId)
        }
        .background(AppTheme.background)
        .refreshable { await vm.refresh() }
        .task {
            await vm.refresh()
            vm.startPolling()
        }
        .onChange(of: feedVM.selectedDates) { _, _ in Task { await vm.refresh() } }
        .onChange(of: feedVM.selectedPartySizes) { _, _ in Task { await vm.refresh() } }
        .onChange(of: feedVM.selectedTimeFilter) { _, _ in Task { await vm.refresh() } }
    }

    // MARK: - Top bar (Live Market: title + "X TABLES DROPPED IN THE LAST HOUR")

    private var topNavBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live Market")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button { onOpenAlerts?() } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
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
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.accentRed)
                    .frame(width: 6, height: 6)
                Text("\(vm.tablesDroppedLastHour) TABLES DROPPED IN THE LAST HOUR")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .tracking(0.3)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .padding(.top, 8)
        .background(AppTheme.background)
    }

    // MARK: - Feed content (Live Market: Available Now → Just Dropped → Expected Drops → Watchlist)

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // ── 1. AVAILABLE NOW — horizontal carousel with LIVE badge
                let availableDrops = Array(vm.justDropped.prefix(10))
                if !availableDrops.isEmpty {
                    AvailableNowSection(drops: availableDrops)
                        .padding(.bottom, 24)
                }

                // ── 2. JUST DROPPED — vertical list, OPEN RESY button
                let justDroppedList = Array(vm.justDropped.prefix(10))
                if !justDroppedList.isEmpty {
                    JustDroppedListSection(drops: justDroppedList)
                        .padding(.bottom, 24)
                }

                // ── 3. EXPECTED DROPS — predicted time + confidence + NOTIFY ME
                let expectedVenues = Array(vm.likelyToOpen.prefix(10))
                if !expectedVenues.isEmpty {
                    ExpectedDropsSection(venues: expectedVenues, onOpenAlerts: onOpenAlerts)
                        .padding(.bottom, 24)
                }

                // ── 4. Your Watchlist
                WatchlistSection(
                    watchedNames: Array(savedVM.watchedVenues).sorted(),
                    onOpenAlerts: onOpenAlerts
                )

                Spacer(minLength: 120)
            }
        }
        .background(AppTheme.background)
    }

    // MARK: - Error / empty

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

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.textTertiary)
            Text("No drops yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text("We're scanning \(vm.totalVenuesScanned > 0 ? "\(vm.totalVenuesScanned)" : "698") venues. New tables appear here the moment they drop.")
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

// MARK: - AVAILABLE NOW (horizontal carousel, LIVE badge on each card)

private struct AvailableNowSection: View {
    let drops: [Drop]

    private let cardHeight: CGFloat = 220
    private var cardWidth: CGFloat {
        (UIScreen.main.bounds.width - 32) * 0.82
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AVAILABLE NOW")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(drops, id: \.id) { drop in
                        AvailableNowCard(drop: drop)
                            .frame(width: cardWidth, height: cardHeight)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct AvailableNowCard: View {
    let drop: Drop

    private var detailLine: String {
        var parts: [String] = []
        if let ds = drop.dateStr {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: ds) {
                if Calendar.current.isDateInToday(d) { parts.append("Tonight") }
                else if Calendar.current.isDateInTomorrow(d) { parts.append("Tomorrow") }
                else { let o = DateFormatter(); o.dateFormat = "EEE"; parts.append(o.string(from: d)) }
            }
        }
        if let t = drop.slots.first?.time, !t.isEmpty {
            let partsT = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
            let h = partsT.first.flatMap { Int($0) } ?? 0
            let m = partsT.count > 1 ? Int(partsT[1].prefix(2)) ?? 0 : 0
            let h12 = h % 12 == 0 ? 12 : h % 12
            let ap = h < 12 ? "AM" : "PM"
            parts.append(m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)")
        }
        if let first = drop.partySizesAvailable.sorted().first {
            parts.append(first > 8 ? "8+ Guests" : "\(first) Guests")
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { availableNowFallback }
                    }
                } else {
                    availableNowFallback
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.7), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(14)

            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.accentRed)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var availableNowFallback: some View {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.10, blue: 0.16), Color(red: 0.06, green: 0.05, blue: 0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - JUST DROPPED (vertical list, JUST DROPPED badge, OPEN RESY white button)

private struct JustDroppedListSection: View {
    let drops: [Drop]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.accentRed)
                    .frame(width: 6, height: 6)
                Text("JUST DROPPED")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            VStack(spacing: 8) {
                ForEach(drops, id: \.id) { drop in
                    JustDroppedRowView(drop: drop)
                }
            }
            .padding(.horizontal, 16)
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
                if Calendar.current.isDateInToday(d) { parts.append("Tonight") }
                else if Calendar.current.isDateInTomorrow(d) { parts.append("Tomorrow") }
                else { let o = DateFormatter(); o.dateFormat = "EEE"; parts.append(o.string(from: d)) }
            }
        }
        if let t = drop.slots.first?.time, !t.isEmpty {
            let partsT = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
            let h = partsT.first.flatMap { Int($0) } ?? 0
            let m = partsT.count > 1 ? Int(partsT[1].prefix(2)) ?? 0 : 0
            let h12 = h % 12 == 0 ? 12 : h % 12
            let ap = h < 12 ? "AM" : "PM"
            parts.append(m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)")
        }
        if let first = drop.partySizesAvailable.sorted().first {
            parts.append(first > 8 ? "8+ Guests" : "\(first) Guests")
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(drop.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("JUST DROPPED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.accentRed)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let url = resyUrl {
                Button { UIApplication.shared.open(url) } label: {
                    Text("OPEN RESY")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - EXPECTED DROPS (name • predicted time, Confidence: High, NOTIFY ME)

private struct ExpectedDropsSection: View {
    let venues: [LikelyToOpenVenue]
    var onOpenAlerts: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXPECTED DROPS")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.textSecondary)
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                ForEach(venues, id: \.id) { venue in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(venue.predictedDropTime.map { "\(venue.name) • \($0)" } ?? venue.name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary)
                            if let conf = venue.confidence, !conf.isEmpty {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(AppTheme.liveDot)
                                        .frame(width: 5, height: 5)
                                    Text("Confidence: \(conf)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        Button { onOpenAlerts?() } label: {
                            Text("NOTIFY ME")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(14)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Live Now (legacy vertical cards; kept for reference)

private struct LiveNowCard: View {
    let drop: Drop

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// "TONIGHT 8:30 PM • 2 SEATS" style
    private var detailLine: String {
        var parts: [String] = []
        if let ds = drop.dateStr {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: ds) {
                let cal = Calendar.current
                if cal.isDateInToday(d) { parts.append("Tonight") }
                else if cal.isDateInTomorrow(d) { parts.append("Tomorrow") }
                else {
                    let out = DateFormatter(); out.dateFormat = "EEEE"
                    parts.append(out.string(from: d))
                }
            }
        }
        if let time = drop.slots.first?.time, !time.isEmpty {
            let partsT = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
            let h = partsT.first.flatMap { Int($0) } ?? 0
            let m = partsT.count > 1 ? Int(partsT[1].prefix(2)) ?? 0 : 0
            let h12 = h % 12 == 0 ? 12 : h % 12
            let ap = h < 12 ? "AM" : "PM"
            parts.append(m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)")
        }
        if let first = drop.partySizesAvailable.sorted().first {
            parts.append(first > 8 ? "8+ SEATS" : "\(first) SEATS")
        }
        return parts.joined(separator: " • ")
    }

    /// Gold timer top-right e.g. "05:00" from avg_drop_duration (minutes)
    private var timerText: String {
        guard let sec = drop.avgDropDurationSeconds, sec > 0 else { return "05:00" }
        let mins = Int(sec / 60)
        if mins >= 60 { return "60:00" }
        return String(format: "%02d:%02d", mins, Int(sec.truncatingRemainder(dividingBy: 60)) % 60)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { liveNowFallback }
                    }
                } else {
                    liveNowFallback
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.6), location: 0.5),
                    .init(color: .black.opacity(0.92), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(drop.name)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !detailLine.isEmpty {
                    Text(detailLine.uppercased())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .tracking(0.5)
                        .padding(.top, 4)
                }
                if let url = resyUrl {
                    Button { UIApplication.shared.open(url) } label: {
                        Text("BOOK ON RESY")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppTheme.premiumGold)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, 12)
                }
            }
            .padding(16)

            Text(timerText)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.premiumGold)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var liveNowFallback: some View {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.10, blue: 0.16), Color(red: 0.06, green: 0.05, blue: 0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Expected Soon (venue name + countdown HH:MM:SS)

private struct ExpectedSoonSection: View {
    let venues: [LikelyToOpenVenue]
    let secondsUntilNextScan: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(goldSquare: true, title: "EXPECTED SOON")
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if venues.isEmpty {
                Text("No venues predicted soon. Check back after the next scan.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(venues.enumerated()), id: \.element.id) { index, venue in
                        HStack {
                            Text(venue.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                            Text(countdownForRow(index: index))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func countdownForRow(index: Int) -> String {
        if index == 0 && secondsUntilNextScan > 0 {
            let h = secondsUntilNextScan / 3600
            let m = (secondsUntilNextScan % 3600) / 60
            let s = secondsUntilNextScan % 60
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return "—"
    }
}

// MARK: - Your Watchlist (name + subtitle + gear)

private struct WatchlistSection: View {
    let watchedNames: [String]
    var onOpenAlerts: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(goldSquare: true, title: "YOUR WATCHLIST")
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if watchedNames.isEmpty {
                Text("No venues on your watchlist. Add some from Alerts.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(watchedNames, id: \.self) { name in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("NEXT 14 DAYS")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            Spacer()
                            Button { onOpenAlerts?() } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
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
                .padding(.horizontal, 16)
            }
        }
    }
}

private func sectionHeader(goldSquare: Bool, title: String) -> some View {
    HStack(spacing: 6) {
        if goldSquare {
            RoundedRectangle(cornerRadius: 2)
                .fill(AppTheme.premiumGold)
                .frame(width: 6, height: 6)
        }
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(AppTheme.textPrimary)
            .tracking(0.5)
    }
}

// MARK: - Just Dropped Carousel (legacy; kept for reference)
// To use ACarousel library instead: add package https://github.com/JWAutumn/ACarousel via Xcode File > Add Package Dependencies, then replace this block with ACarousel(drops, index: $carouselIndex, spacing: 12, headspace: 20, sidesScaling: 0.85, isWrap: drops.count > 1, autoScroll: drops.count > 1 ? .active(5) : .inactive, canMove: true) { drop in JustDroppedCard(...) }

private struct JustDroppedCarouselSection: View {
    let drops: [Drop]
    let isWatched: (String) -> Bool
    let onToggleWatch: (String) -> Void

    @State private var scrollId: String?
    @State private var carouselPaused = false
    @State private var autoPlayTask: Task<Void, Never>?

    private let cardHeight: CGFloat = 280
    private var cardWidth: CGFloat {
        let w = (UIScreen.main.bounds.width - 32) * 0.85
        return max(w, 280)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.accentRed)
                    .frame(width: 8, height: 8)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.premiumGold)
                Text("JUST DROPPED")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 16)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(drops.enumerated()), id: \.element.id) { _, drop in
                            JustDroppedCard(
                                drop: drop,
                                isWatched: isWatched(drop.name),
                                onToggleWatch: onToggleWatch
                            )
                            .frame(width: cardWidth, height: cardHeight)
                            .id(drop.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollId)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in carouselPaused = true }
                        .onEnded { _ in
                            carouselPaused = false
                            startAutoPlay(proxy: proxy)
                        }
                )
                .onAppear {
                    scrollId = drops.first?.id
                    startAutoPlay(proxy: proxy)
                }
                .onDisappear { autoPlayTask?.cancel() }
            }
        }
    }

    private func startAutoPlay(proxy: ScrollViewProxy) {
        autoPlayTask?.cancel()
        guard drops.count > 1 else { return }
        autoPlayTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if carouselPaused { continue }
                guard let current = scrollId, let idx = drops.firstIndex(where: { $0.id == current }) else { continue }
                let nextIdx = (idx + 1) % drops.count
                let nextId = drops[nextIdx].id
                withAnimation(.easeInOut(duration: 0.35)) {
                    scrollId = nextId
                    proxy.scrollTo(nextId, anchor: .leading)
                }
            }
        }
    }
}

private struct JustDroppedCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var urgencyText: String {
        FeedMetricLabels.urgencyText(avgDurationSeconds: drop.avgDropDurationSeconds)
    }

    private var scarcityText: String {
        let rate = drop.availabilityRate14d ?? 1
        return FeedMetricLabels.scarcityStatus(rate: rate)
    }

    private var freshnessText: String {
        FeedMetricLabels.freshnessText(secondsSinceDetected: drop.secondsSinceDetected)
    }

    private var detailLine: String {
        var parts: [String] = []
        if let ds = drop.dateStr {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let d = fmt.date(from: ds) {
                let cal = Calendar.current
                if cal.isDateInToday(d) { parts.append("Tonight") }
                else if cal.isDateInTomorrow(d) { parts.append("Tomorrow") }
                else {
                    let out = DateFormatter(); out.dateFormat = "EEE"
                    parts.append(out.string(from: d))
                }
            }
        }
        if let first = drop.partySizesAvailable.sorted().first {
            let guest = first > 8 ? "8+ Guests" : "\(first) Guests"
            parts.append(guest)
        }
        if let time = drop.slots.first?.time, !time.isEmpty {
            let partsT = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
            let h = partsT.first.flatMap { Int($0) } ?? 0
            let m = partsT.count > 1 ? Int(partsT[1].prefix(2)) ?? 0 : 0
            let h12 = h % 12 == 0 ? 12 : h % 12
            let ap = h < 12 ? "AM" : "PM"
            parts.append(m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)")
        }
        return parts.joined(separator: " • ")
    }

    private var isLive: Bool { drop.secondsSinceDetected < 600 }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background image
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure, .empty:
                            gradientFallback
                        @unknown default:
                            gradientFallback
                        }
                    }
                } else {
                    gradientFallback
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.5), location: 0.5),
                    .init(color: .black.opacity(0.92), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Top badges: urgency (red) + scarcity (yellow)
            VStack {
                HStack(alignment: .top) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                        Text(urgencyText)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.accentRed)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Spacer()
                    Text(scarcityText.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.premiumGold)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(12)
                Spacer()
            }

            // Bottom: name, detail line, freshness, BOOK NOW
            VStack(alignment: .leading, spacing: 6) {
                Text(drop.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text(freshnessText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))

                if let url = resyUrl {
                    Button { UIApplication.shared.open(url) } label: {
                        Text("BOOK NOW ON RESY")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppTheme.premiumGold)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, 8)
                }
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isLive ? AppTheme.liveDot.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .modifier(LivePulseModifier(active: isLive))
    }

    private var gradientFallback: some View {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.10, blue: 0.16), Color(red: 0.06, green: 0.05, blue: 0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Hot Right Now (horizontal, heat labels, SET ALERT)

private struct HotRightNowSection: View {
    let drops: [Drop]
    let isWatched: (String) -> Bool
    let onToggleWatch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.premiumGold)
                Text("HOT RIGHT NOW")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(drops, id: \.id) { drop in
                        HotRightNowCard(
                            drop: drop,
                            isWatched: isWatched(drop.name),
                            onToggleWatch: onToggleWatch
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct HotRightNowCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var heatLabel: String {
        FeedMetricLabels.heatLabel(trendPct: drop.trendPct)
    }

    private var demandLabel: String {
        FeedMetricLabels.demandLevel(rarityScore: drop.rarityScore, availabilityRate: drop.availabilityRate14d)
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
                    } else {
                        AppTheme.surfaceElevated
                    }
                }
                .frame(width: 160, height: 100)
                .clipped()

                Text(heatLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.premiumGold)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(demandLabel)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                Button { onToggleWatch(drop.name) } label: {
                    Text("SET ALERT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - The Rarest (vertical, museum style, NOTIFY ME)

private struct TheRarestSection: View {
    let drops: [Drop]
    let isWatched: (String) -> Bool
    let onToggleWatch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.premiumGold)
                Text("THE RAREST")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 10) {
                ForEach(Array(drops.enumerated()), id: \.element.id) { idx, drop in
                    RarestCard(
                        drop: drop,
                        isWatched: isWatched(drop.name),
                        onToggleWatch: onToggleWatch
                    )
                    .padding(.horizontal, 16)
                    .staggeredAppear(index: idx, delayPerItem: 0.03)
                }
            }
        }
    }
}

private struct RarestCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var rarityTier: String {
        let s = drop.rarityScore ?? 0
        let v = s <= 1 ? s * 100 : s
        return FeedMetricLabels.rarityTier(score: v)
    }

    private var scarcityText: String {
        FeedMetricLabels.scarcityStatus(rate: drop.availabilityRate14d)
    }

    private var subtitle: String {
        drop.neighborhood ?? (drop.location ?? "Reservation")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { AppTheme.surfaceElevated }
                    }
                } else {
                    AppTheme.surfaceElevated
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(rarityTier.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.premiumGold)
                Text(drop.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                Text(scarcityText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }

            Spacer(minLength: 8)

            Button { onToggleWatch(drop.name) } label: {
                Text("NOTIFY ME")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.premiumGold.opacity(0.9), AppTheme.premiumGold.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.premiumGold.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Live pulse (scale + opacity for cards with opened_at within 10 min)

private struct LivePulseModifier: ViewModifier {
    let active: Bool
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 1.02
                }
            }
            .onChange(of: active) { _, new in
                if !new { scale = 1.0 }
            }
    }
}

// MARK: - Section Drop Row

private struct SectionDropRow: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: (String) -> Void
    let metricView: () -> AnyView

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

    private var subtitle: String {
        var parts: [String] = []
        if !dateLabel.isEmpty { parts.append(dateLabel) }
        if let nb = drop.neighborhood, !nb.isEmpty { parts.append(nb) }
        if let times = drop.slots.first?.time.map({ formatTime($0) }), !times.isEmpty {
            parts.append(times)
        }
        return parts.joined(separator: " · ")
    }

    private func formatTime(_ t: String) -> String {
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return t }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
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
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                AppTheme.surfaceElevated
                            }
                        }
                    } else {
                        AppTheme.surfaceElevated
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                    if let sizes = drop.partySizesAvailable.sorted().first {
                        Text("Party of \(sizes)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                // Metric + bookmark
                VStack(alignment: .trailing, spacing: 8) {
                    metricView()
                    Button { onToggleWatch(drop.name) } label: {
                        Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 13))
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

private struct PredictedVenueRow: View {
    let venue: LikelyToOpenVenue
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var rarityInt: Int {
        guard let r = venue.rarityScore else { return 0 }
        let v = r <= 1 ? Int(r * 100) : Int(r.rounded())
        return min(100, max(0, v))
    }

    private var confidenceInt: Int {
        let rarity = min(max(venue.rarityScore ?? 0, 0), 1)
        let scarcity = 1 - min(max(venue.availabilityRate14d ?? 1, 0), 1)
        return Int(((rarity * 0.65) + (scarcity * 0.35)) * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let s = venue.imageUrl, let url = URL(string: s) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { AppTheme.surfaceElevated }
                    }
                } else {
                    AppTheme.surfaceElevated
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let nb = venue.neighborhood, !nb.isEmpty {
                        Text(nb)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                            .lineLimit(1)
                    }
                    if let days = venue.daysWithDrops {
                        Text("open \(days)/14 days")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                Text("Likely \(confidenceInt)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.liveDot)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.liveDot.opacity(0.15))
                    .clipShape(Capsule())

                if rarityInt > 0 {
                    Text("Rarity \(rarityInt)/100")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                }

                Button { onToggleWatch(venue.name) } label: {
                    Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13))
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
}

// MARK: - Legacy views kept for compatibility

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
                            .lineLimit(1)
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
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

