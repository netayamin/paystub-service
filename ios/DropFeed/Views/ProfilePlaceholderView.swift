import SwiftUI

/// Profile tab: signed-in user + sign out.
struct ProfilePlaceholderView: View {
    @EnvironmentObject private var auth: AuthSessionManager

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 24)
            Image(systemName: "bolt.fill")
                .font(.system(size: 40))
                .foregroundColor(SnagDesignSystem.salmonAccent)
            Text("SNAG")
                .font(.system(size: 28, weight: .black, design: .serif))
                .foregroundColor(SnagDesignSystem.darkTextPrimary)
            Text("Hey, \(auth.displayName)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(SnagDesignSystem.darkTextPrimary)
            if !auth.email.isEmpty {
                Text(auth.email)
                    .font(.system(size: 14))
                    .foregroundColor(SnagDesignSystem.darkTextMuted)
            }
            Text("Profile & settings coming soon.")
                .font(.system(size: 15))
                .foregroundColor(SnagDesignSystem.darkTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                auth.signOut()
            } label: {
                Text("Sign out")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SnagDesignSystem.darkCanvas)
    }
}

#Preview {
    ProfilePlaceholderView()
        .environmentObject(AuthSessionManager())
}
