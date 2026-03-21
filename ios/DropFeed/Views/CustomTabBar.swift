import SwiftUI

/// Bottom nav matching reference: FEED · EXPLORE · SAVED · PROFILE — white card, rounded top, upward shadow.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0
    var bottomSafeInset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            tabItem(tag: 0, icon: "dot.radiowaves.left.and.right", label: "FEED")
            tabItem(tag: 1, icon: "safari", label: "EXPLORE")
            tabItem(tag: 2, icon: "bookmark", label: "SAVED")
            tabItem(tag: 3, icon: "person", label: "PROFILE")
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
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
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: sel ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
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
