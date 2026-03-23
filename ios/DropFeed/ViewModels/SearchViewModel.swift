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

// MARK: - Explore tab presets

enum ExplorePartySegment: Int, CaseIterable, Identifiable {
    case two = 2
    case four = 4
    case anyParty = 0
    var id: Int { rawValue }
    var shortLabel: String {
        switch self {
        case .two: return "2"
        case .four: return "4"
        case .anyParty: return "Any"
        }
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

    /// When true, `loadResults` skips meal-preset time filtering and uses Explore party / date rules.
    @Published var exploreTabActive: Bool = false
    @Published var explorePartySegment: ExplorePartySegment = .anyParty

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
    /// Bumps on each `loadResults()` start so stale in-flight responses (e.g. poll vs date swipe) cannot overwrite newer data.
    private var loadResultsGeneration: Int = 0

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

    /// Results filtered by venueQuery then ranked by backend `snag_score` only (nil last).
    var rankedResults: [Drop] {
        let base: [Drop]
        if venueQuery.isEmpty {
            base = results
        } else {
            let q = venueQuery.lowercased()
            base = results.filter { $0.name.lowercased().contains(q) }
        }
        return base.sorted { lhs, rhs in
            switch (lhs.snagScore, rhs.snagScore) {
            case let (a?, b?): return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return false
            }
        }
    }

    private var partyAPIFilter: [Int] {
        partySize >= 4 ? [4, 6, 8] : [partySize]
    }

    /// Party sizes sent to `/just-opened`; `nil` means omit param (any party).
    /// Explore omits party on the wire so `/just-opened` returns the full day inventory; party segment is display-only.
    private var effectivePartySizesForAPI: [Int]? {
        if exploreTabActive { return nil }
        return partyAPIFilter
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
        loadResultsGeneration &+= 1
        let generation = loadResultsGeneration

        hasSearched  = true
        if results.isEmpty { isLoading = true } else { isRefreshing = true }
        error = nil
        defer {
            if generation == loadResultsGeneration {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let dateQuery = selectedDates.isEmpty ? nil : Array(selectedDates)
            let resp = try await service.fetchJustOpened(
                dates:      dateQuery,
                partySizes: effectivePartySizesForAPI,
                timeAfter:  nil,
                timeBefore: nil
            )
            var ranked = resp.rankedBoard ?? []
            // Explore: prefer date-bucket inventory (just_opened + still_open).
            // Only replace ranked_board when the filtered inventory is non-empty — otherwise we'd wipe
            // ranked_board on date-string mismatches and show an empty grid.
            if exploreTabActive {
                if let inv = resp.dayInventory, !inv.isEmpty {
                    let allowedNorm = Set(selectedDates.map { Self.normalizeISODateString($0) })
                    let filtered = inv.filter { drop in
                        guard let ds = drop.dateStr, !ds.isEmpty else { return false }
                        let dn = Self.normalizeISODateString(ds)
                        return selectedDates.isEmpty || allowedNorm.contains(dn)
                    }
                    if !filtered.isEmpty {
                        ranked = filtered
                    }
                }
            }

            // Client-side time window filter (Search sheet only; Explore uses accordion buckets)
            if !exploreTabActive, selectedMealPreset != nil {
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

            // Do not replace date/party-scoped results with `/new-drops` (no date filter) — that breaks Explore.
            let scopedToServerFilters = exploreTabActive || dateQuery != nil || effectivePartySizesForAPI != nil
            if ranked.isEmpty && !scopedToServerFilters {
                let fallback = (try? await service.fetchNewDrops(withinMinutes: 60)) ?? []
                ranked = fallback
            }

            guard generation == loadResultsGeneration else { return }

            results     = ranked
            lastUpdated = Date()

            // Only show venues with real metrics from the server — never show fake data
            if let likely = resp.likelyToOpen {
                likelyToOpen = likely.filter { !$0.name.isEmpty }
            }
        } catch is CancellationError {
        } catch {
            guard generation == loadResultsGeneration else { return }
            self.error = Self.userFacingError(error)
            results = []
        }
    }

    // MARK: - Helpers

    /// Calendar day key `YYYY-MM-DD` from API values that may include time (`2026-03-23T00:00:00Z`).
    private static func normalizeISODateString(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 10 else { return t }
        let head = String(t.prefix(10))
        let parts = head.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else {
            return t
        }
        return head
    }

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
