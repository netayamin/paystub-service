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

    private let gridColumnSpacing: CGFloat = 12
    private let gridRowSpacing: CGFloat = 16
    /// Photo area height inside each inventory card (2-column width scales with screen).
    private let gridImageHeight: CGFloat = 152

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
                        .padding(.top, 20)
                    gridSection
                        .padding(.top, 14)
                    Color.clear.frame(height: 88)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var exploreTopBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Button {
                showExploreMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
            }
            .buttonStyle(.plain)

            Text("EXPLORE")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .tracking(0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Text(exploreMarketLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .tracking(0.35)
                    .lineLimit(1)
                Circle()
                    .fill(Color(red: 52 / 255, green: 199 / 255, blue: 147 / 255))
                    .frame(width: 5, height: 5)
                Text("ONLINE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .tracking(0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(exploreMarketLabel), system online")
            .frame(minWidth: 0)
            .layoutPriority(-1)

            Button {
                showFilterSheet = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
    }

    private var exploreMarketLabel: String {
        let m = vm.results.first?.market?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m, !m.isEmpty { return m.uppercased() }
        return "NYC"
    }

    // MARK: - Availability (horizontal date strip)

    private var exploreAvailabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Availability")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(exploreSelectedMonthYearUppercased)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textTertiary)
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 16)

            // Horizontal ScrollView can report very wide ideal size; pin width so the tab does not overflow horizontally.
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(vm.dateOptions.enumerated()), id: \.element.dateStr) { idx, opt in
                            exploreDateChip(index: idx, opt: opt)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(width: geo.size.width, alignment: .leading)
            }
            .frame(height: 64)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
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

    private func exploreDateChip(index idx: Int, opt: (dateStr: String, monthAbbrev: String, dayNum: String)) -> some View {
        let selected = idx == exploreDatePageIndex
        return Button {
            exploreDatePageIndex = idx
            exploreApplyPageIndex(idx)
        } label: {
            VStack(spacing: 4) {
                Text(weekdayAbbrev(for: opt.dateStr))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(selected ? CreamEditorialTheme.burgundy : CreamEditorialTheme.textTertiary)
                    .tracking(0.35)
                Text(opt.dayNum)
                    .font(.system(size: 16, weight: selected ? .heavy : .semibold))
                    .foregroundColor(selected ? CreamEditorialTheme.burgundy : CreamEditorialTheme.textSecondary)
            }
            .frame(minWidth: 44)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Group {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CreamEditorialTheme.burgundy.opacity(0.08))
                    }
                }
            )
        }
        .buttonStyle(.plain)
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("LIVE INVENTORY")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .tracking(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Text(exploreMarketLabel == "NYC" ? "NEW YORK" : exploreMarketLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(CreamEditorialTheme.textTertiary)
                .tracking(0.45)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 0, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
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
            VStack(alignment: .leading, spacing: gridRowSpacing) {
                ForEach(Array(pairedGridDrops(items).enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: gridColumnSpacing) {
                        ForEach(pair) { drop in
                            exploreInventoryCell(drop)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        if pair.count == 1 {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pairedGridDrops(_ items: [Drop]) -> [[Drop]] {
        stride(from: 0, to: items.count, by: 2).map { i in
            if i + 1 < items.count {
                return [items[i], items[i + 1]]
            }
            return [items[i]]
        }
    }

    private func exploreInventoryCell(_ drop: Drop) -> some View {
        let url = resyURL(for: drop)
        return Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    gridThumb(drop)
                        .frame(maxWidth: .infinity)
                        .frame(height: gridImageHeight)
                        .clipped()

                    Text(slotTimeOnly(drop))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(8)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 14,
                        style: .continuous
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(drop.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(CreamEditorialTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.85)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(CreamEditorialTheme.textSecondary)
                            .layoutPriority(1)
                    }

                    Text(exploreCuisineLine(drop))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CreamEditorialTheme.textTertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(CreamEditorialTheme.burgundy)
                        Text(exploreInventoryStatusLine(drop))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(CreamEditorialTheme.burgundy)
                            .tracking(0.25)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(CreamEditorialTheme.peachBadgeFill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CreamEditorialTheme.cardWhite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CreamEditorialTheme.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
            )
            .shadow(color: CreamEditorialTheme.cardShadow, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gridThumb(_ drop: Drop) -> some View {
        if let s = drop.imageUrl, let u = URL(string: s) {
            CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .lightOnLight) {
                Color(white: 0.93)
            }
        } else {
            Color(white: 0.93)
        }
    }

    private func exploreCuisineLine(_ drop: Drop) -> String {
        let nb = drop.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let s = drop.metricsSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            if !nb.isEmpty, s.count < 36 {
                return "\(s) • \(nb)"
            }
            return s
        }
        if let line = drop.topOpportunitySubtitleLine?.trimmingCharacters(in: .whitespacesAndNewlines),
           !line.isEmpty, line.count < 42 {
            if !nb.isEmpty { return "\(line) • \(nb)" }
            return line
        }
        if !nb.isEmpty {
            return "Prime tables • \(nb)"
        }
        if let loc = drop.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            return "Tonight • \(loc)"
        }
        return "Tonight’s inventory"
    }

    private func exploreInventoryStatusLine(_ drop: Drop) -> String {
        if let tag = drop.exploreStatusTag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
            return tag.uppercased()
        }
        if let sc = drop.feedScarcityLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !sc.isEmpty {
            return sc.uppercased()
        }
        if let s = drop.snagScore {
            return "\(min(99, max(1, s)))% OPENING CHANCE"
        }
        if drop.velocityUrgent == true || drop.speedTier == "fast" {
            return "HIGH LIQUIDITY"
        }
        if let r = drop.rarityPoints, r > 0, r <= 12 {
            return "\(r) TABLES LEFT"
        }
        if drop.exploreSnagAvailable != false, drop.effectiveResyBookingURL != nil {
            return "INSTANT CONFIRM"
        }
        return "LIVE SLOT"
    }

    private func slotTimeOnly(_ drop: Drop) -> String {
        let t = formatFirstSlotTime(drop)
        if !t.isEmpty { return t }
        return "Tonight"
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
                    Text("Results refresh for the selected day and party.")
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
