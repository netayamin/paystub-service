import SwiftUI

/// Barebones shimmer skeleton matching the simplified feed list.
struct FeedSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    skeletonRow
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(AppTheme.background)
    }

    private var skeletonRow: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.14))
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 220, height: 14)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 180, height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 140, height: 12)
            }

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 999)
                .fill(Color.white.opacity(0.16))
                .frame(width: 96, height: 38)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 0.5)
        )
        .shimmer()
    }
}

#Preview("Feed skeleton") {
    FeedSkeletonView()
}
