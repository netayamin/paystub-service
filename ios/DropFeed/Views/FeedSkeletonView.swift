import SwiftUI

/// Shimmer skeleton matching the new 3-section feed layout:
/// Top Opportunities (hero carousel) → Hot Right Now (2-col grid) → Just Dropped (vertical list)
struct FeedSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                topOpportunitiesSkeleton
                hotRightNowSkeleton
                justDroppedSkeleton
            }
        }
        .background(AppTheme.background)
    }

    // MARK: - Section header skeleton

    private func skeletonSectionHeader() -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.22))
                .frame(width: 14, height: 14)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.18))
                .frame(width: 130, height: 12)
        }
        .padding(.horizontal, AppTheme.spacingLG)
        .padding(.top, AppTheme.spacingXL)
        .padding(.bottom, 12)
        .shimmer()
    }

    // MARK: - Top Opportunities (hero carousel)

    private var topOpportunitiesSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            skeletonSectionHeader()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.10))
                            .frame(
                                width: UIScreen.main.bounds.width * 0.82,
                                height: 284
                            )
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
            }
            .shimmer()
        }
        .padding(.bottom, AppTheme.spacingXL)
    }

    // MARK: - Hot Right Now (2-column grid)

    private var hotRightNowSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            skeletonSectionHeader()

            let pairs = 0..<2
            VStack(spacing: 10) {
                ForEach(pairs, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 10) {
                        hotGridCardSkeleton
                        hotGridCardSkeleton
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .shimmer()
        }
        .padding(.bottom, AppTheme.spacingXL)
    }

    private var hotGridCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.white.opacity(0.14))
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 100, height: 13)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 70, height: 10)
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Just Dropped (vertical rows)

    private var justDroppedSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            skeletonSectionHeader()

            VStack(spacing: AppTheme.spacingSM) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 140, height: 14)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 110, height: 10)
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.14))
                                    .frame(width: 52, height: 18)
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.10))
                                    .frame(width: 36, height: 18)
                            }
                        }
                        Spacer()
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 52, height: 34)
                    }
                    .padding(12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .shimmer()
        }
    }
}

#Preview("Feed skeleton") {
    FeedSkeletonView()
        .background(AppTheme.background)
}
