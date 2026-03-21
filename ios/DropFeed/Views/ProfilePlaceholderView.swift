import SwiftUI

/// Minimal profile shell — matches tab bar layout; expand later with account / settings.
struct ProfilePlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 24)
            Image(systemName: "bolt.fill")
                .font(.system(size: 40))
                .foregroundColor(SnagDesignSystem.salmonAccent)
            Text("SNAG")
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundColor(SnagDesignSystem.darkTextPrimary)
            Text("Profile & settings coming soon.")
                .font(.system(size: 15))
                .foregroundColor(SnagDesignSystem.darkTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SnagDesignSystem.darkCanvas)
    }
}

#Preview {
    ProfilePlaceholderView()
}
