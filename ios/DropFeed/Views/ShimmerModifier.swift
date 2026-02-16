import SwiftUI

/// Shimmer effect for skeleton placeholders. Respects Reduce Motion.
struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if !reduceMotion {
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.35),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.5)
                            .offset(x: -geo.size.width * 0.5 + phase * (geo.size.width + geo.size.width * 0.5))
                        }
                        .clipped()
                        .mask(content)
                    }
                }
            )
            .onAppear {
                if reduceMotion { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
