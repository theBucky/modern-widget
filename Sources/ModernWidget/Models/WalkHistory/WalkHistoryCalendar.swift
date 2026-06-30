import Foundation

struct WalkHistoryMonth {
    let month: Date
    let dayCells: [DayCell]

    /// A grid slot carrying its own identity: a real day keys off its date, a
    /// leading blank keys off its position, so ForEach never falls back to indices.
    struct DayCell: Identifiable {
        let id: String
        let date: Date?
    }

    init(containing date: Date, calendar: Calendar = .current) {
        let firstDay = calendar.startOfMonth(for: date)
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay)!.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let filledCells = leadingBlanks + dayCount

        month = firstDay
        dayCells = (0..<filledCells).map { cellIndex in
            let dayOffset = cellIndex - leadingBlanks
            guard (0..<dayCount).contains(dayOffset) else {
                return DayCell(id: "blank-\(cellIndex)", date: nil)
            }
            let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay)!
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            return DayCell(
                id: "\(components.year!)-\(components.month!)-\(components.day!)",
                date: day
            )
        }
    }

    /// Weekday column headers identified by their Gregorian weekday number, stable
    /// regardless of `firstWeekday` ordering and immune to duplicate symbols.
    struct WeekdayLabel: Identifiable {
        let id: Int
        let symbol: String
    }

    static func weekdayLabels(calendar: Calendar = .current) -> [WeekdayLabel] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { column in
            let weekday = (calendar.firstWeekday - 1 + column) % 7
            return WeekdayLabel(id: weekday + 1, symbol: symbols[weekday])
        }
    }
}
