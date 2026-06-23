import Foundation

struct WalkHistoryMonth {
    let month: Date
    let dayCells: [Date?]

    init(containing date: Date, calendar: Calendar = .current) {
        let firstDay = calendar.startOfMonth(for: date)
        let dayCount = calendar.range(of: .day, in: .month, for: firstDay)!.count
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let filledCells = leadingBlanks + dayCount

        month = firstDay
        dayCells = (0..<filledCells).map { cellIndex in
            let dayOffset = cellIndex - leadingBlanks
            guard (0..<dayCount).contains(dayOffset) else { return nil }
            return calendar.date(byAdding: .day, value: dayOffset, to: firstDay)!
        }
    }

    static func weekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }
}
