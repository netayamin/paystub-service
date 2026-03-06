import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var selectedDates: Set<String> = []
    @Published var selectedTimeFilter: String = "all"
    @Published var selectedPartySizes: Set<Int> = []
    @Published var results: [Drop] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasSearched = false

    private let service = APIService.shared

    static let timeOptions: [(key: String, label: String)] = [
        ("all", "All"),
        ("lunch", "Lunch"),
        ("3pm", "Afternoon"),
        ("7pm", "Early dinner"),
        ("dinner", "Late dinner"),
    ]

    static let partySizeOptions: [Int] = [2, 4, 6, 8]

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

    func loadResults() async {
        hasSearched = true
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
            if ranked.isEmpty {
                let newDrops = (try? await service.fetchNewDrops(withinMinutes: 60)) ?? []
                if !newDrops.isEmpty {
                    ranked = newDrops
                }
            }
            results = ranked
        } catch is CancellationError {
            // ignore
        } catch {
            self.error = Self.userFacingError(error)
            results = []
        }
    }

    private static func userFacingError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "Request timed out. Try again in a moment."
            case .cannotFindHost, .cannotConnectToHost:
                return "Can't reach the server. Try again later."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
