import SwiftUI

/// Horizontal scrolling date-pill strip with availability dots and ScaleButtonStyle bounce.
struct DateStripView: View {
    let dateOptions: [(dateStr: String, dayName: String, dayNum: String)]
    @Binding var selectedDates: Set<String>
    var calendarCounts: CalendarCounts

    private var allSelected: Bool { selectedDates.isEmpty }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // "All" pill
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
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
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("All dates")

                    ForEach(dateOptions, id: \.dateStr) { opt in
                        let isSelected = selectedDates.contains(opt.dateStr)
                        let count = calendarCounts.byDate[opt.dateStr] ?? 0

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
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
                                // Availability dot
                                if count > 0 {
                                    Circle()
                                        .fill(isSelected ? Color.white : AppTheme.accentRed)
                                        .frame(width: 5, height: 5)
                                } else {
                                    Spacer().frame(height: 5)
                                }
                            }
                            .frame(width: 48)
                            .padding(.vertical, 8)
                            .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                            .cornerRadius(14)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .id(opt.dateStr)
                        .accessibilityLabel("\(opt.dayName) \(opt.dayNum)\(count > 0 ? ", \(count) available" : "")")
                    }
                }
                .padding(.horizontal, AppTheme.spacingLG)
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
                ("2026-03-18", "Today", "18"),
                ("2026-03-19", "Tmrw",  "19"),
                ("2026-03-20", "Fri",   "20"),
                ("2026-03-21", "Sat",   "21"),
                ("2026-03-22", "Sun",   "22"),
            ],
            selectedDates: .constant(Set(["2026-03-18"])),
            calendarCounts: CalendarCounts(
                byDate: ["2026-03-18": 12, "2026-03-19": 8, "2026-03-21": 3],
                dates: []
            )
        )
    }
}
