import SwiftUI

/// Tab for "latest things that opened" — list from new-drops API across all buckets.
struct NewDropsView: View {
    @Binding var badgeCount: Int
    @State private var drops: [Drop] = []
    @State private var isLoading = false
    @State private var error: String?
    /// IDs we've already shown a local notification for (testing without APNs).
    @State private var notifiedDropIds: Set<String> = []
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && drops.isEmpty {
                    ProgressView()
                        .tint(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.textTertiary)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("Retry") { Task { await load() } }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if drops.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 44))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("No new openings yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("Tables that just opened will show here.")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let columns = [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ]
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(drops) { drop in
                                DropCardView(drop: drop)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(AppTheme.background)
            .navigationTitle("New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable {
                _ = await Task.detached(priority: .userInitiated) { @MainActor in await load() }.value
            }
            .task { await load() }
        }
    }
    
    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let newDrops = try await APIService.shared.fetchNewDrops(withinMinutes: 30)
            // Local notification for any drop we haven't notified for yet (no APNs needed for testing).
            for drop in newDrops where !notifiedDropIds.contains(drop.id) {
                LocalNotificationHelper.notifyNewDrop(
                    venueName: drop.name,
                    dateStr: drop.dateStr,
                    timeStr: drop.slots.first?.time
                )
                notifiedDropIds.insert(drop.id)
            }
            drops = newDrops
            badgeCount = drops.count
        } catch is CancellationError {
            // Pull-to-refresh cancelled; don't show "cancelled" to the user
        } catch let e as APIError {
            error = e.localizedDescription
            badgeCount = 0
        } catch let err {
            error = err.localizedDescription
            badgeCount = 0
        }
    }
}

#Preview("New drops") {
    NewDropsView(badgeCount: .constant(0))
}
