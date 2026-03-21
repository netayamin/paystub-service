import SwiftUI

/// Bottom dock tab bar: **flush** to screen edges, **no shadow**, **only top corners** rounded; white extends into the **home-indicator safe area**.
///
/// `ContentView`: **DISCOVERY** = 0 Feed · **ANALYTICS** = 1 Search · **SNIPES** = 2 Saved · **PROFILE** = 3.
/// Visual order matches reference: DISCOVERY · SNIPES · ANALYTICS · PROFILE.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0

    private let iconWellSize: CGFloat = 44
    private let pillRowHeight: CGFloat = 62
    /// Rounded top-left & top-right only (dock); visibly softer than the feed canvas.
    private let topCornerRadius: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tag: 0, icon: "safari.fill", label: "DISCOVERY")
            tabButton(tag: 2, icon: "scope", label: "SNIPES")
            tabButton(tag: 1, icon: "chart.line.uptrend.xyaxis", label: "ANALYTICS")
            tabButton(tag: 3, icon: "person.fill", label: "PROFILE")
        }
        .padding(.horizontal, 6)
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
            .fill(SnagDesignSystem.pageWhite)
        }
        // Same white under the home indicator / bottom inset (no gap color).
        .background {
            SnagDesignSystem.pageWhite
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(tag: Int, icon: String, label: String) -> some View {
        let on = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if on {
                        Circle()
                            .fill(SnagDesignSystem.tabBarFeaturedCoral)
                            .frame(width: iconWellSize, height: iconWellSize)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: on ? .semibold : .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(on ? .white : SnagDesignSystem.tabBarCharcoal)
                }
                .frame(width: iconWellSize, height: iconWellSize)

                Text(label)
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .foregroundColor(on ? SnagDesignSystem.tabBarFeaturedCoral : SnagDesignSystem.tabBarCharcoal)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

#Preview("Tab bar — Drops") {
    ZStack {
        Color(white: 0.88).ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0))
        }
    }
}

#Preview("Tab bar — Live feed") {
    ZStack {
        Color(white: 0.88).ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(1))
        }
    }
}
