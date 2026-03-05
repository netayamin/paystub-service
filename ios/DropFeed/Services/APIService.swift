import Foundation

/// API service for the Drop Feed backend.
/// Base URL is read from Info.plist key `API_BASE_URL` (e.g. set by `make ngrok-ios`).
final class APIService {
    static let shared = APIService()

    private let baseURL: String = {
        if let url = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String, !url.isEmpty {
            return url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:8000"
        #else
        return "http://127.0.0.1:8000"
        #endif
    }()
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }
    
    // MARK: - Feed
    
    func fetchJustOpened(
        dates: [String]? = nil,
        partySizes: [Int]? = nil,
        timeAfter: String? = nil,
        timeBefore: String? = nil
    ) async throws -> JustOpenedResponse {
        var components = URLComponents(string: "\(baseURL)/chat/watches/just-opened")!
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "_t", value: "\(Int(Date().timeIntervalSince1970 * 1000))")]
        if let dates = dates, !dates.isEmpty {
            queryItems.append(URLQueryItem(name: "dates", value: dates.joined(separator: ",")))
        }
        if let sizes = partySizes, !sizes.isEmpty {
            queryItems.append(URLQueryItem(name: "party_sizes", value: sizes.map { "\($0)" }.joined(separator: ",")))
        }
        if let t = timeAfter, !t.isEmpty { queryItems.append(URLQueryItem(name: "time_after", value: t)) }
        if let t = timeBefore, !t.isEmpty { queryItems.append(URLQueryItem(name: "time_before", value: t)) }
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        
        do {
            return try JustOpenedResponse.decodeLenient(from: data, decoder: decoder)
        } catch {
            throw APIError.decodeError(error)
        }
    }
    
    func fetchNewDrops(withinMinutes: Int = 15, since: String? = nil) async throws -> [Drop] {
        var components = URLComponents(string: "\(baseURL)/chat/watches/new-drops")!
        var qi: [URLQueryItem] = [
            URLQueryItem(name: "within_minutes", value: "\(withinMinutes)"),
            URLQueryItem(name: "_t", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        if let s = since { qi.append(URLQueryItem(name: "since", value: s)) }
        components.queryItems = qi
        guard let url = components.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        let decoded = try decoder.decode(NewDropsResponse.self, from: data)
        return decoded.drops.map { item in
            Drop(
                id: item.id,
                name: item.name,
                venueKey: nil,
                location: nil,
                dateStr: item.dateStr,
                slots: item.slots.map { DropSlot(dateStr: $0.dateStr, time: $0.time, resyUrl: $0.resyUrl) },
                partySizesAvailable: [],
                imageUrl: item.imageUrl,
                createdAt: item.detectedAt,
                detectedAt: item.detectedAt,
                resyUrl: item.resyUrl,
                feedHot: nil
            )
        }
    }
    
    func fetchCalendarCounts() async throws -> CalendarCounts {
        guard let url = URL(string: "\(baseURL)/chat/watches/calendar-counts") else {
            throw APIError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        return try decoder.decode(CalendarCounts.self, from: data)
    }
    
    // MARK: - Watchlist
    
    func fetchWatches() async throws -> VenueWatchesResponse {
        guard let url = URL(string: "\(baseURL)/chat/venue-watches") else {
            throw APIError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        return try decoder.decode(VenueWatchesResponse.self, from: data)
    }
    
    func addWatch(venueName: String) async throws -> VenueWatch {
        guard let url = URL(string: "\(baseURL)/chat/venue-watches") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["venue_name": venueName])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        return try decoder.decode(VenueWatch.self, from: data)
    }
    
    func removeWatch(id: Int) async throws {
        guard let url = URL(string: "\(baseURL)/chat/venue-watches/\(id)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
    }
    
    func addExclude(venueName: String) async throws {
        guard let url = URL(string: "\(baseURL)/chat/venue-watches/exclude") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["venue_name": venueName])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
    }
    
    func removeExclude(id: Int) async throws {
        guard let url = URL(string: "\(baseURL)/chat/venue-watches/exclude/\(id)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
    }
    
    func fetchHotlist() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/chat/watches/hotlist") else {
            throw APIError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        let decoded = try decoder.decode(HotlistResponse.self, from: data)
        return decoded.names
    }
    
    // MARK: - Push
    
    func registerPushToken(deviceToken: String) async {
        guard let url = URL(string: "\(baseURL)/chat/push/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["device_token": deviceToken, "platform": "ios"]
        request.httpBody = try? JSONEncoder().encode(body)
        let _ = try? await session.data(for: request)
    }
}

struct NewDropsResponse: Codable {
    let drops: [NewDropItem]
    let at: String?
}

struct NewDropItem: Codable {
    let id: String
    let name: String
    let dateStr: String?
    let time: String?
    let resyUrl: String?
    let detectedAt: String?
    let imageUrl: String?
    let slots: [NewDropSlot]
    enum CodingKeys: String, CodingKey {
        case id, name, time, slots
        case dateStr = "date_str"
        case resyUrl = "resy_url"
        case detectedAt = "detected_at"
        case imageUrl = "image_url"
    }
}

struct NewDropSlot: Codable {
    let dateStr: String?
    let time: String?
    let resyUrl: String?
    enum CodingKeys: String, CodingKey {
        case dateStr = "date_str"
        case time
        case resyUrl = "resyUrl"
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError
    case decodeError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError: return "Couldn't reach backend. Is it running? Same WiFi?"
        case .decodeError(let e): return "Parse error: \(e.localizedDescription)"
        }
    }
}
