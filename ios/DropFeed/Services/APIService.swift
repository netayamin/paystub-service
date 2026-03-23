import Foundation

/// API service for the Drop Feed backend.
/// Base URL is read from Info.plist key `API_BASE_URL` (e.g. set by `make ngrok-ios`).
///
/// On a **physical device**, `http://127.0.0.1` / `localhost` in Info.plist is ignored (that’s the phone, not your Mac); the app falls back to the deploy host unless you set a real URL (ngrok HTTPS, or `http://192.168.x.x:8000` on the same Wi‑Fi).
final class APIService {
    static let shared = APIService()

    /// API origin only (no trailing slash, no `/chat` suffix — paths add `/chat/...` themselves).
    private let baseURL: String = APIService.resolvedAPIBaseOrigin

    /// Normalized origin actually used for requests (same logic as `baseURL`).
    private static let resolvedAPIBaseOrigin: String = normalizeAPIBaseOrigin(resolveAPIBaseOriginRaw())

    private static func resolveAPIBaseOriginRaw() -> String {
        let plist = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #if targetEnvironment(simulator)
        if !plist.isEmpty { return plist }
        return "http://127.0.0.1:8000"
        #else
        if plist.isEmpty { return "http://18.118.55.231:8000" }
        if plistHostIsDeviceLoopback(plist) {
            return "http://18.118.55.231:8000"
        }
        return plist
        #endif
    }

    /// True when the URL points at this device (useless for reaching a Mac-hosted API).
    private static func plistHostIsDeviceLoopback(_ string: String) -> Bool {
        guard let u = URL(string: string), let host = u.host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" { return true }
        return host.hasPrefix("127.")
    }

    private static func normalizeAPIBaseOrigin(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/chat") {
            s = String(s.dropLast(5))
            while s.hasSuffix("/") { s.removeLast() }
        }
        return s
    }
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    /// Wraps URLSession so sign-in shows setup hints instead of a generic “could not connect”.
    private func dataForAuthRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.serverMessage(Self.connectionHint(for: urlError))
        } catch {
            throw error
        }
    }

    private static func connectionHint(for error: URLError) -> String {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost, .dnsLookupFailed:
            #if targetEnvironment(simulator)
            return """
            Can’t reach \(Self.sharedBaseURLDisplay) — nothing answered, or it’s not this API.

            • In the backend folder: `poetry run uvicorn app.main:app --host 127.0.0.1 --port 8000`
            • Check port 8000 isn’t another app (you should get 200 from POST /chat/auth/request-code, not 404).
            • Simulator uses `API_BASE_URL` from Info.plist (127.0.0.1 is correct for the Mac).
            """
            #else
            return """
            Can’t reach \(Self.sharedBaseURLDisplay).

            On a real iPhone: use ngrok or your Mac’s LAN IP (not 127.0.0.1).

            • ngrok: from repo root run make ngrok-ios, then rebuild the app (updates Info.plist).
            • Same Wi‑Fi: set API_BASE_URL to http://192.168.x.x:8000 and run uvicorn with --host 0.0.0.0 --port 8000.

            If Info.plist still has 127.0.0.1, this build ignores it and uses the deploy server instead.
            """
            #endif
        case .notConnectedToInternet:
            return "No internet connection. Check Wi‑Fi or cellular."
        default:
            return "Network error (\(error.code.rawValue)): \(error.localizedDescription)"
        }
    }

    /// For error copy only (no secrets).
    private static var sharedBaseURLDisplay: String { resolvedAPIBaseOrigin }
    
    // MARK: - Feed
    
    func fetchJustOpened(
        dates: [String]? = nil,
        partySizes: [Int]? = nil,
        timeAfter: String? = nil,
        timeBefore: String? = nil
    ) async throws -> JustOpenedResponse {
        var components = URLComponents(string: "\(baseURL)/chat/watches/just-opened")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "_t", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "mobile", value: "1"),
        ]
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
    
    func fetchFollowStatus(market: String = "nyc") async throws -> FollowStatusResponse {
        var components = URLComponents(string: "\(baseURL)/chat/watches/follows/status")!
        components.queryItems = [
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "_t", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]
        guard let url = components.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        return try decoder.decode(FollowStatusResponse.self, from: data)
    }

    func fetchFollowActivity(limit: Int = 30) async throws -> FollowActivityResponse {
        var components = URLComponents(string: "\(baseURL)/chat/watches/follows/activity")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "_t", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
        ]
        guard let url = components.url else { throw APIError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError
        }
        return try decoder.decode(FollowActivityResponse.self, from: data)
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
        return decoded.allNames
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

    // MARK: - Auth (phone / OTP / profile)

    func requestAuthCode(phoneE164: String) async throws {
        guard let url = URL(string: "\(baseURL)/chat/auth/request-code") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let phone_e164: String }
        request.httpBody = try JSONEncoder().encode(Body(phone_e164: phoneE164))
        let (data, response) = try await dataForAuthRequest(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.httpError }
        guard (200...299).contains(http.statusCode) else {
            throw Self.authFailure(status: http.statusCode, data: data, fallback: "Could not send code")
        }
    }

    func verifyAuthCode(phoneE164: String, code: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/auth/verify-code") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let phone_e164: String; let code: String }
        request.httpBody = try JSONEncoder().encode(Body(phone_e164: phoneE164, code: code))
        let (data, response) = try await dataForAuthRequest(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.httpError }
        guard (200...299).contains(http.statusCode) else {
            throw Self.authFailure(status: http.statusCode, data: data, fallback: "Invalid code")
        }
        struct Resp: Decodable { let access_token: String }
        return try decoder.decode(Resp.self, from: data).access_token
    }

    func completeAuthProfile(accessToken: String, firstName: String, lastName: String, email: String) async throws {
        guard let url = URL(string: "\(baseURL)/chat/auth/complete-profile") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        struct Body: Encodable {
            let first_name: String
            let last_name: String
            let email: String
        }
        request.httpBody = try JSONEncoder().encode(Body(first_name: firstName, last_name: lastName, email: email))
        let (data, response) = try await dataForAuthRequest(request)
        guard let http = response as? HTTPURLResponse else { throw APIError.httpError }
        guard (200...299).contains(http.statusCode) else {
            throw Self.authFailure(status: http.statusCode, data: data, fallback: "Could not save profile")
        }
    }

    /// 404 on auth paths almost always means the server image is older than the phone-login API.
    private static func authFailure(status: Int, data: Data, fallback: String) -> APIError {
        if status == 404 {
            let d = parseErrorDetail(data)?.lowercased()
            if d == nil || d == "not found" {
                return .serverMessage(
                    "This server doesn’t have phone sign-in yet (404). Redeploy the latest backend, or point API_BASE_URL at a machine running the current API (e.g. your Mac on the same Wi‑Fi: http://192.168.x.x:8000)."
                )
            }
        }
        return .serverMessage(parseErrorDetail(data) ?? fallback)
    }

    private static func parseErrorDetail(_ data: Data) -> String? {
        struct E: Decodable { let detail: String? }
        return (try? JSONDecoder().decode(E.self, from: data))?.detail
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
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError: return "Couldn't reach backend. Is it running? Same WiFi?"
        case .decodeError(let e): return "Parse error: \(e.localizedDescription)"
        case .serverMessage(let s): return s
        }
    }
}
