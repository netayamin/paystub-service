import SwiftUI

/// Skeleton loading state that mirrors the feed layout: LIVE bar, date strip, filters, hero, sections.
struct FeedSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                liveBarSkeleton
                dateStripSkeleton
                filterPillsSkeleton
                heroSkeleton
                sectionHeaderSkeleton
                topOpportunitiesSkeleton
                sectionHeaderSkeleton
                latestDropsSkeleton
                sectionHeaderSkeleton
                likelyToOpenSkeleton
            }
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
                .frame(width: 40, height: 12)
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.25))
                .frame(width: 70, height: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.background)
        .shimmer()
    }
    
    private var dateStripSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 48, height: 52)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .shimmer()
    }
    
    private var filterPillsSkeleton: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 12)
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 32)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .shimmer()
    }
    
    private var heroSkeleton: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.15))
            .frame(height: 280)
            .overlay(
                VStack {
                    HStack { Spacer(); RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.2)).frame(width: 36, height: 36).padding() }
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.25)).frame(width: 120, height: 14)
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.2)).frame(width: 180, height: 24)
                        RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.2)).frame(width: 140, height: 12)
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.25)).frame(width: 60, height: 36)
                            }
                        }
                    }
                    .padding(16)
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .shimmer()
    }
    
    private var sectionHeaderSkeleton: some View {
        HStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.25))
                .frame(width: 140, height: 11)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
    
    private var topOpportunitiesSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 280, height: 260)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 16)
        .shimmer()
    }
    
    private var latestDropsSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.25)).frame(width: 140, height: 14)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 100, height: 11)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 180, height: 24)
                    }
                    Spacer()
                }
                .padding(12)
                .background(AppTheme.surface)
                .cornerRadius(16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .shimmer()
    }
    
    private var likelyToOpenSkeleton: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.3)).frame(width: 160, height: 16)
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.2)).frame(width: 140, height: 11)
                }
                Spacer()
            }
            .padding(16)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.2)).frame(width: 40, height: 40)
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.25)).frame(width: 120, height: 14)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(AppTheme.surface)
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .shimmer()
    }
}

#Preview("Feed skeleton") {
    FeedSkeletonView()
}
