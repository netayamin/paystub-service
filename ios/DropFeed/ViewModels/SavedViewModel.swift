import Foundation

@MainActor
final class SavedViewModel: ObservableObject {
    @Published var watchedVenues: Set<String> = []
    @Published var excludedVenues: Set<String> = []
    @Published var hotlist: [String] = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    
    /// Map venue_name -> watch id for deletion
    private var watchIds: [String: Int] = [:]
    private var excludeIds: [String: Int] = [:]
    
    private let service = APIService.shared
    
    var searchSuggestions: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }
        return hotlist
            .filter { $0.lowercased().contains(q) && !watchedVenues.contains($0.lowercased()) }
            .prefix(6)
            .map { $0 }
    }
    
    var showFreeTextAdd: Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.count >= 2
            && !watchedVenues.contains(q)
            && !searchSuggestions.contains(where: { $0.lowercased() == q })
    }
    
    /// All venues that get notifications: hotlist (minus excluded) + manually saved
    var notifyVenues: [(name: String, isSaved: Bool)] {
        let hotActive = hotlist.filter { !excludedVenues.contains($0.trimmingCharacters(in: .whitespaces).lowercased()) }
            .map { (name: $0.trimmingCharacters(in: .whitespaces), isSaved: false) }
        let savedOnly = watchedVenues
            .filter { n in !hotlist.contains(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == n }) }
            .map { (name: $0, isSaved: true) }
        return (hotActive + savedOnly).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func loadAll(market: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        
        async let watchesTask = service.fetchWatches()
        async let hotlistTask = service.fetchHotlist(market: market)
        
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
            hotlist = try await hotlistTask
        } catch {
            // Keep existing
        }
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
                    watchIds[name] = watch.id
                    watchIds[key] = watch.id
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
