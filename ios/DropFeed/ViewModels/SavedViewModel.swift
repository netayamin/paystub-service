import Foundation

@MainActor
final class SavedViewModel: ObservableObject {
    @Published var watchedVenues: Set<String> = []
    @Published var excludedVenues: Set<String> = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    /// Normalized venue name → server follow status (last drop from `drop_events`).
    @Published private(set) var followStatusByKey: [String: FollowStatusItem] = [:]
    /// In-app notification history (from `/notifications` persistence on server).
    @Published private(set) var followActivity: [FollowActivityItem] = []
    
    /// Map venue_name -> watch id for deletion
    private var watchIds: [String: Int] = [:]
    private var excludeIds: [String: Int] = [:]
    
    private let service = APIService.shared
    
    var searchSuggestions: [String] { [] }

    var showFreeTextAdd: Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.count >= 2 && !watchedVenues.contains(q)
    }

    /// All venues the user has manually saved for notifications.
    var notifyVenues: [(name: String, isSaved: Bool)] {
        watchedVenues
            .map { (name: $0, isSaved: true) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        
        async let watchesTask = service.fetchWatches()
        async let followStatusTask = service.fetchFollowStatus()
        async let activityTask = service.fetchFollowActivity(limit: 40)
        
        do {
            let resp = try await watchesTask
            let watches = resp.watches
            let excluded = resp.excluded
            
            watchIds = [:]
            for w in watches { watchIds[w.venueName] = w.id }
            excludeIds = [:]
            for e in excluded { excludeIds[e.venueName.lowercased()] = e.id }
            
            watchedVenues = Set(watches.map(\.venueName))
            excludedVenues = Set(excluded.map { $0.venueName.lowercased() })
        } catch {
            // Silently fail; user can retry
        }

        do {
            let st = try await followStatusTask
            var m: [String: FollowStatusItem] = [:]
            for f in st.follows {
                m[f.venueName.lowercased()] = f
            }
            followStatusByKey = m
        } catch {
            followStatusByKey = [:]
        }

        do {
            followActivity = try await activityTask.items
        } catch {
            followActivity = []
        }
    }

    /// One-line hint under each venue in the notify grid.
    func followSubtitle(forDisplayName name: String) -> String? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let item = followStatusByKey[key] else { return nil }
        if item.recentActivity {
            if let s = Self.relativeOpenedSummary(iso: item.lastDropAt) {
                return "Opened \(s)"
            }
            return "Opened recently"
        }
        if let s = Self.relativeOpenedSummary(iso: item.lastDropAt) {
            return "Last opened \(s)"
        }
        return "No drops seen yet"
    }

    private static func relativeOpenedSummary(iso: String?) -> String? {
        guard let raw = iso?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: raw)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: raw)
        }
        guard let date = d else { return nil }
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .abbreviated
        return r.localizedString(for: date, relativeTo: Date())
    }
    
    func toggleWatch(_ name: String) {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if watchedVenues.contains(key) {
            watchedVenues.remove(key)
            if let id = watchIds[name] ?? watchIds[key] {
                Task {
                    try? await service.removeWatch(id: id)
                    watchIds.removeValue(forKey: name)
                    watchIds.removeValue(forKey: key)
                }
            }
        } else {
            watchedVenues.insert(key)
            Task {
                if let watch = try? await service.addWatch(venueName: name) {
                    let returned = watch.venueName.trimmingCharacters(in: .whitespacesAndNewlines)
                    watchIds[name] = watch.id
                    watchIds[key] = watch.id
                    if !returned.isEmpty {
                        watchIds[returned] = watch.id
                        watchIds[returned.lowercased()] = watch.id
                    }
                }
            }
        }
    }
    
    func isWatched(_ name: String) -> Bool {
        watchedVenues.contains(name.lowercased().trimmingCharacters(in: .whitespaces))
    }
    
    func addExclude(_ name: String) {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        excludedVenues.insert(key)
        Task { try? await service.addExclude(venueName: name) }
    }
    
    func removeExclude(_ name: String) {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        excludedVenues.remove(key)
        if let id = excludeIds[key] {
            Task { try? await service.removeExclude(id: id) }
        }
    }
}
