import SwiftUI

/// Bottom tab bar: gray tray (top-rounded) flush to the bottom safe area, center **DROPS** FAB overlaps upward.
/// Uses a fixed-height `ZStack` — no extra top padding on the whole bar (avoids the “floating strip” gap).
///
/// `ContentView`: **DROPS** = 0 Feed · **LIVE FEED** = 1 Search · **BOOKINGS** = 2 Saved · **PROFILE** = 3.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0

    private let fabSize: CGFloat = 64
    /// Total height reserved for the bar + half the FAB sticking up (content scrolls above via `safeAreaInset`).
    private let stackHeight: CGFloat = 84

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tray sits on the bottom of this ZStack; background is only behind the tray, not a full-screen float.
            HStack(alignment: .bottom, spacing: 0) {
                sideTab(tag: 1, icon: "gauge.with.dots.needle.67percent", label: "LIVE FEED")
                Spacer(minLength: 0)
                Color.clear.frame(width: fabSize)
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                sideTab(tag: 2, icon: "ticket.fill", label: "BOOKINGS")
                sideTab(tag: 3, icon: "person.fill", label: "PROFILE")
            }
            .padding(.horizontal, 6)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 26,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 26,
                    style: .continuous
                )
                .fill(SnagDesignSystem.tabBarSurface)
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: -4)
            )

            // FAB above tray; centered; doesn’t steal taps from side tabs (narrow circle).
            dropsCenterButton
                .offset(y: -(fabSize * 0.36))
        }
        .frame(height: stackHeight)
        .frame(maxWidth: .infinity)
    }

    private var dropsCenterButton: some View {
        let on = selectedTab == 0
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selectedTab = 0
            }
        } label: {
            ZStack {
                Circle()
                    .fill(on ? SnagDesignSystem.tabBarFeaturedCoral : Color.white)
                    .frame(width: fabSize, height: fabSize)
                    .shadow(color: Color.black.opacity(on ? 0.22 : 0.12), radius: on ? 12 : 8, x: 0, y: 5)
                    .overlay(
                        Circle()
                            .stroke(SnagDesignSystem.tabBarFeaturedCoral.opacity(on ? 0 : 0.45), lineWidth: on ? 0 : 2)
                    )

                VStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(on ? .white : SnagDesignSystem.tabBarFeaturedCoral)
                    Text("DROPS")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(on ? .white : SnagDesignSystem.tabBarFeaturedCoral)
                        .tracking(0.5)
                }
                .offset(y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drops")
    }

    private func sideTab(tag: Int, icon: String, label: String) -> some View {
        let on = selectedTab == tag
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: on ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)
                Text(label)
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(on ? SnagDesignSystem.tabBarFeaturedCoral : SnagDesignSystem.tabBarCharcoal)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Tab bar") {
    ZStack {
        Color(white: 0.92).ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0))
        }
    }
}
