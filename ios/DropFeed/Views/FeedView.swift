import SwiftUI

private struct SeeAllDestination: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let drops: [Drop]
    let style: AllDropsListView.Style

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SeeAllDestination, rhs: SeeAllDestination) -> Bool { lhs.id == rhs.id }
}

struct FeedView: View {
    @StateObject private var vm = FeedViewModel()
    @State private var seeAllDestination: SeeAllDestination?
    @State private var showFilterSheet = false
    
    private var viewStateId: String {
        if vm.isLoading && vm.drops.isEmpty { return "loading" }
        if vm.error != nil { return "error" }
        if vm.drops.isEmpty { return "empty" }
        return "content"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LiveUpdateTrainBar()
                Group {
                if vm.isLoading && vm.drops.isEmpty {
                    loadingView
                } else if let err = vm.error {
                    errorView(err)
                } else if vm.drops.isEmpty {
                    emptyView
                } else {
                    feedContent
                }
            }
            .id(viewStateId)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity
            ))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewStateId)
            .refreshable {
                // Run in detached task so pull-to-refresh completes even if SwiftUI cancels the refreshable task
                _ = await Task.detached(priority: .userInitiated) { @MainActor in
                    await vm.refresh()
                }.value
            }
            .task {
                await vm.refresh()
                vm.startPolling()
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $seeAllDestination) { dest in
                AllDropsListView(title: dest.title, drops: dest.drops, style: dest.style)
            }
            }
        }
    }
    
    private var loadingView: some View {
        FeedSkeletonView()
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.textTertiary)
            Text("No drops yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
            Text("New tables will appear when they open. Scout runs every minute.")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
    
    private static let hotReleasesPreviewCount = 3
    private static let hotRightNowPreviewCount = 4
    private static let allDropsPreviewCount = 6
    
    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                filtersSection
                if let top = vm.topOpportunities, !top.isEmpty {
                    VStack(spacing: 0) {
                        hotReleasesSectionHeader
                        topOpportunitiesSection(Array(top.prefix(Self.hotReleasesPreviewCount)), all: top)
                    }
                    .padding(.vertical, 16)
                    .background(AppTheme.background)
                }
                
                VStack(spacing: 24) {
                    if let hot = vm.hotRightNow, !hot.isEmpty {
                        sectionWithSeeAll(
                            "Hot Right Now",
                            updated: vm.lastScanText,
                            preview: Array(hot.prefix(Self.hotRightNowPreviewCount)),
                            all: hot,
                            style: .grid,
                            lightBackground: false,
                            seeAllBinding: $seeAllDestination
                        )
                    }
                    
                    sectionWithSeeAll(
                        "All Drops",
                        updated: vm.lastScanText,
                        preview: Array(vm.drops.prefix(Self.allDropsPreviewCount)),
                        all: vm.drops,
                        style: .grid,
                        lightBackground: false,
                        seeAllBinding: $seeAllDestination
                    )
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(AppTheme.background)
            }
        }
        .background(AppTheme.background)
    }
    
    private var filtersSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                AnimatedLiveDot()
                Text("LIVE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }
            Spacer(minLength: 8)
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Text(selectedDateLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("·")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(selectedTimeLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.surface)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(AppTheme.background)
        .sheet(isPresented: $showFilterSheet) {
            DateTimeFilterSheet(vm: vm)
        }
    }
    
    private var selectedDateLabel: String {
        let dateStr = vm.selectedDate.isEmpty ? (vm.dateOptions.first ?? "") : vm.selectedDate
        let (day, monthDay) = formatDateOption(dateStr)
        if day.isEmpty && monthDay.isEmpty { return "Today" }
        return day.isEmpty ? monthDay : "\(day), \(monthDay)"
    }
    
    private var selectedTimeLabel: String {
        switch vm.selectedTimeFilter {
        case "lunch": return "Lunch"
        case "3pm": return "Afternoon"
        case "7pm": return "Early dinner"
        case "dinner": return "Late dinner"
        default: return "All"
        }
    }
    
    private var hotReleasesSectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 18))
                .foregroundColor(AppTheme.accentRed)
            Text("HOT RELEASES")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
    
    private func formatDateOption(_ dateStr: String) -> (day: String, monthDay: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let d = formatter.date(from: dateStr) else { return ("", dateStr) }
        let cal = Calendar.current
        let day: String = {
            let weekday = cal.component(.weekday, from: d)
            let symbols = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return weekday >= 1 && weekday <= 7 ? symbols[weekday] : ""
        }()
        let month = cal.shortMonthSymbols[cal.component(.month, from: d) - 1]
        let dayNum = cal.component(.day, from: d)
        return (day, "\(month) \(dayNum)")
    }
    
    private func sectionWithSeeAll(
        _ title: String,
        updated: String,
        preview: [Drop],
        all: [Drop],
        style: AllDropsListView.Style,
        lightBackground: Bool = false,
        seeAllBinding: Binding<SeeAllDestination?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if !updated.isEmpty, updated != "—" {
                    Text(updated)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                if all.count > preview.count {
                    Button {
                        seeAllBinding.wrappedValue = SeeAllDestination(title: title, drops: all, style: style)
                    } label: {
                        Text("See all")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .frame(minWidth: 60, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            
            if style == .grid {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(Array(preview.enumerated()), id: \.element.id) { index, drop in
                        DropCardView(drop: drop)
                            .staggeredAppear(index: index, delayPerItem: 0.04)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func topOpportunitiesSection(_ preview: [Drop], all: [Drop]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(preview.enumerated()), id: \.element.id) { index, drop in
                        TopOpportunityCardView(drop: drop)
                            .staggeredAppear(index: index, delayPerItem: 0.06)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func sectionHeader(_ title: String, updated: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            if !updated.isEmpty && updated != "—" {
                Text(updated)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

#Preview("Feed") {
    FeedView()
}
