import SwiftUI

struct HeroCardView: View {
    let drop: Drop
    let isWatched: Bool
    var onToggleWatch: ((String) -> Void)?
    
    private var scarcity: (label: String, color: Color, bg: Color)? {
        guard let label = drop.scarcityLabel else { return nil }
        return (
            label,
            AppTheme.scarcityColor(for: drop.scarcityTier),
            AppTheme.scarcityBackground(for: drop.scarcityTier)
        )
    }
    
    private var slots: [DropSlot] { Array(drop.slots.prefix(5)) }
    
    private var dateLabel: String {
        guard let ds = drop.dateStr ?? drop.slots.first?.dateStr else { return "" }
        let cal = Calendar.current
        let today = Date()
        let todayStr = String(format: "%04d-%02d-%02d",
                              cal.component(.year, from: today),
                              cal.component(.month, from: today),
                              cal.component(.day, from: today))
        if ds == todayStr { return "Today" }
        if let tom = cal.date(byAdding: .day, value: 1, to: today) {
            let tomStr = String(format: "%04d-%02d-%02d",
                                cal.component(.year, from: tom),
                                cal.component(.month, from: tom),
                                cal.component(.day, from: tom))
            if ds == tomStr { return "Tomorrow" }
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        if let d = fmt.date(from: ds) {
            let display = DateFormatter()
            display.dateFormat = "EEEE, MMM d"
            return display.string(from: d)
        }
        return ds
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Image
            GeometryReader { geo in
                if let urlStr = drop.imageUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        default:
                            gradientFallback
                        }
                    }
                } else {
                    gradientFallback
                }
            }
            .frame(height: 280)
            
            // Gradient overlay
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.4),
                    .init(color: .black.opacity(0.85), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)
            
            // Top badges
            VStack {
                HStack(alignment: .top) {
                    if let freshness = drop.freshnessLabel {
                        Text(freshness)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial)
                            .environment(\.colorScheme, .dark)
                            .cornerRadius(8)
                    }
                    Spacer()
                    Button {
                        onToggleWatch?(drop.name)
                    } label: {
                        Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(isWatched ? AppTheme.accentRed.opacity(0.8) : Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                
                Spacer()
            }
            .frame(height: 280)
            
            // Bottom content
            VStack(alignment: .leading, spacing: 8) {
                if let sc = scarcity {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text(sc.label)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(sc.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(sc.bg.opacity(0.9))
                    .cornerRadius(8)
                }
                
                Text(drop.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("\(drop.location ?? "NYC")\(dateLabel.isEmpty ? "" : " · \(dateLabel)")")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                
                // Time slot pills
                if !slots.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                                slotPill(slot)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                // Reserve CTA
                if let firstUrl = slots.first?.resyUrl, let url = URL(string: firstUrl) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Reserve on Resy")
                                .font(.system(size: 15, weight: .bold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(AppTheme.accentRed)
                        .cornerRadius(14)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
    
    private func slotPill(_ slot: DropSlot) -> some View {
        Group {
            if let urlStr = slot.resyUrl, let url = URL(string: urlStr) {
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    slotLabel(slot)
                        .background(Color.white)
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
            } else {
                slotLabel(slot)
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
            }
        }
    }
    
    private func slotLabel(_ slot: DropSlot) -> some View {
        HStack(spacing: 4) {
            Text(formatTime(slot.time ?? ""))
                .font(.system(size: 13, weight: .semibold))
            if slot.resyUrl != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cornerRadius(12)
    }
    
    private var gradientFallback: some View {
        LinearGradient(
            colors: [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.08, green: 0.08, blue: 0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func formatTime(_ time: String) -> String {
        let t = time.split(separator: "–").first.map(String.init) ?? time
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return String(t.prefix(8)) }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "am" : "pm"
        return m > 0 ? "\(hour12):\(String(format: "%02d", m))\(ampm)" : "\(hour12)\(ampm)"
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        HeroCardView(drop: .previewRare, isWatched: false)
            .padding()
    }
}
