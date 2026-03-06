import SwiftUI

struct AlertsView: View {
    @ObservedObject var alertsVM: AlertsViewModel
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var premium: PremiumManager
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                header
                // Set specific notifications: watch list
                setNotificationsSection
                // Recent alerts
                recentAlertsSection
            }
            .padding(.bottom, 120)
        }
        .background(AppTheme.background)
        .task {
            alertsVM.startPolling()
            await savedVM.loadAll()
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(premium: premium)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Alerts")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("Set notifications for restaurants and see when tables drop.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
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
        .padding(.bottom, 8)
    }

    // MARK: - Set specific notifications (watch list)

    private var setNotificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notify me when tables drop")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
                TextField("Add restaurant to watch…", text: $savedVM.searchText)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textPrimary)
                    .autocorrectionDisabled()
                    .onSubmit {
                        addCurrentSearch()
                    }
                if !savedVM.searchText.isEmpty {
                    Button {
                        savedVM.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )

            if !savedVM.searchSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(savedVM.searchSuggestions.prefix(5), id: \.self) { name in
                        Button {
                            if premium.watchlistLimitReached(currentCount: savedVM.watchedVenues.count) {
                                showPaywall = true
                            } else {
                                savedVM.toggleWatch(name)
                                savedVM.searchText = ""
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.badge")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text(name)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().background(AppTheme.border)
                    }
                }
                .background(AppTheme.surfaceElevated)
                .cornerRadius(12)
            }
            if savedVM.showFreeTextAdd && !savedVM.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    if premium.watchlistLimitReached(currentCount: savedVM.watchedVenues.count) {
                        showPaywall = true
                    } else {
                        savedVM.toggleWatch(savedVM.searchText.trimmingCharacters(in: .whitespaces))
                        savedVM.searchText = ""
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.accentOrange)
                        Text("Add \"\(savedVM.searchText.trimmingCharacters(in: .whitespaces))\"")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.accentOrange)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            if !savedVM.watchedVenues.isEmpty {
                Text("Watching \(savedVM.watchedVenues.count) restaurant\(savedVM.watchedVenues.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .textCase(.uppercase)
                AlertsChipFlowLayout(spacing: 6) {
                    ForEach(savedVM.watchedVenues.sorted(), id: \.self) { name in
                        HStack(spacing: 4) {
                            Text(name.capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                            Button {
                                savedVM.toggleWatch(name)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.surfaceElevated)
                        .cornerRadius(8)
                    }
                }
            } else {
                Text("Search above to add restaurants. We'll notify you when tables open up.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private func addCurrentSearch() {
        let q = savedVM.searchText.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        if premium.watchlistLimitReached(currentCount: savedVM.watchedVenues.count) {
            showPaywall = true
        } else {
            savedVM.toggleWatch(q)
            savedVM.searchText = ""
        }
    }

    // MARK: - Recent alerts

    private var recentAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent alerts")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            if alertsVM.notifications.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(alertsVM.notifications) { notif in
                        notificationRow(notif)
                        Divider()
                            .background(AppTheme.border)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
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

// MARK: - Chip flow layout for watched venues

private struct AlertsChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + lineHeight), frames)
    }
}

#Preview {
    AlertsView(alertsVM: AlertsViewModel(), savedVM: SavedViewModel(), premium: PremiumManager())
}
