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

    /// Recently detected tables to surface as "live now".
    /// Uses `secondsSinceDetected` computed from `detectedAt` / `createdAt`.
    var justDropped: [Drop] {
        drops
            .filter { $0.secondsSinceDetected <= 600 }
            .sorted { $0.secondsSinceDetected < $1.secondsSinceDetected }
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
