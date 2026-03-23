import SwiftUI

/// Left title (bold) + right trailing caption — used for Explore “Availability” + month/year.
struct DSSectionTitleRow: View {
    let title: String
    let trailing: String
    var titleSize: CGFloat = 16
    var trailingSize: CGFloat = 10

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundColor(CreamEditorialTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(trailing)
                .font(.system(size: trailingSize, weight: .semibold))
                .foregroundColor(CreamEditorialTheme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.55)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DSSectionTitleRow(title: "Availability", trailing: "OCTOBER 2024")
        .padding()
        .background(CreamEditorialTheme.canvas)
}
