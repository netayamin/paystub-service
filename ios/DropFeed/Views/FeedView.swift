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

    // MARK: - Top nav bar (LIVE UPDATES + red dot, gold DropFeed, bell)

    private var topNavBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.accentRed)
                    .frame(width: 8, height: 8)
                Text("LIVE UPDATES")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                    .tracking(0.5)
            }
            .frame(width: 120, alignment: .leading)

            Spacer()
            Text("DropFeed")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppTheme.premiumGold)
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

                // ── New drops banner
                if vm.newDropsCount > 0 {
                    newDropsBanner
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // ── 1. Just Dropped — auto-scrolling carousel (peek, 5s auto-play, pause on touch)
                let justDropped = Array(vm.justDropped.prefix(10))
                if !justDropped.isEmpty {
                    JustDroppedCarouselSection(
                        drops: justDropped,
                        isWatched: { savedVM.isWatched($0) },
                        onToggleWatch: { savedVM.toggleWatch($0) }
                    )
                    .padding(.bottom, 28)
                }

                // ── 2. Hot Right Now — horizontal list (heat labels, SET ALERT)
                let hotDrops = Array(vm.trendingDrops.prefix(10))
                if !hotDrops.isEmpty {
                    HotRightNowSection(
                        drops: hotDrops,
                        isWatched: { savedVM.isWatched($0) },
                        onToggleWatch: { savedVM.toggleWatch($0) }
                    )
                    .padding(.bottom, 28)
                }

                // ── 3. The Rarest — vertical list (museum style, NOTIFY ME)
                let rarest = Array(vm.rareDrops.prefix(10))
                if !rarest.isEmpty {
                    TheRarestSection(
                        drops: rarest,
                        isWatched: { savedVM.isWatched($0) },
                        onToggleWatch: { savedVM.toggleWatch($0) }
                    )
                    .padding(.bottom, 28)
                }

                Spacer(minLength: 120)
            }
        }
        .background(AppTheme.background)
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

// MARK: - Just Dropped Carousel (peek, 5s auto-play, pause on touch)

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
            HStack(spacing: 6) {
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
        if let first = drop.partySizesAvailable.sorted().first { parts.append("\(first) Guests") }
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

