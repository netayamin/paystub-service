import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    private var refreshTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var tickerRotationTask: Task<Void, Never>?
    private var liveListRotationTask: Task<Void, Never>?
    private var tickerSlotIndex: Int = 0   // which slot gets swapped next

    @Published var drops: [Drop] = []
    @Published var topOpportunities: [Drop]?
    @Published var hotRightNow: [Drop]?
    @Published var likelyToOpen: [LikelyToOpenVenue] = []
    @Published var isLoading = false       // true only on first load (no cards yet)
    @Published var isRefreshing = false    // true on silent background polls
    @Published var lastRefreshed: Date?    // wall-clock time of the last successful poll
    @Published var error: String?
    @Published var lastScanAt: Date?
    @Published var nextScanAt: Date?
    @Published var totalVenuesScanned: Int = 0
    @Published var newDropsCount: Int = 0
    @Published var secondsUntilNextScan: Int = 0
    @Published var tickerDrops: [Drop] = []
    /// Bumps on a timer so the home “live drops” list can rotate order between API refreshes.
    @Published private(set) var liveListShuffleToken: UInt64 = 0
    /// The 5 live-stream slots shown on the home feed â one slot rotates at a time.
    @Published private(set) var liveStreamSlots: [Drop] = []
    private var liveStreamSlotIndex: Int = 0

    @Published var selectedDates: Set<String> = []
    @Published var selectedPartySizes: Set<Int> = []
    @Published var selectedTimeFilter: String = "all"

    private let service = APIService.shared
    private var previousDropIds: Set<String> = []

    // MARK: - Derived

    var heroCard: Drop? { drops.first }

    /// Top drops prioritized by backend `top_opportunities` when available.
    var topDrops: [Drop] {
        if let top = topOpportunities, !top.isEmpty {
            return top
        }
        return Array(drops.prefix(4))
    }

    /// Pool for rotating ticker rows: same order as `drops`.
    /// `ranked_board` order comes from the discovery snapshot / feed builder — keep that order for the ticker pool.
    var justDropped: [Drop] { drops }

    var feedCards: [Drop] {
        guard drops.count > 1 else { return [] }
        return Array(drops.dropFirst())
    }

    var rareDrops: [Drop] {
        drops.filter { $0.feedsRareCarousel == true }
    }

    var trendingDrops: [Drop] {
        drops.filter { ($0.trendPct ?? 0) > 20 }.sorted { ($0.trendPct ?? 0) > ($1.trendPct ?? 0) }
    }

    /// Number of curated elite (hotspot) venues currently open.
    var eliteDropsCount: Int { drops.filter { $0.feedHot == true }.count }
    /// Number of truly rare venues (rarity > 70) currently open.
    var rareDropsCount:  Int { drops.filter { $0.feedsRareCarousel == true }.count }
    /// Number of venues whose availability is trending up vs last 14 days.
    var trendingCount:   Int { drops.filter { ($0.trendPct ?? 0) > 10 }.count }

    /// Venues from likelyToOpen that have a drop likelihood for today specifically
    var likelyTodayVenues: [LikelyToOpenVenue] {
        likelyToOpen.filter { ($0.probability ?? 0) >= 50 }.prefix(5).map { $0 }
    }

    /// likelyToOpen sorted by backend forecast score (1–99) descending.
    var forecastVenues: [LikelyToOpenVenue] {
        likelyToOpen
            .filter { $0.probability != nil }
            .sorted { ($0.probability ?? 0) > ($1.probability ?? 0) }
    }

    /// Live drops where tables disappear quickly — backend `speed_tier` == fast.
    var fastVanishDrops: [Drop] {
        drops.filter { $0.speedTier == "fast" }
    }

    /// Neighborhoods with active drop counts — fully derived from live drops, no hardcoding.
    var hotZones: [(name: String, activeCount: Int)] {
        var counts: [String: Int] = [:]
        for drop in drops {
            let nb = drop.neighborhood ?? ""
            if !nb.isEmpty {
                counts[nb, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { (name: $0.key, activeCount: $0.value) }
    }

    /// Next 14 days for date picker (YYYY-MM-DD)
    var dateOptions: [(dateStr: String, dayName: String, dayNum: String)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<14).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            let y = cal.component(.year, from: d)
            let m = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            let dateStr = String(format: "%04d-%02d-%02d", y, m, day)
            let dayName: String = {
                if offset == 0 { return "Today" }
                if offset == 1 { return "Tmrw" }
                let symbols = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let weekday = cal.component(.weekday, from: d)
                return weekday >= 1 && weekday <= 7 ? symbols[weekday] : ""
            }()
            return (dateStr, dayName, "\(day)")
        }
    }

    var timeFilterAPI: (after: String?, before: String?) {
        switch selectedTimeFilter {
        case "lunch": return ("11:00", "15:00")
        case "3pm": return ("15:00", "18:00")
        case "7pm": return ("18:00", "20:00")
        case "evening79": return ("19:00", "21:00") // 7–9 PM
        case "dinner": return ("20:00", "24:00")
        default: return (nil, nil)
        }
    }

    /// Right-side label for Live Stream header — real signals only (no fake viewer counts).
    var liveStreamActivityLabel: String {
        let scanned = totalVenuesScanned
        let open = drops.count
        if scanned > 0 && open > 0 {
            return "\(scanned) venues · \(open) open"
        }
        if scanned > 0 { return "\(scanned) venues scanned" }
        if open > 0 { return "\(open) browsing" }
        return "Live"
    }

    /// Today's date string YYYY-MM-DD for "Tonight" filter chip.
    var todayDateStr: String {
        let cal = Calendar.current
        let t = Date()
        let y = cal.component(.year, from: t)
        let m = cal.component(.month, from: t)
        let d = cal.component(.day, from: t)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func applyFiltersAndRefresh() {
        Task { await refresh() }
    }

    var lastScanText: String {
        guard let d = lastScanAt else { return "—" }
        let sec = Int(-d.timeIntervalSinceNow)
        if sec < 60 { return "just now" }
        if sec < 3600 { return "\(sec / 60)m ago" }
        if sec < 86400 { return "\(sec / 3600)h ago" }
        return "\(sec / 86400)d ago"
    }

    var nextScanLabel: String {
        if secondsUntilNextScan <= 0 { return "Scanning now…" }
        if secondsUntilNextScan < 60 { return "Next scan in \(secondsUntilNextScan)s" }
        return "Next scan in \(secondsUntilNextScan / 60)m"
    }

    // MARK: - Polling

    func startPolling() {
        refreshTask?.cancel()
        liveListRotationTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s polling
            }
        }
        startCountdownTick()
        startTickerRotation()
        startLiveListRotation()
    }

    /// Quality-ranked pool for live stream: snag-qualified first, then bookable, then rest.
    /// Covers all days returned by the API.
    private var liveStreamPool: [Drop] {
        let qualified  = drops.filter { $0.snagFeedQualified == true }
        let bookable   = drops.filter { $0.snagFeedQualified != true && $0.effectiveResyBookingURL != nil }
        let rest       = drops.filter { $0.snagFeedQualified != true && $0.effectiveResyBookingURL == nil }
        // Within each tier, freshest first
        func byFreshness(_ a: Drop, _ b: Drop) -> Bool { a.secondsSinceDetected < b.secondsSinceDetected }
        return qualified.sorted(by: byFreshness) + bookable.sorted(by: byFreshness) + rest.sorted(by: byFreshness)
    }

    /// Seeds all 5 slots from the top of the pool; called on first load and refresh.
    func seedLiveStreamSlots() {
        let pool = liveStreamPool
        guard !pool.isEmpty else { return }
        liveStreamSlots = Array(pool.prefix(5))
        liveStreamSlotIndex = 0
    }

    /// Swaps one slot (round-robin 0→1→2→3→4→0) with the next best drop not already on screen.
    private func rotateOneLiveStreamSlot() {
        let pool = liveStreamPool
        guard pool.count > 1 else { return }

        if liveStreamSlots.count < min(5, pool.count) {
            seedLiveStreamSlots()
            return
        }

        let slotCount = liveStreamSlots.count
        let idx = liveStreamSlotIndex % slotCount
        liveStreamSlotIndex += 1

        let currentIds = Set(liveStreamSlots.map(\.id))
        // Pick the next-best drop not currently showing
        if let next = pool.first(where: { !currentIds.contains($0.id) }) {
            liveStreamSlots[idx] = next
        }
        liveListShuffleToken &+= 1   // keep FeedView animation trigger alive
    }

    /// Rotates the live stream: one slot swaps every ~6 s (staggered jitter so it never feels robotic).
    private func startLiveListRotation() {
        liveListRotationTask?.cancel()
        seedLiveStreamSlots()
        liveListRotationTask = Task { @MainActor in
            while !Task.isCancelled {
                let jitter = UInt64(5_500_000_000) + UInt64.random(in: 0..<1_000_000_000)
                try? await Task.sleep(nanoseconds: jitter)
                guard !drops.isEmpty else { continue }
                rotateOneLiveStreamSlot()
            }
        }
    }

    // MARK: - Ticker rotation
    // Each of the 5 slots shows a venue for ~10 s. We cycle through slots 0→1→2→3→4→0…
    // with a ~2 s gap between swaps, so they change at different times and never all at once.

    private func startTickerRotation() {
        tickerRotationTask?.cancel()
        tickerSlotIndex = 0
        tickerRotationTask = Task { @MainActor in
            while !Task.isCancelled {
                rotateOneTickerSlot()
                // Small random jitter (1.8 – 2.4 s) so the changes feel natural, not robotic
                let jitterNs = UInt64(1_800_000_000) + UInt64.random(in: 0..<600_000_000)
                try? await Task.sleep(nanoseconds: jitterNs)
            }
        }
    }

    /// Seed all slots on first load / refresh.
    private func rotateTickerDrops() {
        let pool = justDropped
        guard !pool.isEmpty else { return }
        tickerDrops = Array(pool.shuffled().prefix(min(5, pool.count)))
        tickerSlotIndex = 0
    }

    /// Swap the *next* slot in sequence (round-robin), so each slot lives ~10 s
    /// before being replaced (5 slots × ~2 s gap = ~10 s per slot).
    private func rotateOneTickerSlot() {
        let pool = justDropped
        guard pool.count > 1 else { return }

        // Seed if not yet filled
        if tickerDrops.count < min(5, pool.count) {
            tickerDrops = Array(pool.shuffled().prefix(min(5, pool.count)))
            tickerSlotIndex = 0
            return
        }

        let slotIndex = tickerSlotIndex % tickerDrops.count
        tickerSlotIndex += 1

        // Prefer a drop that isn't currently on screen
        let currentIds = Set(tickerDrops.map(\.id))
        let candidates = pool.filter { !currentIds.contains($0.id) }
        let fallback   = pool.filter { $0.id != tickerDrops[slotIndex].id }
        guard let newDrop = candidates.randomElement() ?? fallback.randomElement() else { return }
        tickerDrops[slotIndex] = newDrop
    }

    private func startCountdownTick() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            while !Task.isCancelled {
                if let next = nextScanAt {
                    secondsUntilNextScan = max(0, Int(next.timeIntervalSinceNow))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s tick
            }
        }
    }

    func refresh() async {
        if drops.isEmpty { isLoading = true } else { isRefreshing = true }
        error = nil
        defer { isLoading = false; isRefreshing = false }

        let timeAPI = timeFilterAPI
        do {
            let resp = try await service.fetchJustOpened(
                partySizes: selectedPartySizes.isEmpty ? nil : Array(selectedPartySizes)
            )

            var ranked = resp.rankedBoard ?? []
            let top = resp.topOpportunities ?? []
            let hot = resp.hotRightNow ?? []
            let scanned = resp.totalVenuesScanned ?? 0

            // Curated `ranked_board` can be empty while `just_opened`/`still_open` still have bookable rows.
            if ranked.isEmpty, let inv = resp.dayInventory, !inv.isEmpty {
                if selectedDates.isEmpty {
                    ranked = inv
                } else {
                    let allowed = Set(selectedDates.map { Drop.normalizeCalendarDayKey($0) })
                    let filtered = inv.filter { drop in
                        guard let ds = drop.dateStr, !ds.isEmpty else { return false }
                        return allowed.contains(Drop.normalizeCalendarDayKey(ds))
                    }
                    ranked = filtered.isEmpty ? inv : filtered
                }
            }

            if ranked.isEmpty {
                let newDrops = (try? await service.fetchNewDrops()) ?? []
                if !newDrops.isEmpty { ranked = newDrops }
            }

            // Detect new drops since last refresh
            if !previousDropIds.isEmpty {
                let incoming = Set(ranked.map { $0.id })
                newDropsCount = incoming.subtracting(previousDropIds).count
            } else {
                newDropsCount = 0
            }
            previousDropIds = Set(ranked.map { $0.id })

            drops = ranked
            liveListShuffleToken = 0
            rotateTickerDrops()   // seed ticker immediately on each refresh
            seedLiveStreamSlots() // re-seed live stream with freshest best drops
            topOpportunities = top.isEmpty ? nil : top
            hotRightNow = hot.isEmpty ? nil : hot
            totalVenuesScanned = scanned
            likelyToOpen = resp.likelyToOpen ?? []
            lastRefreshed = Date()

            if let iso = resp.lastScanAt { lastScanAt = Drop.parseISO(iso) }
            if let iso = resp.nextScanAt {
                nextScanAt = Drop.parseISO(iso)
                secondsUntilNextScan = max(0, Int((nextScanAt ?? Date()).timeIntervalSinceNow))
            }

        } catch is CancellationError {
        } catch {
            self.error = APIService.userFacingRequestError(error)
        }
    }

    func acknowledgeNewDrops() {
        newDropsCount = 0
    }
}
