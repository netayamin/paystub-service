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
    
    /// Fetch just-opened feed with optional filters
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
            return try decoder.decode(JustOpenedResponse.self, from: data)
        } catch {
            throw APIError.decodeError(error)
        }
    }
    
    /// Latest things that opened across all buckets (for New / Notifications tab)
    func fetchNewDrops(withinMinutes: Int = 15) async throws -> [Drop] {
        var components = URLComponents(string: "\(baseURL)/chat/watches/new-drops")!
        components.queryItems = [
            URLQueryItem(name: "within_minutes", value: "\(withinMinutes)"),
            URLQueryItem(name: "_t", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
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
                feedHot: nil,
                resyPopularityScore: nil,
                ratingAverage: nil,
                ratingCount: nil
            )
        }
    }

    /// Register device for push notifications (new drops). Call after receiving token from APNs.
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
