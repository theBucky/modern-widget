import Foundation

struct WalkHistoryMonth {
    let month: Date
    let dayCells: [DayCell]

    /// A grid slot identified by its content: a real day keys off its calendar day, a
    /// leading blank off its position, so ForEach never falls back to collection indices.
    enum DayCell: Identifiable, Hashable {
        case day(LocalDay)
        case blank(position: Int)

        var id: Self { self }

        var day: LocalDay? {
            guard case let .day(day) = self else { return nil }
            return day
        }
    }

    init(containing date: Date, calendar: Calendar = LocalDay.calendar) {
        let firstDay = calendar.startOfMonth(for: date)
        let components = calendar.dateComponents([.year, .month], from: firstDay)
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay)!.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let filledCells = leadingBlanks + dayCount

        month = firstDay
        dayCells = (0..<filledCells).map { cellIndex in
            let dayOffset = cellIndex - leadingBlanks
            guard (0..<dayCount).contains(dayOffset) else {
                return .blank(position: cellIndex)
            }
            return .day(
                LocalDay(year: components.year!, month: components.month!, day: dayOffset + 1)!
            )
        }
    }

    /// Weekday column headers identified by their Gregorian weekday number, stable
    /// regardless of `firstWeekday` ordering and immune to duplicate symbols.
    struct WeekdayLabel: Identifiable {
        let id: Int
        let symbol: String
        let name: String
    }

    static func weekdayLabels(calendar: Calendar = LocalDay.calendar) -> [WeekdayLabel] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let names = calendar.standaloneWeekdaySymbols
        return (0..<7).map { column in
            let weekday = (calendar.firstWeekday - 1 + column) % 7
            return WeekdayLabel(
                id: weekday + 1,
                symbol: symbols[weekday],
                name: names[weekday]
            )
        }
    }
}
