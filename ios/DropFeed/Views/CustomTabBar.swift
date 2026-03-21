import SwiftUI

/// Floating pill tab bar: **four equal tabs** in one row — same layout; **red circle + white icon** only when selected.
///
/// `ContentView`: **DROPS** = 0 Feed · **LIVE FEED** = 1 Search · **BOOKINGS** = 2 Saved · **PROFILE** = 3.
/// Visual order: LIVE FEED · DROPS · BOOKINGS · PROFILE.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0

    private let iconWellSize: CGFloat = 44
    private let pillRowHeight: CGFloat = 62

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tag: 1, icon: "gauge.with.dots.needle.67percent", label: "LIVE FEED")
            tabButton(tag: 0, icon: "flame.fill", label: "DROPS")
            tabButton(tag: 2, icon: "ticket.fill", label: "BOOKINGS")
            tabButton(tag: 3, icon: "person.fill", label: "PROFILE")
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(minHeight: pillRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
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
        Color(white: 0.2).ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0))
        }
    }
}

#Preview("Tab bar — Live feed") {
    ZStack {
        Color(white: 0.2).ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(1))
        }
    }
}
