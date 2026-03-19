import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    private var refreshTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var tickerRotationTask: Task<Void, Never>?
    private var tickerSlotIndex: Int = 0   // which slot gets swapped next

    @Published var drops: [Drop] = []
    @Published var topOpportunities: [Drop]?
    @Published var hotRightNow: [Drop]?
    @Published var likelyToOpen: [LikelyToOpenVenue] = []
    @Published var calendarCounts: CalendarCounts = CalendarCounts()
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

    /// Pool for the Real-Time Ticker: all currently-available drops sorted by quality
    /// (hotspot → rarity → popularity → rating), with freshness as a tiebreaker.
    /// Hotspot restaurants always float to the top regardless of when they were detected.
    var justDropped: [Drop] {
        drops.sorted { a, b in
            let sa = tickerQualityScore(a)
            let sb = tickerQualityScore(b)
            if abs(sa - sb) > 0.001 { return sa > sb }
            return a.secondsSinceDetected < b.secondsSinceDetected
        }
    }

    /// Composite quality score used to rank drops in the ticker pool.
    /// Mirrors the backend _top_opportunity_score logic so that the same
    /// prestigious/hard-to-get restaurants surface in both sections.
    private func tickerQualityScore(_ d: Drop) -> Double {
        let hot     = d.feedHot == true        ? 3.0  : 0.0
        let rarity  = (d.rarityScore           ?? 0) * 2.0
        let pop     = (d.resyPopularityScore   ?? 0) * 1.5
        let count   = Double(d.ratingCount     ?? 0)
        let rating  = (d.ratingAverage         ?? 0) / 5.0 * min(1.0, count / 200.0)
        return hot + rarity + pop + rating
    }

    var feedCards: [Drop] {
        guard drops.count > 1 else { return [] }
        return Array(drops.dropFirst())
    }

    var rareDrops: [Drop] {
        drops.filter { $0.scarcityTier == .rare || ($0.rarityScore ?? 0) > 0.65 }
    }

    var trendingDrops: [Drop] {
        drops.filter { ($0.trendPct ?? 0) > 20 }.sorted { ($0.trendPct ?? 0) > ($1.trendPct ?? 0) }
    }

    /// Venues from likelyToOpen that have a drop likelihood for today specifically
    var likelyTodayVenues: [LikelyToOpenVenue] {
        likelyToOpen.filter { ($0.rarityScore ?? 0) > 0.5 }.prefix(5).map { $0 }
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
        case "dinner": return ("20:00", "24:00")
        default: return (nil, nil)
        }
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
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s polling
            }
        }
        startCountdownTick()
        startTickerRotation()
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
                dates: selectedDates.isEmpty ? nil : Array(selectedDates),
                partySizes: selectedPartySizes.isEmpty ? nil : Array(selectedPartySizes),
                timeAfter: timeAPI.after,
                timeBefore: timeAPI.before
            )

            var ranked = resp.rankedBoard ?? []
            let top = resp.topOpportunities ?? []
            let hot = resp.hotRightNow ?? []
            let scanned = resp.totalVenuesScanned ?? 0

            if ranked.isEmpty {
                let newDrops = (try? await service.fetchNewDrops(withinMinutes: 60)) ?? []
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
            rotateTickerDrops()   // seed ticker immediately on each refresh
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

            Task {
                if let counts = try? await service.fetchCalendarCounts() {
                    self.calendarCounts = counts
                }
            }
        } catch is CancellationError {
        } catch {
            self.error = Self.userFacingError(error)
        }
    }

    func acknowledgeNewDrops() {
        newDropsCount = 0
    }

    private static func userFacingError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "Request timed out. The server may be busy — try again in a moment."
            case .cannotFindHost, .cannotConnectToHost:
                return "Can't reach the server. Check your connection or try again later."
            default: break
            }
        }
        return error.localizedDescription
    }
}
