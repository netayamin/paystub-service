import SwiftUI

/// Left label + expanding hairline + right accent label (Explore “LIVE INVENTORY” row).
struct DSLabeledRuleRow: View {
    let leadingLabel: String
    let trailingLabel: String
    var leadingColor: Color = CreamEditorialTheme.textSecondary
    var trailingColor: Color = CreamEditorialTheme.burgundy

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(leadingLabel)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(leadingColor)
                .tracking(0.95)
                .textCase(.uppercase)
                .lineLimit(1)
            Rectangle()
                .fill(CreamEditorialTheme.hairline)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            Text(trailingLabel)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(trailingColor)
                .tracking(0.5)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DSLabeledRuleRow(leadingLabel: "LIVE INVENTORY", trailingLabel: "NEW YORK")
        .padding()
        .background(CreamEditorialTheme.canvas)
}
