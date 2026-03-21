import SwiftUI

/// Floating tab bar: top-rounded **#F5F5F5** tray, **#4A4A4A** side labels, raised coral **DROPS** FAB (**#F1645F**) with flame.
///
/// `ContentView` indices: **DROPS** = 0 Feed · **LIVE FEED** = 1 Search · **BOOKINGS** = 2 Saved · **PROFILE** = 3.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0
    var bottomSafeInset: CGFloat = 0

    private let fabSize: CGFloat = 68
    private let fabOverlap: CGFloat = 30

    private var barBottomPadding: CGFloat {
        10 + (bottomSafeInset > 0 ? bottomSafeInset : 20)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            sideTab(tag: 1, icon: "gauge.with.dots.needle.67percent", label: "LIVE FEED")
            Spacer(minLength: 0)
            Color.clear.frame(width: fabSize - 8)
            Spacer(minLength: 0)
            sideTab(tag: 2, icon: "ticket.fill", label: "BOOKINGS")
            sideTab(tag: 3, icon: "person.fill", label: "PROFILE")
        }
        .padding(.horizontal, 6)
        .padding(.top, 20)
        .padding(.bottom, barBottomPadding)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(SnagDesignSystem.tabBarSurface)
            .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: -6)
        )
        .overlay(alignment: .top) {
            dropsCenterButton
                .offset(y: fabOverlap)
        }
        .padding(.top, fabOverlap)
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
                    .shadow(color: Color.black.opacity(on ? 0.24 : 0.14), radius: on ? 14 : 9, x: 0, y: 7)
                    .overlay(
                        Circle()
                            .stroke(SnagDesignSystem.tabBarFeaturedCoral.opacity(on ? 0 : 0.5), lineWidth: on ? 0 : 2)
                    )

                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(on ? .white : SnagDesignSystem.tabBarFeaturedCoral)
                    Text("DROPS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(on ? .white : SnagDesignSystem.tabBarFeaturedCoral)
                        .tracking(0.6)
                }
                .offset(y: 2)
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
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: on ? .semibold : .regular))
                    .symbolRenderingMode(.monochrome)
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.35)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(on ? SnagDesignSystem.tabBarFeaturedCoral : SnagDesignSystem.tabBarCharcoal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
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
