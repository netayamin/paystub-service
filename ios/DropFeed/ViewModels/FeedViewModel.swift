import Foundation

@MainActor
final class FeedViewModel: ObservableObject {
    private var refreshTask: Task<Void, Never>?
    @Published var drops: [Drop] = []
    @Published var topOpportunities: [Drop]?
    @Published var hotRightNow: [Drop]?
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastScanAt: Date?
    @Published var totalVenuesScanned: Int = 0
    
    @Published var selectedDate: String = "" {
        didSet { applyDateFilter() }
    }
    @Published var selectedTimeFilter: String = "all"
    
    /// Full feed (all dates) from backend; filtered by selectedDate for display.
    private var allRankedBoard: [Drop] = []
    private var allTopOpportunities: [Drop] = []
    private var allHotRightNow: [Drop] = []
    
    private let service = APIService.shared
    
    private func applyDateFilter() {
        guard !selectedDate.isEmpty else {
            drops = allRankedBoard
            topOpportunities = allTopOpportunities.isEmpty ? nil : allTopOpportunities
            hotRightNow = allHotRightNow.isEmpty ? nil : allHotRightNow
            return
        }
        let date = selectedDate
        func matchesDate(_ d: Drop) -> Bool {
            if (d.dateStr ?? "") == date { return true }
            return d.slots.contains { ($0.dateStr ?? "") == date }
        }
        var filtered = allRankedBoard.filter(matchesDate)
        var filteredTop = allTopOpportunities.filter(matchesDate)
        var filteredHot = allHotRightNow.filter(matchesDate)
        // If date filter would hide everything but we have data, show all (e.g. timezone/format mismatch).
        if filtered.isEmpty && !allRankedBoard.isEmpty {
            filtered = allRankedBoard
            filteredTop = allTopOpportunities
            filteredHot = allHotRightNow
        }
        drops = filtered
        topOpportunities = filteredTop.isEmpty ? nil : filteredTop
        hotRightNow = filteredHot.isEmpty ? nil : filteredHot
    }
    
    /// Next 14 days for date picker (YYYY-MM-DD)
    var dateOptions: [String] {
        let cal = Calendar.current
        let today = Date()
        return (0..<14).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            let y = cal.component(.year, from: d)
            let m = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            return String(format: "%04d-%02d-%02d", y, m, day)
        }
    }
    
    /// time_after / time_before for API (e.g. "18:00", "20:00"). Nil = no filter.
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
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
            }
        }
    }
    
    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let today = formatToday()
            if selectedDate.isEmpty { selectedDate = today }
            // Fetch without date filter so we get all drops (match web). Filter by selectedDate for display.
            let resp = try await service.fetchJustOpened(
                dates: nil,
                partySizes: [2, 4],
                timeAfter: nil,
                timeBefore: nil
            )
            
            allRankedBoard = resp.rankedBoard ?? []
            allTopOpportunities = resp.topOpportunities ?? []
            allHotRightNow = resp.hotRightNow ?? []
            totalVenuesScanned = resp.totalVenuesScanned ?? 0
            drops = allRankedBoard
            topOpportunities = allTopOpportunities.isEmpty ? nil : allTopOpportunities
            hotRightNow = allHotRightNow.isEmpty ? nil : allHotRightNow
            
            if let iso = resp.lastScanAt {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                lastScanAt = fmt.date(from: iso)
                    ?? ISO8601DateFormatter().date(from: iso)
            } else {
                lastScanAt = nil
            }
        } catch is CancellationError {
            // Pull-to-refresh or navigation cancelled the task; don't show "cancelled" to the user
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func formatToday() -> String {
        let cal = Calendar.current
        let d = Date()
        let y = cal.component(.year, from: d)
        let m = cal.component(.month, from: d)
        let day = cal.component(.day, from: d)
        return String(format: "%04d-%02d-%02d", y, m, day)
    }
}
