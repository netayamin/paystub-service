import SwiftUI

/// Pulsing red dot for LIVE indicator. Respects Reduce Motion.
struct AnimatedLiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    
    var body: some View {
        Circle()
            .fill(AppTheme.liveDot)
            .frame(width: 8, height: 8)
            .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.3 : 0.9))
            .opacity(reduceMotion ? 1 : (isPulsing ? 0.8 : 1))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

#Preview("LIVE dot") {
    HStack(spacing: 8) {
        AnimatedLiveDot()
        Text("LIVE: Scanning NYC…")
            .font(.caption)
    }
    .padding()
}
