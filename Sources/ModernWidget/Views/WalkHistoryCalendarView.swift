import SwiftUI

struct WalkHistoryCalendarView: View {
    let historyStore: WalkHistoryStore
    let supplementStore: DailySupplementStore
    @State private var visibleMonth = Calendar.current.startOfMonth(for: .now)

    private enum Layout {
        static let cellSpacing: CGFloat = 3
        static let cellHeight: CGFloat = 44
        static let chevronButtonSize: CGFloat = 22
        static let columns = Array(
            repeating: GridItem(.flexible(), spacing: cellSpacing),
            count: 7
        )
    }

    var body: some View {
        VStack(spacing: PanelLayout.sectionSpacing) {
            monthHeader
            weekdayHeader
            daysGrid
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 0) {
            monthStepButton(
                "Previous month", systemImage: "chevron.left", delta: -1, enabled: canGoBack)

            Spacer()

            Text(monthGrid.month, format: .dateTime.month(.wide).year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            monthStepButton(
                "Next month", systemImage: "chevron.right", delta: 1, enabled: canGoForward)
        }
    }

    private func monthStepButton(
        _ label: String, systemImage: String, delta: Int, enabled: Bool
    ) -> some View {
        Button {
            shiftMonth(by: delta)
        } label: {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .frame(width: Layout.chevronButtonSize, height: Layout.chevronButtonSize)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var weekdayHeader: some View {
        HStack(spacing: Layout.cellSpacing) {
            ForEach(WalkHistoryMonth.weekdayLabels()) { weekday in
                Text(weekday.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        LazyVGrid(columns: Layout.columns, spacing: Layout.cellSpacing) {
            ForEach(monthGrid.dayCells) { cell in
                if let date = cell.date {
                    dayCell(for: date, count: historyStore.walkCount(on: date))
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

            Text(date, format: .dateTime.day())
                .font(.system(size: 8, weight: .regular).monospacedDigit())
                .foregroundStyle(dayLabelColor(for: date))
                .padding(.top, 4)
                .padding(.trailing, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: Layout.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: PanelLayout.cornerRadius, style: .continuous)
                .fill(cellFill(today: today, hasWalks: count > 0))
        )
    }

    private func dayLabelColor(for date: Date) -> Color {
        let calendar = Calendar.current

        if calendar.startOfDay(for: date) > calendar.startOfDay(for: .now) {
            return .secondary.opacity(0.5)
        }
        if supplementStore.isTaken(on: date) {
            return PanelColor.statusGreen
        }
        return PanelColor.statusOrange
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
        visibleMonth = Calendar.current.date(byAdding: .month, value: delta, to: visibleMonth)!
    }

    private var monthGrid: WalkHistoryMonth {
        WalkHistoryMonth(containing: visibleMonth)
    }
}
