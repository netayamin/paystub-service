import SwiftUI

struct DateStripView: View {
    let dateOptions: [(dateStr: String, dayName: String, dayNum: String)]
    @Binding var selectedDates: Set<String>
    
    private var allSelected: Bool { selectedDates.isEmpty }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // "All" pill
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDates.removeAll()
                        }
                    } label: {
                        Text("All")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(allSelected ? .white : AppTheme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(allSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    ForEach(dateOptions, id: \.dateStr) { opt in
                        let isSelected = selectedDates.contains(opt.dateStr)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isSelected {
                                    selectedDates.remove(opt.dateStr)
                                } else {
                                    selectedDates = [opt.dateStr]
                                }
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(opt.dayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(isSelected ? .white.opacity(0.8) : AppTheme.textTertiary)
                                Text(opt.dayNum)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(isSelected ? .white : AppTheme.textPrimary)
                                Spacer().frame(height: 5)
                            }
                            .frame(width: 48)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                            .cornerRadius(14)
                        }
                        .buttonStyle(.plain)
                        .id(opt.dateStr)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        DateStripView(
            dateOptions: [
                ("2026-03-04", "Today", "4"),
                ("2026-03-05", "Tmrw", "5"),
                ("2026-03-06", "Thu", "6"),
                ("2026-03-07", "Fri", "7"),
                ("2026-03-08", "Sat", "8"),
            ],
            selectedDates: .constant(Set(["2026-03-04"]))
        )
    }
}
