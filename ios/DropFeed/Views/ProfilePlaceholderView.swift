import SwiftUI

/// Minimal profile shell — matches tab bar layout; expand later with account / settings.
struct ProfilePlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 24)
            Image(systemName: "bolt.fill")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.accentRed)
            Text("SNAG")
                .font(.system(size: 28, weight: .black))
                .italic()
                .foregroundColor(SnagDesignSystem.textDark)
            Text("Profile & settings coming soon.")
                .font(.system(size: 15))
                .foregroundColor(SnagDesignSystem.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SnagDesignSystem.pageCanvas)
    }
}

#Preview {
    ProfilePlaceholderView()
}
