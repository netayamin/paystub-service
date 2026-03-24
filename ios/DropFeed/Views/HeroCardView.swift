import SwiftUI

/// TOP OPPORTUNITY hero — premium dark card (see ``DSPremiumHeroCard``).
struct HeroCardView: View {
    let drop: Drop
    let isWatched: Bool
    var onToggleWatch: ((String) -> Void)?

    var body: some View {
        DSPremiumHeroCard(
            drop: drop,
            layoutHeight: nil,
            useSharpRectangleBorder: false,
            innerClipCornerRadius: nil,
            isWatched: isWatched,
            onToggleWatch: onToggleWatch
        )
        .clipped()
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }
}

#Preview {
    ZStack {
        CreamEditorialTheme.canvas.ignoresSafeArea()
        HeroCardView(drop: .previewRare, isWatched: false, onToggleWatch: { _ in })
            .padding()
    }
}
