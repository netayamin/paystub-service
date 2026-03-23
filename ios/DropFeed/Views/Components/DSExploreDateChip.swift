import SwiftUI

/// Single day column: weekday above date; maroon when selected (Explore calendar strip).
struct DSExploreDateChip: View {
    let weekday: String
    let dayNumber: String
    let isSelected: Bool
    let action: () -> Void

    private var muted: Color { CreamEditorialTheme.textTertiary }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(weekday)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isSelected ? CreamEditorialTheme.burgundy : muted)
                    .tracking(0.45)
                    .textCase(.uppercase)
                Text(dayNumber)
                    .font(.system(size: isSelected ? 18 : 15, weight: isSelected ? .heavy : .semibold))
                    .foregroundColor(isSelected ? CreamEditorialTheme.burgundy : CreamEditorialTheme.textSecondary)
            }
            .frame(minWidth: 40)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        DSExploreDateChip(weekday: "MON", dayNumber: "14", isSelected: false, action: {})
        DSExploreDateChip(weekday: "TUE", dayNumber: "15", isSelected: true, action: {})
    }
    .padding()
    .background(CreamEditorialTheme.canvas)
}
