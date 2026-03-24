import SwiftUI

/// Quiet Curator first-load skeleton: cream canvas, **zero radius**, carousel peek, stream rows + tactical/footer blocks.
struct FeedSkeletonView: View {
    private let side: CGFloat = 14
    private let gap: CGFloat = 10
    /// Matches hottest carousel: two ~4:5 tiles + peek.
    private let peek: CGFloat = 4
    /// Matches live stream minimum row count (`minQuietCuratorStreamRows`).
    private let streamRows = 5

    /// Muted grey-beige blocks on cream (reference “brutalist-chic” loading).
    private let bone = Color(red: 228 / 255, green: 226 / 255, blue: 224 / 255)
    private let boneMuted = Color(red: 218 / 255, green: 216 / 255, blue: 214 / 255)

    private var screenW: CGFloat { UIScreen.main.bounds.width }

    private var heroInner: CGFloat { max(1, screenW - 2 * side) }

    private var heroMainWidth: CGFloat { max(178, (heroInner - gap - peek) / 2) }

    private var heroHeight: CGFloat { heroMainWidth * 5.0 / 4.0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBarSkeleton
                    .padding(.horizontal, side)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                hottestHeaderSkeleton
                    .padding(.horizontal, side)
                    .padding(.bottom, 12)

                heroCarouselSkeleton
                    .padding(.bottom, 24)

                liveStreamHeaderSkeleton
                    .padding(.horizontal, side)
                    .padding(.bottom, 12)

                streamListSkeleton
                    .padding(.horizontal, side)

                midSectionSkeleton
                    .padding(.horizontal, side)
                    .padding(.top, 28)

                exploreCtaSkeleton
                    .padding(.horizontal, side)
                    .padding(.top, 16)

                tacticalPanelSkeleton
                    .padding(.horizontal, side)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .background(CreamEditorialTheme.canvas)
    }

    // MARK: - Sections

    private var topBarSkeleton: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 8) {
                boneRect(width: 22, height: 22)
                boneRect(width: 148, height: 12)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                boneRect(width: 52, height: 9)
                boneRect(width: 76, height: 8)
            }
            boneRect(width: 32, height: 32)
            .padding(.leading, 10)
        }
        .shimmer()
    }

    private var hottestHeaderSkeleton: some View {
        HStack(alignment: .center) {
            boneRect(width: 168, height: 18)
            Spacer(minLength: 8)
            boneRect(width: 80, height: 9)
        }
        .shimmer()
    }

    /// Two-up ~4:5 tiles + sliver (matches live hottest carousel).
    private var heroCarouselSkeleton: some View {
        HStack(alignment: .top, spacing: gap) {
            Rectangle()
                .fill(bone)
                .frame(width: heroMainWidth, height: heroHeight)
            Rectangle()
                .fill(boneMuted)
                .frame(width: max(12, peek - 4), height: heroHeight)
        }
        .padding(.leading, side)
        .clipped()
        .shimmer()
    }

    private var liveStreamHeaderSkeleton: some View {
        HStack(alignment: .center) {
            boneRect(width: 128, height: 16)
            Spacer(minLength: 8)
            boneRect(width: 88, height: 11)
        }
        .shimmer()
    }

    private var streamListSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<streamRows, id: \.self) { index in
                streamRowSkeleton
                if index < streamRows - 1 {
                    Rectangle()
                        .fill(CreamEditorialTheme.hairline)
                        .frame(height: 1)
                }
            }
        }
        .overlay(
            Rectangle()
                .stroke(CreamEditorialTheme.hairline, lineWidth: 1)
        )
        .shimmer()
    }

    private var streamRowSkeleton: some View {
        HStack(alignment: .center, spacing: 12) {
            Rectangle()
                .fill(bone)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                Rectangle()
                    .fill(boneMuted)
                    .frame(width: min(220, screenW - 160), height: 11)
                Rectangle()
                    .fill(bone)
                    .frame(width: min(150, screenW - 200), height: 10)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(boneMuted)
                .frame(width: 56, height: 30)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    /// Reference: short section title, two-up grid, then a full-width strip above the ghost CTA.
    private var midSectionSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            boneRect(width: 140, height: 12)
            HStack(spacing: 12) {
                Rectangle()
                    .fill(bone)
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
                Rectangle()
                    .fill(bone)
                    .frame(maxWidth: .infinity)
                    .frame(height: 88)
            }
            Rectangle()
                .fill(boneMuted)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .shimmer()
    }

    private var exploreCtaSkeleton: some View {
        ZStack {
            Rectangle()
                .stroke(CreamEditorialTheme.exploreHairline, lineWidth: 1)
                .frame(height: 48)
            boneRect(width: 220, height: 11)
        }
        .shimmer()
    }

    private var tacticalPanelSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 150, height: 12)
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 110, height: 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(CreamEditorialTheme.tacticalDarkDivider)
                .frame(height: 1)
                .padding(.horizontal, 12)

            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Rectangle()
                                .stroke(CreamEditorialTheme.tacticalDarkDivider, lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 120, height: 9)
                        Rectangle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: min(240, screenW - 120), height: 12)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CreamEditorialTheme.tacticalDarkMeta)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                if i == 0 {
                    Rectangle()
                        .fill(CreamEditorialTheme.tacticalDarkDivider)
                        .frame(height: 1)
                        .padding(.leading, 70)
                }
            }
        }
        .background(CreamEditorialTheme.tacticalDarkSurface)
        .overlay(
            Rectangle()
                .stroke(CreamEditorialTheme.tacticalDarkDivider, lineWidth: 1)
        )
        .shimmer()
    }

    private func boneRect(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(bone)
            .frame(width: width, height: height)
    }
}

#Preview("Quiet Curator skeleton") {
    FeedSkeletonView()
}
