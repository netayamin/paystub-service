import SwiftUI

/// Sheet for date and time filter selection — keeps the main feed uncluttered.
struct DateTimeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: FeedViewModel
    
    private static let timeOptions: [(key: String, label: String)] = [
        ("all", "All"),
        ("lunch", "Lunch"),
        ("3pm", "Afternoon"),
        ("7pm", "Early dinner"),
        ("evening79", "7–9 PM"),
        ("dinner", "Late dinner"),
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    dateSection
                    timeSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(AppTheme.background)
            .navigationTitle("When")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await vm.refresh() }
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
                }
            }
        }
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
            
            FlowLayout(spacing: 8) {
                Button {
                    vm.selectedDates = []
                } label: {
                    Text("All dates")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(vm.selectedDates.isEmpty ? .white : AppTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(vm.selectedDates.isEmpty ? AppTheme.pillSelected : AppTheme.pillUnselected)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                ForEach(vm.dateOptions, id: \.dateStr) { opt in
                    dateChip(opt.dateStr, dayLabel: opt.dayName, monthDay: opt.dayNum)
                }
            }
        }
    }
    
    private func dateChip(_ dateStr: String, dayLabel: String, monthDay: String) -> some View {
        let isSelected = vm.selectedDates.contains(dateStr)
        return Button {
            vm.selectedDates = [dateStr]
        } label: {
            Text("\(dayLabel) \(monthDay)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .textCase(.uppercase)
            
            FlowLayout(spacing: 8) {
                ForEach(Self.timeOptions, id: \.key) { opt in
                    timeChip(opt.key, label: opt.label)
                }
            }
        }
    }
    
    private func timeChip(_ key: String, label: String) -> some View {
        let isSelected = vm.selectedTimeFilter == key
        return Button {
            vm.selectedTimeFilter = key
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? AppTheme.pillSelected : AppTheme.pillUnselected)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
}

/// Simple wrapping layout for filter chips (date/time).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? 400
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

#Preview("Filter sheet") {
    DateTimeFilterSheet(vm: FeedViewModel())
}
