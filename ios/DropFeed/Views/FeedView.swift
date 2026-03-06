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

    // MARK: - Top nav bar

    private var topNavBar: some View {
        HStack(spacing: 0) {
            Button { onOpenSearch?() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("DropFeed")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            Button { onOpenAlerts?() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    if alertBadgeCount > 0 {
                        Text("\(min(alertBadgeCount, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Circle().fill(AppTheme.accentOrange))
                            .offset(x: 6, y: -6)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(AppTheme.background)
    }

    // MARK: - Feed content

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {

                // ── Live scan bar
                liveScanBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // ── New drops banner
                if vm.newDropsCount > 0 {
                    newDropsBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // ── Top 4 carousel
                if !vm.carouselDrops.isEmpty {
                    topCarousel
                        .padding(.bottom, 28)
                }

                // ── Metric-driven sections
                let rares = Array(vm.rareDrops.prefix(10))
                if !rares.isEmpty {
                    feedSection(
                        emoji: "💎", title: "Rarest Tables",
                        subtitle: "Almost never available — act fast",
                        drops: rares
                    ) { drop in rarityMetricView(drop) }
                }

                let fresh = Array(vm.justDropped.prefix(10))
                if !fresh.isEmpty {
                    feedSection(
                        emoji: "⚡", title: "Just Dropped",
                        subtitle: "Spotted in the last 24 hours",
                        drops: fresh
                    ) { drop in freshnessMetricView(drop) }
                }

                let trending = Array(vm.trendingDrops.prefix(10))
                if !trending.isEmpty {
                    feedSection(
                        emoji: "📈", title: "Trending Now",
                        subtitle: "Availability spiking vs last 14 days",
                        drops: trending
                    ) { drop in trendMetricView(drop) }
                }

                let fleeting = Array(vm.fleetingDrops.prefix(10))
                if !fleeting.isEmpty {
                    feedSection(
                        emoji: "⏱", title: "Gone in Minutes",
                        subtitle: "These slots disappear fast",
                        drops: fleeting
                    ) { drop in durationMetricView(drop) }
                }

                let hotspots = Array(vm.hotspotDrops.prefix(10))
                if !hotspots.isEmpty {
                    feedSection(
                        emoji: "🌟", title: "NYC Hotspots",
                        subtitle: "Legendary tables that rarely open",
                        drops: hotspots
                    ) { drop in hotspotMetricView(drop) }
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
                    .padding(.bottom, 28)
                }

                Spacer(minLength: 120)
            }
        }
        .background(AppTheme.background)
    }

    // MARK: - Top Carousel

    @State private var carouselPage = 0

    private var topCarousel: some View {
        VStack(spacing: 10) {
            sectionHeader(emoji: "🔥", title: "Top Opportunities", subtitle: "Hardest tables to get right now")
                .padding(.horizontal, 16)

            TabView(selection: $carouselPage) {
                ForEach(Array(vm.carouselDrops.enumerated()), id: \.element.id) { idx, drop in
                    CarouselCardView(
                        drop: drop,
                        rank: idx + 1,
                        isWatched: savedVM.isWatched(drop.name),
                        onToggleWatch: { savedVM.toggleWatch($0) }
                    )
                    .padding(.horizontal, 16)
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 290)
            .onAppear {
                UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(AppTheme.accentOrange)
                UIPageControl.appearance().pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.3)
            }
        }
    }

    // MARK: - Feed section builder

    @ViewBuilder
    private func feedSection<Metric: View>(
        emoji: String,
        title: String,
        subtitle: String,
        drops: [Drop],
        @ViewBuilder metricView: @escaping (Drop) -> Metric
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(emoji: emoji, title: title, subtitle: subtitle)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(Array(drops.enumerated()), id: \.element.id) { idx, drop in
                    SectionDropRow(
                        drop: drop,
                        isWatched: savedVM.isWatched(drop.name),
                        onToggleWatch: { savedVM.toggleWatch($0) },
                        metricView: { AnyView(metricView(drop)) }
                    )
                    .padding(.horizontal, 16)
                    .staggeredAppear(index: idx, delayPerItem: 0.02)
                }
            }
        }
        .padding(.bottom, 28)
    }

    // MARK: - Metric chip builders

    private func rarityMetricView(_ drop: Drop) -> some View {
        let score = drop.rarityScore.map { r -> Int in
            let v = r <= 1 ? Int(r * 100) : Int(r.rounded())
            return min(100, max(0, v))
        } ?? 0
        let days = drop.daysWithDrops ?? 0
        return VStack(alignment: .trailing, spacing: 3) {
            metricPill("\(score)/100", color: AppTheme.scarcityRare)
            if days > 0 {
                Text("\(days)/14 days")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
    }

    private func freshnessMetricView(_ drop: Drop) -> some View {
        let sec = drop.secondsSinceDetected
        let label: String
        let color: Color
        if sec < 60 { label = "JUST NOW"; color = AppTheme.liveDot }
        else if sec < 3600 { label = "\(sec / 60)m ago"; color = AppTheme.liveDot }
        else if sec < 7200 { label = "\(sec / 3600)h ago"; color = AppTheme.accentOrange }
        else { label = "\(sec / 3600)h ago"; color = AppTheme.textSecondary }
        return metricPill(label, color: color)
    }

    private func trendMetricView(_ drop: Drop) -> some View {
        let pct = drop.trendPct ?? 0
        let label = pct > 0 ? "+\(Int(pct))%" : "\(Int(pct))%"
        let color: Color = pct > 0 ? AppTheme.liveDot : AppTheme.textSecondary
        return metricPill(label, color: color)
    }

    private func durationMetricView(_ drop: Drop) -> some View {
        let secs = drop.avgDropDurationSeconds ?? 0
        let label: String
        if secs < 60 { label = "<1 min" }
        else if secs < 3600 { label = "\(Int(secs / 60)) min" }
        else { label = "\(Int(secs / 3600))h" }
        return metricPill(label, color: AppTheme.accentOrange)
    }

    private func hotspotMetricView(_ drop: Drop) -> some View {
        let score = drop.rarityScore.map { r -> Int in
            let v = r <= 1 ? Int(r * 100) : Int(r.rounded())
            return min(100, max(0, v))
        } ?? 0
        return VStack(alignment: .trailing, spacing: 3) {
            metricPill("HOTSPOT", color: AppTheme.premiumGold)
            if score > 0 {
                Text("Rarity \(score)/100")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func metricPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(emoji: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(emoji)
                        .font(.system(size: 16))
                    Text(title.uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .tracking(0.5)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Spacer()
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
                Text(vm.secondsUntilNextScan > 0
                     ? vm.nextScanLabel
                     : (vm.lastScanAt != nil ? "Last scan \(vm.lastScanText)" : "Scanning…"))
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
            }
            Spacer()
            if vm.lastScanAt != nil, vm.lastScanText != "—" {
                Text("Updated \(vm.lastScanText)")
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
        Button { vm.acknowledgeNewDrops() } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.accentOrange)
                Text("\(vm.newDropsCount) new drop\(vm.newDropsCount == 1 ? "" : "s") detected")
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

// MARK: - Carousel Card

private struct CarouselCardView: View {
    let drop: Drop
    let rank: Int
    let isWatched: Bool
    let onToggleWatch: (String) -> Void

    private var rarityInt: Int {
        guard let r = drop.rarityScore else { return 0 }
        let v = r <= 1 ? Int(r * 100) : Int(r.rounded())
        return min(100, max(0, v))
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

    private var metricBadge: String {
        if rarityInt > 0 { return "Rarity \(rarityInt)/100" }
        if drop.isHotspot == true { return "NYC Hotspot" }
        if let t = drop.trendPct, t > 10 { return "+\(Int(t))% trending" }
        return "Top Opportunity"
    }

    private var rankColor: Color {
        switch rank {
        case 1: return AppTheme.accentOrange
        case 2: return Color(white: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return AppTheme.textTertiary
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background image
            GeometryReader { geo in
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        default:
                            gradientFallback
                        }
                    }
                } else {
                    gradientFallback
                }
            }
            .frame(height: 260)

            // Dark gradient overlay
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.25), location: 0.45),
                    .init(color: .black.opacity(0.92), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)

            // Top row: rank + bookmark
            VStack {
                HStack(alignment: .top) {
                    // Rank badge
                    Text("#\(rank)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(rankColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())

                    Spacer()

                    Button { onToggleWatch(drop.name) } label: {
                        Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(isWatched ? AppTheme.accentOrange.opacity(0.9) : Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                Spacer()
            }
            .frame(height: 260)

            // Bottom content
            VStack(alignment: .leading, spacing: 6) {
                // Metric badge
                HStack(spacing: 8) {
                    Text(metricBadge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(rankColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(rankColor.opacity(0.2))
                        .clipShape(Capsule())

                    if let nb = drop.neighborhood, !nb.isEmpty {
                        Text(nb)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Name + date
                Text(drop.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !dateLabel.isEmpty {
                    Text(dateLabel)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.75))
                }

                // CTA
                if let url = resyUrl {
                    Button { UIApplication.shared.open(url) } label: {
                        HStack(spacing: 8) {
                            Text("Reserve on Resy")
                                .font(.system(size: 15, weight: .bold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppTheme.accentOrange)
                        .cornerRadius(12)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(14)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }

    private var gradientFallback: some View {
        LinearGradient(
            colors: [Color(red: 0.15, green: 0.12, blue: 0.20), Color(red: 0.08, green: 0.07, blue: 0.13)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
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

struct HotRightNowCard: View {
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
                Text(drop.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 120)
            }
        }
        .buttonStyle(.plain)
    }
}
