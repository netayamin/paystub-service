import SwiftUI

// MARK: - Root container

struct ContentView: View {
    @StateObject private var feedVM  = FeedViewModel()
    @StateObject private var savedVM = SavedViewModel()
    @StateObject private var premium = PremiumManager()
    @State private var selectedTab = 0

    var body: some View {
        GeometryReader { geo in
            let bottomInset = geo.safeAreaInsets.bottom
            // VStack: content fills remaining space, tab bar sits below — no overlap.
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case 0:
                        FeedView(feedVM: feedVM, savedVM: savedVM, premium: premium)
                    default:
                        SearchView(savedVM: savedVM)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                CustomTabBar(selectedTab: $selectedTab, bottomSafeInset: bottomInset)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            await savedVM.loadAll()
            await premium.checkEntitlements()
        }
    }
}

// MARK: - Search tab

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @ObservedObject var savedVM: SavedViewModel

    private let palette = FeedPalette.liveFeedLight

    var body: some View {
        VStack(spacing: 0) {
            // ── Page header ──────────────────────────────────────────────
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(palette.textPrimary)
                    Text("Find available tables by date, size & time")
                        .font(.system(size: 13))
                        .foregroundColor(palette.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .background(palette.pageBackground)

            // ── Scroll body ──────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Filter card
                    VStack(alignment: .leading, spacing: 0) {
                        whenSection
                        divider
                        whoSection
                        divider
                        timeframeSection
                        searchButton
                            .padding(.top, 4)
                    }
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)

                    // Error
                    if let err = vm.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 15))
                            Text(err)
                                .font(.system(size: 13))
                        }
                        .foregroundColor(palette.accentRed)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.accentRed.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // Results
                    resultsSection
                        .padding(.horizontal, 16)
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(palette.pageBackground)
        }
        .background(palette.pageBackground)
        .task {
            if !vm.hasSearched { await vm.loadResults() }
        }
    }

    // MARK: - When? (date strip)

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("When?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(palette.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.dateOptions, id: \.dateStr) { opt in
                        dateChip(opt)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.bottom, 20)
    }

    private func dateChip(_ opt: (dateStr: String, dayName: String, dayNum: String)) -> some View {
        let sel = vm.selectedDates.contains(opt.dateStr)
        return Button {
            vm.selectedDates = [opt.dateStr]
            Task { await vm.loadResults() }
        } label: {
            VStack(spacing: 4) {
                Text(opt.dayName.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                Text(opt.dayNum)
                    .font(.system(size: 20, weight: .bold))
            }
            .foregroundColor(sel ? .white : palette.textSecondary)
            .frame(width: 54, height: 62)
            .background(sel ? Color(red: 0.11, green: 0.14, blue: 0.22) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(sel ? Color.clear : palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Who? (party size)

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Who?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(palette.textPrimary)

            HStack(spacing: 10) {
                ForEach([1, 2, 3, 4], id: \.self) { size in
                    partySizeChip(size)
                }
            }
        }
        .padding(.vertical, 20)
    }

    private func partySizeChip(_ size: Int) -> some View {
        let sel = vm.selectedPartySize == size
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.selectedPartySize = sel ? nil : size
            }
        } label: {
            Text(size >= 4 ? "4+" : "\(size)")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(sel ? .white : palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(sel ? palette.accentRed : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(sel ? Color.clear : palette.border, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timeframe?

    private var timeframeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeframe?")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Text(vm.timeframeName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(palette.textSecondary)
            }

            HStack(spacing: 12) {
                timePicker("EARLIEST", hour: $vm.earliestHour, label: vm.earliestLabel)
                timePicker("LATEST",   hour: $vm.latestHour,   label: vm.latestLabel)
            }
        }
        .padding(.vertical, 20)
    }

    private func timePicker(_ title: String, hour: Binding<Int>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(palette.textTertiary)
                .tracking(0.6)

            Menu {
                ForEach(SearchViewModel.timeHours, id: \.hour) { opt in
                    Button(opt.label) { hour.wrappedValue = opt.hour }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(palette.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(palette.pageBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search button

    private var searchButton: some View {
        Button {
            Task { await vm.loadResults() }
        } label: {
            HStack(spacing: 8) {
                if vm.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(vm.isLoading ? "Searching…" : "Search")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(palette.accentRed)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(vm.isLoading)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if vm.isLoading && vm.results.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding tables…")
                    .font(.system(size: 14))
                    .foregroundColor(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else if vm.hasSearched && vm.results.isEmpty && !vm.isLoading {
            VStack(spacing: 14) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 36))
                    .foregroundColor(palette.textTertiary)
                Text("No tables found")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(palette.textSecondary)
                Text("Try a different date or party size")
                    .font(.system(size: 13))
                    .foregroundColor(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if !vm.results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(vm.results.count) table\(vm.results.count == 1 ? "" : "s") available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.textSecondary)

                ForEach(vm.results) { drop in
                    SearchResultCard(drop: drop, isWatched: savedVM.isWatched(drop.name)) {
                        savedVM.toggleWatch(drop.name)
                    }
                }
            }
        }
    }

    // MARK: - Divider helper

    private var divider: some View {
        Divider()
            .background(palette.border)
    }
}

// MARK: - Search result card

private struct SearchResultCard: View {
    let drop: Drop
    let isWatched: Bool
    let onToggleWatch: () -> Void

    private let palette = FeedPalette.liveFeedLight

    private var resyUrl: URL? {
        guard let s = drop.resyUrl ?? drop.slots.first?.resyUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    private var dateLabel: String {
        let ds = drop.dateStr ?? drop.slots.first?.dateStr ?? ""
        let parts = ds.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "" }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        let cal = Calendar.current
        guard let date = cal.date(from: comps) else { return "" }
        if cal.isDateInToday(date)    { return "Tonight" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return "\(m)/\(d)"
    }

    private var slotsLabel: String {
        let count = drop.slots.count
        if count == 0 { return "Available" }
        if count == 1, let t = drop.slots.first?.time { return formatTime(t) }
        return "\(count) time slots"
    }

    private func formatTime(_ t: String) -> String {
        let p = t.split(separator: ":")
        guard let h = p.first.flatMap({ Int($0) }) else { return t }
        let m  = p.count > 1 ? (Int(p[1].prefix(2)) ?? 0) : 0
        let h12 = h % 12 == 0 ? 12 : h % 12
        let ap  = h < 12 ? "AM" : "PM"
        return m > 0 ? "\(h12):\(String(format: "%02d", m)) \(ap)" : "\(h12) \(ap)"
    }

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            Group {
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color(white: 0.92) }
                    }
                } else {
                    Color(white: 0.92)
                }
            }
            .frame(width: 66, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Info
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    if drop.feedHot == true {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(palette.accentRed)
                    }
                }

                HStack(spacing: 5) {
                    if !dateLabel.isEmpty {
                        Label(dateLabel, systemImage: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(palette.textSecondary)
                        Text("·")
                            .foregroundColor(palette.textTertiary)
                            .font(.system(size: 12))
                    }
                    Text(slotsLabel)
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSecondary)
                }
                .lineLimit(1)

                if let nb = drop.neighborhood ?? drop.location, !nb.isEmpty {
                    Text(nb)
                        .font(.system(size: 11))
                        .foregroundColor(palette.textTertiary)
                }
            }

            Spacer(minLength: 4)

            // Actions
            VStack(spacing: 8) {
                Button {
                    if let u = resyUrl { UIApplication.shared.open(u) }
                } label: {
                    Text("Reserve")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(palette.accentRed)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(resyUrl == nil)
                .opacity(resyUrl == nil ? 0.5 : 1)

                Button { onToggleWatch() } label: {
                    Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15))
                        .foregroundColor(isWatched ? palette.accentRed : palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
