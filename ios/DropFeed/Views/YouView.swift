import SwiftUI

/// You tab: stats, preferences, premium, about.
struct YouView: View {
    @ObservedObject var savedVM: SavedViewModel
    @ObservedObject var feedVM: FeedViewModel
    @ObservedObject var premium: PremiumManager
    @State private var notificationsEnabled = true
    @State private var showPaywall = false
    
    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats
                    statsSection
                    // Preferences
                    preferencesSection
                    // Premium
                    premiumSection
                    // About
                    aboutSection
                }
                .padding(.vertical, 20)
            }
            .background(AppTheme.background)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView(premium: premium)
            }
        }
    }
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                row(label: "Watching", value: "\(savedVM.watchedVenues.count) venues")
                Divider().background(AppTheme.border).padding(.leading, 16)
                row(label: "Last scan", value: feedVM.lastScanText)
            }
            .background(AppTheme.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 16)
    }
    
    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preferences")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                HStack {
                    Text("Push notifications")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Toggle("", isOn: $notificationsEnabled)
                        .labelsHidden()
                        .tint(AppTheme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppTheme.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 16)
    }
    
    private var premiumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Premium")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(0.5)
            
            Button {
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: premium.isPremium ? "crown.fill" : "crown")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.premiumGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(premium.isPremium ? "Premium active" : "Upgrade to Premium")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text(premium.isPremium ? "Instant alerts, rarity insights, unlimited watchlist" : "Instant alerts, full Likely to Open, unlimited watchlist")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    Spacer()
                    if !premium.isPremium {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(16)
                .background(AppTheme.surface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.border, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                row(label: "Version", value: appVersion)
                Divider().background(AppTheme.border).padding(.leading, 16)
                HStack {
                    Text("Support")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary)
                    Spacer()
                    Link("Contact", destination: URL(string: "https://resy.com")!)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppTheme.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    YouView(
        savedVM: SavedViewModel(),
        feedVM: FeedViewModel(),
        premium: PremiumManager()
    )
}
