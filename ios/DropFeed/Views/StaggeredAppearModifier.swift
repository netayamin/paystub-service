import SwiftUI

/// Staggered fade-in + slide-up for list items. Respects Reduce Motion.
struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    let delayPerItem: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    
    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (appeared ? 1 : 0))
            .offset(y: reduceMotion ? 0 : (appeared ? 0 : 20))
            .animation(
                reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(Double(index) * delayPerItem),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

extension View {
    func staggeredAppear(index: Int, delayPerItem: Double = 0.05) -> some View {
        modifier(StaggeredAppearModifier(index: index, delayPerItem: delayPerItem))
    }
}
