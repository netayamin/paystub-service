import SwiftUI

/// Thin “train line” at the top of the feed: a moving strip that indicates the dashboard updates by itself.
/// Respects Reduce Motion.
struct LiveUpdateTrainBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    private let barHeight: CGFloat = 4
    private let trainWidth: CGFloat = 80
    private let duration: Double = 2.2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: barHeight / 2)
                    .fill(AppTheme.surface.opacity(0.8))
                    .frame(height: barHeight)

                // Train: gradient head + soft trail
                if reduceMotion {
                    // Static “on” segment (red = live)
                    RoundedRectangle(cornerRadius: barHeight / 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accentRed.opacity(0.5),
                                    AppTheme.accentRed.opacity(0.8),
                                    AppTheme.accentRed.opacity(0.4)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: trainWidth, height: barHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Moving train: red head + trail (red = live)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(AppTheme.accentRed)
                            .frame(width: 24, height: barHeight)
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(AppTheme.accentRed.opacity(0.8))
                            .frame(width: 16, height: barHeight)
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(AppTheme.accentRed.opacity(0.5))
                            .frame(width: 12, height: barHeight)
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(AppTheme.accentRed.opacity(0.3))
                            .frame(width: 10, height: barHeight)
                    }
                    .offset(x: -trainWidth + (w + trainWidth) * phase)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: barHeight)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .linear(duration: duration)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }
}

#Preview("Live update train bar") {
    VStack(spacing: 0) {
        LiveUpdateTrainBar()
            .padding(.horizontal)
        Spacer()
    }
    .background(AppTheme.background)
}
