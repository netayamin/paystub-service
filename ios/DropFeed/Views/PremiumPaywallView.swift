import SwiftUI

struct PremiumPaywallView: View {
    @ObservedObject var premium: PremiumManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Close button
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Hero
                    VStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(colors: [AppTheme.premiumGold, Color.orange], startPoint: .top, endPoint: .bottom)
                            )
                        
                        Text("DropFeed Premium")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary)
                        
                        Text("Speed and intelligence for serious diners")
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 24)
                    
                    // Value props
                    VStack(spacing: 0) {
                        featureRow(
                            icon: "bolt.fill",
                            iconColor: AppTheme.premiumGold,
                            title: "Instant Drop Alerts",
                            subtitle: "Know the SECOND Don Angie has a table — before anyone else."
                        )
                        featureRow(
                            icon: "chart.bar.fill",
                            iconColor: AppTheme.scarcityRare,
                            title: "Rarity Insights",
                            subtitle: "See exactly HOW rare each opening is — \"open only 2 of the last 14 days.\""
                        )
                        featureRow(
                            icon: "eye.fill",
                            iconColor: AppTheme.accent,
                            title: "Likely to Open",
                            subtitle: "Full list of restaurants about to drop tables, based on 14-day patterns."
                        )
                        featureRow(
                            icon: "bookmark.fill",
                            iconColor: AppTheme.accentRed,
                            title: "Unlimited Watchlist",
                            subtitle: "Save as many restaurants as you want. Get alerts for each one."
                        )
                    }
                    .padding(.top, 32)
                    .padding(.horizontal, 20)
                    
                    // CTA
                    VStack(spacing: 12) {
                        Button {
                            Task { await premium.purchase() }
                        } label: {
                            HStack(spacing: 8) {
                                if premium.purchaseInProgress {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text("Upgrade — \(premium.priceLabel)")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(colors: [AppTheme.premiumGold, Color.orange], startPoint: .leading, endPoint: .trailing)
                            )
                        }
                        .disabled(premium.purchaseInProgress)
                        
                        Button {
                            Task { await premium.restore() }
                        } label: {
                            Text("Restore Purchase")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        
                        if let err = premium.errorMessage {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accentRed)
                        }
                    }
                    .padding(.top, 32)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .task { await premium.loadProducts() }
    }
    
    private func featureRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.15))
                .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

#Preview {
    PremiumPaywallView(premium: PremiumManager())
}
