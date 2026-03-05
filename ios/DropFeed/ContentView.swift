import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var feedVM = FeedViewModel()
    @StateObject private var savedVM = SavedViewModel()
    @StateObject private var alertsVM = AlertsViewModel()
    @StateObject private var premium = PremiumManager()
    
    init() {
        UITabBar.appearance().isHidden = true
    }
    
    var body: some View {
        GeometryReader { geo in
            let bottomInset = geo.safeAreaInsets.bottom
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    FeedView(feedVM: feedVM, savedVM: savedVM, premium: premium)
                        .applyBG()
                        .tag(0)
                    SavedView(savedVM: savedVM, feedVM: feedVM, premium: premium)
                        .applyBG()
                        .tag(1)
                    AlertsView(alertsVM: alertsVM)
                        .applyBG()
                        .tag(2)
                    ProfilePlaceholderView()
                        .applyBG()
                        .tag(3)
                }
                CustomTabBar(
                    selectedTab: $selectedTab,
                    alertBadgeCount: alertsVM.unreadCount,
                    bottomSafeInset: bottomInset
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(AppTheme.background)
            .ignoresSafeArea(.keyboard)
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea()
        .task {
            await savedVM.loadAll()
            alertsVM.startPolling()
            await premium.checkEntitlements()
        }
    }
}

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
