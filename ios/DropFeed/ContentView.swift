import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var feedVM = FeedViewModel()
    @StateObject private var savedVM = SavedViewModel()
    @StateObject private var alertsVM = AlertsViewModel()
    @StateObject private var premium = PremiumManager()
    
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
                    SearchView(savedVM: savedVM)
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
            await savedVM.loadAll()
            alertsVM.startPolling()
            await premium.checkEntitlements()
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

// MARK: - SearchView (in same file so Xcode always has it in scope)
struct SearchView: View {
    @StateObject private var searchVM = SearchViewModel()
    @ObservedObject var savedVM: SavedViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchHeader
                if searchVM.error != nil { searchErrorBanner }
                searchResultsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(AppTheme.background)
        .task {
            // Auto-load today's results on first appear
            if !searchVM.hasSearched {
                await searchVM.loadResults()
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text("Showing \(searchVM.selectedDateLabel) · Tap filters to refine.")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
        }
    }

    private var searchDateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
            FlowLayout(spacing: 8) {
                Button {
                    searchVM.selectedDates = []
                } label: {
                    Text("All dates")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(searchVM.selectedDates.isEmpty ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(searchVM.selectedDates.isEmpty ? AppTheme.pillSelected : AppTheme.pillUnselected)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                ForEach(searchVM.dateOptions, id: \.dateStr) { opt in
                    searchDateChip(opt.dateStr, dayLabel: opt.dayName, monthDay: opt.dayNum)
                }
            }
        }
    }

    private func searchDateChip(_ dateStr: String, dayLabel: String, monthDay: String) -> some View {
        let isSelected = searchVM.selectedDates.contains(dateStr)
        return Button {
            searchVM.selectedDates = [dateStr]
        } label: {
            Text("\(dayLabel) \(monthDay)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var searchTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time range")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
            FlowLayout(spacing: 8) {
                ForEach(SearchViewModel.timeOptions, id: \.key) { opt in
                    searchTimeChip(opt.key, label: opt.label)
                }
            }
        }
    }

    private func searchTimeChip(_ key: String, label: String) -> some View {
        let isSelected = searchVM.selectedTimeFilter == key
        return Button {
            searchVM.selectedTimeFilter = key
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private var searchPeopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Party size")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
            FlowLayout(spacing: 8) {
                Button {
                    searchVM.selectedPartySizes = []
                } label: {
                    Text("Any")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(searchVM.selectedPartySizes.isEmpty ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(searchVM.selectedPartySizes.isEmpty ? AppTheme.pillSelected : AppTheme.pillUnselected)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                ForEach(SearchViewModel.partySizeOptions, id: \.self) { size in
                    let isSelected = searchVM.selectedPartySizes.contains(size)
                    Button {
                        if isSelected {
                            searchVM.selectedPartySizes.remove(size)
                        } else {
                            searchVM.selectedPartySizes.insert(size)
                        }
                    } label: {
                        Text("\(size)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchButton: some View {
        Button {
            Task { await searchVM.loadResults() }
        } label: {
            HStack(spacing: 8) {
                if searchVM.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(searchVM.isLoading ? "Searching…" : "Search")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accentOrange)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(searchVM.isLoading)
    }

    private var searchErrorBanner: some View {
        Group {
            if let msg = searchVM.error {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.accentRed)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.accentRed.opacity(0.12))
                    .cornerRadius(10)
            }
        }
    }

    private var searchResultsSection: some View {
        Group {
            if !searchVM.hasSearched && !searchVM.isLoading {
                // auto-load hasn't triggered yet — show nothing
                EmptyView()
            } else if searchVM.isLoading && searchVM.results.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if searchVM.results.isEmpty {
                Text("No tables match your filters. Try different dates or party size.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(searchVM.results.count) result\(searchVM.results.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                    ForEach(searchVM.results) { drop in
                        SearchResultRow(drop: drop, isWatched: savedVM.isWatched(drop.name)) {
                            savedVM.toggleWatch(drop.name)
                        }
                    }
                }
            }
        }
    }
}

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
        if count > 1 { return "\(count) times" }
        if let t = drop.slots.first?.time { return formatTime(t) }
        return "Table available"
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            AppTheme.surface
                        }
                    }
                } else {
                    AppTheme.surface
                }
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
                Text(slotSummary)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                if resyUrl != nil {
                    Button {
                        if let u = resyUrl { UIApplication.shared.open(u) }
                    } label: {
                        Text("Reserve")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentOrange)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    onToggleWatch()
                } label: {
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

    private func formatTime(_ time: String) -> String {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return time }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "am" : "pm"
        return m > 0 ? "\(hour12):\(String(format: "%02d", m))\(ampm)" : "\(hour12)\(ampm)"
    }
}

#Preview {
    ContentView()
}
