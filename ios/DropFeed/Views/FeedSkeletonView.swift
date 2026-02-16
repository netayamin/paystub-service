import SwiftUI

/// Skeleton loading state that mirrors the feed layout — LIVE bar, HOT RELEASES, cards, grid.
struct FeedSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                liveBarSkeleton
                hotReleasesSkeleton
                gridSkeleton
            }
            .padding(.vertical, 16)
        }
        .background(AppTheme.background)
    }
    
    private var liveBarSkeleton: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.3))
                .frame(width: 8, height: 8)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.3))
                .frame(height: 12)
                .frame(maxWidth: 180)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
        .shimmer()
    }
    
    private var hotReleasesSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 24, height: 20)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 140, height: 22)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 80, height: 14)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        cardSkeleton
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 16)
        .background(AppTheme.background)
        .shimmer()
    }
    
    private var cardSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.2))
                .frame(width: 260, height: 140)
            
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 44, height: 44)
            }
            .padding(12)
        }
        .frame(width: 260)
        .background(AppTheme.surface)
        .cornerRadius(16)
    }
    
    private var gridSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 100, height: 18)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 60, height: 12)
            }
            .padding(.horizontal, 16)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    gridCardSkeleton
                }
            }
            .padding(.horizontal, 16)
        }
        .shimmer()
    }
    
    private var gridCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.2))
                .frame(height: 100)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 80, height: 12)
            }
            .padding(14)
        }
        .background(AppTheme.surface)
        .cornerRadius(14)
    }
}

#Preview("Feed skeleton") {
    FeedSkeletonView()
}
