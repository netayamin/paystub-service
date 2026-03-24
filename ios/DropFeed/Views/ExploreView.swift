import SwiftUI

/// Explore tab — light editorial layout: header, horizontal availability strip, 2-column live inventory grid (reference UI).
struct ExploreView: View {
    @ObservedObject var vm: SearchViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager

    /// Page index aligned with `SearchViewModel.dateOptions` (next 14 days).
    @State private var exploreDatePageIndex: Int = 0
    @State private var showFilterSheet = false
    @State private var showExploreMenu = false

    private var gridColumnSpacing: CGFloat { DropFeedTokens.Layout.gridColumnSpacing }
    private var gridRowSpacing: CGFloat { DropFeedTokens.Layout.gridRowSpacing }
    private var exploreCardCorner: CGFloat { DropFeedTokens.Layout.exploreCardCornerRadius }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            exploreTopBar
            exploreAvailabilitySection
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let err = vm.error {
                        errorBanner(err).padding(.top, 12)
                    }
                    liveInventoryHeader
                        .padding(.top, 18)
                    gridSection
                        .padding(.top, 16)
                    Color.clear.frame(height: 88)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DropFeedTokens.Layout.screenPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .background(CreamEditorialTheme.canvas.ignoresSafeArea())
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
        .sheet(isPresented: $showFilterSheet) {
            exploreFilterSheet
        }
        .sheet(isPresented: $showExploreMenu) {
            exploreMenuSheet
        }
    }

    // MARK: - Top bar

    /// Two rows: avoids one ultra-wide `HStack` inflating past the screen on Pro-size phones.
    private var exploreTopBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    showExploreMenu = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(CreamEditorialTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Text("EXPLORE")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(CreamEditorialTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text(exploreMarketLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .lineLimit(1)
                Circle()
                    .fill(Color(red: 52 / 255, green: 199 / 255, blue: 147 / 255))
                    .frame(width: 5, height: 5)
                Text("SYSTEM ONLINE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(exploreMarketLabel), system online")
        }
        .padding(.horizontal, DropFeedTokens.Layout.screenPadding)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exploreMarketLabel: String { "NYC" }

    // MARK: - Availability (reference: weekday above date, maroon selection, hairline under strip)

    private var exploreAvailabilitySection: some View {
        let pad = DropFeedTokens.Layout.screenPadding
        return VStack(alignment: .leading, spacing: 0) {
            DSSectionTitleRow(title: "Availability", trailing: exploreSelectedMonthYearUppercased)
                .padding(.horizontal, pad)
                .padding(.bottom, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(vm.dateOptions.enumerated()), id: \.element.dateStr) { idx, opt in
                        DSExploreDateChip(
                            weekday: weekdayAbbrev(for: opt.dateStr),
                            dayNumber: opt.dayNum,
                            isSelected: idx == exploreDatePageIndex
                        ) {
                            exploreDatePageIndex = idx
                            exploreApplyPageIndex(idx)
                        }
                    }
                }
                .padding(.horizontal, pad)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .frame(height: 72, alignment: .center)

            DSHairline(horizontalPadding: pad)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exploreSelectedMonthYearUppercased: String {
        guard vm.dateOptions.indices.contains(exploreDatePageIndex) else { return "" }
        let ds = vm.dateOptions[exploreDatePageIndex].dateStr
        let parts = ds.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]) else { return "" }
        let months = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
                      "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
        let name = months[(mo - 1).clamped(to: 0 ... 11)]
        return "\(name) \(y)"
    }

    private func weekdayAbbrev(for dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else {
            return "—"
        }
        var c = DateComponents()
        c.year = y
        c.month = mo
        c.day = d
        guard let date = Calendar.current.date(from: c) else { return "—" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE"
        return df.string(from: date).uppercased()
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

    // MARK: - Live inventory

    private var liveInventoryHeader: some View {
        DSLabeledRuleRow(
            leadingLabel: "LIVE INVENTORY",
            trailingLabel: "NEW YORK"
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.system(size: 13))
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(CreamEditorialTheme.burgundy)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CreamEditorialTheme.peachBadgeFill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var gridSection: some View {
        let items = vm.rankedResults
        if vm.isLoading && items.isEmpty {
            ProgressView()
                .tint(CreamEditorialTheme.burgundy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if items.isEmpty {
            Text("No live tables for this day yet. Try another date.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CreamEditorialTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            let columns = [
                GridItem(.flexible(), spacing: gridColumnSpacing, alignment: .top),
                GridItem(.flexible(), spacing: gridColumnSpacing, alignment: .top),
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: gridRowSpacing) {
                ForEach(items) { drop in
                    exploreInventoryCell(drop)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exploreInventoryCell(_ drop: Drop) -> some View {
        DSExploreInventoryCard(
            drop: drop,
            selectedDateStr: vm.selectedDates.sorted().first,
            partySegment: vm.explorePartySegment,
            cornerRadius: exploreCardCorner,
            onTap: { exploreOpenBooking(for: drop) }
        )
        .frame(maxHeight: .infinity)
    }

    private func exploreOpenBooking(for drop: Drop) {
        guard let s = drop.effectiveResyBookingURL, let url = URL(string: s) else { return }
        APIService.shared.trackBehaviorEvents(events: [
            BehaviorTrackEvent(
                eventType: "resy_opened",
                venueId: drop.venueKey,
                venueName: drop.name,
                notificationId: nil,
                market: drop.market
            )
        ])
        UIApplication.shared.open(url)
    }

    // MARK: - Sheets

    private var exploreFilterSheet: some View {
        NavigationStack {
            Form {
                Section("Party size") {
                    Picker("Party", selection: $vm.explorePartySegment) {
                        Text("2 guests").tag(ExplorePartySegment.two)
                        Text("4+ guests").tag(ExplorePartySegment.four)
                        Text("Any").tag(ExplorePartySegment.anyParty)
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Text("Party size updates labels on cards. Inventory is loaded for the full selected day.")
                        .font(.system(size: 13))
                        .foregroundColor(CreamEditorialTheme.textTertiary)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showFilterSheet = false
                        Task { await vm.loadResults() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var exploreMenuSheet: some View {
        NavigationStack {
            List {
                Section {
                    Text("More from Quiet Curator is coming soon.")
                        .font(.system(size: 14))
                        .foregroundColor(CreamEditorialTheme.textSecondary)
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showExploreMenu = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ExploreView(
        vm: SearchViewModel(),
        savedVM: SavedViewModel(),
        premium: PremiumManager()
    )
}
