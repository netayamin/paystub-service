import SwiftUI

/// Single app tab bar — light canvas, outline-style SF Symbols (Feed · Explore · Profile).
struct AppTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tag: 0, systemName: "dot.radiowaves.left.and.right")
            tabButton(tag: 1, systemName: "magnifyingglass", badge: alertBadgeCount)
            tabButton(tag: 2, systemName: "person")
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(CreamEditorialTheme.canvas)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
        .background(CreamEditorialTheme.canvas.ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(tag: Int, systemName: String, badge: Int = 0) -> some View {
        let on = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tag }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: on ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor(on ? CreamEditorialTheme.textPrimary : Color(white: 0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                if badge > 0, tag == 1 {
                    Text("\(min(badge, 99))")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(SnagDesignSystem.exploreRed)
                        .offset(x: 8, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        Spacer()
        AppTabBar(selectedTab: .constant(0))
    }
    .background(CreamEditorialTheme.canvas)
}
