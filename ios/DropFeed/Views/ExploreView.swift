import SwiftUI

/// Explore tab — dark NYC layout with date/party filters and time-bucket accordions (`just-opened` data).
struct ExploreView: View {
    @ObservedObject var vm: SearchViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var alertsVM: AlertsViewModel
    @ObservedObject var premium: PremiumManager

    @State private var expandedBuckets: Set<ExploreTimeBucket> = [.evening]
    @State private var showAlertsSheet = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topChrome
                    exploreTitle
                    datePills
                    partyRow
                    if let err = vm.error {
                        errorBanner(err)
                            .padding(.top, 14)
                    }
                    bucketsBlock
                        .padding(.top, 22)
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 20)
            }

            alertsFAB
                .padding(.trailing, 20)
                .padding(.bottom, 8)
        }
        .background(Color(red: 13 / 255, green: 13 / 255, blue: 13 / 255).ignoresSafeArea())
        .sheet(isPresented: $showAlertsSheet) {
            NavigationStack {
                AlertsView(alertsVM: alertsVM, savedVM: savedVM, premium: premium)
            }
        }
        .onAppear {
            vm.exploreTabActive = true
            vm.selectedMealPreset = nil
            vm.isSearchActive = true
            vm.applyExploreDatesFromPreset()
            syncExpandedBuckets()
            vm.startPolling()
        }
        .onDisappear {
            vm.exploreTabActive = false
            vm.stopPolling()
        }
    }

    // MARK: - Chrome

    private var topChrome: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(SnagDesignSystem.exploreRed)
                Text("Snag")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .foregroundColor(SnagDesignSystem.exploreRed)
            }
            Spacer()
            Text("NYC • LIVE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SnagDesignSystem.exploreRed.opacity(0.88))
                .tracking(1.0)
        }
        .padding(.top, 6)
    }

    private var exploreTitle: some View {
        Text("Explore NYC")
            .font(.system(size: 30, weight: .bold, design: .serif))
            .foregroundColor(.white)
            .padding(.top, 10)
    }

    private var datePills: some View {
        HStack(spacing: 8) {
            ForEach(ExploreDatePreset.allCases) { preset in
                let on = vm.exploreDatePreset == preset
                Button {
                    vm.exploreDatePreset = preset
                    vm.applyExploreDatesFromPreset()
                    Task { await vm.loadResults() }
                } label: {
                    Text(preset.label)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(on ? SnagDesignSystem.exploreRed : SnagDesignSystem.darkTextMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(on ? SnagDesignSystem.activePillBackground : Color(white: 0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 18)
    }

    private var partyRow: some View {
        HStack {
            Text("PARTY SIZE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(SnagDesignSystem.darkTextMuted)
                .tracking(0.9)
            Spacer()
            HStack(spacing: 4) {
                ForEach(ExplorePartySegment.allCases) { seg in
                    let on = vm.explorePartySegment == seg
                    Button {
                        vm.explorePartySegment = seg
                        Task { await vm.loadResults() }
                    } label: {
                        Text(seg.shortLabel)
                            .font(.system(size: 13, weight: on ? .bold : .medium))
                            .foregroundColor(on ? .white : SnagDesignSystem.darkTextMuted)
                            .frame(minWidth: 36, minHeight: 36)
                            .background(
                                Group {
                                    if on {
                                        Circle().fill(Color(white: 0.22))
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(white: 0.12))
            .clipShape(Capsule())
        }
        .padding(.top, 16)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.system(size: 13))
        }
        .foregroundColor(SnagDesignSystem.exploreRed)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SnagDesignSystem.exploreRed.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Accordions

    private var bucketsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            if vm.isLoading && vm.rankedResults.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(SnagDesignSystem.exploreCoral)
                    Text("Loading tables…")
                        .font(.system(size: 14))
                        .foregroundColor(SnagDesignSystem.darkTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else if vm.hasSearched && vm.rankedResults.isEmpty && !vm.isLoading {
                Text("No tables for these filters. Try another day or party size.")
                    .font(.system(size: 14))
                    .foregroundColor(SnagDesignSystem.darkTextMuted)
                    .padding(.vertical, 24)
            } else {
                ForEach(ExploreTimeBucket.allCases) { bucket in
                    bucketSection(bucket)
                }
            }
        }
    }

    private func bucketSection(_ bucket: ExploreTimeBucket) -> some View {
        let expanded = expandedBuckets.contains(bucket)
        let active = ExploreTimeBucket.isActiveNow(bucket)
        let drops = vm.exploreDrops(in: bucket)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(expanded && active ? SnagDesignSystem.exploreCoral : Color.clear)
                    .frame(width: 3)
                    .padding(.vertical, expanded ? 0 : 2)

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if expanded { expandedBuckets.remove(bucket) } else { expandedBuckets.insert(bucket) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: bucket.headerIcon)
                                .font(.system(size: 16))
                                .foregroundColor(headerIconColor(expanded: expanded, active: active))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(bucket.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(headerTitleColor(expanded: expanded, active: active))
                                    if expanded && active {
                                        Text("• ACTIVE")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(SnagDesignSystem.exploreCoral)
                                    }
                                }
                                Text(bucket.timeRangeLabel)
                                    .font(.system(size: 12))
                                    .foregroundColor(headerSubtitleColor(expanded: expanded, active: active))
                            }
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(SnagDesignSystem.darkTextMuted)
                        }
                        .padding(.vertical, 12)
                        .padding(.leading, 10)
                        .padding(.trailing, 4)
                    }
                    .buttonStyle(.plain)

                    if expanded {
                        if drops.isEmpty {
                            Text("Nothing in this time window.")
                                .font(.system(size: 13))
                                .foregroundColor(SnagDesignSystem.darkTextMuted)
                                .padding(.leading, 10)
                                .padding(.bottom, 12)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(drops) { drop in
                                    exploreCard(drop)
                                }
                            }
                            .padding(.leading, 10)
                            .padding(.bottom, 14)
                        }
                    }
                }
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func headerIconColor(expanded: Bool, active: Bool) -> Color {
        if expanded && active { return SnagDesignSystem.exploreCoral }
        return SnagDesignSystem.darkTextMuted
    }

    private func headerTitleColor(expanded: Bool, active: Bool) -> Color {
        if expanded && active { return SnagDesignSystem.exploreCoral.opacity(0.95) }
        return SnagDesignSystem.darkTextSecondary
    }

    private func headerSubtitleColor(expanded: Bool, active: Bool) -> Color {
        if expanded && active { return SnagDesignSystem.exploreCoral.opacity(0.65) }
        return SnagDesignSystem.darkTextMuted
    }

    // MARK: - Venue card

    private func exploreCard(_ drop: Drop) -> some View {
        let canSnag = drop.exploreCanSnag
        let url = resyURL(for: drop)

        return HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let s = drop.imageUrl, let u = URL(string: s) {
                        CardAsyncImage(url: u, contentMode: .fill, skeletonTone: .darkCard) {
                            Color(white: 0.2)
                        }
                    } else {
                        Color(white: 0.2)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if drop.exploreShowDot == true {
                    Circle()
                        .fill(SnagDesignSystem.exploreRed)
                        .frame(width: 7, height: 7)
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(drop.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let pill = venuePill(for: drop) {
                        Text(pill)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(SnagDesignSystem.exploreCoral)
                            .tracking(0.4)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .overlay(
                                Capsule()
                                    .stroke(SnagDesignSystem.exploreCoral.opacity(0.55), lineWidth: 1)
                            )
                            .lineLimit(1)
                    }
                }
                Text(exploreSubtitle(drop))
                    .font(.system(size: 11))
                    .foregroundColor(SnagDesignSystem.darkTextMuted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                if let tag = drop.exploreStatusTag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SnagDesignSystem.darkTextSecondary)
                        .tracking(0.6)
                }
                if canSnag {
                    Button {
                        if let url { UIApplication.shared.open(url) }
                    } label: {
                        Text("SNAG")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(SnagDesignSystem.exploreCoral)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(url == nil)
                    .opacity(url == nil ? 0.45 : 1)
                } else {
                    Text("TAKEN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SnagDesignSystem.darkTextMuted)
                        .tracking(0.8)
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func venuePill(for drop: Drop) -> String? {
        if let p = drop.exploreVenuePill, !p.isEmpty { return p }
        if let c = drop.crownBadgeLabel, c.count <= 18 { return c.uppercased() }
        return nil
    }

    private func exploreSubtitle(_ drop: Drop) -> String {
        let day = exploreDayWord(for: drop)
        let time = formatFirstSlotTime(drop)
        let party = partyGuestsLabel
        if time.isEmpty { return "\(day) • \(party)" }
        return "\(day) \(time) • \(party)"
    }

    private var partyGuestsLabel: String {
        switch vm.explorePartySegment {
        case .two: return "2 GUESTS"
        case .four: return "4 GUESTS"
        case .anyParty: return "ANY GUESTS"
        }
    }

    private func exploreDayWord(for drop: Drop) -> String {
        let ds = drop.dateStr ?? drop.slots.first?.dateStr ?? ""
        let parts = ds.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return "TONIGHT" }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        let cal = Calendar.current
        guard let date = cal.date(from: comps) else { return "TONIGHT" }
        if cal.isDateInToday(date) { return "TONIGHT" }
        if cal.isDateInTomorrow(date) { return "TOMORROW" }
        return "SOON"
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

    // MARK: - FAB

    private var alertsFAB: some View {
        Button {
            showAlertsSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(SnagDesignSystem.exploreCoral)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)

                if alertsVM.unreadCount > 0 {
                    Circle()
                        .fill(SnagDesignSystem.exploreRed)
                        .frame(width: 10, height: 10)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Alerts")
    }

    private func syncExpandedBuckets() {
        for b in ExploreTimeBucket.allCases where ExploreTimeBucket.isActiveNow(b) {
            expandedBuckets.insert(b)
        }
        if expandedBuckets.isEmpty {
            expandedBuckets = [.evening]
        }
    }
}

#Preview {
    ExploreView(
        vm: SearchViewModel(),
        savedVM: SavedViewModel(),
        alertsVM: AlertsViewModel(),
        premium: PremiumManager()
    )
}
