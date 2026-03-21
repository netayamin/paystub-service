import SwiftUI

struct HeroCardView: View {
    let drop: Drop
    let isWatched: Bool
    var onToggleWatch: ((String) -> Void)?
    
    private var slots: [DropSlot] { Array(drop.slots.prefix(5)) }
    
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
                        case .empty:
                            CardImageSkeleton(tone: .heroMuted)
                                .frame(width: geo.size.width, height: geo.size.height)
                        case .failure:
                            gradientFallback
                                .frame(width: geo.size.width, height: geo.size.height)
                        @unknown default:
                            CardImageSkeleton(tone: .heroMuted)
                                .frame(width: geo.size.width, height: geo.size.height)
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
                    VStack(alignment: .trailing, spacing: 2) {
                        if let rh = drop.rarityHeadline, !rh.isEmpty {
                            Text(rh)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                                .multilineTextAlignment(.trailing)
                        }
                        if let cap = drop.heroScoreCaption, !cap.isEmpty {
                            Text(cap)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
                if let scan = drop.heroScanMetricsLine, !scan.isEmpty {
                    Text(scan)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                if let hd = drop.heroDescription, !hd.isEmpty {
                    Text(hd)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
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
