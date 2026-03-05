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
    
    @Published var selectedDates: Set<String> = [] {
        didSet { applyFilters() }
    }
    @Published var selectedPartySizes: Set<Int> = [] {
        didSet { applyFilters() }
    }
    @Published var selectedTimeFilter: String = "all"
    
    private var allRankedBoard: [Drop] = []
    private var allTopOpportunities: [Drop] = []
    private var allHotRightNow: [Drop] = []
    
    private let service = APIService.shared
    
    // MARK: - Hero card (top-ranked drop)
    
    var heroCard: Drop? {
        drops.first
    }
    
    var feedCards: [Drop] {
        guard drops.count > 1 else { return [] }
        return Array(drops.dropFirst())
    }
    
    // MARK: - Filtering
    
    private func applyFilters() {
        let dateSet = selectedDates
        let partySet = selectedPartySizes
        
        func matchesDrop(_ d: Drop) -> Bool {
            if !dateSet.isEmpty {
                let cardDate = d.dateStr ?? ""
                let slotDates = Set(d.slots.compactMap(\.dateStr))
                if !dateSet.contains(cardDate) && dateSet.isDisjoint(with: slotDates) {
                    return false
                }
            }
            if !partySet.isEmpty {
                let available = Set(d.partySizesAvailable)
                if !available.isEmpty && partySet.isDisjoint(with: available) {
                    return false
                }
            }
            return true
        }
        
        var filtered = allRankedBoard.filter(matchesDrop)
        var filteredTop = allTopOpportunities.filter(matchesDrop)
        var filteredHot = allHotRightNow.filter(matchesDrop)
        
        if filtered.isEmpty && !allRankedBoard.isEmpty && !dateSet.isEmpty {
            filtered = allRankedBoard
            filteredTop = allTopOpportunities
            filteredHot = allHotRightNow
        }
        
        drops = filtered
        topOpportunities = filteredTop.isEmpty ? nil : filteredTop
        hotRightNow = filteredHot.isEmpty ? nil : filteredHot
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
        
        do {
            let resp = try await service.fetchJustOpened(
                dates: nil,
                partySizes: nil,
                timeAfter: nil,
                timeBefore: nil
            )
            
            var ranked = resp.rankedBoard ?? []
            let top = resp.topOpportunities ?? []
            let hot = resp.hotRightNow ?? []
            let scanned = resp.totalVenuesScanned ?? 0
            
            if ranked.isEmpty && scanned == 0 {
                let newDrops = (try? await service.fetchNewDrops(withinMinutes: 60)) ?? []
                if !newDrops.isEmpty {
                    ranked = newDrops
                }
            }
            
            allRankedBoard = ranked
            allTopOpportunities = top
            allHotRightNow = hot
            totalVenuesScanned = scanned
            likelyToOpen = resp.likelyToOpen ?? []
            
            applyFilters()
            
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
            self.error = error.localizedDescription
        }
    }
}
