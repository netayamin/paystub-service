import SwiftUI

struct HeroCardView: View {
    let drop: Drop
    let isWatched: Bool
    var onToggleWatch: ((String) -> Void)?
    
    private var slots: [DropSlot] { Array(drop.slots.prefix(5)) }
    private var rarityScoreInt: Int {
        guard let r = drop.rarityScore else { return 0 }
        let value = r <= 1 ? Int(r * 100) : Int(r.rounded())
        return min(100, max(0, value))
    }
    private var heroDescription: String {
        let party = drop.partySizesAvailable.sorted().first.map { "\($0)" } ?? "2"
        let time = slots.first.flatMap { formatTime($0.time ?? "") } ?? "tonight"
        if (drop.ratingCount ?? 0) > 500 || drop.rarityScore ?? 0 > 0.7 {
            return "Rare table for \(party) available \(time). Usually books 30 days in advance."
        }
        return "Table for \(party) available \(time)."
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
            .frame(height: 300)
            
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.4),
                    .init(color: .black.opacity(0.9), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
            
            // Top: EXCLUSIVE badge (orange pill) + bookmark
            VStack {
                HStack(alignment: .top) {
                    Text("EXCLUSIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.accentOrange)
                        .cornerRadius(8)
                    Spacer()
                    Button {
                        onToggleWatch?(drop.name)
                    } label: {
                        Image(systemName: isWatched ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(isWatched ? AppTheme.accentOrange.opacity(0.9) : Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                Spacer()
            }
            .frame(height: 300)
            
            // Bottom: #1 TOP OPPORTUNITY, name, Rarity Score, description, orange CTA
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("#1 TOP OPPORTUNITY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                        Text(drop.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("Rarity Score \(rarityScoreInt)/100")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                }
                
                Text(heroDescription)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                
                if let firstUrl = drop.resyUrl ?? slots.first?.resyUrl, let url = URL(string: firstUrl) {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 8) {
                            Text("Reserve on Resy")
                                .font(.system(size: 16, weight: .bold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppTheme.accentOrange)
                        .cornerRadius(14)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.top, 6)
                }
            }
            .padding(16)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
    }
    
    private func formatTime(_ time: String) -> String {
        let t = time.split(separator: "–").first.map(String.init) ?? time
        let parts = t.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let h = parts.first.flatMap({ Int($0) }) else { return "tonight" }
        let m = parts.count > 1 ? Int(parts[1].prefix(2)) ?? 0 : 0
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        if m > 0 { return "tonight at \(hour12):\(String(format: "%02d", m)) \(ampm)" }
        return "tonight at \(hour12) \(ampm)"
    }
    
    private var gradientFallback: some View {
        LinearGradient(
            colors: [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.08, green: 0.08, blue: 0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        HeroCardView(drop: .previewRare, isWatched: false)
            .padding()
    }
}
