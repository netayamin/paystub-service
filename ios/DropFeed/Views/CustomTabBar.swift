import SwiftUI

/// Floating pill tab bar: **equal-width columns** so the DROPS FAB stays truly centered (no Spacer asymmetry).
///
/// `ContentView`: **DROPS** = 0 Feed · **LIVE FEED** = 1 Search · **BOOKINGS** = 2 Saved · **PROFILE** = 3.
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    var alertBadgeCount: Int = 0

    private let fabSize: CGFloat = 64
    private let fabLift: CGFloat = 28
    private let pillRowHeight: CGFloat = 56

    var body: some View {
        // Total height includes FAB protrusion so safeAreaInset doesn’t clip the circle.
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(height: pillRowHeight + fabLift)

            // Four equal quarters — geometric center of bar == center of column 2 (FAB).
            HStack(spacing: 0) {
                sideTab(tag: 1, icon: "gauge.with.dots.needle.67percent", label: "LIVE FEED")
                    .frame(maxWidth: .infinity)
                Color.clear
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                sideTab(tag: 2, icon: "ticket.fill", label: "BOOKINGS")
                    .frame(maxWidth: .infinity)
                sideTab(tag: 3, icon: "person.fill", label: "PROFILE")
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(height: pillRowHeight)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 6)
            )
            .overlay(alignment: .top) {
                dropsCenterButton
                    .offset(y: -fabLift)
            }
        }
        .frame(height: pillRowHeight + fabLift)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
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
                    .shadow(color: Color.black.opacity(on ? 0.24 : 0.14), radius: on ? 12 : 8, x: 0, y: 5)
                    .overlay(
                        Circle()
                            .stroke(SnagDesignSystem.tabBarFeaturedCoral.opacity(on ? 0 : 0.5), lineWidth: on ? 0 : 2)
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
            .frame(maxWidth: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Tab bar") {
    ZStack {
        Color(white: 0.2).ignoresSafeArea()
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(0))
        }
    }
}
