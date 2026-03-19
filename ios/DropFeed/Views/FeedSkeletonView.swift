import SwiftUI

struct FeedSkeletonView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    liveRowSkeleton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGray6))
    }

    private var liveRowSkeleton: some View {
        let block = Color(.systemGray5)

        return HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(block)
                    .frame(width: 78, height: 78)

                RoundedRectangle(cornerRadius: 20)
                    .fill(block.opacity(0.95))
                    .frame(width: 72, height: 18)
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(block)
                    .frame(width: 210, height: 14)

                RoundedRectangle(cornerRadius: 6)
                    .fill(block)
                    .frame(width: 140, height: 12)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(block)
                        .frame(width: 28, height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(block)
                        .frame(width: 110, height: 12)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 12)
                .fill(block)
                .frame(width: 104, height: 40)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shimmer()
    }
}

#Preview("Feed skeleton") {
    FeedSkeletonView()
        .background(Color(.systemGray6))
}
