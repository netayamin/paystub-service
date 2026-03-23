import SwiftUI

/// Full-width (or inset) 1pt rule using editorial hairline color.
struct DSHairline: View {
    var horizontalPadding: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(CreamEditorialTheme.hairline)
            .frame(height: 1)
            .padding(.horizontal, horizontalPadding)
    }
}

#Preview {
    DSHairline(horizontalPadding: 16)
        .padding(.vertical, 8)
        .background(CreamEditorialTheme.canvas)
}
