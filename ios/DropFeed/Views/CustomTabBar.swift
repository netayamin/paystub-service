import SwiftUI

/// Snag mock: floating white bar — selected tab = coral pill + chart icon for Scoreboard.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0
    var bottomSafeInset: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            snagTab(tag: 0, icon: "chart.bar.fill", label: "SCOREBOARD")
            snagTab(tag: 1, icon: "magnifyingglass", label: "SEARCH")
            snagTab(tag: 2, icon: "bookmark.fill", label: "SAVED")
            snagTab(tag: 3, icon: "person.fill", label: "PROFILE")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .padding(.bottom, max(6, bottomSafeInset > 0 ? bottomSafeInset - 8 : 6))
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: -4)
        )
        .padding(.horizontal, 12)
    }

    private func snagTab(tag: Int, icon: String, label: String) -> some View {
        let sel = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tag }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: sel ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundColor(sel ? SnagDesignSystem.coral : SnagDesignSystem.tabInactive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Group {
                    if sel {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(SnagDesignSystem.tabPillFill)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Tab bar") {
    ZStack {
        SnagDesignSystem.pageWhite.ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0))
        }
    }
}
