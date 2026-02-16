import SwiftUI

/// Pill-style tab bar: frosted glass (blur + dark tint), selected tab has a light pill.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var badgeCount: Int
    
    private let barHeight: CGFloat = 56
    var bottomSafeInset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 0) {
            tabItem(tag: 0, icon: "house", label: "Home")
            tabItem(tag: 1, icon: "bell", label: "New", badge: badgeCount)
            tabItem(tag: 2, icon: "person", label: "Profile")
        }
        .frame(height: barHeight)
        .padding(.horizontal, 2)
        .padding(.all, 4)
        .padding(.bottom, bottomSafeInset)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color.black.opacity(0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
        .frame(height: barHeight + bottomSafeInset)
    }
    
    private func tabItem(tag: Int, icon: String, label: String, badge: Int = 0) -> some View {
        let selected = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        } label: {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(AppTheme.tabBarPillSelected)
                        .padding(4)
                }
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .medium))
                        if badge > 0 {
                            Text("\(min(badge, 99))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Circle().fill(Color.red))
                                .offset(x: 8, y: -8)
                        }
                    }
                    Text(label)
                        .font(.system(size: 10, weight: selected ? .semibold : .regular))
                }
                .foregroundColor(selected ? AppTheme.tabBarSelected : AppTheme.tabBarUnselected)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Tab bar") {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0), badgeCount: 3)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }
}
