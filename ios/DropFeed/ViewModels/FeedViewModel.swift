import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    private var refreshTask: Task<Void, Never>?
    @Published var drops: [Drop] = []
    @Published var topOpportunities: [Drop]?
    @Published var hotRightNow: [Drop]?
    @Published var likelyToOpen: [LikelyToOpenVenue] = []
    @Published var calendarCounts: CalendarCounts = CalendarCounts()
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastScanAt: Date?
    @Published var totalVenuesScanned: Int = 0
    
    @Published var selectedDates: Set<String> = []
    @Published var selectedPartySizes: Set<Int> = []
    @Published var selectedTimeFilter: String = "all"
    
    private let service = APIService.shared
    
    // MARK: - Hero card (top-ranked drop)
    
    var heroCard: Drop? {
        drops.first
    }
    
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
            let dayNum = "\(day)"
            return (dateStr, dayName, dayNum)
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
        let min = sec / 60
        if min < 60 { return "\(min)m ago" }
        let h = min / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h/24)d ago"
    }
    
    func startPolling() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
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
            
            // If main feed is empty but we have scan data (or no scan yet), fall back to new-drops so feed isn't blank
            if ranked.isEmpty {
                let newDrops = (try? await service.fetchNewDrops(withinMinutes: 60)) ?? []
                if !newDrops.isEmpty {
                    ranked = newDrops
                }
            }
            
            drops = ranked
            topOpportunities = top.isEmpty ? nil : top
            hotRightNow = hot.isEmpty ? nil : hot
            totalVenuesScanned = scanned
            likelyToOpen = resp.likelyToOpen ?? []
            
            if let iso = resp.lastScanAt {
                lastScanAt = Drop.parseISO(iso)
            } else {
                lastScanAt = nil
            }
            
            // Fetch calendar counts (non-blocking)
            Task {
                if let counts = try? await service.fetchCalendarCounts() {
                    self.calendarCounts = counts
                }
            }
        } catch is CancellationError {
            // Ignore
        } catch {
            self.error = Self.userFacingError(error)
        }
    }
    
    /// User-friendly message when backend is unreachable or request fails.
    private static func userFacingError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "Request timed out. The server may be busy — try again in a moment."
            case .cannotFindHost, .cannotConnectToHost:
                return "Can't reach the server. Check your connection or try again later."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
