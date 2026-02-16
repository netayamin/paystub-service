import SwiftUI

struct InitialSearchView: View {
    @State private var selectedDate: String = ""
    @State private var selectedTimeFilter: String = "all"
    @State private var selectedPartySizes: Set<Int> = [2, 4]
    
    var onSearch: (SearchParams) -> Void
    
    private let dateOptions: [String] = {
        let cal = Calendar.current
        let today = Date()
        return (0..<14).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { return nil }
            let y = cal.component(.year, from: d)
            let m = cal.component(.month, from: d)
            let day = cal.component(.day, from: d)
            return String(format: "%04d-%02d-%02d", y, m, day)
        }
    }()
    
    private let timeOptions: [(key: String, label: String)] = [
        ("all", "All times"),
        ("lunch", "Lunch"),
        ("3pm", "Afternoon"),
        ("7pm", "Early dinner"),
        ("dinner", "Late dinner"),
    ]
    
    private let partySizeOptions = [2, 4, 6]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                dateSection
                timeSection
                partySizeSection
                searchButton
            }
            .padding(20)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if selectedDate.isEmpty, let first = dateOptions.first {
                selectedDate = first
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When & who?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
            Text("Pick a date, time, and party size to see available drops.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(dateOptions, id: \.self) { dateStr in
                        dateChip(dateStr)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func dateChip(_ dateStr: String) -> some View {
        let isSelected = selectedDate == dateStr
        let (dayLabel, monthDay) = formatDate(dateStr)
        return Button {
            selectedDate = dateStr
        } label: {
            Text("\(dayLabel) \(monthDay)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? Color.black : Color(.secondarySystemFill))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(timeOptions, id: \.key) { option in
                        timeChip(option.key, label: option.label)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func timeChip(_ key: String, label: String) -> some View {
        let isSelected = selectedTimeFilter == key
        return Button {
            selectedTimeFilter = key
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? Color.black : Color(.secondarySystemFill))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private var partySizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Party size")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                ForEach(partySizeOptions, id: \.self) { size in
                    partySizeChip(size)
                }
            }
        }
    }
    
    private func partySizeChip(_ size: Int) -> some View {
        let isSelected = selectedPartySizes.contains(size)
        return Button {
            if selectedPartySizes.contains(size) {
                if selectedPartySizes.count > 1 {
                    selectedPartySizes.remove(size)
                }
            } else {
                selectedPartySizes.insert(size)
            }
        } label: {
            Text("\(size) people")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? Color.black : Color(.secondarySystemFill))
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private var searchButton: some View {
        Button {
            let params = SearchParams(
                date: selectedDate,
                timeFilter: selectedTimeFilter,
                partySizes: Array(selectedPartySizes).sorted()
            )
            onSearch(params)
        } label: {
            HStack {
                Text("Show drops")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.black)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
    
    private func formatDate(_ dateStr: String) -> (day: String, monthDay: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let d = formatter.date(from: dateStr) else { return ("", dateStr) }
        let cal = Calendar.current
        let day: String = {
            let weekday = cal.component(.weekday, from: d)
            let symbols = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            return weekday >= 1 && weekday <= 7 ? symbols[weekday] : ""
        }()
        let month = cal.shortMonthSymbols[cal.component(.month, from: d) - 1]
        let dayNum = cal.component(.day, from: d)
        return (day, "\(month) \(dayNum)")
    }
}

#Preview {
    InitialSearchView { _ in }
}
