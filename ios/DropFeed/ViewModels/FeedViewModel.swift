import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    private var refreshTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    @Published var drops: [Drop] = []
    @Published var topOpportunities: [Drop]?
    @Published var hotRightNow: [Drop]?
    @Published var likelyToOpen: [LikelyToOpenVenue] = []
    @Published var calendarCounts: CalendarCounts = CalendarCounts()
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastScanAt: Date?
    @Published var nextScanAt: Date?
    @Published var totalVenuesScanned: Int = 0
    @Published var newDropsCount: Int = 0
    @Published var secondsUntilNextScan: Int = 0
    /// Tables dropped in the last 60 minutes (for "X TABLES DROPPED IN THE LAST HOUR")
    @Published var tablesDroppedLastHour: Int = 0

    @Published var selectedDates: Set<String> = []
    @Published var selectedPartySizes: Set<Int> = []
    @Published var selectedTimeFilter: String = "all"

    private let service = APIService.shared
    private var previousDropIds: Set<String> = []

    // MARK: - Derived

    /// Top 4 for the hero carousel — uses topOpportunities if available, else top-ranked drops
    var carouselDrops: [Drop] {
        let top = topOpportunities ?? []
        if top.count >= 2 { return Array(top.prefix(4)) }
        // Fallback: sort drops by rarityScore desc
        return Array(
            drops
                .sorted { ($0.rarityScore ?? 0) > ($1.rarityScore ?? 0) }
                .prefix(4)
        )
    }

    /// Most recently detected drops (within last 24h), sorted newest first
    var justDropped: [Drop] {
        drops
            .filter { $0.secondsSinceDetected < 86_400 }
            .sorted { $0.secondsSinceDetected < $1.secondsSinceDetected }
    }

    /// Drops ranked by rarity score. Fallback: top 10 by rarity so section always has content.
    var rareDrops: [Drop] {
        let withRarity = drops.filter { ($0.rarityScore ?? 0) > 0.3 || $0.scarcityTier == .rare }
        if !withRarity.isEmpty {
            return Array(withRarity.sorted { ($0.rarityScore ?? 0) > ($1.rarityScore ?? 0) }.prefix(10))
        }
        return Array(drops.sorted { ($0.rarityScore ?? 0) > ($1.rarityScore ?? 0) }.prefix(10))
    }

    /// Drops whose trendPct is high (availability spiking). Fallback: top 10 by trend or all drops.
    var trendingDrops: [Drop] {
        let withTrend = drops.filter { ($0.trendPct ?? 0) > 10 }
        if !withTrend.isEmpty {
            return Array(withTrend.sorted { ($0.trendPct ?? 0) > ($1.trendPct ?? 0) }.prefix(10))
        }
        return Array(drops.sorted { ($0.trendPct ?? 0) > ($1.trendPct ?? 0) }.prefix(10))
    }

    /// "Hottest" blend of fresh + trending + rarity. Uses backend hot_right_now when available.
    var hottestDrops: [Drop] {
        let source = (hotRightNow?.isEmpty == false) ? (hotRightNow ?? []) : drops
        return source.sorted { lhs, rhs in
            _heatScore(lhs) > _heatScore(rhs)
        }
    }

    /// Drops with known short slot windows — "Gone in minutes"
    var fleetingDrops: [Drop] {
        drops
            .filter { $0.avgDropDurationSeconds != nil }
            .sorted { ($0.avgDropDurationSeconds ?? 99_999) < ($1.avgDropDurationSeconds ?? 99_999) }
    }

    /// Legendary NYC hotspots in the feed
    var hotspotDrops: [Drop] {
        drops
            .filter { $0.isHotspot == true }
            .sorted { ($0.rarityScore ?? 0) > ($1.rarityScore ?? 0) }
    }

    /// Venues from likelyToOpen that have a drop likelihood for today specifically
    var likelyTodayVenues: [LikelyToOpenVenue] {
        likelyToOpen.filter { ($0.rarityScore ?? 0) > 0.5 }.prefix(5).map { $0 }
    }

    /// Best candidates for "what could drop soon" section
    var predictedVenues: [LikelyToOpenVenue] {
        likelyToOpen.sorted { lhs, rhs in
            let l = (lhs.rarityScore ?? 0) * 0.65 + (1 - min(max(lhs.availabilityRate14d ?? 1, 0), 1)) * 0.35
            let r = (rhs.rarityScore ?? 0) * 0.65 + (1 - min(max(rhs.availabilityRate14d ?? 1, 0), 1)) * 0.35
            return l > r
        }
    }

    // Legacy aliases kept for views that still reference them
    var heroCard: Drop? { drops.first }
    var feedCards: [Drop] {
        guard drops.count > 1 else { return [] }
        return Array(drops.dropFirst())
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
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s polling
            }
        }
        startCountdownTick()
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
        isLoading = true
        error = nil
        defer { isLoading = false }

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
            topOpportunities = top.isEmpty ? nil : top
            hotRightNow = hot.isEmpty ? nil : hot
            totalVenuesScanned = scanned
            likelyToOpen = resp.likelyToOpen ?? []
            tablesDroppedLastHour = resp.tablesDroppedLastHour ?? 0

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

    private func _heatScore(_ drop: Drop) -> Double {
        let trend = max(0, (drop.trendPct ?? 0) / 100)
        let rarity = min(max(drop.rarityScore ?? 0, 0), 1)
        let fresh: Double = {
            let sec = drop.secondsSinceDetected
            if sec < 300 { return 1.0 }
            if sec < 1800 { return 0.7 }
            if sec < 7200 { return 0.45 }
            if sec < 86400 { return 0.2 }
            return 0.05
        }()
        return (trend * 0.45) + (rarity * 0.35) + (fresh * 0.20)
    }
}
