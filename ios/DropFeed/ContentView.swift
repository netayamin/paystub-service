import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var feedVM   = FeedViewModel()
    @StateObject private var savedVM  = SavedViewModel()
    @StateObject private var alertsVM = AlertsViewModel()
    @StateObject private var premium  = PremiumManager()

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        GeometryReader { geo in
            let bottomInset = geo.safeAreaInsets.bottom
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    FeedView(
                        feedVM: feedVM,
                        savedVM: savedVM,
                        premium: premium,
                        onOpenSearch: { selectedTab = 1 },
                        onOpenAlerts: { selectedTab = 2 },
                        alertBadgeCount: alertsVM.unreadCount
                    )
                    .applyBG()
                    .tag(0)

                    SearchView(savedVM: savedVM, currentMarket: feedVM.selectedMarket)
                        .applyBG()
                        .tag(1)

                    AlertsView(alertsVM: alertsVM, savedVM: savedVM, premium: premium)
                        .applyBG()
                        .tag(2)

                    YouView(savedVM: savedVM, feedVM: feedVM, premium: premium)
                        .applyBG()
                        .tag(3)
                }

                CustomTabBar(
                    selectedTab: $selectedTab,
                    alertBadgeCount: alertsVM.unreadCount,
                    bottomSafeInset: bottomInset
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(AppTheme.background)
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea()
        .task {
            await savedVM.loadAll(market: feedVM.selectedMarket)
            alertsVM.startPolling()
            await premium.checkEntitlements()
        }
        .onChange(of: feedVM.selectedMarket) { _, _ in
            Task { await savedVM.loadAll(market: feedVM.selectedMarket) }
        }
    }
}

private extension View {
    func applyBG() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

// MARK: - SearchView

struct SearchView: View {
    @StateObject private var searchVM = SearchViewModel()
    @ObservedObject var savedVM: SavedViewModel
    var currentMarket: String

    var body: some View {
        VStack(spacing: 0) {
            // Sticky header with title + market context
            searchHeader
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.top, AppTheme.spacingLG)
                .padding(.bottom, AppTheme.spacingSM)

            // Sticky filter area
            filterSection

            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 0.5)

            // Scrollable results
            resultsScrollView
        }
        .background(AppTheme.background)
        .task {
            if !searchVM.hasSearched {
                await searchVM.loadResults(market: currentMarket)
            }
        }
        .onChange(of: searchVM.selectedDates)      { _, _ in Task { await searchVM.loadResults(market: currentMarket) } }
        .onChange(of: searchVM.selectedTimeFilter) { _, _ in Task { await searchVM.loadResults(market: currentMarket) } }
        .onChange(of: searchVM.selectedPartySizes) { _, _ in Task { await searchVM.loadResults(market: currentMarket) } }
        .onChange(of: currentMarket)               { _, _ in Task { await searchVM.loadResults(market: currentMarket) } }
    }

    // MARK: - Header

    private var searchHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Search")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("\(currentMarket == "miami" ? "Miami" : "New York") · \(searchVM.selectedDateLabel)")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
            }
            Spacer()
            if searchVM.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accent))
                    .frame(width: 44, height: 44)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: searchVM.isLoading)
    }

    // MARK: - Filter section

    private var filterSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spacingLG) {
                filterGroup("Date")   { datePills }
                filterGroup("Time")   { timePills }
                filterGroup("Party size") { partySizePills }

                if let error = searchVM.error {
                    errorBanner(error)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 260)
        .background(AppTheme.background)
    }

    private func filterGroup<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            FlowLayout(spacing: 8) {
                content()
            }
        }
    }

    // MARK: - Date pills

    private var datePills: some View {
        Group {
            pillButton(
                label: "All dates",
                isSelected: searchVM.selectedDates.isEmpty
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    searchVM.selectedDates = []
                }
            }
            ForEach(searchVM.dateOptions, id: \.dateStr) { opt in
                pillButton(
                    label: "\(opt.dayName) \(opt.dayNum)",
                    isSelected: searchVM.selectedDates.contains(opt.dateStr)
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        searchVM.selectedDates = [opt.dateStr]
                    }
                }
            }
        }
    }

    // MARK: - Time pills

    private var timePills: some View {
        Group {
            ForEach(SearchViewModel.timeOptions, id: \.key) { opt in
                pillButton(
                    label: opt.label,
                    isSelected: searchVM.selectedTimeFilter == opt.key
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        searchVM.selectedTimeFilter = opt.key
                    }
                }
            }
        }
    }

    // MARK: - Party size pills

    private var partySizePills: some View {
        Group {
            pillButton(
                label: "Any",
                isSelected: searchVM.selectedPartySizes.isEmpty
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    searchVM.selectedPartySizes = []
                }
            }
            ForEach(SearchViewModel.partySizeOptions, id: \.self) { size in
                let isSelected = searchVM.selectedPartySizes.contains(size)
                pillButton(label: "\(size)", isSelected: isSelected) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        if isSelected {
                            searchVM.selectedPartySizes.remove(size)
                        } else {
                            searchVM.selectedPartySizes.insert(size)
                        }
                    }
                }
            }
        }
    }

    private func pillButton(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.spacingSM) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.accentRed)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accentRed.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Results scroll view

    private var resultsScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if searchVM.isLoading && searchVM.results.isEmpty {
                    searchLoadingSkeleton
                } else if !searchVM.hasSearched {
                    EmptyView()
                } else if searchVM.results.isEmpty {
                    searchEmptyState
                } else {
                    searchResultsHeader
                    ForEach(searchVM.results) { drop in
                        SearchResultRow(
                            drop: drop,
                            isWatched: savedVM.isWatched(drop.name)
                        ) {
                            savedVM.toggleWatch(drop.name)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.top, AppTheme.spacingLG)
            .padding(.bottom, 120)
        }
        .background(AppTheme.background)
    }

    private var searchResultsHeader: some View {
        HStack {
            Text("\(searchVM.results.count) result\(searchVM.results.count == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
            Spacer()
        }
    }

    private var searchLoadingSkeleton: some View {
        VStack(spacing: AppTheme.spacingSM) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.surface)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(AppTheme.surface).frame(height: 14).frame(maxWidth: 180)
                        RoundedRectangle(cornerRadius: 4).fill(AppTheme.surface).frame(height: 10).frame(maxWidth: 120)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shimmer()
            }
        }
    }

    private var searchEmptyState: some View {
        VStack(spacing: AppTheme.spacingLG) {
            ZStack {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 70, height: 70)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(AppTheme.textTertiary)
            }
            VStack(spacing: AppTheme.spacingSM) {
                Text("No tables found")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Try different dates, a different time, or a larger party size to see more options.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: () -> Void

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var slotSummary: String {
        let count = drop.slots.count
        if count > 1 { return "\(count) times available" }
        if let t = drop.slots.first?.time { return formatTime(t) }
        return "Table available"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { AppTheme.surface }
                    }
                } else { AppTheme.surface }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(drop.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                if let nb = drop.neighborhood, !nb.isEmpty {
                    Text(nb)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                }
                HStack(spacing: 6) {
                    Text(slotSummary)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    ScarcityBadge(tier: drop.scarcityTier)
                }
            }

            Spacer(minLength: AppTheme.spacingSM)

            VStack(spacing: 6) {
                if let url = resyUrl {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Text("Reserve")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentOrange)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                Button { onToggleWatch() } label: {
                    Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundColor(isWatched ? AppTheme.accentOrange : AppTheme.textTertiary)
                        .frame(width: 44, height: 28)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: isWatched)
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

    private func formatTime(_ time: String) -> String {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return time }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "am" : "pm"
        return m > 0 ? "\(hour12):\(String(format: "%02d", m))\(ampm)" : "\(hour12)\(ampm)"
    }
}

// MARK: - FlowLayout (wrapping pill container)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            let position = CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY)
            subviews[index].place(at: position, proposal: ProposedViewSize(frame.size))
        }
    }

    private struct LayoutResult {
        var frames: [CGRect]
        var size: CGSize
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowMaxY: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > maxWidth && origin.x > 0 {
                origin.x = 0
                origin.y = rowMaxY + spacing
            }
            frames.append(CGRect(origin: origin, size: size))
            rowMaxY = max(rowMaxY, origin.y + size.height)
            totalHeight = max(totalHeight, origin.y + size.height)
            origin.x += size.width + spacing
        }

        return LayoutResult(frames: frames, size: CGSize(width: maxWidth, height: totalHeight))
    }
}

#Preview {
    ContentView()
}
