import SwiftUI

/// Bottom tab bar — dark dock, **FEED · EXPLORE · PROFILE**. Unread badge on Explore when alerts need attention.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0

    private let iconWellSize: CGFloat = 44
    private let pillRowHeight: CGFloat = 62
    private let topCornerRadius: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tag: 0, icon: "location.north.circle.fill", label: "FEED")
            tabButton(tag: 1, icon: "safari.fill", label: "EXPLORE", badge: alertBadgeCount)
            tabButton(tag: 2, icon: "person.fill", label: "PROFILE")
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(minHeight: pillRowHeight)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: topCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: topCornerRadius,
                style: .continuous
            )
            .fill(SnagDesignSystem.tabBarDarkSurface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
            }
        }
        .background {
            SnagDesignSystem.tabBarDarkSurface
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabAccent(for tag: Int) -> Color {
        tag == 1 ? SnagDesignSystem.exploreRed : SnagDesignSystem.salmonAccent
    }

    private func tabButton(tag: Int, icon: String, label: String, badge: Int = 0) -> some View {
        let on = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        if on {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(SnagDesignSystem.tabBarDarkSelectedWell)
                                .frame(width: iconWellSize + 8, height: iconWellSize + 4)
                        }
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: on ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(on ? tabAccent(for: tag) : SnagDesignSystem.darkTextMuted)
                    }
                    .frame(width: iconWellSize + 8, height: iconWellSize + 4)

                    if badge > 0, tag == 1 {
                        Text("\(min(badge, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(SnagDesignSystem.exploreRed)
                            .clipShape(Circle())
                            .offset(x: 10, y: -6)
                    }
                }

                Text(label)
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(on ? tabAccent(for: tag) : SnagDesignSystem.darkTextMuted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

#Preview("Tab bar — dark") {
    ZStack {
        SnagDesignSystem.darkCanvas.ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0))
        }
    }
}
