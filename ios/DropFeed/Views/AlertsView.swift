import SwiftUI

struct AlertsView: View {
    @ObservedObject var alertsVM: AlertsViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alerts")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    if alertsVM.unreadCount > 0 {
                        Text("\(alertsVM.unreadCount) unread")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.accentRed)
                    }
                }
                Spacer()
                if !alertsVM.notifications.isEmpty {
                    Button {
                        alertsVM.markAllRead()
                    } label: {
                        Text("Mark all read")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            if alertsVM.notifications.isEmpty {
                emptyState
            } else {
                notificationsList
            }
        }
        .background(AppTheme.background)
        .task { alertsVM.startPolling() }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell")
                .font(.system(size: 44))
                .foregroundColor(AppTheme.textTertiary)
            Text("No alerts yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            Text("New drops will appear here as they're detected. Enable notifications to stay ahead.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(alertsVM.notifications) { notif in
                    notificationRow(notif)
                    Divider()
                        .background(AppTheme.border)
                }
            }
            Spacer(minLength: 120)
        }
    }
    
    private func notificationRow(_ notif: DropNotification) -> some View {
        let drop = notif.drop
        let timeStr: String = {
            if let slot = drop.slots.first, let t = slot.time {
                return formatTime(t)
            }
            return ""
        }()
        let dateStr: String = {
            if let ds = drop.dateStr ?? drop.slots.first?.dateStr {
                return formatDate(ds)
            }
            return ""
        }()
        let resyUrl: URL? = {
            if let urlStr = drop.slots.first?.resyUrl ?? drop.resyUrl, let url = URL(string: urlStr) {
                return url
            }
            return nil
        }()
        
        return HStack(alignment: .top, spacing: 12) {
            // Unread dot
            Circle()
                .fill(notif.read ? Color.clear : AppTheme.accentRed)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(notif.isHotspot ? "HOT SPOT" : "NEW DROP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(notif.isHotspot ? AppTheme.scarcityRare : AppTheme.accentRed)
                        .tracking(0.5)
                    
                    Spacer()
                    
                    Text(notif.timeLabel)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Text(drop.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                if !dateStr.isEmpty || !timeStr.isEmpty {
                    Text([dateStr, timeStr].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                if let label = drop.scarcityLabel {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppTheme.scarcityColor(for: drop.scarcityTier))
                            .frame(width: 5, height: 5)
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.scarcityColor(for: drop.scarcityTier))
                    }
                    .padding(.top, 2)
                }
            }
            
            VStack(spacing: 6) {
                if let url = resyUrl {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Text("Reserve")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentRed)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    alertsVM.dismiss(notif.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(notif.read ? Color.clear : AppTheme.accentRed.opacity(0.05))
        .contentShape(Rectangle())
        .onTapGesture {
            alertsVM.markRead(notif.id)
        }
    }
    
    private func formatTime(_ time: String) -> String {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return time }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "am" : "pm"
        return m > 0 ? "\(hour12):\(String(format: "%02d", m))\(ampm)" : "\(hour12)\(ampm)"
    }
    
    private func formatDate(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "EEE, MMM d"
        return display.string(from: d)
    }
}

#Preview {
    AlertsView(alertsVM: AlertsViewModel())
}
