import SwiftUI

/// Skeleton loading state: Just Dropped carousel, Hot Right Now, The Rarest.
struct FeedSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                sectionHeaderSkeleton
                justDroppedCarouselSkeleton
                sectionHeaderSkeleton
                hotRightNowSkeleton
                sectionHeaderSkeleton
                theRarestSkeleton
            }
        }
        .background(AppTheme.background)
    }

    private var sectionHeaderSkeleton: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.25)).frame(width: 12, height: 12)
            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 120, height: 11)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .shimmer()
    }

    private var justDroppedCarouselSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: (UIScreen.main.bounds.width - 32) * 0.85, height: 280)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
        .shimmer()
    }

    private var hotRightNowSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 0) {
                        RoundedRectangle(cornerRadius: 0).fill(Color.white.opacity(0.15)).frame(width: 160, height: 100)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 100, height: 14)
                            RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)).frame(width: 80, height: 10)
                            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.2)).frame(width: 140, height: 36)
                        }
                        .padding(10)
                    }
                    .frame(width: 160)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
        .shimmer()
    }

    private var theRarestSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.2)).frame(width: 80, height: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.25)).frame(width: 60, height: 10)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)).frame(width: 90, height: 10)
                    }
                    Spacer()
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.2)).frame(width: 90, height: 36)
                }
                .padding(14)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .shimmer()
    }
}

#Preview("Feed skeleton") {
    FeedSkeletonView()
}
