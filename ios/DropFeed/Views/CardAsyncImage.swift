import SwiftUI
import UIKit

// MARK: - Skeleton tone (matches surrounding card surface)

enum CardImageSkeletonTone {
    /// Search / live-feed rows on white or light gray.
    case lightOnLight
    /// Dark `AppTheme` cards (thumbnails on charcoal surfaces).
    case darkCard
    /// Snag-style neutral chip (e.g. circular row avatar).
    case snagMuted
    /// Full-bleed hero / crown cards while loading.
    case heroMuted
    /// Warm cards (e.g. top opportunity image area).
    case warmPlaceholder
}

// MARK: - Shimmer image placeholder

struct CardImageSkeleton: View {
    var tone: CardImageSkeletonTone = .lightOnLight

    private var fill: Color {
        switch tone {
        case .lightOnLight:
            return Color(white: 0.90)
        case .darkCard:
            return AppTheme.surfaceElevated
        case .snagMuted:
            return SnagDesignSystem.cardGray
        case .heroMuted:
            return Color(white: 0.32)
        case .warmPlaceholder:
            return Color(red: 0.70, green: 0.48, blue: 0.38)
        }
    }

    var body: some View {
        Rectangle()
            .fill(fill)
            .shimmer()
    }
}

// MARK: - Async image + loading skeleton + failure fallback

struct CardAsyncImage<Fallback: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var skeletonTone: CardImageSkeletonTone = .lightOnLight
    @ViewBuilder var fallback: () -> Fallback

    @State private var loaded: UIImage?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let url {
                if loadFailed {
                    fallback()
                } else if let ui = loaded ?? RestaurantImageMemoryCache.image(for: url) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity.animation(.easeOut(duration: 0.22)))
                } else {
                    CardImageSkeleton(tone: skeletonTone)
                        .task(id: url.absoluteString) {
                            loadFailed = false
                            if let mem = RestaurantImageMemoryCache.image(for: url) {
                                loaded = mem
                                return
                            }
                            let img = await RestaurantImageLoader.shared.image(for: url)
                            loaded = img
                            loadFailed = (img == nil)
                        }
                }
            } else {
                fallback()
            }
        }
    }
}

#if DEBUG
#Preview("Skeleton tones") {
    VStack(spacing: 8) {
        HStack(spacing: 8) {
            CardImageSkeleton(tone: .lightOnLight).frame(width: 60, height: 60).clipped()
            CardImageSkeleton(tone: .darkCard).frame(width: 60, height: 60).clipped()
            CardImageSkeleton(tone: .snagMuted).frame(width: 48, height: 48).clipShape(Circle())
        }
        CardImageSkeleton(tone: .heroMuted).frame(height: 100).clipped()
    }
    .padding()
    .background(Color.black.opacity(0.2))
}
#endif
