import Foundation

struct DropNotification: Identifiable {
    let id: String
    let drop: Drop
    let isHotspot: Bool
    var read: Bool
    let receivedAt: Date
    
    var timeLabel: String {
        let sec = Int(-receivedAt.timeIntervalSinceNow)
        if sec < 60 { return "Just now" }
        let min = sec / 60
        if min < 60 { return "\(min)m ago" }
        let h = min / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }
}

@MainActor
final class AlertsViewModel: ObservableObject {
    @Published var notifications: [DropNotification] = []
    @Published var isLoading = false
    
    private var pollingTask: Task<Void, Never>?
    private var seenDropIds: Set<String> = []
    private var lastNewDropsAt: String?
    
    private let service = APIService.shared
    
    var unreadCount: Int {
        notifications.filter { !$0.read }.count
    }
    
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            await fetchNewDrops()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await fetchNewDrops()
            }
        }
    }
    
    func stopPolling() {
        pollingTask?.cancel()
    }
    
    private func fetchNewDrops() async {
        do {
            let drops = try await service.fetchNewDrops(withinMinutes: 30, since: lastNewDropsAt)
            lastNewDropsAt = ISO8601DateFormatter().string(from: Date())
            
            var added = false
            for drop in drops {
                guard !seenDropIds.contains(drop.id) else { continue }
                seenDropIds.insert(drop.id)
                let notif = DropNotification(
                    id: drop.id,
                    drop: drop,
                    isHotspot: drop.isHotspot == true || drop.feedHot == true,
                    read: false,
                    receivedAt: Date()
                )
                notifications.insert(notif, at: 0)
                added = true
            }
            
            if added {
                notifications = Array(notifications.prefix(100))
            }
        } catch {
            // Silently retry on next poll
        }
    }
    
    func markRead(_ id: String) {
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].read = true
        }
    }
    
    func markAllRead() {
        for i in notifications.indices {
            notifications[i].read = true
        }
    }
    
    func dismiss(_ id: String) {
        notifications.removeAll { $0.id == id }
    }
}
