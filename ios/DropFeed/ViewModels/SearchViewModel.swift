import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    // Filters
    @Published var selectedDates: Set<String>
    @Published var selectedPartySize: Int? = nil    // nil = any; 4 means "4+"
    @Published var earliestHour: Int = 17           // 5 PM default
    @Published var latestHour: Int  = 22            // 10 PM default

    // Results
    @Published var results: [Drop] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasSearched = false

    private let service = APIService.shared

    init() {
        let cal = Calendar.current
        let today = Date()
        let y = cal.component(.year,  from: today)
        let m = cal.component(.month, from: today)
        let d = cal.component(.day,   from: today)
        selectedDates = [String(format: "%04d-%02d-%02d", y, m, d)]
    }

    // MARK: - Time options

    static let timeHours: [(hour: Int, label: String)] = [
        (11, "11:00 AM"), (12, "12:00 PM"), (13, "1:00 PM"),
        (14, "2:00 PM"),  (15, "3:00 PM"),  (16, "4:00 PM"),
        (17, "5:00 PM"),  (18, "6:00 PM"),  (19, "7:00 PM"),
        (20, "8:00 PM"),  (21, "9:00 PM"),  (22, "10:00 PM"),
        (23, "11:00 PM"),
    ]

    static func hourLabel(_ h: Int) -> String {
        let h12  = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        return "\(h12):00 \(ampm)"
    }

    var earliestLabel: String { Self.hourLabel(earliestHour) }
    var latestLabel:   String { Self.hourLabel(latestHour)   }

    var timeframeName: String {
        let e = earliestHour, l = latestHour
        if e <= 13 && l <= 15 { return "Lunch" }
        if e >= 15 && l <= 18 { return "Afternoon" }
        if e >= 17 && l <= 22 { return "Dinner" }
        if e >= 20             { return "Late Night" }
        return "\(earliestLabel) – \(latestLabel)"
    }

    // MARK: - Date options (next 14 days)

    var dateOptions: [(dateStr: String, dayName: String, dayNum: String)] {
        let cal = Calendar.current
        let today = Date()
        return (0..<14).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            let y   = cal.component(.year,  from: d)
            let m   = cal.component(.month, from: d)
            let day = cal.component(.day,   from: d)
            let dateStr = String(format: "%04d-%02d-%02d", y, m, day)
            let name: String = {
                if offset == 0 { return "Today" }
                if offset == 1 { return "Tmrw" }
                let syms = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let wd = cal.component(.weekday, from: d)
                return (wd >= 1 && wd <= 7) ? syms[wd] : ""
            }()
            return (dateStr, name, "\(day)")
        }
    }

    // MARK: - Helpers

    private var partyAPIFilter: [Int]? {
        guard let s = selectedPartySize else { return nil }
        return s >= 4 ? [4, 6, 8] : [s]
    }

    // MARK: - Load

    func loadResults() async {
        hasSearched = true
        isLoading   = true
        error       = nil
        defer { isLoading = false }

        do {
            let resp = try await service.fetchJustOpened(
                dates:      selectedDates.isEmpty ? nil : Array(selectedDates),
                partySizes: partyAPIFilter,
                timeAfter:  nil,
                timeBefore: nil
            )
            var ranked = resp.rankedBoard ?? []

            // Client-side time window filter
            let eH = earliestHour, lH = latestHour
            ranked = ranked.filter { drop in
                guard !drop.slots.isEmpty else { return true }
                return drop.slots.contains { slot in
                    guard let t = slot.time, !t.isEmpty else { return true }
                    guard let h = t.split(separator: ":").first.flatMap({ Int($0) }) else { return true }
                    return h >= eH && h <= lH
                }
            }

            if ranked.isEmpty {
                let fallback = (try? await service.fetchNewDrops(withinMinutes: 60)) ?? []
                ranked = fallback
            }
            results = ranked
        } catch is CancellationError {
        } catch {
            self.error = Self.userFacingError(error)
            results = []
        }
    }

    // MARK: - Backward-compat stubs (referenced by FeedView via feedVM, not this VM)
    var selectedTimeFilter: String { "all" }
    var selectedPartySizes: Set<Int> { [] }

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
