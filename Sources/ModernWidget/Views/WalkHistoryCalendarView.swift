import SwiftUI

struct WalkHistoryCalendarView: View {
    @State private var visibleMonth = HistoryRetention.currentMonth()

    var body: some View {
        // Rebuilt per evaluation on purpose: caching the grid desyncs it from the
        // weekday header when the system locale or first weekday changes.
        let month = WalkHistoryMonth(containing: visibleMonth)

        VStack(spacing: PanelLayout.sectionSpacing) {
            MonthNavigationHeader(visibleMonth: $visibleMonth)
            WeekdayHeader()
            WalkDaysGrid(cells: month.dayCells)
        }
    }
}

private enum CalendarLayout {
    static let cellSpacing: CGFloat = 3
    static let cellHeight: CGFloat = 40
    static let columns = Array(
        repeating: GridItem(.flexible(), spacing: cellSpacing),
        count: 7
    )
}

private struct MonthNavigationHeader: View {
    @Binding var visibleMonth: Date

    private static let chevronButtonSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            stepButton("Previous month", systemImage: "chevron.left", delta: -1, enabled: canGoBack)

            Spacer()

            Text(visibleMonth, format: .dateTime.month(.wide).year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            stepButton("Next month", systemImage: "chevron.right", delta: 1, enabled: canGoForward)
        }
    }

    private func stepButton(
        _ label: LocalizedStringKey, systemImage: String, delta: Int, enabled: Bool
    ) -> some View {
        Button {
            visibleMonth = LocalDay.calendar.date(byAdding: .month, value: delta, to: visibleMonth)!
        } label: {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .frame(width: Self.chevronButtonSize, height: Self.chevronButtonSize)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private var canGoBack: Bool {
        visibleMonth > HistoryRetention.earliestMonth()
    }

    private var canGoForward: Bool {
        visibleMonth < HistoryRetention.currentMonth()
    }
}

private struct WeekdayHeader: View {
    var body: some View {
        HStack(spacing: CalendarLayout.cellSpacing) {
            ForEach(WalkHistoryMonth.weekdayLabels()) { weekday in
                Text(weekday.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct WalkDaysGrid: View {
    let cells: [WalkHistoryMonth.DayCell]

    @Environment(WalkHistoryStore.self) private var walkHistoryStore
    @Environment(DailySupplementStore.self) private var dailySupplementStore

    var body: some View {
        let today = LocalDay(date: .now)

        LazyVGrid(columns: CalendarLayout.columns, spacing: CalendarLayout.cellSpacing) {
            ForEach(cells) { cell in
                // Single-root row: a top-level if/else would make the ForEach row shape
                // vary per element, forcing id computation to evaluate every row body.
                ZStack {
                    if let day = cell.day {
                        let count = walkHistoryStore.walkCount(on: day)
                        WalkDayCell(
                            day: day,
                            count: count,
                            display: WalkHistoryDayDisplay(
                                day: day,
                                today: today,
                                walkCount: count,
                                isSupplementTaken: dailySupplementStore.isTaken(on: day)
                            )
                        )
                    } else {
                        Color.clear.frame(height: CalendarLayout.cellHeight)
                    }
                }
            }
        }
    }
}

private struct WalkDayCell: View {
    let day: LocalDay
    let count: Int
    let display: WalkHistoryDayDisplay

    var body: some View {
        VStack(spacing: 1) {
            Text(day.day, format: .number)
                .font(.system(size: 9, weight: .regular).monospacedDigit())
                .foregroundStyle(labelColor)

            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .opacity(count > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CalendarLayout.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: PanelLayout.cornerRadius, style: .continuous)
                .fill(fill)
        )
    }

    private var labelColor: Color {
        switch display.label {
        case .future:
            return .secondary.opacity(0.5)
        case .supplementTaken:
            return PanelColor.statusGreen
        case .supplementPending:
            return PanelColor.statusOrange
        }
    }

    private var fill: Color {
        switch display.fill {
        case .today:
            return Color.accentColor.opacity(0.15)
        case .walked:
            return Color.primary.opacity(0.05)
        case .empty:
            return .clear
        }
    }
}
