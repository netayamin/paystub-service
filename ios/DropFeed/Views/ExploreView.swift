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

    private let gridColumnSpacing: CGFloat = 14
    private let gridRowSpacing: CGFloat = 20
    /// Photo block — reference shows a tall hero image with bottom labels.
    private let gridImageHeight: CGFloat = 178
    private let exploreCardCorner: CGFloat = 8

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
                .padding(.horizontal, 16)
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
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exploreMarketLabel: String {
        let m = vm.results.first?.market?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m, !m.isEmpty { return m.uppercased() }
        return "NYC"
    }

    // MARK: - Availability (reference: weekday above date, maroon selection, hairline under strip)

    private var exploreAvailabilitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Availability")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(CreamEditorialTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(exploreSelectedMonthYearUppercased)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CreamEditorialTheme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.55)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(vm.dateOptions.enumerated()), id: \.element.dateStr) { idx, opt in
                        exploreDateChip(index: idx, opt: opt)
                    }
                }
                .padding(.horizontal, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .frame(height: 72, alignment: .center)

            Rectangle()
                .fill(CreamEditorialTheme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 16)
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

    private func exploreDateChip(index idx: Int, opt: (dateStr: String, monthAbbrev: String, dayNum: String)) -> some View {
        let selected = idx == exploreDatePageIndex
        let muted = CreamEditorialTheme.textTertiary
        return Button {
            exploreDatePageIndex = idx
            exploreApplyPageIndex(idx)
        } label: {
            VStack(spacing: 5) {
                Text(weekdayAbbrev(for: opt.dateStr))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(selected ? CreamEditorialTheme.burgundy : muted)
                    .tracking(0.45)
                    .textCase(.uppercase)
                Text(opt.dayNum)
                    .font(.system(size: selected ? 18 : 15, weight: selected ? .heavy : .semibold))
                    .foregroundColor(selected ? CreamEditorialTheme.burgundy : CreamEditorialTheme.textSecondary)
            }
            .frame(minWidth: 40)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
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

    /// Reference: grey label + hairline to the right + maroon city on the far right.
    private var liveInventoryHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("LIVE INVENTORY")
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(CreamEditorialTheme.textSecondary)
                .tracking(0.95)
                .textCase(.uppercase)
                .lineLimit(1)
            Rectangle()
                .fill(CreamEditorialTheme.hairline)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Text(exploreMarketLabel == "NYC" ? "NEW YORK" : exploreMarketLabel)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(CreamEditorialTheme.burgundy)
                .tracking(0.5)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
                // Image + bottom gradient labels (reference: TONIGHT / date row, then time + PAX).
                ZStack(alignment: .bottomLeading) {
                    gridThumb(drop)
                        .frame(maxWidth: .infinity)
                        .frame(height: gridImageHeight)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.0), location: 0.35),
                            .init(color: .black.opacity(0.55), location: 0.78),
                            .init(color: .black.opacity(0.82), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: gridImageHeight)
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(exploreImageNightLabel(for: drop))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .tracking(0.55)
                            .textCase(.uppercase)

                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(slotTimeOnly(drop))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(explorePaxLabel(for: drop))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.88))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.bottom, 12)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                }
                .frame(height: gridImageHeight)
                .clipped()

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(drop.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(CreamEditorialTheme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.85)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(CreamEditorialTheme.textSecondary)
                            .layoutPriority(1)
                    }

                    Text(exploreCuisineLine(drop))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(CreamEditorialTheme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(CreamEditorialTheme.burgundy)
                        Text(exploreInventoryStatusLine(drop))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(CreamEditorialTheme.burgundy)
                            .tracking(0.35)
                            .textCase(.uppercase)
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                            .multilineTextAlignment(.leading)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(exploreStatusPillBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CreamEditorialTheme.cardWhite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CreamEditorialTheme.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: exploreCardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: exploreCardCorner, style: .continuous)
                    .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var exploreStatusPillBackground: Color {
        Color(red: 0.97, green: 0.96, blue: 0.94)
    }

    /// "TONIGHT" when slot date matches selected explore day; else "FRI OCT 18" style.
    private func exploreImageNightLabel(for drop: Drop) -> String {
        let selected = vm.selectedDates.sorted().first
        let slotDateOpt = drop.slots.first?.dateStr ?? drop.dateStr
        guard let slotDate = slotDateOpt, !slotDate.isEmpty else { return "TONIGHT" }
        if let selected, slotDate == selected { return "TONIGHT" }
        return exploreFormatSlotHeaderDate(slotDate) ?? "TONIGHT"
    }

    private func exploreFormatSlotHeaderDate(_ dateStr: String) -> String? {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var c = DateComponents()
        c.year = y
        c.month = mo
        c.day = d
        guard let date = Calendar.current.date(from: c) else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE MMM d"
        return df.string(from: date).uppercased()
    }

    private func explorePaxLabel(for drop: Drop) -> String {
        switch vm.explorePartySegment {
        case .two:
            return "2 PAX"
        case .four:
            return "4 PAX"
        case .anyParty:
            if let p = drop.partySizesAvailable.sorted().first, p > 0 {
                return "\(p) PAX"
            }
            return "2 PAX"
        }
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
