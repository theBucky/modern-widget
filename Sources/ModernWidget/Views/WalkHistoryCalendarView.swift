import SwiftUI

struct WalkHistoryCalendarView: View {
    let historyStore: WalkHistoryStore
    let supplementStore: DailySupplementStore
    @State private var monthGrid = WalkHistoryMonth(containing: .now)

    private enum Layout {
        static let sectionSpacing: CGFloat = 10
        static let cellSpacing: CGFloat = 3
        static let cellHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 5
        static let chevronSize: CGFloat = 22
        static let columns = Array(
            repeating: GridItem(.flexible(), spacing: cellSpacing),
            count: 7
        )
    }

    private enum Palette {
        static let supplementTaken = Color(red: 0, green: 0.45, blue: 0.12)
        static let supplementMissed = Color(red: 0.75, green: 0, blue: 0)
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
            Text(monthGrid.month, format: .dateTime.month(.wide).year())
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
        let symbols = WalkHistoryMonth.weekdaySymbols()

        return HStack(spacing: Layout.cellSpacing) {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index])
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        LazyVGrid(columns: Layout.columns, spacing: Layout.cellSpacing) {
            ForEach(monthGrid.dayCells.indices, id: \.self) { index in
                if let date = monthGrid.dayCells[index] {
                    dayCell(for: date, count: historyStore.walkCountsByDay[date] ?? 0)
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

            dayLabel(date)
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
    private func dayLabel(_ date: Date) -> some View {
        let calendar = Calendar.current
        let text = Text(date, format: .dateTime.day())
            .font(.system(size: 8, weight: .regular).monospacedDigit())

        if calendar.startOfDay(for: date) > calendar.startOfDay(for: .now) {
            text.foregroundStyle(.tertiary)
        } else if supplementStore.isTaken(on: date) {
            text.foregroundStyle(Palette.supplementTaken)
        } else {
            text.foregroundStyle(Palette.supplementMissed)
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
        monthGrid.month > HistoryRetention.earliestMonth()
    }

    private var canGoForward: Bool {
        monthGrid.month < Calendar.current.startOfMonth(for: .now)
    }

    private func shiftMonth(by delta: Int) {
        let month = Calendar.current.date(byAdding: .month, value: delta, to: monthGrid.month)!
        monthGrid = WalkHistoryMonth(containing: month)
    }
}
