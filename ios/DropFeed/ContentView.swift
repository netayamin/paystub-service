import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var newTabBadgeCount = 0
    
    init() {
        UITabBar.appearance().isHidden = true
    }
    
    var body: some View {
        GeometryReader { geo in
            let bottomInset = geo.safeAreaInsets.bottom
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    FeedView()
                        .applyBG()
                        .tag(0)
                    NewDropsView(badgeCount: $newTabBadgeCount)
                        .applyBG()
                        .tag(1)
                    ProfilePlaceholderView()
                        .applyBG()
                        .tag(2)
                }
                CustomTabBar(selectedTab: $selectedTab, badgeCount: newTabBadgeCount, bottomSafeInset: bottomInset)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
            .background(AppTheme.background)
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Full-screen content (article pattern)
private extension View {
    func applyBG() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
