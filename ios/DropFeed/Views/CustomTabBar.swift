import SwiftUI

/// Bottom tab bar — dark dock, **FEED · EXPLORE · PROFILE**. Unread badge on Explore when alerts need attention.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0
    /// Cream / white dock with outline-style tabs (feed home); Explore/Profile keep contrast when this tab is active.
    var useLightChrome: Bool = false

    private let iconWellSize: CGFloat = 44
    private let pillRowHeight: CGFloat = 62
    private let topCornerRadius: CGFloat = 28

    var body: some View {
        Group {
            if useLightChrome {
                quietCuratorTabBar
            } else {
                darkDockTabBar
            }
        }
    }

    /// Flat off-white bar, thin top rule, three outline-style icons (reference UI).
    private var quietCuratorTabBar: some View {
        HStack(spacing: 0) {
            quietTabButton(tag: 0, systemName: "scope")
            quietTabButton(tag: 1, systemName: "magnifyingglass", badge: alertBadgeCount)
            quietTabButton(tag: 2, systemName: "person")
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
        .background(Color.white.ignoresSafeArea(edges: .bottom))
    }

    private func quietTabButton(tag: Int, systemName: String, badge: Int = 0) -> some View {
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
                        .padding(3)
                        .background(SnagDesignSystem.exploreRed)
                        .clipShape(Circle())
                        .offset(x: 8, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var darkDockTabBar: some View {
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
        if useLightChrome {
            if tag == 1 { return SnagDesignSystem.exploreRed }
            return tag == 0 ? CreamEditorialTheme.streamRed : CreamEditorialTheme.textPrimary
        }
        return tag == 1 ? SnagDesignSystem.exploreRed : SnagDesignSystem.salmonAccent
    }

    private func tabInactiveColor() -> Color {
        useLightChrome ? CreamEditorialTheme.textTertiary : SnagDesignSystem.darkTextMuted
    }

    private func selectedWellFill() -> Color {
        useLightChrome
            ? CreamEditorialTheme.canvas.opacity(0.95)
            : SnagDesignSystem.tabBarDarkSelectedWell
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
                                .fill(selectedWellFill())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(useLightChrome ? CreamEditorialTheme.hairline : Color.clear, lineWidth: 1)
                                )
                                .frame(width: iconWellSize + 8, height: iconWellSize + 4)
                        }
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: on ? .semibold : .regular))
                            .symbolRenderingMode(useLightChrome ? .monochrome : .hierarchical)
                            .foregroundColor(on ? tabAccent(for: tag) : tabInactiveColor())
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
                    .foregroundColor(on ? tabAccent(for: tag) : tabInactiveColor())
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
