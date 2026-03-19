import Foundation

// MARK: - Meal preset

enum MealPreset: String, CaseIterable, Identifiable {
    case lunch  = "Lunch"
    case dinner = "Dinner"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .lunch:  return "sun.min"
        case .dinner: return "fork.knife"
        }
    }

    var earliestHour: Int { self == .lunch ? 12 : 17 }
    var latestHour:   Int { self == .lunch ? 15 : 22 }

    static func hourLabel(_ h: Int) -> String {
        let h12  = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        return "\(h12):00 \(ampm)"
    }
}

// MARK: - ViewModel

@MainActor
final class SearchViewModel: ObservableObject {

    // MARK: - Filters
    @Published var selectedDates: Set<String>
    @Published var partySize: Int = 2                        // 1–8 stepper
    @Published var selectedMealPreset: MealPreset? = .dinner // nil = any time
    @Published var venueQuery: String = ""                   // quick-pick / free-text

    // MARK: - Navigation
    @Published var isSearchActive: Bool = false

    // MARK: - Results
    @Published var results: [Drop] = []
    @Published var likelyToOpen: [LikelyToOpenVenue] = []
    @Published var isLoading    = false   // true only on first load (no results yet)
    @Published var isRefreshing = false   // true on silent background polls
    @Published var error: String?
    @Published var hasSearched  = false
    @Published var lastUpdated: Date?

    private let service  = APIService.shared
    private var pollTask: Task<Void, Never>?

    // Quick-pick venue chips (subset of NYC top priority)
    static let suggestedVenues = [
        "Carbone", "Don Angie", "Lilia", "I Sodi",
        "Via Carota", "Tatiana", "Atomix", "4 Charles",
    ]

    // MARK: - Init

    init() {
        let cal   = Calendar.current
        let today = Date()
        let y = cal.component(.year,  from: today)
        let m = cal.component(.month, from: today)
        let d = cal.component(.day,   from: today)
        selectedDates = [String(format: "%04d-%02d-%02d", y, m, d)]
    }

    // MARK: - Date options (next 14 days, month-abbrev style)

    var dateOptions: [(dateStr: String, monthAbbrev: String, dayNum: String)] {
        let cal   = Calendar.current
        let today = Date()
        let abbrevs = ["JAN","FEB","MAR","APR","MAY","JUN",
                       "JUL","AUG","SEP","OCT","NOV","DEC"]
        return (0..<14).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            let y   = cal.component(.year,  from: d)
            let m   = cal.component(.month, from: d)
            let day = cal.component(.day,   from: d)
            let dateStr = String(format: "%04d-%02d-%02d", y, m, day)
            return (dateStr, abbrevs[(m - 1) % 12], "\(day)")
        }
    }

    // MARK: - Computed filter helpers

    var earliestHour: Int { selectedMealPreset?.earliestHour ?? 11 }
    var latestHour:   Int { selectedMealPreset?.latestHour   ?? 23 }

    /// Results filtered by venueQuery (client-side, instant)
    var filteredResults: [Drop] {
        guard !venueQuery.isEmpty else { return results }
        let q = venueQuery.lowercased()
        return results.filter { $0.name.lowercased().contains(q) }
    }

    private var partyAPIFilter: [Int] {
        partySize >= 4 ? [4, 6, 8] : [partySize]
    }

    // MARK: - Polling (same 20 s cadence as Feed tab)

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                await loadResults()
                try? await Task.sleep(nanoseconds: 20_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Load

    func loadResults() async {
        hasSearched  = true
        if results.isEmpty { isLoading = true } else { isRefreshing = true }
        error = nil
        defer { isLoading = false; isRefreshing = false }

        do {
            let resp = try await service.fetchJustOpened(
                dates:      selectedDates.isEmpty ? nil : Array(selectedDates),
                partySizes: partyAPIFilter,
                timeAfter:  nil,
                timeBefore: nil
            )
            var ranked = resp.rankedBoard ?? []

            // Client-side time window filter (only when a meal preset is chosen)
            if selectedMealPreset != nil {
                let eH = earliestHour, lH = latestHour
                ranked = ranked.filter { drop in
                    guard !drop.slots.isEmpty else { return true }
                    return drop.slots.contains { slot in
                        guard let t = slot.time, !t.isEmpty else { return true }
                        guard let h = t.split(separator: ":").first.flatMap({ Int($0) }) else { return true }
                        return h >= eH && h <= lH
                    }
                }
            }

            if ranked.isEmpty {
                let fallback = (try? await service.fetchNewDrops(withinMinutes: 60)) ?? []
                ranked = fallback
            }

            results     = ranked
            lastUpdated = Date()

            if let likely = resp.likelyToOpen, !likely.isEmpty {
                likelyToOpen = likely
            }
        } catch is CancellationError {
        } catch {
            self.error = Self.userFacingError(error)
            results = []
        }
    }

    // MARK: - Helpers

    private static func userFacingError(_ e: Error) -> String {
        if let u = e as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "Request timed out. Try again in a moment."
            case .cannotFindHost, .cannotConnectToHost:
                return "Can't reach the server. Try again later."
            default: break
            }
        }
        return e.localizedDescription
    }
}
