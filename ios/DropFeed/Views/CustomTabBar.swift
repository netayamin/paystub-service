import SwiftUI

/// Card-style tab bar: white background, rounded top corners, upward shadow.
/// Two tabs only: LIVE (feed) and SEARCH.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    /// Legacy params kept so existing call sites compile without changes.
    var alertBadgeCount: Int = 0
    var bottomSafeInset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            tabItem(tag: 0, icon: "antenna.radiowaves.left.and.right", label: "LIVE")
            tabItem(tag: 1, icon: "magnifyingglass", label: "SEARCH")
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        // White background that also fills the safe-area region below (home indicator).
        .background(
            Color.white
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: -4)
    }

    private func tabItem(tag: Int, icon: String, label: String) -> some View {
        let sel = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tag }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: sel ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
            }
            .foregroundColor(sel ? AppTheme.accentRed : Color(white: 0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Tab bar") {
    ZStack {
        Color(white: 0.95).ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0))
        }
    }
}
