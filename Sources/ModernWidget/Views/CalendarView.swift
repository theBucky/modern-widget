import SwiftUI

struct CalendarView: View {
    @ObservedObject var historyStore: WalkHistoryStore
    @State private var displayedMonth: Date = CalendarView.startOfMonth(.now)

    private enum Layout {
        static let sectionSpacing: CGFloat = 10
        static let cellSpacing: CGFloat = 3
        static let cellHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 5
        static let chevronSize: CGFloat = 22
    }

    var body: some View {
        VStack(spacing: Layout.sectionSpacing) {
            monthHeader
            weekdayHeader
            daysGrid
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 0) {
            chevron(systemImage: "chevron.left", delta: -1, disabled: !canGoBack)
            Spacer()
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            chevron(systemImage: "chevron.right", delta: 1, disabled: !canGoForward)
        }
    }

    private func chevron(systemImage: String, delta: Int, disabled: Bool) -> some View {
        Button {
            shiftMonth(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: Layout.chevronSize, height: Layout.chevronSize)
                .foregroundStyle(.secondary)
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
    }

    private var weekdayHeader: some View {
        HStack(spacing: Layout.cellSpacing) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        let counts = historyStore.walkCountsByDay()
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Layout.cellSpacing),
            count: 7
        )
        let cells = dayCells
        return LazyVGrid(columns: columns, spacing: Layout.cellSpacing) {
            ForEach(cells.indices, id: \.self) { index in
                if let date = cells[index] {
                    dayCell(for: date, count: counts[date] ?? 0)
                } else {
                    Color.clear.frame(height: Layout.cellHeight)
                }
            }
        }
    }

    private func dayCell(for date: Date, count: Int) -> some View {
        let today = Calendar.current.isDateInToday(date)

        return ZStack {
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 8)
            }

            dayLabel(date: date, today: today)
                .padding(.top, 4)
                .padding(.trailing, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: Layout.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(cellFill(today: today, hasWalks: count > 0))
        )
    }

    @ViewBuilder
    private func dayLabel(date: Date, today: Bool) -> some View {
        let text = Text(date, format: .dateTime.day())
            .font(.system(size: 8, weight: .regular).monospacedDigit())
        if today {
            text.foregroundStyle(Color.accentColor)
        } else {
            text.foregroundStyle(.tertiary)
        }
    }

    private func cellFill(today: Bool, hasWalks: Bool) -> Color {
        if today {
            return Color.accentColor.opacity(0.15)
        }
        if hasWalks {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }

    private var canGoBack: Bool {
        displayedMonth > WalkHistoryStore.earliestRetainedMonth()
    }

    private var canGoForward: Bool {
        displayedMonth < Self.startOfMonth(.now)
    }

    private func shiftMonth(by delta: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth)!
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    private var dayCells: [Date?] {
        let calendar = Calendar.current
        let firstDay = calendar.dateInterval(of: .month, for: displayedMonth)!.start
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay)!.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        let leading: [Date?] = Array(repeating: nil, count: leadingBlanks)
        let days: [Date?] = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: firstDay)
        }
        let trailing: [Date?] = Array(
            repeating: nil,
            count: (7 - (leading.count + days.count) % 7) % 7
        )
        return leading + days + trailing
    }

    private static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)!.start
    }
}
